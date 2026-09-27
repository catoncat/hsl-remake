"""Verify original command/phase tables, movement rollback and shared finish bytes.

This checker never executes original code. The separate turn-selector probe
records bounded native helper returns; remaining decoded notes are marked.

Registry task action_state_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_action_state_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from hsltools.evidence.item_action import SOURCE_SHA
from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_action_state_machine.json'
COMMANDS = {
    'move': (110, 1, 0x4440F7), 'attack': (111, 2, 0x44413D),
    'item': (112, 3, 0x44416C), 'wait': (113, 4, 0x4454A5),
    'use': (114, 5, 0x444A8B), 'give': (115, 6, 0x444D6A),
    'equip': (116, 7, 0x444185), 'drop': (117, 8, 0x4441AC),
    'magic': (118, 9, 0x4441E8), 'special': (119, 10, 0x444223),
    'ok': (120, 11, 0x4447A7), 'cancel': (121, 12, 0x4447A7),
    'status': (122, 13, 0x44425F),
}
PHASES = {0: 0x4439D5, 1: 0x443A67, 20: 0x443C4A, 21: 0x4440D1}
SUBSTATES = {71: 0x444894, 75: 0x44429B, 76: 0x4447A7, 77: 0x444C19,
             80: 0x4442E4, 81: 0x444F3E, 85: 0x4445F3, 87: 0x444F3E,
             118: 0x444E3B, 119: 0x4447A7, 120: 0x444E58,
             150: 0x4447A7, 151: 0x44500F}
MOVE_SUBSTATES = [0x443C63,0x443E34,0x443E53,0x443E9A,0x443F10,0x443EC0,
                 0x443EE9,0x443F10,0x444086,0x444095,0x4447A7,0x4440B7]
FINISH_SUBSTATES = [0x4454A5,0x4447A7,0x443A86,0x443AD1,0x443B35,
                   0x443B80,0x443BA1,0x443BBA,0x443BED]
ANCHORS = [
    (0x44412E, 'c7868c00000000001400', 'Move enters outer20/low0.'),
    (0x444086, 'c7868c00000000001500', 'Completed movement enters outer21/low0.'),
    (0x4440D1, '6639968c0000000f8507f9ffff6a0156e84aa9ffff83c40866c7868c0000004a00e9b0060000', 'Post-move low0 opens mode1 and waits74; other low states use ordinary dispatch.'),
    (0x44429B, '5356e8eed8fcff33d233c0668b9696000000668b86940000005356895604894608e86fd7fcff6a0156e8677cffffc7868c0000000000000083c41866c7868c0000000100e9c3040000', 'Cancel75 clears old occupancy, restores saved XY, sets restored occupancy, centers camera, resets outer phase and requests Move1.'),
    (0x4440A8, 'c7868c00000000000000', 'Cancelling uncommitted movement selection resets ordinary phase0/state0.'),
    (0x4454AC, '899e8c00000066ff868c000000', 'Common finish writes EBX=0x10000 then increments low word: phase1/state1.'),
    (0x443C01, '33c9898e8c000000', 'End of finish phase resets the complete process state.'),
    (0x443C1A, 'e8f17cfcff83c404e8e938fcff', 'First finish branch ticks status duration then advances the queue exactly once.'),
    (0x443C38, 'e8d37cfcff83c404e8cb38fcff', 'Other finish branch also ticks then advances once.'),
    (0x4074C8, '8b70f885f674058338007526', 'Selector requires a non-null pointer and nonzero ready word.'),
    (0x4074EC, 'e84ffeffff66ff05bc1b4c00', 'Only no-ready-slots path calls rebuild and increments the round counter.'),
]
NOTES = [
    {'address': '0x4439b6', 'operation': 'read word object+0x8e', 'meaning': 'Outer phase is separate from low word object+0x8c.'},
    {'address': '0x44412e', 'operation': 'write DWORD object+0x8c = 0x00140000', 'meaning': 'Move enters outer phase20, substate0; do not call this ordinary state20.'},
    {'address': '0x443d7f..0x443d91', 'operation': 'copy position words object+4/+8 to +0x96/+0x94', 'meaning': 'Remember pre-move coordinates after a successful path-selection predicate.'},
    {'address': '0x444086', 'operation': 'write DWORD object+0x8c = 0x00150000', 'meaning': 'Movement completion enters phase21, substate0.'},
    {'address': '0x4440d1..0x4440f2', 'operation': 'phase21 low0 opens menu mode1 and writes low74; other low states dispatch through0x4439e5', 'meaning': 'Post-move commands preserve the outer phase until an explicit DWORD reset.'},
    {'address': '0x43e96c..0x43e9ae', 'operation': 'cancel-input path increments owner low word object+0x8c and removes menu group', 'meaning': 'Post-move menu74 cancellation reaches75; command Data8=12 is not this cancellation route.'},
    {'address': '0x44429b..0x4442df', 'operation': 'restore object+4/+8 from saved+0x96/+0x94, clear DWORD state, write low1', 'meaning': 'Post-move cancellation restores position and requests Move again. Occupancy-helper internals are not reimplemented by this packet.'},
    {'address': '0x4440a8', 'operation': 'write DWORD object+0x8c = 0', 'meaning': 'Cancelling movement selection before walking returns to ordinary phase0/state0.'},
    {'address': '0x4441da / 0x444c19', 'operation': 'write low76 / low3 only', 'meaning': 'Equip/Drop open/close does not itself clear outer movement phase21.'},
    {'address': '0x444d6a / 0x444def / 0x444bff', 'operation': 'Give loop110, compare returned/outgoing code, end only if used', 'meaning': 'Reuse original_give_exchange for exact checked instruction bytes and limits.'},
    {'address': '0x444e3b', 'operation': 'Use completion enters state4', 'meaning': 'Reuse original_item_actions for checked bytes; state4 and Wait share the same destination.'},
]


def expected_packet() -> dict:
    return {'schema': 'hsl_action_state_machine_static.v1', 'evidence_tier': 'static-derived',
            'exe_sha256': EXE_SHA, 'source_member': '@:\\data\\obj-051.obs', 'source_sha256': SOURCE_SHA,
            'commands': {name: {'object_code': code, 'data8': state, 'destination': hex(entry)}
                         for name,(code,state,entry) in COMMANDS.items()},
            'state_layout': {'outer_word_offset': '0x8e', 'inner_word_offset': '0x8c'},
            'outer_phases': {str(s): hex(e) for s,e in PHASES.items()},
            'inner_states': {str(s): hex(e) for s,e in SUBSTATES.items()},
            'move_substate_table': {'address': '0x445820', 'entries': [hex(e) for e in MOVE_SUBSTATES]},
            'finish_substate_table': {'address': '0x4457fc', 'entries': [hex(e) for e in FINISH_SUBSTATES]},
            'instruction_anchors': [{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS],
            'reviewed_disassembly': NOTES,
            'verification': {'native_execution': False, 'checked': 'Original identity, PAK Data8, dispatch tables and the listed movement/finish anchors.',
                             'trace_instruction_bytes_checked': True},
            'limits': ['The earlier slice saved disassembly only after a blocked extraction; this successor checked the listed instruction anchors directly.',
                       'Movement cost/path predicates, large-actor occupancy, complete control flags and status effects remain incomplete.',
                       'Live cancel now restores position and re-enters movement selection; confirmed inventory/equipment changes remain committed.',
                       'Attack/special completion is in original_offense_completion.json; eight bounded selector returns are separately in original_turn_selection_native.json.',
                       'Godot action_ready is completion bookkeeping. Native readiness is cleared on selection and permits a circular scan before rebuild.',
                       'No complete AI decision tree, all-class control, phase1 status tick or asynchronous callbacks are claimed.']}


def destination(mapped: bytes | bytearray, base: int, index_address: int, targets: int, state: int) -> int:
    index = mapped[index_address-base+state]
    return struct.unpack_from('<I',mapped,targets-base+index*4)[0]


def check_mapped(base: int, mapped: bytes | bytearray) -> None:
    for address, encoded, _ in ANCHORS:
        offset = address-base
        expected = bytes.fromhex(encoded)
        if offset < 0 or bytes(mapped[offset:offset+len(expected)]) != expected:
            raise ValueError(f'Action instruction differs at {address:#x}')
    for state,entry in {**{s:e for _,s,e in COMMANDS.values()}, **SUBSTATES}.items():
        if destination(mapped,base,0x445758,0x445694,state) != entry:
            raise ValueError(f'Action inner dispatch differs at {state}')
    for phase,entry in PHASES.items():
        if destination(mapped,base,0x44567C,0x445668,phase) != entry:
            raise ValueError(f'Action outer dispatch differs at {phase}')
    actual = struct.unpack_from('<12I',mapped,0x445820-base)
    if list(actual) != MOVE_SUBSTATES:
        raise ValueError('Movement substate dispatch differs')
    if list(struct.unpack_from('<9I',mapped,0x4457FC-base)) != FINISH_SUBSTATES:
        raise ValueError('Finish substate dispatch differs')


def check_objects(rows: dict) -> None:
    for name,(code,state,_) in COMMANDS.items():
        row = rows[code]
        if row.get('obj_Process_Code') != 'defProcBattleCommandString' or int(row['obj_Data8']) != state:
            raise ValueError(f'Action PAK Data8 differs: {name}')


def check_pak(path: Path) -> None:
    from hsltools.data.first_skill import blocks
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    found = [(p,r) for p in find_decoded_paks_packages(path)
             if (r := find_paks_record_by_name(p['records'],'@:\\data\\obj-051.obs'))]
    if len(found) != 1:
        raise ValueError('Missing or ambiguous action source')
    p,r = found[0]
    raw = read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA:
        raise ValueError('Action PAK source identity differs')
    check_objects({int(row['obj_code']): row for row in blocks(raw,'Object') if 'obj_code' in row})


class ActionStateEvidenceTask(ScriptCheckTask):
    name = 'action_state_evidence'
    family = 'evidence'
    inputs = ('content/imported/hsl/shared/command_menu/source_objects.json',)
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_action_state_evidence.py',)
    scripts = ('tools/hsltools/evidence/action_state.py', 'tools/hsltools/evidence/item_action.py')

    def verify(self, ctx: Context) -> None:
        expected = expected_packet()
        if json.loads(PACKET.read_text()) != expected:
            raise ValueError('Action-state packet differs from reviewed evidence')
        print(f'ACTION_STATE_EVIDENCE_PASS commands={len(COMMANDS)} original_exe=False original_pak=False native_execution=False')


def tasks() -> list[ActionStateEvidenceTask]:
    return [ActionStateEvidenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path)
    parser.add_argument('--pak',type=Path)
    parser.add_argument('--write',action='store_true')
    args = parser.parse_args()
    if args.exe: check_mapped(*image(args.exe.read_bytes()))
    if args.pak: check_pak(args.pak)
    expected = expected_packet()
    if args.write:
        if not args.exe or not args.pak: raise ValueError('Writing requires original identity and table checks')
        PACKET.write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n')
    if json.loads(PACKET.read_text()) != expected:
        raise ValueError('Action-state packet differs from reviewed evidence')
    print(f'ACTION_STATE_EVIDENCE_PASS commands={len(COMMANDS)} original_exe={bool(args.exe)} original_pak={bool(args.pak)} native_execution=False')


if __name__ == '__main__': main()
