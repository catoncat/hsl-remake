"""Import source WATER 05..08 effects and audio, with checked resource identities.

Registry task support_magic (family skills, OriginalArchiveTask): tracked output
content/imported/hsl/chapter01/support_magic/; generate re-imports from hsl.pak. build/check
also serve water_strike and stat_magic with their own spell sets. Bodies moved verbatim from the former hsl_support_magic.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import struct
import tempfile
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.data.mage_magic import source_bindings, SOURCE
from hsltools.data.skill_book import build as skill_book
from hsltools.registry import Context
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, digest
OUT = Path('content/imported/hsl/chapter01/support_magic')
SOURCES = [TABLES/'MAGIC.TXT', TABLES/'OBJ-ALL.H', SOURCE/'effects.txt', SOURCE/'global.obs']


def definitions():
    return {entry['magic_key']:{'skill_id':identifier,'name':entry['name'],'fields':entry['fields']}
            for identifier,entry in skill_book()['skills'].items()
            if entry['damage_policy']=='native_magic_support' and entry['type']=='magicWATER'}


def build(pak, spells=None, out=OUT, schema='hsl_support_magic_resources.v1', frame_members=None):
    packages=find_decoded_paks_packages(pak)
    def read(member):
        found=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],'@:\\'+member))]
        if len(found)!=1: raise ValueError('Missing or ambiguous support resource: '+member)
        package,record=found[0]
        return read_paks_record_bytes(package['path'],record,data_end_offset=int(package['paks']['candidate_index_offset']))
    spells=definitions() if spells is None else spells; bindings=source_bindings(spells)
    result=dict(schema=schema,evidence_tier='resource-derived',spells=spells,bindings=bindings,
                source_hashes={p.as_posix():digest(p.read_bytes()) for p in SOURCES},images={},sounds={},
                limits=['Original local-effect sprites, frame origins, object delays and script sounds.',
                        'Remake particle positions and presentation clock are provisional; this is not an original effect-opcode interpreter.'])
    out.mkdir(parents=True,exist_ok=True)
    sounds=set()
    for binding in bindings.values():
        sounds.update(re.findall(r'WAV\\[\w]+\.WAV',','.join(binding['actions'])))
        for obj in binding['objects'].values():
            first=obj['obj_Shape_Name']; match=re.fullmatch(r'(.+_)(\d+)\.SHP',first)
            if match is None: raise ValueError('Unsupported support shape sequence: '+first)
            prefix,number=match.groups(); frames=[]
            members=(frame_members or {}).get(first, [prefix+str(int(number)+index).zfill(len(number))+'.SHP' for index in range(int(obj['obj_Shape_Number']))])
            if len(members)!=int(obj['obj_Shape_Number']): raise ValueError('Explicit frame member count differs: '+first)
            for member in members:
                frames.append(member)
                if member in result['images']: continue
                raw=read(member); path=out/(member.split('\\')[-1].lower()+'.png')
                write_shp_preview(raw,parse_shp(raw),path)
                result['images'][member]=dict(res_path='res://'+path.as_posix(),source_sha256=digest(raw),png_sha256=png_sha256(path),draw_origin=list(struct.unpack_from('<ii',raw,0x1c)))
            obj['source_frames']=frames
            for value in obj.values():
                if isinstance(value,str) and value.startswith('WAV\\'): sounds.add(value)
    for member in sorted(sounds):
        raw=read(member)
        with tempfile.TemporaryDirectory() as temporary:
            encoded=Path(temporary)/'source.wav'; encoded.write_bytes(raw)
            candidate=parse_xor_a8_wave_candidate(encoded,0,len(raw))
            if candidate is None: raise ValueError('Unsupported encoded WAV: '+member)
            audio=decoded_xor_a8_wave_bytes(encoded,candidate)
        path=out/member.split('\\')[-1].lower(); path.write_bytes(audio)
        result['sounds'][member]=dict(res_path='res://'+path.as_posix(),source_sha256=digest(raw),sha256=digest(audio))
    (out/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')


def check(spells=None, out=OUT, frame_members=None):
    spells=definitions() if spells is None else spells
    data=json.loads((out/'manifest.json').read_text()); bindings=source_bindings(spells)
    assert data['spells']==spells and data['source_hashes']=={p.as_posix():digest(p.read_bytes()) for p in SOURCES}
    for key,binding in bindings.items():
        actual=data['bindings'][key]
        assert actual['actions']==binding['actions'] and set(actual['objects'])==set(binding['objects'])
        for name,obj in binding['objects'].items():
            derived=actual['objects'][name]
            assert {k:v for k,v in derived.items() if k!='source_frames'}==obj
            prefix,number=re.fullmatch(r'(.+_)(\d+)\.SHP',obj['obj_Shape_Name']).groups()
            expected=(frame_members or {}).get(obj['obj_Shape_Name'], [prefix+str(int(number)+i).zfill(len(number))+'.SHP' for i in range(int(obj['obj_Shape_Number']))])
            assert len(expected)==int(obj['obj_Shape_Number']) and derived['source_frames']==expected
            assert all(member in data['images'] for member in derived['source_frames'])
        assert all(member in data['sounds'] for member in re.findall(r'WAV\\[\w]+\.WAV',','.join(binding['actions'])))
    for item in data['images'].values(): assert png_sha256(Path(item['res_path'].removeprefix('res://')))==item['png_sha256']
    for item in data['sounds'].values(): assert digest(Path(item['res_path'].removeprefix('res://')).read_bytes())==item['sha256']
    print(f'SUPPORT_ASSETS_PASS spells={len(data["spells"])} images={len(data["images"])} sounds={len(data["sounds"])}')


class SupportMagicTask(OriginalArchiveTask):
    name = 'support_magic'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', SOURCE.as_posix() + '/', 'content/generated/hsl/skills/initial_book.json')
    outputs = (OUT.as_posix() + '/',)
    replaces = ('tools/hsl_support_magic.py --check',)
    scripts = ('tools/hsltools/data/support_magic.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check)

    def rebuild(self, ctx: Context) -> None:
        build(self.archive)


def tasks() -> list[SupportMagicTask]:
    return [SupportMagicTask()]
