"""Join supported initial skills to PLAYERS declarations and exact alias bits.

No EXE is executed. Absence of a source declaration means no initially granted
supported skill, not proof of every original learning/control/state condition.
Registry task initial_skill_book (family skill_book): output
content/generated/hsl/skills/initial_book.json. Bodies moved verbatim from the former hsl_initial_skill_book.py.
The authored skills (content/authored/roles/skills.json, hsltools.data.authored_skills) follow the
registered source rows; a character grants one by writing its name in the declaration field of
its element (they have no mag-spc.h bit).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from hsltools.data import authored_skills
from hsltools.data.first_skill import definition
from hsltools.data.mage_magic import definitions
from hsltools.paths import TABLES
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import blocks, character_rows

OUT = Path('content/generated/hsl/skills/initial_book.json')
SOURCE_NAMES = ['PLAYERS.TXT', 'mag-spc.h', 'SPECIAL.TXT', 'MAGIC.TXT', 'TYPE.H']
# Every PLAYERS ability declaration field (resource-derived). All of them are
# extracted so a registered skill declared in special_earth/wind/water/other2 is
# granted; unregistered aliases still grant nothing.
# mag-spc.h aliases that are neither the RESOURCE name nor name+'2' (resource-derived spelling).
ALIAS_OVERRIDES = {'special:magicOTHER:magicCode14': '金之手LV2'}
DECLARATION_FIELDS = ('magic_earth', 'magic_water', 'magic_wind', 'magic_fire', 'magic_mind', 'magic_other',
                      'special_earth', 'special_water', 'special_wind', 'special_fire', 'special_mind', 'special_other', 'special_other2')
REGISTRY = {
    'special:magicOTHER:magicCode01': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode06': ('special', 'special_other', 'native_special_sequence', ''),
    'special:magicMIND:magicCode03': ('special', 'special_mind', 'native_special_poison', '4'),
    'magic:magicAIR:magicCode01': ('magic', 'magic_wind', 'native_magic_damage', '2'),
    'magic:magicFIRE:magicCode01': ('magic', 'magic_fire', 'native_magic_damage', '3'),
    'magic:magicWATER:magicCode01': ('magic', 'magic_water', 'native_magic_damage', '1'),
    'magic:magicAIR:magicCode05': ('magic', 'magic_wind', 'native_magic_status', '2'),
    'magic:magicMIND:magicCode02': ('magic', 'magic_mind', 'native_magic_status', '4'),
    'magic:magicEARTH:magicCode05': ('magic', 'magic_earth', 'native_magic_status', '0'),
    'magic:magicWATER:magicCode05': ('magic', 'magic_water', 'native_magic_support', '1'),
    'magic:magicWATER:magicCode06': ('magic', 'magic_water', 'native_magic_support', '1'),
    'magic:magicWATER:magicCode07': ('magic', 'magic_water', 'native_magic_support', '1'),
    'magic:magicWATER:magicCode08': ('magic', 'magic_water', 'native_magic_support', '1'),
    'magic:magicEARTH:magicCode06': ('magic', 'magic_earth', 'native_magic_stat', '0'),
    'magic:magicFIRE:magicCode05': ('magic', 'magic_fire', 'native_magic_stat', '3'),
    'magic:magicMIND:magicCode06': ('magic', 'magic_mind', 'native_magic_stat', '4'),
    # magicOTHER damage magic (type 5: no resist_by_type case); PLAYERS magic_other declares 滅／裁.
    'magic:magicOTHER:magicCode01': ('magic', 'magic_other', 'native_magic_damage', '5'),
    'magic:magicOTHER:magicCode02': ('magic', 'magic_other', 'native_magic_damage', '5'),
    # 極 (eff_proc_Global, 120 MP, range5CellCircle→range3CellCircle): same type-5 default path; 059／060 declare it.
    'magic:magicOTHER:magicCode03': ('magic', 'magic_other', 'native_magic_damage', '5'),
}

# Learned source rows are separate from initial declarations. Keeping this
# table explicit prevents a declaration alias from silently granting a skill.
EXTRA_REGISTRY = {
    'magic:magicEARTH:magicCode01': ('magic', 'magic_earth', 'native_magic_damage', '0'),
    'special:magicAIR:magicCode01': ('special', 'special_wind', 'native_special_damage', '2'),
    'magic:magicMIND:magicCode01': ('magic', 'magic_mind', 'native_magic_damage', '4'),
    'magic:magicWATER:magicCode02': ('magic', 'magic_water', 'native_magic_damage', '1'),
    'magic:magicFIRE:magicCode02': ('magic', 'magic_fire', 'native_magic_damage', '3'),
    'magic:magicAIR:magicCode02': ('magic', 'magic_wind', 'native_magic_damage', '2'),
    'magic:magicEARTH:magicCode02': ('magic', 'magic_earth', 'native_magic_damage', '0'),
    'magic:magicMIND:magicCode03': ('magic', 'magic_mind', 'native_magic_status', '4'),
    # eff_proc_Global wind magic: same native damage policy as 風刃; the global effect is presentation only.
    'magic:magicAIR:magicCode03': ('magic', 'magic_wind', 'native_magic_damage', '2'),
    'magic:magicAIR:magicCode04': ('magic', 'magic_wind', 'native_magic_damage', '2'),
    # Line (Dir) effect specials: range1Cell cast, 0x4100e0 line footprint from the chosen cell.
    'special:magicOTHER:magicCode02': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode19': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicAIR:magicCode07': ('special', 'special_wind', 'native_special_damage', '2'),
    # Pure magicFun_Attack specials (0x40a7b0 channel1/proc0; elemental rows read resist_by_type).
    'special:magicAIR:magicCode02': ('special', 'special_wind', 'native_special_damage', '2'),
    'special:magicAIR:magicCode03': ('special', 'special_wind', 'native_special_damage', '2'),
    'special:magicAIR:magicCode04': ('special', 'special_wind', 'native_special_damage', '2'),
    'special:magicEARTH:magicCode02': ('special', 'special_earth', 'native_special_damage', '0'),
    'special:magicEARTH:magicCode03': ('special', 'special_earth', 'native_special_damage', '0'),
    'special:magicFIRE:magicCode01': ('special', 'special_fire', 'native_special_damage', '3'),
    'special:magicMIND:magicCode06': ('special', 'special_mind', 'native_special_damage', '4'),
    'special:magicWATER:magicCode01': ('special', 'special_water', 'native_special_damage', '1'),
    'special:magicOTHER:magicCode03': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode04': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode05': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode07': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode11': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode15': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode17': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode18': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode25': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode26': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode27': ('special', 'special_other', 'native_special_damage', ''),
    # Party members' initial specials (PLAYERS 006 連續突刺／007 碎岩擊／009+053 魔晃斬), magicFun_Attack rows.
    'special:magicOTHER:magicCode16': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicEARTH:magicCode01': ('special', 'special_earth', 'native_special_damage', '0'),
    'special:magicMIND:magicCode05': ('special', 'special_mind', 'native_special_damage', '4'),
    # Enemy "2" variants: separate SPECIAL rows and mag-spc.h bits (alias = name + '2'), same
    # RESOURCE name as the base skill; ids differ. magicOTHER2 (TYPE.H 6) is above the
    # 0x40a7b0 resist switch bound (cmp 4 / ja 0x40aa64) like magicOTHER: no resistance slot.
    'special:magicOTHER2:magicCode01': ('special', 'special_other2', 'native_special_damage', ''),
    'special:magicOTHER2:magicCode02': ('special', 'special_other2', 'native_special_damage', ''),
    'special:magicEARTH:magicCode04': ('special', 'special_earth', 'native_special_damage', '0'),
    'special:magicEARTH:magicCode05': ('special', 'special_earth', 'native_special_damage', '0'),
    'special:magicAIR:magicCode06': ('special', 'special_wind', 'native_special_damage', '2'),
    'special:magicWATER:magicCode05': ('special', 'special_water', 'native_special_damage', '1'),
    'special:magicOTHER:magicCode30': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode31': ('special', 'special_other', 'native_special_damage', ''),
    # Boss initial specials: 017 神罰 (range1Cell cast, range4CellDir line) and 057 咕噜最終型態
    # 虛空無轉 (range4CellCircle cast, range2CellCircle footprint); both magicFun_Attack rows.
    'special:magicOTHER:magicCode22': ('special', 'special_other', 'native_special_damage', ''),
    'special:magicOTHER:magicCode28': ('special', 'special_other', 'native_special_damage', ''),
    # Lane A (status/support/stat/utility families). 魂體衰竭 introduces the weaken status.
    'magic:magicMIND:magicCode04': ('magic', 'magic_mind', 'native_magic_status', '4'),
    'special:magicMIND:magicCode04': ('special', 'special_mind', 'native_special_status', '4'),
    'special:magicOTHER:magicCode21': ('special', 'special_other', 'native_special_status', ''),
    'special:magicOTHER:magicCode09': ('special', 'special_other', 'native_special_status', ''),
    'magic:magicMIND:magicCode07': ('magic', 'magic_mind', 'native_magic_support', '4'),
    'special:magicWATER:magicCode03': ('special', 'special_water', 'native_special_support', '1'),
    'special:magicWATER:magicCode02': ('special', 'special_water', 'native_special_support', '1'),
    'special:magicOTHER:magicCode08': ('special', 'special_other', 'native_special_support', ''),
    'special:magicWATER:magicCode04': ('special', 'special_water', 'native_special_support', '1'),
    'special:magicAIR:magicCode05': ('special', 'special_wind', 'native_special_stat', '2'),
    'special:magicFIRE:magicCode02': ('special', 'special_fire', 'native_special_stat', '3'),
    'special:magicMIND:magicCode01': ('special', 'special_mind', 'native_special_stat', '4'),
    'special:magicMIND:magicCode02': ('special', 'special_mind', 'native_special_utility', '4'),
    'special:magicOTHER:magicCode20': ('special', 'special_other', 'native_special_utility', ''),
    'special:magicOTHER:magicCode24': ('special', 'special_other', 'native_special_utility', ''),
    'special:magicOTHER:magicCode13': ('special', 'special_other', 'native_special_utility', ''),
    'special:magicOTHER:magicCode12': ('special', 'special_other', 'native_special_utility', ''),
    'special:magicOTHER:magicCode10': ('special', 'special_other', 'native_special_utility', ''),  # 銀之手: 004 initial special_other
    # Lane A2 (wave 9): high-tier eff_proc_Global damage magic. magicFun_Attack only, same 0x40a7b0
    # channel0/proc0 roll and resist_by_type slot as the tier-1/2 rows of each element; the wide
    # Global effect is presentation only (no imported art: provisional wind-frame fallback).
    'magic:magicEARTH:magicCode03': ('magic', 'magic_earth', 'native_magic_damage', '0'),  # 天地鳴動: 052／057／060／065 initial, job 99@28／91@30
    'magic:magicEARTH:magicCode04': ('magic', 'magic_earth', 'native_magic_damage', '0'),  # 怒濤地裂崩: 057／060 initial, job 99@37 (range6CellCircle→range4CellCircle, 84 MP)
    'magic:magicFIRE:magicCode03': ('magic', 'magic_fire', 'native_magic_damage', '3'),  # 魔燒焚燼: 051／057／058／060 initial, job 91@25 (range5CellCircle→range3CellCircle, 33 MP)
    'magic:magicFIRE:magicCode04': ('magic', 'magic_fire', 'native_magic_damage', '3'),  # 怒炎魔獄燋: 051／057 initial, job 91@39 (range5CellCircle→range4CellCircle, 84 MP)
    'magic:magicWATER:magicCode03': ('magic', 'magic_water', 'native_magic_damage', '1'),  # 烈蝕水彈: 054／058／060 initial, job 91@27 (range5CellCircle→range2CellCircle, 33 MP)
    'magic:magicWATER:magicCode04': ('magic', 'magic_water', 'native_magic_damage', '1'),  # 極零裂凍破: 058／059 initial, job 91@40 (range5CellCircle→range4CellCircle, 84 MP)
    'magic:magicEARTH:magicCode07': ('magic', 'magic_earth', 'native_magic_stat', '0'),  # 地靈聖護: DefUp area (range4CellCircle→range2CellCircle, 30 MP); 058／065 initial, job 86／87@28
    'magic:magicFIRE:magicCode06': ('magic', 'magic_fire', 'native_magic_stat', '3'),  # 赤炎波動: AttUp area (range4CellCircle→range2CellCircle, 38 MP); 058／065 initial, job 86／87@26
    'magic:magicEARTH:magicCode08': ('magic', 'magic_earth', 'native_magic_support', '0'),  # 大地之癒: Heal area (range4CellCircle→range3CellCircle, 25 MP); 056／065 initial, job 86／87@30
    'magic:magicEARTH:magicCode09': ('magic', 'magic_earth', 'native_magic_support', '0'),  # 大地之惠: Heal area (range6CellCircle→range4CellCircle, 45 MP, eff_proc_Global); 059 initial, job 87@48
    'magic:magicMIND:magicCode05': ('magic', 'magic_mind', 'native_magic_status', '4'),  # 死骸腐靈獄: Attack+Paralysis+Poison+NoMagic+Weaken (0x101d), range5CellCircle→range3CellCircle, 100 MP; 059／068 initial, job 99@42
    'special:magicOTHER:magicCode23': ('special', 'special_other', 'native_special_damage', ''),  # 神怒: job 97 tier 2 (017 邪獸 up-tier) learner; range4CellCircle→range1Cell, 180,250／98, magicOTHER no resist
    'special:magicOTHER:magicCode29': ('special', 'special_other', 'native_special_damage', ''),  # 百裂突刺2 (alias 百裂突刺2, RESOURCE 289): enemy '2' row of OTHER 18 — no PLAYERS declaration and no learner (resource-derived), data row only
    'special:magicOTHER:magicCode32': ('special', 'special_other', 'native_special_utility', ''),  # 獅子吼2 (alias 獅子吼2, RESOURCE 292): enemy '2' row of OTHER 20 — no declaration, no learner (resource-derived), data row only
    'special:magicOTHER2:magicCode03': ('special', 'special_other2', 'native_special_utility', ''),  # 吸血劍2 (alias 吸血劍2 = OTHER2 bit 0x4, RESOURCE 299): enemy '2' row of OTHER 24. 059's PLAYERS special_other lists the alias, but the alias table is field-agnostic: bit 0x4 in special_other resolves to OTHER 03 無想冥殺, so this row has no holder (resource-derived)
    'special:magicOTHER:magicCode14': ('special', 'special_other', 'native_special_utility', ''),  # 高級金之手 (alias 金之手LV2 = 0x2000, RESOURCE 264): StealItem row above OTHER 12 金之手 — no declaration, no learner (resource-derived), data row only
    'magic:magicOTHER:magicCode04': ('magic', 'magic_other', 'native_magic_stat', '5'),  # 魔障壁: magicFun_AllUp 0x100 (all five resistances +rand(14)+7, cap 20／80), range3CellCircle→range1Cell, 31 MP; no initial holder, job 87@48
}


def aliases() -> dict[str, int]:
    text = (TABLES/'mag-spc.h').read_bytes().decode('cp950')
    return {name: int(value, 16) for name, value in
            re.findall(r'^\s*#define\s+(\S+)\s+(0x[0-9a-fA-F]+)\b', text, re.M)}


def declared_mask(expression: str, symbols: dict[str, int], authored_names: frozenset[str] = frozenset()) -> int:
    """mag-spc.h bits of a PLAYERS declaration; authored skill names carry no bit and are skipped."""
    mask = 0
    for token in expression.split(','):
        token = token.strip()
        if token == '0' or token in authored_names:
            continue
        if token not in symbols:
            raise ValueError('Unknown skill alias: '+token)
        mask |= symbols[token]
    return mask


def build() -> dict:
    special, magic = definition(), definitions()
    sources = {'special:magicOTHER:magicCode01': (special['source_fields'], special['name'], '')}
    for key, spell in magic['spells'].items():
        row = spell['fields']
        sources[f'magic:{row["type"]}:{row["code"]}'] = (row, spell['name'], key)
    from hsltools.sources.tables import parse_table
    names_path = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
    names = parse_table(names_path.read_bytes())
    from hsltools.data.moon_dance import definition as moon_definition
    moon = moon_definition()
    sources[moon['skill_id']] = (moon['source_fields'], names[moon['source_fields']['name']], '')
    arrow = next(row for row in blocks((TABLES/'SPECIAL.TXT').read_bytes(), 'special') if row['type']=='magicMIND' and row['code']=='magicCode03')
    sources['special:magicMIND:magicCode03'] = (arrow, names[arrow['name']], '')
    for row in blocks((TABLES/'MAGIC.TXT').read_bytes(), 'magic'):
        sid = f'magic:{row["type"]}:{row["code"]}'
        if sid in REGISTRY and sid not in sources:
            key = {'magic:magicWATER:magicCode01':'water','magic:magicAIR:magicCode05':'poison','magic:magicMIND:magicCode02':'silence',
                   'magic:magicEARTH:magicCode05':'paralysis',
                   'magic:magicWATER:magicCode05':'cure_poison','magic:magicWATER:magicCode06':'heal',
                   'magic:magicWATER:magicCode07':'greater_heal','magic:magicWATER:magicCode08':'life_heal',
                   'magic:magicEARTH:magicCode06':'defense_up','magic:magicFIRE:magicCode05':'attack_up',
                   'magic:magicMIND:magicCode06':'dispel',
                   'magic:magicOTHER:magicCode01':'other','magic:magicOTHER:magicCode02':'other','magic:magicOTHER:magicCode03':'other'}[sid]
            sources[sid] = (row, names[row['name']], key)
    source_rows = {}
    for channel, filename in [('magic', 'MAGIC.TXT'), ('special', 'SPECIAL.TXT')]:
        for row in blocks((TABLES/filename).read_bytes(), channel):
            source_rows[f'{channel}:{row["type"]}:{row["code"]}'] = row
    for skill_id in set(REGISTRY) | set(EXTRA_REGISTRY):
        if skill_id in sources:
            continue
        row = source_rows[skill_id]
        sources[skill_id] = (row, names[row['name']], '')
    all_registry = dict(REGISTRY)
    all_registry.update(EXTRA_REGISTRY)
    if any(declaration not in DECLARATION_FIELDS for _, declaration, _, _ in all_registry.values()):
        raise ValueError('Registered declaration field is not a PLAYERS ability field')
    symbols = aliases()
    type_indices = {name: int(value) for name, value in re.findall(
        r'^\s*#define\s+(magic[A-Z0-9]+)\s+(\d+)\b', (TABLES/'TYPE.H').read_bytes().decode('cp950'), re.M)}
    supported = {}
    for skill_id, (channel, declaration, policy, element) in all_registry.items():
        row, name, key = sources[skill_id]
        key = {'magic:magicEARTH:magicCode01': 'earth', 'magic:magicMIND:magicCode01': 'mind', 'magic:magicWATER:magicCode02': 'water', 'magic:magicFIRE:magicCode02': 'fire', 'magic:magicAIR:magicCode02': 'wind', 'magic:magicEARTH:magicCode02': 'earth', 'magic:magicMIND:magicCode03': 'paralysis',
               'magic:magicOTHER:magicCode01': 'other', 'magic:magicOTHER:magicCode02': 'other', 'magic:magicOTHER:magicCode03': 'other', 'magic:magicAIR:magicCode03': 'wind', 'magic:magicAIR:magicCode04': 'wind',
               'magic:magicMIND:magicCode04': 'weaken', 'magic:magicMIND:magicCode07': 'cure_all',
               'magic:magicEARTH:magicCode03': 'earth', 'magic:magicOTHER:magicCode04': 'resist_up', 'magic:magicMIND:magicCode05': 'decay', 'magic:magicEARTH:magicCode09': 'heal', 'magic:magicEARTH:magicCode08': 'heal', 'magic:magicFIRE:magicCode06': 'attack_up', 'magic:magicEARTH:magicCode07': 'defense_up', 'magic:magicWATER:magicCode04': 'water', 'magic:magicWATER:magicCode03': 'water', 'magic:magicFIRE:magicCode04': 'fire', 'magic:magicFIRE:magicCode03': 'fire', 'magic:magicEARTH:magicCode04': 'earth'}.get(skill_id, key)
        bit = 1 << (int(row['code'].removeprefix('magicCode')) - 1)
        # Enemy "2" rows reuse the base RESOURCE name; their mag-spc.h alias is name + '2'.
        if symbols.get(name) != bit and symbols.get(name + '2') != bit and symbols.get(ALIAS_OVERRIDES.get(skill_id, '')) != bit:
            raise ValueError('Unsupported source ability bit mapping: '+skill_id)
        supported[skill_id] = {'channel':channel, 'type':row['type'], 'code':row['code'],
                               'source_order':type_indices[row['type']]*32 + bit.bit_length()-1,
                               'name':name, 'declaration_field':declaration, 'alias_bit':bit,
                               'magic_key':key, 'damage_policy':policy, 'element':element,
                               'formula_evidence':'static-derived',
                               'damage_bounds':'native_triangular', 'fields':row}
        if policy == 'native_special_sequence':
            supported[skill_id]['sequence'] = {key:moon[key] for key in ['pulses','target_order','kill_accounting','after_zero_hp']}
    authored = authored_skills.book_rows(symbols, type_indices)
    supported.update(authored)
    authored_names = frozenset(entry['name'] for entry in authored.values())
    actors = {}
    for actor in character_rows():
        identifier = f'{int(actor["code"]):03d}'
        declarations = {field:actor[field] for field in DECLARATION_FIELDS if field in actor}
        masks = {field:declared_mask(expr,symbols,authored_names) for field,expr in declarations.items()}
        tokens = {field:{token.strip() for token in expr.split(',')} for field,expr in declarations.items()}
        for field, names in tokens.items():
            for name in names & authored_names:
                if next(entry for entry in authored.values() if entry['name'] == name)['declaration_field'] != field:
                    raise ValueError(f'{identifier}: authored skill {name} is declared in {field}, not in the field of its element')
        granted = [skill_id for skill_id, row in supported.items()
                   if masks.get(row['declaration_field'],0) & row['alias_bit']
                   or (row.get('evidence_tier') == 'authored' and row['name'] in tokens.get(row['declaration_field'], ()))]
        caps = sum(bit for field,bit in [('no_attack',2),('no_poison',0x40),('no_disablemagic',0x1000),('no_paralyze',0x800),('no_weaken',0x2000)] if int(actor.get(field,0)))
        actors[identifier] = {'declarations':declarations, 'supported_initial_ids':granted,
                              'status_capability_flags':caps, 'double_attack':bool(int(actor.get('double_attack',0))),
                              'move_magic_use':bool(int(actor.get('move_magic_use',0))),
                              'traversal':{'flying':bool(int(actor.get('move_fly',0))),
                                           'no_block':bool(int(actor.get('no_block',0))),
                                           'size_type':int(actor.get('size_type',0))}}
    return {'schema':'hsl_initial_supported_skills.v1', 'evidence_tier':'resource-derived',
            'sources':{name:hashlib.sha256((TABLES/name).read_bytes()).hexdigest() for name in SOURCE_NAMES},
            'names_source':{'path':names_path.as_posix(), 'sha256':hashlib.sha256(names_path.read_bytes()).hexdigest()},
            'skills':supported, 'actors':actors,
            'limits':['Only supported source skills are mapped, including exact Acid Mist/Seal aliases; other declarations grant no substitute skill.',
                      'Missing declaration means no supported initial grant; original runtime defaults/learning/job/status are not inferred.',
                      'Registered numeric policies use independently checked native helpers. Full initialization/global RNG/area traversal are separate. Registration grants no substitute ability without matching declarations.']}


def check_pak(path: Path) -> dict:
    from hsltools.probes.skill_cost import canonical_table, check_pak as check_cost_sources
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    check_cost_sources(path)
    packages = find_decoded_paks_packages(path)
    result = {}
    for name in ['PLAYERS.TXT','mag-spc.h']:
        found = [(p,r) for p in packages if (r := find_paks_record_by_name(p['records'],'@:\\data\\'+name.lower()))]
        if len(found) != 1: raise ValueError('Missing/ambiguous skill source '+name)
        p,r = found[0]
        raw = read_paks_record_bytes(p['path'],r,data_end_offset=int(p['paks']['candidate_index_offset']))
        if canonical_table(raw) != canonical_table((TABLES/name).read_bytes()):
            raise ValueError('Original skill source differs: '+name)
        result[name] = hashlib.sha256(raw).hexdigest()
    return result


class InitialSkillBookTask(GeneratedFilesTask):
    name = 'initial_skill_book'
    family = 'skill_book'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',
              'content/imported/hsl/shared/first_skill/', authored_skills.AUTHORED_SKILLS)
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_initial_skill_book.py --check',)
    scripts = ('tools/hsltools/data/skill_book.py', 'tools/hsltools/data/first_skill.py', 'tools/hsltools/data/mage_magic.py', 'tools/hsltools/data/moon_dance.py',
               'tools/hsltools/data/authored_skills.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): (json.dumps(build(), ensure_ascii=False, indent=2) + '\n').encode('utf-8')}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        result = json.loads(rendered[OUT.as_posix()])
        return f'INITIAL_SKILL_BOOK_PASS actors={len(result["actors"])} skills={len(result["skills"])} native_execution=False'


def tasks() -> list[InitialSkillBookTask]:
    return [InitialSkillBookTask()]
