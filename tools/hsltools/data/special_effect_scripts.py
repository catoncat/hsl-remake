"""Inventory of every skill's source effect script — the SPECIAL rows' EFFECTS.TXT specCode
pairs (ANIMAL.H ``ani*`` verbs) and the MAGIC rows' effCode scripts (effects.h ``eff*``
verbs) — with the objects, SHP members and WAV members those scripts reference.

Registry task special_effect_scripts (family skills): output
content/generated/hsl/skills/special_effect_scripts.json, rendered only from tracked sources
(the first_skill copies of effects.txt / global.obs / objcomd.txt / OBJCOMD.H, OBJ-ALL.H,
effects.h and the initial skill book). A defProcObjectMove object (every obj_Special*) runs the
objcomd.txt command program its obj_Data7 selects; the objmPlaySound／objmPlayHitSound WAVs in
that program are the object's `command_sounds` (the 氣刃斬 impact burst obj_Special01_03,
command 2, plays WAV\BOMB0017.WAV) — its delay before each is the sum of the objmDelay counts
ahead of it; a motion wait ahead of it (objmWait*／objmLoop*／objmRandomDelay) is named, not
timed. It is the scope oracle for the skill_effects import (which SHP frames / WAVs
the cut-in needs) and the opcode census SkillEffectScriptPlayer.gd must cover. No art, audio
or timing semantics are claimed here; the PAK import and the opcode player are separate
slices.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import TABLES, blocks

FIRST_SKILL = Path('content/imported/hsl/shared/first_skill')
EFFECTS = FIRST_SKILL / 'effects.txt'
OBJECTS = FIRST_SKILL / 'global.obs'
OBJECT_CODES = TABLES / 'OBJ-ALL.H'
EFFECT_VERBS = TABLES / 'effects.h'
COMMANDS = FIRST_SKILL / 'objcomd.txt'
COMMAND_VERBS = FIRST_SKILL / 'OBJCOMD.H'
BOOK = Path('content/generated/hsl/skills/initial_book.json')
OUTPUT = Path('content/generated/hsl/skills/special_effect_scripts.json')
SCHEMA = 'hsl_special_effect_scripts.v3'
# The one row family whose art is imported (content/imported/hsl/shared/first_skill/).
IMPORTED_CODES = {'specCode01', 'specCode02'}
# Script verbs: ANIMAL.H ani* (specCode) and effects.h eff* (effCode).
VERB_PREFIXES = ('ani', 'eff')


def effect_scripts(text: str) -> dict[str, list[str]]:
    """code -> action lines, exactly as the [effect] blocks list them (comments stripped)."""
    scripts: dict[str, list[str]] = {}
    for block in text.split('[effect]')[1:]:
        code = re.search(r'^code\s*=\s*(\w+)\s*$', block, re.M)
        if code is None:
            continue
        if code[1] in scripts:
            raise ValueError(f'duplicate effect code {code[1]}')
        scripts[code[1]] = re.findall(r'^action\s*=\s*([^\r\n;]+)', block, re.M)
    return scripts


def command_programs(text: str) -> dict[str, list[str]]:
    """objcomd.txt code -> its command tokens in order, as the [command] blocks list them."""
    programs: dict[str, list[str]] = {}
    for block in text.split('[command]')[1:]:
        code = re.search(r'^\s*code\s*=\s*(\d+)', block, re.M)
        if code is None:
            continue
        if code[1] in programs:
            raise ValueError(f'duplicate command code {code[1]}')
        actions = re.findall(r'^\s*action\s*=\s*([^\r\n;]+)', block, re.M)
        programs[code[1]] = [token.strip() for action in actions for token in action.split(',') if token.strip()]
    return programs


def command_verbs() -> set[str]:
    """The objm* verbs OBJCOMD.H defines (a commented-out define is not a verb)."""
    header = COMMAND_VERBS.read_bytes().decode('cp950')
    return set(re.findall(r'^\s*#define\s+(objm\w+)\s+\d+', header, re.M))


def command_sounds(tokens: list[str], verbs: set[str]) -> list[dict]:
    """The objmPlaySound／objmPlayHitSound cues of one command program, in order: the WAV,
    whether it needs a hit (objmPlayHitSound plays only while the hit roll is under the hit
    rate, 0x4059cf), the objmDelay ticks ahead of it and the motion waits ahead of it that
    the delay cannot count (then `timing` is provisional)."""
    sounds: list[dict] = []
    delay = 0
    waits: list[str] = []
    for index, token in enumerate(tokens):
        if token not in verbs:
            continue
        if token == 'objmDelay':
            delay += int(tokens[index + 1], 0)
        elif token == 'objmRandomDelay':
            delay += int(tokens[index + 1], 0)
            waits.append(token)
        elif token.startswith(('objmWait', 'objmLoop')):
            waits.append(token)
        elif token in ('objmPlaySound', 'objmPlayHitSound'):
            sounds.append({'member': tokens[index + 1], 'hit_only': token == 'objmPlayHitSound', 'delay_ticks': delay,
                           'timing': 'provisional' if waits else 'delays', 'unresolved_waits': list(waits)})
    return sounds


# defProcEffectProcess1 (0x415dc0) copies an effect object's obj_Y1／obj_X2 WAVs to +0x44／+0x46 as
# it starts; its effProc* program plays them at its own events (0x415d40 plays +0x44 once, 0x415d70
# every time, 0x415d90 plays +0x46 once). Ticks after the object starts, counted from each program's
# state counters in hsl01.exe (static-derived; docs/evidence_packets/static_reverse/
# original_effect_object_sounds.md §6). `counts`: every state ahead of the cue is a fixed countdown
# (±1 tick); `provisional`: a state ahead of it waits on motion or animation the remake does not run,
# counted as the named estimate. `data` is the object's own obj_Data4／obj_Data6 (template +0x98／
# +0xa0) where the program reads it.
EFFECT_PROGRAM_SOUNDS = {
    # states 1／200／120／60, then three flame rings 48 apart, each with 0x415d70 (+0x44 kept)
    'effProcFireArray': lambda data: [('obj_Y1', 430, 'counts'), ('obj_Y1', 478, 'counts'), ('obj_Y1', 526, 'counts')],
    # state 1 counts obj_Data4 (+0x98) down, then plays +0x44 as the head rises
    'effProcFireHead': lambda data: [('obj_Y1', 1 + int(data.get('obj_Data4', '0'), 0), 'counts')],
    # 40-tick zoom-in, then the orbit radius shrinks 48 → 2 px by 2 px a tick (22), then the burst
    'effProcMindBall': lambda data: [('obj_Y1', 63, 'counts')],
    # countdowns 66／40／100, then the beast's roar
    'effProcMindBeast': lambda data: [('obj_Y1', 207, 'counts')],
    # countdowns 42／60
    'effProcWaterBeast': lambda data: [('obj_Y1', 103, 'counts')],
    # piece d = obj_Data6 waits 8·d ticks (+0x34), plays +0x46 when that wait reaches exactly 0
    # (piece 0 never does), then counts 48 and plays +0x44 as it breaks
    'effProcUpBreakShape': lambda data: ([('obj_X2', 1 + 8 * int(data.get('obj_Data6', '0'), 0), 'counts')]
                                         if int(data.get('obj_Data6', '0'), 0) > 0 else [])
                                        + [('obj_Y1', 8 * int(data.get('obj_Data6', '0'), 0) + 48, 'counts')],
    # +0x46 in state 0; then a 16.0 → 8.0 → 1.0 zoom (16 + 30 ticks), an animation wait (unread,
    # counted 0) and a 40-tick countdown before +0x44
    'effProcOtherWord3': lambda data: [('obj_X2', 0, 'counts'), ('obj_Y1', 87, 'provisional')],
    # a 0x43bf30 wait (unread, counted 0), then a 120-tick countdown before +0x44
    'effProcOtherBig': lambda data: [('obj_Y1', 121, 'provisional')],
    # +0x46 when the first countdown (its start value unread, counted 1) ends; one shape-delay
    # wait (24) and an 80-tick countdown before +0x44
    'effProcOtherGlass': lambda data: [('obj_X2', 2, 'provisional'), ('obj_Y1', 106, 'provisional')],
    # countdown 80, six children 16 apart (96), countdown 40 → +0x46; then a flight of ~200 px at
    # 8 px a tick (25, motion not run) → +0x44
    'effProcWaterBig': lambda data: [('obj_X2', 217, 'provisional'), ('obj_Y1', 242, 'provisional')],
}


def program_sounds(block: dict) -> list[dict]:
    """An effect object's obj_Y1／obj_X2 cues: WAV, source field, ticks after it starts, timing."""
    wavs = {field: block.get(field, '') for field in ('obj_Y1', 'obj_X2')}
    wavs = {field: value for field, value in wavs.items() if value.upper().endswith('.WAV')}
    if not wavs:
        return []
    program = block.get('obj_Data9', '')
    if program not in EFFECT_PROGRAM_SOUNDS:
        raise ValueError(f'obj_code {block["obj_code"]}: {program} carries {sorted(wavs)} but its cue ticks are unread')
    return [{'member': wavs[field], 'field': field, 'delay_ticks': ticks, 'timing': timing}
            for field, ticks, timing in EFFECT_PROGRAM_SOUNDS[program](block) if field in wavs]


def shape_members(shape_name: str, count: int) -> list[str]:
    match = re.fullmatch(r'(.+_)(\d+)\.SHP', shape_name)
    if match is None:
        return [shape_name]
    prefix, number = match.groups()
    return [prefix + str(int(number) + index).zfill(len(number)) + '.SHP' for index in range(count)]


def is_verb(token: str) -> bool:
    return token.startswith(VERB_PREFIXES)


def effect_verbs() -> list[str]:
    """The eff* opcodes effects.h defines (effCodeNN are [effect] block ids, not verbs)."""
    header = EFFECT_VERBS.read_bytes().decode('cp950')
    return [name for name in re.findall(r'^\s*#define\s+(eff[A-Z]\w+)\s+\d+', header, re.M) if not name.startswith('effCode')]


def render_inventory() -> dict:
    effects = effect_scripts(EFFECTS.read_bytes().decode('cp950'))
    object_codes = dict(re.findall(r'#define\s+(obj_\w+)\s+(\d+)', OBJECT_CODES.read_bytes().decode('cp950')))
    objects_by_code = {b['obj_code']: b for b in blocks(OBJECTS.read_bytes(), 'Object') if 'obj_code' in b}
    programs = command_programs(COMMANDS.read_bytes().decode('cp950'))
    verbs = command_verbs()
    book = json.loads(BOOK.read_text(encoding='utf-8'))
    rows = {}
    all_objects: dict[str, dict] = {}
    opcode_counts: dict[str, int] = {}
    magic_opcode_counts: dict[str, int] = {}
    unresolved: list[str] = []
    shp_members: set[str] = set()
    wav_members: set[str] = set()
    for skill_id, entry in sorted(book['skills'].items()):
        # Authored skills are presented from authored_effect_scripts.json (hsltools.data.authored_skills):
        # this file stays the inventory of the original rows the skill_effects import is scoped by.
        if entry.get('evidence_tier') == 'authored':
            continue
        fields = entry['fields']
        channel = entry['channel']
        if channel == 'special':
            codes = [fields['attack_code'], fields['defense_code']]
        elif channel == 'magic':
            codes = [fields['effect_code']]
        else:
            continue
        actions = {code: effects.get(code, []) for code in codes}
        tokens = [token.strip() for code in codes for action in actions[code] for token in action.split(',')]
        opcodes = sorted({token for token in tokens if is_verb(token)})
        for opcode in (token for token in tokens if is_verb(token)):
            opcode_counts[opcode] = opcode_counts.get(opcode, 0) + 1
            if channel == 'magic':
                magic_opcode_counts[opcode] = magic_opcode_counts.get(opcode, 0) + 1
        row_objects = []
        for token in tokens:
            if not token.startswith('obj_') or token in row_objects:
                continue
            row_objects.append(token)
            if token in all_objects or token in unresolved:
                continue
            block = objects_by_code.get(object_codes.get(token, ''))
            if block is None:
                unresolved.append(token)
                continue
            count = int(block.get('obj_Shape_Number', '1') or '1')
            members = shape_members(block['obj_Shape_Name'], count)
            shp_members.update(members)
            # obj_X1 on an effect object is the WAV it plays when inserted (the AirBlade objects
            # carry WIND0001, the earth shapes UPGROUND／EARTH cues); obj_Data9 names its
            # effProc* motion program, which the player does not restore (listed as the gap).
            insert_sound = block.get('obj_X1', '')
            if not insert_sound.upper().endswith('.WAV'):
                insert_sound = ''
            elif insert_sound:
                wav_members.add(insert_sound)
            # A defProcObjectMove object runs the objcomd.txt command its obj_Data7 selects.
            command_code = ''
            sounds: list[dict] = []
            if block.get('obj_Process_Code') == 'defProcObjectMove':
                command_code = block['obj_Data7']
                if command_code not in programs:
                    raise ValueError(f'{token}: obj_Data7 {command_code} names no objcomd.txt command')
                sounds = command_sounds(programs[command_code], verbs)
                wav_members.update(sound['member'] for sound in sounds)
            secondary = program_sounds(block) if block.get('obj_Process_Code') == 'defProcEffectProcess1' else []
            wav_members.update(sound['member'] for sound in secondary)
            all_objects[token] = {'obj_code': block['obj_code'], 'obj_name': block.get('obj_name', ''),
                                  'plane': block.get('obj_Plane', ''), 'process': block.get('obj_Process_Code', ''),
                                  'effect_process': block.get('obj_Data9', ''), 'insert_sound': insert_sound,
                                  'command_code': command_code, 'command_sounds': sounds, 'program_sounds': secondary,
                                  'shape_name': block['obj_Shape_Name'], 'shape_number': count,
                                  'shape_delay': int(block.get('obj_Shape_Delay', '0') or '0'), 'shape_members': members}
        row_wavs = sorted({token for token in tokens if token.upper().endswith('.WAV')})
        # The WAVs the row's objects sound by themselves (special command／effect program cues).
        row_object_wavs = sorted({sound['member'] for name in row_objects if name in all_objects
                                  for sound in all_objects[name]['command_sounds'] + all_objects[name]['program_sounds']})
        wav_members.update(row_wavs)
        row_shp = sorted({token for action in actions.values() for line in action for token in line.split(',')
                          if token.strip().upper().endswith('.SHP')})
        shp_members.update(row_shp)
        row = {'name': entry['name'], 'channel': channel, 'damage_policy': entry['damage_policy']}
        if channel == 'special':
            row.update({'attack_code': codes[0], 'defense_code': codes[1]})
        else:
            row.update({'effect_code': codes[0], 'effect_proc': fields['effect_proc'], 'effect_caster': fields.get('effect_caster', '')})
        row.update({'actions': actions, 'opcodes': opcodes, 'objects': row_objects, 'sounds': row_wavs,
                    'object_sounds': row_object_wavs, 'script_shapes': row_shp,
                    'art_imported': set(codes) <= IMPORTED_CODES})
        rows[skill_id] = row
    verbs = effect_verbs()
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived; static-derived (objects.program_sounds ticks)',
        'sources': {'effects': EFFECTS.as_posix(), 'objects': OBJECTS.as_posix(), 'object_codes': OBJECT_CODES.as_posix(),
                    'effect_verbs': EFFECT_VERBS.as_posix(), 'commands': COMMANDS.as_posix(),
                    'command_verbs': COMMAND_VERBS.as_posix(), 'book': BOOK.as_posix()},
        'policy': ('Scope inventory for the skill_effects import and the script player. SPECIAL rows list their '
                   'attack／defense specCode scripts (ANIMAL.H ani* verbs), MAGIC rows their effCode script (effects.h '
                   'eff* verbs: effWait／effInsertObject／effInsertRandomObject／effPlaySound, positions are displacements '
                   'from the effect origin) with effect_proc (eff_proc_Local／Global) and the unread effect_caster field. '
                   'Objects carry their obj_X1 insertion WAV and obj_Data9 effProc* program name; a defProcObjectMove '
                   'object carries its obj_Data7 objcomd.txt command code and that program\'s objmPlaySound／objmPlayHitSound '
                   'cues (command_sounds: WAV, hit_only, the objmDelay ticks ahead of it, and the motion waits ahead of it '
                   'that make its timing provisional); an effect object carries its obj_Y1／obj_X2 cues '
                   '(program_sounds: WAV, field, ticks after it starts from the static EFFECT_PROGRAM_SOUNDS reading, '
                   'timing counts／provisional). No art or playback semantics are claimed here.'),
        'rows': rows,
        'objects': dict(sorted(all_objects.items())),
        'unresolved_objects': sorted(unresolved),
        'opcode_counts': dict(sorted(opcode_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        'magic_opcode_counts': dict(sorted(magic_opcode_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        'effect_verbs': verbs,
        'totals': {'rows': len(rows),
                   'rows_special': sum(1 for row in rows.values() if row['channel'] == 'special'),
                   'rows_magic': sum(1 for row in rows.values() if row['channel'] == 'magic'),
                   'effect_blocks': len(effects),
                   'rows_with_imported_art': sum(1 for row in rows.values() if row['art_imported']),
                   'objects': len(all_objects), 'shape_members': len(shp_members), 'sound_members': len(wav_members),
                   'objects_with_command_sounds': sum(1 for o in all_objects.values() if o['command_sounds']),
                   'rows_with_command_sounds': sum(1 for row in rows.values()
                                                   if any(all_objects[n]['command_sounds'] for n in row['objects'] if n in all_objects)),
                   'rows_with_program_sounds': sum(1 for row in rows.values()
                                                   if any(all_objects[n]['program_sounds'] for n in row['objects'] if n in all_objects)),
                   'objects_with_program_sounds': sum(1 for o in all_objects.values() if o['program_sounds']),
                   'opcodes': len(opcode_counts), 'magic_opcodes': len(magic_opcode_counts),
                   'frames': sum(o['shape_number'] for o in all_objects.values())},
    }


class SpecialEffectScriptsTask(GeneratedFilesTask):
    name = 'special_effect_scripts'
    family = 'skills'
    inputs = (EFFECTS.as_posix(), OBJECTS.as_posix(), COMMANDS.as_posix(), COMMAND_VERBS.as_posix(), OBJECT_CODES.as_posix(),
              EFFECT_VERBS.as_posix(), BOOK.as_posix())
    outputs = (OUTPUT.as_posix(),)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/data/special_effect_scripts.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(render_inventory())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        totals = json.loads(rendered[OUTPUT.as_posix()])['totals']
        return (f'SPECIAL_EFFECT_SCRIPTS_{"CHECK_" if mode == "check" else ""}PASS rows={totals["rows"]} '
                f'special={totals["rows_special"]} magic={totals["rows_magic"]} effect_blocks={totals["effect_blocks"]} '
                f'objects={totals["objects"]} frames={totals["frames"]} sounds={totals["sound_members"]} '
                f'command_sound_objects={totals["objects_with_command_sounds"]} command_sound_rows={totals["rows_with_command_sounds"]} '
                f'program_sound_objects={totals["objects_with_program_sounds"]} program_sound_rows={totals["rows_with_program_sounds"]} '
                f'opcodes={totals["opcodes"]} magic_opcodes={totals["magic_opcodes"]}')


def tasks() -> list[SpecialEffectScriptsTask]:
    return [SpecialEffectScriptsTask()]
