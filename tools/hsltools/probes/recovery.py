"""Bounded original HP/MP auto-recovery arithmetic and no-effect full returns.

Effective branches stop before the original number renderer. The MP suffix has
an explicit prepared caller frame; it is never relabelled a complete invocation.

Registry task recovery (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_recovery_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_resource_recovery.json'

SEEDS=[1,3,7,19,101,257,4095,65535,0x76543210]
ANCHORS=[(0x447ec4,68,'ITEM hp_auto_restore and mp_auto_restore independently OR effect bits100/200.'),
         (0x40e310,19,'HP automatic recovery getter uses effect bit100.'),
         (0x40e330,19,'MP automatic recovery getter uses effect bit200.'),
         (0x40e47e,95,'HP amount: rand6+5 percent; add3 only when truncated amount is below3; cap missing HP.'),
         (0x40e506,95,'MP amount: rand6+3 percent; add2 only when truncated amount is below3; cap missing MP.'),
         (0x40e4c5,32,'HP number is type2 at owner y-48; subsequent MP display is delayed by40 source ticks.'),
         (0x40e54d,42,'MP number is type3, uses preceding delay, then contributes40 source ticks.'),
         (0x443bba,85,'Player final tail invokes recovery then waits before kill-chain/status/queue cleanup.'),
         (0x44202d,141,'AI final tail has the same recovery call before status/queue cleanup.'),
         (0x4094c0,29,'HP-to-MP transfer checks a different effect word; its positive branch remains unsupported.')]


def cases():
    rows=[]
    for kind in ('hp','mp'):
        for maximum in (1,2,19,30,39,60,100,400,999):
            for current in sorted({1 if kind=='hp' else 0,maximum//2 or 1,maximum-1 if maximum>1 else maximum,maximum}):
                for seed in SEEDS:
                    rows.append(dict(kind=kind,maximum=maximum,current=current,enabled=True,seed=seed,delay=40 if kind=='mp' else 0))
        for maximum in (1,30,400):
            rows.append(dict(kind=kind,maximum=maximum,current=1,enabled=False,seed=19,delay=0))
    return rows


def amount(kind,maximum,current,roll):
    value=maximum*(roll+(5 if kind=='hp' else 3))//100
    if value<3:value+=3 if kind=='hp' else 2
    return min(maximum-current,value)


def execute(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBX,UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001fe00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    kind=case['kind'];offset=0xd8 if kind=='hp' else 0xe0
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+4,160);put(obj+8,260)
    for off,value in [(0xd8,17),(0xdc,100),(0xe0,11),(0xe4,60),(0xe8,20),(0x88,37),(0x24,3),(0x30,0x70003),(0x34,2)]:put(actor+off,value)
    put(actor+offset,case['current']);put(actor+offset+4,case['maximum'])
    put(actor+0x18c,(0x100 if kind=='hp' else 0x200) if case['enabled'] else 8)
    put(0x4c1e8c,1);put(0x4c3044,case['seed']);put(0x4c3040,0x87654321)
    entry=0x40e430 if kind=='hp' else 0x40e4e5
    stops=[0x40e4d1,0x40e4e5] if kind=='hp' else [0x40e55c,0x40e56b]
    if kind=='hp':m.mem_write(stack,struct.pack('<2I',stop,obj))
    else:
        put(stack+0x18,actor);put(stack+0x10,case['delay'])
        m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EBX,actor);m.reg_write(UC_X86_REG_EDI,212)
    m.reg_write(UC_X86_REG_ESP,stack)
    before=bytes(m.mem_read(actor,0x1fc));steps=0;draws=[];returning=[]
    def guard(_m,address,_size,_data):
        nonlocal steps
        if address in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=address<hi for lo,hi in [(0x40e240,0x40e270),(0x40e310,0x40e343),(0x40e430,0x40e56b),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]):raise ValueError(f'Unreviewed recovery callee {address:#x}')
        if returning and returning[-1][0]==address:
            _,bound=returning.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if address==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);returning.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,stop,count=4096)
    end=m.reg_read(UC_X86_REG_EIP)
    if end not in stops or returning:raise ValueError('Recovery prefix exceeded boundary')
    active=case['enabled'] and case['current']<case['maximum']
    if len(draws)!=int(active) or any(d['bound']!=6 or not 0<=d['value']<6 for d in draws):raise ValueError('Recovery RNG call shape differs')
    gain=amount(kind,case['maximum'],case['current'],draws[0]['value']) if active else 0
    expected=bytearray(before);struct.pack_into('<I',expected,offset,case['current']+gain)
    if bytes(m.mem_read(actor,0x1fc))!=expected:raise ValueError('Recovery changed unexpected actor fields')
    numbers=[]
    if end==stops[0]:
        sp=m.reg_read(UC_X86_REG_ESP);numbers=list(struct.unpack('<6I',m.mem_read(sp,24)))
        if numbers!=[160,212,gain,0,2 if kind=='hp' else 3,case['delay']]:raise ValueError('Source number arguments differ')
    elif gain:raise ValueError('Positive recovery omitted display')
    return dict(input=case,entry=hex(entry),stop_address=hex(end),normal_return=False,instructions=steps,
                native=dict(after=get(actor+offset),amount=gain,number_args=numbers),draws=draws,only_resource_changed=True)


def no_effect(base,mapped,flags):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);actor,obj,stack,stop=0x10004000,0x10001000,0x1001fe00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v))
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(actor+0x18c,flags)
    for off,v in [(0xd8,30),(0xdc,30),(0xe0,0),(0xe4,0)]:put(actor+off,v)
    before=bytes(m.mem_read(actor,0x1fc));steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=address<hi for lo,hi in [(0x40e210,0x40e343),(0x40e430,0x40e581),(0x4094c0,0x4095d7)]):raise ValueError('No-effect branch reached RNG/renderer')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<2I',stop,obj));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x40e430,stop,count=4096)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or m.reg_read(UC_X86_REG_EAX)!=0 or before!=bytes(m.mem_read(actor,0x1fc)):raise ValueError('No-effect recovery did not return unchanged')
    return dict(effects=flags,normal_return=True,value=0,instructions=steps,no_rng_or_renderer=True)


def check(p):
    if p.get('schema')!='hsl_resource_recovery_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Recovery identity differs')
    if p['sources']!={n:digest((TABLES/n).read_bytes()) for n in ('ITEM.TXT','TYPE.H')}:raise ValueError('Recovery source changed')
    if [r['input'] for r in p['prefixes']]!=cases():raise ValueError('Recovery cases differ')
    for row in p['prefixes']:
        c=row['input'];active=c['enabled'] and c['current']<c['maximum'];draws=row['draws']
        if len(draws)!=int(active) or any(d['bound']!=6 or not 0<=d['value']<6 for d in draws):raise ValueError('Recovery draws invalid')
        gain=amount(c['kind'],c['maximum'],c['current'],draws[0]['value']) if active else 0
        args=[160,212,gain,0,2 if c['kind']=='hp' else 3,c['delay']] if gain else []
        stop=(0x40e4d1 if gain else 0x40e4e5) if c['kind']=='hp' else (0x40e55c if gain else 0x40e56b)
        if row['native']!=dict(after=c['current']+gain,amount=gain,number_args=args) or row['normal_return'] is not False or row['stop_address']!=hex(stop) or not row['only_resource_changed'] or not 0<row['instructions']<4096:raise ValueError('Recovery prefix differs')
    if [r['effects'] for r in p['no_effect_returns']]!=[0,8,256,512,768,778]:raise ValueError('Recovery return cases differ')
    if any(r['value']!=0 or not r['normal_return'] or not r['no_rng_or_renderer'] for r in p['no_effect_returns']):raise ValueError('Recovery return unproved')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in p['anchors']]!=ANCHORS:raise ValueError('Recovery anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in p['anchors']))).hexdigest()!='b72f92d29816fcf270943caa9c8a3276165c38660d7102303008631f19b871af':raise ValueError('Original recovery instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_resource_recovery_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
           sources={n:digest((TABLES/n).read_bytes()) for n in ('ITEM.TXT','TYPE.H')},
           prefixes=[execute(base,mapped,c) for c in cases()],no_effect_returns=[no_effect(base,mapped,f) for f in [0,8,256,512,768,778]],
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           limits=['Effective HP prefix and prepared-frame MP suffix stop before number drawing; no stubs or forged full returns.',
                   'Six inactive/full-resource calls return completely with unchanged actor and no RNG/renderer.',
                   'Source renderer type2/3 and delay40 are arguments, not a recovered wall clock or audio cue.',
                   'HP transfer uses the other effect word and is not enabled. Whole global RNG and dispatcher remain separate.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    rolls=sorted({d['value'] for r in p['prefixes'] for d in r['draws']})
    return f'RESOURCE_RECOVERY_NATIVE_PASS prefixes={len(p["prefixes"])} full_returns=6 rolls={rolls} executed_now={executed_now}'


TASK = ProbeTask('recovery', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
