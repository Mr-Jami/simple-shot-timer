#!/usr/bin/env python3
"""Put the product page header and the search result image on an App Store version.

App Store Connect keeps these "creative assets" in the app's asset library
(App Store Connect API, "App Asset Library"): an image is uploaded once, then
a *placement* puts it on one surface, here each language of the version that
is being prepared. The placements go through App Review with that version.

    app_store_creative_assets.py --bundle-id cc.example.app --version 2.5.0 \
        --header header-3840x1646.png --search search-3840x2560.png

What it does, for each image:

1. Reads Apple's reference data to find the image specification the file
   matches and the placement groups that take it (nothing is hard-coded but
   the two placement types).
2. Uploads the file to the library, unless a file with the same name and
   size is already there.
3. Places it on every language of the version, replacing a different image
   that sits in the same slot. A slot that already shows this image is left
   alone, so the script can be run again.

--dry-run only reads: it prints the version, the specifications and what
would be uploaded and placed.

The API key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY
(the contents of the .p8). The token is signed with the openssl command, so
no Python packages are needed.
"""

import argparse
import base64
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
HEADER = "PRODUCT_PAGE_HEADER_ASSET"
SEARCH = "APP_STORE_SEARCH_RESULTS_ASSET"
CATEGORY = "CREATIVE_ASSETS"
FEATURE = "APP_STORE_VERSIONS"
# States of a library image that can still be placed.
USABLE = {
    "UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW",
    "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED",
}


class ApiError(Exception):
    def __init__(self, method, url, status, body):
        super().__init__(f"{method} {url} -> {status}\n{body}")
        self.status = status
        self.body = body


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw(der):
    """ECDSA signature: DER SEQUENCE of two INTEGERs -> r || s, 32 bytes each."""
    assert der[0] == 0x30, "not a DER sequence"
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert der[i] == 0x02, "not a DER integer"
        n = der[i + 1]
        parts.append(int.from_bytes(der[i + 2:i + 2 + n], "big"))
        i += 2 + n
    return b"".join(p.to_bytes(32, "big") for p in parts)


def make_token(key_id, issuer_id, key_pem, now=None):
    """An ES256 JSON Web Token for the App Store Connect API, good for 15 minutes."""
    now = int(now if now is not None else time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer_id, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = b".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims))
    fd, path = tempfile.mkstemp(suffix=".p8")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(key_pem.strip() + "\n")
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", path],
            input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.remove(path)
    return (signing_input + b"." + b64url(der_to_raw(der))).decode()


class Client:
    def __init__(self, key_id, issuer_id, key_pem):
        self._creds = (key_id, issuer_id, key_pem)
        self._token = None
        self._token_time = 0

    def _auth(self):
        if self._token is None or time.time() - self._token_time > 600:
            self._token = make_token(*self._creds)
            self._token_time = time.time()
        return "Bearer " + self._token

    def request(self, method, path, body=None, params=None):
        url = path if path.startswith("http") else API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", self._auth())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            raise ApiError(method, url, e.code, e.read().decode("utf-8", "replace")) from None
        return json.loads(raw) if raw else None

    def get(self, path, **params):
        return self.request("GET", path, params=params)

    def get_all(self, path, **params):
        """Every page of a collection."""
        page = self.get(path, **params)
        items = list(page["data"])
        while page.get("links", {}).get("next"):
            page = self.request("GET", page["links"]["next"])
            items += page["data"]
        return items


def image_size(path):
    """(width, height) of a PNG or JPEG, and whether a PNG has an alpha channel."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        width, height, _, colour_type = struct.unpack(">IIBB", data[16:26])
        return width, height, colour_type in (4, 6)
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data):
            marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return width, height, False
            i += 2 + length
    raise SystemExit(f"{path}: not a PNG or JPEG")


def matching_spec(image_specs, path, placement_type):
    """The image specification a file fits for a placement type, or None."""
    width, height, alpha = image_size(path)
    size = os.path.getsize(path)
    ext = os.path.splitext(path)[1].lower()
    for spec in image_specs:
        d = spec.get("dimensions") or {}
        if placement_type not in (spec.get("compatiblePlacementTypes") or []):
            continue
        if not (d.get("minWidth", 0) <= width <= d.get("maxWidth", 0)
                and d.get("minHeight", 0) <= height <= d.get("maxHeight", 0)):
            continue
        if ext not in (spec.get("fileExtensions") or [ext]):
            continue
        if alpha and not spec.get("alphaAllowed"):
            continue
        if size > spec.get("maxFileSize", size):
            continue
        return spec
    return None


def placement_groups(ref, placement_type, spec_id):
    """Placement groups of an App Store version that take this specification."""
    allowed = None
    for feature in ref.get("features") or []:
        if feature.get("featureId") != FEATURE:
            continue
        for policy in feature.get("placementPolicies") or []:
            if policy.get("placementType") == placement_type:
                allowed = {g for limit in policy.get("groupLimits") or []
                           for g in limit.get("groupIds") or []}
    groups = []
    for entry in ref.get("placementTypes") or []:
        if entry.get("placementTypeId") != placement_type:
            continue
        for mapping in entry.get("specMappings") or []:
            group = mapping.get("placementGroupId")
            if spec_id in (mapping.get("specs") or []) and (allowed is None or group in allowed):
                groups.append(group)
    return groups


def describe_specs(ref, placement_type):
    """Lines that say what Apple accepts for a placement type."""
    by_id = {s.get("specId"): s for s in ref.get("imageSpecs") or []}
    lines = []
    for entry in ref.get("placementTypes") or []:
        if entry.get("placementTypeId") != placement_type:
            continue
        lines.append(f"  accepts categories: {entry.get('acceptsAssetCategories')}")
        for mapping in entry.get("specMappings") or []:
            names = []
            for spec_id in mapping.get("specs") or []:
                s = by_id.get(spec_id)
                if s:
                    d = s.get("dimensions") or {}
                    names.append(f"{s.get('shortName')} {d.get('minWidth')}-{d.get('maxWidth')}"
                                 f"x{d.get('minHeight')}-{d.get('maxHeight')}"
                                 f"{' universal' if s.get('universalAsset') else ''}")
            lines.append(f"  group {mapping.get('placementGroupId')}: "
                         + (", ".join(names) or "(video only)"))
    for feature in ref.get("features") or []:
        if feature.get("featureId") != FEATURE:
            continue
        for policy in feature.get("placementPolicies") or []:
            if policy.get("placementType") == placement_type:
                lines.append(f"  limits on a version: {json.dumps(policy.get('groupLimits'))}")
    return lines or ["  (not in the reference data)"]


def upload_image(client, library_id, path, reference_name, existing):
    """Id of the library image for a file, uploading it if it isn't there yet."""
    name, size = os.path.basename(path), os.path.getsize(path)
    for image in existing:
        a = image["attributes"]
        if a.get("fileName") == name and a.get("fileSize") == size:
            if a.get("state") in USABLE:
                print(f"  already in the library: {image['id']} ({a.get('state')})")
                return image["id"]
            if a.get("state") in ("AWAITING_UPLOAD", "FAILED"):
                print(f"  removing a leftover reservation {image['id']} ({a.get('state')})")
                client.request("DELETE", f"/v1/appAssetLibraryImages/{image['id']}")
    reserved = client.request("POST", "/v1/appAssetLibraryImages", {"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"fileName": name, "fileSize": size, "category": CATEGORY,
                       "referenceName": reference_name},
        "relationships": {"assetLibrary": {"data": {
            "type": "appAssetLibraries", "id": library_id}}},
    }})["data"]
    image_id = reserved["id"]
    with open(path, "rb") as f:
        data = f.read()
    for op in reserved["attributes"]["uploadOperations"]:
        req = urllib.request.Request(
            op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"])
        for h in op.get("requestHeaders") or []:
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=300):
            pass
    client.request("PATCH", f"/v1/appAssetLibraryImages/{image_id}", {"data": {
        "type": "appAssetLibraryImages", "id": image_id, "attributes": {"uploaded": True}}})
    print(f"  uploaded as {image_id}")
    return image_id


def wait_processed(client, image_id, timeout=600):
    """Waits until App Store Connect has processed an image; returns its attributes."""
    deadline = time.time() + timeout
    while True:
        a = client.get(f"/v1/appAssetLibraryImages/{image_id}")["data"]["attributes"]
        if a.get("state") == "FAILED":
            raise SystemExit(f"Processing failed for {a.get('fileName')}: {a.get('stateDetails')}")
        if a.get("state") != "UPLOAD_COMPLETE" and a.get("state") in USABLE:
            return a
        if time.time() > deadline:
            raise SystemExit(f"{a.get('fileName')} is still {a.get('state')} after {timeout} s")
        time.sleep(5)


def place(client, localization, placement_type, group, image_id, dry_run):
    """Puts an image in one slot of one language. Returns what happened."""
    loc_id = localization["id"]
    current = client.request(
        "GET", f"/v1/appStoreVersionLocalizations/{loc_id}/placements",
        params={"filter[placementType]": placement_type, "filter[placementGroup]": group,
                "include": "image,video", "limit": 50})
    for placement in current["data"]:
        rel = (placement.get("relationships") or {}).get("image", {}).get("data")
        if rel and rel.get("id") == image_id:
            return "kept"
    if dry_run:
        return "would replace" if current["data"] else "would place"
    for placement in current["data"]:
        client.request("DELETE", f"/v1/appAssetLibraryPlacements/{placement['id']}")
    client.request("POST", "/v1/appAssetLibraryPlacements", {"data": {
        "type": "appAssetLibraryPlacements",
        "attributes": {"placementType": placement_type, "placementGroup": group},
        "relationships": {
            "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
            "appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": loc_id}},
        },
    }})
    return "replaced" if current["data"] else "placed"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--header", help="image for the product page header")
    parser.add_argument("--search", help="image for the search results")
    parser.add_argument("--dry-run", action="store_true", help="read only, change nothing")
    args = parser.parse_args()
    jobs = [(t, p) for t, p in ((HEADER, args.header), (SEARCH, args.search)) if p]
    if not jobs:
        parser.error("give --header, --search or both")

    try:
        client = Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY"])
    except KeyError as e:
        raise SystemExit(f"Missing environment variable {e}") from None

    apps = client.get("/v1/apps", **{"filter[bundleId]": args.bundle_id})["data"]
    if not apps:
        raise SystemExit(f"No app with bundle id {args.bundle_id}")
    app_id = apps[0]["id"]
    versions = client.get(f"/v1/apps/{app_id}/appStoreVersions", **{
        "filter[versionString]": args.version, "filter[platform]": "IOS"})["data"]
    if not versions:
        raise SystemExit(f"App Store Connect has no iOS version {args.version}")
    version = versions[0]
    state = version["attributes"].get("appVersionState") or version["attributes"].get("appStoreState")
    print(f"Version {args.version}: {state}")
    localizations = client.get_all(
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", limit=200)
    locales = sorted(l["attributes"]["locale"] for l in localizations)
    print(f"Languages: {', '.join(locales)}")

    library_id = client.get(f"/v1/apps/{app_id}/assetLibrary")["data"]["id"]
    ref = client.get("/v1/appAssetLibraryRefData")["data"]
    ref = (ref[0] if isinstance(ref, list) else ref)["attributes"]
    existing = client.get_all(
        f"/v1/appAssetLibraries/{library_id}/images", **{"filter[category]": CATEGORY, "limit": 200})
    print(f"Creative images in the library: {len(existing)}")
    for image in existing:
        a = image["attributes"]
        print(f"  {image['id']} {a.get('fileName')} {a.get('fileSize')} B {a.get('state')}")

    failed = False
    for placement_type, path in jobs:
        width, height, alpha = image_size(path)
        print(f"\n{placement_type}: {path} ({width}x{height}{', alpha' if alpha else ''}, "
              f"{os.path.getsize(path)} B)")
        if args.dry_run:
            print("\n".join(describe_specs(ref, placement_type)))
        spec = matching_spec(ref.get("imageSpecs") or [], path, placement_type)
        if not spec:
            print(f"::error title=App Store creative assets::{os.path.basename(path)} matches no "
                  f"image specification for {placement_type}")
            print("\n".join(describe_specs(ref, placement_type)))
            failed = True
            continue
        groups = placement_groups(ref, placement_type, spec["specId"])
        print(f"  specification {spec.get('shortName')}, placement groups: {groups}")
        if not groups:
            print(f"::error title=App Store creative assets::no placement group of an App Store "
                  f"version takes {spec.get('shortName')}")
            failed = True
            continue

        if args.dry_run:
            name, size = os.path.basename(path), os.path.getsize(path)
            image_id = next((i["id"] for i in existing
                             if i["attributes"].get("fileName") == name
                             and i["attributes"].get("fileSize") == size
                             and i["attributes"].get("state") in USABLE), None)
            print(f"  {'already in the library: ' + image_id if image_id else 'would upload'}")
        else:
            reference = f"{os.path.splitext(os.path.basename(path))[0]} ({args.version})"
            image_id = upload_image(client, library_id, path, reference, existing)
            processed = wait_processed(client, image_id)
            print(f"  processed: {processed.get('state')}, specification {processed.get('specId')}"
                  f"{'' if processed.get('specId') == spec['specId'] else ' (not the expected one)'}")

        for group in groups:
            results = {}
            for localization in localizations:
                locale = localization["attributes"]["locale"]
                if args.dry_run and not image_id:
                    outcome = "would place"
                else:
                    try:
                        outcome = place(client, localization, placement_type, group, image_id,
                                        args.dry_run)
                    except ApiError as e:
                        outcome = f"FAILED ({e.status})"
                        print(f"::error title=App Store creative assets::{placement_type} "
                              f"{group} {locale}: {e.body[:600]}")
                        failed = True
                results.setdefault(outcome, []).append(locale)
            for outcome, where in results.items():
                print(f"  {group}: {outcome} in {', '.join(sorted(where))}")

    if failed:
        raise SystemExit(1)
    print("\nNothing was changed (dry run)." if args.dry_run else
          "\nDone. The images go to App Review with the version.")


if __name__ == "__main__":
    try:
        main()
    except ApiError as e:
        print(f"::error title=App Store creative assets::{str(e)[:1500]}")
        sys.exit(1)
