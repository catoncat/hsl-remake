"""Original single-cell faction/flying floods and a bounded player landing gate.

The three trait/mode helpers and 0x40f440 return normally. Player landing stops
before inspection/UI or movement callbacks, after the original occupancy gate.
Synthetic maps are independent of source initialization and renderer timing.

Registry task traversal (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_traversal_probe.py.
"""
from __future__ import annotations
import hashlib
import heapq
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_actor_traversal.json'

ANCHOR_SHA = '7c63b64de5db629b95643f4de9a198c28e8241abb4f16914b926a09c9d0404b0'
DIRS = [(0,-1), (0,1), (-1,0), (1,0)]
MASKS = {2:0x64000, 3:0x54000, 6:0x4000, 7:0x34000}
ANCHORS = [
    (0x4440f7, 57, 'Player Move selects flight mode6, otherwise ground mode2, and passes live movement.'),
    (0x40cd42, 105, 'AI casting positions select mode6 or the actor faction mode before the same flood.'),
    (0x40bab0, 70, 'Ground faction helper: player bit first, then enemy, then NPC.'),
    (0x446ad0, 41, 'Fly queries actor capability bit1.'),
    (0x446b30, 41, 'No-block queries actor capability bit0x10.'),
    (0x40f1c4, 44, 'Eleven primary flood branch addresses; mode6 is the distinct flight branch.'),
    (0x443c7c, 58, 'Player landing inspects occupied faction cells, with the no-block exception.'),
    (0x443d47, 39, 'Empty no-stop cells are refused, then positive movement coverage is required.'),
    (0x44c294, 40, 'PLAYERS move_fly loader and capability update.'),
    (0x44c2f4, 40, 'PLAYERS no_block loader and capability update.'),
]


def helper_fixtures():
    return [dict(side=side, flags=flags) for side in [0x10000,0x20000,0x40000,0x30000,0x50000,0x60000,0x70000]
            for flags in [0,1,16,17]]


def helper_expected(c):
    ground = 2 if c['side'] & 0x10000 else 3 if c['side'] & 0x20000 else 7
    return dict(ground=ground, flying=bool(c['flags'] & 1), no_block=bool(c['flags'] & 16),
                mode=6 if c['flags'] & 1 else ground)


def flood_fixtures():
    rows = []
    layouts = [([[4,3,side]], []) for side in [0x10000,0x20000]]
    layouts += [([[4,y,flag] for y in range(7)], []) for flag in [0x10000,0x20000,0x4000,0xff000000]]
    layouts += [([[4,3,0xff000000],[5,3,0x4000]], [])]
    for mode in [2,3,6,7]:
        for budget in [2,4]:
            for cells, occupants in layouts:
                rows.append(dict(mode=mode, budget=budget, size=[7,7], origin=[3,3], base_height=0,
                                 cells=cells, occupants=occupants))
    for mode in [2,3,6]:
        for height in [1,2,3,255]:
            rows.append(dict(mode=mode, budget=4, size=[7,7], origin=[3,3], base_height=0,
                             cells=[[4,y,height<<24] for y in range(7)], occupants=[]))
        for height in [2,3]:
            rows.append(dict(mode=mode, budget=4, size=[7,7], origin=[3,3], base_height=height,
                             cells=[[4,y,0] for y in range(7)], occupants=[]))
    for mode, side in [(2,0x20000),(3,0x10000),(6,0x20000)]:
        for no_block in [False,True]:
            rows.append(dict(mode=mode, budget=4, size=[7,7], origin=[3,3], base_height=0, cells=[],
                             occupants=[dict(coord=[4,3], side=side, no_block=no_block)]))
    # A start on a 0xff cell (an install point on a cliff, e.g. 552 咕嚕): 0x40f200 seeds
    # the origin without a terrain test and passes its own height byte to the first
    # 0x40ed50 calls — alone on the cliff, on a cliff ledge, beside 252／253／254 steps.
    for mode in [2,3,6,7]:
        for cells in [[[3,3,0xff000000]], [[x,3,0xff000000] for x in range(7)],
                      [[3,3,0xff000000],[4,3,253<<24],[2,3,254<<24],[3,2,252<<24]]]:
            rows.append(dict(mode=mode, budget=4, size=[7,7], origin=[3,3], base_height=0,
                             cells=cells, occupants=[]))
    return rows


def flags_for(c):
    width,height=c['size']
    flags={(x,y):c['base_height']<<24 for y in range(height) for x in range(width)}
    flags.update({(x,y):value for x,y,value in c['cells']})
    for actor in c['occupants']:
        point=tuple(actor['coord']);flags[point] |= actor['side']
    return flags


def expected_flood(c):
    width,height=c['size'];ox,oy=c['origin'];budget=c['budget'];mode=c['mode'];mask=MASKS[mode]
    flags=flags_for(c); no_block={tuple(a['coord']) for a in c['occupants'] if a['no_block']}
    costs={(ox,oy,-1):0};queue=[(0,ox,oy,-1)];arrival={(ox,oy):0}
    while queue:
        spent,x,y,direction=heapq.heappop(queue)
        if costs[(x,y,direction)] != spent:continue
        previous=None if direction<0 else (x-DIRS[direction][0],y-DIRS[direction][1])
        clearance=int(direction>=0 and mode!=6 and any((x+dx,y+dy)!=previous and flags.get((x+dx,y+dy),0)&mask for dx,dy in DIRS))
        for next_direction,(dx,dy) in enumerate(DIRS):
            nx,ny=x+dx,y+dy;point=(nx,ny)
            if not 0<=nx<width or not 0<=ny<height or point==(ox,oy):continue
            value=flags[point]
            if value&mask and not (mode!=6 and point in no_block):continue
            gain=0
            if mode!=6:
                old_height=(flags[(x,y)]>>24)&255;new_height=(value>>24)&255
                delta=(16 if new_height==255 else 0) if old_height==128 else new_height-old_height
                if abs(delta)>=3:continue
                gain=max(0,delta)
            candidate=spent+1+clearance+gain;state=(nx,ny,next_direction)
            if candidate<=budget and candidate<costs.get(state,10**9):
                costs[state]=candidate;arrival[point]=min(candidate,arrival.get(point,10**9))
                heapq.heappush(queue,(candidate,nx,ny,next_direction))
    side=2*budget+1
    return [[budget+1-arrival[(ox+x-budget,oy+y-budget)] if (ox+x-budget,oy+y-budget) in arrival else 0
             for x in range(side)] for y in range(side)]


def landing_fixtures():
    return [dict(flags=flags,present=present,no_block=no_block)
            for flags in [0,0x100000,0x10000,0x20000,0x40000,0x110000,0x850000]
            for present in [False,True] for no_block in [False,True]]


def landing_expected(c):
    return bool(c['present'] and c['no_block']) if c['flags']&0x70000 else not bool(c['flags']&0x100000)


def execute(base,mapped,c,kind):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped)
    obj,grid,coverage,roster,stack,stop=0x10001000,0x10003000,0x10006000,0x10008000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    put(0x4c1bc8,roster);put(obj+0xa4,0);put(obj+4,112);put(obj+8,112)
    put(roster+0x28,0x10000);put(roster+0xd8,100)
    put(0x4c0934,7);put(0x4c0938,7);put(0x4c0928,grid);put(0x4c1b44,coverage)
    m.mem_write(0x4c34c0,bytes(800))
    allowed=[(0x40ba20,0x40baf6),(0x446ad0,0x446af9),(0x446b30,0x446b59),
             (0x40eb40,0x40ecb0),(0x40ed50,0x40f530),(0x407800,0x40793c),
             (0x411c40,0x411c90),(0x443c6f,0x443cba),(0x443d47,0x443d4e)]
    stops=[0x443cba,0x443d4e,0x443d9d] if kind=='landing' else []
    steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        if address in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=address<hi for lo,hi in allowed):raise ValueError(f'Unreviewed traversal callee {address:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    def call(entry,args):
        m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(entry,stop,count=300000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Traversal helper did not return normally')
        return m.reg_read(UC_X86_REG_EAX)
    if kind=='helper':
        put(roster+0x28,c['side']);put(roster+0xa0,c['flags'])
        before=bytes(m.mem_read(roster,0x1fc))
        ground=call(0x40bab0,[obj]);flying=bool(call(0x446ad0,[obj]));no_block=bool(call(0x446b30,[obj]))
        actual=dict(ground=ground,flying=flying,no_block=no_block,mode=6 if flying else ground)
        if before!=bytes(m.mem_read(roster,0x1fc)):raise ValueError('Trait query mutated actor')
        wanted=helper_expected(c); normal=True; entry='0x40bab0/0x446ad0/0x446b30'
    else:
        occupants=c['occupants'] if kind=='flood' else ([dict(coord=[4,3],side=0,no_block=c['no_block'])] if c['present'] else [])
        for i,actor in enumerate(occupants,1):
            pointer=obj+i*0x200;record=roster+i*0x1fc
            put(0x4c34c0+(i-1)*4,pointer);put(pointer+0xa4,i)
            put(pointer+4,actor['coord'][0]*32+16);put(pointer+8,actor['coord'][1]*32+16)
            put(record+0xa0,16 if actor['no_block'] else 0);put(record+0xd8,100)
        if kind=='flood':
            for (x,y),value in flags_for(c).items():put(grid+(y*7+x)*4,value)
            before=bytes(m.mem_read(grid,196));actors=bytes(m.mem_read(roster,0x1000))
            call(0x40f440,[obj,c['budget'],c['mode']])
            side=2*c['budget']+1;values=m.mem_read(coverage,side*side)
            actual=[list(values[y*side:(y+1)*side]) for y in range(side)]
            if before!=bytes(m.mem_read(grid,196)) or actors!=bytes(m.mem_read(roster,0x1000)):raise ValueError('Single-cell flood changed map/actor truth')
            wanted=expected_flood(c);normal=True;entry='0x40f440'
        else:
            put(grid+(3*7+4)*4,c['flags']);put(0x4c1a8c,144);put(0x4c1a90,112)
            m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x443c6f,stop,count=300000)
            address=m.reg_read(UC_X86_REG_EIP)
            if address not in stops:raise ValueError('Landing prefix exceeded its boundary')
            actual=dict(accepted=address==0x443d4e,stop_address=hex(address))
            wanted=dict(accepted=landing_expected(c),stop_address=hex(0x443d4e if landing_expected(c) else 0x443cba if c['flags']&0x70000 else 0x443d9d))
            normal=False;entry='0x443c6f'
    if actual!=wanted:raise ValueError(f'Traversal mismatch {kind}: {c}\n{actual}\nexpected {wanted}')
    return dict(input=c,native=actual,normal_return=normal,entry=entry,instructions=steps)


def sources():
    return {name:hashlib.sha256((TABLES/name).read_bytes()).hexdigest() for name in ['PLAYERS.TXT','TYPE.H']}


def check(p):
    if p.get('schema')!='hsl_actor_traversal_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('sources')!=sources() or p.get('native_execution') is not True:
        raise ValueError('Traversal source identity differs')
    for name,cases,oracle in [('helper',helper_fixtures(),helper_expected),('flood',flood_fixtures(),expected_flood),('landing',landing_fixtures(),landing_expected)]:
        if [r['input'] for r in p[name]]!=cases:raise ValueError('Traversal fixture coverage differs')
        for row in p[name]:
            actual=row['native']['accepted'] if name=='landing' else row['native']
            if actual!=oracle(row['input']) or row['normal_return'] is not (name!='landing') or not 0<row['instructions']<300000:
                raise ValueError('Traversal return or bounded result differs')
            entry = {'helper':'0x40bab0/0x446ad0/0x446b30','flood':'0x40f440','landing':'0x443c6f'}[name]
            if row['entry'] != entry: raise ValueError('Traversal original entry differs')
            if name == 'landing':
                expected_stop = '0x443d4e' if actual else '0x443cba' if row['input']['flags'] & 0x70000 else '0x443d9d'
                if row['native']['stop_address'] != expected_stop: raise ValueError('Landing prefix stop differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in p['anchors']]!=ANCHORS:
        raise ValueError('Traversal anchor coverage differs')
    if hashlib.sha256(b''.join(bytes.fromhex(a['bytes']) for a in p['anchors'])).hexdigest()!=ANCHOR_SHA:
        raise ValueError('Traversal original caller bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_actor_traversal_native.v1',exe_sha256=EXE_SHA,sources=sources(),evidence_tier='static-derived',native_execution=True,
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           helper=[execute(base,mapped,c,'helper') for c in helper_fixtures()],flood=[execute(base,mapped,c,'flood') for c in flood_fixtures()],
           landing=[execute(base,mapped,c,'landing') for c in landing_fixtures()],
           limits=['Single-cell original wrapper/flood and trait helpers return normally; no unknown callee is stubbed.',
                   'Landing executes a player input prefix and stops before UI, reachability or movement callbacks.',
                   'Source actor initialization, large-footprint movement/targeting and renderer timing are separate.',
                   'A shortest whole-map route and deterministic equal-cost tie order are remake composition, not the original global search cache.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'ACTOR_TRAVERSAL_NATIVE_PASS helper={len(p["helper"])} flood={len(p["flood"])} landing={len(p["landing"])} executed_now={executed_now}'


TASK = ProbeTask('traversal', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
