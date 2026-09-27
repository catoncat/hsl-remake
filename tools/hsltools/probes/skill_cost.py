"""Bounded original MP/ST getters, affordability functions and MP debit block.

Getters and affordability functions return normally. The MP debit is explicitly
a bounded block, not a completed spell function. No callee is stubbed.

Registry task skill_cost (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_skill_cost_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_skill_resources.json'

TABLES = ROOT / 'content/imported/hsl/global/tables'
ARCHIVE_SOURCES = {
    'MAGIC.TXT':'aa7474108f0d86e21e86673354336c76dec50768b31b569346691c790d473de3',
    'SPECIAL.TXT':'ca284fc31eb5a0c093d17a900f38636aa88e922853425f1f8c2fff7c8c6ceb5c',
    'ITEM.TXT':'db1d59b055244b1f54b5f42d31af1617d7b505f6a1c927be797ef0c7031529c3',
}
ANCHORS = [
    (0x44D571, '6860924700', 'Load special sections into the special table family.'),
    (0x44D699, '6848924700', 'SPECIAL numeric parser reads expend.'),
    (0x44D6B3, '894710', 'Store special expend at record+0x10.'),
    (0x44D9D4, '68a4924700', 'Load magic sections into the magic table family.'),
    (0x44DB06, '6848924700', 'MAGIC numeric parser reads expend.'),
    (0x44DB20, '894310', 'Store magic expend at record+0x10.'),
    (0x479248, '657870656e6400', 'Original NUL-terminated field name expend.'),
    (0x409899, 'a02c4c00', 'Magic getter uses table-of-groups 0x4c2ca0.'),
    (0x4098A8, '8b4110c3', 'Magic cost getter returns raw expend.'),
    (0x409998, '8b41108d0480c1e002c3', 'Special cost getter multiplies raw expend by 20.'),
    (0x409020, 'd1fe', 'Affordability halves MP cost without a minimum-one adjustment.'),
    (0x409022, '8b87e00000003bc6', 'Compare current MP with eligibility threshold.'),
    (0x409056, '8b4a108d1489', 'Special affordability also begins with expend times five.'),
    (0x409060, 'c1e202', 'Special affordability completes the times-20 conversion.'),
    (0x40E294, '6a0250e8a4ffffff', 'MP half predicate requests effect bit2 through the shared helper.'),
    (0x40E25E, '858c968c010000', 'Effect predicate tests actor+0x18c.'),
    (0x448709, '8b91a00000008bb08c0100000bf289b08c010000', 'Equipment application ORs item+0xa0 into actor+0x18c.'),
    (0x478A34, '6d705f7573655f68616c6600', 'Original field name mp_use_half.'),
    (0x447DDF, '68348a4700', 'ITEM parser requests mp_use_half.'),
    (0x447DF4, '8b4424100c0289442410', 'Nonzero mp_use_half sets effect bit2.'),
    (0x4481B1, '89843aa0000000', 'Store the effect word in item+0xa0.'),
    (0x442B99, 'e8f26cfcff', 'Magic execution reads the same raw cost getter.'),
    (0x442BAD, '8bc6992bc2d1f88bf07505be01000000', 'Magic debit halves with truncation and enforces a minimum of one.'),
    (0x442BC1, '8b98e00000002bde8998e0000000', 'Subtract charge once from current MP.'),
    (0x44529E, 'e8dd46fcff', 'Player special execution calls the ST cost getter.'),
    (0x4452AF, '89afe8000000', 'Player special stores remaining ST at actor+0xe8.'),
    (0x441CF3, 'e8887cfcff', 'The second special execution path uses the same getter.'),
    (0x441D00, '2981e8000000', 'Second special execution subtracts from actor+0xe8.'),
]


def source_tables() -> dict:
    return {name: hashlib.sha256((TABLES/name).read_bytes()).hexdigest()
            for name in ['MAGIC.TXT', 'SPECIAL.TXT', 'ITEM.TXT']}


def canonical_table(raw: bytes) -> bytes:
    # Existing tracked imports use LF and SPECIAL omits one terminal empty line.
    # Nothing inside a table row, including whitespace/comments, is rewritten.
    return raw.replace(b'\r\n',b'\n').rstrip(b'\n')+b'\n'


def check_pak(path: Path) -> None:
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    packages=find_decoded_paks_packages(path)
    for name in source_tables():
        member='@:\\data\\'+name.lower()
        found=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],member))]
        if len(found)!=1:
            raise ValueError('Missing or ambiguous source '+member)
        p,r=found[0]
        raw=read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
        if hashlib.sha256(raw).hexdigest()!=ARCHIVE_SOURCES[name] or canonical_table(raw)!=canonical_table((TABLES/name).read_bytes()):
            raise ValueError('Original PAK table differs: '+name)


def cases() -> list[dict]:
    result = []
    for channel in ['magic', 'special']:
        for half in ([False, True] if channel == 'magic' else [False]):
            for raw in [0, 1, 3, 6]:
                threshold = raw*20 if channel == 'special' else (raw//2 if half else raw)
                for available in sorted({max(0, threshold-1), threshold, threshold+1}):
                    result.append({'channel':channel, 'expend':raw, 'half_mp':half, 'available':available})
    return result


def expected(case: dict) -> dict:
    raw, channel = case['expend'], case['channel']
    cost = raw*20 if channel == 'special' else raw
    required = cost//2 if case['half_mp'] else cost
    charge = max(1, cost//2) if case['half_mp'] else cost
    return {'base_cost':cost, 'required':required, 'charge':charge,
            'affordable':int(case['available'] >= required),
            'remaining_if_debited':case['available']-charge}


def run_case(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX, UC_X86_REG_ESI
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x20000)
    obj, actor, group, record = 0x10001000, 0x10002000, 0x10003000, 0x10004000
    stack, sentinel = 0x1001FF00, 0x10000000
    machine.mem_write(0x4C1BC8, struct.pack('<I', actor))
    machine.mem_write(obj+0xA4, bytes(4))
    machine.mem_write(actor+0x18C, struct.pack('<I', 2 if case['half_mp'] else 0))
    for offset in [0xE0, 0xE8]:
        machine.mem_write(actor+offset, struct.pack('<i', case['available']))
    table = 0x4C2CA0 if case['channel'] == 'magic' else 0x4C3920
    machine.mem_write(table+4, struct.pack('<I', group))
    machine.mem_write(group+8, struct.pack('<I', record))
    machine.mem_write(record+0x10, struct.pack('<i', case['expend']))
    initial_actor = bytes(machine.mem_read(actor, 0x1FC))
    allowed = [(0x408FE0, 0x409038), (0x409040, 0x409089),
               (0x409890, 0x4098AC), (0x409980, 0x4099A2),
               (0x40E240, 0x40E26E), (0x40E290, 0x40E2A0),
               (0x442BA9, 0x442BCF)]
    steps = 0

    def guard(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= address < hi for lo, hi in allowed):
            raise RuntimeError(f'Unexpected original callee: {address:#x}')

    machine.hook_add(UC_HOOK_CODE, guard)

    def call(entry, args):
        machine.mem_write(stack, struct.pack('<'+'I'*(len(args)+1), sentinel, *args))
        machine.reg_write(UC_X86_REG_ESP, stack)
        machine.emu_start(entry, sentinel, count=512)
        if machine.reg_read(UC_X86_REG_EIP) != sentinel:
            raise RuntimeError('Cost helper did not return within 512 instructions')
        return machine.reg_read(UC_X86_REG_EAX)

    base_cost = call(0x409890 if case['channel']=='magic' else 0x409980, [1,2])
    affordable = call(0x408FE0 if case['channel']=='magic' else 0x409040, [obj,1,2])
    if bytes(machine.mem_read(actor,0x1FC)) != initial_actor:
        raise ValueError('Affordability unexpectedly changed actor memory')
    output = expected(case)
    if base_cost != output['base_cost'] or affordable != output['affordable']:
        raise ValueError('Original cost/eligibility differs from the independent model')
    result = {**case, 'base_cost':base_cost, 'affordable':affordable,
              'normal_helper_returns':2, 'eligibility_actor_unchanged':True}
    if case['channel']=='magic':
        # Enter after the real half-MP predicate. EAX is its proven boolean,
        # ESI the getter cost; stop immediately after the MP store, before effects.
        machine.reg_write(UC_X86_REG_EAX, int(case['half_mp']))
        machine.reg_write(UC_X86_REG_ESI, base_cost)
        machine.mem_write(stack+0x14, struct.pack('<I',actor))
        machine.reg_write(UC_X86_REG_ESP,stack)
        machine.emu_start(0x442BA9,0x442BCF,count=128)
        if machine.reg_read(UC_X86_REG_EIP)!=0x442BCF:
            raise RuntimeError('MP debit block exceeded its bound')
        remaining = struct.unpack('<i',machine.mem_read(actor+0xE0,4))[0]
        expected_actor = bytearray(initial_actor)
        struct.pack_into('<i',expected_actor,0xE0,output['remaining_if_debited'])
        if remaining != output['remaining_if_debited'] or bytes(machine.mem_read(actor,0x1FC)) != expected_actor:
            raise ValueError('Original MP debit changed unexpected state')
        result['debit_block'] = {'start':'0x442ba9','stop':'0x442bcf',
                                 'remaining_mp':remaining,'full_spell_function_return':False}
    result['instructions'] = steps
    return result


def check_mapped(base: int, mapped: bytes) -> None:
    for address, encoded, _ in ANCHORS:
        raw = bytes.fromhex(encoded)
        if bytes(mapped[address-base:address-base+len(raw)]) != raw:
            raise ValueError(f'Skill resource anchor differs at {address:#x}')


def check_packet(packet: dict) -> None:
    anchors=[{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS]
    if packet.get('exe_sha256')!=EXE_SHA or packet.get('sources')!=source_tables() or packet.get('archive_sources')!=ARCHIVE_SOURCES or packet.get('instruction_anchors')!=anchors:
        raise ValueError('Skill resource sources or anchors differ')
    if packet.get('native_execution') is not True or len(packet.get('cases',[]))!=len(cases()):
        raise ValueError('Native cost execution cases missing')
    for saved, case in zip(packet['cases'],cases()):
        model=expected(case)
        if any(saved.get(key)!=value for key,value in case.items()) or saved['base_cost']!=model['base_cost'] or saved['affordable']!=model['affordable']:
            raise ValueError('Cost fixture/result differs')
        if saved['normal_helper_returns']!=2 or not saved['eligibility_actor_unchanged'] or not 0<saved['instructions']<=1152:
            raise ValueError('Cost helper return boundary differs')
        if case['channel']=='magic' and (saved['debit_block']['remaining_mp']!=model['remaining_if_debited'] or saved['debit_block']['full_spell_function_return'] is not False):
            raise ValueError('MP debit block boundary/result differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original helpers on the documented EXE and assemble the packet
    (the optional --pak archive comparison is check_pak, not packet content)."""
    base,mapped=image(exe.read_bytes())
    check_mapped(base,mapped)
    packet={'schema':'hsl_skill_resources.v1','evidence_tier':'static-derived',
            'exe_sha256':EXE_SHA,'sources':source_tables(),'archive_sources':ARCHIVE_SOURCES,
            'source_normalization':'CRLF to LF and collapse trailing LF only; table body remains unchanged.',
            'native_execution':True,
            'instruction_anchors':[{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS],
            'cases':[run_case(base,mapped,c) for c in cases()],
            'limits':['Synthetic memory, original helper instructions, bounded calls without stubs; no original gameplay.',
                      'MP debit is an explicitly bounded internal block, not a normal whole spell function return.',
                      'Half-cost eligibility may be zero while debit is one. Product refuses charges beyond available resources.',
                      'Full skill ownership, target/state conditions, ST gain/cap, effects and other passives remain outside this packet.']}
    return packet


def summary_line(packet: dict, executed_now: bool, original_pak: bool = False) -> str:
    return f'SKILL_RESOURCE_NATIVE_PASS cases={len(cases())} executed_now={executed_now} original_pak={original_pak}'


TASK = ProbeTask('skill_cost', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
