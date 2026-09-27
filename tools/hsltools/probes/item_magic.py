"""Execute only new item-strength inputs through existing original stat kernels.

Registry task item_magic (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_item_magic_probe.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path

from hsltools.data.equipment import build
from hsltools.model.jobs import SLOTS, ATTRIBUTES, source_profile, calculate
from hsltools.paths import ROOT
from hsltools.probes import stat_magic as stat
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_item_magic.json'

def cases():
    result=[]
    for kind in ['attack_up','defense_up','dispel']:
        template=copy.deepcopy(next(c for c in stat.fixtures() if c['kind']==kind))
        for strength in [5,10]:
            c=copy.deepcopy(template)
            c['words'].update(attack_up=strength<<16|3,defense_up=strength<<16|3)
            result.append(c)
    return result

def ticks():
    return [dict(stat.initial_words(),attack_up=power<<16|remaining,defense_up=power<<16|remaining)
            for power in [5,10] for remaining in [1,3]]

def check(p):
    stat.check(json.loads(stat.PACKET.read_text()))
    if p.get('schema')!='hsl_item_magic_native.v1' or p.get('exe_sha256')!=stat.EXE_SHA or p.get('native_execution') is not True:raise ValueError('Item/magic identity differs')
    if [r['input'] for r in p['applications']]!=cases() or [r['input'] for r in p['ticks']]!=ticks():raise ValueError('Item/magic coverage differs')
    for row in p['applications']:
        if row['native']!=stat.model(row['input'],row['draws']) or row['normal_return'] or row['stop_address']!='0x40b831' or not 0<row['instructions']<18000:raise ValueError('Item/magic prefix differs')
        c=row['input'];src=stat.sources()[0][c['actor']]
        v=calculate(source_profile(src,stat.sources()[2]),{k:int(src[k]) for k in ATTRIBUTES},c['level'],[int(src.get(k,0)) for k in SLOTS],build()['items'],c['hp'],c['mp'],int(src['move_point']))
        v['attack']+=row['native']['words']['attack_up']>>16;v['defense']+=row['native']['words']['defense_up']>>16
        if row['derived']!={k:v[k] for k in row['derived']}:raise ValueError('Mixed item/spell derived values differ')
    for row in p['ticks']:
        wanted={k:(v-1 if v&65535>1 else 0) for k,v in row['input'].items()}
        if row['native']!=wanted or not row['normal_return'] or not 0<row['instructions']<18000:raise ValueError('Item/magic expiry differs')
        src=stat.sources()[0]['002']
        v=calculate(source_profile(src,stat.sources()[2]),{k:int(src[k]) for k in ATTRIBUTES},3,[int(src.get(k,0)) for k in SLOTS],build()['items'],10,5,int(src['move_point']))
        if row['derived']!={'attack':v['attack']+(wanted['attack_up']>>16),'defense':v['defense']+(wanted['defense_up']>>16)}:raise ValueError('Item-strength expiry derived values differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=stat.image(exe.read_bytes())
    p=dict(schema='hsl_item_magic_native.v1',exe_sha256=stat.EXE_SHA,native_execution=True,evidence_tier='static-derived',
           applications=[stat.execute(base,mapped,c) for c in cases()],ticks=[stat.execute_tick(base,mapped,w) for w in ticks()],
           limits=['Same pinned original helper/refresh/tick code and boundaries as original_stat_magic.json; these cases add actual item-strength5/10 inputs only.',
                   'No original gameplay, full dispatcher, audio/render or global RNG identity is claimed.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return 'ITEM_MAGIC_NATIVE_PASS applications=6 ticks=4 executed_now='+str(executed_now)


TASK = ProbeTask('item_magic', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
