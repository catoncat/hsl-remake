"""Check original item-command dispatch and important-item guards without execution.

Registry task item_action_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_item_action_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_item_actions.json'
OBJECTS = ROOT / 'content/imported/hsl/shared/command_menu/source_objects.json'
SOURCE_SHA = 'f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8'
ROUTES = {
    'use': {'object_code': 114, 'state': 5, 'entry': '0x444a8b', 'inventory_mode': 6, 'selection_state': 102},
    'give': {'object_code': 115, 'state': 6, 'entry': '0x444d6a', 'inventory_mode': 7, 'selection_state': 110},
    'equip': {'object_code': 116, 'state': 7, 'entry': '0x444185', 'inventory_mode': 4, 'selection_state': 76},
    'drop': {'object_code': 117, 'state': 8, 'entry': '0x4441ac', 'inventory_mode': 5, 'selection_state': 76},
}
PARENT_RETURNS = {
    'item_menu': {'state': 3, 'entry': '0x44416c'},
    'window_wait': {'state': 76, 'entry': '0x4447a7'},
    'window_closed': {'state': 77, 'entry': '0x444c19'},
}
ANCHORS = [
    (0x43E887, '668b8ea8000000', 'Read command obj_Data8 from object+0xa8.'),
    (0x43E891, '6689888c000000', 'Write that command value to parent process state+0x8c.'),
    (0x447DA1, '68548a4700', 'ITEM loader requests the important field.'),
    (0x447DAA, 'e821e9ffff', 'Read the numeric field via 0x4466d0.'),
    (0x447DB2, '3bc5894424147408814c241000000008', 'Nonzero important adds mask 0x08000000.'),
    (0x4481B1, '89843aa0000000', 'Store assembled first flag word at ITEM+0xa0.'),
    (0x478A54, '696d706f7274616e7400', 'Original field name important, NUL terminated.'),
    (0x40E690, '8b4c240433c08d14898d0c518b15401b4c00c1e104f78411a0000000000000087405b801000000c3', 'Predicate returns whether item flags+0xa0 contain bit 27.'),
    (0x43AACB, 'a1e41c4c0085c0747e50e8b63bfdff83c40485c07571a3e41c4c00', 'Battle item UI discard leaves held item intact when important; clears only after false predicate.'),
    (0x42A7E2, 'a1e41c4c0085c00f841f01000050e89b3efeff83c40485c00f850e010000a3e41c4c00', 'Other item UI independently applies the same guarded discard.'),
    (0x444A5C, '8b15001b4c00a1e41c4c0081e2ffffdfff85c08915001b4c0074145056e8b223ffff83c408c705e41c4c000000000066c7868c0000006600e90efdffff', 'Use target cancellation returns held code through insert, clears hold and returns to state102.'),
    (0x444D3B, '8b15001b4c00a1e41c4c0081e2ffffdfff85c08915001b4c0074145056e8d320ffff83c408c705e41c4c000000000066c7868c0000006e00e92ffaffff', 'Give target cancellation returns held code through insert, clears hold and returns to state110.'),
    (0x444DEF, 'a1e41c4c008b0d882c4c003bc874138b86800000000bc3898680000000a1e41c4c00', 'Give return compares current hold with original selection and ORs EBX into owner flags when changed.'),
    (0x444E11, '85c00f8451ffffff5056e81020ffffc705e41c4c000000000083c40866c7868c0000006e00', 'Give return reinserts any remaining held code before returning to selection.'),
    (0x444BFF, '8b868000000085c3741025fffffeff898680000000e98c08000066c7868c0000000300e980fbffff', 'Closing Give checks flag 0x10000: clear and enter common action finish if set, otherwise state3.'),
    (0x444E3B, 'e88066ffffc7868c0000000000000066c7868c0000000400e94ff9ffff', 'Use completion state118 closes UI and goes to command state4.'),
    (0x444185, '33c96a01668b8ea00000006a0051e8f822ffff33d256668b96a00000006a048915e42a4c00eb25', 'Actual Equip entry selects item UI mode4.'),
    (0x4441AC, '33c06a00668b86a00000006a0050e8d122ffff33c956668b8ea00000006a05890de42a4c0056e80973ffff83c41866c7868c0000004c00', 'Actual Drop entry selects mode5, shared wait state76.'),
    (0x43BF04, 'fdb74300fdb74300', 'UI builder modes4/5 share the root-construction entry 0x43b7fd.'),
    (0x43B7FD, '8b44241c5055e808f4ffff', 'Pass caller parent and actor to the status-root constructor 0x43ac10.'),
    (0x43AC10, '6a00688200000068102700006810270000e8e1360200', 'Spawn original object130, whose source process is defProcStatusWindow with Data9=0.'),
    (0x43AC4D, '8b4c240889889c000000', 'Store the caller parent pointer in root+0x9c for closure notification.'),
    (0x43B81B, '66c78694000000010081c900400040898e80000000', 'Equip/Drop roots set selection1 and flags0x40004000; the held-return gate uses 0x4000.'),
    (0x43B8FE, '83fb050f85e60500006a006a00e870f9ffff', 'Mode5 adds the discard button via 0x43b280; mode4 skips it.'),
    (0x439ED8, 'd3854300', 'Ordinary Data9=0 root handling enters 0x4385d3.'),
    (0x4385F1, '33ffeb0e33ffc744243800000040897c2460', 'Both root frame branches set EDI=0 before input and closure handling.'),
    (0x439EF8, 'b5874300118843003d894300ce894300', 'Root states0/1/2/3 dispatch to opening, input, closing animation and parent notification.'),
    (0x438811, 'a198634c00a9000002007510f70590634c00000010000f849a000000a8010f8592000000', 'Root accepts cancel input or alternate cancel only after the input-held bit clears.'),
    (0x438835, '8b442474f6c4040f8585000000f6c4407477f6c41075728b0de41c4c003bcf7468', 'With flags0x4000 and no0x1000/0x0400, a held item must be returned before closing.'),
    (0x438868, 'e8c3e5ffff83c40885c00f8435160000', 'Call first-empty insertion; failure exits without clearing hold or requesting closure.'),
    (0x438882, '893de41c4c00e803dcffff', 'Only successful insertion clears held code and refreshes the inventory view.'),
    (0x4388B6, '5f5e5d5b83c45cc3', 'Successful held-item return exits this invocation before the close-request branch.'),
    (0x4388BE, '66c78696000000ffff6683be96000000ff7508426689968c000000', 'No held item requests close with sentinel-1, then advances the root input state to its closing animation.'),
    (0x43896B, 'e89d5e020083c42085c0740766ff868c000000', 'Closing animation completion advances the root to notification state3.'),
    (0x4389CE, '8b869c000000575666ff808c000000e82f65020083c40450e82d660200', 'Increment the saved parent state76 to77 and release the UI group; no turn handoff here.'),
    (0x444C19, '66c7868c0000000300e980fbffff', 'Parent state77 returns to item-menu state3, preserving the current action.'),
]


def check_objects(objects: dict) -> None:
    if objects.get('source_sha256') != SOURCE_SHA:
        raise ValueError('Unexpected original command-object source identity')
    for name, route in ROUTES.items():
        obj = objects['commands'][name]
        if (obj['object_code'], obj['command_id'], obj['process']) != (
                route['object_code'], route['state'], 'defProcBattleCommandString'):
            raise ValueError(f'Command Data8/state mismatch: {name}')


def expected_packet() -> dict:
    objects = json.loads(OBJECTS.read_text())
    check_objects(objects)
    return {'schema': 'hsl_item_actions_static.v1', 'evidence_tier': 'static-derived',
            'exe_sha256': EXE_SHA, 'source_member': objects['source_member'], 'source_sha256': SOURCE_SHA,
            'command_routes': ROUTES, 'dispatch': {'byte_indices': '0x445758', 'destination_table': '0x445694'},
            'window_close': {
                'source_object': {'object_code': 130, 'process': 'defProcStatusWindow', 'data9': 0},
                'process_address': '0x438160', 'root_state_table': '0x439ef8',
                'parent_pointer_offset': '0x9c', 'parent_returns': PARENT_RETURNS,
                'held_return': '0x438868 inserts into owner; full backpack preserves hold and open window.',
                'close': 'After held item is cleared, root1->2->3 increments parent76->77->3 item submenu.',
                'action_policy': 'Traced ordinary Equip/Drop closure returns to the item menu without ending the actor action.',
            },
            'important': {'source_field': 'important', 'flags_offset': '0xa0', 'mask': '0x08000000', 'predicate': '0x40e690'},
            'instruction_anchors': [{'address': hex(a), 'bytes': b, 'reviewed_meaning': m} for a, b, m in ANCHORS],
            'native_execution': False,
            'correction': 'Menu rtus order does not determine process states. Use/Give/Equip/Drop are Data8=5/6/7/8, not 7/10/8/9.',
            'limits': ['No original function or UI was executed. Static branches do not establish the entire interactive lifecycle.',
                       'Important prohibits discard; this evidence does not prohibit transfer or equipment.',
                       'Use/Give cancel returns held items to the first empty slot; current remake cancellation never removes draft items.',
                       'Confirmation instead of dragging, cancellation preserving the original slot order and movement rollback are remake interaction policies.',
                       'Give multi-transfer sessions, same-code exchanges, sorting and full original movement flags remain unresolved.']}


def check_mapped(base: int, mapped: bytes | bytearray) -> None:
    for address, encoded, _ in ANCHORS:
        expected = bytes.fromhex(encoded)
        offset = address - base
        if offset < 0 or bytes(mapped[offset:offset+len(expected)]) != expected:
            raise ValueError(f'Original item-action bytes differ at {address:#x}')
    for name, route in {**ROUTES, **PARENT_RETURNS}.items():
        index = mapped[0x445758 - base + route['state']]
        actual = struct.unpack_from('<I', mapped, 0x445694 - base + index*4)[0]
        if actual != int(route['entry'], 16):
            raise ValueError(f'Original item-command dispatch differs: {name}')


def check_pak(path: Path) -> None:
    from hsltools.data.first_skill import blocks
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    objects = json.loads(OBJECTS.read_text())
    candidates = [(package, record) for package in find_decoded_paks_packages(path)
                  if (record := find_paks_record_by_name(package['records'], objects['source_member']))]
    if len(candidates) != 1:
        raise ValueError('Missing or ambiguous original item command definitions')
    package, record = candidates[0]
    raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA:
        raise ValueError('Original obj-051.obs bytes differ')
    rows = {int(row['obj_code']): row for row in blocks(raw, 'Object') if 'obj_code' in row}
    for name, route in ROUTES.items():
        if int(rows[route['object_code']]['obj_Data8']) != route['state']:
            raise ValueError(f'Original resource Data8 differs: {name}')
    root = rows[130]
    if root.get('obj_Process_Code') != 'defProcStatusWindow' or int(root.get('obj_Data9', -1)) != 0:
        raise ValueError('Original status-root process or Data9 differs')


class ItemActionEvidenceTask(ScriptCheckTask):
    name = 'item_action_evidence'
    family = 'evidence'
    inputs = ('content/imported/hsl/shared/command_menu/source_objects.json',)
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_item_action_evidence.py',)
    scripts = ('tools/hsltools/evidence/item_action.py',)

    def verify(self, ctx: Context) -> None:
        result = expected_packet()
        if json.loads(PACKET.read_text()) != result:
            raise ValueError('Item-action packet differs from reviewed evidence')
        print(f'ITEM_ACTION_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe=False original_pak=False native_execution=False')


def tasks() -> list[ItemActionEvidenceTask]:
    return [ItemActionEvidenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--pak', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    result = expected_packet()
    if args.exe:
        check_mapped(*image(args.exe.read_bytes()))
    if args.pak:
        check_pak(args.pak)
    if args.write:
        if not args.exe or not args.pak:
            raise ValueError('Writing evidence requires actual EXE and PAK checks')
        PACKET.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    if json.loads(PACKET.read_text()) != result:
        raise ValueError('Item-action packet differs from reviewed evidence')
    print(f'ITEM_ACTION_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe={bool(args.exe)} original_pak={bool(args.pak)} native_execution=False')


if __name__ == '__main__':
    raise SystemExit(main())
