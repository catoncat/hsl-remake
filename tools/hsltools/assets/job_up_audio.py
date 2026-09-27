"""Sound bindings of the job-up target rows (PLAYERS 010–020) and the level-37 guardian 052,
shared by every battle.

The job-up exchange 0x4348f0 copies the target row's four sound fields (+0x8 sound_walk,
+0xc/+0x10/+0x14 attack/miss/dead) into the member record when the target declares them
(static-derived, docs/evidence_packets/static_reverse/original_town_job_up.md), so a member
who has changed title walks, strikes and dies with the target row's sounds — 咕嚕 017
flies with FLY002 / ATTACK20 instead of 008's ANIMAL004 / SHOOT007. Level audio manifests
(hsltools.levels.actors) only carry the base rows a level casts; this shared manifest is
looked up after them through game/battle/runtime/ActorSpriteKey.audio_binding.
Row 052 (謎之生命體, WINFAIL037's script-inserted obj_Story_Level_Enemy52) is bound here beside
its walk frames in the shared up-title walk manifest: it is fielded only by the script insert,
not by the level-37 cast, so no level audio manifest carries it and it walked silently; PLAYERS
code 52 declares FLY002 / ATTACK20 / MISS0001 / DEAD0003 (resource-derived).

Registry task job_up_audio (family assets): output content/imported/hsl/shared/actor_audio.json
plus content/imported/hsl/shared/actor_audio/ for the members not already normalized by the
chapter-01 table import (hsltools.assets.actor_audio); those are referenced, not copied.
"""
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from hsltools.assets.actor_audio import OUTPUT as CHAPTER_AUDIO, SOURCE as PLAYERS, profile
from hsltools.levels.actors import AUDIO_EVENTS, _players, _read_member
from hsltools.paths import ROOT
from hsltools.registry import Context, ScriptCheckTask, original_archive

## OBJ-ALL.H obj_Player1Up1..9Up1 (809..817) / 1Up2, 2Up2 (818, 819) -> global.obs obj_Data7 rows
## 10..20 (resource-derived, JobUpRules.TOWN_TARGETS). 018 has no SHAPEDEF walk row but its
## PLAYERS sound fields are declared and copied like any other target.
ACTORS = ('010', '011', '012', '013', '014', '015', '016', '017', '018', '019', '020', '052')
OUTPUT = Path('content/imported/hsl/shared/actor_audio.json')
SOUND_ROOT = Path('content/imported/hsl/shared/actor_audio')
SCHEMA = 'hsl_actor_audio.v1'


def bindings() -> dict[str, dict[str, str]]:
    players = _players()
    return {str(int(code)): {event: players[int(code)]['sound_' + event].replace('\\', '/').lower()
                             for event in AUDIO_EVENTS if players[int(code)].get('sound_' + event)}
            for code in ACTORS}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check() -> None:
    characters = bindings()
    manifest = json.loads((ROOT / OUTPUT).read_text(encoding='utf-8'))
    assert manifest['schema'] == SCHEMA
    assert manifest['source_sha256'] == _sha((ROOT / PLAYERS).read_bytes())
    assert manifest['characters'] == characters, 'job-up row sound bindings drifted from PLAYERS.TXT'
    used = sorted({name for entry in characters.values() for name in entry.values()})
    assert sorted(manifest['sounds']) == used, 'manifest sounds differ from the rows\' declared members'
    shared = json.loads((ROOT / CHAPTER_AUDIO).read_text(encoding='utf-8'))['sounds']
    for name, item in manifest['sounds'].items():
        if name in shared:
            assert item == shared[name], f'{name} must reference the chapter-01 normalized sound'
        else:
            assert Path(item['path']).parent == SOUND_ROOT, f'{name} must live in {SOUND_ROOT}'
        data = (ROOT / item['path']).read_bytes()
        assert _sha(data) == item['sha256'] and profile(data) == item['profile'], f'{name} differs from manifest'
    print(f'JOB_UP_AUDIO_CHECK_PASS rows={len(characters)} sounds={len(manifest["sounds"])}')


def build(pak: Path) -> None:
    characters = bindings()
    shared = json.loads((ROOT / CHAPTER_AUDIO).read_text(encoding='utf-8'))
    sounds = dict(shared['sounds'])
    packages = None
    for name in sorted({name for entry in characters.values() for name in entry.values()}):
        if name in sounds:
            continue
        if packages is None:
            from hsltools.sources.pak import find_decoded_paks_packages
            packages = find_decoded_paks_packages(pak)
        raw = _read_member(packages, '@:\\' + name.replace('/', '\\'))
        from hsltools.sources.pak import decoded_xor_a8_wave_bytes, parse_xor_a8_wave_candidate
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source.wav'
            source.write_bytes(raw)
            candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
            if candidate is None:
                raise ValueError('unsupported sound format: ' + name)
            audio = decoded_xor_a8_wave_bytes(source, candidate)
        target = ROOT / SOUND_ROOT / (Path(name).stem + '.wav')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(audio)
        sounds[name] = {'source_member': '@:\\' + name.replace('/', '\\'), 'source_sha256': _sha(raw),
                        'path': target.relative_to(ROOT).as_posix(), 'res_path': 'res://' + target.relative_to(ROOT).as_posix(),
                        'sha256': _sha(audio), 'profile': profile(audio)}
    used = sorted({name for entry in characters.values() for name in entry.values()})
    manifest = {'schema': SCHEMA, 'evidence_tier': 'resource-derived', 'rows': 'job_up_targets_010_020_and_guardian_052',
                'source': PLAYERS.as_posix(), 'source_sha256': _sha((ROOT / PLAYERS).read_bytes()),
                'characters': characters, 'sounds': {name: sounds[name] for name in used},
                'shared_manifest': 'res://' + CHAPTER_AUDIO.as_posix(),
                'unresolved_semantics': ['0x4348f0 copies the four sound fields when the target declares them (static-derived); the consumer looks this manifest up after the level manifest by the job-up target row',
                                         'playback cadence, volume and mixing remain the remake\'s (see the chapter-01 actor_audio manifest)']}
    (ROOT / OUTPUT).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'JOB_UP_AUDIO_IMPORT_PASS rows={len(characters)} sounds={len(manifest["sounds"])}')


class JobUpAudioTask(ScriptCheckTask):
    name = 'job_up_audio'
    family = 'assets'
    inputs = (PLAYERS.as_posix(), CHAPTER_AUDIO.as_posix())
    outputs = (OUTPUT.as_posix(), SOUND_ROOT.as_posix() + '/')
    # No pre-registry script existed; the ledger entry is the task's own check command (tools/README.md 新增任务).
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/assets/job_up_audio.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[JobUpAudioTask]:
    return [JobUpAudioTask()]
