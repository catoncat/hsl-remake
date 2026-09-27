#!/usr/bin/env python3
"""Import native SHP draw origins for the first battle's stand objects."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_PAK
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'content/imported/hsl/chapter01/map_object_alignment.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pak', type=Path, default=ORIGINAL_PAK)
    parser.add_argument('--check', action='store_true', help='Recheck against the external original PAK without writing')
    args = parser.parse_args()
    packages = find_decoded_paks_packages(args.pak)
    placements = json.loads((OUTPUT.parent / 'map_objects.json').read_text())['placements']
    shapes = {}
    for item in placements:
        if item.get('role') != 'map_object' or item['shape_resource_id'] in shapes:
            continue
        member = '@:\\' + item['shape_resource']
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous SHP: ' + member)
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        if raw[:4] != b'TLHS' or len(raw) < 36:
            raise ValueError('invalid SHP: ' + member)
        shapes[item['shape_resource_id']] = {'source_member': member, 'source_sha256': hashlib.sha256(raw).hexdigest(),
            'draw_origin': list(struct.unpack_from('<ii', raw, 28)), 'evidence_tier': 'resource-derived'}
    result = json.loads(OUTPUT.read_text())
    if args.check:
        assert result['shapes'] == shapes
        print('MAP_OBJECT_ORIGINS_CHECK_PASS')
        return
    result.update(shapes=shapes, evidence_tier='static-derived', provisional=False,
        source_policy='EVEF world coordinates minus the original SHP draw_origin. Historical bridge calibrations are validation evidence only; they do not override placement.')
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('MAP_OBJECT_ORIGINS_IMPORTED', len(shapes))


if __name__ == '__main__':
    main()
