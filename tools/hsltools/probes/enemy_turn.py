"""Original enemy turn oracle: the NPC actions that follow the player's handoff, run by the
original hsl01.exe frame code from a tracked battle save.

Registry task enemy_turn (family probe). generate loads the tracked level-51 HSLBAT sample
(docs/evidence_packets/static_reverse/original_save_format/HSLBAT_first_control.SAV, the
first player control of the first battle) with the original save reader in a whole-image
machine (hsltools.native.battle_machine), ends Leonard's turn by putting him in the player
process's turn-end mode (object +0x8c = 0x10000: 0x443330 then runs its own end sequence —
terrain, poison, recovery, status countdown — and the handoff 0x407510; its draws and HP
changes are meta.handoff), then calls the original frame body 0x42d600 once per frame until
the turn queue hands control back to a player-process actor (object +0x64 == 3). It writes one
`enemy_turn_v1` record per RNG start: the sample's own start (damage stream from the save,
global stream from the emulated clock — see RNG below) and SEEDS for the global stream.

Per actor: the cell when the queue made it current and when it handed over, the action and
its target, and every RNG draw made while it was current (site = call address of the draw
routine's caller, stream, modulus n — null for a raw 32-bit draw — and the value).

RNG streams (static-derived, executed): `global` is 0x458c10 (state 0x4795d4／0x4795d8,
seeded flag 0x4c1e8c, lazily seeded from GetTickCount − [0x4c2310]); rand(n) 0x458c80
returns (raw & 0xffff) % n for n <= 0xffff, raw % n above, and 0 without a draw for n == 0
(recorded with n 0: a draw point that advances no state). `damage` is the state
0x4c3044／0x4c3040 that the wrappers 0x42c780 (rand(n)) and 0x42c720 (raw, single caller
0x409d06) swap into the global generator around one draw;
their draws are attributed to the wrapper's caller. The save carries the damage words; it
does not carry the global state, so the sample start of the global stream is an emulator
artefact (clock stub value plus the draws the save load makes), labelled in meta.rng_source.

Action (runtime-measured on the emulated original): attack = 0x4423c0 exchange started
(phase word 0x4c432c == 0) with the current actor as striker, target = the defender;
magic／skill = the AI name caption 0x43e110 (MAGIC [0x4c2c54]／[0x4c2c40]) or 0x43e1c0
(SPECIAL [0x4c2c44]／[0x4c2c94]) drawn for the current actor, target = the AI target object
[0x4c1cec]; item = 0x409e40(target, item, user == current actor); none of these → wait, whose
target is the held pursuit target (object +0x88 u16 = registry slot + 1, read at handover;
null when 0) — the convention of the remake exporter tests/diagnostics/export_enemy_turns.gd.
`call` (the 0x40bee0 help broadcast) is a side effect of target search, never an action here.

The packet's `growth` section calls the original entry level-up 0x40e870 on the loaded sample's
actor023_2 with its caller's arguments (0x43ef26: object, live +0x1fa, live +0x1f8) and records
every rand(n) call site and whether each stream's state moved — the executed evidence that the
opening level-up draws from the global stream (0x40e92c／0x40e938 first), not the damage stream.

CLI `--lines FILE` also writes the turn split per round, one single-line enemy_turn_v1 object
per round, draws renamed by SITE_MAP (global stream only; a call address becomes the remake's
`Script.function` draw point, a raw & 1 draw becomes n 2 with value & 1; unmapped addresses stay) —
the input of `_enemy_level.py compare`. `--bare-lines FILE` writes the same with draws emptied, the
exporter's `--expect`／`--search` input (the exporter compares non-empty draws as whole JSON, values
included, so it would report `draws differ` on every otherwise agreeing action).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/enemy_turn.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.data import compact_json_text  # noqa: E402
from hsltools.native.image import EXE_SHA  # noqa: E402
from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402
from hsltools.registry import NotGeneratable, PacketTask  # noqa: E402

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_enemy_turn.json'
SAVE = ROOT / 'docs/evidence_packets/static_reverse/original_save_format/HSLBAT_first_control.SAV'
BATTLE = ROOT / 'content/battles/battle_051.json'
TYPE_H = ROOT / 'content/imported/hsl/global/tables/TYPE.H'
SCHEMA = 'hsl_enemy_turn_oracle.v1'
FORMAT = 'enemy_turn_v1'
LEVEL = 51
SEEDS = ((1, 2), (0x12345678, 0x9abcdef0), (7, 7), (0xdeadbeef, 0x13579bdf))
FRAME_LIMIT = 6000
ACTIONS = ('attack', 'magic', 'skill', 'item', 'wait', 'call', 'other')
STREAMS = ('global', 'damage')
# Recording R1-09..R1-12 (docs/evidence_packets/runtime_observations/battle_051_ai_moves): the four
# moves that follow Leonard's first control in both the recording and the sample.
REGRESSION = {'actor024_2': ([15, 22], [15, 18]), 'actor024_1': ([17, 21], [17, 17]),
              'actor026_1': ([13, 6], [11, 7]), 'actor026_2': ([4, 9], [7, 9])}

QUEUE_BASE, QUEUE_INDEX, QUEUE_ENTRY = 0x4c3940, 0x4c6e48, 12
QUEUE_SORT = 0x407340        # rebuilds the round queue: registry slots 0..199, then insertion sort on speed
# Speed overrides for the native queue-sort cases (None = as loaded; 'slot' = speed := registry slot).
QUEUE_CASES = (('loaded', None), ('actor023_2 speed 16 (recording: L3 after the opening level-up)', {'actor023_2': 16}),
               ('every unit speed 10', 10), ('speed = registry slot', 'slot'))
HANDOFF = 0x407510
# Player process 0x443330: object +0x8c high word 1 = the turn-end mode (0x4439b6 → 0x443a67), low word
# its step (jump table 0x4457fc: 0x4454a5 terrain, 0x443a86 0x40e2b0 check／poison, recovery 0x40e3b0／0x40e430,
# status countdown 0x40b910, then the handoff 0x407510). Writing it makes the original run the whole sequence.
END_TURN_MODE = 0x10000
REGISTRY, REGISTRY_SLOTS = 0x4c34c0, 200
LIVE_TABLE, LIVE_SIZE = 0x4c1bc8, 0x1fc
ROUND = 0x4c1bbc             # u16 round counter
GLOBAL_STATE, SEEDED = (0x4795d4, 0x4795d8), 0x4c1e8c
DAMAGE_STATE = (0x4c3044, 0x4c3040)
EXCHANGE, EXCHANGE_PHASE = 0x4423c0, 0x4c432c
MAGIC_CAPTION, MAGIC_SELECTION = 0x43e110, (0x4c2c54, 0x4c2c40)
SPECIAL_CAPTION, SPECIAL_SELECTION = 0x43e1c0, (0x4c2c44, 0x4c2c94)
ITEM_APPLY = 0x409e40
AI_TARGET = 0x4c1cec
RAND, RAND_RETURNS, RAW_RETURN = 0x458c80, (0x458ca1, 0x458cae, 0x458cb2), 0x458c7c
DAMAGE_RAND, DAMAGE_RAND_INNER, DAMAGE_RAND_RET = 0x42c780, 0x42c7af, 0x42c7d8
DAMAGE_RAW, DAMAGE_RAW_INNER, DAMAGE_RAW_RET = 0x42c720, 0x42c74a, 0x42c773
PLAYER_PROCESS = 3
GROWTH, GROWTH_END, GROWTH_ACTOR = 0x40e870, 0x40eb40, 'actor023_2'   # entry level-up, called from 0x43ef26
GROWTH_TARGET_SITES = ['0x40e92c', '0x40e938']                       # 1 + rand(high-low+1) + rand(...)
TRANSITION_STEP, TRANSITION_PENDING = 0x460a06, 0x4bbb5a
# Ablation switches: frame shims left original (keep) or an extra stub (the spike's omission).
ABLATIONS = {'keep-present': 'leave the presentation blit 0x42d280 original',
             'keep-shape': 'leave the shape draw 0x4607f9 original',
             'keep-text': 'leave the text draw 0x460884 original',
             'keep-draw-pass': 'run the walker draw pass 0x45f724..0x45f75e',
             'stub-transition': 'stub the screen-transition stepper 0x460a06 (what the hand-sequenced spike frame did)'}
ABLATION_KEEP = {'keep-present': 0x42d280, 'keep-shape': 0x4607f9, 'keep-text': 0x460884, 'keep-draw-pass': 0x45f724}
LIVE_FIELDS = {'hp': 0xd8, 'max_hp': 0xdc, 'level': 0x9c, 'speed': 0xb8}
# Board injection (apply_board; the _enemy_level round referee and --set): what each field writes in
# the original's memory and why that is the field the original reads.
OBJ_X, OBJ_Y, OBJ_FLAGS, OBJ_MODE, OBJ_HELD, OBJ_SLOT, OBJ_UNIT, OBJ_LIVE = 4, 8, 0x80, 0x8c, 0x88, 0xa0, 0xa2, 0xa4
DEAD_FLAG, DEAD_TABLE = 0x4000000, 0x4c6d80
SIDE_MASK, SAME_CELL, OCCUPY_CLEAR, OCCUPY_SET = 0x40ba20, 0x407940, 0x411b90, 0x411a30
UNREGISTER, TEMPLATE_CLEAR, OBJECT_UNLINK = 0x407720, 0x44cb90, 0x45e3ed
PLAYER_SIDE = 0x10000        # the player process clears its own cell with side 0x10000 (0x443681)
INJECTION = {
    'speed': 'live [0x4c1bc8] + (object +0xa4) x 0x1fc, +0xb8: the key 0x407340 sorts on (0x4073de)',
    'hp': 'live +0xd8, clamped to live +0xdc as the remake exporter clamps (--set ID.hp writes it raw)',
    'level': 'live +0x9c', 'max_hp': 'live +0xdc',
    'units': 'object +4/+8 pixel x/y (cell = value >> 5; the low five bits are kept). Map occupancy moves with it: '
             '0x411b90(obj, 0x40ba20(obj)) clears the old cell unless 0x407940 finds another object there (the script-departure '
             'order 0x453c9a..0x453caf), 0x411a30(obj, same mask) marks the new one; all clears before all writes before all marks',
    'targets': 'object +0x88 u16 = registry slot + 1 of the held pursuit target (0 = none), read by the AI target scan',
    'dead': 'the death entry writes 0x43ef36..0x43ef5b (+0x80 |= 0x4000000, +0x8c = 0, byte [0x4c6d80 + u16 +0xa2] = 1), live hp 0, '
            'then what the death sub-states run: 0x411b90(obj, 0x40ba20(obj)) (NPC 0x43f179; player process side 0x10000, 0x443687) '
            'frees the cell (no corpse stays), then 0x407720 (registry slot, queue entry, side totals 0x4c1b90/0x4c1b94), '
            '0x44cb90(live idx), 0x45e3ed(obj) (0x43f190..0x43f1b6). Not run: the death caption/event 0x446b60/0x446c40 and the '
            'killer experience and money',
    'turn': 'u16 round counter [0x4c1bbc]',
    'live': '--set ID.FIELD=N: the live field raw (hp/max_hp/level/speed)',
}
# Draw-point map (static-derived: each call site disassembled back to its function and compared with the
# remake line that draws there). Key: a global-stream `draws[].site` (the call address of the draw routine's
# caller). Value: (the remake draw point the exporter records — tests/diagnostics/export_enemy_turns.gd names a draw by
# its innermost AI-rule frame, `Script.function`; None = no remake draw point), the remake modulus for a raw
# original draw (the original tests raw & 1 where the remake draws rand(2): the same bit for the same
# generator state, so a mapped raw draw carries value & 1), the basis.
SITE_MAP: dict[str, tuple[str | None, int | None, str]] = {
    '0x40bd4f': ('AIDecisionRules.select_target', 2, '0x40bb80 target scan, equal-score tie: raw & 1 (AIDecisionRules.gd:96/105)'),
    '0x40c061': ('AIPriorityRules.low_hp_target', None, '0x40bf70 low-HP ally test: 12 + rand(18) percent (AIPriorityRules.gd:88)'),
    '0x40c138': ('AIPriorityRules.self_recovery', None, '0x40c110 own-HP test: 12 + rand(18) percent (AIPriorityRules.gd:51)'),
    '0x40c58d': ('AIDecisionRules.select_action', None, '0x40c570 action-class roll rand(99) + 1 (AIDecisionRules.gd:40)'),
    '0x40c5b3': ('AIDecisionRules.select_action', None, '0x40c570 re-roll rand(99) + 1 (AIDecisionRules.gd:50)'),
    '0x40c5f8': ('AIDecisionRules.select_action', None, '0x40c570 re-roll rand(99) + 1 (AIDecisionRules.gd:50)'),
    '0x40c7f8': ('AISkillDecisionRules.select_index', None, '0x40c770 MAGIC list start rand(32) % count (AISkillDecisionRules.gd:44)'),
    '0x40c842': ('AISkillDecisionRules.select_index', None, '0x40c770 MAGIC per-entry rate rand(100) + 1 (AISkillDecisionRules.gd:48)'),
    '0x40de0c': ('AISkillDecisionRules.select_index', None, '0x40dd80 SPECIAL list start rand(32) % count (AISkillDecisionRules.gd:44)'),
    '0x40de56': ('AISkillDecisionRules.select_index', None, '0x40dd80 SPECIAL per-entry rate rand(100) + 1 (AISkillDecisionRules.gd:48)'),
    '0x40d500': ('AISkillDecisionRules.area_order', None, '0x40d4e0 area-first roll rand(100) + 1 (AISkillDecisionRules.gd:26)'),
    '0x4136ba': ('AINavigationRules.station_order', 2, '0x413390 station sort, equal-distance swap: raw & 1 (AINavigationRules.gd station_order)'),
    '0x440bf5': ('AINavigationRules.attack_station', None, '0x440b2c no-foe station roll rand(99) + 1 (AINavigationRules.gd:359)'),
    '0x41385d': ('AINavigationRules.nearest_stoppable', 2, '0x413740 equal-distance cell: raw & 1 (AINavigationRules.gd:288)'),
    '0x413890': ('AINavigationRules.nearest_stoppable', None, '0x413740 crowded cell skip rand(100) < 80 (AINavigationRules.gd:289)'),
    '0x440db5': ('AIPriorityRules.choose_check', None, 'NPC priority chain first roll rand(99) + 1 (AIPriorityRules.gd:33)'),
    '0x440ddf': ('AIPriorityRules.choose_check', None, 'NPC priority chain re-roll rand(99) + 1 (AIPriorityRules.gd:43)'),
    '0x440e1b': ('AIPriorityRules.choose_check', None, 'NPC priority chain re-roll rand(99) + 1 (AIPriorityRules.gd:43)'),
    '0x440e57': ('AISupportRules.next_check', None, 'NPC support chain roll rand(99) + 1 (AISupportRules.gd:32)'),
    '0x440e93': ('AISupportRules.next_check', None, 'NPC support chain roll rand(99) + 1 (AISupportRules.gd:32)'),
    '0x440ecf': ('AISupportRules.next_check', None, 'NPC support chain roll rand(99) + 1 (AISupportRules.gd:32)'),
    '0x43ff32': ('AIDecisionRules.side_walk_roll', None, '0x43ff1f..0x44003c magic category found no cast: side walk on '
                                                          'rand(100) <= 10 (AIDecisionRules.gd side_walk_roll)'),
    '0x40cb54': ('AISkillPlanning.centre_scan', 2, '0x40c9a0 contains-held best, equal coverage: raw & 1 (AISkillPlanning.gd centre_scan)'),
    '0x40cb99': ('AISkillPlanning.centre_scan', 2, '0x40c9a0 general best, equal coverage: raw & 1 keeps the later centre '
                                                   '(AISkillPlanning.gd centre_scan)'),
    '0x40d1c8': ('AISkillPlanning._cast_search', None, '0x40cca0 kept move-search cells, no threat: rand(count) (AISkillPlanning.gd _cast_search)'),
    '0x40d273': ('AISkillDecisionRules.farthest_index', 2, '0x40d200..0x40d2b0 equal distance from the threat: raw & 1 '
                                                           '(AISkillDecisionRules.gd farthest_index)'),
}
# Damage-stream sites (stream 'damage', the wrappers' callers): the remake draws them from DamageRandomStream,
# which the exporter's AI draw record leaves out, so mapped lines drop them (original_damage_random.md).
DAMAGE_SITE_MAP: dict[str, str] = {
    '0x442669': 'CoreCombatRules.attack_back_triggered (0x4423c0 counter gate rand(100) + 1)',
    '0x403efa': 'CoreCombatRules.resolve_attack (0x403860 hit rand(100))',
    '0x403f51': 'CoreCombatRules.critical_impact (0x403860 critical rand(100))',
    '0x409c96': 'CoreCombatRules.preview_damage (0x409be0 ordinary damage)',
    '0x409cc3': 'CoreCombatRules.preview_damage (0x409be0 ordinary damage)',
    '0x409ce6': 'CoreCombatRules.preview_damage (0x409be0 ordinary damage)',
    '0x409cf5': 'CoreCombatRules.preview_damage (0x409be0 ordinary damage)',
    '0x40a660': 'ExperienceRules.from_contribution (0x40a5d0 contribution EXP)',
    '0x40a6d7': 'ExperienceRules.from_contribution (0x40a5d0 contribution EXP)',
    '0x40a7f0': 'NativeMagicRollRules.roll (0x40a7b0 magic hit rand(100) + 1)',
    '0x40a884': 'NativeMagicRollRules.roll (0x40a7b0 spread rand(half + 1))',
    '0x40a893': 'NativeMagicRollRules.roll (0x40a7b0 spread rand(half + 1))',
}
# Global-stream sites seen only inside a magic action window (level-51 magic sample, _enemy_level.py) with no
# remake draw point; map_draws keeps their addresses. Enclosing function by nearest preceding call target —
# the meaning of each draw is not individually proven.
UNMAPPED_ACTION_SITES: dict[str, str] = {
    '0x4013d4': '0x401390 (called from the 0x402066/0x403b63/0x405414 effect paths)',
    '0x4013f3': '0x401390',
    '0x401450': '0x401390',
    '0x415c5a': '0x415c10 (called from 0x408ba5 and the 0x4161d5.. effect processes)',
    '0x415c7b': '0x415c10',
    '0x415cf5': '0x415c10',
    '0x4160e1': 'effect-process region 0x415d90..0x4239xx',
    '0x416307': 'effect-process region 0x415d90..0x4239xx',
    '0x41635c': 'effect-process region 0x415d90..0x4239xx',
    '0x41646e': 'effect-process region 0x415d90..0x4239xx',
    '0x4164a6': 'effect-process region 0x415d90..0x4239xx',
    '0x41f4f4': 'effect-process region 0x415d90..0x4239xx',
    '0x41f54a': 'effect-process region 0x415d90..0x4239xx',
    '0x41f560': 'effect-process region 0x415d90..0x4239xx',
    '0x4238bd': 'effect-process region 0x415d90..0x4239xx',
    '0x4238e9': 'effect-process region 0x415d90..0x4239xx',
    '0x423955': 'effect-process region 0x415d90..0x4239xx',
    '0x407dba': '0x407cc0 unit entry (0x43eef6/0x44343e): rand(0x18) into +0x7c for an object that was not on the board at '
                'round start (level 51 escape cell [8,6]); drawn inside the running action window, not by the caster',
    '0x407c86': '0x407c40 carry roll rand(101) (called from 0x407e3b in the same 0x407cc0 entry; '
                'battle_reward_inputs.md)',
    '0x40e92c': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40e938': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40e956': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40e9a2': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40ea0b': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40ea38': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40ea62': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40ea90': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40eabe': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
    '0x40eaf9': '0x40e870 level-up growth of the same entering object (0x43ef26 growth words)',
}


def map_draws(draws: list[dict], site_map: dict = SITE_MAP) -> list[dict]:
    """Original draws as the remake exporter names them: global-stream draws only; a mapped site becomes
    `Script.function` (raw draws: n and value & 1 as the remake's rand(2)); an unmapped site keeps its address."""
    out = []
    for draw in draws:
        if draw.get('stream', 'global') != 'global':
            continue
        name, n, _ = site_map.get(draw['site'], (None, None, ''))
        raw = draw['n'] is None and n is not None
        out.append({'site': name or draw['site'], 'n': n if raw else draw['n'],
                    'value': draw['value'] & 1 if raw and n == 2 else draw['value']})
    return out


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def magic_groups() -> dict[int, str]:
    """TYPE.H element defines (magicEARTH 0 .. magicOTHER2 6); magicCodeNN is 0-based."""
    text = TYPE_H.read_bytes().decode('cp950', 'replace')
    return {int(value): name for name, value in re.findall(r'#define\s+(magic[A-Z][A-Z0-9]*)\s+(\d+)', text) if int(value) <= 6}


def skill_identity(channel: str, group: int, index: int, groups: dict[int, str]) -> str:
    return f'{channel}:{groups.get(group, f"group{group}")}:magicCode{index + 1:02d}'


def remake_names(machine, battle_path: Path = BATTLE, by_coord: bool = False) -> dict[int, str]:
    """Registry object → remake unit id. Units of one actor code are matched in registry-slot
    order against the battle's playable_units order (the save's registry slots 20.. follow the
    opening order); by_coord (a level just entered, units still on their opening cells) first
    takes the unit of that code whose opening coord is the object's cell — except units an opening
    actInsertObjectRandomPos binds to a random slot (STORY037's guards): their cell is the shuffled
    slot's, so they keep registry-slot (insert) order."""
    battle = json.loads(battle_path.read_text())
    units = battle['playable_units']
    shuffled = {b.get('unit_id') for b in battle.get('opening', {}).get('actor_bindings', {}).values() if 'random_slot' in b}
    by_code: dict[int, list[dict]] = {}
    for unit in units:
        by_code.setdefault(int(unit['actor_id']), []).append(unit)
    names = {}
    live = machine.get(LIVE_TABLE)
    objects = [(slot, machine.get(REGISTRY + 4 * slot)) for slot in range(REGISTRY_SLOTS)]
    objects = [(slot, obj, machine.get(live + LIVE_SIZE * machine.get(obj + 0xa4))) for slot, obj in objects if obj]
    if by_coord:
        for slot, obj, code in objects:
            cell = [machine.geti(obj + 4) >> 5, machine.geti(obj + 8) >> 5]
            pool = by_code.get(code, [])
            match = next((unit for unit in pool if list(unit.get('coord', [])) == cell and unit['id'] not in shuffled), None)
            if match is not None:
                pool.remove(match)
                names[obj] = match['id']
    for slot, obj, code in objects:
        if obj not in names:
            pool = by_code.get(code, [])
            names[obj] = pool.pop(0)['id'] if pool else f'slot{slot}_code{code:03d}'
    return names


class TurnRun:
    """Hooks the draw routines and the action entry points on a loaded machine and runs
    frames until a player-process actor is current again."""

    def __init__(self, machine, names: dict[int, str]) -> None:
        from hsltools.native.battle_machine import RAND_INNER_RETURNS
        self.m, self.names = machine, names
        self.groups = magic_groups()
        self.inner = RAND_INNER_RETURNS
        self.actions: list[dict] = []
        self.current_obj = None
        self.pending: list[tuple[int, int]] = []
        self.wrapper_sites: list[int] = []
        self.frame_index = 0
        self.stop = None
        self.handoff: dict | None = None   # the player's own turn-end sequence (draws, hp, frames)
        self.removed: set[int] = set()      # objects a board killed (unlinked by 0x45e3ed: their memory is not a unit any more)
        # live-record index (object +0xa4) per unit, read once: a unit that dies in play is unlinked
        # (0x45e3ed) and its object word is no longer an index, while its live record stays in the table
        self.live_index = {obj: machine.get(obj + 0xa4) for obj in names}
        m = machine
        m.hook(RAND, lambda: self.pending.append((m.arg(0), m.return_address())))
        for at in RAND_RETURNS:
            m.hook(at, self._rand_out)
        m.hook(RAW_RETURN, self._raw_out)
        for entry, ret in ((DAMAGE_RAND, DAMAGE_RAND_RET), (DAMAGE_RAW, DAMAGE_RAW_RET)):
            m.hook(entry, lambda: self.wrapper_sites.append(m.return_address() - 5))
            m.hook(ret, lambda: self.wrapper_sites.pop())
        m.hook(EXCHANGE, self._exchange)
        m.hook(MAGIC_CAPTION, lambda: self._cast('magic', MAGIC_SELECTION))
        m.hook(SPECIAL_CAPTION, lambda: self._cast('skill', SPECIAL_SELECTION))
        m.hook(ITEM_APPLY, self._item)

    # ---- state readers
    def queue_current(self) -> int:
        index = self.m.geti(QUEUE_INDEX)
        return self.m.get(QUEUE_BASE + QUEUE_ENTRY * index) if index >= 0 else 0

    def cell(self, obj: int) -> list[int]:
        return [self.m.geti(obj + 4) >> 5, self.m.geti(obj + 8) >> 5]

    def live(self, obj: int, field: str) -> int:
        index = self.live_index.get(obj)
        index = self.m.get(obj + 0xa4) if index is None else index
        return self.m.geti(self.m.get(LIVE_TABLE) + LIVE_SIZE * index + LIVE_FIELDS[field])

    def name(self, obj: int) -> str | None:
        return self.names.get(obj, f'obj{obj:#x}') if obj else None

    def hp(self) -> dict[str, int]:
        return {name: self.live(obj, 'hp') for obj, name in self.names.items() if obj not in self.removed}

    def chase(self, obj: int) -> str | None:
        slot = self.m.get16(obj + 0x88)
        return self.name(self.m.get(REGISTRY + 4 * (slot - 1))) if slot else None

    # ---- bookkeeping
    def sync(self) -> None:
        """Close the running action and open the next one when the queue moved on."""
        obj = self.queue_current()
        if obj == self.current_obj:
            return
        if self.handoff is not None and self.handoff['frames'][1] is None:
            before = self.handoff.pop('_hp')
            self.handoff['hp'] = {k: v - before[k] for k, v in self.hp().items() if v != before[k]}
            self.handoff['frames'][1] = self.frame_index
        if self.current_obj is not None and self.actions:
            action = self.actions[-1]
            action['to'] = self.cell(self.current_obj)
            action['_meta']['frames'][1] = self.frame_index
            action['_meta']['chase'] = self.chase(self.current_obj)
            if action['action'] == 'wait':   # held pursuit target, as the remake exporter writes a Wait
                action['target'] = action['_meta']['chase']
            before = action['_meta'].pop('_hp')
            action['_meta']['hp'] = {k: v - before[k] for k, v in self.hp().items() if v != before[k]}
        self.current_obj = obj
        if obj and self.m.get(obj + 0x64) == PLAYER_PROCESS:
            self.on_player(obj)
            return
        self.actions.append({'actor': self.name(obj), 'from': self.cell(obj), 'to': None, 'action': 'wait', 'target': None,
                             'skill': None, 'draws': [],
                             '_meta': {'frames': [self.frame_index, None], 'round': self.m.get16(ROUND), 'counters': [],
                                       '_hp': self.hp()}})

    def on_player(self, obj: int) -> None:
        """A player-process actor became current: the save-path run ends there."""
        self.stop = self.stop or 'player_control'

    def active(self) -> dict | None:
        self.sync()
        return self.actions[-1] if self.actions and self.stop is None and self.current_obj else None

    def record(self, site: int, stream: str, n: int | None, value: int) -> None:
        action = self.active()
        draw = {'site': f'{site:#x}', 'n': n, 'value': value, 'stream': stream}
        if action is not None:
            action['draws'].append(draw)
        elif self.handoff is not None and self.handoff['frames'][1] is None:
            self.handoff['draws'].append(draw)

    def _rand_out(self) -> None:
        n, back = self.pending.pop()   # rand(0) is recorded (n 0, value 0) although it advances no state
        damage = back == DAMAGE_RAND_INNER
        self.record(self.wrapper_sites[-1] if damage else back - 5, 'damage' if damage else 'global', n, self.m.eax())

    def _raw_out(self) -> None:
        back = self.m.return_address()
        if back in self.inner:
            return   # counted by rand(n)
        damage = back == DAMAGE_RAW_INNER
        self.record(self.wrapper_sites[-1] if damage else back - 5, 'damage' if damage else 'global', None, self.m.eax())

    def _classify(self, kind: str, target: int, skill: str | None) -> None:
        action = self.active()
        if action is None or action['action'] in ('magic', 'skill', 'item'):
            return
        if kind == 'attack' and action['action'] == 'attack':
            return
        action.update(action=kind, target=self.name(target), skill=skill)

    def _exchange(self) -> None:
        if self.m.get(EXCHANGE_PHASE) != 0:
            return
        striker, defender = self.m.arg(0), self.m.arg(1)
        action = self.active()
        if action is None:
            return
        if striker == self.current_obj:
            self._classify('attack', defender, None)
        else:
            action['_meta']['counters'].append([self.name(striker), self.name(defender)])

    def _cast(self, kind: str, selection: tuple[int, int]) -> None:
        group, index = self.m.get(selection[0]), self.m.get(selection[1])
        self._classify(kind, self.m.get(AI_TARGET), skill_identity('magic' if kind == 'magic' else 'special', group, index, self.groups))

    def _item(self) -> None:
        if self.m.arg(2) == self.current_obj:
            self._classify('item', self.item_target(self.m.arg(0)), f'item:{self.m.arg(1)}')

    def item_target(self, obj: int) -> int:
        """0x409e40 applies the item to the live record at obj +0xa4 (0x409e55), not to obj itself. The AI path
        0x440375 passes [0x4c1cec] = 0x4c42a0, a static object holding the target's live index (level 52 s1:
        ally024_1's 241 heals ally023_2), so a pointer that is no unit is named by that live index."""
        if obj in self.names:
            return obj
        index = self.m.get(obj + 0xa4)
        return next((unit for unit, live in self.live_index.items() if live == index and unit not in self.removed), obj)

    def end_player_turn(self) -> None:
        """Put the current player-process actor into the turn-end mode (+0x8c = 0x10000) so the
        original player process runs its own end sequence and handoff on the next frames."""
        obj = self.current_obj
        if not obj or self.m.get(obj + 0x64) != PLAYER_PROCESS:
            raise RuntimeError('end_player_turn: the current actor is not a player-process object')
        self.handoff = {'actor': self.name(obj), 'draws': [], 'frames': [self.frame_index, None], '_hp': self.hp()}
        self.m.put(obj + 0x8c, END_TURN_MODE)

    def run(self, frame_limit: int) -> None:
        m = self.m
        self.sync()
        self.end_player_turn()
        while self.stop is None:
            self.sync()
            if self.stop:
                break
            if self.frame_index >= frame_limit:
                self.stop = 'frame_limit'
                break
            m.frame()
            self.frame_index += 1
            if m.stop_reason:
                self.stop = f'emulator: {m.stop_reason}'


def round_lines(turn: dict, site_map: dict | None = None) -> list[dict]:
    """The turn as the remake exporter prints it: one enemy_turn_v1 object per round
    (meta.actions[].round); later rounds carry no rng start. Draws: emptied without a site map
    (the exporter's --expect then compares actions only), else map_draws."""
    out: list[dict] = []
    for action, meta in zip(turn['actions'], turn['meta']['actions']):
        if not out or out[-1]['turn'] != meta['round']:
            out.append({'format': FORMAT, 'battle': turn['battle'], 'turn': meta['round'],
                        'rng': {} if out else turn['rng'], 'actions': []})
        out[-1]['actions'].append(dict(action, draws=map_draws(action['draws'], site_map) if site_map else []))
    return out


def write_lines(path: Path, turn: dict, site_map: dict | None) -> None:
    path.write_text(''.join(json.dumps(line, ensure_ascii=False) + '\n' for line in round_lines(turn, site_map)), encoding='utf-8')


def parse_seed(values: list[str] | None) -> tuple[int, int] | None:
    return (int(values[0], 0) & 0xffffffff, int(values[1], 0) & 0xffffffff) if values else None


def run_turn(exe: Path, save: bytes, global_seed: tuple[int, int] | None = None, damage_seed: tuple[int, int] | None = None,
             edits: list[tuple[str, str, int]] = (), frame_limit: int = FRAME_LIMIT, use_cache: bool = True,
             ablate: tuple[str, ...] = ()) -> dict:
    """One enemy_turn_v1 record from the loaded save (see the module docstring)."""
    from hsltools.native.battle_machine import loaded_machine
    machine, info = loaded_machine(exe, save, LEVEL, use_cache)
    names = remake_names(machine)
    rng_source = {'global': 'save load: clock-stub seed ' + json.dumps(info['load']['global_draws']),
                  'damage': 'save words 0x4c3044/0x4c3040'}
    if global_seed is not None:
        machine.put(GLOBAL_STATE[0], global_seed[0]); machine.put(GLOBAL_STATE[1], global_seed[1]); machine.put(SEEDED, 1)
        rng_source['global'] = 'injected (seeded flag 0x4c1e8c = 1)'
    if damage_seed is not None:
        machine.put(DAMAGE_STATE[0], damage_seed[0]); machine.put(DAMAGE_STATE[1], damage_seed[1])
        rng_source['damage'] = 'injected'
    current = machine.get(QUEUE_BASE + QUEUE_ENTRY * machine.geti(QUEUE_INDEX))
    applied = apply_board(machine, names, edits_board(edits), current=current) if edits else []
    rng = {'global': [machine.get(GLOBAL_STATE[0]), machine.get(GLOBAL_STATE[1])],
           'damage': [machine.get(DAMAGE_STATE[0]), machine.get(DAMAGE_STATE[1])]}
    start_round = machine.get16(ROUND)
    first = machine.get(QUEUE_BASE + QUEUE_ENTRY * machine.geti(QUEUE_INDEX))
    machine.install_frame_stubs(keep=tuple(ABLATION_KEEP[name] for name in ablate if name in ABLATION_KEEP))
    if 'stub-transition' in ablate:
        machine.stub(TRANSITION_STEP, 0, 'ablation: transition stepper 0x460a06')
    run = TurnRun(machine, names)
    run.removed = killed(names, edits_board(edits))
    run.current_obj = first      # the player's own entry is not an NPC action
    run.run(frame_limit)
    if run.handoff:
        run.handoff.pop('_hp', None)
    actions, meta_actions = [], []
    for action in run.actions:
        meta = action.pop('_meta')
        meta.pop('_hp', None)
        actions.append(action)
        meta_actions.append(meta)
    return {'format': FORMAT, 'battle': f'{LEVEL:03d}', 'turn': start_round, 'rng': rng, 'actions': actions,
            'meta': {'stop': run.stop, 'next_actor': run.name(run.current_obj) if run.stop == 'player_control' else None,
                     'frames': run.frame_index, 'round_end': machine.get16(ROUND), 'first_actor': names.get(first),
                     'rng_source': rng_source, 'edits': applied, 'ablate': list(ablate), 'cache': info['cache'],
                     'transition_pending': machine.get(TRANSITION_PENDING), 'current': run.name(run.current_obj),
                     'handoff': run.handoff,
                     'stub_hits': dict(sorted(machine.stub_hits.items())), 'actions': meta_actions,
                     'hp_end': run.hp()}}


def queue_sort_cases(exe: Path, save: bytes) -> list[dict]:
    """Call the original queue builder 0x407340 on the loaded sample under QUEUE_CASES speeds
    and read the queue it writes (entries [object, registry slot, 1], index reset to 0)."""
    from hsltools.native.battle_machine import loaded_machine
    machine, _ = loaded_machine(exe, save, LEVEL)
    names = remake_names(machine)
    slots = {machine.get(REGISTRY + 4 * slot): slot for slot in range(REGISTRY_SLOTS) if machine.get(REGISTRY + 4 * slot)}
    ids = {name: obj for obj, name in names.items()}
    speed_at = {obj: machine.get(LIVE_TABLE) + LIVE_SIZE * machine.get(obj + 0xa4) + LIVE_FIELDS['speed'] for obj in names}
    snapshot = machine.snapshot()
    cases = []
    for label, speeds in QUEUE_CASES:
        machine.restore(snapshot)
        if isinstance(speeds, dict):
            for name, value in speeds.items():
                machine.put(speed_at[ids[name]], value)
        elif speeds is not None:
            for obj in names:
                machine.put(speed_at[obj], slots[obj] if speeds == 'slot' else speeds)
        machine.call(QUEUE_SORT)
        if machine.stop_reason:
            raise RuntimeError(f'0x407340 ({label}): {machine.stop_reason}')
        order = []
        for index in range(REGISTRY_SLOTS):
            obj = machine.get(QUEUE_BASE + QUEUE_ENTRY * index)
            if not obj:
                break
            order.append([names[obj], machine.get(QUEUE_BASE + QUEUE_ENTRY * index + 4), machine.geti(speed_at[obj])])
        cases.append({'case': label, 'index': machine.geti(QUEUE_INDEX), 'order': order})
    machine.restore(snapshot)
    return cases


def growth_draws(exe: Path, save: bytes) -> dict:
    """Call the original entry level-up 0x40e870 on the loaded sample's GROWTH_ACTOR with the
    arguments its caller 0x43ef26 pushes and record which generator it draws from."""
    from hsltools.native.battle_machine import loaded_machine
    machine, _ = loaded_machine(exe, save, LEVEL)
    obj = {name: obj for obj, name in remake_names(machine).items()}[GROWTH_ACTOR]
    rec = machine.get(LIVE_TABLE) + LIVE_SIZE * machine.get(obj + 0xa4)
    args = [machine.get16(rec + 0x1fa), machine.get16(rec + 0x1f8)]
    fields = lambda: {field: machine.geti(rec + offset) for field, offset in LIVE_FIELDS.items()}
    words = lambda addresses: [machine.get(a) for a in addresses]
    before, global0, damage0 = fields(), words(GLOBAL_STATE), words(DAMAGE_STATE)
    sites, wrappers = [], []
    machine.hook(RAND, lambda: sites.append(f'{machine.return_address() - 5:#x}'))
    for wrapper in (DAMAGE_RAND, DAMAGE_RAW):
        machine.hook(wrapper, lambda wrapper=wrapper: wrappers.append(f'{wrapper:#x}'))
    machine.call(GROWTH, obj, *args)
    if machine.stop_reason:
        raise RuntimeError(f'0x40e870: {machine.stop_reason}')
    return {'function': f'{GROWTH:#x}', 'caller': '0x43ef26', 'actor': GROWTH_ACTOR, 'args': args,
            'before': before, 'after': fields(), 'rand_sites': sites, 'damage_wrappers': wrappers,
            'global_moved': words(GLOBAL_STATE) != global0, 'damage_moved': words(DAMAGE_STATE) != damage0}


def execute_packet(exe: Path) -> dict:
    from hsltools.native.battle_machine import SHIMS
    save = SAVE.read_bytes()
    queue = queue_sort_cases(exe, save)
    growth = growth_draws(exe, save)
    turns = [run_turn(exe, save)] + [run_turn(exe, save, global_seed=seed) for seed in SEEDS]
    for turn in turns:
        turn['meta'].pop('cache')
    ablations = []
    for name in ABLATIONS:
        meta = run_turn(exe, save, ablate=(name,))['meta']
        last = meta['actions'][-1] if meta['actions'] else {}
        ablations.append({'ablate': name, 'what': ABLATIONS[name], 'stop': meta['stop'], 'frames': meta['frames'],
                          'current': meta['current'], 'actions_closed': sum(a['frames'][1] is not None for a in meta['actions']),
                          'transition_pending': meta['transition_pending'], 'last_round': last.get('round')})
    return {'schema': SCHEMA, 'evidence_tier': 'runtime-measured (emulated original: whole hsl01.exe image in unicorn)',
            'exe_sha256': EXE_SHA, 'save': SAVE.relative_to(ROOT).as_posix(), 'save_sha256': sha256(save),
            'battle_units': BATTLE.relative_to(ROOT).as_posix(), 'level': LEVEL, 'shims': SHIMS,
            'seeds': [[a, b] for a, b in SEEDS], 'queue_sort': queue, 'growth': growth, 'ablations': ablations,
            'turns': turns}


def check_ablations(runs: list[dict]) -> None:
    """Every remaining frame shim is needed (dropping it stops the turn before control returns),
    and stubbing 0x460a06 reproduces the attack wait: the first attacker never hands over and
    the transition-pending word [0x4bbb5a] stays set."""
    if [run['ablate'] for run in runs] != list(ABLATIONS):
        raise ValueError('ablations differ from ABLATIONS')
    for run in runs:
        if run['stop'] == 'player_control':
            raise ValueError(f'ablation {run["ablate"]}: the turn still returns control, the shim is not needed')
    stall = runs[list(ABLATIONS).index('stub-transition')]
    if (stall['stop'], stall['current'], stall['transition_pending']) != ('frame_limit', 'actor021_2', 1):
        raise ValueError(f'ablation stub-transition does not reproduce the attack wait: {stall}')


def check_queue_sort(cases: list[dict]) -> None:
    """0x407340 is a stable descending sort: speed first, equal speeds in registry-slot order."""
    if [case['case'] for case in cases] != [label for label, _ in QUEUE_CASES]:
        raise ValueError('queue_sort cases differ from QUEUE_CASES')
    for case in cases:
        order = case['order']
        if case['index'] != 0 or order != sorted(order, key=lambda entry: (-entry[2], entry[1])):
            raise ValueError(f'queue_sort {case["case"]}: not speed-descending with registry-slot ties')
        if sorted(entry[1] for entry in order) != sorted(entry[1] for entry in cases[0]['order']):
            raise ValueError(f'queue_sort {case["case"]}: registry slots differ')
    position = [{entry[0]: i for i, entry in enumerate(case['order'])} for case in cases]
    if not position[0]['leonard'] < position[0]['actor023_1'] < position[0]['actor023_2']:
        raise ValueError('queue_sort loaded: equal-speed leonard／023_1／023_2 are not in slot order')
    if not position[1]['actor023_2'] < position[1]['leonard']:
        raise ValueError('queue_sort: speed 16 does not put actor023_2 before leonard')


def check_growth(growth: dict) -> None:
    """0x40e870 draws only through rand(n) 0x458c80 inside itself (target level at 0x40e92c／0x40e938
    first), never through the damage wrappers: the global state moves, the damage state does not."""
    sites = growth.get('rand_sites', [])
    if growth.get('function') != f'{GROWTH:#x}' or growth.get('actor') != GROWTH_ACTOR:
        raise ValueError('growth: not the 0x40e870 run on actor023_2')
    if sites[:2] != GROWTH_TARGET_SITES or not all(GROWTH <= int(site, 16) < GROWTH_END for site in sites):
        raise ValueError(f'growth: rand(n) sites {sites} are not 0x40e92c／0x40e938 then 0x40e870-local')
    if growth['damage_wrappers'] or growth['damage_moved'] or not growth['global_moved']:
        raise ValueError('growth: 0x40e870 must move the global stream only')
    if growth['after']['level'] <= growth['before']['level'] and len(sites) > 2:
        raise ValueError('growth: per-level draws without a level gain')


def check_turn(turn: dict) -> None:
    if turn.get('format') != FORMAT or turn.get('battle') != f'{LEVEL:03d}' or not isinstance(turn.get('turn'), int):
        raise ValueError('turn header is not enemy_turn_v1 for battle 051')
    if set(turn['rng']) != set(STREAMS) or any(len(v) != 2 for v in turn['rng'].values()):
        raise ValueError('rng must name the global and damage start states')
    if turn['meta']['stop'] != 'player_control':
        raise ValueError(f'turn did not return control to the player: {turn["meta"]["stop"]}')
    if not turn['actions'] or len(turn['meta']['actions']) != len(turn['actions']):
        raise ValueError('actions and meta.actions differ')
    handoff = turn['meta'].get('handoff') or {}
    if list(handoff) != ['actor', 'draws', 'frames', 'hp'] or handoff['frames'][1] is None:
        raise ValueError(f'the player turn-end sequence (meta.handoff) is missing or did not finish: {handoff}')
    for action, meta in zip(turn['actions'], turn['meta']['actions']):
        if list(action) != ['actor', 'from', 'to', 'action', 'target', 'skill', 'draws']:
            raise ValueError(f'{action.get("actor")}: action keys {list(action)}')
        if action['action'] not in ACTIONS:
            raise ValueError(f'{action["actor"]}: unknown action {action["action"]}')
        if action['action'] != 'wait' and action['target'] is None:
            raise ValueError(f'{action["actor"]}: {action["action"]} without target')
        if action['action'] == 'wait' and action['target'] != meta['chase']:
            raise ValueError(f'{action["actor"]}: wait target is not the held pursuit target {meta["chase"]}')
        if action['action'] in ('magic', 'skill', 'item') and not action['skill']:
            raise ValueError(f'{action["actor"]}: {action["action"]} without skill id')
        for draw in action['draws']:
            if list(draw) != ['site', 'n', 'value', 'stream'] or draw['stream'] not in STREAMS:
                raise ValueError(f'{action["actor"]}: bad draw {draw}')
            if draw['n'] is not None and not 0 <= draw['value'] < max(draw['n'], 1):
                raise ValueError(f'{action["actor"]}: draw value {draw} outside its modulus')
        if action['action'] == 'attack' and not any(d['stream'] == 'damage' for d in action['draws']):
            raise ValueError(f'{action["actor"]}: attack without damage-stream draws')


def validate(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA:
        raise ValueError('packet identity (schema / exe_sha256) differs')
    if packet.get('save_sha256') != sha256(SAVE.read_bytes()):
        raise ValueError('tracked save sample changed since the packet was generated')
    if packet.get('seeds') != [[a, b] for a, b in SEEDS] or len(packet['turns']) != 1 + len(SEEDS):
        raise ValueError('turns must be the sample start plus every SEEDS start')
    check_queue_sort(packet.get('queue_sort', []))
    check_growth(packet.get('growth', {}))
    check_ablations(packet.get('ablations', []))
    for turn in packet['turns']:
        check_turn(turn)
    sample = packet['turns'][0]
    moves = {a['actor']: (a['from'], a['to']) for a in sample['actions']}
    for actor, move in REGRESSION.items():
        if list(moves.get(actor, ())) != list(move):
            raise ValueError(f'{actor}: sample move {moves.get(actor)} differs from recording {move}')
    if not any(a['action'] == 'attack' for a in sample['actions']):
        raise ValueError('sample turn has no attack')
    queue = [entry[0] for entry in packet['queue_sort'][0]['order']]
    lead = queue.index('leonard')
    if [a['actor'] for a in sample['actions']] != queue[lead + 1:] + queue[:lead]:
        raise ValueError('sample actors do not follow the 0x407340 queue (rest of round 1, round 2 up to leonard)')
    for turn, seed in zip(packet['turns'][1:], SEEDS):
        if turn['rng']['global'] != list(seed):
            raise ValueError(f'seeded turn start {turn["rng"]["global"]} is not {seed}')


def summary_line(packet: dict, executed_now: bool) -> str:
    turns = packet['turns']
    actions = sum(len(t['actions']) for t in turns)
    attacks = sum(a['action'] == 'attack' for t in turns for a in t['actions'])
    draws = sum(len(a['draws']) for t in turns for a in t['actions'])
    return (f'ENEMY_TURN_ORACLE_PASS turns={len(turns)} actions={actions} attacks={attacks} draws={draws} '
            f'regression={len(REGRESSION)}/{len(REGRESSION)} executed_now={executed_now}')


render = compact_json_text  # the packet / --out text (also _enemy_level's): one line per action's draw list


class EnemyTurnTask(PacketTask):
    """generate re-runs the original (needs hsl01.exe, hsl.pak and unicorn); check validates the
    tracked packet offline (format, sample regression moves, control returned to the player)."""
    name = 'enemy_turn'
    family = 'probe'
    packet = PACKET.relative_to(ROOT).as_posix()
    outputs = (packet,)
    inputs = (SAVE.relative_to(ROOT).as_posix(), BATTLE.relative_to(ROOT).as_posix(), TYPE_H.relative_to(ROOT).as_posix())
    scripts = ('tools/hsltools/probes/enemy_turn.py', 'tools/hsltools/native/battle_machine.py')
    replaces = ()

    def validate(self, packet: dict) -> None:
        validate(packet)

    def execute(self, ctx) -> dict:
        return execute_packet(ctx.original_exe)

    def summary(self, packet: dict, executed_now: bool) -> str:
        return summary_line(packet, executed_now)

    def generate(self, ctx) -> str:
        if not ctx.original_exe.exists():
            raise NotGeneratable(f'{self.name}: original EXE not found at {ctx.original_exe} (needs the documented hsl01.exe and unicorn)')
        packet = self.execute(ctx)
        self.validate(packet)
        target = ctx.root / self.packet
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(compact_json_text(packet) + '\n', encoding='utf-8')
        return self.summary(packet, True)


TASK = EnemyTurnTask()


def tasks() -> list[PacketTask]:
    return [TASK]


EDIT_FIELDS = tuple(LIVE_FIELDS) + ('cell', 'target', 'dead')


def parse_edit(text: str) -> tuple[str, str, object]:
    """ID.FIELD=VALUE: a live field (hp／max_hp／level／speed, integer), cell=X/Y, target=ID (or
    none) or dead=1. ID with or without the "actor" prefix."""
    target, value = text.split('=', 1)
    actor, field = target.rsplit('.', 1)
    if field not in EDIT_FIELDS:
        raise argparse.ArgumentTypeError(f'field {field!r} not in {list(EDIT_FIELDS)}')
    try:
        if field == 'cell':
            x, y = value.replace(',', '/').split('/')
            return actor, field, [int(x), int(y)]
        if field == 'target':
            return actor, field, None if value.lower() in ('', 'none', 'null', '0') else value
        return actor, field, int(value, 0)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f'{text}: {error}') from None


def edits_board(edits) -> dict:
    """--set edits as a board (apply_board): live fields raw, cell → units, target, dead."""
    board: dict = {}
    for actor, field, value in edits:
        if field == 'cell':
            board.setdefault('units', {})[actor] = value
        elif field == 'target':
            board.setdefault('targets', {})[actor] = value
        elif field == 'dead':
            if value:
                board.setdefault('dead', []).append(actor)
        else:
            board.setdefault('live', {}).setdefault(actor, {})[field] = value
    return board


def unit_id(short: str) -> str:
    """The remake exporter's id rule: "021_3" → "actor021_3"; leonard／named ids unchanged."""
    return short if short.startswith('actor') or short == 'leonard' or not short[:1].isdigit() else 'actor' + short


def killed(names: dict[int, str], board: dict) -> set[int]:
    """The objects a board's dead list removes (apply_board runs their death clean-up)."""
    ids = {name: obj for obj, name in names.items()}
    return {ids[unit_id(str(key))] for key in board.get('dead', []) if unit_id(str(key)) in ids}


BOARD_KEYS = ('growth', 'turn', 'speed', 'units', 'hp', 'dead', 'targets', 'resume_after', 'live', 'level', 'max_hp')


def apply_board(machine, names: dict[int, str], board: dict, current: int = 0) -> list[str]:
    """Write a board (the recorded_round_boards.json form: speed／hp／units／targets／dead／turn,
    plus live raw fields) into the original's own memory — INJECTION names each write. current is
    the queue's current object (a current actor cannot be killed). growth／resume_after are the
    caller's (_enemy_level). Returns the applied writes."""
    ids = {name: obj for obj, name in names.items()}
    applied: list[str] = []

    def obj_of(key: str) -> int:
        name = unit_id(str(key))
        if name not in ids:
            raise ValueError(f'board unit {key!r} is not on this level ({sorted(ids)})')
        return ids[name]

    def record(obj: int) -> int:
        return machine.get(LIVE_TABLE) + LIVE_SIZE * machine.get(obj + OBJ_LIVE)
    unknown = set(board) - set(BOARD_KEYS)
    if unknown:
        raise ValueError(f'board keys not understood: {sorted(unknown)}')
    for field in ('speed', 'level', 'max_hp'):
        for key, value in board.get(field, {}).items():
            machine.put(record(obj_of(key)) + LIVE_FIELDS[field], int(value))
            applied.append(f'{unit_id(key)}.{field}={int(value)}')
    for key, value in board.get('hp', {}).items():
        at = record(obj_of(key))
        hp = min(int(value), machine.geti(at + LIVE_FIELDS['max_hp']))
        machine.put(at + LIVE_FIELDS['hp'], hp)
        applied.append(f'{unit_id(key)}.hp={hp}')
    for key, fields in board.get('live', {}).items():
        for field, value in fields.items():
            machine.put(record(obj_of(key)) + LIVE_FIELDS[field], int(value))
            applied.append(f'{unit_id(key)}.{field}={int(value)} (raw)')
    for key, value in board.get('targets', {}).items():
        target = obj_of(value) if value is not None else 0
        machine.put16(obj_of(key) + OBJ_HELD, machine.get16(target + OBJ_SLOT) + 1 if target else 0)
        applied.append(f'{unit_id(key)}.target={unit_id(value) if value is not None else None}')
    moves = [(obj_of(key), [int(v) for v in cell]) for key, cell in board.get('units', {}).items()]
    masks = {obj: machine.call_nested(SIDE_MASK, obj) for obj, _ in moves}
    for obj, _ in moves:
        if machine.call_nested(SAME_CELL, obj) == 0:
            machine.call_nested(OCCUPY_CLEAR, obj, masks[obj])
    for obj, (x, y) in moves:
        machine.put(obj + OBJ_X, (x << 5) | (machine.get(obj + OBJ_X) & 31))
        machine.put(obj + OBJ_Y, (y << 5) | (machine.get(obj + OBJ_Y) & 31))
    for obj, (x, y) in moves:
        machine.call_nested(OCCUPY_SET, obj, masks[obj])
        applied.append(f'{names[obj]}.cell={x}/{y}')
    for key in board.get('dead', []):
        obj = obj_of(key)
        if obj == current:
            raise ValueError(f'{key}: the current actor cannot be injected dead')
        at = record(obj)
        machine.put(obj + OBJ_FLAGS, machine.get(obj + OBJ_FLAGS) | DEAD_FLAG)
        machine.put(obj + OBJ_MODE, 0)
        machine.mu.mem_write(DEAD_TABLE + machine.get16(obj + OBJ_UNIT), bytes([1]))
        machine.put(at + LIVE_FIELDS['hp'], 0)
        side = PLAYER_SIDE if machine.get(obj + 0x64) == PLAYER_PROCESS else machine.call_nested(SIDE_MASK, obj)
        machine.call_nested(OCCUPY_CLEAR, obj, side)
        machine.call_nested(UNREGISTER, obj)
        machine.call_nested(TEMPLATE_CLEAR, machine.get(obj + OBJ_LIVE))
        machine.call_nested(OBJECT_UNLINK, obj)
        applied.append(f'{names[obj]}.dead')
    if 'turn' in board:
        machine.put16(ROUND, int(board['turn']))
        applied.append(f'round={int(board["turn"])}')
    return applied


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Run the original enemy turn from a battle save and print enemy_turn_v1 JSON.')
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    parser.add_argument('--save', type=Path, default=SAVE, help='level-51 HSLBAT battle save (default: tracked first-control sample)')
    parser.add_argument('--seed', nargs=2, metavar=('S1', 'S2'), help='global RNG start 0x4795d4 0x4795d8 (default: as loaded)')
    parser.add_argument('--damage-seed', nargs=2, metavar=('D1', 'D2'), help='damage RNG start 0x4c3044 0x4c3040 (default: from the save)')
    parser.add_argument('--set', dest='edits', action='append', type=parse_edit, default=[], metavar='ACTOR.FIELD=VALUE',
                        help=f'write a field after the load ({", ".join(EDIT_FIELDS)}; cell=X/Y, target=ID|none, dead=1; see INJECTION)')
    parser.add_argument('--frames', type=int, default=FRAME_LIMIT)
    parser.add_argument('--ablate', action='append', choices=sorted(ABLATIONS), default=[],
                        help='drop a frame shim or add the spike stub (exit status 1 unless control returns)')
    parser.add_argument('--no-cache', action='store_true', help='rebuild the loaded state instead of using ignored/native_cache')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--lines', type=Path, metavar='FILE',
                        help='also write one enemy_turn_v1 line per round, draws named by SITE_MAP (_enemy_level.py compare input)')
    parser.add_argument('--bare-lines', type=Path, metavar='FILE',
                        help='the same lines with draws emptied (export_enemy_turns.gd --expect／--search input)')
    parser.add_argument('--brief', action='store_true', help='also print one line per action to stderr')
    args = parser.parse_args(argv)
    turn = run_turn(args.exe, args.save.read_bytes(), parse_seed(args.seed), parse_seed(args.damage_seed), args.edits,
                    args.frames, not args.no_cache, tuple(args.ablate))
    text = compact_json_text(turn)
    if args.out:
        args.out.write_text(text + '\n', encoding='utf-8')
    else:
        print(text)
    if args.lines:
        write_lines(args.lines, turn, SITE_MAP)
    if args.bare_lines:
        write_lines(args.bare_lines, turn, None)
    if args.brief or args.out:
        for action in turn['actions']:
            print(f'{action["actor"]} {action["from"]}->{action["to"]} {action["action"]} {action["target"]} '
                  f'skill={action["skill"]} draws={len(action["draws"])}', file=sys.stderr)
        meta = turn['meta']
        print(f'stop={meta["stop"]} next={meta["next_actor"]} frames={meta["frames"]} current={meta["current"]} '
              f'transition_pending={meta["transition_pending"]}', file=sys.stderr)
    return 0 if turn['meta']['stop'] == 'player_control' else 1


if __name__ == '__main__':
    raise SystemExit(main())
