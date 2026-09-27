#!/usr/bin/env python3
"""Execute only native stat refresh in isolated x86 emulation (analysis dependency: unicorn)."""
import argparse
import json
from pathlib import Path
import re
import struct
from hsltools.data.first_skill import blocks, digest, TABLES
from hsltools.paths import ORIGINAL_EXE


DEFAULT_ACTORS = ('1','21','23','24','26')


def probe(exe, actor_codes=DEFAULT_ACTORS):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
    raw=exe.read_bytes()
    if digest(raw) != 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7':
        raise ValueError('Unsupported EXE: this probe requires the documented hsl01.exe SHA256')
    pe=struct.unpack_from('<I',raw,60)[0]
    n=struct.unpack_from('<H',raw,pe+6)[0]
    optional=struct.unpack_from('<H',raw,pe+20)[0]
    base=struct.unpack_from('<I',raw,pe+52)[0]
    image_size=struct.unpack_from('<I',raw,pe+80)[0]
    header=(TABLES/'TYPE.H').read_bytes().decode('cp950')
    defines={k:int(v,0) for k,v in re.findall(r'#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',header)}
    players={b['code']:b for b in blocks((TABLES/'PLAYERS.TXT').read_bytes(),'character')}
    items={b['code']:b for b in blocks((TABLES/'ITEM.TXT').read_bytes(),'item')}
    actor_fields={'str':0x64,'dex':0x68,'mind':0x6c,'con':0x70,'level':0x9c,'attack_power':0x1a4,'magic_attack_power':0x1a8,'defense':0x1ac,'speed':0x1b0,'move_point':0x130}
    item_fields={'attack_damage':0x88,'hit_ratio':0x98,'add_attack':0x20,'add_defense':0x3c,'add_speed':0x38,'add_move':0x34,'add_hp':0x2c,'add_mp':0x28,'add_magic_attack':0x24}
    equipment={'weapon_equip':0xec,'head_equip':0xf0,'armor_equip':0xf4,'foot_equip':0xf8,'other1_equip':0xfc,'other2_equip':0x100}
    equipment_limit = ('No status effects, buffs or inventory passives. Equipment fields populated from the first-battle templates only.'
                       if tuple(actor_codes) == DEFAULT_ACTORS else
                       'No status effects, buffs or inventory passives. Equipment fields are populated from each requested PLAYERS template.')
    result={'schema':'hsl_native_stat_probe.v1','evidence_tier':'static-derived','exe_sha256':digest(raw),'entry':'0x448840','inputs_sha256':{name:digest((TABLES/name).read_bytes()) for name in ['PLAYERS.TXT','ITEM.TXT','TYPE.H']},'actors':{},'limits':['Synthetic table initialization; no native parser or NPC level adjustment.', 'Spell presence is a synthetic boolean sentinel, not recovered native spell IDs.', equipment_limit, 'Emulated stat refresh is not a complete original-game runtime measurement.']}
    for code in actor_codes:
        if code not in players:
            raise ValueError('missing requested PLAYERS actor code '+str(code))
        row=players[code]
        samples={}
        for equipped in [False,True]:
            uc=Uc(UC_ARCH_X86,UC_MODE_32)
            uc.mem_map(base,(image_size+4095)&~4095)
            for i in range(n):
                size,rva,rs,ptr=struct.unpack_from('<IIII',raw,pe+24+optional+40*i+8)
                if rs:uc.mem_write(base+rva,raw[ptr:ptr+rs])
            uc.mem_map(0x10000000,0x10000)
            uc.mem_map(0x20000000,0x10000)
            uc.mem_map(0x21000000,0x20000)
            actor=0x20000000
            def put(address,value):uc.mem_write(address,struct.pack('<I',value&0xffffffff))
            for name,offset in actor_fields.items():put(actor+offset,int(row.get(name,'0')))
            put(actor+0x18,defines[row['job']]);put(actor+0x28,defines[row['mode']])
            # 0x44b7b8..0x44b815 only ORs these six slots to detect magic presence.
            # A synthetic nonzero sentinel models that predicate, not spell IDs.
            if any(row.get('magic_'+element, '0') != '0' for element in ['other','earth','water','wind','fire','mind']):
                put(actor+0x174, 1)
            put(actor+0x1b4,(int(row.get('hit_point',0))<<16)|int(row.get('magic_point',0)))
            for i,key in enumerate(['earth','water','air','fire','mind']):put(actor+0x118+4*i,int(row.get('resist_'+key,0)))
            put(0x4c1b40,0x21000000)
            if equipped:
                for name,offset in equipment.items():
                    item_code=int(row.get(name,0));put(actor+offset,item_code)
                    if not item_code:continue
                    item=items[str(item_code)];address=0x21000000+item_code*176
                    put(address+8,defines[item['type']])
                    for field,field_offset in item_fields.items():put(address+field_offset,int(item.get(field,0)))
            stop=0x10000000
            stack=0x1000fff0
            put(stack,stop);put(stack+4,actor);uc.reg_write(UC_X86_REG_ESP,stack)
            def guard(machine,address,size,user):
                if not 0x448370<=address<0x44b820:raise ValueError('unexpected execution address '+hex(address))
            uc.hook_add(UC_HOOK_CODE,guard)
            uc.emu_start(0x448840,stop,count=10000)
            if uc.reg_read(UC_X86_REG_EIP) != stop:
                raise RuntimeError('instruction budget exhausted')
            fields={'max_hp':0xdc,'max_mp':0xe4,'attack':0xc0,'defense':0xb4,'speed':0xb8,'hit_rate':0xbc,'magic_attack':0xd0,'exp_threshold':0x8c}
            samples['equipped' if equipped else 'unequipped']={name:struct.unpack('<i',uc.mem_read(actor+offset,4))[0] for name,offset in fields.items()}
        result['actors'][code.zfill(3)]={'base':{name:row.get(name,'0') for name in ['str','dex','mind','con','level','hit_point','magic_point','job','mode']},**samples}
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path,default=ORIGINAL_EXE);p.add_argument('--output',type=Path,required=True);p.add_argument('--actors',nargs='+',default=list(DEFAULT_ACTORS));a=p.parse_args()
    codes=[str(int(code)) for code in a.actors]
    result=probe(a.exe,codes);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result['actors'],ensure_ascii=False,indent=2))
