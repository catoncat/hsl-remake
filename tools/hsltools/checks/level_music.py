"""Level music against the original: every campaign scene's music actions vs original_music.md §4.

The original plays no music when a level starts; only the scripts do (static-derived,
docs/evidence_packets/static_reverse/original_music.md §1-§4): actPlayMusic N plays track N,
actPlayLevelMusic the table track of the script's level, actPlayDefaultLevelMusic L the table
track of level L (table 0x477b44, levels 0-99; >= 100 resolves to -1 = keep the current track),
and the movie player stops the music. hsltools.levels.timeline resolves every music event's
`track` / `stream` at generation time and each scene carries `level_table_music` (what loading
its battle record plays, §3.1). This check re-reads the evidence packet and FAILs when

  - the §2 table differs from timeline.LEVEL_MUSIC_TABLE, or a §4 LVL／DEF track disagrees
    with the §2 table;
  - a campaign scene's opening (STORY) music / movie events differ from its §4 row in order,
    kind, argument, resolved track or position (section 0 action index and action count,
    mapped through the level's seed);
  - the music / movie events of its winfail programs (status timelines and select-event
    timelines, positions mapped from the flat chain index through the seed) differ from the
    §4 WINFAIL rows of that level (a row no program carries is a mismatch too);
  - an event's `stream` is not the imported file of its track ("" for -1), or the scene's
    `level_table_music` is not the table entry of its level.

The chapter-wide opening timeline (story051 script IR) is compared with the STORY051 row.
The authored level (200) has no original row: its events are listed, not compared. §4 rows
whose level has no campaign scene (097-099) are listed as rows_without_scene.

PASS line: LEVEL_MUSIC_PASS scenes=N table_levels=100 story_scripts=N winfail_rows=N chapter_timeline=1
music_events=N movie_events=N level_table_music=N authored=N rows_without_scene=N mismatches=0
(story_scripts: compared campaign openings; music／movie events: campaign scenes only).

Table (every campaign scene): PYTHONPATH=tools python3 -m hsltools.checks.level_music --table

Registry task level_music (family checks, CheckTask, replaces=()).
"""
from __future__ import annotations

import dataclasses
import json
import re
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.levels.timeline import LEVEL_MUSIC_TABLE, MUSIC_KINDS, level_table_music, level_table_track, music_stream
from hsltools.registry import CheckFailed, Context

PACKET = 'docs/evidence_packets/static_reverse/original_music.md'
CAMPAIGN = 'content/battles/campaign.json'
CHAPTER_TIMELINE = 'content/imported/hsl/chapter01/opening_timeline.json'
CHAPTER_IR = 'content/imported/hsl/chapter01/scripts/story051.json'
CHAPTER_ROW = 'chapter01/opening_timeline.json'
SEEDS = 'content/generated/hsl/chapter01'
MOVIE = 'movie_play'
KINDS = (*MUSIC_KINDS, MOVIE)
MINUS = '−'  # the packet writes -1 with U+2212

_SCRIPT_CELL = re.compile(r'^(STORY|WINFAIL)(\d{3}(?:[–／]\d{3})*)$')
_MUS = re.compile(r'^MUS (\d+)（(?:act(\d+)(?:/(\d+))?|各自 act(\d+))）$')
_LVL = re.compile(rf'^LVL→([{MINUS}-]?\d+)（act(\d+)(?:/(\d+))?）$')
_DEF = re.compile(r'^DEF\((\d+)\)→(\d+)（act(\d+)(?:/(\d+))?）$')
_MOVIE = re.compile(r'^actPlayMovie（act(\d+)/(\d+)），停乐$')
_EVENT_LVL = re.compile(rf'^第 (\d+) 节事件 (\d+) act(\d+)：LVL→([{MINUS}-]?\d+)$')


@dataclasses.dataclass(frozen=True)
class Action:
    """One music / movie action: what it plays and where it sits in its script section."""
    kind: str
    arg: int | None          # actPlayMusic N / actPlayDefaultLevelMusic L; None otherwise
    track: int | None        # the resolved track (-1 = keep the current one); None for a movie
    section: int
    action: int
    total: int | None        # the section's action count (None: the packet names none)

    def label(self) -> str:
        where = f'act{self.action}' + (f'/{self.total}' if self.total is not None else '')
        where = where if self.section == 0 else f's{self.section} {where}'
        if self.kind == MOVIE:
            return f'movie（{where}，停乐）'
        track = f'{self.track:02d}' if self.track is not None and self.track >= 0 else str(self.track)
        head = {'music_track': f'MUS {self.arg}', 'opening_music': 'LVL', 'default_level_music': f'DEF({self.arg})'}[self.kind]
        return f'{head}→{track}（{where}）'

    def key(self) -> tuple:
        return (self.kind, self.arg, self.track, self.section, self.action)


def _load(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def _int(text: str) -> int:
    return int(text.replace(MINUS, '-'))


def _section(text: str, number: str) -> list[str]:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith(f'## {number} ')), None)
    if start is None:
        raise ValueError(f'{PACKET}: section §{number} not found')
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    return lines[start + 1:end]


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip('|').split('|')]


def packet_table(text: str) -> list[int]:
    """§2: the int16 table 0x477b44, ten levels per row."""
    values: list[int] = []
    for line in _section(text, '2'):
        cells = _cells(line) if line.startswith('|') else []
        if len(cells) == 11 and cells[0].isdigit():
            if int(cells[0]) != len(values):
                raise ValueError(f'{PACKET} §2: row {cells[0]} out of order')
            values.extend(_int(cell) for cell in cells[1:])
    return values


def _levels(numbers: str) -> list[int]:
    if '–' in numbers:
        first, last = (int(part) for part in numbers.split('–'))
        return list(range(first, last + 1))
    return [int(part) for part in numbers.split('／')]


def _story_action(text: str) -> Action:
    if match := _MUS.match(text):
        action = match.group(2) if match.group(2) is not None else match.group(4)
        total = int(match.group(3)) if match.group(3) else None
        return Action('music_track', int(match.group(1)), int(match.group(1)), 0, int(action), total)
    if match := _LVL.match(text):
        return Action('opening_music', None, _int(match.group(1)), 0, int(match.group(2)),
                      int(match.group(3)) if match.group(3) else None)
    if match := _DEF.match(text):
        return Action('default_level_music', int(match.group(1)), int(match.group(2)), 0, int(match.group(3)),
                      int(match.group(4)) if match.group(4) else None)
    if match := _MOVIE.match(text):
        return Action(MOVIE, None, None, 0, int(match.group(1)), int(match.group(2)))
    raise ValueError(f'{PACKET} §4: unreadable action {text!r}')


def packet_rows(text: str) -> tuple[dict[int, list[Action]], dict[int, list[tuple[int | None, Action]]]]:
    """§4: STORY rows (level -> actions in order) and WINFAIL rows (level -> [(event code, action)])."""
    story: dict[int, list[Action]] = {}
    winfail: dict[int, list[tuple[int | None, Action]]] = {}
    for line in _section(text, '4'):
        cells = _cells(line) if line.startswith('|') else []
        if len(cells) != 2 or not (match := _SCRIPT_CELL.match(cells[0])):
            continue
        kind, levels = match.group(1), _levels(match.group(2))
        if kind == 'STORY':
            # "MUS 8（…） → LVL→13（…）": the row separator is " → "; an action's own arrow has no spaces.
            actions = [_story_action(part.strip()) for part in cells[1].split(' → ')]
            for level in levels:
                if level in story:
                    raise ValueError(f'{PACKET} §4: STORY{level:03d} listed twice')
                story[level] = actions
        else:
            if match := _EVENT_LVL.match(cells[1]):
                row = (int(match.group(2)), Action('opening_music', None, _int(match.group(4)), int(match.group(1)),
                                                   int(match.group(3)), None))
            else:
                row = (None, _story_action(cells[1]))
            for level in levels:
                winfail.setdefault(level, []).append(row)
    return story, winfail


def _packet_consistency(table: list[int], story: dict[int, list[Action]],
                        winfail: dict[int, list[tuple[int | None, Action]]]) -> list[str]:
    problems = []
    if table != list(LEVEL_MUSIC_TABLE):
        diff = [level for level in range(max(len(table), len(LEVEL_MUSIC_TABLE)))
                if level >= len(table) or level >= len(LEVEL_MUSIC_TABLE) or table[level] != LEVEL_MUSIC_TABLE[level]]
        problems.append(f'§2 table differs from timeline.LEVEL_MUSIC_TABLE at levels {diff[:10]}')
    rows = [(level, action) for level, actions in story.items() for action in actions]
    rows += [(level, action) for level, entries in winfail.items() for _code, action in entries]
    for level, action in rows:
        if action.kind == 'opening_music' and action.track != level_table_track(level):
            problems.append(f'§4 level {level:03d}: LVL→{action.track} but the table gives {level_table_track(level)}')
        if action.kind == 'default_level_music' and action.track != level_table_track(int(action.arg)):
            problems.append(f'§4 level {level:03d}: DEF({action.arg})→{action.track} but the table gives {level_table_track(int(action.arg))}')
    return problems


def _event_action(event: dict, section: int, action: int, total: int) -> Action:
    kind = str(event['kind'])
    arg = int(str(event['args'][0]).strip()) if kind in ('music_track', 'default_level_music') and event.get('args') else None
    track = event.get('track') if kind in MUSIC_KINDS else None
    return Action(kind, arg, track, section, action, total)


def _stream_problems(where: str, event: dict) -> list[str]:
    if event['kind'] not in MUSIC_KINDS:
        return []
    track = event.get('track')
    if not isinstance(track, int):
        return [f'{where}: {event["id"]} carries no resolved track']
    if event.get('stream') != music_stream(track):
        return [f'{where}: {event["id"]} streams {event.get("stream")!r}, track {track} is {music_stream(track)!r}']
    return []


def _story_positions(seed: dict) -> dict[int, tuple[int, int, int]]:
    """timeline._action_chain_from_seed numbers STORY actions across sections; -> (section, action, count)."""
    positions: dict[int, tuple[int, int, int]] = {}
    cumulative = 0
    for section in seed['scripts']['story']['sections']:
        actions = section.get('actions', [])
        for local in range(len(actions)):
            positions[cumulative] = (int(section.get('index', 0)), local, len(actions))
            cumulative += 1
    return positions


def _ir_positions(ir: dict) -> dict[int, tuple[int, int, int]]:
    counts: dict[int, set[int]] = {}
    for action in ir['action_chain']:
        counts.setdefault(int(action['section_index']), set()).add(int(action['action_index']))
    return {int(action['action_index']): (int(action['section_index']), int(action['action_index']),
                                          len(counts[int(action['section_index'])])) for action in ir['action_chain']}


def _chain_entries(section: dict) -> list[tuple[int, int, int]]:
    actions = section.get('actions', [])
    return [(int(section.get('index', 0)), local, len(actions)) for local, action in enumerate(actions) for _ in action.get('chain', [])]


def _program_positions(seed: dict, program: dict) -> list[tuple[int, int, int]]:
    """scenario.status_timelines / story_scene._select_event_timelines number a program's
    events by flat chain index over its section (and the actTRUE event sections a select
    chain splices after it, without their first command)."""
    sections = [section for section in seed['scripts']['winfail']['sections']
                if str(section.get('name', '')) == program['section']
                and (int(section['codes'][0]) if section.get('codes') else 0) == int(program['code'])]
    if not sections:
        raise ValueError(f'no winfail section {program["section"]} {program["code"]} in the seed')
    entries = _chain_entries(sections[-1])  # both builders keep the last section of a key
    events = {int(section['codes'][0]): section for section in seed['scripts']['winfail']['sections']
              if str(section.get('name', '')) == 'event' and section.get('codes')}
    for code in program.get('chained_event_codes', []):
        entries += _chain_entries(events[int(code)])[1:]
    return entries


@dataclasses.dataclass
class Row:
    level: int
    scene: str
    script: str
    actual: list[Action]
    expected: list[Action] | None     # None: authored, nothing to compare
    problems: list[str]


def _seed_for(root: Path, scene: dict, level: int) -> dict:
    path = str(scene.get('resources', {}).get('battle_seed', '')).removeprefix('res://') or f'{SEEDS}/battle{level:03d}_seed.json'
    return _load(root / path)


def _compare(where: str, actual: list[Action], expected: list[Action]) -> list[str]:
    problems = []
    if [a.key() for a in actual] != [e.key() for e in expected]:
        problems.append(f'{where}: events {[a.label() for a in actual]} vs §4 {[e.label() for e in expected]}')
    for a, e in zip(actual, expected):
        if e.total is not None and a.total != e.total:
            problems.append(f'{where}: {a.label()} sits in a section of {a.total} actions, §4 counts {e.total}')
    return problems


def survey(root: Path) -> dict:
    text = (root / PACKET).read_text(encoding='utf-8')
    table = packet_table(text)
    story_rows, winfail_rows = packet_rows(text)
    problems = _packet_consistency(table, story_rows, winfail_rows)
    campaign = _load(root / CAMPAIGN)['battles']
    rows: list[Row] = []
    counts = dict(scenes=0, music=0, movie=0, table=0, authored=0, winfail=0)
    scene_levels: set[int] = set()
    for key in sorted(campaign, key=int):
        path = str(campaign[key]['scenario']).removeprefix('res://')
        if not path.endswith('.json'):
            continue  # 998 GameClearScreen.tscn: the clear epilogue is not a script scene (§3.5)
        scene = _load(root / path)
        level = int(scene['level'])
        name = Path(path).name
        counts['scenes'] += 1
        scene_levels.add(level)
        authored = scene.get('status') == 'authored'
        seed = _seed_for(root, scene, level)
        scene_problems: list[str] = []
        if scene.get('level_table_music') != level_table_music(level):
            scene_problems.append(f'{name}: level_table_music {scene.get("level_table_music")!r}, the table gives {level_table_music(level)!r}')
        else:
            counts['table'] += 1
        # The opening (STORY) timeline.
        timeline = _load(root / str(scene['resources']['opening_timeline']).removeprefix('res://'))
        positions = _story_positions(seed)
        actual = []
        for event in timeline['events']:
            if event.get('kind') in KINDS:
                actual.append(_event_action(event, *positions[int(event['source_action_index'])]))
                scene_problems += _stream_problems(name, event)
        counts['music'] += sum(a.kind != MOVIE for a in actual)
        counts['movie'] += sum(a.kind == MOVIE for a in actual)
        script = str(timeline.get('source_script', f'story{level:03d}')).upper()
        if authored:
            counts['authored'] += 1
            expected = None
        else:
            expected = story_rows.get(level, [])
            scene_problems += _compare(f'{name} {script}', actual, expected)
        rows.append(Row(level, name, script, actual, expected, scene_problems))
        # The winfail programs: status timelines and select-event branches (one event may be in both).
        programs = [*scene.get('scenario_rules', {}).get('status_timelines', {}).values(),
                    *scene.get('opening', {}).get('select_event_timelines', {}).values()]
        found: dict[tuple, tuple[int, Action]] = {}
        winfail_problems: list[str] = []
        for program in programs:
            entries = _program_positions(seed, program)
            for event in program['events']:
                if event.get('kind') in KINDS:
                    action = _event_action(event, *entries[int(event['source_action_index'])])
                    found[action.key()] = (int(program['code']), action)
                    winfail_problems += _stream_problems(f'{name} {program["section"]}_{program["code"]}', event)
        counts['music'] += sum(a.kind != MOVIE for _c, a in found.values())
        counts['movie'] += sum(a.kind == MOVIE for _c, a in found.values())
        expected_winfail = [] if authored else winfail_rows.get(level, [])
        if found or expected_winfail:
            actual_w = sorted((a for _c, a in found.values()), key=lambda a: (a.section, a.action))
            expected_w = sorted((a for _c, a in expected_winfail), key=lambda a: (a.section, a.action))
            where = f'{name} WINFAIL{level:03d}'
            if not authored:
                counts['winfail'] += len(expected_w)
                if [a.key() for a in actual_w] != [e.key() for e in expected_w]:
                    winfail_problems.append(f'{where}: events {[a.label() for a in actual_w]} vs §4 {[e.label() for e in expected_w]}')
                for code, e in expected_winfail:
                    hit = found.get(e.key())
                    if hit and code is not None and hit[0] != code:
                        winfail_problems.append(f'{where}: {e.label()} is in event {hit[0]}, §4 names event {code}')
                    if hit and e.total is not None and hit[1].total != e.total:
                        winfail_problems.append(f'{where}: {e.label()} sits in a section of {hit[1].total} actions, §4 counts {e.total}')
            rows.append(Row(level, name, f'WINFAIL{level:03d}', actual_w, None if authored else expected_w, winfail_problems))
    # The chapter-wide timeline the story051 script IR compiles to.
    chapter = _load(root / CHAPTER_TIMELINE)
    positions = _ir_positions(_load(root / CHAPTER_IR))
    actual = [_event_action(event, *positions[int(event['source_action_index'])]) for event in chapter['events'] if event.get('kind') in KINDS]
    chapter_problems = [p for event in chapter['events'] if event.get('kind') in KINDS for p in _stream_problems(CHAPTER_TIMELINE, event)]
    chapter_problems += _compare(f'{CHAPTER_TIMELINE} STORY051', actual, story_rows.get(51, []))
    rows.append(Row(51, CHAPTER_ROW, 'STORY051 (IR)', actual, story_rows.get(51, []), chapter_problems))
    without_scene = sorted(level for level in story_rows if level not in scene_levels)
    for row in rows:
        problems += row.problems
    return dict(table=table, rows=rows, counts=counts, without_scene=without_scene, story_rows=story_rows,
                winfail_rows=winfail_rows, problems=problems)


def check(root: Path) -> str:
    result = survey(root)
    if result['problems']:
        shown = '; '.join(result['problems'][:8])
        raise ValueError(f'{len(result["problems"])} mismatch(es): {shown}')
    counts = result['counts']
    story_scripts = sum(1 for row in result['rows'] if row.script.startswith('STORY') and row.expected is not None
                        and row.scene != CHAPTER_ROW)
    return (f'LEVEL_MUSIC_PASS scenes={counts["scenes"]} table_levels={len(result["table"])} story_scripts={story_scripts} '
            f'winfail_rows={counts["winfail"]} chapter_timeline=1 music_events={counts["music"]} movie_events={counts["movie"]} '
            f'level_table_music={counts["table"]} authored={counts["authored"]} rows_without_scene={len(result["without_scene"])} mismatches=0')


def table(root: Path) -> str:
    result = survey(root)
    lines = ['level | scene | script | scene events (position: track) | §4 | load plays | result']
    for row in sorted(result['rows'], key=lambda r: (r.level, r.script)):
        actual = ' → '.join(a.label() for a in row.actual) or '（无放乐动作）'
        if row.expected is None:
            expected = '（自制关，无原版行）' if row.script.startswith('STORY') else '—'
        else:
            expected = ' → '.join(e.label() for e in row.expected) or '（无）'
        load = level_table_track(row.level)
        load_text = f'{load:02d}' if load >= 0 else '静音'
        verdict = 'MISMATCH' if row.problems else ('listed' if row.expected is None else 'ok')
        lines.append(f'{row.level:03d} | {row.scene} | {row.script} | {actual} | {expected} | {load_text} | {verdict}')
    for level in result['without_scene']:
        lines.append(f'{level:03d} | （无场景） | STORY{level:03d} | — | '
                     + ' → '.join(e.label() for e in result['story_rows'][level]) + ' | — | row_without_scene')
    try:
        lines.append(check(root))
    except ValueError as error:
        lines.append(f'LEVEL_MUSIC_FAIL {error}')
    return '\n'.join(lines)


class LevelMusicTask(CheckTask):
    name = 'level_music'
    family = 'checks'
    inputs = (PACKET, 'content/battles/', 'content/imported/hsl/chapter01/', SEEDS + '/', 'content/generated/hsl/authored/')
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/level_music.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[LevelMusicTask]:
    return [LevelMusicTask()]


if __name__ == '__main__':
    import sys
    from hsltools.paths import ROOT
    if '--table' in sys.argv:
        print(table(ROOT))
    else:
        try:
            print(check(ROOT))
        except ValueError as error:
            print(f'LEVEL_MUSIC_FAIL {error}', file=sys.stderr)
            raise SystemExit(1)
