#!/usr/bin/env python3
"""Turn a release-please GitHub Release body into plain-text store notes.

The GitHub Release keeps the developer-facing changelog (links, commit
hashes, scopes). Store "What's new" fields don't render markdown and are
read by end users, so this keeps only the user-visible sections and
rewrites each entry as a short bullet:

    ### Features
    * **drills:** save, load and manage named custom drills ([#25](...)) ([83fcee8](...)), closes [#24](...)

becomes

    New:
    • Save, load and manage named custom drills

Reads the release body from stdin, writes the notes to stdout. Output is
capped at --max-chars (Play Store limit is 500 per locale), cutting at a
whole bullet rather than mid-sentence. When the result is the generic
fallback or entries had to be dropped, a GitHub Actions ::warning:: saying
why goes to stderr.
"""

import argparse
import re
import sys

FALLBACK = "Bug fixes and improvements."

# release-please section heading -> store heading, in output order.
# "Changed" carries the BREAKING CHANGE footer text, which is where
# release-please puts the explanation of what was removed or behaves
# differently; the Features/Bug Fixes entry for the same commit only has
# the subject line. Sections not listed here (Dependencies, Reverts,
# hidden types) are left out: they mean nothing to someone updating the app.
SECTIONS = {
    "breaking changes": "Changed",
    "features": "New",
    "bug fixes": "Fixes",
    "performance": "Improvements",
}

HEADING = re.compile(r"^#{1,6}\s+(.*)$")
BULLET = re.compile(r"^\s*[*-]\s+(.*)$")


def warn(message: str) -> None:
    print(f"::warning title=Play Store release notes::{message}", file=sys.stderr)


def section_for(heading: str) -> str | None:
    # "⚠ BREAKING CHANGES" -> "breaking changes"
    key = re.sub(r"^[^\w]+", "", heading).strip().lower()
    return SECTIONS.get(key)


def clean_entry(text: str) -> str:
    # ", closes #24" / ", closes [#24](...)" trailers
    text = re.sub(r",\s*closes\s+\[?#.*$", "", text, flags=re.IGNORECASE)
    # Trailing link groups only: ([#25](url)) ([83fcee8](url))
    text = re.sub(r"(\s*\(\[[^\]]*\]\([^)]*\)\))+$", "", text)
    # Leading scope: **drills:**
    text = re.sub(r"^\*\*[^*]+:\*\*\s*", "", text)
    # Any remaining markdown links -> their label
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Matched bold / inline-code pairs only, so mic_permission or 5*5 survive
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    text = re.sub(r"\s+", " ", text).strip().rstrip(".")
    return text[:1].upper() + text[1:]


def parse(body: str) -> tuple[list[tuple[str, list[str]]], bool]:
    """Returns (sections in output order, whether any section heading was seen).

    The version line (## [1.7.0](...)) doesn't count as a section heading.
    """
    raw: dict[str, list[str]] = {}
    current = None
    saw_section = False
    for line in body.splitlines():
        heading = HEADING.match(line)
        if heading:
            title = heading.group(1)
            saw_section |= not title.startswith("[")
            current = section_for(title)
            if current:
                raw.setdefault(current, [])
            continue
        if not current:
            continue
        bullet = BULLET.match(line)
        if bullet:
            raw[current].append(bullet.group(1))
        elif line.strip() and raw[current]:
            # Wrapped continuation of the previous bullet (multi-line footers)
            raw[current][-1] += " " + line.strip()
    sections = []
    for name in SECTIONS.values():
        entries: list[str] = []
        for entry in map(clean_entry, raw.get(name, [])):
            if entry and entry not in entries:
                entries.append(entry)
        if entries:
            sections.append((name, entries))
    return sections, saw_section


def shorten(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text[: limit - 1].rsplit(" ", 1)[0].rstrip(",;:")
    return cut + "…"


def render(sections: list[tuple[str, list[str]]], max_chars: int) -> tuple[str, int]:
    """Returns (notes, number of entries left out for length)."""
    out = ""
    total = sum(len(entries) for _, entries in sections)
    written = 0
    for name, entries in sections:
        head = ("\n\n" if out else "") + f"{name}:"
        for i, entry in enumerate(entries):
            prefix = (head if i == 0 else "") + "\n• "
            room = max_chars - len(out) - len(prefix)
            if len(entry) > room:
                if written:
                    return out, total - written
                # A single entry longer than the whole budget: shorten it
                # rather than publishing nothing.
                warn(f"First entry is longer than {max_chars} characters and was shortened")
                entry = shorten(entry, room)
            out += prefix + entry
            written += 1
    return out, total - written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--max-chars", type=int, default=500)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding="utf-8-sig")
    sys.stdout.reconfigure(encoding="utf-8")
    body = sys.stdin.read()

    sections, saw_section = parse(body)
    notes, dropped = render(sections, args.max_chars)

    if not body.strip():
        warn(f'Release body is empty; using "{FALLBACK}"')
    elif not saw_section:
        warn(f'No section headings in the release body (hand-edited?); using "{FALLBACK}"')
    elif not sections:
        warn(
            "Release only contains sections that are hidden from the store "
            f'(e.g. Dependencies, Reverts); using "{FALLBACK}"'
        )
    if dropped:
        warn(f"{dropped} entr{'y' if dropped == 1 else 'ies'} left out to fit {args.max_chars} characters")

    sys.stdout.write(notes or FALLBACK)


if __name__ == "__main__":
    main()
