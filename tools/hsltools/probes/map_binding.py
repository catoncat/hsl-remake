"""Check bounded original OBS shape-binding evidence; execute only when requested.

Registry task map_binding (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_map_binding_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.shp import parse_shp
from hsltools.sources.tables import blocks
from hsltools.data.world_map import PakReader
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_map_binding.json'

STOP, STACK = 0x10000000, 0x1001f000
OBJ, TABLE, STRINGS, REGISTRY = 0x10006000, 0x10001000, 0x10003000, 0x10005000
NAMES = sorted(['SHAPE01\\LEVEL08.SHP','SHAPE31\\LEVEL32.SHP','SHAPE31\\LEVEL33.SHP',
                'SHAPE41\\LEVEL55.SHP','SHAPE41\\LEVEL56.SHP','SHAPE41\\LEVEL58.SHP'])
ANCHORS = [(0x477c30,4,'PROCESS.DEF index1 resolves defProcIconBG to430370.'),
           (0x45de9d,62,'OBS obj_Process_Code populates object+64 before callback lookup/installation.'),
           (0x45e0f7,33,'OBS obj_Data9 numeric reader destination is object+ac.'),
           (0x45e145,78,'OBS obj_Shape_Name field is read and searched by name; packed shape index writes before asset IO.'),
           (0x430370,151,'Map object callback initialization and Data9-dependent ordinary update.'),
           (0x46dd50,164,'String field lookup over the parsed source-node list.'),
           (0x45fc01,164,'Case-insensitive sorted shape-name search with200-iteration bound and optional symbol fallback.')]
ANCHOR_SHA='f708f878c1f69bfe8ab8d660fe69a4b624c0545e1318204f02f42eb1aebf1721'
SOURCE_SHA='d4951b8c25098ecec448358e17282756903b23b8bc4ffe803b8edd0a173c5c7b'

def digest(value):return hashlib.sha256(value).hexdigest()

def source_digest(value):
    return digest(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())

def source_records(root):
    reader=PakReader(root);bindings=[];absent=[]
    process=reader.read('@:\\data\\PROCESS.DEF')
    definitions={k:int(v) for k,v in re.findall(r'^(\w+)\s*=\s*(\d+)',process.decode('cp950'),re.M)}
    assert definitions['defProcIconBG']==1
    for member in sorted(set(reader.names())):
        found=re.search(r'obj-(\d+)\.obs$',member,re.I)
        if not found:continue
        raw=reader.read(member)
        managers=[row for row in blocks(raw,'Object') if row.get('obj_Process_Code')=='defProcIconBG']
        if not managers:
            absent.append({'level':int(found[1]),'member':member,'sha256':digest(raw),'reason':'No defProcIconBG record in this OBS; no fallback map is inferred.'})
            continue
        if len(managers)!=1:raise ValueError('Ambiguous source map object: '+member)
        row=managers[0];shape_member=reader.find('@:\\'+row['obj_Shape_Name'])
        if shape_member is None:raise ValueError('Missing exact source map: '+member)
        shape=reader.read(shape_member);meta=parse_shp(shape)
        bindings.append({'level':int(found[1]),'obs_member':member,'obs_sha256':digest(raw),'object':row,
                         'shape_member':shape_member,'shape_sha256':digest(shape),'shape_size':[meta['width'],meta['height']]})
    return {'process_member':'@:\\data\\PROCESS.DEF','process_sha256':digest(process),'process_index':1,
            'bindings':sorted(bindings,key=lambda r:r['level']),'without_map_manager':absent}

class Native:
    def __init__(self,base,mapped):
        from unicorn import Uc,UC_ARCH_X86,UC_MODE_32
        self.m=Uc(UC_ARCH_X86,UC_MODE_32);self.m.mem_map(base,len(mapped));self.m.mem_write(base,bytes(mapped))
        self.m.mem_map(0x10000000,0x20000)
        self.put(0x4c3040,0x12345678);self.put(0x4c3044,0x87654321)
        self.put(0x4c27b8,0) # Reviewed ASCII comparison path; locale branch is not exercised.

    def put(self,at,value):self.m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(self,at):return struct.unpack('<I',self.m.mem_read(at,4))[0]

    def call(self,entry,args,allowed,stops=(),prefix=False,budget=100000):
        from unicorn import UC_HOOK_CODE
        from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP,UC_X86_REG_EAX,UC_X86_REG_EBP
        steps=0;callees=[]
        def guard(_m,at,_size,_data):
            nonlocal steps
            if at in stops:self.m.emu_stop();return
            if not any(lo<=at<hi for lo,hi in allowed):raise ValueError('Unreviewed map binding instruction '+hex(at))
            steps+=1
            if at in [0x46dd50,0x45fc01]:callees.append(hex(at))
        hook=self.m.hook_add(UC_HOOK_CODE,guard)
        origin=STACK-0x80 if prefix else STACK
        if prefix:self.m.reg_write(UC_X86_REG_EBP,STACK)
        else:self.m.mem_write(STACK,struct.pack('<'+'I'*(len(args)+1),STOP,*[a&0xffffffff for a in args]))
        self.m.reg_write(UC_X86_REG_ESP,origin)
        try:self.m.emu_start(entry,STOP,count=budget)
        finally:self.m.hook_del(hook)
        end=self.m.reg_read(UC_X86_REG_EIP)
        if end not in (STOP,*stops):raise ValueError('Map binding instruction budget exhausted at '+hex(end))
        normal=end==STOP
        if self.m.reg_read(UC_X86_REG_ESP)!=origin+(4 if normal else 0):raise ValueError('Map binding caller stack changed')
        if [self.get(0x4c3040),self.get(0x4c3044)]!=[0x12345678,0x87654321]:raise ValueError('Unexpected original RNG mutation')
        return {'entry':hex(entry),'stop_address':hex(end),'normal_return':normal,'instructions':steps,'callees':callees,'rng_unchanged':True,'eax':self.m.reg_read(UC_X86_REG_EAX)}

def prefix_case(base,mapped,binding,lower,missing):
    n=Native(base,mapped);field=binding['object']['obj_Shape_Name'];value=field.lower() if lower else field
    n.put(0x4c24b4,TABLE);n.put(0x4c25c8,0x1000);n.put(0x4c24b0,STRINGS)
    n.put(TABLE+11,0x20);n.put(TABLE+0x20,0);n.put(TABLE+0x24,0x100);n.put(TABLE+0x2c,0)
    n.m.mem_write(STRINGS,b'obj_Shape_Name\0');n.m.mem_write(STRINGS+0x100,value.encode()+b'\0')
    available=[name for name in NAMES if not missing or name!=field]
    n.put(0x4bbb38,len(available));n.put(0x4bbb3c,REGISTRY);n.put(0x4bb92c,1);n.put(0x4bb930,-1)
    for i,name in enumerate(available):
        addr=REGISTRY+0x100+i*0x100;n.put(REGISTRY+i*4,addr);n.m.mem_write(addr,name.encode()+b'\0')
    n.put(STACK-8,0);n.put(0x4a19d4,OBJ);n.put(OBJ+0x30,0x34563456)
    before=[bytes(n.m.mem_read(a,l)) for a,l in [(TABLE,0x40),(STRINGS,0x200),(REGISTRY,0x800)]]
    proof=n.call(0x45e145,[],[(0x45e145,0x45e193),(0x46dd50,0x46ddf4),(0x45fc01,0x45fca5),(0x472ec0,0x472f4c)],(0x45e172,0x45e193),True)
    expected=0x34563456 if missing else available.index(field)*0x10001
    assert proof['stop_address']==('0x45e172' if missing else '0x45e193') and n.get(OBJ+0x30)==expected
    assert before==[bytes(n.m.mem_read(a,l)) for a,l in [(TABLE,0x40),(STRINGS,0x200),(REGISTRY,0x800)]]
    return {'input':{'level':binding['level'],'source_field':field,'parsed_value':value,'registry':available,'missing':missing,'lookup_symbol_fallback_disabled':True},
            'proof':proof,'packed_shape_before':0x34563456,'packed_shape_after':n.get(OBJ+0x30),'source_and_registry_unchanged':True}

def callback_case(base,mapped,phase,data9,shape):
    n=Native(base,mapped)
    for off,value in [(0,7),(4,512),(8,384),(12,99),(0x28,9),(0x30,shape*0x10001),(0x64,1),(0x80,0x20000005),(0xac,data9)]:n.put(OBJ+off,value)
    n.put(0x4c1cc0,13);n.put(0x4c1cc4,17)
    before=bytes(n.m.mem_read(OBJ,0xb0))
    if phase=='initialize':message=0x20000000;stops=()
    elif phase=='ordinary':message=0;stops=() if data9 else (0x4303eb,)
    else:message=-3;stops=()
    proof=n.call(0x430370,[OBJ,message],[(0x430370,0x430407)],stops,budget=256)
    expected=bytearray(before)
    def put(off,value):struct.pack_into('<I',expected,off,value&0xffffffff)
    if phase=='initialize':
        put(4,0);put(8,0);put(12,3);put(0x80,0x100005)
        if not data9:struct.pack_into('<H',expected,0x30,0xffff)
    elif phase=='ordinary' and data9:put(0,13);put(0x28,17)
    assert bytes(n.m.mem_read(OBJ,0xb0))==expected
    return {'input':{'phase':phase,'data9':data9,'shape_index':shape},'proof':proof,
            'object_before_hex':before.hex(),'object_after_hex':bytes(expected).hex(),'only_expected_fields_changed':True}

def check(packet):
    if packet.get('schema')!='hsl_native_map_binding.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Map binding native identity differs')
    if source_digest(packet['sources'])!=SOURCE_SHA:
        raise ValueError('Map binding source index differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:
        raise ValueError('Map binding instruction anchors differ')
    if digest(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors'])))!=ANCHOR_SHA or packet['anchors_sha256']!=ANCHOR_SHA:
        raise ValueError('Map binding original instruction fingerprint differs')
    sources={r['level']:r for r in packet['sources']['bindings']}
    expected_inputs=[]
    for level in [32,33,55,56,58,60,61,66,901]:
        field=sources[level]['object']['obj_Shape_Name']
        for lower,missing in [(False,False),(True,False),(False,True)]:
            expected_inputs.append({'level':level,'source_field':field,'parsed_value':field.lower() if lower else field,
                                    'registry':[s for s in NAMES if not missing or s!=field],'missing':missing,'lookup_symbol_fallback_disabled':True})
    if [r['input'] for r in packet['prefixes']]!=expected_inputs:
        raise ValueError('Map binding prefix coverage differs')
    for r in packet['prefixes']:
        c=r['input'];p=r['proof'];expected=0x34563456 if c['missing'] else c['registry'].index(c['source_field'])*0x10001
        if (p['entry'],p['stop_address'],p['normal_return'],p['callees'])!=('0x45e145','0x45e172' if c['missing'] else '0x45e193',False,['0x46dd50','0x45fc01']):
            raise ValueError('Map binding prefix boundary differs')
        if r['packed_shape_before']!=0x34563456 or r['packed_shape_after']!=expected or r['source_and_registry_unchanged'] is not True or p['rng_unchanged'] is not True or not 0<p['instructions']<100000:
            raise ValueError('Map binding prefix writes or side effects differ')
    cases=[{'phase':phase,'data9':data9,'shape_index':shape} for phase in ['initialize','ordinary','ignored_message'] for data9 in [0,1] for shape in [0,1,17]]
    if [r['input'] for r in packet['callbacks']]!=cases:raise ValueError('Map callback coverage differs')
    for r in packet['callbacks']:
        c=r['input'];p=r['proof'];before=bytearray(0xb0)
        for off,value in [(0,7),(4,512),(8,384),(12,99),(0x28,9),(0x30,c['shape_index']*0x10001),(0x64,1),(0x80,0x20000005),(0xac,c['data9'])]:
            struct.pack_into('<I',before,off,value)
        expected=bytearray(before)
        if c['phase']=='initialize':
            for off,value in [(4,0),(8,0),(12,3),(0x80,0x100005)]:struct.pack_into('<I',expected,off,value)
            if not c['data9']:struct.pack_into('<H',expected,0x30,0xffff)
        elif c['phase']=='ordinary' and c['data9']:
            struct.pack_into('<I',expected,0,13);struct.pack_into('<I',expected,0x28,17)
        normal=c['phase']!='ordinary' or c['data9']==1
        if (p['entry'],p['stop_address'],p['normal_return'])!=('0x430370',hex(STOP) if normal else '0x4303eb',normal):
            raise ValueError('Map callback return/stop differs')
        if r['object_before_hex']!=before.hex() or r['object_after_hex']!=expected.hex() or r['only_expected_fields_changed'] is not True or p['rng_unchanged'] is not True or not 0<p['instructions']<256:
            raise ValueError('Map callback fields or side effects differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE (sibling PAKs read-only) and assemble the packet."""
    root=exe.parent;base,mapped=image(exe.read_bytes())
    sources=source_records(root)
    binding={r['level']:r for r in sources['bindings']}
    prefixes=[prefix_case(base,mapped,binding[level],low,missing) for level in [32,33,55,56,58,60,61,66,901]
              for low,missing in [(False,False),(True,False),(False,True)]]
    callbacks=[callback_case(base,mapped,phase,data9,shape) for phase in ['initialize','ordinary','ignored_message'] for data9 in [0,1] for shape in [0,1,17]]
    anchors=[{'address':hex(at),'bytes':bytes(mapped[at-base:at-base+length]).hex(),'meaning':meaning} for at,length,meaning in ANCHORS]
    packet={'schema':'hsl_native_map_binding.v1','exe_sha256':EXE_SHA,'native_execution':True,'evidence_tier':'static-derived',
            'sources':sources,'prefixes':prefixes,'callbacks':callbacks,'anchors':anchors,
            'anchors_sha256':digest(bytes.fromhex(''.join(a['bytes'] for a in anchors))),
            'limits':['OBS source names are real; source node/string arenas and the preloaded sorted shape registry are explicit synthetic inputs.',
                      'Shape registry flag4bb92c=1 disables the lookup helper internal symbol fallback in these fixtures. Missing-name prefixes do not establish the full native fallback policy.',
                      'OBS loader45dc5c is executed only from45e145 to45e193, before asset loading; on missing names stop45e172 before symbol fallback. Not a full parser/PAK loader return.',
                      'Map callback430370 returns for Data9=1 initialization/ordinary/ignored messages. Data9=0 ordinary stops before drawing; no renderer or free callback is executed.',
                      'The source fields select an exact map name, not a level-number filename or preceding map. This does not establish original wall-clock timing or global map renderer parity.',
                      '154 of157 named OBJ-NNN.OBS files have one map manager; OBJ000/998/999 have none and remain explicitly unbound.']}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    if not executed_now:
        return 'MAP_BINDING_NATIVE_PASS bindings=154 prefixes=27 callbacks=18 executed_now=False'
    return 'MAP_BINDING_NATIVE_PASS bindings=%d prefixes=%d callbacks=%d executed_now=True sha=%s'%(len(packet['sources']['bindings']),len(packet['prefixes']),len(packet['callbacks']),packet['anchors_sha256'])


TASK = ProbeTask('map_binding', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
