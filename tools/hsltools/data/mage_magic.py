"""Import the first-battle mage's source-bound spells and effect assets.

Registry task mage_magic (family skills, OriginalArchiveTask): tracked output
content/imported/hsl/shared/mage_magic/; generate re-imports from hsl.pak. Bodies moved
verbatim from the former hsl_mage_magic.py.
"""
import json
import re
import struct
import tempfile
from pathlib import Path
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.registry import Context
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, blocks, digest, parse_table, table_rows
ROOT = Path('content/imported/hsl/shared/mage_magic')
SOURCE = Path('content/imported/hsl/shared/first_skill')


def definitions():
    mage = next(b for b in table_rows('PLAYERS.TXT') if b['code']=='26')
    names = parse_table(Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT').read_bytes())
    result = {}
    for key, element in [('wind','AIR'),('fire','FIRE')]:
        row = next(b for b in blocks((TABLES/'MAGIC.TXT').read_bytes(),'magic') if b['type']=='magic'+element and b['code']=='magicCode01')
        assert names[row['name']] == mage['magic_'+key]
        assert row['range']=='range3CellCircle' and row['effect_range']=='range0Cell'
        result[key] = {'name':names[row['name']], 'fields':row}
    return {'actor_id':'026','magic_point_raw':int(mage['magic_point']), 'mind_raw':int(mage['mind']), 'ai_att_magic':int(mage['ai_att_magic']), 'spells':result}


def source_bindings(spells=None):
    effects = (SOURCE/'effects.txt').read_bytes().decode('cp950')
    header = (TABLES/'OBJ-ALL.H').read_bytes().decode('cp950')
    objects = {b['obj_code']:b for b in blocks((SOURCE/'global.obs').read_bytes(),'Object')}
    result = {}
    for key, spell in (definitions()['spells'] if spells is None else spells).items():
        block = next(b for b in effects.split('[effect]') if re.search(r'^code\s*=\s*'+spell['fields']['effect_code']+r'\s*$',b,re.M))
        actions = re.findall(r'^action\s*=\s*([^\r\n;]+)',block,re.M)
        names = list(dict.fromkeys(re.findall(r'obj_Effect_\w+',','.join(actions))))
        result[key] = {'actions':actions,'objects':{name:objects[re.search(r'#define\s+'+name+r'\s+(\d+)',header)[1]] for name in names}}
    return result


def build(pak):
    packages = find_decoded_paks_packages(pak)
    def read(member):
        matches=[(p,r) for p in packages if (r:=find_paks_record_by_name(p['records'],'@:\\'+member))]
        if len(matches)!=1:raise ValueError('missing or ambiguous '+member)
        p,r=matches[0]
        return read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
    ROOT.mkdir(parents=True,exist_ok=True)
    result={'schema':'hsl_mage_magic.v1','evidence_tier':'resource-derived','definition':definitions(),'bindings':source_bindings(),'images':{},'sounds':{}}
    cast_source = read('DATA\\OBJ-051.OBS')
    caster = next(row for row in blocks(cast_source, 'Object') if row.get('obj_code') == '399')
    result['casting'] = {'source_member': 'DATA\\OBJ-051.OBS', 'source_sha256': digest(cast_source),
                         'object': caster, 'frames': [],
                         'limits': 'Source Cast_Star object and six frames; exact trajectory/timing requires runtime comparison.'}
    for index in range(int(caster['obj_Shape_Number'])):
        member = 'MAGIC\\CAST_STAR%02d.SHP' % (index + 1)
        raw = read(member)
        target = ROOT / ('cast_star%02d.png' % index)
        write_shp_preview(raw, parse_shp(raw), target)
        result['casting']['frames'].append({'res_path': 'res://' + target.as_posix(), 'source_member': member,
            'source_sha256': digest(raw), 'png_sha256': png_sha256(target), 'draw_origin': list(struct.unpack_from('<ii',raw,0x1c))})
    for binding in result['bindings'].values():
        for obj in binding['objects'].values():
            prefix,number=re.fullmatch(r'(.+_)(\d+)\.SHP',obj['obj_Shape_Name']).groups()
            for i in range(int(obj['obj_Shape_Number'])):
                member=prefix+str(int(number)+i).zfill(len(number))+'.SHP'
                if member in result['images']:continue
                raw=read(member);target=ROOT/(member.split('\\')[-1].lower()+'.png')
                write_shp_preview(raw,parse_shp(raw),target)
                result['images'][member]={'res_path':'res://'+target.as_posix(),'source_sha256':digest(raw),'png_sha256':png_sha256(target),'draw_origin':list(struct.unpack_from('<ii',raw,0x1c))}
            member=obj.get('obj_X1','')
            if not member.startswith('WAV\\') or member in result['sounds']:continue
            raw=read(member)
            with tempfile.TemporaryDirectory() as tmp:
                p=Path(tmp)/'sound.wav';p.write_bytes(raw)
                candidate=parse_xor_a8_wave_candidate(p,0,len(raw))
                if candidate is None:raise ValueError('unsupported '+member)
                audio=decoded_xor_a8_wave_bytes(p,candidate)
            target=ROOT/member.split('\\')[-1].lower();target.write_bytes(audio)
            result['sounds'][member]={'res_path':'res://'+target.as_posix(),'source_sha256':digest(raw),'sha256':digest(audio)}
    (ROOT/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')


def check():
    data=json.loads((ROOT/'manifest.json').read_text())
    assert data['definition']==definitions() and data['bindings']==source_bindings()
    assert data['casting']['object']['obj_code'] == '399'
    assert len(data['casting']['frames']) == int(data['casting']['object']['obj_Shape_Number'])
    for item in data['casting']['frames']: assert png_sha256(Path(item['res_path'].removeprefix('res://'))) == item['png_sha256']
    for item in data['images'].values():assert png_sha256(Path(item['res_path'].removeprefix('res://')))==item['png_sha256']
    for item in data['sounds'].values():assert digest(Path(item['res_path'].removeprefix('res://')).read_bytes())==item['sha256']
    print('MAGE_MAGIC_CHECK_PASS')


class MageMagicTask(OriginalArchiveTask):
    name = 'mage_magic'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT', SOURCE.as_posix() + '/')
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_mage_magic.py --check',)
    scripts = ('tools/hsltools/data/mage_magic.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check)

    def rebuild(self, ctx: Context) -> None:
        build(self.archive)


def tasks() -> list[MageMagicTask]:
    return [MageMagicTask()]
