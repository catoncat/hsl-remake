"""Check function getters; execute one-cell coverage and target enumeration.

The coverage builder and enumerator return normally on a bounded 1x1 fixture.
Function-to-mode excerpts are checked statically; no whole spell execution claim.

Registry task skill_target (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_skill_target_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.skill_cost import check_pak as check_skill_pak, canonical_table
from hsltools.registry import NotGeneratable
from hsltools.data.skill_targeting import TABLES, function_bits
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_skill_targets.json'

MAGIC_FRIEND_MASK, SPECIAL_FRIEND_MASK = 0xF62, 0x18F62
ANCHORS = [
    (0x409868,'8b4124c3','Magic function getter reads record+0x24.'),
    (0x409888,'8b4128c3','Special function getter reads record+0x28.'),
    (0x444E9E,'25620f0000','Magic uses the function mask 0xf62.'),
    (0x444EA5,'f7d81bc06afff7d883c002','Convert intersection to target mode2 or3.'),
    (0x44504A,'a9628f0100','Special uses the different function mask 0x18f62.'),
    (0x445053,'c705782c4c0003000000','Special support mask selects mode3.'),
    (0x44507F,'c705782c4c0002000000','Other special functions select mode2.'),
    (0x444F08,'e8d3b1fcff','Magic passes effect range and target mode to the coverage builder.'),
    (0x4450E0,'e8fbaffcff','Special uses the same coverage builder.'),
    (0x41049C,'550141005501410061014100','Coverage modes1/2 exclude0x10000; mode3 excludes0x20000.'),
    (0x410155,'c705506d4c0000000100','First exclusion is pmPlayer from TYPE.H.'),
    (0x410161,'c705506d4c0000000200','Second exclusion is pmEnemy from TYPE.H.'),
    (0x4103CC,'85ca890d606d4c00740e81e10000070081f9000007007551','Center rejects an excluded map mode except full0x70000 marker.'),
    (0x410410,'25000087003d00008500','A separate0x850000 marker test follows the actor lookup.'),
    (0x410432,'881428','Accepted center sets a coverage byte.'),
    (0x410553,'803c39007445','Only nonzero coverage cells are enumerated.'),
    (0x41055F,'e89c72ffff','Enumerator looks up an original actor at the cell.'),
    (0x410579,'390674214183c6043bca7cf4','Repeated actor pointers are excluded from the result list.'),
    (0x410585,'89449500','Append the unique actor pointer.'),
    (0x4105DA,'8b0d541a4c0033c03bca7d0b8b448d0041890d541a4c00','Return one cached target and increment the iterator; exhausted returns zero.'),
]


def fixtures() -> list[dict]:
    return [{'mode':mode,'map_flags':flags,'present':present}
            for mode in [2,3] for flags in [0,0x10000,0x20000,0x40000,0x50000,0x60000,0x70000,0x850000]
            for present in [False,True]]


def expected(case: dict) -> dict:
    flags = case['map_flags']
    excluded = 0x10000 if case['mode']==2 else 0x20000
    accepted = not ((flags & excluded) and (flags & 0x70000)!=0x70000)
    # A visible actor lookup clears the temporary map flag before the special
    # NoMagic marker test. This ordering is kept rather than renamed to a guess.
    if accepted and not case['present'] and flags & 0x870000 == 0x850000:
        accepted = False
    return {'coverage':int(accepted), 'target_found':accepted and case['present']}


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX
    machine = Uc(UC_ARCH_X86,UC_MODE_32)
    machine.mem_map(base,len(mapped))
    machine.mem_write(base,bytes(mapped))
    machine.mem_map(0x10000000,0x20000)
    obj, actor, grid, coverage, range_table, shape, targets = [0x10001000+i*0x1000 for i in range(7)]
    stack,sentinel=0x1001FF00,0x10000000
    def word(addr,value): machine.mem_write(addr,struct.pack('<I',value))
    word(0x4C0934,1); word(0x4C0938,1); word(0x4C0928,grid)
    word(0x476B3C,1); word(0x476B40,1); word(0x4C1B4C,coverage)
    word(0x4C1B58,range_table); word(range_table,shape)
    machine.mem_write(shape,bytes([1,1]))
    word(0x4C1B88,targets); word(0x4C1BC8,actor)
    machine.mem_write(0x4C34C0,bytes(200*4))
    if case['present']: word(0x4C34C0,obj)
    word(obj+4,16); word(obj+8,16); word(obj+0xA4,0)
    word(grid,case['map_flags']); word(actor+0xD8,30)
    actor_before=bytes(machine.mem_read(actor,0x1FC))
    allowed=[(0x4100E0,0x410498),(0x4104D0,0x4105F9),(0x40FDC0,0x4100E0),
             (0x40FC90,0x40FDB3),(0x407800,0x40793C),(0x446B30,0x446B59)]
    steps=0
    def guard(_uc,address,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=address<hi for lo,hi in allowed):
            raise RuntimeError(f'Unexpected target callee: {address:#x}')
    machine.hook_add(UC_HOOK_CODE,guard)
    def call(entry,args):
        machine.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),sentinel,*args))
        machine.reg_write(UC_X86_REG_ESP,stack)
        machine.emu_start(entry,sentinel,count=8192)
        if machine.reg_read(UC_X86_REG_EIP)!=sentinel:
            raise RuntimeError('Target helper failed to return within8192 instructions')
        return machine.reg_read(UC_X86_REG_EAX)
    call(0x4100E0,[obj,16,16,0,case['mode']])
    actual_coverage=machine.mem_read(coverage,1)[0]
    first=call(0x4104D0,[0])
    following=call(0x4104D0,[1])
    predicted=expected(case)
    if actual_coverage!=predicted['coverage'] or first!=(obj if predicted['target_found'] else 0) or following!=0:
        raise ValueError(f'Unexpected native target result: {case}, coverage={actual_coverage}, first={first:#x}')
    if bytes(machine.mem_read(actor,0x1FC))!=actor_before or bytes(machine.mem_read(grid,4))!=struct.pack('<I',case['map_flags']):
        raise ValueError('Target query changed actor/grid truth')
    return {**case,**predicted,'normal_returns':3,'next_target':0,'actor_and_map_unchanged':True,'instructions':steps}


def header_sources() -> dict:
    return {name:hashlib.sha256((TABLES/name).read_bytes()).hexdigest() for name in ['TYPE.H','RANGE.TXT']}


def check_mapped(base: int, mapped: bytes) -> None:
    for addr,encoded,_ in ANCHORS:
        raw=bytes.fromhex(encoded)
        if bytes(mapped[addr-base:addr-base+len(raw)])!=raw:
            raise ValueError(f'Target instruction differs at {addr:#x}')


def check_headers_in_pak(path: Path) -> dict:
    from hsltools.sources.pak import find_decoded_paks_packages,find_paks_record_by_name,read_paks_record_bytes
    packages=find_decoded_paks_packages(path)
    result={}
    for name in header_sources():
        found=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],'@:\\data\\'+name.lower()))]
        if len(found)!=1: raise ValueError('Source header/range member ambiguous: '+name)
        p,r=found[0]
        raw=read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
        source, imported=canonical_table(raw),canonical_table((TABLES/name).read_bytes())
        if name=='TYPE.H':
            # Existing import also trims one trailing space in a job-name comment.
            # Never alter symbol names, values or internal whitespace.
            source=b'\n'.join(line.rstrip(b' \t') for line in source.split(b'\n'))
            imported=b'\n'.join(line.rstrip(b' \t') for line in imported.split(b'\n'))
        if source!=imported: raise ValueError('Original source differs: '+name)
        result[name]=hashlib.sha256(raw).hexdigest()
    return result


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256')!=EXE_SHA or packet.get('sources')!=header_sources() or packet.get('native_execution') is not True:
        raise ValueError('Target evidence identity differs')
    if packet.get('instruction_anchors')!=[{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS]:
        raise ValueError('Target evidence anchors differ')
    if len(packet.get('cases',[]))!=len(fixtures()): raise ValueError('Target fixtures missing')
    for saved,case in zip(packet['cases'],fixtures()):
        if any(saved.get(k)!=v for k,v in {**case,**expected(case)}.items()) or saved.get('normal_returns')!=3 or saved.get('next_target')!=0 or not saved.get('actor_and_map_unchanged') or not 0<saved.get('instructions',0)<=24576:
            raise ValueError('Target result/return differs')
    bits=function_bits()
    expected_modes={name:{'magic':3 if bit&MAGIC_FRIEND_MASK else 2,'special':3 if bit&SPECIAL_FRIEND_MASK else 2} for name,bit in bits.items()}
    if packet.get('source_function_modes')!=expected_modes: raise ValueError('Function mode mapping differs')


def execute_packet(exe: Path, pak: Path | None = None) -> dict:
    """Run the bounded original builder/enumerator on the documented EXE and assemble the packet.
    The archive_headers field needs the decoded PAK directory (legacy --pak); without it the
    registry cannot regenerate the tracked packet and reports NotGeneratable."""
    if pak is None:
        raise NotGeneratable('skill_target: regeneration needs the decoded PAK directory; the registry passes only the EXE, so call hsltools.probes.skill_target.execute_packet(exe, pak) and write PACKET')
    check_skill_pak(pak)
    archive=check_headers_in_pak(pak)
    base,mapped=image(exe.read_bytes()); check_mapped(base,mapped)
    packet={'schema':'hsl_skill_targets.v1','evidence_tier':'static-derived','exe_sha256':EXE_SHA,
            'sources':header_sources(),'archive_headers':archive,'native_execution':True,
            'instruction_anchors':[{'address':hex(a),'bytes':b,'meaning':m} for a,b,m in ANCHORS],
            'source_function_modes':{name:{'magic':3 if bit&MAGIC_FRIEND_MASK else 2,'special':3 if bit&SPECIAL_FRIEND_MASK else 2} for name,bit in function_bits().items()},
            'cases':[execute(base,mapped,c) for c in fixtures()],
            'limits':['1x1 synthetic coverage/roster, original full builder/enumerator returns with original callees; no stubs.',
                      'Function-to-mode mapping is static-reviewed, not a full spell dispatcher execution.',
                      'Large actor footprint, obstacles, directional propagation, special NoMagic flag lifecycle, AI mode selection and all support effects remain outside these fixtures.',
                      'Product supports exact Attack-only/single-target effects and current explicit battle roles; other functions fail rather than silently becoming damage.']}
    return packet


def summary_line(packet: dict, executed_now: bool, original_pak: bool = False) -> str:
    return f'SKILL_TARGET_NATIVE_PASS cases={len(fixtures())} executed_now={executed_now} original_pak={original_pak}'


TASK = ProbeTask('skill_target', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
