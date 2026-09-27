"""Bounded original Water Strike numeric returns and per-target HP prefixes.

Registry task water_strike (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_water_strike_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path

from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.magic_damage import execute, expected
from hsltools.probes.status_roll import EXE_SHA, image, independent, run_case
from hsltools.sources.tables import TABLES, digest
from hsltools.data.water_strike import definitions
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_water_strike.json'

def fixtures():
    field = definitions()['water']['fields']
    low, high = map(int, field['damage'].split(','))
    common = dict(spell='water', proc=0, channel=0, low=low, high=high,
                  hit_ratio=int(field['hit_ratio']), status_hit_ratio=0,
                  hit_bonus=0,magic_hit_bonus=0,no_attack=False,element=1)
    rows = [dict(common,level=level,mind=mind,magic_attack=power,resistance=resist,
                 seed=[seed,0x87654321])
            for level,mind,power in [(4,21,40),(12,35,80)]
            for resist in [0,25,80] for seed in [1,7,19]]
    rows += [dict(rows[0],hit_ratio=rate,hit_bonus=bonus,magic_hit_bonus=gear,no_attack=disabled)
             for rate,bonus,gear,disabled in [(0,0,0,False),(0,0,0,True),(0,7,95,False),(50,0,0,False)]]
    return rows


def applications():
    return [dict(row,hp=hp) for row in fixtures() for hp in [1,100]]


def check(packet):
    if packet.get('schema') != 'hsl_native_water_strike.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing original execution identity')
    if packet['source_magic_sha256'] != digest((TABLES/'MAGIC.TXT').read_bytes()) or packet['definition'] != definitions():
        raise ValueError('Water Strike source changed')
    if [row['input'] for row in packet['rolls']] != fixtures() or [row['input'] for row in packet['applications']] != applications():
        raise ValueError('Native fixture coverage differs')
    for row in packet['rolls']:
        if row['normal_return'] is not True or row['native'] != independent(row['input'],row['draws']) or not 0 < row['instructions'] < 4096:
            raise ValueError('Invalid numeric full return')
    for row in packet['applications']:
        if row['normal_return'] is not False or row['stop_address'] not in ['0x40ab87','0x40abb0'] or row['native'] != expected(row['input'],row['draws']) or not 0 < row['instructions'] < 4096:
            raise ValueError('Invalid HP prefix boundary')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_water_strike.v1',exe_sha256=EXE_SHA,native_execution=True,
                evidence_tier='static-derived',source_magic_sha256=digest((TABLES/'MAGIC.TXT').read_bytes()),
                definition=definitions(),rolls=[run_case(base,mapped,c) for c in fixtures()],
                applications=[execute(base,mapped,c) for c in applications()],
                functions={'numeric':'0x40a7b0','apply':'0x40aa80','random':'0x42c780'},
                limits=['Original numeric helper returns; application stops before display/EXP callbacks, not a full cast.',
                        'Synthetic actor values test actual water element1, source damage/hit, resistance and current HP caps.',
                        'Cross range is source table data. Remake per-target order, whole-cast atomicity, global RNG identity and rendering clock are separate claims.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'WATER_STRIKE_NATIVE_PASS rolls={len(packet["rolls"])} applications={len(packet["applications"])} executed_now={executed_now}'


TASK = ProbeTask('water_strike', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
