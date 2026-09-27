"""Batch rule classifier: the BATCH2 做法 (docs/evidence_packets/runtime_observations/oracle_batch/README.md
「做法」) over the AIFREQ inputs, round 1 only — which of the original's round-1 rows the remake cannot walk
(rule), can walk with another probability (random), or are not comparable (injection gap／probe caliber／
pending). Lane AIFREQ2 rewrote it: BATCH2's classify.py stayed in an ignored/ directory that is gone.

Inputs (untracked, the three exports of ai_action_frequency.py's docstring):
  ignored/ai_action_frequency/original/L<lvl>_s<s>_original.jsonl  referee, --mix, first line = round 1
  ignored/ai_action_frequency/remake/*.jsonl                        remake main run per seed, first round
  ignored/ai_action_frequency/dist/*.jsonl                          `export --ai-seeds --seeds 1-32 --turns 1
                                                                    --dir dist`: one seed-1 opening, AI seeds 1..32

A referee run stopped inside round 1 (frame limit or emulator stop) is left out. Per (level, seed), rows pair by (actor, k-th action of that actor in round 1); a pair agrees when
from／to／action／target are equal. The remake side merges action_twice (merge_twice), drops the
player_controlled units' rows (the referee records no player turn) and the ship hulls' zero-frame
turns (ai_action_frequency.REMAKE_AS_REFEREE), and reads paralysis_skip ('other')
as the in-place wait the referee records for that queue slot. A differing pair is, in order:
  injection  actor／target outside the remake roster (obj0x…, slotNN_codeNNN), a remake-only row on an
             INJECTION_GAPS level (the original names that unit obj0x…), or k = 0 with from different
  pending    the same seed already has a from difference (context not comparable)
  caliber    a ROUND_ONE_END level, the original row has no `to` (the battle ended on it), or a remake-only row on a PROBE_GAPS level
             other than the hull levels 12／26 (their hull rows are already dropped)
  prefix     expectation = the original's rows of remake actors; each dist seed's agreeing prefix; a seed
             walking all of it → every difference random; else j = the longest prefix, and when the seeds
             reaching j stop on one field (≥ 10) or with one outcome (≥ 3), that field's singleton share
             among them ≤ 0.1, the original row j is a rule root (rule, 前缀确证); differences before j random
  marginal   the original's value of the first differing field (action → target → to; acts = row missing)
             among the dist seeds' values for that actor's k-th action: seen → random; unseen with singleton
             share ≤ 0.1 → rule (边际); unseen otherwise, or the actor has < 8 dist samples → pending
Rule rows get a category (法术分支／地形射程／道具／法术目标／持有目标／持有目标·重制无目标／选目标／站位／
行动有无) and the number of original seeds whose same actor k-th action has the same value (复现).

  python3 tools/hsltools/probes/_batch_rules.py [--json OUT]
Prints the leaderboard, every rule row and `BATCH_RULES levels=… actions=… agree=… rule=… random=…
injection=… caliber=… pending=…`.
"""
from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_batch_rules.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes.ai_action_frequency import (  # noqa: E402
    INJECTION_GAPS, MAIN_SEEDS, PROBE_GAPS, RAW, ZERO_FRAME_PREFIX, battle_names, default_levels, level_of, merge_twice, scenario_path)

FIELDS = ('from', 'to', 'action', 'target')
ROUND_ONE_END = (73, 75)   # PROBE_GAPS: the original's battle ends inside round 1 (exit／049_10), every row is caliber
ORDER = ('action', 'target', 'to')
PREFIX_MANY, PREFIX_ONE, SINGLETON_MAX, MIN_SAMPLES = 10, 3, 0.1, 8


def roster(level: int) -> dict[str, str]:
    units = json.loads(scenario_path(level).read_text(encoding='utf-8'))['playable_units']
    return {str(u['id']): str(u.get('battle_actor_role', '')) for u in units}


def remake_rows(actions: list[dict], roles: dict[str, str]) -> list[dict]:
    out = []
    for row in merge_twice(actions):
        if roles.get(row['actor']) == 'player_controlled' or row['actor'].startswith(ZERO_FRAME_PREFIX):
            continue
        if row['action'] == 'other':   # paralysis_skip: the referee's in-place wait for the slot
            row = dict(row, action='wait', to=row['from'])
        out.append(row)
    return out


def load_remake(sub: str) -> dict:
    runs: dict = {}
    for path in sorted((RAW / sub).glob('*.jsonl')):
        for line in path.read_text(encoding='utf-8').splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not row['error'] and row['turns']:
                runs[(level_of(str(row['battle'])), int(row['seed']))] = row['turns'][0]['actions']
    return runs


def keyed(rows: list[dict]) -> list[tuple]:
    seen: Counter = Counter()
    out = []
    for row in rows:
        out.append((row['actor'], seen[row['actor']]))
        seen[row['actor']] += 1
    return out


def same(a: dict | None, b: dict | None) -> bool:
    return a is not None and b is not None and all(list(a[f]) == list(b[f]) if isinstance(a[f], list) and isinstance(b[f], list)
                                                   else a[f] == b[f] for f in FIELDS)


def first_field(o: dict | None, r: dict | None) -> str:
    if o is None or r is None:
        return 'acts'
    return next((f for f in ORDER if o[f] != r[f]), 'from')


def value(row: dict | None, field: str):
    if field == 'acts':
        return row is not None
    return None if row is None else (tuple(row[field]) if isinstance(row[field], list) else row[field])


def singleton_share(values: list) -> float:
    counts = Counter(values)
    return sum(1 for v in values if counts[v] == 1) / len(values) if values else 1.0


def category(o: dict | None, r: dict | None, field: str) -> str:
    if field == 'acts':
        return '行动有无'
    if field == 'action':
        verbs = {o['action'], r['action']}
        if verbs & {'magic', 'skill'}:
            return '法术分支'
        if verbs == {'attack', 'wait'}:
            return '地形射程'
        return '道具' if 'item' in verbs else '其他'
    if field == 'target':
        return {'magic': '法术目标', 'skill': '法术目标', 'attack': '选目标', 'item': '道具',
                'wait': '持有目标·重制无目标' if r['target'] is None else '持有目标'}.get(o['action'], '其他')
    return '站位'


def classify(level: int, seed: int, orig: list[dict], main: list[dict], dist: dict[int, list[dict]], roles: dict[str, str]) -> list[dict]:
    o_map = dict(zip(keyed(orig), orig))
    r_map = dict(zip(keyed(main), main))
    d_maps = {s: dict(zip(keyed(rows), rows)) for s, rows in dist.items()}
    keys = list(o_map) + [k for k in r_map if k not in o_map]
    rows = []
    for key in keys:
        o, r = o_map.get(key), r_map.get(key)
        rows.append({'level': level, 'seed': seed, 'actor': key[0], 'k': key[1], 'original': o, 'remake': r,
                     'verdict': 'agree' if same(o, r) else None})
    diffs = [row for row in rows if row['verdict'] is None]
    from_diff = False
    for row in diffs:
        o, r = row['original'], row['remake']
        names = [row['actor']] + ([o['target']] if o and o['target'] else [])
        if any(n not in roles for n in names) or (o is None and level in INJECTION_GAPS) or \
                (o and r and row['k'] == 0 and list(o['from']) != list(r['from'])):
            row['verdict'], row['why'] = 'injection', 'from' if o and r and list(o['from']) != list(r['from']) else 'roster'
            from_diff = from_diff or row['why'] == 'from'
    for row in diffs:
        if row['verdict'] is None and from_diff:
            row['verdict'] = 'pending'
        elif row['verdict'] is None and (level in ROUND_ONE_END or (row['original'] and row['original']['to'] is None)
                                         or (row['original'] is None and level in PROBE_GAPS and level not in (12, 26))):
            row['verdict'] = 'caliber'
    # prefix search
    expect = [row for row in orig if row['actor'] in roles]
    expect_keys = keyed(expect)
    position = {key: i for i, key in enumerate(expect_keys)}
    prefixes = {}
    for s, rows_d in dist.items():
        n = 0
        while n < len(expect) and n < len(rows_d) and rows_d[n]['actor'] == expect[n]['actor'] and same(rows_d[n], expect[n]):
            n += 1
        prefixes[s] = n
    root = None
    if dist and any(n == len(expect) for n in prefixes.values()):
        j = len(expect)
    else:
        j = max(prefixes.values(), default=0)
        reach = [s for s, n in prefixes.items() if n == j]
        if j < len(expect) and reach:
            stuck = [(first_field(expect[j], dist[s][j] if j < len(dist[s]) else None), s) for s in reach]
            fields = Counter(f for f, _ in stuck)
            field, count = fields.most_common(1)[0]
            outcomes = [value(dist[s][j] if j < len(dist[s]) else None, field) for f, s in stuck if f == field]
            if ((count >= PREFIX_MANY and len(fields) == 1) or (count >= PREFIX_ONE and len(set(outcomes)) == 1 and len(fields) == 1)) \
                    and (len(set(outcomes)) == 1 or singleton_share(outcomes) <= SINGLETON_MAX):
                root = {'key': expect_keys[j], 'field': field, 'reach': len(reach), 'outcomes': len(set(outcomes))}
    for row in diffs:
        if row['verdict'] is not None:
            continue
        key = (row['actor'], row['k'])
        at = position.get(key)
        if at is not None and at < j:
            row['verdict'], row['why'] = 'random', 'prefix'
            continue
        if root and key == root['key']:
            row['verdict'], row['why'], row['field'] = 'rule', 'prefix', first_field(row['original'], row['remake'])
            row['root'] = root
            continue
        field = first_field(row['original'], row['remake'])
        samples = [value(m.get(key), field) for m in d_maps.values()] if field == 'acts' else \
            [value(m[key], field) for m in d_maps.values() if key in m]
        mine = value(row['original'], field)
        row['field'] = field
        if len(samples) < MIN_SAMPLES:
            row['verdict'], row['why'] = 'pending', f'samples {len(samples)}'
        elif mine in samples:
            row['verdict'], row['why'] = 'random', 'seen'
        elif field == 'acts' or singleton_share(samples) <= SINGLETON_MAX:
            row['verdict'], row['why'] = 'rule', 'marginal' + (' after root' if root and position.get(root['key'], 1e9) < (at if at is not None else 1e9) else '')
        else:
            row['verdict'], row['why'] = 'pending', f'singletons {singleton_share(samples):.2f}'
    return rows


def collect() -> tuple[list[dict], list[int], dict]:
    """Every round-1 row classified (verdict, and for rule rows field／category／repeat), the levels run and
    the distribution per level — main's input, and the batch rule rows the replay judge (ai_replay.py) looks up."""
    main_runs, dist_runs = load_remake('remake'), load_remake('dist')
    dist_by_level: dict = defaultdict(dict)
    for (level, seed), actions in dist_runs.items():
        dist_by_level[level][seed] = actions
    all_rows: list[dict] = []
    levels_done = []
    originals: dict = {}
    for level in default_levels():
        roles = roster(level)
        for seed in MAIN_SEEDS:
            path = RAW / 'original' / f'L{level:03d}_s{seed}_original.jsonl'
            meta_path = path.with_name(path.name.replace('.jsonl', '_meta.json'))
            if not meta_path.exists() or not path.read_text().strip():
                continue
            lines = path.read_text(encoding='utf-8').splitlines()
            stop = str(json.loads(meta_path.read_text(encoding='utf-8'))['stop'])
            if len(lines) <= 1 and (stop == 'frame_limit' or stop.startswith('emulator')):
                continue   # stopped inside round 1: no whole round (ai_action_frequency EMULATOR_STOP)
            originals[(level, seed)] = json.loads(lines[0])['actions']
        dist = {s: remake_rows(a, roles) for s, a in dist_by_level.get(level, {}).items()}
        ran = False
        for seed in MAIN_SEEDS:
            if (level, seed) not in originals or (level, seed) not in main_runs:
                continue
            ran = True
            orig = [dict(a) for a in originals[(level, seed)] if not a['actor'].startswith(ZERO_FRAME_PREFIX)]
            all_rows += classify(level, seed, orig, remake_rows(main_runs[(level, seed)], roles), dist, roles)
        if ran:
            levels_done.append(level)
    # 复现: original seeds whose same actor k-th action has the rule field's value
    for row in all_rows:
        if row['verdict'] != 'rule':
            continue
        field, key = row['field'], (row['actor'], row['k'])
        mine = value(row['original'], field)
        row['repeat'] = sum(1 for s in MAIN_SEEDS if (row['level'], s) in originals and
                            value(dict(zip(keyed(originals[(row['level'], s)]), originals[(row['level'], s)])).get(key), field) == mine)
        row['category'] = category(row['original'], row['remake'], field)
    return all_rows, levels_done, dist_by_level


def main(argv: list[str] | None = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description='BATCH2 rule classifier over the AIFREQ inputs (round 1).')
    parser.add_argument('--json', type=Path)
    args = parser.parse_args(argv)
    names = battle_names()
    all_rows, levels_done, dist_by_level = collect()
    totals = Counter(row['verdict'] for row in all_rows)
    rules = [row for row in all_rows if row['verdict'] == 'rule']
    board: dict = defaultdict(list)
    for row in rules:
        board[row['category']].append(row)
    print('| 名次 | 类别 | 行 | ≥2 种子复现 | 前缀确证 | 边际（其中确证根之后） | 涉及关 |')
    print('|---:|---|---:|---:|---:|---|---|')
    for rank, (cat, rows) in enumerate(sorted(board.items(), key=lambda item: -len(item[1])), 1):
        levels = sorted({r['level'] for r in rows})
        print(f'| {rank} | {cat} | {len(rows)} | {sum(1 for r in rows if r["repeat"] >= 2)} | {sum(1 for r in rows if r["why"] == "prefix")} | '
              f'{sum(1 for r in rows if r["why"].startswith("marginal"))}（{sum(1 for r in rows if r["why"] == "marginal after root")}） | '
              f'{len(levels)} 关：{"、".join(map(str, levels))} |')

    def show(row: dict | None) -> str:
        return '（无此行）' if row is None else f'{row["from"]}→{row["to"]} {row["action"]} {row["target"]}' + (f' {row["skill"]}' if row.get('skill') else '')
    for row in sorted(rules, key=lambda r: (r['level'], r['seed'], r['actor'], r['k'])):
        print(f'RULE {names.get(row["level"], row["level"])} s{row["seed"]} {row["actor"]}#{row["k"]} [{row["category"]}, {row["why"]}, 复现 {row["repeat"]}/3] '
              f'原版 {show(row["original"])} ｜ 重制 {show(row["remake"])}')
    print(f'BATCH_RULES levels={len(levels_done)} dist_levels={len(dist_by_level)} actions={len(all_rows)} agree={totals["agree"]} rule={totals["rule"]} '
          f'random={totals["random"]} injection={totals["injection"]} caliber={totals["caliber"]} pending={totals["pending"]}')
    if args.json:
        args.json.write_text(json.dumps({'totals': dict(totals), 'levels': levels_done, 'rules': rules,
                                         'injection_levels': sorted(INJECTION_GAPS)}, ensure_ascii=False, indent=0) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
