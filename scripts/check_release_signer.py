#!/usr/bin/env python3
"""Refuse an unexpected signing-key change for a published Android release."""
import argparse
import json
import re
import sys

METADATA = re.compile(r'<!--\s*downlist-update:(\{[^\r\n]*\})\s*-->')
FINGERPRINT = re.compile(r'^[a-f0-9]{64}$')


def latest_signer(releases):
    candidates = []
    for release in releases:
        if not isinstance(release, dict) or release.get('draft'):
            continue
        body = release.get('body')
        match = METADATA.search(body) if isinstance(body, str) else None
        if not match:
            continue
        try:
            data = json.loads(match.group(1))
            signer = data.get('signerSha256', '').lower()
            code = data.get('versionCode')
            if data.get('packageName') == 'com.dowlist.com' and isinstance(code, int) and not isinstance(code, bool) and code > 0 and FINGERPRINT.fullmatch(signer):
                candidates.append((code, signer))
        except (ValueError, TypeError, AttributeError):
            continue
    return max(candidates)[1] if candidates else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('releases_file')
    parser.add_argument('signer')
    parser.add_argument('--allow-migration', action='store_true')
    args = parser.parse_args()
    signer = args.signer.lower()
    if not FINGERPRINT.fullmatch(signer):
        parser.error('Invalid current signing certificate fingerprint')
    try:
        with open(args.releases_file, encoding='utf-8') as file:
            releases = json.load(file)
        if not isinstance(releases, list):
            raise ValueError('Expected a release list')
        previous = latest_signer(releases)
    except (OSError, ValueError) as error:
        print(f'Could not verify previous release signing: {error}', file=sys.stderr)
        return 1
    if previous and previous != signer:
        if not args.allow_migration:
            print('::error::Release signing differs from the latest published app. Existing users cannot update in place. An owner must explicitly approve a one-time signing migration.', file=sys.stderr)
            return 1
        print('::warning::Signing migration approved. Existing users of differently signed versions must reinstall; app data will be removed.')
    else:
        print('Release signing matches the latest known release.' if previous else 'No prior release signing metadata found.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
