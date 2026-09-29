"""Import the per-skill effect art and audio named by the EFFECTS.TXT scripts — the SPECIAL
rows' specCode pairs and the MAGIC rows' effCode scripts.

Registry task skill_effects (family assets): output content/imported/hsl/shared/skill_effects/
(manifest.json, frames/*.png, sounds/*.wav). The scope is the tracked inventory
content/generated/hsl/skills/special_effect_scripts.json (every SHP member of every obj_Special*
／obj_Effect_* object plus the aniInsertSpecialBG panels, every aniPlaySound / aniPlayHitSound /
effPlaySound WAV, every object's obj_X1 insertion WAV and every objmPlaySound／objmPlayHitSound WAV
of a special object's objcomd.txt command program) plus every SHP member the native effect-object
tracks content/generated/hsl/skills/effect_motion.json draw (the sparks, bullets and afterimages
the effProc* programs spawn) and every SHP member a special object's native objcomd.txt run draws
(content/generated/hsl/skills/objcomd_motion.json: the children it throws); generate re-imports them from hsl.pak
with the first_skill decoders (parse_shp / write_shp_preview, XOR-A8 WAVE). The manifest also
declares, per row, which presentation the cut-in uses (the script player, a dedicated module,
or the borrowed 氣刃斬 staging when an opcode is not implemented) so the fallback is data, not a
silent code branch: BattleCombatCutin builds its presenter list from these rows.
"""
from __future__ import annotations

import json
import struct
import tempfile
from pathlib import Path

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import (decoded_xor_a8_wave_bytes, find_decoded_paks_packages, find_paks_record_by_name,
                                  parse_xor_a8_wave_candidate, read_paks_record_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import blocks, digest

SCOPE = Path('content/generated/hsl/skills/special_effect_scripts.json')
# The native effect-object tracks (hsltools.probes.effect_motion): their spawned objects draw
# SHP members no script names.
MOTION = Path('content/generated/hsl/skills/effect_motion.json')
# The native objcomd.txt runs (hsltools.probes.objcomd_motion): their recorded sounds and every shape
# their trees draw (miss-run children and hit-only throws) are imported too.
OBJCOMD_MOTION = Path('content/generated/hsl/skills/objcomd_motion.json')
OBJECTS = Path('content/imported/hsl/shared/first_skill/global.obs')
ROOT = Path('content/imported/hsl/shared/skill_effects')
# Story-object shapes no effect script reaches: global.obs 706 obj_Fire_Smoke, whose defProcFireSmoke
# (0x43c260) draws its own +0x32 every tick (噴人沼氣 smoke, docs/evidence_packets/static_reverse/original_poison_gas.md).
STORY_SHAPES = ('MAGIC\\SMOKE001.SHP',)
MANIFEST = ROOT / 'manifest.json'
SCHEMA = 'hsl_skill_effects.v1'
# EFFECTS.TXT ani* verbs SkillEffectScriptPlayer.gd interprets (ANIMAL.H names its parameters);
# a row whose scripts use any other verb keeps the borrowed 氣刃斬 staging and says so in `rows`.
IMPLEMENTED_OPCODES = (
    'aniDelay', 'aniPlaySound', 'aniInsertObject', 'aniInsertRandomObject', 'aniInsertRandomObjectFixDelay',
    'aniProcessHitMiss', 'aniShowHitResult', 'aniInsertRandomObjectDelay', 'aniPlayHitSound',
    'aniInsertHitRandomObject', 'aniInsertSpecialBG', 'aniDoublePageMode', 'aniInsertHitRandomObjectFixDelay',
    'aniProcessHitMissMulti', 'aniInsertAngleObject', 'aniInsertDistanceObjectFixDelay',
    'aniInsertHitRandomObjectDisp', 'aniShowHitResultNoWait', 'aniNoSpecialDarkBG', 'aniInsertRoundRandomObject',
    'aniInsertTornadoObject', 'aniShowAttacker', 'aniInsertAngleObjectMakeShape', 'aniSetXYDisp',
    'effWait', 'effInsertObject', 'effInsertRandomObject', 'effPlaySound')
# Rows whose original program is already restored by its own presentation module.
DEDICATED_MODULES = {
    'special:magicMIND:magicCode03': 'PoisonArrowPresentation.gd',
    'special:magicOTHER:magicCode06': 'MoonDancePresentation.gd',
}
POLICY = ('Art and audio are byte-for-byte imports of the PAK members the specCode／effCode scripts and their '
          'global.obs objects name (resource-derived). Playback semantics are not claimed here: SkillEffectScriptPlayer.gd '
          'runs the scripts at a provisional 60 ticks/s, plays an effCode object that has a native track in '
          'effect_motion.json (its effProc* program and every object it spawns, executed per tick) along that '
          'track, keeps the other objects at their insertion point for '
          'shape_number x (shape_delay + 1) ticks (the SHP helper D+1 convention; untracked effCode objects at least '
          'EFFECT_MIN_LIFETIME_TICKS, then an EFFECT_FADE_TICKS alpha tail), flies specCode objects inserted '
          'outside the 640x320 stage to the target centre, places the ANIMAL random / distance / round inserts as '
          'the interpreter 0x4038a0 does and draws angle / tornado placements from ANIMAL.H parameter names, '
          'random draws from a presentation-only RNG; a special object '
          'plays its objcomd.txt command sounds (objects.command_sounds: objmPlaySound always, objmPlayHitSound '
          'only on a hit) at its insertion tick plus the objmDelay ticks ahead of each, a motion wait ahead of one '
          'counted as zero (timing provisional); an effect object plays its obj_Y1／obj_X2 cues '
          '(objects.program_sounds) at its instruction tick plus the statically read effProc* delay; the rest of '
          'the defProcObjectMove motion (obj_Data7 programs), the effProc* programs effect_motion.json lists as '
          'unrestored, '
          'and the angle / tornado insertion geometry (ANIMAL op 20-22) remain '
          'static-derived work. A magic script fires impact at its last insertion or sound cue and plays once '
          'per affected position (eff_proc_Local) or once at the screen centre (eff_proc_Global). Every row '
          'declares its presentation: script (the player), dedicated_module (an existing restored module) or '
          'borrowed_qi_blade (an opcode outside implemented_opcodes; none today).')


def frame_path(member: str) -> Path:
    return ROOT / 'frames' / (member.split('\\')[-1].lower() + '.png')


def sound_path(member: str) -> Path:
    return ROOT / 'sounds' / member.split('\\')[-1].lower()


def load_scope() -> dict:
    return json.loads(SCOPE.read_text(encoding='utf-8'))


def row_presentation(row: dict) -> dict:
    """The cut-in path one SPECIAL row takes, from its opcodes alone."""
    unimplemented = sorted(set(row['opcodes']) - set(IMPLEMENTED_OPCODES))
    if unimplemented:
        return {'presentation': 'borrowed_qi_blade', 'unimplemented_opcodes': unimplemented}
    return {'presentation': 'script'}


def render_rows(scope: dict) -> dict:
    rows = {}
    for skill_id, row in scope['rows'].items():
        entry = {'name': row['name'], 'channel': row['channel']}
        if row['channel'] == 'special':
            entry.update({'attack_code': row['attack_code'], 'defense_code': row['defense_code']})
        else:
            entry.update({'effect_code': row['effect_code'], 'effect_proc': row['effect_proc']})
        if skill_id in DEDICATED_MODULES:
            entry.update({'presentation': 'dedicated_module', 'module': DEDICATED_MODULES[skill_id]})
        else:
            entry.update(row_presentation(row))
        rows[skill_id] = entry
    return rows


def scope_members(scope: dict) -> tuple[list[str], list[str], list[str]]:
    """(SHP members, aniInsertSpecialBG panels, WAV members) the scope names, sorted."""
    shp: set[str] = set()
    panels: set[str] = set()
    wav: set[str] = set()
    for obj in scope['objects'].values():
        shp.update(obj['shape_members'])
        if obj['insert_sound']:
            wav.add(obj['insert_sound'])
        wav.update(sound['member'] for sound in obj['command_sounds'] + obj['program_sounds'])
    for row in scope['rows'].values():
        panels.update(row['script_shapes'])
        wav.update(row['sounds'])
    shp.update(panels)
    shp.update(STORY_SHAPES)
    motion = json.loads(MOTION.read_text(encoding='utf-8'))
    shp.update(motion['members'])
    # Every sound the native runs recorded (children's obj_X1, per-variant timings, hit-run cues).
    for row in motion['objects'].values():
        wav.update(sound[1] for tree in [row] + row.get('variants', []) for sound in tree.get('sounds', []))
    objcomd = json.loads(OBJCOMD_MOTION.read_text(encoding='utf-8'))
    for name, row in objcomd['objects'].items():
        if name in scope['objects']:
            wav.update(sound[1] for runs in [row['sounds']] + row.get('variant_sounds', []) for sound in runs)
            # Every shape the native runs drew: the children the program throws on every run (variants)
            # and the hit-only throws (hit_variants: 0x405434／0x405495 fire only on a hit).
            shp.update(objcomd['members'][index] for instances in row.get('variants', []) + row.get('hit_variants', [])
                       for instance in instances for index, _ in instance.get('member', []) if index >= 0)
    return sorted(shp), sorted(panels), sorted(wav)


def object_modes() -> dict[str, str]:
    """obj_code -> obj_Mode (blend hint) from the tracked global.obs; '' when the block has none."""
    return {b['obj_code']: b.get('obj_Mode', '') for b in blocks(OBJECTS.read_bytes(), 'Object') if 'obj_code' in b}


def fixed16(token: str) -> float:
    """A 16.16 fixed-point OBS field ('0x00014000' → 1.25, '-0x00010000' → -1.0)."""
    text = token.strip()
    sign = -1.0 if text.startswith('-') else 1.0
    return sign * int(text.lstrip('-'), 16) / 65536.0


def object_zooms() -> dict[str, list[float]]:
    """obj_code -> [zoom x, zoom y] from obj_ZoomX／obj_ZoomY (1.0 when absent)."""
    zooms = {}
    for b in blocks(OBJECTS.read_bytes(), 'Object'):
        if 'obj_code' in b:
            zooms[b['obj_code']] = [fixed16(b.get('obj_ZoomX', '0x00010000')), fixed16(b.get('obj_ZoomY', '0x00010000'))]
    return zooms


def build(pak: Path) -> None:
    packages = find_decoded_paks_packages(pak)

    def read(member: str) -> bytes | None:
        """The member's bytes, or None when hsl.pak has no record of that name."""
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
        if len(matches) > 1:
            raise ValueError('ambiguous member: ' + member)
        if not matches:
            return None
        p, r = matches[0]
        return read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))

    scope = load_scope()
    shp_members, panels, wav_members = scope_members(scope)
    (ROOT / 'frames').mkdir(parents=True, exist_ok=True)
    (ROOT / 'sounds').mkdir(parents=True, exist_ok=True)
    frames = {}
    missing = []
    for member in shp_members:
        raw = read(member)
        if raw is None:
            # global.obs declares more shapes than hsl.pak holds (the 闇瑩蝶舞 SP08 objects: 9 per
            # object, 3 present per decade); listed rather than skipped silently.
            missing.append(member)
            continue
        target = frame_path(member)
        write_shp_preview(raw, parse_shp(raw), target)
        frames[member] = {'res_path': 'res://' + target.as_posix(), 'source_sha256': digest(raw),
                          'png_sha256': png_sha256(target), 'draw_origin': list(struct.unpack_from('<ii', raw, 0x1c))}
    sounds = {}
    for member in wav_members:
        raw = read(member)
        if raw is None:
            raise ValueError('missing sound member: ' + member)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'sound.wav'
            source.write_bytes(raw)
            candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
            if candidate is None:
                raise ValueError('unsupported skill audio: ' + member)
            audio = decoded_xor_a8_wave_bytes(source, candidate)
        target = sound_path(member)
        target.write_bytes(audio)
        sounds[member] = {'res_path': 'res://' + target.as_posix(), 'source_sha256': digest(raw), 'sha256': digest(audio)}
    modes = object_modes()
    zooms = object_zooms()
    rows = render_rows(scope)
    objects = {}
    for name, obj in scope['objects'].items():
        objects[name] = {'obj_code': obj['obj_code'], 'plane': obj['plane'], 'process': obj['process'],
                         'effect_process': obj['effect_process'], 'insert_sound': obj['insert_sound'],
                         'command_code': obj['command_code'], 'command_sounds': obj['command_sounds'],
                         'program_sounds': obj['program_sounds'],
                         'shape_delay': obj['shape_delay'], 'frame_ticks': obj['shape_delay'] + 1,
                         'mode': modes.get(obj['obj_code'], ''), 'zoom': zooms[obj['obj_code']],
                         'shape_members': list(obj['shape_members'])}
    manifest = {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'scope': {'path': SCOPE.as_posix(), 'sha256': digest(SCOPE.read_bytes())},
        'policy': POLICY,
        'tick_hz': 62.5,
        'tick_evidence': 'docs/evidence_packets/runtime_observations/original_tick_rate/README.md',
        'timing_evidence_tier': 'provisional',
        'replacement_evidence': ['static read of the 0x4037b0 opcode handlers 15..35 (insertion geometry, delay semantics)',
                                 'defProcObjectMove / obj_Data7 motion programs',
                                 'original cut-in frame timing (runtime-measured)'],
        'implemented_opcodes': list(IMPLEMENTED_OPCODES),
        'rows': rows,
        'objects': objects,
        'special_backgrounds': panels,
        'frames': frames,
        'missing_members': missing,
        'missing_members_evidence': 'negative-evidence: these SHP names follow from obj_Shape_Name + obj_Shape_Number but hsl.pak has no such record; the player cycles the frames that exist',
        'sounds': sounds,
        'unresolved_objects': list(scope['unresolved_objects']),
        'totals': {'objects': len(objects), 'frames': len(frames), 'missing_members': len(missing), 'sounds': len(sounds),
                   'unresolved': len(scope['unresolved_objects']),
                   'rows_special': sum(1 for r in rows.values() if r['channel'] == 'special'),
                   'rows_magic': sum(1 for r in rows.values() if r['channel'] == 'magic'),
                   'rows_script': sum(1 for r in rows.values() if r['presentation'] == 'script'),
                   'rows_dedicated_module': sum(1 for r in rows.values() if r['presentation'] == 'dedicated_module'),
                   'rows_borrowed_qi_blade': sum(1 for r in rows.values() if r['presentation'] == 'borrowed_qi_blade')},
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def check() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    scope = load_scope()
    assert manifest['schema'] == SCHEMA
    assert manifest['scope'] == {'path': SCOPE.as_posix(), 'sha256': digest(SCOPE.read_bytes())}, 'scope inventory changed: regenerate skill_effects'
    assert manifest['policy'] == POLICY
    assert manifest['implemented_opcodes'] == list(IMPLEMENTED_OPCODES)
    assert manifest['rows'] == render_rows(scope)
    shp_members, panels, wav_members = scope_members(scope)
    assert sorted(list(manifest['frames']) + manifest['missing_members']) == shp_members, 'frame set differs from the scope inventory'
    assert not set(manifest['missing_members']) & set(panels) and not set(manifest['missing_members']) & set(manifest['frames'])
    assert manifest['special_backgrounds'] == panels
    assert sorted(manifest['sounds']) == wav_members, 'sound set differs from the scope inventory'
    assert manifest['unresolved_objects'] == scope['unresolved_objects']
    modes = object_modes()
    zooms = object_zooms()
    assert sorted(manifest['objects']) == sorted(scope['objects'])
    for name, obj in scope['objects'].items():
        entry = manifest['objects'][name]
        assert entry['shape_members'] == obj['shape_members'] and entry['shape_delay'] == obj['shape_delay'], name
        assert entry['frame_ticks'] == obj['shape_delay'] + 1 and entry['mode'] == modes.get(obj['obj_code'], ''), name
        assert entry['plane'] == obj['plane'] and entry['process'] == obj['process'], name
        assert entry['effect_process'] == obj['effect_process'] and entry['insert_sound'] == obj['insert_sound'], name
        assert entry['zoom'] == zooms[obj['obj_code']] and (entry['insert_sound'] == '' or entry['insert_sound'] in manifest['sounds']), name
        assert entry['command_code'] == obj['command_code'] and entry['command_sounds'] == obj['command_sounds'], name
        assert entry['program_sounds'] == obj['program_sounds'], name
        assert all(sound['member'] in manifest['sounds'] for sound in entry['command_sounds'] + entry['program_sounds']), name
        present = [member for member in obj['shape_members'] if member in manifest['frames']]
        assert present, f'{name}: no shape member imported'
        for member in obj['shape_members']:
            assert member in manifest['frames'] or member in manifest['missing_members'], f'{name}: {member} not imported'
    for member, item in manifest['frames'].items():
        path = Path(item['res_path'].removeprefix('res://'))
        assert path == frame_path(member) and png_sha256(path) == item['png_sha256'], member
        assert len(item['draw_origin']) == 2
    for member, item in manifest['sounds'].items():
        path = Path(item['res_path'].removeprefix('res://'))
        assert path == sound_path(member) and digest(path.read_bytes()) == item['sha256'], member
    # Godot's ignored *.import sidecars sit next to the tracked PNG／WAV files.
    tracked = {p.as_posix() for p in (ROOT / 'frames').glob('*.png')} | {p.as_posix() for p in (ROOT / 'sounds').glob('*.wav')}
    declared = {Path(i['res_path'].removeprefix('res://')).as_posix() for i in manifest['frames'].values()}
    declared |= {Path(i['res_path'].removeprefix('res://')).as_posix() for i in manifest['sounds'].values()}
    assert tracked == declared, f'orphan or missing files: {sorted(tracked ^ declared)[:5]}'
    totals = manifest['totals']
    assert totals == {'objects': len(manifest['objects']), 'frames': len(manifest['frames']), 'missing_members': len(manifest['missing_members']),
                      'sounds': len(manifest['sounds']), 'unresolved': len(manifest['unresolved_objects']),
                      'rows_special': sum(1 for r in manifest['rows'].values() if r['channel'] == 'special'),
                      'rows_magic': sum(1 for r in manifest['rows'].values() if r['channel'] == 'magic'),
                      'rows_script': sum(1 for r in manifest['rows'].values() if r['presentation'] == 'script'),
                      'rows_dedicated_module': sum(1 for r in manifest['rows'].values() if r['presentation'] == 'dedicated_module'),
                      'rows_borrowed_qi_blade': sum(1 for r in manifest['rows'].values() if r['presentation'] == 'borrowed_qi_blade')}
    print(f'SKILL_EFFECTS_CHECK_PASS objects={totals["objects"]} frames={totals["frames"]} missing={totals["missing_members"]} '
          f'sounds={totals["sounds"]} unresolved={totals["unresolved"]} rows_special={totals["rows_special"]} '
          f'rows_magic={totals["rows_magic"]} rows_script={totals["rows_script"]} '
          f'rows_dedicated={totals["rows_dedicated_module"]} rows_borrowed={totals["rows_borrowed_qi_blade"]}')


class SkillEffectsTask(ScriptCheckTask):
    name = 'skill_effects'
    family = 'assets'
    inputs = (SCOPE.as_posix(), OBJECTS.as_posix(), MOTION.as_posix(), OBJCOMD_MOTION.as_posix())
    outputs = (ROOT.as_posix() + '/',)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/assets/skill_effects.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[SkillEffectsTask]:
    return [SkillEffectsTask()]
