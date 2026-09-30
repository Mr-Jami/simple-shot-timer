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
whole bullet rather than mid-sentence.
"""

import argparse
import re
import sys

FALLBACK = "Bug fixes and improvements."

# release-please section heading -> store heading. Sections not listed here
# (Breaking Changes, Dependencies, Reverts, hidden types) are left out:
# breaking entries already appear under Features/Bug Fixes, and the rest
# mean nothing to someone updating the app.
SECTIONS = {
    "features": "New",
    "bug fixes": "Fixes",
    "performance": "Improvements",
}

HEADING = re.compile(r"^#{1,6}\s+(.*)$")
BULLET = re.compile(r"^\s*[*-]\s+(.*)$")


def clean_entry(text: str) -> str:
    # ", closes #24" / ", closes [#24](...)" trailers
    text = re.sub(r",\s*closes\s+\[?#.*$", "", text, flags=re.IGNORECASE)
    # Trailing link groups: ([#25](url)) ([83fcee8](url))
    text = re.sub(r"\s*\(\[[^\]]*\]\([^)]*\)\)", "", text)
    # Leading scope: **drills:**
    text = re.sub(r"^\*\*[^*]+:\*\*\s*", "", text)
    # Any remaining markdown links -> their label
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Emphasis / inline code markers
    text = re.sub(r"[*_`]", "", text)
    text = re.sub(r"\s+", " ", text).strip().rstrip(".")
    return text[:1].upper() + text[1:]


def parse(body: str) -> list[tuple[str, list[str]]]:
    sections: dict[str, list[str]] = {}
    current = None
    for line in body.splitlines():
        heading = HEADING.match(line)
        if heading:
            current = SECTIONS.get(heading.group(1).strip().lower())
            if current:
                sections.setdefault(current, [])
            continue
        bullet = BULLET.match(line)
        if current and bullet:
            entry = clean_entry(bullet.group(1))
            if entry and entry not in sections[current]:
                sections[current].append(entry)
    # Keep the order defined in SECTIONS, drop empty ones.
    return [(name, sections[name]) for name in SECTIONS.values() if sections.get(name)]


def render(sections: list[tuple[str, list[str]]], max_chars: int) -> str:
    out = ""
    for name, entries in sections:
        block_head = ("\n\n" if out else "") + f"{name}:"
        added = False
        for entry in entries:
            line = f"\n• {entry}"
            chunk = (block_head if not added else "") + line
            if len(out) + len(chunk) > max_chars:
                return out or FALLBACK
            out += chunk
            added = True
    return out or FALLBACK


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--max-chars", type=int, default=500)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding="utf-8-sig")
    sys.stdout.reconfigure(encoding="utf-8")
    body = sys.stdin.read()
    sys.stdout.write(render(parse(body), args.max_chars))


if __name__ == "__main__":
    main()
