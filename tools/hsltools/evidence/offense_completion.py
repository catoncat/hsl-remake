"""Check ordinary attack/special completion paths, without native execution.

Registry task offense_completion_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_offense_completion_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from hsltools.evidence.action_state import check_pak
from hsltools.evidence.item_action import SOURCE_SHA
from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_offense_completion.json'
STATES = {4:0x4454A5, 82:0x4445C1, 83:0x4447A7, 84:0x444757,
          85:0x4445F3, 86:0x4447A7, 87:0x444F3E, 88:0x4447D8,
          89:0x44483C, 153:0x445290, 154:0x4447A7, 155:0x4452C9,
          156:0x4447A7, 157:0x445305, 158:0x445328, 159:0x4447A7,
          160:0x445424, 161:0x445458}
ANCHORS = [
    (0x44249E, 'a120434c00a900000100744f', 'Resolution phase4 checks only the pending-counter flag before returning completion1 or counter2; zero EXP does not reopen movement.'),
    (0x4424B7, 'b8020000005bc3', 'Pending counter returns2 to the caller.'),
    (0x4424F9, '5f5e5db8010000005bc3', 'Normal completed resolution returns1, including the zero-EXP/miss route.'),
    (0x4445CF, 'e8ecddffff83c410480f84cd000000480f85c2010000', 'Caller82 distinguishes complete1, counter2 and still-running0.'),
    (0x4446CA, '85ed0f8f47f4ffff', 'Surviving target after completion1 jumps to the common low-state plus2 helper, reaching84.'),
    (0x443B19, '6683868c00000002e9810c0000', 'Increment only the low state by2; do not reset movement phase or reopen a menu.'),
    (0x44460A, '85c00f849501000066c7868c0000005700', 'Completed counter advances to87; zero still waits.'),
    (0x444F3E, 'e86dd4ffff66ff868c000000e958f8ffff', 'State87 resets the resolution helper and advances to88.'),
    (0x444770, '0f842f0d0000', 'Ordinary attack completion84 branches directly to common finish4454a5 when no further reward work remains.'),
    (0x444798, '0f84070d0000', 'No remaining growth/loot work also reaches the same finish.'),
    (0x44481E, 'a178294c0085c00f847a0c0000', 'After owner growth processing, absent counter growth reaches common finish, without consulting prior movement.'),
    (0x444855, '0f854a0c0000', 'Completed counter growth reaches common finish.'),
    (0x4452BD, '66ff868c000000e9def4ffff', 'Special wind-up increments153 to wait154.'),
    (0x4452F9, '66ff868c000000e9a2f4ffff', 'Special presentation increments155 to wait156.'),
    (0x445305, '6a00e8c4b1fcff83c404a3ec1c4c0085c00f8489010000', 'Special157 enumerates targets; no target work remains -> common finish4454a5.'),
    (0x445424, '6a01e8a5b0fcff83c404a3ec1c4c0085c00f8439e7ffff', 'Special160 advances target iteration; no next target increments low state to161.'),
    (0x44548B, 'a1842c4c0085c00f8506f3ffffe833a0000085c00f85f9f2ffff', 'Special161 returns to reward work if needed; otherwise falls through to4454a5. No branch on movement phase.'),
]


def expected_packet() -> dict:
    return {'schema':'hsl_offense_completion_static.v1','evidence_tier':'static-derived',
            'exe_sha256':EXE_SHA,'source_member':'@:\\data\\obj-051.obs','source_sha256':SOURCE_SHA,
            'native_execution':False,'state_destinations':{str(s):hex(e) for s,e in STATES.items()},
            'original_byte_validation_performed':True,
            'instruction_anchors':[{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS],
            'completed_action':{'ordinary_attack':True,'ordinary_miss':True,'special':True,
                                'requires_prior_movement':False,'wait_for_presentation_and_rewards':True},
            'paths':{'ordinary_without_counter':'82 ->84 -> common finish, with optional growth path87/88/89',
                     'ordinary_with_counter':'82 ->85 ->87 ->88[/89] -> common finish',
                     'special':'153/154 ->155/156 ->157 ->158/159/160 target loop ->161 -> common finish',
                     'finish':'0x4454a5, shared with Wait Data8=4 and successful Use'},
            'limits':['No offense function was executed. After the earlier interrupted attempt, this slice checked all listed bytes, dispatch targets and the original PAK directly.',
                      'Native asynchronous presentation/death/growth callbacks and every skill type are not emulated by this packet.',
                      'Current offensive formulas, counter/double-hit PRNG order, target filters and exact animation timing remain separate gaps.',
                      'Death or victory may divert to terminal handling; product must not advance after a terminal outcome.',
                      'Selection cancellation, invalid target or insufficient stamina does not reach these completion routes and must not be treated as a completed offense.']}


def check_mapped(base: int, mapped: bytes | bytearray) -> None:
    for address,encoded,_ in ANCHORS:
        expected = bytes.fromhex(encoded)
        offset = address-base
        if offset < 0 or bytes(mapped[offset:offset+len(expected)]) != expected:
            raise ValueError(f'Offense completion instruction differs at {address:#x}')
    for state,entry in STATES.items():
        slot=mapped[0x445758-base+state]
        if struct.unpack_from('<I',mapped,0x445694-base+4*slot)[0] != entry:
            raise ValueError(f'Offense dispatcher differs at state{state}')


class OffenseCompletionEvidenceTask(ScriptCheckTask):
    name = 'offense_completion_evidence'
    family = 'evidence'
    inputs = ()
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_offense_completion_evidence.py',)
    scripts = ('tools/hsltools/evidence/offense_completion.py', 'tools/hsltools/evidence/action_state.py', 'tools/hsltools/evidence/item_action.py')

    def verify(self, ctx: Context) -> None:
        expected=expected_packet()
        if json.loads(PACKET.read_text()) != expected:
            raise ValueError('Offense packet differs from reviewed evidence')
        print(f'OFFENSE_COMPLETION_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe=False original_pak=False native_execution=False')


def tasks() -> list[OffenseCompletionEvidenceTask]:
    return [OffenseCompletionEvidenceTask()]


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path)
    parser.add_argument('--pak',type=Path)
    parser.add_argument('--write',action='store_true')
    args=parser.parse_args()
    if args.exe:check_mapped(*image(args.exe.read_bytes()))
    if args.pak:check_pak(args.pak)
    expected=expected_packet()
    if args.write:
        if not args.exe or not args.pak:raise ValueError('Writing requires original EXE/PAK validation')
        PACKET.write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n')
    if json.loads(PACKET.read_text()) != expected:
        raise ValueError('Offense packet differs from reviewed evidence')
    print(f'OFFENSE_COMPLETION_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe={bool(args.exe)} original_pak={bool(args.pak)} native_execution=False')


if __name__ == '__main__':main()
