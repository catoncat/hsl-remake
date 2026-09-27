"""Check reviewed Give instruction paths and publish an independent slot model.

This is static evidence. It reads the hash-checked original PE and PAK; it does
not execute native functions. Model examples are explicitly synthetic.

Registry task give_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_give_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from hsltools.evidence.item_action import SOURCE_SHA, check_pak
from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_give_exchange.json'
ROUTES = {110: 0x444B8A, 111: 0x4447A7, 112: 0x444BC7, 113: 0x444C27,
          114: 0x444D9C, 115: 0x4447A7, 116: 0x444DEF, 4: 0x4454A5}
ANCHORS = [
    (0x43BA0B, '66c78694000000010081c900500040898e80000000', 'Mode7 root selects inventory and sets 0x40005000.'),
    (0x43BA97, '8b9f8000000080cf50e922ffffff', 'Mode7 inventory child sets 0x5000 before the shared writer.'),
    (0x438C53, '85ff0f8ce201000083ff080f8dd90100008b84bb38010000', 'Reject negative or >=8 clicked indices, then read that exact item slot.'),
    (0x438C92, '8bd981e3001000007523', 'Give flag0x1000 bypasses the ordinary tail/fullness shortcut: occupied slots can be exchanged even with free space.'),
    (0x438CBF, '8b15e41c4c00c705e41c4c000000000085c089542420741ba3e41c4c00a1e42a4c00578b0c85c0344c0051e891e1ffff83c408a1e42a4c008b542420528b0c85c0344c0051e827e1ffff83c408', 'Save incoming hold; occupied target becomes the new hold and is removed/compacted; insert incoming at first empty slot. No stack or same-code special case.'),
    (0x438D0C, '85db741956e8fb61020083c40466ff808c00000066c78096000000ffff', 'Mode7 requests receiver-window closure after one slot transaction.'),
    (0x438D63, '85c00f8488000000f6c510751df6c5207435', 'Without a held item, empty slots are inert; Give bypasses the Use-only type filter.'),
    (0x438D8D, '56e87e61020083c40466ff808c00000066c78096000000ffff8b4424708b0de42a4c0057a3e41c4c008b148dc0344c0052e8bde0ffff', 'Owner selection closes its window, saves the selected code as hold and removes that exact slot.'),
    (0x444D9C, '8b0de41c4c00a1ec1c4c0033d2890d882c4c00668b90a000000068000000806a0052e8cd16ffffa1ec1c4c0033c9566a07668b88a000000050890de42a4c00e80067ffff83c41866ff868c000000e9b8f9ffff', 'Save outgoing code in0x4c2c88; open mode7 for target0x4c1cec, retaining owner as parent.'),
    (0x444DEF, 'a1e41c4c008b0d882c4c003bc874138b86800000000bc3898680000000a1e41c4c0085c00f8451ffffff5056e81020ffffc705e41c4c000000000083c40866c7868c0000006e00e96cf9ffff', 'Compare returned hold to outgoing code, OR action flag only when different; return nonzero hold to owner, clear hold and repeat state110.'),
    (0x444B8A, '33c96800000080668b8ea00000006a0051e8f018ffff33d256668b96a00000006a07568915e42a4c00e82869ffff83c41866ff868c000000e9e0fbffff', 'State110 opens the owner inventory in mode7 again.'),
    (0x444BFF, '8b868000000085c3741025fffffeff898680000000e98c08000066c7868c0000000300e980fbffff', 'Closing owner selection ends the action only when flag0x10000 is set; otherwise return to item menu.'),
    (0x443955, 'bb00000100bd00010000', 'EBX is0x10000, EBP is0x100 in the player dispatcher.'),
    (0x444C4E, 'e80da9fcff83c40885c074448b15901a4c00a18c1a4c005250e8d4cffcff83c40885c3742b8b0d901a4c008b158c1a4c005152e87a2bfcff83c408a3ec1c4c0085c0740c66ff868c000000', 'Target selection requires reachability, cell flag0x10000 and a non-null object. Complete flag-to-role mapping is not established here.'),
    (0x444D3B, '8b15001b4c00a1e41c4c0081e2ffffdfff85c08915001b4c0074145056e8d320ffff83c408c705e41c4c000000000066c7868c0000006e00e92ffaffff', 'Target cancellation returns held item through first-empty insertion, clears hold and repeats state110 without setting action-used flag.'),
]


def exchange(sender: list[int], index: int, receiver: list[int], target: int) -> dict:
    """Independent synthetic reference for the reviewed receive/return chain."""
    if any(len(bag) != 8 or any(type(x) is not int or x < 0 for x in bag) for bag in (sender, receiver)):
        raise ValueError('Expected two eight-slot integer inventories')
    if not 0 <= index < 8 or not 0 <= target < 8 or sender[index] == 0:
        raise ValueError('Invalid occupied source or target slot')
    sent, returned = sender[index], receiver[target]
    out = sender[:index] + sender[index+1:] + [0]
    incoming = receiver[:target] + receiver[target+1:] + [0] if returned else receiver.copy()
    incoming[incoming.index(0)] = sent
    if returned:
        out[out.index(0)] = returned
    return {'sender': out, 'receiver': incoming, 'sent': sent, 'returned': returned,
            'action_used': returned != sent}


def expected_packet() -> dict:
    fixtures = [
        ('give_to_empty', [241, 246, 241, 0, 0, 0, 0, 0], 2, [246, 0, 0, 0, 0, 0, 0, 0], 1),
        ('full_exchange', [241, 246, 241, 241, 241, 241, 241, 241], 0, [246, 241, 241, 241, 241, 241, 241, 241], 0),
        ('occupied_with_room', [241, 246, 241, 0, 0, 0, 0, 0], 2, [246, 241, 0, 0, 0, 0, 0, 0], 0),
        ('same_code_reorders_without_new_charge', [241, 246, 0, 0, 0, 0, 0, 0], 0, [241, 246, 0, 0, 0, 0, 0, 0], 0),
        ('hole_uses_first_empty', [241, 246, 0, 0, 0, 0, 0, 0], 0, [0, 246, 0, 0, 0, 0, 0, 0], 7),
        ('important_can_transfer', [281, 241, 0, 0, 0, 0, 0, 0], 0, [246, 0, 0, 0, 0, 0, 0, 0], 0),
    ]
    return {
        'schema': 'hsl_give_exchange_static.v1', 'evidence_tier': 'static-derived',
        'exe_sha256': EXE_SHA, 'source_member': '@:\\data\\obj-051.obs', 'source_sha256': SOURCE_SHA,
        'native_execution': False, 'synthetic_examples_are_native_results': False,
        'instruction_anchors': [{'address': hex(a), 'bytes': b, 'reviewed_meaning': m} for a,b,m in ANCHORS],
        'routes': {str(s): hex(a) for s,a in ROUTES.items()},
        'session': {'outgoing_global': '0x4c2c88', 'held_global': '0x4c1ce4', 'target_global': '0x4c1cec',
                    'action_flag': '0x10000', 'changed': 'previous_used OR returned_code != outgoing_code',
                    'close': 'end actor if used; otherwise return to item menu',
                    'same_code': 'slot order may change but code comparison does not newly set action flag'},
        'examples': [{'name': name, 'sender': s, 'index': i, 'receiver': r, 'target': t,
                      'expected': exchange(s,i,r,t)} for name,s,i,r,t in fixtures],
        'limits': [
            'No new native execution: the earlier inventory-probe creation was refused; byte checks do not substitute for execution.',
            'Full original target flag-to-role, range, dead/hidden roster filters and movement rollback are not proven here.',
            'Product keeps confirm-before-mutation: cancelling a draft preserves both slot orders exactly, unlike original pickup/first-hole return.',
            'Cancelling the next draft does not undo earlier confirmed exchanges; an already-set session action flag stays set.',
            'Native invalid raw helper indices and corrupt inventories are not supported inputs; product validates before mutation.',
        ],
    }


def check_mapped(base: int, mapped: bytes | bytearray) -> None:
    for address, encoded, _ in ANCHORS:
        expected = bytes.fromhex(encoded)
        offset = address - base
        if offset < 0 or bytes(mapped[offset:offset+len(expected)]) != expected:
            raise ValueError(f'Give instruction bytes differ at {address:#x}')
    for state, entry in ROUTES.items():
        slot = mapped[0x445758-base+state]
        if struct.unpack_from('<I', mapped, 0x445694-base+slot*4)[0] != entry:
            raise ValueError(f'Give dispatcher differs at state{state}')


class GiveEvidenceTask(ScriptCheckTask):
    name = 'give_evidence'
    family = 'evidence'
    inputs = ()
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_give_evidence.py',)
    scripts = ('tools/hsltools/evidence/give.py', 'tools/hsltools/evidence/item_action.py')

    def verify(self, ctx: Context) -> None:
        result = expected_packet()
        if json.loads(PACKET.read_text()) != result:
            raise ValueError('Give packet differs from reviewed evidence')
        print(f'GIVE_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe=False original_pak=False native_execution=False')


def tasks() -> list[GiveEvidenceTask]:
    return [GiveEvidenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--pak', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    if args.exe:
        check_mapped(*image(args.exe.read_bytes()))
    if args.pak:
        check_pak(args.pak)
    result = expected_packet()
    if args.write:
        if not args.exe or not args.pak:
            raise ValueError('Writing evidence requires original EXE and PAK checks')
        PACKET.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    if json.loads(PACKET.read_text()) != result:
        raise ValueError('Give packet differs from reviewed evidence')
    print(f'GIVE_EVIDENCE_PASS anchors={len(ANCHORS)} original_exe={bool(args.exe)} original_pak={bool(args.pak)} native_execution=False')


if __name__ == '__main__':
    raise SystemExit(main())
