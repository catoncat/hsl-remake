"""Original double_attack query and ordinary-series dispatch boundaries.

The flag helper returns normally. Init, innate mapping, next-strike and
post-series branches stop before callbacks, unless a no-effect branch returns.
Source instructions and callees are unmodified; no UI callback is stubbed.

Registry task extra_attack (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_extra_attack_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest, blocks

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_extra_attack.json'

ANCHORS=[(0x447fea,34,'Item double_attack produces effect flag0x8000.'),
         (0x447e1f,33,'Separate action_twice produces flag8; not another strike.'),
         (0x44c46b,26,'Source actor double_attack produces capability0x200.'),
         (0x448747,20,'During equipment application capability0x200 maps to effect0x8000.'),
         (0x442616,43,'Initialize one extra strike before checking counter mode.'),
         (0x442465,30,'Dead target cancels remaining strikes and queued counter.'),
         (0x4424be,38,'Live target with an extra strike restarts animation before final status/ST calls.'),
         (0x442483,28,'Only final nonzero-contribution strike reaches status and stamina callbacks.'),
         (0x4424a3,27,'Counter handoff is returned only after the series finishes.')]


def source():
    return dict(hashes={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT']},
                items=[int(r['code']) for r in blocks((TABLES/'ITEM.TXT').read_bytes(),'item') if int(r.get('double_attack',0))],
                actors=[str(r['code']).zfill(3) for r in blocks((TABLES/'PLAYERS.TXT').read_bytes(),'character') if int(r.get('double_attack',0))])


def fixtures():
    return ([dict(kind='query',effects=f) for f in [0,8,0x200,0x8000,0x8008,0x10000,0x18000]]+
            [dict(kind='innate',effects=e,capability=c) for e in [0,8,0x8000] for c in [0,2,0x200,0x240]]+
            [dict(kind='init',effects=f,counter_mode=c) for f in [0,8,0x8000,0x8008] for c in [False,True]]+
            [dict(kind='settle',remaining=r,target_hp=hp,contribution=p,pending_counter=c)
             for r in [0,1] for hp in [0,20] for p in [0,20] for c in [False,True]])


def expected(c):
    kind=c['kind']
    if kind=='query':return dict(extra=1 if c['effects']&0x8000 else 0)
    if kind=='innate':return dict(effects=c['effects']|(0x8000 if c['capability']&0x200 else 0))
    if kind=='init':return dict(remaining=int(bool(c['effects']&0x8000)),pending_counter=False,phase=0,next='counter_series' if c['counter_mode'] else 'counter_qualification')
    alive=c['target_hp']>0
    if alive and c['remaining']:
        return dict(remaining=0,pending_counter=c['pending_counter'],phase=1,next='additional_animation')
    return dict(remaining=0,pending_counter=c['pending_counter'] if alive and c['contribution'] else False,phase=4,
                next='final_status_and_stamina' if c['contribution'] else ('counter_handoff' if alive and c['pending_counter'] else 'complete'))


def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ECX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);obj,target_obj,roster,stack,sentinel=0x10001000,0x10002000,0x10004000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,roster);put(obj+0xa4,0);put(target_obj+0xa4,1)
    put(roster+0x18c,c.get('effects',0));put(0x4c1e8c,1);put(0x4c3044,7);put(0x4c3040,0x87654321)
    kind=c['kind'];entry=0x4092a0 if kind=='query' else 0x448747 if kind=='innate' else 0x4423c0
    stops=[]
    if kind=='innate':
        m.reg_write(UC_X86_REG_EAX,roster);m.reg_write(UC_X86_REG_ECX,c['capability']);stops=[0x44875b]
    if kind=='init':
        put(0x4c432c,0);put(0x4c2c48,73);put(0x4c4320,0x10000)
        stops=[0x442641,0x4426f2]
    if kind=='settle':
        put(0x4c432c,4);put(0x4c2c48,c['remaining']);put(0x4c4320,0x10000 if c['pending_counter'] else 0)
        put(roster+0x9c,1);put(roster+0x1fc+0x9c,1);put(roster+0x1fc+0xd8,c['target_hp'])
        put(0x4c13fc,c['contribution']);stops=[0x4424e4,0x442487]
    mode=int(c.get('counter_mode',False))|2 # bit2 bypasses irrelevant hit-bonus write, not series state.
    m.mem_write(stack,struct.pack('<5I',sentinel,obj,target_obj,0x10003000,mode));m.reg_write(UC_X86_REG_ESP,stack)
    steps=0;draws=[];returning=[]
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(a<=at<b for a,b in [(0x4092a0,0x4092cc),(0x448747,0x44875b),(0x4423c0,0x442720),(0x40a5d0,0x40a78d),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]):
            raise ValueError(f'Unreviewed series callback {at:#x}')
        if returning and returning[-1][0]==at:
            _,bound=returning.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            esp=m.reg_read(UC_X86_REG_ESP);returning.append((get(esp),get(esp+4)))
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,sentinel,count=4096)
    stop=m.reg_read(UC_X86_REG_EIP);normal=stop==sentinel
    if stop not in [sentinel,*stops] or returning or (normal and m.reg_read(UC_X86_REG_ESP)!=stack+4):raise ValueError('Series boundary exceeded')
    if kind=='query':actual=dict(extra=m.reg_read(UC_X86_REG_EAX))
    elif kind=='innate':actual=dict(effects=get(roster+0x18c))
    else:
        next_step={0x442641:'counter_qualification',0x4426f2:'counter_series',0x4424e4:'additional_animation',0x442487:'final_status_and_stamina'}.get(stop)
        if normal:next_step='counter_handoff' if m.reg_read(UC_X86_REG_EAX)==2 else 'complete'
        actual=dict(remaining=get(0x4c2c48),pending_counter=bool(get(0x4c4320)&0x10000),phase=get(0x4c432c),next=next_step)
    if actual!=expected(c):raise ValueError(f'Series result differs {c}: {actual} vs {expected(c)}')
    return dict(input=c,native=actual,entry=hex(entry),stop_address=hex(stop),normal_return=normal,instructions=steps,draws=draws)


def check(p):
    if p.get('schema')!='hsl_native_extra_attack.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True or p['source']!=source():raise ValueError('Extra attack source identity changed')
    if [r['input'] for r in p['cases']]!=fixtures():raise ValueError('Extra attack cases changed')
    for row in p['cases']:
        c=row['input'];normal=c['kind']=='query' or (c['kind']=='settle' and c['contribution']==0 and (not c['remaining'] or not c['target_hp']))
        stop={'query':'0x10000000','innate':'0x44875b','init':'0x4426f2' if c.get('counter_mode') else '0x442641'}.get(c['kind'])
        if c['kind']=='settle':stop='0x10000000' if normal else '0x4424e4' if c['remaining'] and c['target_hp'] else '0x442487'
        if row['native']!=expected(c) or row['normal_return'] is not normal or row['stop_address']!=stop or not 0<row['instructions']<4096:raise ValueError('Extra attack result/boundary changed')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Extra attack anchors changed')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_native_extra_attack.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,source=source(),
           cases=[execute(base,mapped,c) for c in fixtures()],anchors=[dict(address=hex(a),bytes=bytes(mapped[a-base:a-base+n]).hex(),meaning=s) for a,n,s in ANCHORS],
           limits=['Flag query and no-effect final branches return normally; other branches stop before callbacks.',
                   'Synthetic completed strike states isolate extra scheduling and final ST/counter boundaries; this is not a whole native rendered exchange.',
                   'Numeric damage/hit/crit/EXP are separately verified helpers. Whole action_twice and other attack-status passives are not enabled.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'EXTRA_ATTACK_NATIVE_PASS cases={len(p["cases"])} executed_now={executed_now}'


TASK = ProbeTask('extra_attack', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
