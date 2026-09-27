#!/usr/bin/env python3
"""Steam 經典版 (幻世錄 1.06 inside 幻世錄 重製版) fetch / verify / pak diff / music listing.

The folder lives outside the repository (hsltools.paths.STEAM_CLASSIC_ROOT, env HSL_STEAM_CLASSIC);
its pinned file list is docs/evidence_packets/resource_inventory/steam_classic_files.json. Packet:
docs/evidence_packets/resource_inventory/steam_classic_edition.md.

    python3 tools/hsl_steam_classic.py fetch            # print the DepotDownloader commands (the user logs in)
    python3 tools/hsl_steam_classic.py verify           # sha1 every file against the pinned list
    python3 tools/hsl_steam_classic.py pakdiff [--text] # local ORIGINAL_PAK vs Steam hsl.pak / hsl-cn.pak, per member
    python3 tools/hsl_steam_classic.py music            # music\\NN.wav format and durations
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from collections import Counter
from difflib import unified_diff
from pathlib import Path

from hsltools.paths import EVIDENCE, ORIGINAL_PAK, STEAM_CLASSIC_ROOT
from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes

PINNED = EVIDENCE / 'resource_inventory/steam_classic_files.json'
EMPTY_SHA1 = hashlib.sha1(b'').hexdigest()
TEXT_SUFFIXES = ('.txt', '.h', '.def')


def pinned() -> dict:
    return json.loads(PINNED.read_text(encoding='utf-8'))


def cmd_fetch(args: argparse.Namespace) -> int:
    pin = pinned()
    dest = STEAM_CLASSIC_ROOT.parent
    common = (f"-app {pin['app']} -depot {pin['depot']} -manifest {pin['manifest']} -os windows "
              f"-filelist {dest.parent / 'classic_all.txt'} -max-downloads 16 -dir {dest}")
    print(f"# DepotDownloader (github.com/SteamRE/DepotDownloader, macOS arm64 build) — the owner logs in, never the agent")
    print(f"printf 'regex:^GAME-PAK/\\n' > {dest.parent / 'classic_all.txt'}")
    print(f"DepotDownloader {common} -qr -remember-password            # first time: scan the QR code in the Steam app")
    print(f"DepotDownloader {common} -username <steam-account> -remember-password   # later runs")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    root = Path(args.root)
    ok = bad = missing = 0
    for entry in pinned()['files']:
        path = root / entry['path']
        if not path.is_file():
            missing += 1
            print(f"MISSING {entry['path']}")
            continue
        digest = hashlib.sha1(path.read_bytes()).hexdigest()
        if digest == (entry['sha1'] or EMPTY_SHA1) and path.stat().st_size == entry['size']:
            ok += 1
        else:
            bad += 1
            print(f"BAD {entry['path']}")
    print(f"STEAM_CLASSIC_VERIFY root={root} ok={ok} bad={bad} missing={missing}")
    return 0 if bad == missing == 0 else 1


def pak_members(path: Path) -> dict[str, bytes]:
    package = find_decoded_paks_packages(path)[0]
    end = int(package['paks']['candidate_index_offset'])
    return {str(r['name']).lower(): read_paks_record_bytes(package['path'], r, end) for r in package['records']}


def diff_summary(label: str, left: dict[str, bytes], right: dict[str, bytes], text: bool) -> None:
    changed = sorted(k for k in left.keys() & right.keys() if left[k] != right[k])
    only_left, only_right = sorted(left.keys() - right.keys()), sorted(right.keys() - left.keys())
    print(f"== {label}: members {len(left)} vs {len(right)}, identical {len(left.keys() & right.keys()) - len(changed)}, "
          f"changed {len(changed)}, only-left {len(only_left)}, only-right {len(only_right)}")
    folder = lambda name: name.split('\\')[1] if name.count('\\') > 1 else ''
    print('   changed by folder:', dict(Counter(folder(k) for k in changed).most_common()))
    for title, names in (('changed', changed), ('only-left', only_left), ('only-right', only_right)):
        if names:
            print(f'   {title}:', ' '.join(n.replace('@:\\', '') for n in names))
    if text:
        for name in changed:
            if name.endswith(TEXT_SUFFIXES):
                a = left[name].decode('big5', 'replace').splitlines()
                b = right[name].decode('big5', 'replace').splitlines()
                print(f'--- {name}')
                for line in unified_diff(a, b, 'left', 'right', n=0, lineterm=''):
                    if not line.startswith(('---', '+++')):
                        print('   ', line)


def cmd_pakdiff(args: argparse.Namespace) -> int:
    root = Path(args.root)
    local = pak_members(Path(args.local))
    steam_tw = pak_members(root / 'hsl.pak')
    steam_cn = pak_members(root / 'hsl-cn.pak')
    diff_summary('local hsl.pak -> Steam hsl-cn.pak', local, steam_cn, text=False)
    diff_summary('local hsl.pak -> Steam hsl.pak (Steam default)', local, steam_tw, text=args.text)
    return 0


def wav_info(path: Path) -> tuple[int, int, int, float]:
    data = path.read_bytes()
    pos, fmt, frames = 12, None, 0
    while pos + 8 <= len(data):
        tag, size = data[pos:pos + 4], struct.unpack_from('<I', data, pos + 4)[0]
        if tag == b'fmt ':
            fmt = struct.unpack_from('<HHIIHH', data, pos + 8)
        elif tag == b'data':
            frames = size
        pos += 8 + size + (size & 1)
    _, channels, rate, _, align, bits = fmt
    return rate, channels, bits, frames / align / rate


def cmd_music(args: argparse.Namespace) -> int:
    folder = Path(args.root) / 'music'
    total = 0.0
    for path in sorted(folder.glob('*.wav')):
        rate, channels, bits, seconds = wav_info(path)
        total += seconds
        print(f'{path.name:10} {rate} Hz {channels}ch {bits}-bit {seconds:7.1f} s')
    print(f'total {total / 60:.1f} min')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', default=str(STEAM_CLASSIC_ROOT), help='Steam GAME-PAK folder')
    sub = parser.add_subparsers(dest='cmd', required=True)
    sub.add_parser('fetch')
    sub.add_parser('verify')
    diff = sub.add_parser('pakdiff')
    diff.add_argument('--local', default=str(ORIGINAL_PAK))
    diff.add_argument('--text', action='store_true', help='also print Big5 line diffs of changed text members')
    sub.add_parser('music')
    args = parser.parse_args()
    return {'fetch': cmd_fetch, 'verify': cmd_verify, 'pakdiff': cmd_pakdiff, 'music': cmd_music}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
