"""Extract Leonard's initial technique and its source-bound audiovisual assets.

Registry task first_skill (family skills, OriginalArchiveTask): tracked output
content/imported/hsl/shared/first_skill/ (manifest, source texts, PNG previews, audio);
generate re-imports from hsl.pak. Bodies moved verbatim from the former hsl_first_skill.py.
"""
import json
from pathlib import Path
import re
import struct
import tempfile
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.registry import Context
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, blocks, digest, parse_table

ROOT = Path('content/imported/hsl/shared/first_skill')


def definition():
    player = next(b for b in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character') if b['code'] == '1')
    skill = next(b for b in blocks((TABLES / 'SPECIAL.TXT').read_bytes(), 'special')
                 if b['type'] == 'magicOTHER' and b['code'] == 'magicCode01')
    names = parse_table(Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT').read_bytes())
    name = names[skill['name']]
    assert player['special_other'] == name == '氣刃斬'
    aliases = (TABLES / 'mag-spc.h').read_bytes().decode('cp950')
    assert re.search(r'#define\s+氣刃斬\s+0x00000001\b', aliases)
    ranges = (TABLES / 'RANGE.TXT').read_bytes().decode('cp950')
    patterns = {}
    for code in (skill['range'], skill['effect_range']):
        block = next(b for b in ranges.split('[range]') if re.search(r'^code\s*=\s*' + code + r'\s*$', b, re.M))
        size = int(re.search(r'^size\s*=\s*(\d+)', block, re.M)[1])
        rows = [[int(n) for n in row.split(',')] for row in re.findall(r'^data\s*=\s*([^\r\n;]+)', block, re.M)]
        assert len(rows) == size and all(len(row) == size for row in rows)
        patterns[code] = {'size': size, 'data': rows}
    return {'actor_id': '001', 'name': name, 'initial_stamina_raw': int(player['stamina']),
            'source_fields': skill, 'range_patterns': patterns}


def build(pak):
    packages = find_decoded_paks_packages(pak)
    def read(member):
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous member: ' + member)
        p, r = matches[0]
        return read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))
    ROOT.mkdir(parents=True, exist_ok=True)
    sources = {}
    # objcomd.txt／OBJCOMD.H: the defProcObjectMove command programs a special object's obj_Data7
    # selects (objmPlaySound／objmPlayHitSound among them) — the scope of special_effect_scripts.
    for name in ('effects.txt', 'global.obs', 'objcomd.txt', 'OBJCOMD.H'):
        raw = read('data\\' + name)
        (ROOT / name).write_bytes(raw)
        sources[name] = digest(raw)
    effects = (ROOT / 'effects.txt').read_bytes().decode('cp950')
    scripts = {}
    for code in ('specCode01', 'specCode02'):
        block = next(b for b in effects.split('[effect]') if re.search(r'^code\s*=\s*' + code + r'\s*$', b, re.M))
        scripts[code] = re.findall(r'^action\s*=\s*([^\r\n;]+)', block, re.M)
    objects = {}
    for b in blocks((ROOT / 'global.obs').read_bytes(), 'Object'):
        if b.get('obj_code') in ('410', '411', '412', '413'):
            objects[b['obj_code']] = b
    assert len(objects) == 4
    members = {'MAGIC\\SP00_001.SHP'}
    for obj in objects.values():
        member = obj['obj_Shape_Name']
        prefix, number = re.fullmatch(r'(.+_)(\d+)\.SHP', member).groups()
        for index in range(int(obj['obj_Shape_Number'])):
            members.add(prefix + str(int(number) + index).zfill(len(number)) + '.SHP')
    images = {}
    for member in sorted(members):
        raw = read(member)
        target = ROOT / (member.split('\\')[-1].lower() + '.png')
        write_shp_preview(raw, parse_shp(raw), target)
        images[member] = {'res_path': 'res://' + target.as_posix(), 'source_sha256': digest(raw),
                          'png_sha256': png_sha256(target), 'draw_origin': list(struct.unpack_from('<ii', raw, 0x1c))}
    member = re.search(r'aniPlaySound,([^,\s]+)', ','.join(scripts['specCode01']))[1]
    raw = read(member)
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / 'sound.wav'
        source.write_bytes(raw)
        candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
        if candidate is None:
            raise ValueError('unsupported skill audio')
        audio = decoded_xor_a8_wave_bytes(source, candidate)
    target = ROOT / 'attack.wav'
    target.write_bytes(audio)
    result = {'schema': 'hsl_first_skill.v1', 'evidence_tier': 'resource-derived', 'definition': definition(),
              'sources': sources, 'scripts': scripts, 'objects': objects, 'images': images,
              'sound': {'source_member': member, 'source_sha256': digest(raw), 'res_path': 'res://' + target.as_posix(), 'sha256': digest(audio)},
        'unresolved': ['full native actor initial stamina and innate effect initialization', 'native object movement handlers and delay clock', 'global RNG identity and complete skill callbacks; native channel1 Qi Blade magnitude and HP cap are separately verified'],
              'live': True}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['definition'] == definition()
    for name, sha in data['sources'].items():
        assert digest((ROOT / name).read_bytes()) == sha
    effects = (ROOT / 'effects.txt').read_bytes().decode('cp950')
    for code, actions in data['scripts'].items():
        block = next(b for b in effects.split('[effect]') if re.search(r'^code\s*=\s*' + code + r'\s*$', b, re.M))
        assert actions == re.findall(r'^action\s*=\s*([^\r\n;]+)', block, re.M)
    objects = {b['obj_code']: b for b in blocks((ROOT / 'global.obs').read_bytes(), 'Object')
               if b.get('obj_code') in ('410', '411', '412', '413')}
    assert data['objects'] == objects
    for item in data['images'].values():
        assert png_sha256(Path(item['res_path'].removeprefix('res://'))) == item['png_sha256']
    sound = data['sound']
    assert digest(Path(sound['res_path'].removeprefix('res://')).read_bytes()) == sound['sha256']
    print('FIRST_SKILL_CHECK_PASS')


class FirstSkillTask(OriginalArchiveTask):
    name = 'first_skill'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_first_skill.py --check',)
    scripts = ('tools/hsltools/data/first_skill.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check)

    def rebuild(self, ctx: Context) -> None:
        build(self.archive)


def tasks() -> list[FirstSkillTask]:
    return [FirstSkillTask()]
