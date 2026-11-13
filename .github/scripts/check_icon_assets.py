#!/usr/bin/env python3
"""Checks that a compiled asset archive holds the layered app icon.

Usage: check_icon_assets.py <output of `assetutil --info Assets.car`>

Xcode builds without the Icon Composer document just as happily, with the
flat icon of the asset catalog, so the build alone proves nothing. With the
document compiled in, the archive holds its layers as vectors, one record
per appearance, and flat pictures for iOS 18 and earlier.
"""
import json
import os
import sys

ICON = 'AppIcon'


def main() -> int:
    entries = json.load(open(sys.argv[1], encoding='utf-8'))[1:]
    errors = []

    # One vector per layer image in the document.
    package = os.path.join('ios', 'Runner', ICON + '.icon')
    layers = {
        os.path.splitext(name)[0]
        for name in os.listdir(os.path.join(package, 'Assets'))
    }
    vectors = {
        e['Name'].split('/', 1)[1]
        for e in entries
        if e.get('AssetType') == 'Vector'
        and e.get('Name', '').startswith(ICON + '_Assets/')
    }
    if vectors != layers:
        errors.append(
            f'layers in the archive: {sorted(vectors)}, '
            f'in the document: {sorted(layers)}')

    # The icon itself, for the light, dark and tinted appearances.
    appearances = {
        e.get('Appearance')
        for e in entries
        if e.get('Name') == ICON and e.get('AssetType') == 'Unknown'
    }
    wanted = {'UIAppearanceLight', 'UIAppearanceDark', 'ISAppearanceTintable'}
    if not wanted <= appearances:
        errors.append(f'icon appearances in the archive: {appearances}')

    # The flat pictures. App Store Connect refuses one with an alpha
    # channel (ITMS-90717).
    flat = [
        e for e in entries
        if e.get('Name') == ICON and e.get('AssetType') == 'Icon Image'
    ]
    if not flat:
        errors.append('no flat pictures for iOS 18 and earlier')
    for e in flat:
        if not e.get('Opaque'):
            errors.append(f"{e.get('RenditionName')} is not opaque")

    for error in errors:
        print(f'::error::{error}')
    if not errors:
        print(f'{ICON}: layers {sorted(vectors)}, {len(flat)} flat pictures, '
              'all opaque')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
