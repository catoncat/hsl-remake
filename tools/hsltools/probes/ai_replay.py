"""AI replay judge: the referee's round-1 AI decisions replayed in the remake with the original's own
draws fed in, decision point by decision point — registry task `ai_replay` (lane BATCH3; measure only).

Why: the batch rule classifier (_batch_rules.py) calls a row 'rule' when the original's value never shows
in the remake's own distribution, which the two generators alone can cause (AI-PRIO-2: 70 of 73 such rows
agreed once the original's draws were fed in). Here a row is a rule difference only when the remake, given
the original's draws at the same decision points and the original's board, still decides otherwise.

Inputs (untracked; generate raises NotGeneratable when absent):
  ignored/ai_action_frequency/original/L<lvl>_s<s>_original.jsonl (+ _meta.json)
      `_enemy_level.py batch --levels <LEVELS> --seeds 1,2,3 --turns 1 --align --mix 20 --no-remake` (the AIFREQ2
      referee run, round 1; the meta carries action_after — hp deltas, held target and the call address of
      every global draw per action — and handoff_after, the player turn-ends' hp deltas)
  ignored/ai_replay/replay_<i>.jsonl
      `python3 tools/hsltools/probes/ai_replay.py export --levels <LEVELS>`: tests/diagnostics/replay_ai_actions.gd,
      one line per (level, seed), four feeding variants per row (first／final／low／high, see that script)
  ignored/ai_action_frequency/{remake,dist}/ (optional): the batch classifier's inputs; when present each row
      says whether _batch_rules.collect() calls it a rule row (the AIFREQ2 candidates)

Decision points (DECISION_POINTS): the original's global-draw call sites (enemy_turn.SITE_MAP) and the remake
draw points (the exporter's `Script.function`) they feed; the feeder answers a remake draw at site/n with the
next value the original drew there in the same queue slot. REMAKE_ONLY lists remake draw points with no
original site (their draws are `exhausted` unless aliased); coverage counts both sides' draws per point.

Verdict per original row (round 1):
  agree     variant first decides as the original (from／to／action／target)
  random    first differs, final／low／high agrees: the original's decision is what the remake makes once the
            looped-back chain passes are dropped or its exhausted draws take another value (draw structure)
  rule      every variant differs, no context flag, and first or final asked for no draw the original did not
            make: given the original's draws and board the remake decides otherwise. Decision point = the first
            differing field (action → target → to) and its point name (FIELD_POINT)
  caliber   every variant differs and the remake drew past the original's values in both first and final
            (exhausted: draw structure or a missing mapping), or a context flag: from／death／revive (the board
            correction), board_event SITE (an earlier slot drew at a non-AI site that may change the board — poison
            gas, units entering: statuses and new units are not replayed), probe_gap／injection_gap (the level's
            draws per slot are not the slot's own: ai_action_frequency PROBE_GAPS／INJECTION_GAPS)
  order／unreached  the remake's queue reached another actor first, or the run stopped before the row

PASS: AI_REPLAY_CHECK_PASS levels=N runs=N rows=N agree=N random=N rule=N caliber=N unreached=N batch_rule=N
batch_rule_confirmed=N
"""
from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/ai_replay.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ROOT  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402
from hsltools.probes._enemy_level import MENU_EVENTS  # noqa: E402
from hsltools.probes.ai_action_frequency import INJECTION_GAPS, PROBE_GAPS, ZERO_FRAME_PREFIX, battle_arg, battle_names  # noqa: E402
from hsltools.registry import CheckFailed, Context, NotGeneratable, Task  # noqa: E402

REPORT_JSON = 'content/generated/hsl/development/ai_replay.json'
REPORT_MD = 'content/generated/hsl/development/ai_replay.md'
SCHEMA = 'hsl_ai_replay.v1'
ORIGINAL = ROOT / 'ignored/ai_action_frequency/original'
RAW = ROOT / 'ignored/ai_replay'
BOARD = ROOT / 'ignored/ai_action_frequency/board_growth_false.json'
SCRIPT = 'res://tests/diagnostics/replay_ai_actions.gd'
SEEDS = (1, 2, 3)
FIELDS = ('from', 'to', 'action', 'target')
ORDER = ('action', 'target', 'to')
VARIANTS = ('final', 'low', 'high')
FIELD_POINT = {
    'action': '行动种类：优先级链 0x440db1..0x440ef1／行动类别 0x40c570／法术表 0x40c770',
    'target': '目标：扫描 0x40bb80（保留旧候选硬币 0x40bd4f）／锁定 ai_lock（携带的链掷骰）',
    'to': '落点：站位排序 0x413390（硬币 0x4136ba）／可停格 0x413740（硬币 0x41385d、拥挤 0x413890）／侧走 0x43ff1f',
    'from': '起点（盘面）',
}
# Original AI call sites outside enemy_turn.SITE_MAP the feeder (replay_ai_actions.gd Feeder.prime) maps itself.
FEEDER_ALIASES = {'0x440a86': ('AISupportPlanning.choose', 2, '0x440a86..0x440ad3 buff aid: one raw draw, low bit orders magic／special (AISupportPlanning.gd special_first)')}
# Remake draw points with no original call site in enemy_turn.SITE_MAP (the feeder's alias in parentheses).
REMAKE_ONLY = {
    'BattleLoopAI._ai_lock_check': '锁定检查的新掷骰（重制没有携带的链掷骰时才抽；喂原版本槽最后一个链掷骰 choose_check／next_check）',
    'AISupportPlanning.choose': '援助链首掷（重制没有携带的链掷骰时才抽；原版链首总是 0x440db5，无独立站点）',
    'AISkillPlanning.choose': '同落点中心替换硬币／无威胁时在不同落点里 rand(count)（原版对应 0x40c9a0／0x40cca0 内的抽取未逐条映射）',
}


# ---- export

def jobs_for(levels: list[int]) -> list[dict]:
    jobs = []
    for level in levels:
        for seed in SEEDS:
            original = ORIGINAL / f'L{level:03d}_s{seed}_original.jsonl'
            meta = original.with_name(original.name.replace('.jsonl', '_meta.json'))
            if original.exists() and meta.exists() and original.read_text(encoding='utf-8').strip():
                jobs.append({'battle': battle_arg(level), 'level': level, 'seed': seed, 'original': str(original), 'meta': str(meta),
                             'select_event': MENU_EVENTS.get(level)})
    return jobs


def export(levels: list[int], jobs: int) -> int:
    from concurrent.futures import ThreadPoolExecutor
    RAW.mkdir(parents=True, exist_ok=True)
    BOARD.parent.mkdir(parents=True, exist_ok=True)
    BOARD.write_text('{"growth": false}\n', encoding='utf-8')
    work = jobs_for(levels)
    chunks = [work[i::jobs] for i in range(jobs) if work[i::jobs]]

    def run(index: int) -> int:
        spec = RAW / f'jobs_{index}.json'
        spec.write_text(json.dumps(chunks[index]), encoding='utf-8')
        command = [str(ROOT / 'tools/godot.sh'), '--headless', '--script', SCRIPT, '--', '--jobs', str(spec), '--state', str(BOARD),
                   '--turns', '1', '--out', str(RAW / f'replay_{index}.jsonl')]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (RAW / f'replay_{index}.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        print(f'chunk {index}: exit {result.returncode}', [line for line in result.stdout.splitlines() if line.startswith('REPLAY_DONE')])
        return result.returncode

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        return max(pool.map(run, range(len(chunks))), default=0)


# ---- classification

def first_field(original: dict, remake: dict) -> str:
    return next((f for f in ORDER if str(original[f]) != str(remake.get(f))), 'from')


def board_event(site: str) -> bool:
    """A global draw that is no AI decision and may change the board the replay does not follow: every site
    outside SITE_MAP except the effect-process draws of a cast (0x401390／0x415c10／0x415d90..0x4239xx)."""
    if site in et.SITE_MAP or site in FEEDER_ALIASES:
        return False
    address = int(site, 16)
    return not (0x401390 <= address < 0x401500 or 0x415c10 <= address < 0x423a00)


def classify(row: dict, events: list[str] = (), gap: str = '') -> dict:
    """`events`: the board-event sites the original drew in slots before this one (map objects such as the
    poison gas, units entering) — context the replay board does not carry (statuses, new units). `gap`: the
    level is a probe／injection gap of ai_action_frequency (zero-frame turns whose draws the probe files under
    a neighbouring slot, units installed after the halt) — its draws per slot are not the slot's own."""
    variants = row.get('variants', {})
    out = {'verdict': None, 'why': ''}
    if row['same']:
        out['verdict'] = 'agree'
        return out
    reached = [m for m in VARIANTS if variants.get(m, {}).get('same')]
    context = sorted(set(row['context']) | set(variants.get('final', {}).get('context', [])) | ({'board_event ' + events[0]} if events else set()) | ({gap} if gap else set()))
    final = variants.get('final', {})
    if reached:
        out.update(verdict='random', why='+'.join(reached))
    elif context:
        out.update(verdict='caliber', why='context ' + ','.join(context))
    elif not row['exhausted'] or (final and not final.get('exhausted')):
        fed = 'first' if not row['exhausted'] else 'final'
        remake = row['remake'] if fed == 'first' else final['remake']
        field = first_field(row['original'], remake)
        out.update(verdict='rule', why=f'fed {fed}', field=field, point=FIELD_POINT[field])
    else:
        sites = sorted(set(row['exhausted']) | set(final.get('exhausted', [])))
        out.update(verdict='caliber', why='exhausted ' + ','.join(sites))
    return out


def per_actor_index(rows: list[dict]) -> dict[int, int]:
    """k (index in the original's jsonl) → that actor's ordinal in round 1, hull rows left out (_batch_rules keyed)."""
    seen: Counter = Counter()
    out = {}
    for row in rows:
        if row['actor'].startswith(ZERO_FRAME_PREFIX):
            continue
        out[row['k']] = seen[row['actor']]
        seen[row['actor']] += 1
    return out


def batch_rules() -> dict[tuple, dict]:
    """The batch classifier's rule rows keyed (level, seed, actor, k), when its inputs are present."""
    if not (ROOT / 'ignored/ai_action_frequency/dist').is_dir() or not (ROOT / 'ignored/ai_action_frequency/remake').is_dir():
        return {}
    from hsltools.probes._batch_rules import collect
    rows, _levels, _dist = collect()
    return {(r['level'], r['seed'], r['actor'], r['k']): r for r in rows if r['verdict'] == 'rule'}


def show(action: dict | None) -> str:
    if not action:
        return '（无此行）'
    return f'{action["from"]}→{action["to"]} {action["action"]} {action["target"]}' + (f' {action["skill"]}' if action.get('skill') else '')


def build() -> dict:
    paths = sorted(RAW.glob('replay_*.jsonl'))
    if not paths:
        raise NotGeneratable(f'no replay export under {RAW.relative_to(ROOT)} (ai_replay.py export --levels …)')
    names = battle_names()
    rules_index = batch_rules()
    runs, rows_out = [], []
    coverage_remake: Counter = Counter()
    coverage_original: Counter = Counter()
    exhausted_sites: Counter = Counter()
    for path in paths:
        for line in path.read_text(encoding='utf-8').splitlines():
            run = json.loads(line)
            runs.append({'level': run['level'], 'seed': run['seed'], 'error': run['error'], 'stop': run['stop'],
                         'opening_diff': len(run['opening_diff']), 'rows': len(run['rows']), 'uncompared': len(run['uncompared']),
                         'unreached': len(run['unreached'])})
            ordinal = per_actor_index(run['rows'])
            meta = json.loads((ORIGINAL / f'L{run["level"]:03d}_s{run["seed"]}_original_meta.json').read_text(encoding='utf-8'))
            events_before: list[list[str]] = []
            seen_events: list[str] = []
            for after in meta.get('action_after', []):
                coverage_original.update(after.get('sites', []))
                events_before.append(list(seen_events))
                seen_events += [s for s in after.get('sites', []) if board_event(s) and s not in seen_events]
            for row in run['rows']:
                coverage_remake.update(key.rsplit('/', 1)[0] for key in row['drawn'])
                gap = ('probe_gap' if run['level'] in PROBE_GAPS else 'injection_gap' if run['level'] in INJECTION_GAPS else '')
                verdict = classify(row, events_before[row['k']] if row['k'] < len(events_before) else [], gap)
                exhausted_sites.update(set(row['exhausted']))
                key = (run['level'], run['seed'], row['actor'], ordinal.get(row['k'], -1))
                batch = rules_index.get(key)
                rows_out.append({'level': run['level'], 'seed': run['seed'], 'k': row['k'], 'actor': row['actor'], 'ordinal': key[3],
                                 'original': row['original'], 'remake': row['remake'], **verdict,
                                 'final': row.get('variants', {}).get('final', {}).get('remake'),
                                 'exhausted': sorted(set(row['exhausted'])), 'leftover': row['leftover'],
                                 'decision': row['decision'][-1] if row['decision'] else {},
                                 'batch_rule': None if batch is None else {'category': batch['category'], 'why': batch['why'], 'repeat': batch['repeat']}})
            for gone in run['unreached']:
                rows_out.append({'level': run['level'], 'seed': run['seed'], 'k': gone['k'], 'actor': gone['actor'], 'ordinal': -1,
                                 'original': None, 'remake': None, 'verdict': 'unreached', 'why': run['stop'] or run['error'] or 'battle_end',
                                 'final': None, 'exhausted': [], 'leftover': {}, 'decision': {}, 'batch_rule': None})
    # batch rule rows the replay has no row for (remake-only rows: the original did not act)
    matched = {(r['level'], r['seed'], r['actor'], r['ordinal']) for r in rows_out}
    missing = [{'level': k[0], 'seed': k[1], 'actor': k[2], 'ordinal': k[3], 'category': v['category'], 'remake': show(v['remake'])}
               for k, v in sorted(rules_index.items()) if k not in matched]
    totals = Counter(r['verdict'] for r in rows_out)
    batch_rows = [r for r in rows_out if r['batch_rule']]
    site_rows = []
    for site, (name, _n, basis) in sorted({**et.SITE_MAP, **FEEDER_ALIASES}.items()):
        site_rows.append({'original': site, 'remake': name, 'original_draws': coverage_original.get(site, 0),
                          'remake_draws': coverage_remake.get(name, 0), 'basis': basis})
    mapped_names = {name for name, _n, _b in {**et.SITE_MAP, **FEEDER_ALIASES}.values()}
    remake_only = [{'remake': key, 'remake_draws': coverage_remake.get(key.rsplit('/', 1)[0], 0), 'exhausted_rows': count,
                    'note': REMAKE_ONLY.get(key.rsplit('/', 1)[0], '') if key.rsplit('/', 1)[0] not in mapped_names or key == 'AISupportPlanning.choose/99'
                    else '有原版站点，重制在此点比原版本槽抽得多（抽取结构或走了另一支）'}
                   for key, count in sorted(exhausted_sites.items())]
    original_only = [{'original': site, 'original_draws': count, 'note': et.UNMAPPED_ACTION_SITES.get(site, et.DAMAGE_SITE_MAP.get(site, '非 AI 站点（地图物件／事件），不喂'))}
                     for site, count in sorted(coverage_original.items()) if site not in et.SITE_MAP and site not in FEEDER_ALIASES]
    report = {
        'schema': SCHEMA,
        'totals': {'levels': len({r['level'] for r in runs}), 'runs': len(runs), 'rows': len(rows_out),
                   **{v: totals.get(v, 0) for v in ('agree', 'random', 'rule', 'caliber', 'unreached')},
                   'batch_rule': len(batch_rows) + len(missing),
                   'batch_rule_confirmed': sum(1 for r in batch_rows if r['verdict'] == 'rule'),
                   'mapped_sites': sum(1 for s in site_rows if s['original_draws'] or s['remake_draws']), 'site_map': len(site_rows),
                   'remake_only_points': sum(1 for s in remake_only if s['remake'].rsplit('/', 1)[0] not in mapped_names or s['remake'] == 'AISupportPlanning.choose/99'), 'original_unmapped_sites': len(original_only)},
        'names': {str(level): names.get(level, str(level)) for level in sorted({r['level'] for r in runs})},
        'runs': runs,
        'sites': site_rows, 'remake_only': remake_only, 'original_only': original_only,
        'rows': [r for r in rows_out if r['verdict'] != 'agree' or r['batch_rule']],   # agreeing rows only when a batch rule row
        'batch_missing': missing,
    }
    return report


def summary(report: dict) -> str:
    t = report['totals']
    return (f'AI_REPLAY_CHECK_PASS levels={t["levels"]} runs={t["runs"]} rows={t["rows"]} agree={t["agree"]} random={t["random"]} '
            f'rule={t["rule"]} caliber={t["caliber"]} unreached={t["unreached"]} batch_rule={t["batch_rule"]} '
            f'batch_rule_confirmed={t["batch_rule_confirmed"]}')


def render_json(report: dict) -> str:
    head = {k: v for k, v in report.items() if k not in ('rows', 'runs')}
    lines = [json.dumps(head, ensure_ascii=False)[:-1] + ', "runs": [']
    lines.append(',\n'.join(json.dumps(r, ensure_ascii=False) for r in report['runs']) + '], "rows": [')
    lines.append(',\n'.join(json.dumps(r, ensure_ascii=False) for r in report['rows']) + ']}')
    return '\n'.join(lines) + '\n'


def render_md(report: dict) -> str:
    t, names = report['totals'], report['names']
    name = lambda level: names.get(str(level), str(level))
    out = ['# AI 回放判定（lane BATCH3，首轮）', '',
           '生成：`python3 tools/hsl.py generate ai_replay`（做法见 tools/hsltools/probes/ai_replay.py 文档串与 '
           '[oracle_batch README](../../../../docs/evidence_packets/runtime_observations/oracle_batch/README.md)「回放判定」）。', '',
           f'- {t["levels"]} 关 {t["runs"]} 局，原版首轮 {t["rows"]} 行：一致 {t["agree"]}、随机（换喂法可达）{t["random"]}、'
           f'规则 {t["rule"]}、口径 {t["caliber"]}、未走到 {t["unreached"]}。',
           f'- 批量分类器的规则行 {t["batch_rule"]} 行，回放确证 {t["batch_rule_confirmed"]} 行。',
           f'- 决策点：SITE_MAP {t["site_map"]} 个原版站点，本批用到 {t["mapped_sites"]} 个；重制独有抽取点 {t["remake_only_points"]} 个；'
           f'原版未映射站点 {t["original_unmapped_sites"]} 个（非 AI，不喂）。', '',
           '## 确证规则差异', '', '| 关 | 种子 | 单位 | 决策点 | 原版 | 重制（喂原版抽签） | 批量分类 |', '|---|---:|---|---|---|---|---|']
    for r in report['rows']:
        if r['verdict'] != 'rule':
            continue
        remake = r['remake'] if r['why'] == 'fed first' else r['final']
        batch = f'{r["batch_rule"]["category"]}（{r["batch_rule"]["why"]}）' if r['batch_rule'] else '—'
        out.append(f'| {name(r["level"])} | {r["seed"]} | {r["actor"]}#{r["ordinal"]} | {r["field"]}：{r["point"]} | {show(r["original"])} | {show(remake)} | {batch} |')
    out += ['', '## 批量规则行的回放结论', '', '| 关 | 种子 | 单位 | 批量类别 | 回放 | 依据 |', '|---|---:|---|---|---|---|']
    for r in report['rows']:
        if r['batch_rule']:
            out.append(f'| {name(r["level"])} | {r["seed"]} | {r["actor"]}#{r["ordinal"]} | {r["batch_rule"]["category"]} | {r["verdict"]} | {r["why"]} |')
    for m in report['batch_missing']:
        out.append(f'| {name(m["level"])} | {m["seed"]} | {m["actor"]}#{m["ordinal"]} | {m["category"]} | 原版无此行 | 重制 {m["remake"]} |')
    out += ['', '## 口径', '', '| 关 | 种子 | 单位 | 原因 |', '|---|---:|---|---|']
    for r in report['rows']:
        if r['verdict'] in ('caliber', 'unreached'):
            out.append(f'| {name(r["level"])} | {r["seed"]} | {r["actor"]} | {r["verdict"]}：{r["why"]} |')
    out += ['', '## 决策点映射', '', '| 原版站点 | 重制抽取点 | 原版抽取 | 重制抽取 |', '|---|---|---:|---:|']
    for s in report['sites']:
        out.append(f'| {s["original"]} | {s["remake"]} | {s["original_draws"]} | {s["remake_draws"]} |')
    out += ['', '重制抽过原版本槽值的抽取点（site/n，用尽行数）：', '']
    for s in report['remake_only']:
        out.append(f'- `{s["remake"]}`：该点重制共抽 {s["remake_draws"]} 次，用尽 {s["exhausted_rows"]} 行。{s["note"]}')
    out += ['', '原版未映射站点（回合内全局流抽取，不是 AI 决策，不喂）：', '']
    out.append('、'.join(f'`{s["original"]}` {s["original_draws"]}' for s in report['original_only']) or '无')
    return '\n'.join(out) + '\n'


def validate(report: dict, md: str) -> None:
    if report.get('schema') != SCHEMA:
        raise ValueError(f'schema {report.get("schema")!r} is not {SCHEMA}')
    t, rows = report['totals'], report['rows']
    for verdict in ('random', 'rule', 'caliber', 'unreached'):
        if t[verdict] != sum(1 for r in rows if r['verdict'] == verdict):
            raise ValueError(f'totals.{verdict} does not recount from the rows')
    if t['rows'] != t['agree'] + sum(1 for r in rows if r['verdict'] != 'agree') or t['runs'] != len(report['runs']):
        raise ValueError('row／run totals do not recount')
    if t['batch_rule_confirmed'] != sum(1 for r in rows if r['batch_rule'] and r['verdict'] == 'rule') or \
            t['batch_rule'] != sum(1 for r in rows if r['batch_rule']) + len(report['batch_missing']):
        raise ValueError('batch rule totals do not recount')
    if md != render_md(report):
        raise ValueError(f'{REPORT_MD} is not the rendering of {REPORT_JSON}')


class AiReplayTask(Task):
    name = 'ai_replay'
    family = 'development'  # a replay report over content/generated/hsl/development, like ai_action_frequency
    outputs = (REPORT_JSON, REPORT_MD)
    scripts = ('tools/hsltools/probes/ai_replay.py',)
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
    return [AiReplayTask()]


def main(argv: list[str] | None = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description='AI replay judge (lane BATCH3).')
    sub = parser.add_subparsers(dest='command', required=True)
    ex = sub.add_parser('export', help='replay the referee rounds in the remake into ignored/ai_replay')
    ex.add_argument('--levels', required=True, help='comma list')
    ex.add_argument('--jobs', type=int, default=2)
    sub.add_parser('show', help='print the verdict totals and rule rows (no write)')
    args = parser.parse_args(argv)
    if args.command == 'export':
        return export([int(x) for x in args.levels.split(',')], args.jobs)
    report = build()
    print(summary(report))
    for r in report['rows']:
        if r['verdict'] == 'rule':
            print('RULE', report['names'].get(str(r['level'])), f's{r["seed"]}', f'{r["actor"]}#{r["ordinal"]}', r['field'], '|',
                  '原版', show(r['original']), '| 重制', show(r['remake'] if r['why'] == 'fed first' else r['final']),
                  '| batch', r['batch_rule'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
