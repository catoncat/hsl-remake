"""Reproducible Poison Arrow source effect assets; never substitute Qi Blade art.

Registry task poison_arrow_data (family skills, OriginalArchiveTask): tracked output
content/imported/hsl/shared/poison_arrow/; generate re-imports from hsl.pak. Bodies moved
verbatim from the former hsl_poison_arrow.py.
"""
from __future__ import annotations
import json
import re
import struct
import tempfile
from pathlib import Path
from hsltools.probes.poison_arrow import PACKET, fields, check as check_native
from hsltools.data import OriginalArchiveTask
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)
from hsltools.sources.shp import parse_shp, write_shp_preview
from hsltools.sources.tables import TABLES,blocks,digest

OUT=Path('content/imported/hsl/shared/poison_arrow')
EFFECTS=Path('content/imported/hsl/shared/first_skill/effects.txt')
OBJECTS=Path('content/imported/hsl/shared/first_skill/global.obs')

def definition():
    check_native(json.loads(PACKET.read_text()))
    program={}
    for code in ['specCode37','specCode38']:
        block=next(b for b in EFFECTS.read_bytes().decode('cp950').split('[effect]') if re.search(r'^code\s*=\s*'+code+r'\s*$',b,re.M))
        program[code]=re.findall(r'^action\s*=\s*([^\r\n;]+)',block,re.M)
    header=(TABLES/'OBJ-ALL.H').read_bytes().decode('cp950')
    names={name:code for name,code in re.findall(r'^\s*#define\s+(obj_Special19_\d+)\s+(\d+)',header,re.M)}
    records={r['obj_code']:r for r in blocks(OBJECTS.read_bytes(),'Object') if r.get('obj_code') in names.values()}
    if names!={'obj_Special19_01':'428','obj_Special19_02':'429','obj_Special19_03':'430'} or len(records)!=3:raise ValueError('Poison Arrow source object join differs')
    return dict(skill_id='special:magicMIND:magicCode03',source_fields=fields(),program=program,objects={key:records[code] for key,code in names.items()},
                sources={str(p.relative_to(ROOT) if p.is_absolute() else p):digest(p.read_bytes()) for p in [EFFECTS,OBJECTS,TABLES/'OBJ-ALL.H',TABLES/'SPECIAL.TXT',PACKET]},
                presentation_boundary='Source spec37/spec38 ordering and original SP19 images/audio; map-target composition, trajectories and wall clock are explicit remake values, not original dispatcher timing.')

def build(pak:Path,data):
    packages=find_decoded_paks_packages(pak)
    def read(member):
        matches=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],'@:\\'+member))]
        if len(matches)!=1:raise ValueError('Missing/ambiguous original Poison Arrow asset: '+member)
        p,r=matches[0];return read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
    for member,path in [('data\\effects.txt',EFFECTS),('data\\global.obs',OBJECTS)]:
        if read(member)!=path.read_bytes():raise ValueError('Poison Arrow PAK/text source differs')
    OUT.mkdir(parents=True,exist_ok=True);images={};groups={}
    members=['MAGIC\\SP00_003.SHP']
    for name,obj in data['objects'].items():
        prefix,digits=re.fullmatch(r'(.+_)(\d+)\.SHP',obj['obj_Shape_Name']).groups()
        groups[name]=[prefix+str(int(digits)+i).zfill(len(digits))+'.SHP' for i in range(int(obj['obj_Shape_Number']))]
        members.extend(groups[name])
    for member in members:
        raw=read(member);path=OUT/(member.split('\\')[-1].lower()+'.png');write_shp_preview(raw,parse_shp(raw),path)
        images[member]=dict(res_path='res://'+path.as_posix(),source_sha256=digest(raw),png_sha256=digest(path.read_bytes()),draw_origin=list(struct.unpack_from('<ii',raw,0x1c)))
    sounds={}
    for key,member in [('shoot','WAV\\SHOOT001.WAV'),('hit','WAV\\BOMB0024.WAV')]:
        raw=read(member)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'source.wav';path.write_bytes(raw)
            candidate=parse_xor_a8_wave_candidate(path,0,len(raw))
            if candidate is None:raise ValueError('Unsupported original Poison Arrow audio')
            audio=decoded_xor_a8_wave_bytes(path,candidate)
        path=OUT/(key+'.wav');path.write_bytes(audio)
        sounds[key]=dict(source_member=member,res_path='res://'+path.as_posix(),source_sha256=digest(raw),sha256=digest(audio))
    (OUT/'manifest.json').write_text(json.dumps(dict(schema='hsl_poison_arrow_assets.v1',definition=data,images=images,groups=groups,sounds=sounds),ensure_ascii=False,indent=2)+'\n')

def check(data):
    manifest=json.loads((OUT/'manifest.json').read_text())
    if manifest['definition']!=data or len(manifest['images'])!=11:raise ValueError('Poison Arrow asset identity differs')
    if [len(manifest['groups'][key]) for key in data['objects']]!=[1,4,5]:raise ValueError('Poison Arrow source frame count differs')
    for row in manifest['images'].values():
        if digest(Path(row['res_path'].removeprefix('res://')).read_bytes())!=row['png_sha256']:raise ValueError('Poison Arrow image changed')
    for row in manifest['sounds'].values():
        if digest(Path(row['res_path'].removeprefix('res://')).read_bytes())!=row['sha256']:raise ValueError('Poison Arrow audio changed')


class PoisonArrowTask(OriginalArchiveTask):
    name = 'poison_arrow_data'  # 'poison_arrow' is the native probe task (hsltools.probes.poison_arrow)
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', EFFECTS.as_posix(), OBJECTS.as_posix(),
              'docs/evidence_packets/static_reverse/original_poison_arrow.json')
    outputs = (OUT.as_posix() + '/',)
    replaces = ('tools/hsl_poison_arrow.py --check',)
    scripts = ('tools/hsltools/data/poison_arrow.py', 'tools/hsltools/probes/poison_arrow.py')

    def verify(self, ctx: Context) -> str:
        try:
            check(definition())
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return 'POISON_ARROW_ASSETS_PASS images=11 sounds=2 source=spec37_spec38'

    def rebuild(self, ctx: Context) -> None:
        build(self.archive, definition())


def tasks() -> list[PoisonArrowTask]:
    return [PoisonArrowTask()]
