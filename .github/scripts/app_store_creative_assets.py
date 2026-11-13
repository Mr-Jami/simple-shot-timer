#!/usr/bin/env python3
"""Put the product page header and the search result asset on an App Store version.

App Store Connect keeps these "creative assets" in the app's asset library
(App Store Connect API, "App Asset Library"): an image or a video is uploaded
once, then a *placement* puts it on one surface, here each language of the
version that is being prepared. The placements go through App Review with
that version.

    app_store_creative_assets.py --bundle-id cc.example.app --version 2.5.0 \
        --header header.mp4 --search search-3840x2560.png

Each of the two can be an image (PNG, JPEG) or a video (MP4, M4V, MOV); a
video loops on the App Store, and --preview-frame chooses its still picture.
What the script does, for each file:

1. Reads Apple's reference data to find the specification the file matches
   (size, and for a video frame rate and length) and the placement groups
   that take it (nothing is hard-coded but the two placement types).
2. Uploads the file to the library, unless a file with the same name and
   size is already there.
3. Places it on every language of the version, replacing a different asset
   that sits in the same slot. A slot that already shows this file is left
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
import re
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
VIDEO_EXTENSIONS = (".mp4", ".m4v", ".mov")
# States of a library asset that can still be placed.
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


def mp4_boxes(data, start, end):
    """The boxes of an MP4 / QuickTime file between two offsets: (type, body start, end)."""
    while start + 8 <= end:
        size, kind = struct.unpack(">I4s", data[start:start + 8])
        body = start + 8
        if size == 1:
            size = struct.unpack(">Q", data[body:body + 8])[0]
            body += 8
        elif size == 0:
            size = end - start
        if size < 8:
            return
        yield kind.decode("latin-1"), body, start + size
        start += size


def video_facts(path):
    """Width, height, frames per second, length in seconds and whether there is sound."""
    with open(path, "rb") as f:
        data = f.read()

    def find(kind, start, end):
        return [(a, b) for k, a, b in mp4_boxes(data, start, end) if k == kind]

    facts = {"audio": False}
    for moov in find("moov", 0, len(data)):
        for trak in find("trak", *moov):
            for mdia in find("mdia", *trak):
                handler = [data[a + 8:a + 12] for a, _ in find("hdlr", *mdia)]
                if handler and handler[0] == b"soun":
                    facts["audio"] = True
                if not handler or handler[0] != b"vide" or "width" in facts:
                    continue
                a, _ = find("tkhd", *trak)[0]
                # Width and height are the last two fields, as 16.16 fixed point.
                size = 92 if data[a] == 1 else 80
                width, height = struct.unpack(">II", data[a + size - 4:a + size + 4])
                facts["width"], facts["height"] = width >> 16, height >> 16
                a, _ = find("mdhd", *mdia)[0]
                if data[a] == 1:
                    timescale, duration = struct.unpack(">IQ", data[a + 20:a + 32])
                else:
                    timescale, duration = struct.unpack(">II", data[a + 12:a + 20])
                facts["seconds"] = duration / timescale
                frames = 0
                for minf in find("minf", *mdia):
                    for stbl in find("stbl", *minf):
                        for a, _ in find("stts", *stbl):
                            count = struct.unpack(">I", data[a + 4:a + 8])[0]
                            for i in range(count):
                                frames += struct.unpack(">I", data[a + 8 + 8 * i:a + 12 + 8 * i])[0]
                facts["fps"] = frames / facts["seconds"] if facts["seconds"] else 0
    if "width" not in facts:
        raise SystemExit(f"{path}: no video track found")
    return facts


def is_video(path):
    return os.path.splitext(path)[1].lower() in VIDEO_EXTENSIONS


def describe_file(path):
    if is_video(path):
        v = video_facts(path)
        return (f"{v['width']}x{v['height']}, {v['fps']:.2f} fps, {v['seconds']:.2f} s, "
                f"{'with' if v['audio'] else 'no'} sound")
    width, height, alpha = image_size(path)
    return f"{width}x{height}{', alpha' if alpha else ''}"


def iso_seconds(text):
    """Seconds of an ISO 8601 duration such as PT30S or PT1M30S."""
    m = re.fullmatch(r"PT(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?", text or "")
    return (int(m.group(1) or 0) * 60 + float(m.group(2) or 0)) if m else None


def matching_spec(ref, path, placement_type):
    """The image or video specification a file fits for a placement type, or None."""
    video = is_video(path)
    size = os.path.getsize(path)
    ext = os.path.splitext(path)[1].lower()
    if video:
        v = video_facts(path)
        width, height, alpha = v["width"], v["height"], False
    else:
        width, height, alpha = image_size(path)
    for spec in ref.get("videoSpecs" if video else "imageSpecs") or []:
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
        if video:
            rates = spec.get("frameRates") or []
            if rates and not any(r.get("minFps", 0) - 0.01 <= v["fps"] <= r.get("maxFps", 0) + 0.01
                                 for r in rates):
                continue
            low = iso_seconds((spec.get("duration") or {}).get("min"))
            high = iso_seconds((spec.get("duration") or {}).get("max"))
            if (low is not None and v["seconds"] < low) or (high is not None and v["seconds"] > high):
                continue
            if spec.get("audioRequired") and not v["audio"]:
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
    videos = {s.get("specId"): s for s in ref.get("videoSpecs") or []}
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
                         + (", ".join(names) or "(no image)"))
            for spec_id in mapping.get("specs") or []:
                v = videos.get(spec_id)
                if v:
                    lines.append("    video " + json.dumps({k: v.get(k) for k in (
                        "shortName", "dimensions", "frameRates", "duration", "audioRequired",
                        "fileExtensions", "maxFileSize", "universalAsset")}))
    for feature in ref.get("features") or []:
        if feature.get("featureId") != FEATURE:
            continue
        for policy in feature.get("placementPolicies") or []:
            if policy.get("placementType") == placement_type:
                lines.append(f"  limits on a version: {json.dumps(policy.get('groupLimits'))}")
    return lines or ["  (not in the reference data)"]


def resource(path):
    """The API's resource type for a file: library images or library videos."""
    return "appAssetLibraryVideos" if is_video(path) else "appAssetLibraryImages"


def upload_asset(client, library_id, path, reference_name, existing, preview_frame):
    """Id of the library asset for a file, uploading it if it isn't there yet."""
    kind = resource(path)
    name, size = os.path.basename(path), os.path.getsize(path)
    for asset in existing:
        a = asset["attributes"]
        if asset["type"] == kind and a.get("fileName") == name and a.get("fileSize") == size:
            if a.get("state") in USABLE:
                print(f"  already in the library: {asset['id']} ({a.get('state')})")
                return asset["id"]
            if a.get("state") in ("AWAITING_UPLOAD", "FAILED"):
                print(f"  removing a leftover reservation {asset['id']} ({a.get('state')})")
                client.request("DELETE", f"/v1/{kind}/{asset['id']}")
    attributes = {"fileName": name, "fileSize": size, "category": CATEGORY,
                  "referenceName": reference_name}
    if is_video(path) and preview_frame:
        attributes["previewFrameTimeCode"] = preview_frame
    reserved = client.request("POST", f"/v1/{kind}", {"data": {
        "type": kind,
        "attributes": attributes,
        "relationships": {"assetLibrary": {"data": {
            "type": "appAssetLibraries", "id": library_id}}},
    }})["data"]
    asset_id = reserved["id"]
    with open(path, "rb") as f:
        data = f.read()
    for op in reserved["attributes"]["uploadOperations"]:
        req = urllib.request.Request(
            op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"])
        for h in op.get("requestHeaders") or []:
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=600):
            pass
    client.request("PATCH", f"/v1/{kind}/{asset_id}", {"data": {
        "type": kind, "id": asset_id, "attributes": {"uploaded": True}}})
    print(f"  uploaded as {asset_id}")
    return asset_id


def wait_processed(client, kind, asset_id, timeout=900):
    """Waits until App Store Connect has processed an asset; returns its attributes."""
    deadline = time.time() + timeout
    while True:
        a = client.get(f"/v1/{kind}/{asset_id}")["data"]["attributes"]
        if a.get("state") == "FAILED":
            raise SystemExit(f"Processing failed for {a.get('fileName')}: {a.get('stateDetails')}")
        if a.get("state") != "UPLOAD_COMPLETE" and a.get("state") in USABLE:
            return a
        if time.time() > deadline:
            raise SystemExit(f"{a.get('fileName')} is still {a.get('state')} after {timeout} s")
        time.sleep(5)


def place(client, localization, placement_type, group, kind, asset_id, dry_run):
    """Puts a library asset in one slot of one language. Returns what happened."""
    loc_id = localization["id"]
    relationship = "video" if kind == "appAssetLibraryVideos" else "image"
    current = client.request(
        "GET", f"/v1/appStoreVersionLocalizations/{loc_id}/placements",
        params={"filter[placementType]": placement_type, "filter[placementGroup]": group,
                "include": "image,video", "limit": 50})
    for placement in current["data"]:
        rel = ((placement.get("relationships") or {}).get(relationship) or {}).get("data")
        if rel and rel.get("id") == asset_id:
            return "kept"
    if dry_run:
        return "would replace" if current["data"] else "would place"
    for placement in current["data"]:
        client.request("DELETE", f"/v1/appAssetLibraryPlacements/{placement['id']}")
    client.request("POST", "/v1/appAssetLibraryPlacements", {"data": {
        "type": "appAssetLibraryPlacements",
        "attributes": {"placementType": placement_type, "placementGroup": group},
        "relationships": {
            relationship: {"data": {"type": kind, "id": asset_id}},
            "appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": loc_id}},
        },
    }})
    return "replaced" if current["data"] else "placed"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--header", help="image or video for the product page header")
    parser.add_argument("--search", help="image or video for the search results")
    parser.add_argument("--preview-frame", default="00:00:01:00",
                        help="the still picture of a video, as HH:MM:SS:FF (default: after one second)")
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
    existing = []
    for what in ("images", "videos"):
        existing += client.get_all(
            f"/v1/appAssetLibraries/{library_id}/{what}",
            **{"filter[category]": CATEGORY, "limit": 200})
    print(f"Creative assets in the library: {len(existing)}")
    for asset in existing:
        a = asset["attributes"]
        print(f"  {asset['id']} {a.get('fileName')} {a.get('fileSize')} B {a.get('state')}")

    failed = False
    for placement_type, path in jobs:
        kind = resource(path)
        print(f"\n{placement_type}: {path} ({describe_file(path)}, {os.path.getsize(path)} B)")
        if args.dry_run:
            print("\n".join(describe_specs(ref, placement_type)))
        spec = matching_spec(ref, path, placement_type)
        if not spec:
            print(f"::error title=App Store creative assets::{os.path.basename(path)} matches no "
                  f"specification for {placement_type}")
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
            asset_id = next((i["id"] for i in existing
                             if i["type"] == kind
                             and i["attributes"].get("fileName") == name
                             and i["attributes"].get("fileSize") == size
                             and i["attributes"].get("state") in USABLE), None)
            print(f"  {'already in the library: ' + asset_id if asset_id else 'would upload'}")
        else:
            reference = f"{os.path.splitext(os.path.basename(path))[0]} ({args.version})"
            asset_id = upload_asset(client, library_id, path, reference, existing,
                                    args.preview_frame)
            processed = wait_processed(client, kind, asset_id)
            print(f"  processed: {processed.get('state')}, specification {processed.get('specId')}"
                  f"{'' if processed.get('specId') == spec['specId'] else ' (not the expected one)'}")

        for group in groups:
            results = {}
            for localization in localizations:
                locale = localization["attributes"]["locale"]
                if args.dry_run and not asset_id:
                    outcome = "would place"
                else:
                    try:
                        outcome = place(client, localization, placement_type, group, kind,
                                        asset_id, args.dry_run)
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
          "\nDone. The assets go to App Review with the version.")


if __name__ == "__main__":
    try:
        main()
    except ApiError as e:
        print(f"::error title=App Store creative assets::{str(e)[:1500]}")
        sys.exit(1)
