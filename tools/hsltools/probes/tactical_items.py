"""Original tactical consumables: prefix before audio, complete RNG/cure helpers.

Application starts at409e40 and stops at40a343. Source stat refresh and RNG run
normally, without stubs. Inventory, turn commit and renderer remain separate.

Registry task tactical_items (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_tactical_items_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build
from hsltools.model.jobs import SLOTS, ATTRIBUTES, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.stat_magic import machine, put_actor, WORDS, flags
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_tactical_items.json'

# ITEM cure fields -> item+0xa0 bits (loader 0x447f8f..0x447fe2); the application 0x409e40 clears the
# matching flag/word per bit and only the cure_weaken branch (0x40a31f) refreshes through 0x448840.
CURE_BITS={'cure_poison':0x80000000,'cure_no_magic':0x40000000,'cure_paralysis':0x20000000,'cure_weaken':0x10000000}
CURE_WORDS={'cure_poison':'poison','cure_no_magic':'no_magic','cure_paralysis':'paralysis','cure_weaken':'weaken'}
ITEM_WORDS=dict(WORDS,weaken=(0x38,8))
ANCHOR_SHA='bce6c2d186a59a7f6bb8f05b1d143399f8768d574fa1a4396d5918e2341d7f63'
ANCHORS=[(0x409e10,37,'Signed packed endpoints are sorted and sampled inclusively with one native RNG call.'),
         (0x40a12b,142,'Battle item boosts extend low-word duration by three, capped nine; existing power is not resampled.'),
         (0x40a275,41,'Item stamina adds its source amount then caps at60.'),
         (0x40a2f9,19,'Cure-no-magic clears only flag2 and the full no-magic counter.'),
         (0x40c230,154,'Eight-slot cure scan includes no-magic and returns the first matching one-based slot.'),
         (0x447f8f,34,'ITEM cure_no_magic sets effect40000000.'),
         (0x447b45,27,'ITEM add_st populates offset30.'),
         (0x447c59,54,'ITEM local attack/defense ranges populate packed fields74/7c.'),
         (0x40a31f,36,'Cure-weaken clears the whole weaken word and flag8, then falls into the shared 0x448840 refresh call; other cure bits skip it.'),
         (0x447fd7,19,'ITEM cure_weaken sets effect10000000.')]

def cure_mask(row):
    return sum(bit for field,bit in CURE_BITS.items() if row.get(field)=='1')


def item_flags(words):
    return flags(words)|(8 if words.get('weaken',0) else 0)


def applications():
    empty=dict.fromkeys(ITEM_WORDS,0)
    both=dict(empty,poison=0x70003,no_magic=3,paralysis=2,attack_up=0x180004,defense_up=0x1e0004)
    rows=[dict(actor=actor,level=3,code=code,stamina=19,words=words,seed=7,outside_battle=False)
          for actor in ['001','002','026','024'] for code in [247,250,262,263] for words in [empty,both]]
    for code in [262,263]:
        key='attack_up' if code==262 else 'defense_up'
        for before in [0,0x50001,0xa0007,0x180008,0x600009]:
            for seed in [1,19,101]:
                rows.append(dict(actor='002',level=20,code=code,stamina=40,words=dict(both,**{key:before}),seed=seed,outside_battle=False))
        rows.append(dict(rows[-1],outside_battle=True,words=empty))
    for st in [0,39,40,59,60]:rows.append(dict(actor='002',level=1,code=250,stamina=st,words=both,seed=7,outside_battle=False))
    # R32 cure_weaken: 249 clears only the weaken word/flag and refreshes; 251 clears all four; 247 on a
    # weakened actor leaves the weaken (and its derived penalty) alone without a refresh.
    weakened=dict(both,weaken=0x50003)
    for actor in ['001','002','026','024']:
        for code,words in [(249,weakened),(249,dict(empty,weaken=0x70009)),(249,both),(251,weakened),(251,dict(empty,weaken=0x20001)),(247,weakened),(248,dict(empty,weaken=0x50003,paralysis=9))]:
            rows.append(dict(actor=actor,level=3 if actor!='002' else 20,code=code,stamina=19,words=words,seed=7,outside_battle=False))
    return rows

def model(c,draws):
    row=sources()[1][c['code']];words=dict(c['words']);cursor=0
    for key,field in [('attack_up','local_add_weapon_power'),('defense_up','local_add_defense')]:
        if c['outside_battle'] or field not in row or (words[key]&65535)>=9:continue
        power=words[key]>>16
        if not power:
            low,high=sorted(map(int,row[field].split(',')))
            if cursor>=len(draws) or draws[cursor]['bound']!=high-low+1 or not 0<=draws[cursor]['value']<=high-low:raise ValueError('Tactical item draw/order differs')
            power=low+draws[cursor]['value'];cursor+=1
        words[key]=power<<16|min(9,(words[key]&65535)+3)
    for field,key in CURE_WORDS.items():
        if row.get(field)=='1':words[key]=0
    if cursor!=len(draws):raise ValueError('Tactical item consumed extra RNG')
    return dict(words=words,flags=item_flags(words),stamina=min(60,c['stamina']+int(row.get('add_st',0))),hp=1,mp=0,exp=37)

def cure_refreshes(c):
    """For a pure cure item the 0x448840 count inside 0x409e40 is fixed: one for cure_weaken, none otherwise.
    Boost/stamina items refresh on their own branches and are not pinned here."""
    row=sources()[1][c['code']]
    if not cure_mask(row) or any(field in row for field in ['add_st','local_add_weapon_power','local_add_defense','add_hp','add_mp']):return None
    return 1 if row.get('cure_weaken')=='1' else 0

def derived(c,words):
    src=sources()[0][c['actor']];gear=[int(src.get(k,0)) for k in SLOTS]
    attributes={k:int(src[k]) for k in ATTRIBUTES}
    if words.get('weaken',0):
        # 0x448840 prelude: live attributes = base - weaken power (signed high word), floor 1.
        power=struct.unpack('<h',struct.pack('<H',words['weaken']>>16))[0]
        attributes={k:max(1,v-power) for k,v in attributes.items()}
    result=calculate(source_profile(src,sources()[2]),attributes,c['level'],gear,build()['items'],1,0,int(src['move_point']))
    result['attack']+=words['attack_up']>>16;result['defense']+=words['defense_up']>>16
    return {k:result[k] for k in ['attack','defense','speed','max_hp','max_mp','move_point']}

def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    src=sources()[0][c['actor']];gear=[int(src.get(k,0)) for k in SLOTS]
    put_actor(m,actor,c['actor'],c['level'],1,0,gear,c['words'])
    put(actor+0x38,c['words'].get('weaken',0));put(actor+0x24,item_flags(c['words']))
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+4,240);put(obj+8,240);put(actor+0xe8,c['stamina'])
    row=sources()[1][c['code']];record=0x20000000+176*c['code'];put(record+8,1)
    put(record+0x30,int(row.get('add_st',0)));put(record+0xa0,cure_mask(row))
    for field,off in [('local_add_weapon_power',0x74),('local_add_defense',0x7c)]:
        if field in row:
            low,high=map(int,row[field].split(','));put(record+off,(high&65535)<<16|(low&65535))
    steps=0;refreshes=0;pending=[];draws=[];phase='initial'
    def guard(_m,at,_n,_d):
        nonlocal steps,refreshes
        steps+=1
        allowed=[(0x448370,0x44b820)] if phase=='initial' else [(0x409e40,0x40a343),(0x409e10,0x409e35),(0x446ad0,0x446af9),(0x448370,0x44b820),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed tactical item callee {at:#x}')
        if at==0x448840:refreshes+=1
        if pending and pending[-1][0]==at:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<2I',stop,actor));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x448840,stop,count=14000)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Initial source refresh failed return')
    before={off:bytes(m.mem_read(actor+off,size)) for off,size in [(0x64,16),(0x90,16),(0xec,24),(0x138,32),(0x1a4,28)]}
    phase='item';initial_steps=steps;initial_refreshes=refreshes
    put(0x4c1e8c,1);put(0x4c3044,c['seed']);put(0x4c3040,0x87654321)
    m.mem_write(stack,struct.pack('<5I',stop,obj,c['code'],0,int(c['outside_battle'])));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x409e40,0x40a343,count=30000)
    if m.reg_read(UC_X86_REG_EIP)!=0x40a343 or pending:raise ValueError('Tactical item missed pre-audio boundary')
    actual=dict(words={k:get(actor+off) for k,(off,_) in ITEM_WORDS.items()},flags=get(actor+0x24),stamina=get(actor+0xe8),hp=get(actor+0xd8),mp=get(actor+0xe0),exp=get(actor+0x88))
    if actual!=model(c,draws):raise ValueError(f'Original tactical item differs: {c}, {actual}, {draws}')
    if cure_refreshes(c) not in [None,refreshes-initial_refreshes]:raise ValueError(f'Cure item refresh count differs: {c}, {refreshes-initial_refreshes}')
    for off,value in before.items():
        if bytes(m.mem_read(actor+off,len(value)))!=value:raise ValueError('Item changed inventory, base stats, level or equipment')
    values={k:get(actor+off) for k,off in [('attack',0xc0),('defense',0xb4),('speed',0xb8),('max_hp',0xdc),('max_mp',0xe4),('move_point',0x12c)]}
    if values!=derived(c,actual['words']):raise ValueError('Tactical item derived refresh differs')
    return dict(input=c,native=actual,draws=draws,derived=values,normal_return=False,entry='0x409e40',stop_address='0x40a343',instructions=steps-initial_steps,initial_refresh_return=True,refresh_calls=refreshes-initial_refreshes,base_inventory_unchanged=True)

def sampler_cases():
    return [dict(low=lo,high=hi,seed=seed) for lo,hi in [(5,10),(10,5),(7,7),(-4,2),(2,-4),(-8,-3)] for seed in [1,7,19]]

def scan_cases():
    rows=[[0]*8,[262,250,247,246,248,0,0,0],[246,247,248,0,0,0,0,0],[248,246,247,0,0,0,0,0],[250,262,263,0,0,0,0,247],
          [249,246,0,0,0,0,0,0],[250,251,249,0,0,0,0,0],[247,248,249,251,0,0,0,0]]
    return [dict(inventory=row,flags=bits) for row in rows for bits in [0,1,2,4,7,0x37,8,0xf,0x3f]]

def sampler_model(c,draws):
    lo,hi=sorted([c['low'],c['high']])
    if len(draws)!=1 or draws[0]['bound']!=hi-lo+1 or not 0<=draws[0]['value']<=hi-lo:raise ValueError('Packed sample differs')
    return lo+draws[0]['value']

def scan_model(c):
    # 0x40c230: negative flag bits 1/2/4/8 match item+0xa0 bits 0x80000000/0x40000000/0x20000000/0x10000000.
    items=sources()[1]
    def matches(code):
        mask=cure_mask(items[code]) if code else 0
        return any(c['flags']&flag and mask&bit for flag,bit in zip([1,2,4,8],CURE_BITS.values()))
    return next((i+1 for i,code in enumerate(c['inventory']) if matches(code)),0)

def helper(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    sampler='low' in c
    if sampler:
        args=[stop,(c['high']&65535)<<16|(c['low']&65535)];entry=0x409e10
        put(0x4c1e8c,1);put(0x4c3044,c['seed']);put(0x4c3040,0x87654321)
    else:
        entry=0x40c230;args=[stop,obj,c['flags']];put(0x4c1bc8,actor);put(obj+0xa4,0);put(0x4c1b40,0x20000000)
        for code in [246,247,248,249,250,251,262,263]:
            put(0x20000000+code*176+8,1);put(0x20000000+code*176+0xa0,cure_mask(sources()[1][code]))
        for i,code in enumerate(c['inventory']):put(actor+0x138+i*4,code)
    steps=0;pending=[];draws=[]
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        allowed=[(0x409e10,0x409e35),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)] if sampler else [(0x40c230,0x40c2d0)]
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unexpected tactical helper {at:#x}')
        if pending and pending[-1][0]==at:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4)))
    before=bytes(m.mem_read(actor,0x1fc));m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*len(args),*args));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(entry,stop,count=4096)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or pending or before!=bytes(m.mem_read(actor,0x1fc)):raise ValueError('Tactical helper failed normal return or mutated inventory')
    value=m.reg_read(UC_X86_REG_EAX);value=value-0x100000000 if value&0x80000000 else value
    if value!=(sampler_model(c,draws) if sampler else scan_model(c)):raise ValueError(f'Tactical helper mismatch {c} {value}')
    return dict(input=c,native=value,draws=draws,normal_return=True,instructions=steps)

def check(p):
    if p.get('schema')!='hsl_tactical_items_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Tactical evidence identity differs')
    if p['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']}:raise ValueError('Tactical source fields differ')
    for field,cases,model_func in [('applications',applications,model),('samplers',sampler_cases,sampler_model),('scans',scan_cases,lambda c,d:scan_model(c))]:
        if [r['input'] for r in p[field]]!=cases():raise ValueError('Tactical fixture coverage differs')
        for row in p[field]:
            if row['native']!=model_func(row['input'],row['draws']) or not 0<row['instructions']<(30000 if field=='applications' else 4096):raise ValueError('Tactical native outcome differs')
            if row['normal_return']!=(field!='applications'):raise ValueError('Tactical native boundary differs')
            if field=='applications':
                if row['entry']!='0x409e40' or row['stop_address']!='0x40a343' or not row['initial_refresh_return'] or not row['base_inventory_unchanged']:raise ValueError('Tactical application boundary differs')
                if row['derived']!=derived(row['input'],row['native']['words']):raise ValueError('Tactical derived refresh differs')
                if cure_refreshes(row['input']) not in [None,row['refresh_calls']]:raise ValueError('Tactical cure refresh count differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in p['anchors']]!=ANCHORS:raise ValueError('Tactical anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in p['anchors']))).hexdigest()!=ANCHOR_SHA or p['anchors_sha256']!=ANCHOR_SHA:raise ValueError('Tactical instruction digest differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS]
    p=dict(schema='hsl_tactical_items_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
           sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']},applications=[execute(base,mapped,c) for c in applications()],
           samplers=[helper(base,mapped,c) for c in sampler_cases()],scans=[helper(base,mapped,c) for c in scan_cases()],anchors=anchors,
           anchors_sha256=hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in anchors))).hexdigest(),
           limits=['Item prefix stops before audio/rendering and caller inventory/turn completion; no global engine equivalence.',
                   'Packed sampler and eight-slot cure helper return normally; no AI policy for self stamina or enhancement items is inferred.',
                   'Outside-battle input records the native exclusion only; remake exposes the four items in battle.',
                   'Source item fields, four source jobs and supplied conditions/actor memory are separate from natural gameplay.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return 'TACTICAL_ITEMS_NATIVE_PASS applications='+str(len(p['applications']))+' samplers='+str(len(p['samplers']))+' scans='+str(len(p['scans']))+' executed_now='+str(executed_now)+' anchors='+p['anchors_sha256']


TASK = ProbeTask('tactical_items', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
