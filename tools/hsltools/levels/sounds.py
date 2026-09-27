"""Import the WAV resources that one level's story script plays (actPlaySound) from the
original PAK into a tracked, decoded manifest (level_sounds:N).

Registry task (tools/hsl.py check|generate level_sounds:N): check validates the tracked sounds/manifest.json
and its WAVs against the seed without the PAK; generate decodes them from hsl.pak.
"""
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from hsltools.levels import legacy_failures, original_pak, story_levels
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import Context, NotGeneratable, Task

DEFAULT_PAK = ORIGINAL_PAK
SCHEMA = 'hsl_level_script_sounds.v1'


def seed_path(level: int) -> Path:
    return (ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json')


def sound_dir(level: int) -> Path:
    return (ROOT / f'content/imported/hsl/chapter01/battle{level:03d}/sounds')


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def script_wav_refs(seed: dict) -> list[str]:
    """actPlaySound resources, then WAVs named by script-inserted objects' data fields
    (mapobjPlayBGSound objects such as level 10's 雨聲 carry WAV\\RAIN001.WAV in obj_Data2),
    then WAVs named by EVEF-placed stand objects (the camp levels 55/61/62/64 place 夜晚聲
    NIGHT001.WAV, level 56 places 鳥聲 YELL010.WAV as map objects)."""
    refs = []
    for script in seed.get('scripts', {}).values():
        if not isinstance(script, dict):
            continue
        for ref in script.get('resource_refs', []):
            if ref.upper().endswith('.WAV') and ref not in refs:
                refs.append(ref)
    rows = list(seed.get('script_objects', [])) + list(seed.get('placements', {}).get('records', []))
    for row in rows:
        if row.get('join_status') != 'joined':
            continue
        for value in row.get('object_data_fields', {}).values():
            ref = str(value)
            if ref.upper().endswith('.WAV') and ref not in refs:
                refs.append(ref)
    return refs


def decode_wav(packages, member: str) -> tuple[bytes, bytes]:
    from hsltools.sources.pak import (decoded_xor_a8_wave_bytes, find_paks_record_by_name,
                                      parse_xor_a8_wave_candidate, read_paks_record_bytes)
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous sound: ' + member)
    package, record = matches[0]
    raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / 'source.wav'
        source.write_bytes(raw)
        candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
        if candidate is None:
            raise ValueError('unsupported sound format: ' + member)
        return raw, decoded_xor_a8_wave_bytes(source, candidate)


def build(level: int, pak: Path) -> int:
    from hsltools.assets.actor_audio import profile
    from hsltools.sources.pak import find_decoded_paks_packages
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    refs = script_wav_refs(seed)
    packages = find_decoded_paks_packages(pak)
    out_dir = sound_dir(level)
    out_dir.mkdir(parents=True, exist_ok=True)
    sounds = {}
    for ref in refs:
        raw, audio = decode_wav(packages, '@:\\' + ref)
        target = out_dir / (ref.split('\\')[-1].split('.')[0] + '.wav')
        target.write_bytes(audio)
        sounds[ref] = {'source_member': '@:\\' + ref, 'source_sha256': _sha(raw), 'sha256': _sha(audio),
                       'profile': profile(audio), 'res_path': 'res://' + target.relative_to(ROOT).as_posix()}
    manifest = {
        'schema': SCHEMA,
        'level': level,
        'evidence_tier': 'resource-derived',
        'sources': {'battle_seed': seed_path(level).relative_to(ROOT).as_posix()},
        'sounds': sounds,
        'limits': ['Decoded resource audio only; original mix level, channel and trigger timing are not proven.'],
    }
    (out_dir / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return len(sounds)


def check(level: int) -> int:
    from hsltools.assets.actor_audio import profile
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    manifest = json.loads((sound_dir(level) / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('schema') != SCHEMA or set(manifest['sounds']) != set(script_wav_refs(seed)):
        raise SystemExit('script sound manifest does not match the tracked seed')
    for ref, row in manifest['sounds'].items():
        audio = (ROOT / row['res_path'].removeprefix('res://')).read_bytes()
        if _sha(audio) != row['sha256'] or profile(audio) != row['profile']:
            raise SystemExit('script sound differs from manifest: ' + ref)
    return len(manifest['sounds'])


class LevelSoundsTask(Task):
    family = 'level_sounds'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_sounds:{level}'
        self.outputs = ((sound_dir(level) / 'manifest.json').relative_to(ROOT).as_posix(),)
        self.inputs = (seed_path(level).relative_to(ROOT).as_posix(),)
        self.replaces = (f'tools/hsl_level_sounds.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/sounds.py', 'tools/hsltools/assets/actor_audio.py')

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            count = check(self.level)
        return f'LEVEL_SCRIPT_SOUNDS_CHECK_PASS level={self.level} sounds={count}'

    def generate(self, ctx: Context) -> str:
        pak = original_pak(ctx)
        if not pak.is_file():
            raise NotGeneratable(f'{self.name}: original PAK not found at {pak}')
        return f'LEVEL_SCRIPT_SOUNDS_BUILD_PASS level={self.level} sounds={build(self.level, pak)}'


def tasks() -> list[LevelSoundsTask]:
    return [LevelSoundsTask(level) for level in story_levels()]
