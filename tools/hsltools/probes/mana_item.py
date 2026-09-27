"""Execute original item244 application from entry to its post-MP boundary.

The prefix includes the real source item-field read and original flying getter;
it stops before stamina, cures, renderer and item-handler completion.

Registry task mana_item (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mana_item_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_mana_item.json'

def cases():
    return [dict(mp=current,max_mp=cap,flags=flags,flying=flying)
            for current,cap in [(0,0),(0,19),(3,19),(19,19),(0,100),(70,100),(99,100)]
            for flags in [0,3,7] for flying in [False,True]]


def expected(c):
    _,items,_=sources();amount=int(items[244]['add_mp']);gain=min(amount,c['max_mp']-c['mp'])
    return dict(mp=c['mp']+gain,restored_mp=gain,flags=c['flags'])


def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);obj,actor,table,stack=0x10001000,0x10003000,0x10005000,0x1001ff00
    _,items,_=sources()
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actor);put(0x4c1b40,table);put(obj+0xa4,0);put(obj+4,240);put(obj+8,240)
    put(actor+0xa0,0x20000 if c['flying'] else 0);put(actor+0xd8,17);put(actor+0xdc,100)
    put(actor+0xe0,c['mp']);put(actor+0xe4,c['max_mp']);put(actor+0x24,c['flags'])
    for off in [0x30,0x34,0x3c]:put(actor+off,2)
    # Synthetic table slot1 carries exact source244 fields; actor/inventory untouched.
    put(table+176+8,1);put(table+176+0x28,int(items[244]['add_mp']))
    before=bytes(m.mem_read(actor,0x1fc));steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at==0x40a275:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x409e40,0x40a275),(0x446ad0,0x446af9)]):raise ValueError(f'Unreviewed mana item callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<4I',0x10000000,obj,1,0));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x409e40,0x10000000,count=4096)
    if m.reg_read(UC_X86_REG_EIP)!=0x40a275:raise ValueError('Mana item exceeded declared boundary')
    actual=dict(mp=get(actor+0xe0),restored_mp=get(0x4c1a48),flags=get(actor+0x24))
    after=bytes(m.mem_read(actor,0x1fc))
    if actual!=expected(c) or before[:0xe0]!=after[:0xe0] or before[0xe4:]!=after[0xe4:]:raise ValueError(f'Mana item result/unrelated state differs {c}: {actual}')
    return dict(input=c,native=actual,instructions=steps,normal_return=False,stop_address='0x40a275',entry='0x409e40',rng_calls=0)


def check(p):
    if p.get('schema')!='hsl_mana_item_native.v1' or p.get('exe_sha256')!=EXE_SHA or not p.get('native_execution'):raise ValueError('Mana evidence identity differs')
    if p['source_sha256']!=digest((TABLES/'ITEM.TXT').read_bytes()) or [r['input'] for r in p['cases']]!=cases():raise ValueError('Mana item coverage/source differs')
    for row in p['cases']:
        if row['native']!=expected(row['input']) or row['normal_return'] is not False or row['rng_calls']!=0 or row['stop_address']!='0x40a275' or row['entry']!='0x409e40' or not 0<row['instructions']<4096:raise ValueError('Mana item prefix differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());packet=dict(schema='hsl_mana_item_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
        source_sha256=digest((TABLES/'ITEM.TXT').read_bytes()),cases=[execute(base,mapped,c) for c in cases()],
        limits=['Source244 restores30 capped by missing MP, no RNG in this prefix; HP, statuses and inventory unchanged here.',
                'Stops before stamina/cure/display callbacks, not full item handler or native inventory transaction.',
                'Player/ally use and full-MP refusal reuse the current explicit remake item contract. No autonomous native AI mana-potion policy claimed.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return 'MANA_ITEM_NATIVE_PASS cases='+str(len(packet['cases']))+' executed_now='+str(executed_now)


TASK = ProbeTask('mana_item', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
