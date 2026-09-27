"""Verify reviewed inventory/equipment instruction bytes; never execute the EXE.

Default checks the curated packet offline. --exe additionally verifies the full
original file identity and reads its PE sections to compare all anchored bytes.

Registry task inventory_equipment_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_inventory_equipment_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_inventory_equipment.json'
# Human-reviewed bounded excerpts, not an automatically inferred decompilation.
ANCHORS = [
    (0x436E4C, '8d8a38010000', 'Inventory starts at actor+0x138.'),
    (0x436E52, '833900740c', 'Insert branches on empty code 0, not matching item code.'),
    (0x436E57, '4083c10483f8087cf2', 'Advance one DWORD until exactly eight slots have been checked.'),
    (0x436E60, '33c0c3', 'Full insert returns 0 without a slot write.'),
    (0x436E67, '898c8238010000b801000000c3', 'Write new code to first empty slot and return 1.'),
    (0x436E9E, 'b9070000002bca7822', 'Removal copies 7-index following slots; oversized index exits.'),
    (0x436EAD, '8db4903c0100008dbc9038010000f3a5', 'Copy following DWORDs one slot left with rep movsd.'),
    (0x436EBF, 'c7805401000000000000c3', 'Clear last slot at actor+0x154, then return.'),
    (0x436EE7, '8b848a54010000c3', 'Tail helper returns the last item code.'),
    (0x436F68, '3de80300007421', 'Job 1000 bypasses the ordinary job mask gate.'),
    (0x436F84, '8b86a8000000d3e285c2746a', 'Check item+0xa8 against the job bit; zero intersection rejects.'),
    (0x436F94, '83f8057761', 'Unsigned slot index above 5 rejects.'),
    (0x436F99, 'b902000000', 'CL=2 is retained for the old-equipment blocking-bit test.'),
    (0x437004, 'a56f4300ac6f4300b46f4300bc6f4300c46f4300c46f4300', 'Six slot/type dispatch destinations; accessories share the type-6 case.'),
    (0x436FCA, '8bbc85ec000000', 'Keep old equipped code in EDI.'),
    (0x436FE0, '848c32a4000000740a', 'Old item+0xa4 bit 1 must be clear before writing replacement.'),
    (0x436FF3, '899c85ec0000008bc75f5e5d5bc3', 'Write new equipped code then return old code from EDI.'),
    (0x437060, 'f6c3025b740333c0c3', 'Unequip uses the same bit; blocked returns 0.'),
    (0x437069, 'c78491ec00000000000000c3', 'Allowed unequip clears selected slot and returns retained old code.'),
    (0x47886C, '74616b655f6f666600', 'Original NUL-terminated field name: take_off.'),
    (0x4481D7, '686c884700e8efe4ffff', 'Loader looks up take_off through the numeric field helper.'),
    (0x4481EA, '740a8b4424100c0289442410', 'Nonzero take_off adds flag value 2.'),
    (0x448207, '899439a4000000', 'Store assembled flags at item+0xa4.'),
    (0x4292AA, 'a3e41c4c00e8ccdb0000', 'UI holds selected code at 0x4c1ce4, then removes its inventory slot.'),
    (0x429283, '8b54241c5255e8a2db0000', 'UI inserts its previously held code through the same first-empty helper.'),
    (0x429E18, 'a1e41c4c005585c07452', 'UI reads held code; zero selects unequip, nonzero replacement.'),
    (0x429E24, 'e807d1000083c40c83f8ff', 'UI calls replacement setter and tests return against -1.'),
    (0x429E3F, 'a3e41c4c00', 'Successful replacement makes old equipment the held code.'),
    (0x429E59, 'e8e2e90100', 'Successful replacement calls unified stat refresh.'),
    (0x429E75, 'e8a6d1000083c408a3e41c4c00', 'Unequip result becomes the held code.'),
    (0x429EA1, 'e89ae90100', 'Successful unequip calls unified stat refresh.'),
]


def instruction_anchors() -> list[dict]:
    return [{'address': hex(address), 'bytes': encoded, 'reviewed_meaning': meaning}
            for address, encoded, meaning in ANCHORS]


def check_mapped(base: int, mapped: bytes | bytearray) -> None:
    for address, encoded, _ in ANCHORS:
        expected = bytes.fromhex(encoded)
        offset = address - base
        if offset < 0 or offset + len(expected) > len(mapped):
            raise ValueError(f'Inventory evidence address outside image: {address:#x}')
        if bytes(mapped[offset:offset + len(expected)]) != expected:
            raise ValueError(f'Inventory instruction bytes differ at {address:#x}')


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256') != EXE_SHA or packet.get('instruction_anchors') != instruction_anchors():
        raise ValueError('Inventory packet does not match the reviewed instruction anchors')
    if packet['layout']['inventory_capacity'] != 8 or packet['layout']['inventory_offset'] != '0x138':
        raise ValueError('Inventory layout contradicts the reviewed loop')
    if packet['verification_boundary']['new_native_execution'] is not False:
        raise ValueError('Static evidence checker cannot claim native execution')


class InventoryEquipmentEvidenceTask(ScriptCheckTask):
    name = 'inventory_equipment_evidence'
    family = 'evidence'
    inputs = ()
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_inventory_equipment_evidence.py',)
    scripts = ('tools/hsltools/evidence/inventory_equipment.py',)

    def verify(self, ctx: Context) -> None:
        packet = json.loads(PACKET.read_text())
        check_packet(packet)
        print(f'INVENTORY_STATIC_EVIDENCE_PASS anchors={len(ANCHORS)} original_bytes_checked=False native_execution=False')


def tasks() -> list[InventoryEquipmentEvidenceTask]:
    return [InventoryEquipmentEvidenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, help='Read this original PE; no code is executed')
    parser.add_argument('--write-anchors', action='store_true', help='Save reviewed anchors after a successful original-file check')
    args = parser.parse_args()
    packet = json.loads(PACKET.read_text())
    if args.exe:
        base, mapped = image(args.exe.read_bytes())
        check_mapped(base, mapped)
    if args.write_anchors:
        if not args.exe:
            raise ValueError('--write-anchors requires --exe identity and byte checks')
        packet['instruction_anchors'] = instruction_anchors()
        PACKET.write_text(json.dumps(packet, ensure_ascii=False, indent=2) + '\n')
    check_packet(packet)
    print(f'INVENTORY_STATIC_EVIDENCE_PASS anchors={len(ANCHORS)} original_bytes_checked={bool(args.exe)} native_execution=False')


if __name__ == '__main__':
    raise SystemExit(main())
