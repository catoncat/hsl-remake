"""Bounded full original Thief88/WingWarrior92 refresh on exact role/gear inputs.

No source parser, initialization-level randomization or UI is bypassed/claimed.
The common refresh executes twice, including dirty derived-cache replacement.

Registry task mobile_jobs (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mobile_jobs_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import source_profile, calculate, ATTRIBUTES, CAPS, SLOTS
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.job_stats import execute
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_mobile_jobs.json'

ACTORS=['004','006','028','036']
ANCHOR_SHA='d86fdd5270cee25193e417bc5fcf21295e59ec21b76e9c6996ab3f62fd249e61'
ANCHORS=[(0x449a55,16,'Job88 enters cap row8; its resistance terms remain separate from the shared thief-family suffix.'),
         (0x449d1d,390,'Thief-family HP/MP/attack/defense/magic/speed uses ordered integer arithmetic.'),
         (0x44a2e5,16,'Job92 enters cap row12; flying is not granted by this dispatch.'),
         (0x44a5b9,405,'Wing-family derived arithmetic follows its own resistance terms.'),
         (0x4786fc,8,'Job88 strength/dexterity/mind/constitution caps are92/96/74/90.'),
         (0x47871c,8,'Job92 caps are92/84/78/98.'),
         (0x44b840,4,'Stat-dispatch row8 routes job88 to449a55.'),
         (0x44b850,4,'Stat-dispatch row12 routes job92 to44a2e5.')]

def fixtures():
    players,_,defines=sources();rows=[]
    for code in ACTORS:
        actor=players[code];attrs={k:int(actor[k]) for k in ATTRIBUTES}
        base=dict(actor=code,name='initial',attributes=attrs,level=int(actor.get('level',1)),
                  equipment=[int(actor.get(k,0)) for k in SLOTS],hp=9999,mp=9999,
                  mode=defines[actor['mode']],base_move=int(actor['move_point']))
        rows.append(base)
        for level in [2,9,10,19,20,21,44,79,80,99]:rows.append(dict(base,name=f'level_{level}',level=level,hp=7,mp=3))
        for key in ATTRIBUTES:rows.append(dict(base,name=key+'_plus1',level=2,attributes=dict(attrs,**{key:attrs[key]+1})))
        rows.append(dict(base,name='caps',level=99,attributes=dict(zip(ATTRIBUTES,CAPS[defines[actor['job']]]))))
        rows.append(dict(base,name='empty',equipment=[0]*6,hp=1,mp=0))
        for mode in [0x10000,0x20000,0x40000]:rows.append(dict(base,name='mode_'+str(mode),mode=mode,level=17))
        for label,gear in [('repeat',[108 if defines[actor['job']]==88 else 43,151,123,181,227,229]),
                           ('range_move',[102 if defines[actor['job']]==88 else 43,151,123,193,233,236]),
                           ('resist',[102 if defines[actor['job']]==88 else 43,151,123,181,207,208])]:
            # These slots are explicit arithmetic fixtures, not an equip-eligibility claim.
            rows.append(dict(base,name=label,equipment=gear,level=20))
    return rows

def check(packet):
    if packet.get('schema')!='hsl_mobile_jobs_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Mobile jobs identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H']}:raise ValueError('Mobile jobs table hashes differ')
    if [r['input'] for r in packet['cases']]!=fixtures():raise ValueError('Mobile jobs coverage differs')
    players,_,defines=sources();catalog=equipment_data()['items']
    for row in packet['cases']:
        c=row['input'];profile=source_profile(players[c['actor']],defines);profile['source']['mode']=c['mode']
        expected=calculate(profile,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        if row['profile']!=profile or len(row['native'])!=2:raise ValueError('Mobile job profile or repeated return differs')
        if any(r['values']!=expected or r['normal_return'] is not True or not 0<r['instructions']<12000 for r in row['native']):raise ValueError('Mobile job arithmetic/return differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:raise ValueError('Mobile job anchors differ')
    raw=bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))
    if hashlib.sha256(raw).hexdigest()!=ANCHOR_SHA or packet['anchors_sha256']!=ANCHOR_SHA:raise ValueError('Mobile job instruction fingerprint differs')
    for job,index in [(88,4),(92,5)]:
        if list(struct.unpack('<4H',bytes.fromhex(packet['anchors'][index]['bytes'])))!=CAPS[job]:raise ValueError('Cap row differs')
    for index,address in [(6,0x449a55),(7,0x44a2e5)]:
        if struct.unpack('<I',bytes.fromhex(packet['anchors'][index]['bytes']))[0]!=address:raise ValueError('Dispatch branch differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS]
    packet=dict(schema='hsl_mobile_jobs_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                sources={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H']},
                cases=[execute(base,mapped,c) for c in fixtures()],anchors=anchors,
                anchors_sha256=hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in anchors))).hexdigest(),
                limits=['004 level1 is source-declared;006/028/036 level1 is an explicit remake fixed-level input, not native level_adjust_range initialization.',
                        'Source role mode remains independent of present player/AI authority. Flight comes from PLAYERS.move_fly, not job92.',
                        'Full derived refresh returns are original instructions; source loaders, automatic stat allocation, learning and unsupported specials are separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'MOBILE_JOBS_NATIVE_PASS cases={len(packet["cases"])} full_returns={2*len(packet["cases"])} executed_now={executed_now} sha={packet["anchors_sha256"]}'


TASK = ProbeTask('mobile_jobs', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
