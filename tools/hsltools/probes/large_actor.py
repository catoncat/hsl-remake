"""Original large-body lookup, map marking, full movement and effect dedup.

All queried functions return normally without stubs. The original movement
wrapper removes the owner's ring flags from its working map; that mutation is
verified explicitly, not described as a restored map or used as game state.

Registry task large_actor (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_large_actor_probe.py.
"""
from __future__ import annotations
import hashlib
import heapq
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import source_profile, calculate
from hsltools.native.image import image, EXE_SHA
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.job_stats import execute as execute_stats
from hsltools.probes.traversal import DIRS, MASKS
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_large_actor.json'

SOURCE_NAMES=['PLAYERS.TXT','ITEM.TXT','TYPE.H','RANGE.H','RANGE.TXT','SHAPEDEF.TXT']
ANCHORS=[(0x407800,316,'Registered actor lookup uses center or 3x3 body and prefers ordinary blockers over no_block actors; no HP gate.'),
         (0x411ae0,176,'Occupancy setter writes center and eight neighbors for a large actor.'),
         (0x411b90,176,'Occupancy clearer visits the same footprint.'),
         (0x40ecc0,144,'Whole-body clearance checks all nine cells except the original actor center; outside-grid flags read as zero.'),
         (0x40f440,218,'Large flood wrapper sets large mode and removes own eight-cell ring before the full original flood.'),
         (0x4104d0,297,'Effect-mask actor enumeration calls body-aware lookup and deduplicates registered pointers.'),
         (0x409090,123,'Large weapon range is base index plus seventeen and boolean extension, capped at twenty.')]
ANCHOR_SHA='93af4ac92f6384742952f664de6413c1b8003ea5aecc4095c997248cb433c848'
AI_LOADER = {
    'ai_help_otherhp': (0x44c93a,0x44c970,0x1dc),
    'ai_help_status': (0x44c961,0x44c997,0x1e0),
    'ai_help_attack': (0x44c988,0x44c9bd,0x1e4),
    'ai_magic_multi_first': (0x44c9b2,0x44c9e8,0x1f4),
    'ai_att_special': (0x44ca00,0x44ca36,0x1ec),
    'ai_att_magic': (0x44ca27,0x44ca5c,0x1f0),
}

def ai_defaults(base,mapped,key,junk):
    """A bounded loader suffix, with the REAL missing-key parser, no stubs.

    An empty section has no field records. Its output begins deliberately dirty;
    the original caller clears it, parser returns not-found, caller stores zero.
    Stop before the next field, not a claimed whole template-loader return.
    """
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ECX,UC_X86_REG_EDX,UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_EBP,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);stack=0x1001f800;actor=0x10001000;table=0x10006000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    entry,stop,offset=AI_LOADER[key]
    put(0x4c1afc,actor);put(0x4c24b4,table);put(0x4c25c8,256)
    put(table+16+0xb,0)
    for i in range(32):put(stack+4*i,junk)
    put(actor+offset,999)
    for reg,value in [(UC_X86_REG_ESP,stack),(UC_X86_REG_EBP,0),(UC_X86_REG_ESI,0),
                      (UC_X86_REG_EDI,16),(UC_X86_REG_EDX,actor),(UC_X86_REG_ECX,777)]:m.reg_write(reg,value)
    steps=0;parser_seen=False
    def guard(_m,at,_n,_d):
        nonlocal steps,parser_seen
        if at==stop:m.emu_stop();return
        steps+=1
        if at==0x46de70:parser_seen=True
        if not (entry<=at<stop or 0x46dd50<=at<0x46de00 or 0x46de70<=at<0x46debe):raise ValueError(f'Unreviewed AI loader callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,0x10000000,count=1024)
    actual=struct.unpack('<I',m.mem_read(actor+offset,4))[0]
    if m.reg_read(UC_X86_REG_EIP)!=stop or actual!=0 or not parser_seen:raise ValueError('AI missing-field loader boundary differs')
    return dict(field=key,initial_output=junk,native=actual,entry=hex(entry),stop_address=hex(stop),
                normal_return=False,parser_executed=True,instructions=steps,bytes=bytes(mapped[entry-base:stop-base]).hex())

def body(center,size):
    r=1 if size else 0
    return [(center[0]+x,center[1]+y) for y in range(-r,r+1) for x in range(-r,r+1)]

def setup(base,mapped,c):
    from unicorn.x86_const import UC_X86_REG_ESP
    m=machine_for(base,mapped)
    obj,actors,grid,coverage,stack,stop=0x10001000,0x10008000,0x10004000,0x10006000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    w,h=c.get('size',[9,9]);center=c.get('origin',[4,4])
    put(0x4c0934,w);put(0x4c0938,h);put(0x4c0928,grid);put(0x4c1b44,coverage);put(0x4c1bc8,actors)
    put(obj+4,center[0]*32+16);put(obj+8,center[1]*32+16);put(obj+0xa4,0)
    put(actors+0x2c,c.get('large',1));put(actors+0xd8,100)
    m.mem_write(0x4c34c0,bytes(800));m.reg_write(UC_X86_REG_ESP,stack)
    def call(entry,args,budget=300000):
        m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(entry,stop,count=budget)
        from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_EAX
        assert m.reg_read(UC_X86_REG_EIP)==stop and m.reg_read(UC_X86_REG_ESP)==stack+4,(hex(entry),hex(m.reg_read(UC_X86_REG_EIP)))
        return m.reg_read(UC_X86_REG_EAX)
    return m,put,get,call,obj,actors,grid,coverage

def lookup(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,obj,actors,grid,coverage=setup(base,mapped,c)
    pointers=[]
    for i,row in enumerate(c['actors']):
        p=obj+i*0x200;record=actors+i*0x1fc;pointers.append(p)
        if row['registered']:put(0x4c34c0+i*4,p)
        put(p+4,row['coord'][0]*32+16);put(p+8,row['coord'][1]*32+16);put(p+0xa4,i)
        put(record+0x2c,row['large']);put(record+0xa0,16 if row['no_block'] else 0);put(record+0xd8,row['hp'])
    steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(a<=at<b for a,b in [(0x407800,0x40793c),(0x446b30,0x446b59)]):raise ValueError(hex(at))
    m.hook_add(UC_HOOK_CODE,guard)
    query=c['query'];value=call(0x407800,[query[0]*32+16,query[1]*32+16])
    actual=pointers.index(value) if value else -1
    wanted=-1
    for i,row in enumerate(c['actors']):
        if row['registered'] and tuple(query) in body(row['coord'],row['large']):
            wanted=i
            if not row['no_block']:break
    assert actual==wanted,(c,actual,wanted)
    return dict(input=c,native=actual,normal_return=True,instructions=steps)

def marking(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,obj,actors,grid,coverage=setup(base,mapped,c)
    w,h=c['size'];values=[0x05000abc]*(w*h)
    m.mem_write(grid,struct.pack('<'+'I'*len(values),*values));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(a<=at<b for a,b in [(0x411940,0x4119d0),(0x411ae0,0x411c40)]):raise ValueError(hex(at))
    m.hook_add(UC_HOOK_CODE,guard)
    call(0x411ae0,[obj,0x20000])
    changed=body(c['origin'],c['large']);wanted=[0x20abc if (i%w,i//w) in changed else value for i,value in enumerate(values)]
    marked=list(struct.unpack('<'+'I'*len(values),m.mem_read(grid,4*len(values))))
    assert marked==wanted,(c,marked,wanted)
    call(0x411b90,[obj,0x20000])
    cleared=list(struct.unpack('<'+'I'*len(values),m.mem_read(grid,4*len(values))))
    assert cleared==[v&~0x20000 if (i%w,i//w) in changed else v for i,v in enumerate(wanted)]
    return dict(input=c,native=dict(marked=marked,cleared=cleared),normal_returns=2,instructions=steps)

def flags_for(c,with_owner=False):
    w,h=c['size'];flags={(x,y):c['base_height']<<24 for y in range(h) for x in range(w)}
    flags.update({(x,y):v for x,y,v in c['cells']})
    for actor in c['occupants']:
        for p in body(actor['coord'],actor['large']):
            if p in flags:flags[p]|=actor['side']
    if with_owner:
        side={2:0x10000,3:0x20000,6:0x10000,7:0x40000}[c['mode']]
        for p in body(c['origin'],c['large']):
            if p in flags:flags[p]|=side
    return flags

def oracle(c):
    w,h=c['size'];ox,oy=c['origin'];budget=c['budget'];mode=c['mode'];mask=MASKS[mode]
    flags=flags_for(c);costs={(ox,oy,-1):0};queue=[(0,ox,oy,-1)];arrival={(ox,oy):0};transit={}
    no_block={point for a in c['occupants'] if a['no_block'] for point in body(a['coord'],a['large'])}
    while queue:
        spent,x,y,direction=heapq.heappop(queue)
        if costs[(x,y,direction)]!=spent:continue
        previous=None if direction<0 else (x-DIRS[direction][0],y-DIRS[direction][1])
        penalty=int(direction>=0 and mode!=6 and any((x+dx,y+dy)!=previous and flags.get((x+dx,y+dy),0)&mask for dx,dy in DIRS))
        for d,(dx,dy) in enumerate(DIRS):
            nx,ny=x+dx,y+dy;point=(nx,ny)
            if not 0<=nx<w or not 0<=ny<h or point==(ox,oy):continue
            cells=body(point,c['large']);marked=False
            if c['large']:
                cells=[p for p in cells if p!=(ox,oy)]
                hard=any(flags.get(p,0)&0x74000 for p in cells)
                if mode!=6:
                    if hard or any(flags.get(p,0)>>24==255 for p in cells):continue
                elif hard:
                    if any(flags.get(p,0)&0x4000 for p in cells):continue
                    marked=True
            elif flags.get(point,0)&mask and not (mode!=6 and point in no_block):continue
            gain=0
            if mode!=6:
                old=flags[(x,y)]>>24;new=flags[point]>>24
                delta=(16 if new==255 else 0) if old==128 else new-old
                if abs(delta)>=3:continue
                gain=max(0,delta)
            candidate=spent+1+penalty+gain;state=(nx,ny,d)
            if candidate<=budget and candidate<costs.get(state,10**9):
                costs[state]=candidate;arrival[point]=min(candidate,arrival.get(point,10**9));transit[point]=marked
                heapq.heappush(queue,(candidate,nx,ny,d))
    side=2*budget+1
    return [[(budget+1-arrival[(ox+x-budget,oy+y-budget)] | (0x80 if transit.get((ox+x-budget,oy+y-budget),False) else 0)) if (ox+x-budget,oy+y-budget) in arrival else 0 for x in range(side)] for y in range(side)]

def flood(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,obj,actors,grid,coverage=setup(base,mapped,c)
    w,h=c['size'];side={2:0x10000,3:0x20000,6:0x10000,7:0x40000}[c['mode']]
    put(actors+0x28,side)
    for i,actor in enumerate(c['occupants'],1):
        p=obj+i*0x200;record=actors+i*0x1fc
        put(0x4c34c0+(i-1)*4,p);put(p+0xa4,i);put(p+4,actor['coord'][0]*32+16);put(p+8,actor['coord'][1]*32+16)
        put(record+0x2c,actor['large']);put(record+0xa0,16 if actor['no_block'] else 0);put(record+0xd8,100)
    for (x,y),v in flags_for(c,True).items():put(grid+4*(y*w+x),v)
    before=bytes(m.mem_read(grid,4*w*h));actor_before=bytes(m.mem_read(actors,0x1400));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(a<=at<b for a,b in [(0x40ba20,0x40baf6),(0x40eb40,0x40ecb0),(0x40ecc0,0x40f550),(0x407800,0x40793c),(0x446b30,0x446b59),(0x411900,0x4119d0)]):raise ValueError(f'flood callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);call(0x40f440,[obj,c['budget'],c['mode']])
    dim=2*c['budget']+1;values=m.mem_read(coverage,dim*dim);actual=[list(values[y*dim:(y+1)*dim]) for y in range(dim)]
    wanted=oracle(c)
    assert actual==wanted,(c,actual,wanted)
    expected_map=bytearray(before)
    if c['large']:
        for x,y in body(c['origin'],1):
            if [x,y]==c['origin'] or not 0<=x<w or not 0<=y<h:continue
            offset=4*(y*w+x);value=struct.unpack_from('<I',expected_map,offset)[0]
            struct.pack_into('<I',expected_map,offset,value&~side)
    assert expected_map==bytes(m.mem_read(grid,4*w*h)) and actor_before==bytes(m.mem_read(actors,0x1400))
    return dict(input=c,native=actual,normal_return=True,instructions=steps,actor_unchanged=True,only_own_ring_removed=True)

def enumerate_targets(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,obj,actors,grid,coverage=setup(base,mapped,c)
    m.mem_write(0x4c34c0,bytes(800));pointers=[]
    for i,row in enumerate(c['actors']):
        p=obj+i*0x200;pointers.append(p);put(p+0xa4,i);put(p+4,row['coord'][0]*32+16);put(p+8,row['coord'][1]*32+16)
        put(actors+i*0x1fc+0x2c,row['large']);put(actors+i*0x1fc+0xd8,100);put(0x4c34c0+i*4,p)
    # The original enumerator consumes the completed effect mask. Synthetic masks
    # exercise overlapping body cells without substituting any actor lookup.
    dim=c['dimension'];put(0x476b3c,dim);put(0x476b40,dim);put(0x4c1b4c,coverage);put(0x4c1b88,0x1000c000)
    put(0x4c6d44,c['center'][0]);put(0x4c6d40,c['center'][1]);m.mem_write(coverage,bytes(c['mask']));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(a<=at<b for a,b in [(0x4104d0,0x4105f9),(0x407800,0x40793c),(0x446b30,0x446b59)]):raise ValueError(f'enumerate callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);before=bytes(m.mem_read(actors,0x1000))
    values=[];value=call(0x4104d0,[0])
    while value:
        assert len(values)<len(pointers)
        values.append(pointers.index(value));value=call(0x4104d0,[1])
    wanted=[];half=dim//2
    for i,v in enumerate(c['mask']):
        point=(c['center'][0]+i%dim-half,c['center'][1]+i//dim-half)
        if not v:continue
        for j,row in enumerate(c['actors']):
            if point in body(row['coord'],row['large']):
                if j not in wanted:wanted.append(j)
                break
    assert values==wanted and before==bytes(m.mem_read(actors,0x1000))
    return dict(input=c,native=values,normal_returns=len(values)+1,instructions=steps,actor_unchanged=True)

def fixtures():
    giant=dict(coord=[4,4],large=1,no_block=False,hp=100,registered=True)
    queries=[dict(actors=[dict(giant,large=large)],query=[x,y]) for large in [0,1] for y in range(2,7) for x in range(2,7)]
    queries += [dict(actors=[dict(giant,no_block=True),dict(giant,coord=[5,4],large=0,hp=hp,registered=registered)],query=[5,4]) for hp in [0,100] for registered in [False,True]]
    marks=[dict(size=[7,7],origin=origin,large=large) for origin in [[3,3],[0,0],[6,6]] for large in [0,1]]
    common=dict(size=[9,9],origin=[4,4],large=1,base_height=0,mode=2,budget=4,cells=[],occupants=[])
    floods=[]
    for mode in [2,3,6,7]:
        for flag in [0,0x4000,0x10000,0x20000,0x40000,0xff000000,0x02000000,0x04000000]:
            floods.append(dict(common,mode=mode,cells=[] if not flag else [[6,4,flag]]))
        for height in [0,128]:floods.append(dict(common,mode=mode,base_height=height,cells=[[6,y,0] for y in range(9)]))
        for no_block in [False,True]:
            floods.append(dict(common,mode=mode,occupants=[dict(coord=[6,4],large=0,side=0x20000,no_block=no_block)]))
    for large in [0,1]:
        for gap in [1,3]:
            floods.append(dict(common,origin=[2,4],large=large,budget=6,cells=[[4,y,0xff000000] for y in range(9) if abs(y-4)>gap//2]))
    for origin in [[0,0],[8,8]]:floods.append(dict(common,origin=origin,budget=3))
    # A second large object blocks every occupied cell, not just its center.
    floods += [dict(common,large=large,origin=[2,4],occupants=[dict(coord=[6,4],large=1,side=0x20000,no_block=False)]) for large in [0,1]]
    enums=[dict(actors=[dict(giant,coord=[2,2]),dict(giant,large=0,coord=[4,4])],dimension=5,center=[2,2],mask=mask) for mask in [[1]*25,[int(i==6) for i in range(25)],[int(i in [6,7,8,11,12,13,16,17,18,24]) for i in range(25)]]]
    return dict(lookup=queries,marking=marks,flood=floods,enumeration=enums)

def stat_cases():
    players,_,defines=sources();row=players['039']
    attrs={k:int(row[k]) for k in ['str','dex','mind','con']}
    gear=[int(row.get(k+'_equip',0)) for k in ['weapon','head','armor','foot','other1','other2']]
    common=dict(actor='039',attributes=attrs,level=1,equipment=gear,hp=9999,mp=9999,mode=defines[row['mode']],base_move=int(row['move_point']))
    return [dict(common,name='initial_fixed_level1'),dict(common,name='level3',level=3),
            dict(common,name='allocation',level=2,attributes={k:v+d for (k,v),d in zip(attrs.items(),[1,1,2,1])}),
            dict(common,name='equipment_refresh',level=3,equipment=[40,0,138,0,236,227],hp=1,mp=0)]

def check(output):
    if output.get('schema')!='hsl_large_actor_native.v1' or output.get('exe_sha256')!=EXE_SHA or output.get('native_execution') is not True:
        raise ValueError('Large-actor proof identity differs')
    if output['sources']!={n:digest((TABLES/n).read_bytes()) for n in SOURCE_NAMES}:raise ValueError('Large-actor sources differ')
    for kind,cases in fixtures().items():
        if [r['input'] for r in output[kind]]!=cases:raise ValueError('Large-actor fixture coverage differs: '+kind)
        for row in output[kind]:
            c=row['input']
            if not 0<row['instructions']<300000:raise ValueError('Large-actor execution exceeded bound')
            if kind=='lookup':
                expected=-1
                for i,actor in enumerate(c['actors']):
                    if actor['registered'] and tuple(c['query']) in body(actor['coord'],actor['large']):
                        expected=i
                        if not actor['no_block']:break
                if row['native']!=expected or row['normal_return'] is not True:raise ValueError('Large lookup differs')
            elif kind=='marking':
                w,h=c['size'];cells=body(c['origin'],c['large'])
                marked=[0x20abc if (i%w,i//w) in cells else 0x05000abc for i in range(w*h)]
                cleared=[v&~0x20000 if (i%w,i//w) in cells else v for i,v in enumerate(marked)]
                if row['native']!=dict(marked=marked,cleared=cleared) or row['normal_returns']!=2:raise ValueError('Body marking differs')
            elif kind=='flood':
                if row['native']!=oracle(c) or row['normal_return'] is not True or row['actor_unchanged'] is not True or row['only_own_ring_removed'] is not True:raise ValueError('Full large flood differs')
            else:
                expected=[];dim=c['dimension'];half=dim//2
                for i,v in enumerate(c['mask']):
                    if not v:continue
                    point=(c['center'][0]+i%dim-half,c['center'][1]+i//dim-half)
                    for j,actor in enumerate(c['actors']):
                        if point in body(actor['coord'],actor['large']):
                            if j not in expected:expected.append(j)
                            break
                if row['native']!=expected or row['normal_returns']!=len(expected)+1 or row['actor_unchanged'] is not True:raise ValueError('Footprint targets were not uniquely enumerated')
    if [r['input'] for r in output['stats']]!=stat_cases():raise ValueError('Source039 refresh coverage differs')
    players,_,defines=sources();profile=source_profile(players['039'],defines);catalog=equipment_data()['items']
    for row in output['stats']:
        c=row['input'];expected=calculate(profile,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        if row['profile']!=profile or len(row['native'])!=2 or any(r['values']!=expected or r['normal_return'] is not True or not 0<r['instructions']<12000 for r in row['native']):raise ValueError('Source039 refresh differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in output['anchors']]!=ANCHORS:raise ValueError('Large-actor anchors differ')
    actual=hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in output['anchors']))).hexdigest()
    if actual!=ANCHOR_SHA:raise ValueError('Large-actor original bytes differ')
    expected_defaults=[(key,junk) for key in AI_LOADER for junk in [0,123456]]
    if [(r['field'],r['initial_output']) for r in output['ai_defaults']]!=expected_defaults:raise ValueError('AI defaults coverage differs')
    for row in output['ai_defaults']:
        entry,stop,_=AI_LOADER[row['field']]
        if row['native']!=0 or row['entry']!=hex(entry) or row['stop_address']!=hex(stop) or row['normal_return'] is not False or row['parser_executed'] is not True or not 0<row['instructions']<1024 or len(bytes.fromhex(row['bytes']))!=stop-entry:
            raise ValueError('AI defaults missing-field execution differs')
    if digest(b''.join(bytes.fromhex(r['bytes']) for r in output['ai_defaults']))!='2ed055ef5675211d8c0159bd49cd892adc80c0a7ac2bd27b4243650f7648f65f':
        raise ValueError('AI defaults original loader bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    functions=dict(lookup=lookup,marking=marking,flood=flood,enumeration=enumerate_targets)
    output=dict(schema='hsl_large_actor_native.v1',evidence_tier='static-derived',native_execution=True,exe_sha256=EXE_SHA,
                sources={n:digest((TABLES/n).read_bytes()) for n in SOURCE_NAMES},
                **{kind:[functions[kind](base,mapped,c) for c in cases] for kind,cases in fixtures().items()},
                stats=[execute_stats(base,mapped,c) for c in stat_cases()],
                ai_defaults=[ai_defaults(base,mapped,key,junk) for key in AI_LOADER for junk in [0,123456]],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Lookup/marking/flood/enumerator and stat helpers return normally; effect-mask inputs are synthetic completed masks, not full original spell-grid construction.',
                        'AI missing-field probes are bounded loader suffixes executing the original parser on an empty section; stop before the next field, not a full template-loader return.',
                        'Original lookup follows registered object pointers even at zero HP. Current game filters defeated actors at the shared lifecycle seam.',
                        'Movement removes only own ring side flags from its scratch map. Current game instead derives occupancy afresh and never mutates terrain.',
                        'Outside map body cells are ignored by native queries; the center stays in map. Full-body NO_STOP policy is the explicit current placement adapter.',
                        'Source039 has no fixed level declaration; level1 is the existing remake fixed-template policy. Eight numeric refresh returns do not claim original level selection.',
                        'Original global map lifecycle, equal path ties and full rendering remain separate.'])
    return output


def summary_line(output: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('LARGE_ACTOR_NATIVE_PASS', {k:len(output[k]) for k in fixtures()}, 'stats_returns=', len(output['stats'])*2, 'executed_now=', executed_now, 'anchors_sha=', hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in output['anchors']))).hexdigest()))


TASK = ProbeTask('large_actor', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
