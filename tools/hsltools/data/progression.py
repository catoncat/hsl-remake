"""Extract template level/EXP/kill-EXP/stamina fields from PLAYERS.TXT.

Registry task progression_data (family actors): output
content/imported/hsl/chapter01/progression.json. Bodies moved verbatim from the former hsl_progression_data.py.
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import blocks, digest, TABLES

OUTPUT=Path('content/imported/hsl/chapter01/progression.json')

def build():
    raw=(TABLES/'PLAYERS.TXT').read_bytes()
    actors={b['code'].zfill(3):{k:int(b[k]) for k in ('level','exp','kill_exp')} for b in blocks(raw,'character') if b.get('code') in ('1','2','21','23','24','25','26')}
    large=next(b for b in blocks(raw,'character') if b.get('code')=='39')
    # Source039 declares kill_exp, but no initial level/EXP. Apply the same
    # explicit fixed-level development policy as its bounded refresh fixture.
    actors['039']={'level':1,'exp':0,'kill_exp':int(large['kill_exp'])}
    for row in blocks(raw,'character'):
        if row['code'] in ['3','4','6','28','36','61','62']:
            actors[row['code'].zfill(3)]={'level':int(row.get('level',1)),'exp':int(row.get('exp',0)),'kill_exp':int(row.get('kill_exp',0))}
    from hsltools.model.jobs import CAMPAIGN_ACTORS
    for row in blocks(raw,'character'):
        code=row['code'].zfill(3)
        if code in CAMPAIGN_ACTORS:
            actors[code]={'level':int(row.get('level',1)),'exp':int(row.get('exp',0)),'kill_exp':int(row.get('kill_exp',0))}
    assert len(actors)==65
    # The stamina word (+0xe8) every actor is constructed with: 0x44cb10 copies the whole PLAYERS
    # template record (0x44cb41 for a first registration, 0x44cb88 for an NPC); an undeclared
    # field is 0 (only 001 20 and 006 8 declare one). original_stamina.md#开场实测.
    rows={b['code'].zfill(3):b for b in blocks(raw,'character')}
    for code,row in actors.items(): row['stamina']=int(rows[code].get('stamina',0))
    return {'schema':'hsl_progression_templates.v1','evidence_tier':'resource-derived','source_sha256':digest(raw),'actors':actors,'note':'Unadjusted source template fields; undeclared NPC level1/EXP0 are construction inputs, not final encounter levels. InitialRosterGrowth/EntryGrowth apply the reviewed native adjustment. Final EXP is resolved separately by ExperienceRules. stamina is the PLAYERS template word an actor is constructed with (first registration / NPC); a carried player enters at 0 unless the previous script ran actKeepPlayerST (CampaignCarryRules).'}

def check_exe(path):
    raw=path.read_bytes()
    assert digest(raw)=='f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7'
    pe=struct.unpack_from('<I',raw,60)[0]
    base=struct.unpack_from('<I',raw,pe+52)[0]
    count=struct.unpack_from('<H',raw,pe+6)[0]
    optional_size=struct.unpack_from('<H',raw,pe+20)[0]
    anchors={0x44b678:'8b869c000000408d04808d0480d1e03dd007000089868c0000007e0ac7868c000000d0070000',
             0x43a235:'8b888c0000008b90880000002bd1'}
    for va,hex_bytes in anchors.items():
        expected=bytes.fromhex(hex_bytes)
        for i in range(count):
            size,rva,raw_size,offset=struct.unpack_from('<IIII',raw,pe+24+optional_size+40*i+8)
            if rva<=va-base<rva+max(size,raw_size):
                start=offset+va-base-rva
                assert raw[start:start+len(expected)]==expected
                break
        else:raise ValueError('unmapped instruction anchor')
    print('NATIVE_EXP_THRESHOLD_CHECK_PASS')


class ProgressionDataTask(GeneratedFilesTask):
    name = 'progression_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/PLAYERS.TXT',)
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_progression_data.py --check',)
    scripts = ('tools/hsltools/data/progression.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): (json.dumps(build(), ensure_ascii=False, indent=2) + '\n').encode('utf-8')}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'PROGRESSION_DATA_CHECK_PASS'


def tasks() -> list[ProgressionDataTask]:
    return [ProgressionDataTask()]


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');p.add_argument('--check-exe',type=Path);a=p.parse_args()
    if a.check_exe:check_exe(a.check_exe)
    task = ProgressionDataTask()
    print(task.check(Context()) if a.check else task.generate(Context()))
