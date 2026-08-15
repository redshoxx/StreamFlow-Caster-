#!/usr/bin/env python3
"""Publish an AltStore Classic version entry from a built StreamFlow IPA."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote
from zipfile import ZipFile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--ipa', required=True, type=Path)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--repository', required=True, help='GitHub repository in owner/name form')
    parser.add_argument(
        '--localized-description',
        default='Stabilitäts-, Performance- und Kompatibilitätsverbesserungen.',
    )
    return parser.parse_args()


def ipa_metadata(ipa: Path) -> dict[str, object]:
    if not ipa.is_file():
        raise SystemExit(f'IPA not found: {ipa}')

    with ZipFile(ipa) as archive:
        plist_names = [
            name
            for name in archive.namelist()
            if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')
        ]
        if len(plist_names) != 1:
            raise SystemExit(f'Expected exactly one app Info.plist, found {len(plist_names)}')
        info = plistlib.loads(archive.read(plist_names[0]))

    required = ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')
    missing = [key for key in required if not str(info.get(key, '')).strip()]
    if missing:
        raise SystemExit(f'IPA Info.plist is missing: {", ".join(missing)}')

    privacy = {
        key: value
        for key, value in info.items()
        if key.endswith('UsageDescription') and isinstance(value, str) and value.strip()
    }
    return {
        'bundleIdentifier': str(info['CFBundleIdentifier']),
        'version': str(info['CFBundleShortVersionString']),
        'buildVersion': str(info['CFBundleVersion']),
        'minOSVersion': str(info.get('MinimumOSVersion', '')).strip(),
        'privacy': privacy,
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    if not args.source.is_file():
        raise SystemExit(f'Source JSON not found: {args.source}')

    metadata = ipa_metadata(args.ipa)
    source = json.loads(args.source.read_text(encoding='utf-8'))
    apps = source.get('apps')
    if not isinstance(apps, list):
        raise SystemExit('Source JSON has no apps array')

    app = next(
        (
            item
            for item in apps
            if isinstance(item, dict) and item.get('bundleIdentifier') == metadata['bundleIdentifier']
        ),
        None,
    )
    if app is None:
        raise SystemExit(f"No source app matches {metadata['bundleIdentifier']}")

    permissions = app.setdefault('appPermissions', {})
    entitlements = permissions.setdefault('entitlements', [])
    if not isinstance(entitlements, list):
        raise SystemExit('appPermissions.entitlements must be an array')
    permissions['privacy'] = metadata['privacy']

    version_entry: dict[str, object] = {
        'version': metadata['version'],
        'buildVersion': metadata['buildVersion'],
        'date': datetime.now(timezone.utc).date().isoformat(),
        'localizedDescription': args.localized_description,
        'downloadURL': (
            f"https://github.com/{args.repository}/releases/download/"
            f"{quote(args.tag, safe='')}/{quote(args.ipa.name, safe='')}"
        ),
        'size': args.ipa.stat().st_size,
        'sha256': sha256(args.ipa),
    }
    if metadata['minOSVersion']:
        version_entry['minOSVersion'] = metadata['minOSVersion']

    versions = app.setdefault('versions', [])
    if not isinstance(versions, list):
        raise SystemExit('App versions must be an array')

    versions[:] = [
        item
        for item in versions
        if not (
            isinstance(item, dict)
            and item.get('version') == metadata['version']
            and str(item.get('buildVersion')) == metadata['buildVersion']
        )
    ]
    versions.insert(0, version_entry)

    args.source.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )


if __name__ == '__main__':
    main()
