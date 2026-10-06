"""The authored skill table: sequel skills that have no SPECIAL.TXT／MAGIC.TXT row.

content/authored/roles/skills.json lists one row per skill in the original tables' own field
vocabulary (SPECIAL.TXT for channel `special` — a 絕技 paid in ST —, MAGIC.TXT for channel
`magic` — paid in MP) plus `channel` and `name_text` (the display name; the original rows name a
RESOURCE.TXT id). Nothing here invents an effect: a row's `function` must map onto an effect
policy the runtime already resolves from the row's numbers and function bits (EFFECT_POLICIES: the
native 0x40a7b0 special or magic damage roll, and on the special channel the two turn-queue
utilities of SpecialUtilityRules — magicFun_CancelActive takes the target's pending action of
this round away, magicFun_ActiveAgain lets a target that has acted act again), its ranges are
RANGE.TXT shapes and its presentation is an EFFECTS.TXT script — an existing specCode／effCode
block, or a new block in the table's `scripts` written with the ani*／eff* verbs
SkillEffectScriptPlayer.gd already implements and the objects／sounds the skill_effects import
already carries. A row outside that vocabulary fails generation with the reason (a new effect
family or opcode is a runtime decision, not data).

Consumers: hsltools.data.skill_book appends book_rows() to content/generated/hsl/skills/
initial_book.json (so skill_target_data grows the RANGE rows they name and characters grant
them by name in the declaration field of their element); hsltools.data.growth_lifecycle
resolves learning-table ids through names(); registry task authored_effect_scripts (family
skills) renders the presentation rows to content/generated/hsl/skills/authored_effect_scripts.json,
which SkillEffectScriptPlayer.gd reads beside special_effect_scripts.json. The chapter-1
inventories (special_effect_scripts.json, the skill_effects manifest, coverage.json) keep only
original rows.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.assets.skill_effects import IMPLEMENTED_OPCODES, MANIFEST
from hsltools.data import json_bytes
from hsltools.data.special_effect_scripts import EFFECTS, effect_scripts
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask

AUTHORED_SKILLS = 'content/authored/roles/skills.json'
SCHEMA = 'hsl_authored_skills.v1'
OUTPUT = Path('content/generated/hsl/skills/authored_effect_scripts.json')
OUTPUT_SCHEMA = 'hsl_authored_effect_scripts.v1'
# Field order of the SPECIAL.TXT／MAGIC.TXT row each channel copies (the book's `fields`).
CHANNEL_FIELDS = {
    'special': ('code', 'name', 'type', 'range', 'effect_range', 'expend', 'damage', 'hit_ratio', 'use_ratio',
                'function', 'attackpow_ratio', 'attack_code', 'defense_code'),
    'magic': ('code', 'name', 'type', 'range', 'effect_range', 'expend', 'damage', 'hit_ratio', 'function',
              'use_ratio', 'effect_proc', 'effect_code'),
}
PRESENTATION_FIELDS = {'special': ('attack_code', 'defense_code'), 'magic': ('effect_code',)}
VERB_PREFIX = {'special': 'ani', 'magic': 'eff'}
# element type -> (PLAYERS declaration suffix, magic_key of a damage spell); the book's element
# index is the TYPE.H value except channel1 magicOTHER (no resist slot, as skill_book.REGISTRY).
ELEMENTS = {'magicEARTH': ('earth', 'earth'), 'magicWATER': ('water', 'water'), 'magicAIR': ('wind', 'wind'),
            'magicFIRE': ('fire', 'fire'), 'magicMIND': ('mind', 'mind'), 'magicOTHER': ('other', 'other')}
# (channel, function mask) -> policy: the effect families a row may use without new code. The runtime
# picks the family from the policy and the function bits (SpecialUtilityRules.ACCEPTED), never from the
# skill id, so an authored ActiveAgain／CancelActive row resolves exactly as 天鳴覺醒／獅子吼.
EFFECT_POLICIES = {('special', 1): 'native_special_damage', ('magic', 1): 'native_magic_damage',
                   ('special', 0x10000): 'native_special_utility', ('special', 0x80000): 'native_special_utility'}
EFFECT_PROCS = ('eff_proc_Local', 'eff_proc_Global')


def _integer(value: str, low: int, high: int, what: str) -> int:
    if not re.fullmatch(r'\d+', value) or not low <= int(value) <= high:
        raise ValueError(f'{AUTHORED_SKILLS}: {what} {value!r} must be an integer in {low}..{high}')
    return int(value)


def table() -> dict:
    """The authored table, validated for shape: {'scripts': {code: [lines]}, 'skills': [row]}.
    Values are the table strings (JSON numbers are accepted and written as strings)."""
    path = ROOT / AUTHORED_SKILLS
    if not path.is_file():
        return {'scripts': {}, 'skills': []}
    raw = json.loads(path.read_text(encoding='utf-8'))
    if raw.get('schema') != SCHEMA:
        raise ValueError(f'{AUTHORED_SKILLS}: schema {raw.get("schema")!r} is not {SCHEMA}')
    scripts = raw.get('scripts', {})
    for code, lines in scripts.items():
        if not re.fullmatch(r'authored[A-Z]\w*', code) or not isinstance(lines, list) or not lines or not all(isinstance(line, str) for line in lines):
            raise ValueError(f'{AUTHORED_SKILLS}: script {code!r} needs an authored… code and a non-empty list of action lines')
    rows, seen_codes, seen_names = [], set(), set()
    for index, source in enumerate(raw.get('skills', [])):
        channel = source.get('channel')
        if channel not in CHANNEL_FIELDS:
            raise ValueError(f'{AUTHORED_SKILLS}: skills[{index}] channel {channel!r} is not special or magic')
        expected = {'channel', 'name_text'} | set(CHANNEL_FIELDS[channel]) - {'name'}
        if set(source) != expected:
            raise ValueError(f'{AUTHORED_SKILLS}: skills[{index}] fields differ from the {channel} row: missing {sorted(expected - set(source))}, unknown {sorted(set(source) - expected)}')
        row = {key: str(value) for key, value in source.items()}
        if not re.fullmatch(r'authored[A-Z]\w*', row['code']) or row['code'] in seen_codes:
            raise ValueError(f'{AUTHORED_SKILLS}: skills[{index}] code {row["code"]!r} must be a distinct authored… identifier')
        if not row['name_text'] or row['name_text'] in seen_names:
            raise ValueError(f'{AUTHORED_SKILLS}: skills[{index}] name_text {row["name_text"]!r} must be a distinct non-empty name')
        seen_codes.add(row['code'])
        seen_names.add(row['name_text'])
        rows.append(row)
    return {'scripts': scripts, 'skills': rows}


def skill_id(row: dict) -> str:
    return f'{row["channel"]}:{row["type"]}:{row["code"]}'


def names() -> dict[str, str]:
    """{skill id: display name} of every authored row."""
    return {skill_id(row): row['name_text'] for row in table()['skills']}


def declaration_field(row: dict) -> str:
    return f'{row["channel"]}_{ELEMENTS[row["type"]][0]}'


def effect_policy(row: dict, bits: dict[str, int]) -> str:
    """The EFFECT_POLICIES policy of the row's function on its channel; `bits` are the TYPE.H magicFun_* bits."""
    from hsltools.data.skill_targeting import function_mask
    policy = EFFECT_POLICIES.get((row['channel'], function_mask(row['function'], bits)))
    if policy is None:
        supported = ', '.join(name for name, bit in bits.items() if (row['channel'], bit) in EFFECT_POLICIES)
        raise ValueError(f'{AUTHORED_SKILLS}: {skill_id(row)}: function {row["function"]} has no data-only effect policy on channel '
                         f'{row["channel"]} (supported: {supported}); a new effect family needs a runtime decision')
    return policy


def book_rows(aliases: dict[str, int], type_indices: dict[str, int]) -> dict[str, dict]:
    """{skill id: initial_book skill entry} for the authored rows, each checked against the same
    descriptor gate the runtime applies (hsltools.data.skill_coverage mirrors SkillResolutionRules).
    `aliases` are the mag-spc.h names an authored name may not shadow (a PLAYERS declaration
    token must stay unambiguous)."""
    from hsltools.data.skill_coverage import _descriptor_judgment
    from hsltools.data.skill_targeting import function_bits, range_pattern
    bits = function_bits()
    result = {}
    for row in table()['skills']:
        identifier = skill_id(row)
        where = f'{AUTHORED_SKILLS}: {identifier}'
        if row['type'] not in ELEMENTS:
            raise ValueError(f'{where}: type {row["type"]} is not one of {sorted(ELEMENTS)}')
        if row['name_text'] in aliases:
            raise ValueError(f'{where}: name_text {row["name_text"]} is already a mag-spc.h skill alias')
        policy = effect_policy(row, bits)
        for key in ('range', 'effect_range'):
            range_pattern(row[key])
        _integer(row['expend'], 0, 999, f'{identifier} expend')
        low, _, high = row['damage'].partition(',')
        if _integer(low, 0, 10000, f'{identifier} damage low') > _integer(high, 0, 10000, f'{identifier} damage high'):
            raise ValueError(f'{where}: damage {row["damage"]} low exceeds high')
        _integer(row['hit_ratio'], 0, 100, f'{identifier} hit_ratio')
        _integer(row['use_ratio'], 0, 100, f'{identifier} use_ratio')
        if row['channel'] == 'special':
            _integer(row['attackpow_ratio'], 0, 1000, f'{identifier} attackpow_ratio')
        elif row['effect_proc'] not in EFFECT_PROCS:
            raise ValueError(f'{where}: effect_proc {row["effect_proc"]} is not one of {EFFECT_PROCS}')
        fields = {key: (row['name_text'] if key == 'name' else row[key]) for key in CHANNEL_FIELDS[row['channel']]}
        type_index = type_indices[row['type']]
        element = '' if row['channel'] == 'special' and row['type'] == 'magicOTHER' else str(type_index)
        entry = {'channel': row['channel'], 'type': row['type'], 'code': row['code'],
                 # Authored rows have no mag-spc.h bit; they sort after the original bits of their element.
                 'source_order': type_index * 32 + 31, 'name': row['name_text'],
                 'declaration_field': declaration_field(row), 'alias_bit': 0,
                 'magic_key': ELEMENTS[row['type']][1] if row['channel'] == 'magic' else '',
                 'damage_policy': policy, 'element': element, 'formula_evidence': 'static-derived',
                 'damage_bounds': 'native_triangular', 'fields': fields, 'evidence_tier': 'authored'}
        targeting = {'function_bits': bits, 'ranges': {name: range_pattern(name) for name in (row['range'], row['effect_range'])}}
        judgment = _descriptor_judgment(identifier, fields, {'skills': {identifier: entry}}, targeting)
        if judgment != 'ok':
            raise ValueError(f'{where}: the runtime descriptor gate rejects the row ({judgment})')
        result[identifier] = entry
    return result


def _effect_manifest() -> dict:
    return json.loads((ROOT / MANIFEST).read_text(encoding='utf-8'))


def effect_rows() -> dict[str, dict]:
    """{skill id: effect-script row} in special_effect_scripts.json's row shape plus
    `presentation: script`, each script checked against the player's opcode set and the
    imported objects, sounds and panels."""
    from hsltools.data.skill_targeting import function_bits
    authored = table()
    original = effect_scripts((ROOT / EFFECTS).read_bytes().decode('cp950'))
    manifest = _effect_manifest()
    bits = function_bits()
    shapes = set(manifest['frames']) | set(manifest['special_backgrounds'])
    rows = {}
    for row in authored['skills']:
        identifier = skill_id(row)
        channel = row['channel']
        codes = [row[key] for key in PRESENTATION_FIELDS[channel]]
        actions = {}
        for code in codes:
            if code in authored['scripts']:
                actions[code] = list(authored['scripts'][code])
            elif code in original:
                actions[code] = original[code]
            else:
                raise ValueError(f'{AUTHORED_SKILLS}: {identifier} names script {code}, which is neither an EFFECTS.TXT block nor in `scripts`')
        tokens = [token.strip() for code in codes for line in actions[code] for token in line.split(',')]
        verbs = [token for token in tokens if token.startswith(('ani', 'eff'))]
        for verb in verbs:
            if verb not in IMPLEMENTED_OPCODES:
                raise ValueError(f'{AUTHORED_SKILLS}: {identifier} uses {verb}, which SkillEffectScriptPlayer does not implement (a new opcode is a decision item)')
            if not verb.startswith(VERB_PREFIX[channel]):
                raise ValueError(f'{AUTHORED_SKILLS}: {identifier} is a {channel} row; {verb} belongs to the other script family')
        objects = []
        for token in tokens:
            if token.startswith('obj_') and token not in objects:
                if token not in manifest['objects']:
                    raise ValueError(f'{AUTHORED_SKILLS}: {identifier} inserts {token}, which the skill_effects import does not carry')
                objects.append(token)
        sounds = sorted({token for token in tokens if token.upper().endswith('.WAV')})
        script_shapes = sorted({token for token in tokens if token.upper().endswith('.SHP')})
        missing = [name for name in sounds if name not in manifest['sounds']] + [name for name in script_shapes if name not in shapes]
        if missing:
            raise ValueError(f'{AUTHORED_SKILLS}: {identifier} names members the skill_effects import does not carry: {missing}')
        entry = {'name': row['name_text'], 'channel': channel, 'damage_policy': effect_policy(row, bits)}
        if channel == 'special':
            entry.update({'attack_code': codes[0], 'defense_code': codes[1]})
        else:
            entry.update({'effect_code': codes[0], 'effect_proc': row['effect_proc'], 'effect_caster': ''})
        entry.update({'actions': actions, 'opcodes': sorted(set(verbs)), 'objects': objects, 'sounds': sounds,
                      'script_shapes': script_shapes, 'presentation': 'script', 'evidence_tier': 'authored'})
        rows[identifier] = entry
    return rows


def render() -> dict:
    return {'schema': OUTPUT_SCHEMA, 'evidence_tier': 'authored',
            'sources': {'skills': AUTHORED_SKILLS, 'effects': EFFECTS.as_posix(), 'manifest': MANIFEST.as_posix()},
            'policy': ('Presentation rows of the authored skills (content/authored/roles/skills.json), in the row shape of '
                       'special_effect_scripts.json: each names an EFFECTS.TXT block or an authored script built from the '
                       'opcodes SkillEffectScriptPlayer implements over the imported skill_effects objects and sounds. '
                       'The player reads these rows beside the chapter-1 inventory; `presentation` is always script.'),
            'rows': effect_rows()}


class AuthoredEffectScriptsTask(GeneratedFilesTask):
    name = 'authored_effect_scripts'
    family = 'skills'
    inputs = (AUTHORED_SKILLS, EFFECTS.as_posix(), MANIFEST.as_posix())
    outputs = (OUTPUT.as_posix(),)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/data/authored_skills.py', 'tools/hsltools/data/special_effect_scripts.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(render())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        rows = json.loads(rendered[OUTPUT.as_posix()])['rows']
        return f'AUTHORED_EFFECT_SCRIPTS_PASS rows={len(rows)} special={sum(r["channel"] == "special" for r in rows.values())} magic={sum(r["channel"] == "magic" for r in rows.values())}'


def tasks() -> list[AuthoredEffectScriptsTask]:
    return [AuthoredEffectScriptsTask()]
