#!/usr/bin/env python3
"""Recheck compact combat instruction anchors against the local original EXE."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_EXE

PACKET = Path('content/generated/hsl/static/hsl01/core_logic.json')


def probe(exe: Path, packet: Path = PACKET) -> dict:
    anchors = json.loads(packet.read_text())['combat_resolution']['instruction_anchors']
    commands = ';'.join(f'p8 {len(a["bytes"]) // 2} @ {a["address"]}' for a in anchors)
    result = subprocess.run(['r2', '-e', 'scr.color=0', '-e', 'bin.cache=true', '-q', '-c', commands, str(exe)], capture_output=True, text=True, check=True)
    actual = result.stdout.splitlines()
    if actual != [a['bytes'] for a in anchors]:
        raise ValueError('combat instruction anchors differ from the inspected executable')
    return {'schema': 'hsl_combat_resolution_probe.v1', 'evidence_tier': 'static-derived', 'exe_sha256': hashlib.sha256(exe.read_bytes()).hexdigest(), 'verified_anchor_count': len(anchors)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    args = parser.parse_args()
    print(json.dumps(probe(args.exe), indent=2))
