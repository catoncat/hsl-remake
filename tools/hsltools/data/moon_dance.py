"""Source Moon Dance effect program, native pulse contract and independent assets.

Registry task moon_dance_data (family skills): tracked outputs the generated contract
content/generated/hsl/skills/moon_dance.json and the authored trial
content/battles/moon_dance_trial.json (rendered byte for byte), plus the imported asset folder
content/imported/hsl/shared/moon_dance/ which check validates and only the legacy --pak
entry re-imports. Bodies moved verbatim from the former hsl_moon_dance_data.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
import re
import struct
import tempfile
from hsltools.probes.moon_dance import PACKET, EFFECTS, source_fields, check as native_check
from hsltools.data import json_bytes
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask, original_archive
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, blocks, digest

OUT=Path('content/imported/hsl/shared/moon_dance')
CONTRACT=Path('content/generated/hsl/skills/moon_dance.json')
OBJECTS=Path('content/imported/hsl/shared/first_skill/global.obs')
PROGRAMS=Path('content/generated/hsl/animation/animal_programs.json')
ID='special:magicOTHER:magicCode06'
TRIAL=Path('content/battles/moon_dance_trial.json')
COUNTS={'aniDelay':1,'aniInsertRandomObject':7,'aniPlaySound':1,'aniProcessHitMiss':0,
        'aniInsertHitRandomObjectDisp':7,'aniPlayHitSound':1,'aniShowHitResultNoWait':0}


def definition() -> dict:
    packet=json.loads(PACKET.read_text());native_check(packet)
    raw=EFFECTS.read_bytes().decode('cp950')
    block=next(b for b in raw.split('[effect]') if re.search(r'^code\s*=\s*specCode20\s*$',b,re.M))
    actions=re.findall(r'^action\s*=\s*([^\r\n;]+)',block,re.M)
    tokens=[part.strip() for part in ','.join(actions).split(',')]
    program=[];cursor=0;clock=0;hits=[]
    while cursor<len(tokens):
        op=tokens[cursor];cursor+=1
        if op not in COUNTS:raise ValueError('Unreviewed Moon opcode '+op)
        count=COUNTS[op];args=tokens[cursor:cursor+count];cursor+=count
        if len(args)!=count or any(a.startswith('ani') for a in args):raise ValueError('Moon opcode arity differs')
        program.append(dict(op=op,args=[int(v) if re.fullmatch(r'-?\d+',v) else v for v in args]))
        if op=='aniDelay':clock+=int(args[0])
        elif op=='aniProcessHitMiss':hits.append(clock)
    if hits!=[80,90,100,110,120] or clock!=180:raise ValueError('Moon source pulse schedule changed')
    caster=next(r for r in json.loads(PROGRAMS.read_text())['records'] if r['code']=='SID_PLAYER1')
    objects={r['obj_code']:r for r in blocks(OBJECTS.read_bytes(),'Object') if r.get('obj_code') in ['421','422']}
    if len(objects)!=2:raise ValueError('Moon source objects missing')
    return dict(schema='hsl_moon_dance.v1',skill_id=ID,evidence_tier='static-derived',source_fields=source_fields(),
                pulses=5,target_order='coverage_row_major_unique',kill_accounting='after_all_targets',
                after_zero_hp='continue_original_rolls_zero_contribution',source_hit_delays=hits,source_duration=clock,
                actions=actions,program=program,objects=objects,caster_fields={k:caster['fields'][k] for k in ['s_shape','s_number']},
                caster_program=caster['programs']['s_action'],
                sources={'special':digest((TABLES/'SPECIAL.TXT').read_bytes()),'effect':digest(EFFECTS.read_bytes()),
                         'objects':digest(OBJECTS.read_bytes()),'animal':digest(PROGRAMS.read_bytes()),'native':digest(PACKET.read_bytes())},
                limits=['Original numeric/receiver phases are separately bounded; source delay totals do not prove global real-time clock.',
                        'Map burst layout and particle trajectories are remake presentation of these source assets; no native object scheduler claim.'])


def build_assets(pak: Path, data: dict) -> None:
    packages=find_decoded_paks_packages(pak)
    def read(member):
        found=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],'@:\\'+member))]
        if len(found)!=1:raise ValueError('Missing/ambiguous Moon asset '+member)
        p,r=found[0];return read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
    for member,path in [('data\\effects.txt',EFFECTS),('data\\global.obs',OBJECTS)]:
        if read(member)!=path.read_bytes():raise ValueError('Original Moon source differs: '+member)
    OUT.mkdir(parents=True,exist_ok=True);groups={};images={}
    shapes=[('caster',data['caster_fields']['s_shape']['token'],data['caster_fields']['s_number']['value'])]
    shapes += [(key,obj['obj_Shape_Name'],int(obj['obj_Shape_Number'])) for key,obj in data['objects'].items()]
    for group,start,count in shapes:
        prefix,digits=re.fullmatch(r'(.+_)(\d+)\.SHP',start).groups();groups[group]=[]
        for i in range(count):
            member=prefix+str(int(digits)+i).zfill(len(digits))+'.SHP';raw=read(member)
            target=OUT/(group+'-'+str(i)+'.png');write_shp_preview(raw,parse_shp(raw),target)
            images[member]=dict(res_path='res://'+target.as_posix(),source_sha256=digest(raw),png_sha256=png_sha256(target),
                                draw_origin=list(struct.unpack_from('<ii',raw,0x1c)))
            groups[group].append(member)
    sounds={}
    for op,key in [('aniPlaySound','wind'),('aniPlayHitSound','hit')]:
        names={row['args'][0] for row in data['program'] if row['op']==op}
        if len(names)!=1:raise ValueError('Moon audio ambiguity')
        member=names.pop();raw=read(member)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'audio.wav';path.write_bytes(raw)
            candidate=parse_xor_a8_wave_candidate(path,0,len(raw))
            if candidate is None:raise ValueError('Unsupported Moon audio')
            audio=decoded_xor_a8_wave_bytes(path,candidate)
        target=OUT/(key+'.wav');target.write_bytes(audio)
        sounds[key]=dict(member=member,res_path='res://'+target.as_posix(),source_sha256=digest(raw),sha256=digest(audio))
    (OUT/'manifest.json').write_text(json.dumps(dict(schema='hsl_moon_dance_assets.v1',sources=data['sources'],images=images,groups=groups,sounds=sounds),indent=2)+'\n')


def check_assets(data: dict) -> None:
    manifest=json.loads((OUT/'manifest.json').read_text())
    if manifest['sources']!=data['sources'] or len(manifest['images'])!=11:raise ValueError('Moon asset source mismatch')
    for key,count in [('caster',3),('421',4),('422',4)]:
        if len(manifest['groups'][key])!=count:raise ValueError('Moon frame coverage differs')
    for row in manifest['images'].values():
        if png_sha256(Path(row['res_path'].removeprefix('res://')))!=row['png_sha256']:raise ValueError('Moon image mismatch')
    for row in manifest['sounds'].values():
        if digest(Path(row['res_path'].removeprefix('res://')).read_bytes())!=row['sha256']:raise ValueError('Moon audio mismatch')


def trial() -> dict:
    value=json.loads(Path('content/battles/priest_trial.json').read_text())
    value['id']='moon_dance_training';value['title']='月花圓舞 · 演練'
    value['skill_rules']['initial_stamina']=40
    actors={r['id']:r for r in value['playable_units']}
    actors['tina']['coord']=[14,16];actors['companion']['coord']=[14,15]
    # This explicit training encounter starts surrounded. Give its protagonist
    # time to demonstrate the move before the three source soldiers act.
    actors['tina']['growth_profile']['source']['hit_point']+=120
    actors['tina']['growth_profile']['source']['speed']+=20
    actors['tina']['hp']+=120;actors['tina']['max_hp']+=120;actors['tina']['live_speed']+=20
    foes=[]
    for index,coord in enumerate([[15,16],[13,15],[13,17]],1):
        actor=copy.deepcopy(actors['enemy021_1']);actor['id']='enemy021_'+str(index);actor['coord']=coord
        foes.append(actor)
    value['playable_units']=[actors['tina'],actors['companion'],*foes]
    value['development_note']='Authored Moon Dance practice on source051 terrain: source002 skills/equipment/job, three ordinary enemy021 templates, the explicit supplied PriestTrial inventory,40 starting stamina and training source additions120HP/20speed so the surrounded protagonist acts first. This is not a formal original encounter or a default campaign grant.'
    return value


class MoonDanceDataTask(GeneratedFilesTask):
    name = 'moon_dance_data'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/shared/first_skill/effects.txt', OBJECTS.as_posix(),
              'content/battles/priest_trial.json', 'docs/evidence_packets/static_reverse/original_moon_dance.json')
    outputs = (CONTRACT.as_posix(), TRIAL.as_posix(), OUT.as_posix() + '/')
    replaces = ('tools/hsl_moon_dance_data.py --check',)
    scripts = ('tools/hsltools/data/moon_dance.py', 'tools/hsltools/probes/moon_dance.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {CONTRACT.as_posix(): json_bytes(definition()), TRIAL.as_posix(): json_bytes(trial())}

    def check(self, ctx: Context) -> str:
        line = super().check(ctx)
        try:
            check_assets(json.loads((ctx.root / CONTRACT).read_bytes()))
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return line

    def generate(self, ctx: Context) -> str:
        line = super().generate(ctx)
        # The asset folder (frames, sounds, manifest.json) re-imports from the PAK too.
        data = json.loads((ctx.root / CONTRACT).read_bytes())
        build_assets(original_archive(ctx), data)
        check_assets(data)
        return line

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'MOON_DANCE_DATA_PASS pulses=5 source_images=11'


def tasks() -> list[MoonDanceDataTask]:
    return [MoonDanceDataTask()]
