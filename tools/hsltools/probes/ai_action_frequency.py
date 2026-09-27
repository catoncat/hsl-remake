"""AI action frequency: how often each kind of AI action happens per level, the original referee
against the remake — registry task `ai_action_frequency` (lane AIFREQ; measure only, no fixes).

Why: a rule written correctly whose branch is never reached (level 51／52 knights never healing the
wounded player: the rule was right, the knights carried no potion — ALLYHEAL) only shows up in play.
Counting every AI action by kind on both sides, per level, finds kinds one side does and the other
never does, whatever row-by-row agreement says.

Inputs (untracked; `hsl generate ai_action_frequency` reads them, NotGeneratable when absent):

  ignored/ai_action_frequency/original/L051_s1_original.jsonl (+ _meta.json)
      tools/hsltools/probes/_enemy_level.py batch --levels <LEVELS> --seeds 1,2,3 --turns 3 --align --mix 20
      --no-remake --out ignored/ai_action_frequency/original — the original entered by 0x42da60, halted at
      the first 0x407340, growth false (births without level dispersion), the remake's opening cells written
      in (--align writes cells only), global words (s, s) and damage words (s + 7777) each stepped 20 times
      (--mix: every seed its own damage stream), its own frame loop run 3 rounds with every player waiting
      (original_enemy_turn.md §11)
  ignored/ai_action_frequency/remake/seeds_1-3.jsonl, seeds_4-32.jsonl
      `python3 tools/hsltools/probes/ai_action_frequency.py export --seeds 1-3` — per level and seed the
      export_enemy_turns.gd run the referee's batch makes (--seed s --global-seed s, {"growth": false}: the
      opening births with adjust_level [0, 0] as the referee's growth false, lane LETHALITY), many runs
      per Godot process (tests/diagnostics/export_ai_action_frequency.gd); seeds 4-32 only for the levels
      a one-sided row names (`--flagged`), as the remake's wider distribution

Both sides are the same enemy_turn_v1 action rows (actor, from, to, action, target, skill), so one
classifier maps both (KINDS). Sides come from the scenario's battle_actor_role (player_controlled／
friendly_ai = our camp, enemy_ai = enemy camp); a name only the original has (obj0x…, slotNN_codeNNN)
has no side. Positions for chase／flee: the scenario's cells, each actor's own `from`／`to` as it acts.
The remake's action_twice pair (two rows of one queue slot) is merged the way the original probe
records one queue slot (BATCH2: from of the first, to of the second, action／target of the last non-wait);
its paralysis_skip is the referee's in-place wait and its player_controlled rows are dropped (REMAKE_AS_REFEREE).

Rows: per level × kind, the count summed over the runs each side has (seeds 1..3; a referee run that is
missing is left out, so the sides may differ in runs) and the number of runs with at least one; the
remake's extra seeds (4..32, levels named by hand) give the share of its runs doing the kind. A level
whose referee run stopped at the frame limit (ROUND_FRAMES × rounds) is compared, both sides, on the
rounds before the cut one. Flagged: kinds the original does on a level and the remake never does
(orig_only), the reverse (remake_only), then both > 0 whose shares of their side's actions are over
twice apart with the larger count ≥ RATIO_FLOOR (ratio). Each flagged row carries the exact two-rate
test p (rate_test: given both counts' sum, the original's count is Binomial with the sides' action
totals as weights); p ≥ ALPHA is attributed to sampling automatically, otherwise the row needs an
attribution — the injection／probe gap levels of BATCH126／BATCH2 first, then NOTES (missing input／
missing branch／random structure／mapping); a flagged row without one fails generate. The kind table
pools the levels both sides ran equally often and tests the pooled counts the same way.

PASS: AI_ACTION_FREQUENCY_CHECK_PASS levels=N runs_original=N runs_remake=N actions_original=N
actions_remake=N kinds=N orig_only=N remake_only=N ratio=N
"""
from __future__ import annotations

import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/ai_action_frequency.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ROOT  # noqa: E402
from hsltools.probes._enemy_level import MENU_EVENTS  # noqa: E402
from hsltools.registry import CheckFailed, Context, NotGeneratable, Task  # noqa: E402

REPORT_JSON = 'content/generated/hsl/development/ai_action_frequency.json'
REPORT_MD = 'content/generated/hsl/development/ai_action_frequency.md'
SCHEMA = 'hsl_ai_action_frequency.v1'
RAW = ROOT / 'ignored/ai_action_frequency'
MAIN_SEEDS = (1, 2, 3)
WIDE_SEEDS = tuple(range(4, 33))
TURNS = 3
ALPHA = 0.01      # a flagged row with the exact two-rate test p ≥ ALPHA is within sampling (many rows are tested)
RATIO_FLOOR = 4   # a ratio row needs the larger side's count ≥ this (1 vs 3 is noise at a few runs)
EXPORTER = 'res://tests/diagnostics/export_ai_action_frequency.gd'
OUR_ROLES = ('player_controlled', 'friendly_ai')

# The shared dictionary: key → label. Order is the report's order.
KINDS = {
    'attack': '普攻',
    'magic_offense': '法术进攻',
    'magic_support': '法术辅助',
    'skill_offense': '绝技进攻',
    'skill_support': '绝技辅助',
    'item_ally': '给药救人',
    'item_self': '自救用药',
    'item_enemy': '对敌用道具',
    'item_unresolved': '用药（原版目标未解析）',
    'call': '呼叫',
    'other': '其他',
    'idle': '待机（不动无目标）',
    'hold': '守候（不动持目标）',
    'chase': '追击（持目标移动、直线距离不变大）',
    'flee': '逃跑（持目标移动、直线距离变大）',
    'wander': '移动无目标',
}

# The remake rows read the way the referee records the same queue slot (lane AIFREQ2): a paralysis_skip
# ('other') is the in-place wait the referee writes (with the held target), and a player_controlled
# unit's row (a paralysed player the remake runs through the AI path, e.g. 564 緹娜) is dropped — the
# referee records no player turn. Ship hulls actor101_x (enemy candidates since lane ACTORS100) are in the
# original's queue too — 巴瀚納海峽／亞雷比斯 (LEVEL012／026): 26 hulls in 026's round-1 queue, each passing
# the handoff 0x407510 — but each turn ends inside one frame, so the frame-sampling probe never sees one
# (like level 37's guard067, one hull's turn shows for a frame); hull rows are dropped on both sides. The referee's AI item target is read
# through 0x409e40's live index (enemy_turn.EnemyTurn.item_target), so an item row names the unit it healed.
REMAKE_AS_REFEREE = True
ZERO_FRAME_PREFIX = 'actor101_'

# Levels whose rows the referee does not see the way the remake exports them (BATCH126／BATCH2
# 注入缺口与探针口径, oracle_batch/README.md): a flagged row there is attributed to that first.
INJECTION_GAPS = {
    18: '原版停点后开场事件又挪了单位（开局格不同，同种子上下文不可比）',
    53: 'enemy023_2／023_3 在原版停点之后才由事件装上（原版名单里是 obj0x…）',
}
PROBE_GAPS = {
    12: '船壳 actor101_x 的回合在原版同一帧内走完（零帧回合），探针看不到；两边船壳行都按 REMAKE_AS_REFEREE 去掉',
    26: '船壳 actor101_x 的回合在原版多在同一帧内走完（零帧回合），探针只看到 101_1（每轮 1 行待机）；两边船壳行都按 REMAKE_AS_REFEREE 去掉',
    37: 'guard067_x 的回合在原版同一帧内走完，探针按帧看队列看不到（零帧回合）',
    73: '原版首轮内战斗结束（出关），探针只记半行',
    75: '原版队列刚轮到 049_10 战斗就结束，探针只记开头',
}

# Attribution per flagged row, key 'LEVEL:kind:direction' (direction orig_only／remake_only／ratio),
# or 'LEVEL:*:direction'／'*:kind:direction' for a whole level／kind. Category is the first word:
# 缺输入／缺分支／随机结构差异／映射差异. Filled from the measured rows (see the report's 做法). Lane AIFREQ2's
# rerun (new 口径): each row is within sampling on its own, but the pooled 法术进攻 is not (p < 0.01) and two
# clusters make it up. Lane AIMAGIC reran both at 16 seeds: within sampling, no rule difference.
_AIR01 = ('随机结构差异（lane AIMAGIC 16 种子复跑，不改）：041_1／041_2 贴着雷特时两边走同一条法术位——'
          '0x43fe0c 的 0x40c570 掷 rand(99)+1 ≤ ai_att_magic 26 才进法术，风刃 use_ratio 90 也过了就原地放 magicAIR01，否则普攻；'
          '16 种子×3 回合原版 10 次、重制 16 次（p=0.33）；原版 40 种子第 2 回合 80 次行动掷中 16 次、放出 13 次；'
          '种子 13 两边 041_1／041_2 的行逐项相同；AIFREQ2 的 3 种子 0 对 5 是抽样')
_MIND = ('随机结构差异（lane AIMAGIC 16 种子复跑，不改）：049_x 对玩家放 magicMIND02／03 两边都有——'
         '16 种子×3 回合 033／561／563／564 原版 5／4／3／5 次、重制 9／5／4／4 次（合计 17 对 22，p=0.52），'
         '四关法术进攻合计 25 对 33（p=0.36）；033 种子 9 第 2 回合 049_3 在 [11,8] 对 hanks 放咒靈縛剎、049_2 在 [10,11] 对 hanks 放幻火，两边相同；'
         'AIFREQ2 的 3 种子 0 对 7 是抽样')
NOTES: dict[str, str] = {
    '19:magic_offense:remake_only': _AIR01,
    '904:magic_offense:remake_only': _AIR01,
    '33:magic_offense:remake_only': _MIND,
    '561:magic_offense:remake_only': _MIND,
    '563:magic_offense:remake_only': _MIND,
    '564:magic_offense:remake_only': _MIND,
}


# ---- battle names (docs/BATTLE_NAMES.md: 「玩家第 N 场 · 场景名（LEVEL0xx）」)

def scenario_path(level: int) -> Path:
    entry = json.loads((ROOT / 'content/battles/campaign.json').read_text(encoding='utf-8'))['battles'].get(str(level), {})
    scenario = str(entry.get('scenario', ''))
    return ROOT / scenario.removeprefix('res://') if scenario else ROOT / f'content/battles/battle_{level:03d}.json'


def battle_arg(level: int) -> str:
    path = scenario_path(level)
    return f'{level:03d}' if path.name == f'battle_{level:03d}.json' else 'res://' + path.relative_to(ROOT).as_posix()


def level_of(battle: str) -> int:
    """battle_arg's inverse: '051' or a campaign res:// scenario path."""
    if battle.isdigit():
        return int(battle)
    campaign = json.loads((ROOT / 'content/battles/campaign.json').read_text(encoding='utf-8'))['battles']
    return next(int(level) for level, entry in campaign.items() if entry.get('scenario') == battle)


def battle_names() -> dict[int, str]:
    order: dict[int, tuple[str, str]] = {}
    for line in (ROOT / 'docs/BATTLE_NAMES.md').read_text(encoding='utf-8').splitlines():
        match = re.match(r'\| (第 \d+ 场) \| ([^|]+?) \| LEVEL(\d+) \|', line)
        if match:
            order[int(match.group(3))] = (match.group(1), match.group(2))
    names: dict[int, str] = {}
    for path in sorted((ROOT / 'content/battles').glob('battle_*.json')):
        try:
            level = int(path.stem.removeprefix('battle_'))
        except ValueError:
            continue
        names[level] = str(json.loads(path.read_text(encoding='utf-8')).get('title', '')).replace('（開場預覽）', '').strip()
    for level in (1, 2):
        names[level] = str(json.loads(scenario_path(level).read_text(encoding='utf-8')).get('title', names.get(level, ''))).replace('（開場預覽）', '').strip()
    for level, (nth, title) in order.items():
        names[level] = f'玩家{nth} · {title}'
    return {level: f'{title}（LEVEL{level:03d}）' for level, title in names.items()}


# ---- classification

def scenario_units(level: int) -> dict[str, dict]:
    units = json.loads(scenario_path(level).read_text(encoding='utf-8'))['playable_units']
    return {str(u['id']): {'side': 'our' if u.get('battle_actor_role') in OUR_ROLES else 'enemy', 'cell': list(u.get('coord', [0, 0])),
                           'role': str(u.get('battle_actor_role', ''))}
            for u in units}


def merge_twice(actions: list[dict]) -> list[dict]:
    """The remake's action_twice pair → one row per queue slot, as the original probe records it."""
    out: list[dict] = []
    for action in actions:
        if out and out[-1]['actor'] == action['actor']:
            first = out[-1]
            last = action if action['action'] != 'wait' else (first if first['action'] != 'wait' else action)
            out[-1] = dict(first, to=action['to'], action=last['action'], target=last['target'], skill=last['skill'])
            continue
        out.append(dict(action))
    return out


def distance(a, b) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def classify(action: dict, units: dict[str, dict], cells: dict[str, list]) -> str:
    actor, target, verb = action['actor'], action.get('target') or None, action['action']
    moved = action.get('to') is not None and list(action['to']) != list(action['from'])
    if verb == 'attack':
        return 'attack'
    if verb in ('magic', 'skill', 'item'):
        mine = units.get(actor, {}).get('side', 'enemy')
        theirs = units.get(target, {}).get('side')
        same = target == actor or (theirs is not None and theirs == mine)
        if verb == 'item' and str(target).startswith('obj0x'):
            return "item_unresolved"   # the referee could not name the target (none since EnemyTurn.item_target)
        if verb == 'item':
            return 'item_self' if target == actor else ('item_ally' if same else 'item_enemy')
        return f'{verb}_{"support" if same else "offense"}'
    if verb in ('call', 'other'):
        return verb
    if not moved:
        return 'hold' if target else 'idle'
    if not target:
        return 'wander'
    where = cells.get(target)
    if where is not None and distance(action['to'], where) > distance(action['from'], where):
        return 'flee'
    return 'chase'


def count_run(turns: list[dict], units: dict[str, dict], merge: bool, cap: int | None = None) -> Counter:
    cells = {name: list(unit['cell']) for name, unit in units.items()}
    counts: Counter = Counter()
    first = turns[0]['turn'] if turns else 0
    for turn in turns:
        if cap is not None and turn['turn'] - first >= cap:
            break
        actions = [a for a in (merge_twice(turn['actions']) if merge else turn['actions']) if not a['actor'].startswith(ZERO_FRAME_PREFIX)]
        if merge:   # the remake side read as the referee records it (REMAKE_AS_REFEREE)
            actions = [dict(a, action='wait', to=a['from']) if a['action'] == 'other' else a for a in actions
                       if units.get(a['actor'], {}).get('role') != 'player_controlled']
        for action in actions:
            cells[action['actor']] = list(action['from'])
            counts[classify(action, units, cells)] += 1
            if action.get('to') is not None:
                cells[action['actor']] = list(action['to'])
    return counts


# ---- loading

def load_original(levels: list[int]) -> tuple[dict, list[dict], dict]:
    """{(level, seed): turns}, skipped [{level, seed, reason}], {level: round cap}: a run the referee stopped at
    its frame limit (ROUND_FRAMES × rounds) has a cut last round; that level is compared on the rounds before it.
    EMULATOR_STOP: a run the emulator stopped (unmapped 0x30000000 at 0x4603ca: a resource loaded by id mid-round,
    _enemy_level.EmptyFiles) is cut the same way; one stopped inside round 1 is left out, not its level."""
    runs: dict = {}
    caps: dict = {}
    skipped: list[dict] = []
    for level in levels:
        for seed in MAIN_SEEDS:
            path = RAW / 'original' / f'L{level:03d}_s{seed}_original.jsonl'
            if not path.with_name(path.name.replace(".jsonl", "_meta.json")).exists():   # meta is written last
                skipped.append({'level': level, 'seed': seed, 'side': 'original', 'reason': 'no referee output (the 3-round batch rows that recorded a reason say KeyError: 0)'})
                continue
            turns = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]
            meta = json.loads(path.with_name(path.name.replace('.jsonl', '_meta.json')).read_text(encoding='utf-8'))
            if str(meta['stop']).startswith('emulator') and len(turns) <= 1:   # stopped inside round 1: nothing whole
                skipped.append({'level': level, 'seed': seed, 'side': 'original', 'reason': f'referee {meta["stop"]} inside round 1 (EMULATOR_STOP)'})
                continue
            runs[(level, seed)] = turns
            if meta['stop'] == 'frame_limit' or str(meta['stop']).startswith('emulator'):
                caps[level] = min(caps.get(level, TURNS), len(turns) - 1)
    return runs, skipped, caps


def load_remake() -> tuple[dict, list[dict]]:
    runs: dict = {}
    skipped: list[dict] = []
    for path in sorted((RAW / 'remake').glob('*.jsonl')):
        for line in path.read_text(encoding='utf-8').splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:   # the tail of a file an exporter is still writing
                continue
            level = level_of(str(row['battle']))
            if row['error']:
                skipped.append({'level': level, 'seed': row['seed'], 'side': 'remake', 'reason': row['error']})
            runs[(level, int(row['seed']))] = row['turns']
    return runs, skipped


def default_levels() -> list[int]:
    """The BATCH126／BATCH2 levels the referee enters (oracle_batch_ai_prio.json, without its tool errors: level 200)."""
    batch = json.loads((ROOT / 'docs/evidence_packets/runtime_observations/oracle_batch/oracle_batch_ai_prio.json').read_text(encoding='utf-8'))
    return sorted(int(row['level']) for row in batch['levels'] if not row.get('tool_error'))


# ---- report

def build(levels: list[int] | None = None) -> dict:
    if not (RAW / 'original').is_dir() or not (RAW / 'remake').is_dir():
        raise NotGeneratable(f'{RAW.relative_to(ROOT)}/original and /remake are absent (see the module docstring for the two exports)')
    levels = levels or default_levels()
    names = battle_names()
    original, skipped, caps = load_original(levels)
    remake, remake_skipped = load_remake()
    skipped += [row for row in remake_skipped if row['level'] in levels]
    rows: list[dict] = []
    totals = Counter()
    per_level: list[dict] = []
    for level in levels:
        units = scenario_units(level)
        cap = caps.get(level)
        if cap == 0:
            skipped.append({'level': level, 'seed': 0, 'side': 'original', 'reason': 'referee frame limit inside round 1'})
            continue
        o_counts = {seed: count_run(original[(level, seed)], units, False, cap) for seed in MAIN_SEEDS if (level, seed) in original}
        r_counts = {seed: count_run(remake[(level, seed)], units, True, cap) for seed in MAIN_SEEDS if (level, seed) in remake}
        wide = {seed: count_run(remake[(level, seed)], units, True, cap) for seed in WIDE_SEEDS if (level, seed) in remake}
        if not o_counts or not r_counts:
            continue
        totals['runs_original'] += len(o_counts)
        totals['runs_remake'] += len(r_counts)
        o_sum, r_sum = sum(o_counts.values(), Counter()), sum(r_counts.values(), Counter())
        totals['actions_original'] += sum(o_sum.values())
        totals['actions_remake'] += sum(r_sum.values())
        runs = [len(o_counts), len(r_counts)]
        per_level.append({'level': level, 'name': names.get(level, f'LEVEL{level:03d}'), 'original': dict(o_sum), 'remake': dict(r_sum),
                          'actions': [sum(o_sum.values()), sum(r_sum.values())], 'runs': runs, 'round_cap': cap})
        for kind in KINDS:
            o, r = o_sum.get(kind, 0), r_sum.get(kind, 0)
            direction = flag(o, r, [sum(o_sum.values()), sum(r_sum.values())])
            if direction is None:
                continue
            all32 = {**r_counts, **wide}
            r_share = sum(1 for c in r_counts.values() if c.get(kind))
            rows.append({'level': level, 'kind': kind, 'direction': direction, 'original': o, 'remake': r, 'runs': runs,
                         'original_seeds': sum(1 for c in o_counts.values() if c.get(kind)), 'remake_seeds': r_share,
                         'remake_wide': [sum(1 for c in all32.values() if c.get(kind)), len(all32)] if wide else None,
                         'actions': [sum(o_sum.values()), sum(r_sum.values())],
                         'p': rate_test(o, r, sum(o_sum.values()), sum(r_sum.values()))})
            rows[-1]['attribution'] = attribution(level, kind, direction, rows[-1]['p'])
    order = {'orig_only': 0, 'remake_only': 1, 'ratio': 2}
    rows.sort(key=lambda r: (order[r['direction']], r['p'] >= ALPHA, list(KINDS).index(r['kind']), -max(r['original'], r['remake']), r['level']))
    kind_totals = []
    for kind, label in KINDS.items():
        o = sum(level['original'].get(kind, 0) for level in per_level)
        r = sum(level['remake'].get(kind, 0) for level in per_level)
        # Pooled test over the levels both sides ran the same number of times (level mix kept equal).
        even = [level for level in per_level if level['runs'][0] == level['runs'][1]]
        eo, er = sum(level['original'].get(kind, 0) for level in even), sum(level['remake'].get(kind, 0) for level in even)
        pooled = [eo, er, sum(level['actions'][0] for level in even), sum(level['actions'][1] for level in even), len(even)]
        kind_totals.append({'kind': kind, 'label': label, 'original': o, 'remake': r, 'even_levels': pooled,
                            'p': stratified_test([(level['original'].get(kind, 0), level['remake'].get(kind, 0), *level['actions']) for level in even]),
                            'orig_only': sum(1 for row in rows if row['kind'] == kind and row['direction'] == 'orig_only'),
                            'remake_only': sum(1 for row in rows if row['kind'] == kind and row['direction'] == 'remake_only'),
                            'ratio': sum(1 for row in rows if row['kind'] == kind and row['direction'] == 'ratio')})
    t = dict(levels=len(per_level), runs_original=totals['runs_original'], runs_remake=totals['runs_remake'],
             actions_original=totals['actions_original'], actions_remake=totals['actions_remake'], kinds=len(KINDS),
             orig_only=sum(1 for r in rows if r['direction'] == 'orig_only'),
             remake_only=sum(1 for r in rows if r['direction'] == 'remake_only'),
             ratio=sum(1 for r in rows if r['direction'] == 'ratio'))
    return {'schema': SCHEMA, 'turns': TURNS, 'seeds': list(MAIN_SEEDS), 'ratio_floor': RATIO_FLOOR, 'kinds': KINDS,
            'totals': t, 'kind_totals': kind_totals, 'rows': rows, 'levels': per_level, 'skipped': skipped}


def flag(o: int, r: int, actions: list[int]) -> str | None:
    """orig_only／remake_only／ratio (shares of each side's actions over twice apart, larger count ≥ RATIO_FLOOR)
    or None. Shares, not per-run counts: a battle that ends earlier on one side has fewer actions of every kind."""
    if o and not r:
        return 'orig_only'
    if r and not o:
        return 'remake_only'
    if o and r and max(o, r) >= RATIO_FLOOR:
        a, b = o / actions[0], r / actions[1]
        if max(a, b) > 2 * min(a, b):
            return 'ratio'
    return None


def rate_test(o: int, r: int, total_o: int, total_r: int) -> float:
    """Exact conditional test of equal rates: given o + r events, o ~ Binomial(o + r, total_o / (total_o + total_r));
    two-sided p (sum of outcomes no likelier than the observed one), rounded to 4 significant digits."""
    n, q = o + r, total_o / (total_o + total_r)
    def log_pmf(k: int) -> float:
        return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1) + k * math.log(q) + (n - k) * math.log1p(-q)
    observed = log_pmf(o)
    p = sum(math.exp(log_pmf(k)) for k in range(n + 1) if log_pmf(k) <= observed + 1e-9)
    return float(f'{min(p, 1.0):.4g}')


def stratified_test(strata: list[tuple[int, int, int, int]]) -> float:
    """Pooled over levels without letting one level's action volume stand for all: per level the original's expected
    share of the kind's o + r events is its share of the level's actions; two-sided normal p of the summed
    difference (observed − expected) over its binomial variance, rounded to 4 significant digits."""
    diff = var = 0.0
    for o, r, total_o, total_r in strata:
        if not (o + r) or not (total_o and total_r):
            continue
        q = total_o / (total_o + total_r)
        diff += o - (o + r) * q
        var += (o + r) * q * (1 - q)
    if var <= 0:
        return 1.0
    return float(f'{math.erfc(abs(diff) / math.sqrt(2 * var)):.4g}')


def attribution(level: int, kind: str, direction: str, p: float) -> str:
    for key in (f'{level}:{kind}:{direction}', f'{level}:*:{direction}', f'{level}:{kind}:*', f'*:{kind}:{direction}'):
        if key in NOTES:
            return NOTES[key]
    if level in INJECTION_GAPS:
        return f'缺输入：注入缺口关——{INJECTION_GAPS[level]}'
    if level in PROBE_GAPS:
        return f'映射差异：探针口径——{PROBE_GAPS[level]}'
    if p >= ALPHA:
        return f'随机结构差异：在抽样误差内（精确检验 p={p:g} ≥ {ALPHA:g}），本批样本分不出两边'
    return ''


def render_json(report: dict) -> str:
    head = {k: v for k, v in report.items() if k not in ('rows', 'levels', 'skipped')}
    lines = ['{'] + [f'  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)},' for k, v in head.items()]
    for key in ('rows', 'levels', 'skipped'):
        lines.append(f'  {json.dumps(key)}: [')
        items = report[key]
        lines += [f'    {json.dumps(item, ensure_ascii=False)}' + (',' if i < len(items) - 1 else '') for i, item in enumerate(items)]
        lines.append('  ]' + (',' if key != 'skipped' else ''))
    return '\n'.join(lines + ['}']) + '\n'


def _seeds(row: dict) -> str:
    wide = f'；重制扩种子 {row["remake_wide"][0]}/{row["remake_wide"][1]}' if row['remake_wide'] else ''
    return f'{row["original_seeds"]}/{row["runs"][0]} · {row["remake_seeds"]}/{row["runs"][1]}{wide}'


def render_md(report: dict) -> str:
    t = report['totals']
    names = {level['level']: level['name'] for level in report['levels']}
    lines = ['# AI 行动种类频率对拍（原版裁判 vs 重制）', '',
             f'_由 `python3 tools/hsl.py generate ai_action_frequency` 从 `{REPORT_JSON}` 生成，勿手改。_', '',
             f'- 关卡 {t["levels"]}；每关首 {report["turns"]} 回合（从首个有人行动的回合起算），玩家全部待机；种子 {"、".join(map(str, report["seeds"]))}，两边同数种子，比分布不比逐次；原版 `--mix 20`（每种子各自的全局流与伤害流），两边都跑无散布开场出生（growth false）',
             f'- 原版 {t["runs_original"]} 局 {t["actions_original"]} 次行动；重制 {t["runs_remake"]} 局 {t["actions_remake"]} 次行动（action_twice 两行并一行）',
             f'- 差异：原版有、重制为 0 {t["orig_only"]} 条；重制有、原版为 0 {t["remake_only"]} 条；两边都有、占本方行动的比例差超 2 倍（大者 ≥ {report["ratio_floor"]} 次）{t["ratio"]} 条',
             f'- p：两边该种类次数的精确检验（给定两边合计次数，原版一侧服从按两边行动总数分配的二项分布，双侧）；p ≥ {ALPHA:g} 的行在抽样误差内，归「随机结构差异」；各表先列 p < {ALPHA:g} 的行',
             '- 种子列：「原版有该种类的局数/原版局数 · 重制有该种类的局数/重制局数」；标了「扩种子」的，是重制把种子加到 1..N 后有该种类的局数', '',
             '## 种类总表', '', '「同局数关合计」只合计两边局数相同的关（关卡构成一致）；合计 p 按关分层（每关按两边行动数分配期望，差值合计的正态检验），不让一关的行动量代表全部。', '',
             '| 种类 | 原版次数 | 重制次数 | 同局数关合计：原版 · 重制（行动 原版 · 重制，关数） | 合计 p | 原版有重制 0（关） | 重制有原版 0（关） | 超 2 倍（关） |',
             '|---|---:|---:|---|---:|---:|---:|---:|']
    for row in report['kind_totals']:
        e = row['even_levels']
        lines.append(f'| {row["label"]} | {row["original"]} | {row["remake"]} | {e[0]} · {e[1]}（{e[2]} · {e[3]}，{e[4]} 关） | {row["p"]:g} | '
                     f'{row["orig_only"]} | {row["remake_only"]} | {row["ratio"]} |')
    titles = {'orig_only': '原版有、重制为 0', 'remake_only': '重制有、原版为 0', 'ratio': '次数比例差超过 2 倍'}
    for direction, title in titles.items():
        chosen = [r for r in report['rows'] if r['direction'] == direction]
        lines += ['', f'## {title}（{len(chosen)} 条）', '', '| 种类 | 原版次数 | 重制次数 | 关卡 | 局数 | 两边行动总数 | p | 归因 |', '|---|---:|---:|---|---|---|---:|---|']
        for row in chosen:
            lines.append(f'| {report["kinds"][row["kind"]]} | {row["original"]} | {row["remake"]} | {names.get(row["level"], row["level"])} | '
                         f'{_seeds(row)} | {row["actions"][0]} · {row["actions"][1]} | {row["p"]:g} | {row["attribution"]} |')
    if report['skipped']:
        groups: dict = defaultdict(list)
        for s in report['skipped']:
            groups[(s['side'], s['seed'], s['reason'])].append(s['level'])
        lines += ['', '## 未对拍的局', ''] + [f'- {side} 种子 {seed}：{reason}（{len(levels)} 关：{"、".join(map(str, levels))}）'
                                               for (side, seed, reason), levels in sorted(groups.items())]
    return '\n'.join(lines) + '\n'


def summary(report: dict) -> str:
    t = report['totals']
    return (f'AI_ACTION_FREQUENCY_CHECK_PASS levels={t["levels"]} runs_original={t["runs_original"]} runs_remake={t["runs_remake"]} '
            f'actions_original={t["actions_original"]} actions_remake={t["actions_remake"]} kinds={t["kinds"]} '
            f'orig_only={t["orig_only"]} remake_only={t["remake_only"]} ratio={t["ratio"]}')


def validate(report: dict, md: str) -> None:
    if report.get('schema') != SCHEMA:
        raise ValueError(f'schema {report.get("schema")!r} is not {SCHEMA}')
    rows, t = report['rows'], report['totals']
    for direction in ('orig_only', 'remake_only', 'ratio'):
        if t[direction] != sum(1 for r in rows if r['direction'] == direction):
            raise ValueError(f'totals.{direction} does not recount from the rows')
    for level in report['levels']:
        for kind in set(level['original']) | set(level['remake']):
            o, r = level['original'].get(kind, 0), level['remake'].get(kind, 0)
            flagged = flag(o, r, level['actions']) is not None
            if flagged != any(row['level'] == level['level'] and row['kind'] == kind for row in rows):
                raise ValueError(f'level {level["level"]} {kind}: rows do not recount from the level counts')
    if t['actions_original'] != sum(level['actions'][0] for level in report['levels']) or \
            t['actions_remake'] != sum(level['actions'][1] for level in report['levels']):
        raise ValueError('action totals do not recount from the levels')
    missing = [f'{r["level"]}:{r["kind"]}:{r["direction"]}' for r in rows if not r['attribution']]
    if missing:
        raise ValueError(f'flagged rows without an attribution (NOTES): {missing}')
    if md != render_md(report):
        raise ValueError(f'{REPORT_MD} is not the rendering of {REPORT_JSON}')


class AiActionFrequencyTask(Task):
    name = 'ai_action_frequency'
    family = 'development'  # a frequency report over content/generated/hsl/development, not an evidence-packet probe
    outputs = (REPORT_JSON, REPORT_MD)
    scripts = ('tools/hsltools/probes/ai_action_frequency.py',)
    replaces = ()

    def check(self, ctx: Context) -> str:
        try:
            report = json.loads((ctx.root / REPORT_JSON).read_text(encoding='utf-8'))
            validate(report, (ctx.root / REPORT_MD).read_text(encoding='utf-8'))
        except (OSError, ValueError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return summary(report)

    def generate(self, ctx: Context) -> str:
        report = build()
        md = render_md(report)
        validate(report, md)
        (ctx.root / REPORT_JSON).write_text(render_json(report), encoding='utf-8')
        (ctx.root / REPORT_MD).write_text(md, encoding='utf-8')
        return summary(report)


def tasks() -> list[Task]:
    return [AiActionFrequencyTask()]


# ---- remake export driver

def export(levels: list[int], seeds: str, jobs: int, out_name: str, turns: int = TURNS, sub: str = 'remake', ai_seeds: bool = False) -> int:
    """Run the remake exporter over `levels` split into `jobs` Godot processes; one JSONL per chunk."""
    from concurrent.futures import ThreadPoolExecutor
    (RAW / sub).mkdir(parents=True, exist_ok=True)
    board = RAW / 'board_growth_false.json'
    board.write_text('{"growth": false}\n', encoding='utf-8')
    chunks = [levels[i::jobs] for i in range(jobs) if levels[i::jobs]]

    def run(index: int) -> int:
        out = RAW / sub / f'{out_name}_{index}.jsonl'
        command = [str(ROOT / 'tools/godot.sh'), '--headless', '--script', EXPORTER, '--',
                   '--battles', ','.join(battle_arg(level) for level in chunks[index]), '--ai-seeds' if ai_seeds else '--seeds', seeds,
                   '--turns', str(turns), '--state', str(board), '--out', str(out),
                   '--select', ','.join(f'{battle_arg(level)}={event}' for level, event in MENU_EVENTS.items())]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (RAW / sub / f'{out_name}_{index}.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        print(f'chunk {index}: exit {result.returncode}', [l for l in result.stdout.splitlines() if l.startswith('AIFREQ_DONE')])
        return result.returncode

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        codes = list(pool.map(run, range(len(chunks))))
    return max(codes)


def main(argv: list[str] | None = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description='AI action frequency (lane AIFREQ).')
    sub = parser.add_subparsers(dest='command', required=True)
    ex = sub.add_parser('export', help='remake side into ignored/ai_action_frequency/remake')
    ex.add_argument('--levels', help='comma list (default: every level the original side has)')
    ex.add_argument('--seeds', default='1-3')
    ex.add_argument('--jobs', type=int, default=2)
    ex.add_argument('--turns', type=int, default=TURNS)
    ex.add_argument('--ai-seeds', action='store_true', help='--seeds are AI source seeds on one seed-1 opening per level (the batch_rules distribution)')
    ex.add_argument('--dir', default='remake', help='subdirectory of ignored/ai_action_frequency (dist: the round-1 distribution batch_rules reads)')
    ex.add_argument('--flagged', action='store_true', help='only levels with a one-sided row in the current build (seeds 4-32)')
    show = sub.add_parser('show', help='print the leaderboard without the attribution gate (no write)')
    show.add_argument('--direction', action='append', default=[])
    args = parser.parse_args(argv)
    if args.command == 'export':
        levels = [int(x) for x in args.levels.split(',')] if args.levels else default_levels()
        if args.flagged:
            report = build(levels)
            levels = sorted({r['level'] for r in report['rows'] if r['direction'] in ('orig_only', 'remake_only')})
            print('flagged levels', levels)
        return export(levels, args.seeds, args.jobs, 'seeds_' + args.seeds.replace(',', '_'), args.turns, args.dir, args.ai_seeds)
    report = build()
    print(json.dumps(report['totals'], ensure_ascii=False))
    for row in report['kind_totals']:
        print(f'{row["label"]:<16} orig={row["original"]:<5} remake={row["remake"]:<5} orig_only={row["orig_only"]} remake_only={row["remake_only"]} ratio={row["ratio"]}')
    for row in report['rows']:
        if args.direction and row['direction'] not in args.direction:
            continue
        print(f'{row["direction"]:<11} {row["kind"]:<14} L{row["level"]:03d} o={row["original"]} r={row["remake"]} '
              f'seeds={row["original_seeds"]}/{row["remake_seeds"]} runs={row["runs"]} wide={row["remake_wide"]} acts={row["actions"]} p={row["p"]:g} | {row["attribution"]}')
    print('skipped', report['skipped'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
