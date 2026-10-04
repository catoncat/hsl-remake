#!/usr/bin/env python3
"""Level atlas: per-level reference material for whoever designs levels, kept in the project local reference directory.

  python3 tools/hsl_level_atlas.py capture  [--levels 51,1,501] [--out DIR] [--screen N]
  python3 tools/hsl_level_atlas.py assemble [--out DIR]
  python3 tools/hsl_level_atlas.py build    [--levels ...] [--out DIR] [--screen N]   capture, then assemble

capture runs the windowed driver tests/capture_level_atlas.gd for all the levels in one Godot process
(one window on the built-in screen, events injected inside the engine; the keyboard focus the window takes
on opening is handed back to the app that had it), retries a failed level once in its own process, and
keeps the raw output in DIR/_capture/LEVELnnn/ (map.png, opening.png, units.json, godot.log) plus
DIR/_capture/summary.json. Without --levels it takes every original
battle and story scene in content/battles/campaign.json (not the authored sequel level, not the ending
screen). assemble reads only those captures and repository data and rebuilds the per-level folders,
README.md and index.html in seconds. DIR defaults to the primary checkout ignored/level-atlas; the material is original-derived and
never enters Git (CONTRIBUTING §5). Godot runs with HOME under ignored/ so no real save is
touched; on macOS the run holds a caffeinate -i assertion.
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN = ROOT / 'content/battles/campaign.json'
DRIVER = 'res://tests/capture_level_atlas.gd'
SEQUEL_LEVELS = {200}
CELL = 32
LEVEL_TIMEOUT = 330
## Opening choices taken by row (0-based). 曼多力亞 對峙 (LEVEL900): the first row hands the scene to the
## story without a battle, the second opens the battle. A choice not listed is captured as it stands.
OPENING_CHOICE = {900: 1}


def default_out() -> Path:
    common = subprocess.check_output(
        ['git', '-C', str(ROOT), 'rev-parse', '--path-format=absolute', '--git-common-dir'],
        text=True,
    ).strip()
    return Path(common).parent / 'ignored' / 'level-atlas'


def campaign_levels() -> dict[int, dict]:
    battles = json.loads(CAMPAIGN.read_text(encoding='utf-8'))['battles']
    levels = {}
    for key, entry in battles.items():
        level = int(key)
        if level in SEQUEL_LEVELS or not str(entry.get('scenario', '')).endswith('.json'):
            continue
        levels[level] = entry
    return levels


def builtin_screen() -> int:
    """Godot screen index of the built-in display: screen 0 is the main display, so a built-in panel
    that is not the main display is screen 1 when exactly two are attached (macOS only)."""
    if sys.platform != 'darwin':
        return 0
    try:
        text = subprocess.run(['system_profiler', 'SPDisplaysDataType'], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return 0
    blocks = re.split(r'\n(?=        \S[^\n]*:\n)', text)
    displays = [b for b in blocks if 'Resolution:' in b]
    internal = [b for b in displays if 'Internal' in b or 'Built-in' in b]
    if len(displays) == 2 and internal and 'Main Display: Yes' not in internal[0]:
        return 1
    return 0


def frontmost_app() -> str | None:
    """Bundle path of the frontmost macOS app. Godot activates itself when its window opens (also under
    `open -g`), taking the keyboard focus from whatever the user is typing in; it is handed back."""
    if sys.platform != 'darwin':
        return None
    try:
        asn = subprocess.run(['lsappinfo', 'front'], capture_output=True, text=True, timeout=5).stdout.strip()
        info = subprocess.run(['lsappinfo', 'info', '-only', 'pid', asn], capture_output=True, text=True, timeout=5).stdout
        pid = re.search(r'(\d+)\s*$', info.strip())
        comm = subprocess.run(['ps', '-o', 'comm=', '-p', pid.group(1)], capture_output=True, text=True, timeout=5).stdout if pid else ''
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.match(r'(.+?\.app)/', comm.strip())
    return match.group(1) if match else None


def run_batch(levels: list[int], target: Path, screen: int, env: dict, app: str | None, slot: int = 0, mode: str = 'levels') -> dict[int, dict]:
    """One Godot process captures `levels` in turn into target/LEVELnnn (one window, one focus grab,
    handed back at once). Returns, for each level the process reached, its verdict line, log segment
    and seconds; a level silent for LEVEL_TIMEOUT seconds gets the process killed by its own PID."""
    cmd = [os.environ.get('GODOT_BIN') or shutil.which('godot') or 'godot', '--path', str(ROOT), '--script', DRIVER,
           '--resolution', '640x480', '--screen', str(screen), '--always-on-top', '--',
           f"--levels={','.join(str(level) for level in levels)}", f'--out={target}', f'--slot={slot}', f'--mode={mode}']
    choices = [f'{level}:{row}' for level, row in OPENING_CHOICE.items() if level in levels]
    if choices:
        cmd.append('--choice=' + ','.join(choices))
    proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines: queue.Queue = queue.Queue()
    threading.Thread(target=lambda: [lines.put(line) for line in proc.stdout] + [lines.put(None)], daemon=True).start()
    results: dict[int, dict] = {}
    current, began, killed = None, time.time(), False
    while True:
        try:
            line = lines.get(timeout=5)
        except queue.Empty:
            if current is not None and not killed and time.time() - began > LEVEL_TIMEOUT:
                results[current]['verdict'] = f'LEVEL_ATLAS_FAIL level={current} timed out after {LEVEL_TIMEOUT} s'
                proc.kill()
                killed = True
            continue
        if line is None:
            break
        line = line.rstrip('\n')
        if line.startswith('LEVEL_ATLAS_WINDOW_READY') and app:
            subprocess.run(['open', '-a', app], capture_output=True)
        elif line.startswith('LEVEL_ATLAS_BEGIN'):
            current, began = int(line.split('level=')[1]), time.time()
            results[current] = {'verdict': '', 'log': [], 'seconds': 0.0}
            continue
        elif line.startswith('LEVEL_ATLAS_DONE'):
            current = None
        if current is None:
            continue
        results[current]['log'].append(line)
        if line.startswith(('LEVEL_ATLAS_PASS', 'LEVEL_ATLAS_FAIL')) and not results[current]['verdict']:
            results[current]['verdict'] = line
            results[current]['seconds'] = round(time.time() - began, 1)
    proc.wait()
    for level, result in results.items():
        result['verdict'] = result['verdict'] or f'LEVEL_ATLAS_FAIL level={level} process ended (exit {proc.returncode})'
        log = '\n'.join(result.pop('log'))
        (target / f'LEVEL{level:03d}' / 'godot.log').write_text(log + '\n', encoding='utf-8')
        result['script_errors'] = log.count('SCRIPT ERROR')
        result['errors'] = sum(1 for row in log.splitlines() if row.startswith('ERROR:'))
        result['ok'] = result['verdict'].startswith('LEVEL_ATLAS_PASS') and not result['script_errors'] and not result['errors']
        print(f"LEVEL{level:03d} {mode} seconds={result['seconds']} script_errors={result['script_errors']} errors={result['errors']} {result['verdict']}", flush=True)
    return results


def capture_phase(levels: list[int], target: Path, mode: str, screen: int, jobs: int, env: dict, app: str | None) -> list[int]:
    """Captures `levels` in `jobs` lanes (one Godot process each, windows staggered), retries a failed
    level once in its own process, merges the results into target/summary.json; returns the failed."""
    for level in levels:
        folder = target / f'LEVEL{level:03d}'
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    started = time.time()
    outcome: dict[int, dict] = {}

    def lane(slot: int, mine: list[int]) -> None:
        pending = list(mine)
        while pending:  # a crash or a hang ends the process: the rest goes on in a new one
            results = run_batch(pending, target, screen, env, app, slot, mode)
            if not results:
                break
            outcome.update(results)
            pending = [level for level in pending if level not in results]

    lanes = [threading.Thread(target=lane, args=(slot, levels[slot::jobs])) for slot in range(max(1, jobs)) if levels[slot::jobs]]
    for thread in lanes:
        thread.start()
    for thread in lanes:
        thread.join()
    for level in [level for level in levels if not outcome.get(level, {}).get('ok')]:
        print(f'LEVEL{level:03d} {mode} retry in its own process', flush=True)
        outcome.update(run_batch([level], target, screen, env, app, 0, mode))
    path = target / 'summary.json'
    summary = read_json(path) if path.exists() else {'results': {}}
    summary['results'].update({str(k): v for k, v in outcome.items()})
    summary['failed'] = sorted(int(k) for k, v in summary['results'].items() if not v.get('ok'))
    summary['last_run'] = {'levels': levels, 'seconds': round(time.time() - started), 'jobs': jobs}
    for stale in ('levels', 'seconds'):
        summary.pop(stale, None)
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=1), encoding='utf-8')
    failed = [level for level in levels if not outcome.get(level, {}).get('ok')]
    print(f'LEVEL_ATLAS_CAPTURE {"PASS" if not failed else "FAIL"} mode={mode} levels={len(levels)} failed={failed} seconds={round(time.time() - started)}', flush=True)
    return failed


def capture(levels: list[int], maps: list[int], out: Path, screen: int, jobs: int = 1) -> int:
    """`levels` get the battle／story renders (out/_capture), `maps` the clean map (out/_capture/clean)."""
    env = dict(os.environ, HOME=str(ROOT / 'ignored/atlas-home'), HSL_SELF_HEAL='1', HSL_RNG_SEED=os.environ.get('HSL_RNG_SEED', '1'))
    env.pop('__CFBundleIdentifier', None)  # as tools/godot.sh: the window is its own app, not the terminal's
    Path(env['HOME']).mkdir(parents=True, exist_ok=True)
    imported = subprocess.run([str(ROOT / 'tools/godot.sh'), '--headless', '--import'], cwd=ROOT,
                              capture_output=True, text=True)
    if imported.returncode != 0:
        sys.stderr.write(imported.stdout[-4000:] + imported.stderr[-4000:])
        print('LEVEL_ATLAS_CAPTURE_FAIL import')
        return 1
    app = frontmost_app()
    failed = capture_phase(levels, out / '_capture', 'levels', screen, jobs, env, app) if levels else []
    failed += capture_phase(maps, out / '_capture' / 'clean', 'clean', screen, jobs, env, app) if maps else []
    return 0 if not failed else 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['capture', 'assemble', 'build'])
    parser.add_argument('--levels', help='comma-separated level numbers (default: every original battle and story scene)')
    parser.add_argument('--out', type=Path, default=default_out(), help='atlas directory (default primary checkout ignored/level-atlas)')
    parser.add_argument('--screen', type=int, help='Godot screen index for the capture window (default: the built-in display)')
    parser.add_argument('--jobs', type=int, default=1, help='Godot processes capturing in parallel, windows staggered (default 1)')
    parser.add_argument('--only', choices=['levels', 'maps'], help='capture only the per-level renders, or only the clean maps (default both)')
    args = parser.parse_args(argv)
    out = args.out.expanduser()
    known = campaign_levels()
    levels = sorted(known) if not args.levels else [int(x) for x in args.levels.split(',') if x.strip()]
    unknown = [level for level in levels if level not in known]
    if unknown:
        parser.error(f'not an original campaign entry: {unknown}')
    if args.command in ('capture', 'build'):
        if sys.platform == 'darwin' and shutil.which('caffeinate') and not os.environ.get('HSL_ATLAS_CAFFEINATED'):
            os.environ['HSL_ATLAS_CAFFEINATED'] = '1'
            os.execvp('caffeinate', ['caffeinate', '-i', sys.executable, *sys.argv])
        groups = Atlas(out).map_groups()
        maps = [group['first'] for group in groups if set(group['levels']) & set(levels)]
        code = capture([] if args.only == 'maps' else levels, [] if args.only == 'levels' else maps, out,
                       builtin_screen() if args.screen is None else args.screen, args.jobs)
        if args.command == 'capture':
            return code
        return assemble(out) or code
    return assemble(out)


# ---------------------------------------------------------------- assemble

SCRIPT_MD = ROOT / 'docs/internal/ORIGINAL_SCRIPT.md'
LEVELS_MD = ROOT / 'docs/ORIGINAL_LEVELS.md'
OVERVIEW_MD = ROOT / 'docs/evidence_packets/resource_inventory/campaign_overview.md'
CORPUS = ROOT / 'content/imported/hsl/story_corpus/scripts'
CHAPTER = ROOT / 'content/imported/hsl/chapter01'
ACTOR_PANELS = ROOT / 'content/generated/hsl/roles/actor_panels.json'
SHAPEDEF = ROOT / 'content/imported/hsl/global/tables/SHAPEDEF.TXT'
GENERATED = ('地图原图', '剧情战', '遭遇战', '过场', '_thumbs', 'README.md', 'index.html')
## Kept in 整图.png but worth a look: water／lava surfaces, waterfalls, shadows, additive still objects, chests.
UNCERTAIN_KINDS = ('mapobjWaterMove', 'mapobjWaterFall', 'mapobjShadow', 'mapobjNextShape', 'mapobjNextShape2', 'mapobjBuildBottom')
SIDE = {'player_controlled': '我', 'friendly_ai': '友', 'enemy_ai': '敌'}
SIDE_ORDER = {'我': 0, '友': 1, '敌': 2}
SIDE_RGB = {'我': (60, 130, 255), '友': (60, 210, 90), '敌': (240, 50, 50)}
CHECKS = ('actTRUE', 'actFALSE', 'actDetectRoundDispDisp')
UNIT_INSERTS = ('actInsertObject', 'actInsertObjectRandomPos', 'actInsertRandomObject')
FONTS = (ROOT / 'game/assets/fonts/NotoSansSC-UI.woff2', Path('/System/Library/Fonts/STHeiti Medium.ttc'),
         Path('/System/Library/Fonts/Hiragino Sans GB.ttc'), Path('/System/Library/Fonts/PingFang.ttc'),
         Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'), Path('C:/Windows/Fonts/msyh.ttc'))


def read_json(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding='utf-8'))


def res(path: str) -> Path:
    return ROOT / str(path).replace('res://', '')


def safe(text: str) -> str:
    """Folder-name form: no ASCII or full-width spaces, no path separators."""
    text = re.sub(r'\s*·\s*', '・', text)
    return re.sub(r'[\s\u3000/\\:]+', '_', text).strip('_')


def script_sections() -> tuple[dict[int, tuple[str, str]], list[int]] | None:
    if not SCRIPT_MD.exists():
        return None
    text = SCRIPT_MD.read_text(encoding='utf-8')
    starts = [m.start() for m in re.finditer(r'^## ', text, re.M)]
    sections, order = {}, []
    for m in re.finditer(r'^## (.+?)（LEVEL(\d+)）[ \t]*$', text, re.M):
        end = next((s for s in starts if s > m.start()), len(text))
        body = re.sub(r'(\s*<!--.*?-->)+\s*$', '', text[m.start():end].rstrip())
        sections[int(m.group(2))] = (m.group(1), body)
        order.append(int(m.group(2)))
    return sections, order


def level_table() -> dict[int, dict]:
    """ORIGINAL_LEVELS appendix: one row per story battle (map, opening sides, win, fail, counts)."""
    rows = {}
    if LEVELS_MD.exists():
        for line in LEVELS_MD.read_text(encoding='utf-8').splitlines():
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            m = re.search(r'（LEVEL(\d+)）$', cells[0]) if len(cells) == 7 else None
            if m:
                rows[int(m.group(1))] = dict(zip(('map', 'sides', 'win', 'fail', 'inserts', 'events'), cells[1:]))
    return rows


def overview_next() -> dict[int, int]:
    nxt = {}
    if OVERVIEW_MD.exists():
        for m in re.finditer(r'^\| (\d+) \|[^|]*\|[^|]*\|[^|]*\| → (\d+) \|', OVERVIEW_MD.read_text(encoding='utf-8'), re.M):
            nxt[int(m.group(1))] = int(m.group(2))
    return nxt


def sid_actors() -> dict[str, str]:
    table, code = {}, None
    if SHAPEDEF.exists():
        for line in SHAPEDEF.read_bytes().decode('latin-1').splitlines():
            line = line.split(';')[0].strip()
            m = re.match(r'code\s*=\s*(\S+)', line)
            if m:
                code = m.group(1)
                continue
            m = re.match(r'stand\s*=\s*SHAPE\\(\d+)-', line, re.I)
            if m and code and code not in table:
                table[code] = m.group(1)
    return table


class Atlas:
    def __init__(self, out: Path):
        self.out = out
        self.levels = campaign_levels()
        self.scenarios = {lv: read_json(res(e['scenario'])) for lv, e in self.levels.items()}
        self.panels = read_json(ACTOR_PANELS)['actors'] if ACTOR_PANELS.exists() else {}
        self.sids = sid_actors()
        self.table = level_table()
        self.script = script_sections()
        self.font_path = next((p for p in FONTS if p.exists() and self._font_ok(p)), None)
        self.inserted: list[int] = []
        self._map_keys: dict[str, str] = {}
        self._groups: list[dict] | None = None

    def map_key(self, level: int) -> str:
        """Identity of a map picture: its backdrop pixels (two files with the same pixels are one map)."""
        texture = self.map_texture(level)
        if texture not in self._map_keys:
            import hashlib
            from PIL import Image
            image = Image.open(res(texture)).convert('RGBA')
            self._map_keys[texture] = hashlib.md5(repr(image.size).encode() + image.tobytes()).hexdigest()
        return self._map_keys[texture]

    def map_groups(self) -> list[dict]:
        """Distinct map pictures in the order play first meets them (mainline, then encounters); the
        first level using one names its 地图原图 folder and is the one its clean map is taken from."""
        if self._groups is None:
            groups: dict[str, dict] = {}
            for level in self.play_order() + sorted(lv for lv in self.levels if self.kind(lv) == '遭遇战'):
                groups.setdefault(self.map_key(level), {'key': self.map_key(level), 'first': level, 'levels': []})['levels'].append(level)
            self._groups = list(groups.values())
        return self._groups

    def map_group(self, level: int) -> dict:
        return next(group for group in self.map_groups() if group['key'] == self.map_key(level))

    def map_folder(self, level: int) -> str:
        first = self.map_group(level)['first']
        return f'地图原图/{safe(self.name(first))}_LEVEL{first:03d}'

    @staticmethod
    def _font_ok(path: Path) -> bool:
        from PIL import ImageFont
        try:
            ImageFont.truetype(str(path), 11)
            return True
        except OSError:
            return False

    # ---- naming and order
    def kind(self, level: int) -> str:
        if self.levels[level].get('kind') == 'story':
            return '过场'
        return '遭遇战' if 501 <= level <= 578 else '剧情战'

    def name(self, level: int) -> str:
        if self.script and level in self.script[0]:
            return self.script[0][level][0]
        return re.sub(r'(\s*·.*|[\s\u3000]*遭遇戰)$', '', str(self.levels[level].get('title', f'LEVEL{level:03d}')))

    def map_texture(self, level: int) -> str:
        return str(self.scenarios[level].get('resources', {}).get('map_texture', ''))

    def grid(self, level: int) -> tuple[int, int]:
        terrain = self.scenarios[level].get('resources', {}).get('terrain', '')
        if terrain and res(terrain).exists():
            fmt = read_json(res(terrain)).get('source_format', {})
            return int(fmt.get('width', 0)), int(fmt.get('height', 0))
        return 0, 0

    def play_order(self) -> list[int]:
        mainline = [lv for lv in self.levels if self.kind(lv) != '遭遇战']
        if not self.script:
            return mainline
        order = [lv for lv in self.script[1] if lv in self.levels and self.kind(lv) != '遭遇战']
        nxt = overview_next()
        for lv in mainline:
            if lv not in order:
                before = next((src for src, dst in nxt.items() if dst == lv and src in order), None)
                order.insert(order.index(before) + 1 if before is not None else len(order), lv)
                self.inserted.append(lv)
        return order

    def owner_of_map(self, level: int) -> int | None:
        texture = self.map_texture(level)
        owners = sorted(lv for lv in self.levels if self.kind(lv) == '剧情战' and self.map_texture(lv) == texture)
        return owners[0] if owners else None

    # ---- labels
    def actor_label(self, actor_id: str, short: bool = False) -> str:
        row = self.panels.get(str(actor_id), {})
        name, title = str(row.get('name', '')), str(row.get('title', ''))
        if name and name != '???':
            return name if short or not title or title == name else f'{name}（{title}）'
        return title or f'{actor_id} 号'

    def token(self, token: str, templates: dict) -> str:
        if token in templates:
            actor = templates[token].get('actor', {})
            return f"{self.actor_label(actor.get('actor_id', ''), True)}（{actor.get('actor_id', '')} 号）"
        if token.startswith('SID_') and not token[4:].isascii():
            return token[4:]
        actor_id = self.sids.get(token) or (re.fullmatch(r'SID_ENEMY(\d{3})', token) or [None, None])[1]
        if actor_id:
            return f'{self.actor_label(actor_id, True)}（{actor_id} 号）' if self.panels.get(actor_id, {}).get('title') else f'{actor_id} 号'
        return {'-1': '任何人', '0': self.actor_label('001', True)}.get(token, token)

    @staticmethod
    def cell(x: str, y: str) -> str:
        try:
            return f'({int(x) // CELL},{int(y) // CELL})'
        except ValueError:
            return f'({x},{y})'

    def cell_rect(self, args: list[str]) -> str:
        if len(args) < 4:
            return ' '.join(args)
        first, last = self.cell(args[-4], args[-3]), self.cell(args[-2], args[-1])
        return first if first == last else f'{first}–{last}'

    def condition(self, name: str, a: list[str], templates: dict) -> str:
        tok = lambda t: self.token(t, templates)  # noqa: E731
        try:
            if name == 'actTRUE':
                return '无条件（武装即成立）'
            if name == 'actCheckRoundNumber':
                return f'第 {a[0]} 回合起'
            if name == 'actCheckEnemyTotalNumber':
                return '敌全灭' if a[0] == '0' else f'敌方剩 ≤{a[0]} 名'
            if name == 'actCheckPlayerTotalNumber':
                return f'我方剩 ≤{a[0]} 名'
            if name == 'actCheckEnemyNumber':
                return f'{tok(a[0])}少于 {a[1]} 名'
            if name in ('actCheckPlayer', 'actCheckEnemy'):
                return '、'.join(tok(t) for t in a[1:]) + ('全部倒下' if len(a) > 2 else '倒下')
            if name == 'actCheckPlayerHPLow':
                return f'{tok(a[0])} HP ≤{a[-1]}%'
            if name == 'actCheckPlayerArrivePos':
                return f'{tok(a[0])}到达 {self.cell_rect(a)}'
            if name == 'actCheckAnyPlayerArrivePos':
                return f'任一我方到达 {self.cell_rect(a)}'
            if name == 'actCheckPlayerAttacked':
                return f'{tok(a[0])}攻击{tok(a[1])}'
            if name == 'actCheckSerialPlayerAttacked':
                return f'{tok(a[0])}第 {a[1]} 名被攻击'
            if name == 'actCheckNotPlayerAttacker':
                return f'攻击者不是{tok(a[0])}'
            if name == 'actCheckEventNotExist':
                return f'事件 {"、".join(a)} 都已结束'
        except IndexError:
            pass
        return f'`{name},{",".join(a)}`'

    # ---- winfail reading
    @staticmethod
    def split(section: dict) -> tuple[list[dict], list[dict]]:
        conds, acts = [], []
        for action in section.get('actions', []):
            for step in action.get('chain', []):
                if not acts and (step['name'].startswith('actCheck') or step['name'] in CHECKS):
                    conds.append(step)
                else:
                    acts.append(step)
        return conds, acts

    def scripts(self, level: int) -> tuple[dict, dict]:
        story = CORPUS / f'STORY{level:03d}.json'
        winfail = CORPUS / f'WINFAIL{level:03d}.json'
        return (read_json(story) if story.exists() else {}), (read_json(winfail) if winfail.exists() else {})

    def armers(self, story: dict, winfail: dict, templates: dict) -> dict[tuple[str, int], list[str]]:
        found: dict[tuple[str, int], list[str]] = {}
        for source, doc in (('开场', story), ('', winfail)):
            for section in doc.get('sections', []):
                conds, acts = self.split(section)
                where = source or f"{ {'win': '胜利', 'fail': '失败', 'event': '事件'}.get(section['name'], section['name'])} {','.join(section.get('codes', []))}"
                when = '、'.join(self.condition(c['name'], c['args'], templates) for c in conds)
                for step in acts:
                    kind = {'actInsertWinStatus': 'win', 'actInsertFailStatus': 'fail', 'actInsertEventStatus': 'event'}.get(step['name'])
                    if kind and step['args'] and step['args'][0].lstrip('-').isdigit():
                        label = where if source else f'{where}（{when}）' if when else where
                        found.setdefault((kind, int(step['args'][0])), []).append(label)
        return found

    def boards(self, winfail: dict) -> dict[int, str]:
        texts: dict[int, list[str]] = {}
        for message in winfail.get('messages', []):
            if message.get('board_label'):
                speaker = message.get('speaker_name', '')
                texts.setdefault(int(message['section_index']), []).append(f"{speaker}：{message['text']}" if speaker else message['text'])
        return {k: ' ／ '.join(v) for k, v in texts.items()}

    def describe_battle(self, level: int, capture: dict, folder_rel: str) -> str:
        scenario = self.scenarios[level]
        templates = scenario.get('script_actor_templates') or {}
        story, winfail = self.scripts(level)
        armers = self.armers(story, winfail, templates)
        boards = self.boards(winfail)
        w, h = self.grid(level)
        kind = self.kind(level)
        lines = [f'# {self.heading(level)}', '']
        px = capture.get('map_px', [w * CELL, h * CELL])
        extra = '' if px == [w * CELL, h * CELL] else f'；底图是 {px[0]}×{px[1]} px，比格子多出的部分不在格子里，图按底图原尺寸出'
        lines += [f'- 类型：{kind}', f'- 地图：{w}×{h} 格（{w * CELL}×{h * CELL} px{extra}）', f"- 场景文件：`{self.levels[level]['scenario'].replace('res://', '')}`"]
        if kind == '遭遇战':
            owner = self.owner_of_map(level)
            if owner is not None:
                lines.append(f'- 地图借用：{self.heading(owner)}')
        lines.append(f'- 地图原图（整图、地面层、地形）：`../../{self.map_folder(level)}/`')
        row = self.table.get(level)
        if row:
            lines.append(f"- 胜利（一句话，取自 docs/ORIGINAL_LEVELS.md）：{row['win']}")
            lines.append(f"- 雷歐納德之外的失败：{row['fail']}")
        elif kind == '遭遇战':
            lines.append('- 胜利：全灭；失败：雷歐納德死亡（遭遇战一律如此，docs/ORIGINAL_LEVELS.md 1.2）')
        lines.append('- 站位是开场演完、谁都还没动时的布阵（关卡设计的初始站位）；等级是这次截图那一局的，敌人开场等级由随机流决定，实际每局可能不同'
                     + ('；我方是直接开这一关时场景文件给的名单，实际游玩时由当时的队伍上场' if kind == '遭遇战' or level not in (51, 52, 53, 1, 2) else ''))
        choice = capture.get('opening_choice')
        if choice and 'row' in choice:
            lines.append(f"- 开场有 {choice['options']} 选 1 的抉择，截图时取第 {choice['row'] + 1} 项（另一项不开战，直接交给剧情）")
        elif choice:
            lines.append(f"- 开场停在 {choice['options']} 选 1 的抉择上，这一关没有走到开战：图与表是抉择时的场面")
        ahead = self.acts_before(capture)
        if ahead:
            lines.append(f'- 第 1 回合比我方先动（按这一局各单位的速度）：{ahead}')
        lines += ['', '## 胜负条件', '']
        armed = {k: set(capture.get(f'{k}_statuses', [])) for k in ('win', 'fail', 'event')}
        if winfail:
            lines += ['| 状态 | 开局时 | 看板原文 | 判定 | 由谁武装 |', '| --- | --- | --- | --- | --- |']
            for section in winfail['sections']:
                if section['name'] not in ('win', 'fail'):
                    continue
                conds, _ = self.split(section)
                for code in section.get('codes', []) or ['?']:
                    code_i = int(code) if code.lstrip('-').isdigit() else -1
                    on = '已生效' if code_i in armed[section['name']] else '未生效（晚开）'
                    by = '；'.join(armers.get((section['name'], code_i), [])) or '—'
                    judge = ' 且 '.join(self.condition(c['name'], c['args'], templates) for c in conds) or '—'
                    label = {'win': '胜利', 'fail': '失败'}[section['name']]
                    lines.append(f"| {label} {code} | {on} | {boards.get(section['index'], '—')} | {judge} | {by} |")
        else:
            lines.append('（没有 WINFAIL 脚本）')
        lines += ['', f"## 开局单位（开场演完、谁都还没动时；在场 {capture.get('living_units', 0)} 名，图上画出 {capture.get('drawn_units', 0)} 名）", '']
        if not capture.get('opening_done', False) and not choice:
            lines += [f"> 这一关的开场没有演完（停在 `{json.dumps(capture.get('stopped_at', {}), ensure_ascii=False)[:200]}`），图与表是实际拍到的状态。", '']
        lines += ['| 阵营 | 名字 | 稱號 | 等级 | 格 (x,y) | 可操作 | 备注 |', '| --- | --- | --- | --- | --- | --- | --- |']
        first_movers = set(capture.get('acts_before_player', [])) if capture.get('player_in_queue') and capture.get('opening_done') else set()
        hidden: dict[str, list[dict]] = {}
        for unit in self.present_units(capture):
            if not unit['drawn']:
                hidden.setdefault(unit['actor_id'], []).append(unit)
                continue
            note = '第 1 回合比我方先动' if unit['id'] in first_movers else ''
            name = unit['name'] if unit['name'] and unit['name'] != '???' else '—'
            lines.append(f"| {SIDE.get(unit['role'], unit['role'])} | {name} | {unit['title'] or '—'} | {unit['level']} | ({unit['cell'][0]},{unit['cell'][1]}) | {'是' if unit['commandable'] else '否'} | {note} |")
        for actor_id, group in hidden.items():
            unit = group[0]
            cells = ' '.join(f"({u['cell'][0]},{u['cell'][1]})" for u in group)
            lines.append(f"| {SIDE.get(unit['role'], unit['role'])} | {actor_id} 号 ×{len(group)} | {unit['title'] or '—'} | {unit['level']} | {cells} | 否 | 图上不画单位，由地图物件表示（如船体）；标注图用细框、不标名字 |")
        lines += ['', '## 增援', '']
        inserts = self.reinforcements(winfail, templates, armers, armed)
        if inserts:
            grouped: dict[tuple, list[str]] = {}
            for (trigger, who, side, at, to), n in inserts:
                grouped.setdefault((trigger, who, side), []).extend([at if to == '—' else f'{at}→{to}'] * n)
            lines += ['| 触发 | 来的是谁 | 阵营 | 人数 | 出现格（→ 走到） |', '| --- | --- | --- | ---: | --- |']
            lines += [f"| {t} | {who} | {side} | {len(cells)} | {'；'.join(cells)} |" for (t, who, side), cells in grouped.items()]
            lines.append('')
            lines.append('格坐标在地图外（负数或超过格数）的，是从画面外飞入／走入。')
        else:
            lines.append('没有（WINFAIL 里没有插入单位的动作）。')
        lines += ['', '## 主要事件', '']
        events = [s for s in winfail.get('sections', []) if s['name'] == 'event']
        for section in events:
            conds, acts = self.split(section)
            code = ','.join(section.get('codes', []))
            when = ' 且 '.join(self.condition(c['name'], c['args'], templates) for c in conds) or '—'
            status = '开局已武装' if any(int(c) in armed['event'] for c in section.get('codes', []) if c.isdigit()) else '由 ' + ('；'.join(armers.get(('event', int(code)), [])) or '?') + ' 武装' if code.isdigit() else ''
            lines.append(f'- 事件 {code}（{status}）：{when} → {self.summarize(acts)}')
        if not events:
            lines.append('没有事件段。')
        lines += ['', '## 文件', '', '- `开局.png`、`标注.png`' + ('、`地图.png`' if kind == '剧情战' else ''), '- `台词.md`：台词全本对应一节' if kind == '剧情战' else '- 遭遇战没有对白', '- `脚本/`：原版脚本原件与编译后的 STORY／WINFAIL JSON', '']
        return '\n'.join(lines)

    @staticmethod
    def acts_before(capture: dict) -> str:
        """Round-1 actors ahead of the first commandable one, grouped by kind in queue order."""
        if 'acts_before_player' not in capture or not capture.get('player_in_queue') or not capture.get('opening_done'):
            return ''
        units = {u['id']: u for u in capture.get('units', [])}
        groups: dict[str, list[str]] = {}
        for uid in capture['acts_before_player']:
            unit = units.get(uid)
            if unit is None:
                groups.setdefault(uid, []).append('')
                continue
            label = unit['name'] if unit['name'] and unit['name'] != '???' else (unit['title'] or f"{unit['actor_id']} 号")
            groups.setdefault(f"{SIDE.get(unit['role'], '?')}·{label}", []).append('({},{})'.format(*unit['cell']))
        if not groups:
            return '没有，我方第一个行动'
        count = len(capture['acts_before_player'])
        return f'{count} 名，' + '、'.join(f'{k} {v[0]}' if len(v) == 1 else f'{k} ×{len(v)}' for k, v in groups.items())

    def present_units(self, capture: dict) -> list[dict]:
        units = [u for u in capture.get('units', []) if u.get('living')]
        return sorted(units, key=lambda u: (SIDE_ORDER.get(SIDE.get(u['role'], ''), 3), u['cell'][1], u['cell'][0]))

    def reinforcements(self, winfail: dict, templates: dict, armers: dict, armed: dict) -> list:
        rows: dict[tuple, int] = {}
        for section in winfail.get('sections', []):
            conds, acts = self.split(section)
            trigger = ' 且 '.join(self.condition(c['name'], c['args'], templates) for c in conds) or '—'
            codes = [int(c) for c in section.get('codes', []) if c.lstrip('-').isdigit()]
            if section['name'] == 'event' and codes and not any(c in armed['event'] for c in codes):
                by = '；'.join(armers.get(('event', codes[0]), []))
                trigger += f'（事件 {codes[0]} 由 {by} 武装）' if by else ''
            elif section['name'] in ('win', 'fail'):
                trigger = f"{ {'win': '胜利', 'fail': '失败'}[section['name']]}段：{trigger}"
            for index, step in enumerate(acts):
                if step['name'] not in UNIT_INSERTS or not step['args']:
                    continue
                template = templates.get(step['args'][0], {}).get('actor', {})
                who = self.token(step['args'][0], templates)
                side = SIDE.get(template.get('battle_actor_role', ''), '?')
                at = self.cell(step['args'][1], step['args'][2]) if len(step['args']) >= 3 else '随机'
                to = '—'
                for follow in acts[index + 1:]:
                    if follow['name'] in UNIT_INSERTS:
                        break
                    if follow['name'].startswith('actWalkPrevInsertObject') and len(follow['args']) >= 2:
                        to = self.cell(follow['args'][0], follow['args'][1])
                        break
                key = (trigger, who, side, at, to)
                rows[key] = rows.get(key, 0) + 1
        return list(rows.items())

    def summarize(self, acts: list[dict]) -> str:
        parts, other = [], []
        count = lambda pred: sum(1 for a in acts if pred(a['name']))  # noqa: E731
        lines = count(lambda n: n.startswith('actMessage'))
        if lines:
            parts.append(f'对白 {lines} 句')
        units = count(lambda n: n in UNIT_INSERTS)
        if units:
            parts.append(f'插入单位 {units} 名')
        props = count(lambda n: n.startswith('actInsertStoryObject'))
        if props:
            parts.append(f'演出物件 {props} 个')
        for step in acts:
            n, a = step['name'], step['args']
            if n == 'actInsertWinStatus':
                parts.append(f'武装胜利 {a[0]}')
            elif n == 'actInsertFailStatus':
                parts.append(f'武装失败 {a[0]}')
            elif n == 'actInsertEventStatus':
                parts.append(f'武装事件 {a[0]}')
            elif n == 'actDeleteEventStatus':
                parts.append(f'撤销事件 {a[0]}')
            elif n in ('actDeleteWinStatus', 'actDeleteFailStatus'):
                parts.append(f"撤销{'胜利' if 'Win' in n else '失败'} {a[0] if a else ''}")
            elif n == 'actSetNextPlayLevelEvent':
                parts.append(f'下一关 LEVEL{int(a[0]):03d}' if a and a[0].isdigit() else '下一关')
            elif n == 'actPlayerJobUpProcess':
                parts.append('转职')
            elif n.startswith('actWalkAndDelete') or n.startswith('actDeletePlayer') or n.startswith('actDeletePosPlayer'):
                parts.append('有单位离场') if '有单位离场' not in parts else None
            elif n in ('actSetPlayerMode', 'actSetPlayerUndead', 'actSetPlayerFixPos', 'actSetPlayerNoAttack'):
                other.append(n)
            elif not n.startswith(('actMessage', 'actInsertStoryObject', 'actDelay', 'actWalk')) and n not in UNIT_INSERTS:
                other.append(n)
        if other:
            unique = list(dict.fromkeys(other))
            parts.append('另有 ' + '、'.join(f'`{n}`' for n in unique[:6]) + (' 等' if len(unique) > 6 else ''))
        return '，'.join(parts) or '（只有演出）'

    # ---- folders
    def heading(self, level: int) -> str:
        n = self.numbers.get(level)
        name = self.name(level)
        if self.kind(level) == '剧情战' and n:
            return f'玩家第 {n} 场 · {name}（LEVEL{level:03d}）'
        if self.kind(level) == '过场':
            return f'{name}（LEVEL{level:03d}，过场，第 {self.after.get(level, 0)} 场之后）' if self.script else f'{name}（LEVEL{level:03d}，过场）'
        if self.kind(level) == '遭遇战':
            return f'{name} · 遭遇戰（LEVEL{level:03d}）'
        return f'{name}（LEVEL{level:03d}）'

    def folder(self, level: int) -> str:
        kind, name = self.kind(level), safe(self.name(level))
        if kind == '剧情战':
            return f'剧情战/第{self.numbers[level]:02d}场_{name}_LEVEL{level:03d}' if level in self.numbers else f'剧情战/{name}_LEVEL{level:03d}'
        if kind == '过场':
            return f'过场/第{self.after.get(level, 0):02d}场后_{name}_LEVEL{level:03d}' if self.script else f'过场/{name}_LEVEL{level:03d}'
        owner = self.owner_of_map(level)
        return f'遭遇战/{safe(self.name(owner)) if owner else name}_LEVEL{level:03d}'

    def place(self, src: Path, dst: Path) -> None:
        try:
            os.link(src, dst)
        except OSError:
            shutil.copy2(src, dst)

    def copy_scripts(self, level: int, target: Path) -> int:
        target.mkdir(parents=True, exist_ok=True)
        copied = 0
        texts = CHAPTER / f'battle{level:03d}' / 'source_texts'
        for path in sorted(texts.iterdir()) if texts.is_dir() else []:
            if path.is_file():
                shutil.copy2(path, target / path.name)
                copied += 1
        for family in ('STORY', 'WINFAIL'):
            path = CORPUS / f'{family}{level:03d}.json'
            if path.exists():
                shutil.copy2(path, target / path.name)
                copied += 1
        return copied

    @staticmethod
    def tag(draw, xy: tuple[int, int], text: str, font, fg, bg=(0, 0, 0, 170)) -> None:
        box = draw.textbbox(xy, text, font=font)
        draw.rectangle((box[0] - 1, box[1] - 1, box[2] + 1, box[3] + 1), fill=bg)
        draw.text(xy, text, font=font, fill=fg)

    def grid_overlay(self, size: tuple[int, int]):
        """Transparent layer: the 32 px grid, column／row numbers on the top and left edges, `x,y` every 5 cells."""
        from PIL import Image, ImageDraw, ImageFont
        overlay = Image.new('RGBA', size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        small = ImageFont.truetype(str(self.font_path), 9) if self.font_path else ImageFont.load_default()
        width, height = size
        for x in range(0, width, CELL):
            draw.line([(x, 0), (x, height)], fill=(255, 255, 255, 55))
        for y in range(0, height, CELL):
            draw.line([(0, y), (width, y)], fill=(255, 255, 255, 55))
        for cx in range(width // CELL):
            self.tag(draw, (cx * CELL + 2, 1), str(cx), small, (255, 230, 80, 255))
        for cy in range(1, height // CELL):
            self.tag(draw, (1, cy * CELL + 2), str(cy), small, (255, 230, 80, 255))
        for cx in range(5, width // CELL, 5):
            for cy in range(5, height // CELL, 5):
                self.tag(draw, (cx * CELL + 2, cy * CELL + 2), f'{cx},{cy}', small, (255, 255, 255, 200), (0, 0, 0, 110))
        return overlay

    def annotate(self, src: Path, dst: Path, units: list[dict]) -> None:
        from PIL import Image, ImageDraw, ImageFont
        image = Image.open(src).convert('RGBA')
        image = Image.alpha_composite(image, self.grid_overlay(image.size))
        overlay = Image.new('RGBA', image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        font = ImageFont.truetype(str(self.font_path), 11) if self.font_path else ImageFont.load_default()
        for unit in units:
            side = SIDE.get(unit['role'], '友')
            rgb = SIDE_RGB.get(side, SIDE_RGB['友'])
            x, y = unit['cell'][0] * CELL, unit['cell'][1] * CELL
            if not unit['drawn']:
                draw.rectangle((x + 3, y + 3, x + CELL - 4, y + CELL - 4), outline=rgb + (190,), width=1)
                continue
            draw.rectangle((x + 1, y + 1, x + CELL - 2, y + CELL - 2), outline=rgb + (255,), width=2)
            label = unit['name'] if unit['name'] and unit['name'] != '???' else unit['title'] or unit['actor_id']
            self.tag(draw, (x + 1, max(0, y - 13)), f"{label} {unit['level']}", font, (255, 255, 255, 255), rgb + (200,))
        Image.alpha_composite(image, overlay).convert('RGB').save(dst)

    def thumb(self, src: Path, dst: Path) -> None:
        from PIL import Image
        image = Image.open(src).convert('RGBA')
        flat = Image.new('RGBA', image.size, (40, 40, 40, 255))
        flat = Image.alpha_composite(flat, image).convert('RGB')
        flat.thumbnail((320, 320))
        flat.save(dst, quality=85)

    @staticmethod
    def pixels(path: Path) -> str:
        import hashlib
        from PIL import Image
        image = Image.open(path).convert('RGB')
        return hashlib.md5(repr(image.size).encode() + image.tobytes()).hexdigest()

    # ---- 地图原图
    def terrain_grid(self, level: int) -> list[list[dict]]:
        terrain = self.scenarios[level].get('resources', {}).get('terrain', '')
        return read_json(res(terrain)).get('grid', []) if terrain and res(terrain).exists() else []

    @staticmethod
    def blocked(cell: dict) -> bool:
        return bool(int(cell.get('b', 0))) or int(cell.get('h', 0)) >= 255

    def terrain_text(self, level: int, grid: list[list[dict]]) -> str:
        rows, clamped = [], 0
        for row in grid:
            chars = []
            for cell in row:
                height = int(cell.get('h', 0))
                if self.blocked(cell):
                    chars.append('#')
                elif height == 0:
                    chars.append('.')
                else:
                    clamped += height > 9
                    chars.append(str(min(9, height)))
            rows.append(''.join(chars))
        width, height = len(grid[0]), len(grid)
        header = [f'; {self.name(level)}（LEVEL{level:03d}）的地形：{width}×{height} 格，每格 32 px；一行一排（y），一个字符一格（x），从左上角 (0,0) 起',
                  '; # 不能走（悬崖、墙、房子、水）；. 能走，高度 0；1–9 能走，数字是高度（相邻两格高差 ≥3 走不通）',
                  '; 格式同自制地图的 terrain.txt（docs/ORIGINAL_LEVELS.md 2.1）'
                  + (f'；原版高度超过 9 的可走格有 {clamped} 格，这里写成 9' if clamped else '')
                  + '；原版另有「房屋底下硬阻挡」「能经过不能停」两种格标记，这个格式写不出']
        return '\n'.join(header + rows) + '\n'

    def terrain_image(self, src: Path, dst: Path, grid: list[list[dict]]) -> None:
        from PIL import Image, ImageDraw
        image = Image.open(src).convert('RGBA')
        red = Image.new('RGBA', image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(red)
        for y, row in enumerate(grid):
            for x, cell in enumerate(row):
                if self.blocked(cell):
                    draw.rectangle((x * CELL, y * CELL, x * CELL + CELL - 1, y * CELL + CELL - 1), fill=(255, 0, 0, 110))
        image = Image.alpha_composite(Image.alpha_composite(image, red), self.grid_overlay(image.size))
        image.save(dst)

    def who(self, level: int) -> str:
        if level in self.numbers and self.script:
            return f'玩家第 {self.numbers[level]} 场'
        if self.kind(level) == '过场' and self.script:
            return f'第 {self.after.get(level, 0)} 场后'
        return '遭遇战' if self.kind(level) == '遭遇战' else '—'

    def usage_line(self, levels: list[int]) -> str:
        parts = []
        battles = [f'{self.who(lv)} · {self.name(lv)}（LEVEL{lv:03d}）' for lv in levels if self.kind(lv) == '剧情战']
        stories = [f'{self.name(lv)}（LEVEL{lv:03d}）' for lv in levels if self.kind(lv) == '过场']
        encounters = [f'LEVEL{lv:03d}' for lv in levels if self.kind(lv) == '遭遇战']
        if battles:
            parts.append('剧情战 ' + '、'.join(battles))
        if encounters:
            parts.append('遭遇战 ' + '、'.join(encounters))
        if stories:
            parts.append('过场 ' + '、'.join(stories))
        return '；'.join(parts)

    def build_maps(self) -> dict[str, list[str]]:
        """地图原图/<scene>_LEVELnnn per distinct map picture; returns map key -> files written."""
        written: dict[str, list[str]] = {}
        self.hidden_kinds: dict[str, set] = {}
        self.kept_uncertain: dict[str, set] = {}
        for group in self.map_groups():
            first = group['first']
            raw = self.out / '_capture' / 'clean' / f'LEVEL{first:03d}'
            target = self.out / self.map_folder(first)
            target.mkdir(parents=True, exist_ok=True)
            files = []
            grid = self.terrain_grid(first)
            if (raw / 'clean.png').exists():
                self.place(raw / 'clean.png', target / '整图.png')
                files.append('整图.png')
            shutil.copy2(res(self.map_texture(first)), target / '地面层.png')
            files.append('地面层.png')
            if grid and (raw / 'clean.png').exists():
                self.terrain_image(raw / 'clean.png', target / '地形.png', grid)
                files.append('地形.png')
            if grid:
                (target / '地形.txt').write_text(self.terrain_text(first, grid), encoding='utf-8')
                files.append('地形.txt')
            clean = read_json(raw / 'clean.json') if (raw / 'clean.json').exists() else {}
            for row in clean.get('hidden_objects', []):
                self.hidden_kinds.setdefault(f"{row['kind'] or '—'}{'（加色）' if row.get('additive') else ''}", set()).add(row['name'])
            for row in clean.get('kept_objects', []):
                if row['kind'] in UNCERTAIN_KINDS or row.get('additive') or row.get('role') == 'treasure_box':
                    self.kept_uncertain.setdefault(f"{row['kind'] or row.get('role') or '—'}{'（加色）' if row.get('additive') else ''}", set()).add(row['name'])
            px = clean.get('map_px', [])
            w, h = (len(grid[0]), len(grid)) if grid else self.grid(first)
            hidden = sorted({row['name'] for row in clean.get('hidden_objects', [])})
            lines = [f'# {self.name(first)}（LEVEL{first:03d} 的地图）', '', f'用到这张图的关：{self.usage_line(group["levels"])}。', '',
                     f'- {w}×{h} 格' + (f'，底图 {px[0]}×{px[1]} px' if px else '') + f"；不能走的格 {sum(self.blocked(c) for row in grid for c in row)} 个。",
                     '- `整图.png`：地面加上静态地图物件，背景透明；没有单位、界面、光标和临时特效' + (f"（这张图藏掉的：{'、'.join(hidden)}）" if hidden else '') + '。',
                     '- `地面层.png`：map_texture 原样。`地形.png`：整图上把不能走的格涂成半透明红色。`地形.txt`：自制地图 terrain.txt 格式。', '']
            (target / '说明.md').write_text('\n'.join(lines), encoding='utf-8')
            files.append('说明.md')
            written[group['key']] = files
        return written

    def build(self) -> int:
        self.inserted = []
        order = self.play_order()
        self.numbers, self.after = {}, {}
        battles = 0
        for level in order:
            if self.kind(level) == '剧情战':
                battles += 1
                self.numbers[level] = battles
            else:
                self.after[level] = battles
        for name in GENERATED:
            path = self.out / name
            if path.is_dir():
                shutil.rmtree(path)
            elif path.exists():
                path.unlink()
        (self.out / '_thumbs').mkdir(parents=True, exist_ok=True)
        maps = self.build_maps()
        encounters = sorted(lv for lv in self.levels if self.kind(lv) == '遭遇战')
        done, results = {}, []
        for level in order + encounters:
            raw = self.out / '_capture' / f'LEVEL{level:03d}'
            if not (raw / 'units.json').exists() or not (raw / 'map.png').exists():
                continue
            capture = read_json(raw / 'units.json')
            kind = self.kind(level)
            target = self.out / self.folder(level)
            target.mkdir(parents=True, exist_ok=True)
            files = []
            if kind != '遭遇战':
                self.place(raw / 'map.png', target / '地图.png')
                files.append('地图.png')
            if kind != '过场' and (raw / 'opening.png').exists():
                self.place(raw / 'opening.png', target / '开局.png')
                self.annotate(raw / 'opening.png', target / '标注.png', self.present_units(capture))
                (target / '说明.md').write_text(self.describe_battle(level, capture, self.folder(level)), encoding='utf-8')
                files += ['开局.png', '标注.png', '说明.md']
            if self.script and level in self.script[0]:
                (target / '台词.md').write_text(self.script[0][level][1] + '\n', encoding='utf-8')
                files.append('台词.md')
            if self.copy_scripts(level, target / '脚本'):
                files.append('脚本/')
            done[level] = files
            results.append((level, capture))
        thumbs = self.write_index(order, encounters, done, maps)
        for level, capture in results:
            size = capture.get('opening', capture.get('map', {})).get('size')
            print(f"LEVEL{level:03d} {self.folder(level)} files={len(done[level])} size={size} living={capture.get('living_units', '-')} drawn={capture.get('drawn_units', '-')}")
        print('HIDDEN_IN_CLEAN ' + '；'.join(f"{k}: {'、'.join(sorted(v))}" for k, v in sorted(self.hidden_kinds.items())))
        print('KEPT_UNCERTAIN ' + '；'.join(f"{k}: {'、'.join(sorted(v))}" for k, v in sorted(self.kept_uncertain.items())))
        unique = len(set(thumbs))
        verdict = 'PASS' if unique == len(thumbs) else 'FAIL'
        print(f'LEVEL_ATLAS_ASSEMBLE {verdict} levels={len(done)} maps={len(maps)} thumbs={len(thumbs)} unique_thumbs={unique} out={self.out}'
              + (f' inserted={self.inserted}' if self.inserted else ''))
        return 0 if verdict == 'PASS' else 1

    def win_line(self, level: int) -> str:
        kind = self.kind(level)
        if kind == '过场':
            return '—（不打仗）'
        if kind == '遭遇战':
            return '全灭'
        return self.table.get(level, {}).get('win', '—')

    def write_index(self, order: list[int], encounters: list[int], done: dict[int, list[str]], maps: dict[str, list[str]]) -> list[str]:
        """README.md and index.html. Each picture is shown once: a thumbnail whose pixels were already
        shown gets a note instead. Returns the pixel hashes of every thumbnail placed (the self-check)."""
        from html import escape
        from urllib.parse import quote
        try:
            commit = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
        except OSError:
            commit = '?'
        stamp = time.strftime('%Y-%m-%d %H:%M')
        shown: dict[str, str] = {}
        thumbs: list[str] = []

        def link(path: str, text: str) -> str:
            return f'<a href="{quote(path)}">{escape(text)}</a>'

        def thumb(src: Path, name: str, href: str, label: str) -> tuple[str, str]:
            """(html cell, note): a picture already shown elsewhere gets no thumbnail, only the note."""
            key = self.pixels(src)
            if key in shown:
                return '', shown[key]
            shown[key] = label
            thumbs.append(key)
            self.thumb(src, self.out / '_thumbs' / name)
            return f'<a href="{quote(href)}"><img src="_thumbs/{quote(name)}" loading="lazy"></a>', ''

        md = ['# 《幻世錄》第一章关卡素材库', '',
              '逐关参考原版美术与关卡设计用。由仓库工具 `tools/hsl_level_atlas.py` 生成，素材是原版派生物，只放在本机，不进 git。',
              f'生成于 {stamp}，仓库提交 `{commit}`；已拍 {len(done)} 项，共 {len(order) + len(encounters)} 项（49 场剧情战、22 段过场、78 场遭遇战；不含续集示范 LEVEL200），不同的地图 {len(maps)} 张。', '',
              '- 全量重拍并拼装：`python3 tools/hsl_level_atlas.py build --jobs 3`；只重拼（秒级）：`python3 tools/hsl_level_atlas.py assemble`；重拍一关：`python3 tools/hsl_level_atlas.py capture --levels 51` 后再 assemble。', '']
        if not self.script:
            md += ['> 本检出没有 `docs/internal/ORIGINAL_SCRIPT.md`（公开检出不带）：跳过了台词；顺序按 campaign.json 登记顺序，「玩家第 N 场」编号不可用。', '']
        md += ['## 目录约定', '',
               '- `地图原图/<场景名>_LEVELnnn/`：每张不同的地图一个（按底图像素去重），以游玩时第一个用到它的关命名。',
               '  - `整图.png`：地面加上静态地图物件（房子、树、栅栏、水井……），背景透明；不带单位、界面、光标，也不带临时特效（视差天空、云与云影、雾、闪光、火，以及剧情脚本插进来的雨、烟、火）。',
               '  - `地面层.png`：`resources.map_texture` 原样。`地形.png`：整图上把不能走的格涂成半透明红色，叠格子与坐标。`地形.txt`：同一份地形，写成自制地图 terrain.txt 的格式。',
               '  - `说明.md`：这张图被哪些关用到。',
               '- `剧情战/第NN场_场景名_LEVELnnn/`：NN 是玩家第几场（按游玩顺序数剧情战，不数过场和遭遇战）。',
               '  - `地图.png`：整张地图（含地图物件和演出特效），不带单位、光标、界面。宽高＝格数×32 px；例外是王座廳那张 960×720 的底图（LEVEL058／060／063／071／076–079／081／082），比 30×22 格多出下方 16 px，图按底图原尺寸出。带视差天空的图按「镜头看到哪一块，就按那时的镜头摆天空」逐块拼成。',
               '  - `开局.png`：同一张整图，加上开场演完、谁都还没动那一刻场上的全部单位，即关卡设计的初始布阵（比我方快的 AI 第 1 回合会先动，说明.md 里列出是谁）。',
               '  - `标注.png`：开局图叠上格子：每格 32 px，上边与左边标列号／行号，每 5 格标一次 `x,y`；单位脚下那一格按阵营框出——敌红、我蓝、友绿（含中立），框上写名字（无名的写稱號）和等级。',
               '  - `说明.md`：名称、类型、地图格数、胜负条件（含晚开的，附看板原文与判定）、开局单位表、增援、主要事件。',
               '  - `台词.md`：台词全本（`docs/internal/ORIGINAL_SCRIPT.md`）对应一节，原样照抄。',
               '  - `脚本/`：原版脚本原件（LEVELnnn.H、OBJ-nnn.H、STORYnnn.TXT、winfailnnn.txt）与编译后的 STORYnnn.json、WINFAILnnn.json。',
               '- `遭遇战/<借用地图的场景名>_LEVEL5xx/`：开局.png、标注.png、说明.md、脚本/；地图见 `地图原图/`。',
               '- `过场/第NN场后_场景名_LEVEL0xx/`：地图.png、台词.md、脚本/；不打仗，没有开局图和标注图。NN 是它前面打完的剧情战场数。',
               '- `_capture/`：截图驱动的原始输出，assemble 只读它；`_thumbs/`：网页缩略图；`index.html`：本索引的网页版（同一张图只放一次缩略图）。',
               '- 格坐标 `(x,y)` 从地图左上角 (0,0) 起，x 向右、y 向下，与脚本里的像素坐标 ÷32 取整一致。', '']
        html = []
        # 地图原图
        md += ['## 地图原图（每张不同的地图一行，按游玩时第一次用到的先后）', '', '| # | 地图（第一次用到的关） | 格数 | 用到的关 | 文件夹 |', '| ---: | --- | --- | --- | --- |']
        html.append('<h2>地图原图</h2><table><tr><th>整图</th><th>地图（第一次用到的关）</th><th>格数</th><th>用到的关</th><th>文件</th></tr>')
        for index, group in enumerate(self.map_groups(), 1):
            first, folder = group['first'], self.map_folder(group['first'])
            files = maps.get(group['key'], [])
            w, h = self.grid(first)
            usage = self.usage_line(group['levels'])
            md.append(f"| {index} | {self.name(first)}（LEVEL{first:03d}） | {w}×{h} | {usage} | [{folder}]({quote(folder)}/) |")
            cell, note = thumb(self.out / folder / '整图.png', f'MAP_LEVEL{first:03d}.jpg', f'{folder}/整图.png', f'地图原图 {self.name(first)}') if '整图.png' in files else ('', '未拍')
            html.append(f'<tr><td>{cell}{escape(note)}</td><td>{escape(self.name(first))}（LEVEL{first:03d}）</td><td>{w}×{h}</td><td>{escape(usage)}</td>'
                        f'<td>{" ".join(link(folder + "/" + f, f) for f in files)}</td></tr>')
        html.append('</table>')
        # 剧情战与过场
        md += ['', '## 剧情战与过场（按游玩顺序）', '',
               '| # | 玩家口径 | 场景名 | 文件号 | 类型 | 地图格数 | 胜利条件 | 地图原图 | 文件夹 | 备注 |', '| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |']
        html.append('<h2>剧情战与过场（按游玩顺序）</h2><table><tr><th>开局／地图</th><th>玩家口径</th><th>场景名</th><th>文件号</th><th>类型</th><th>格数</th><th>胜利条件</th><th>地图原图</th><th>文件</th></tr>')
        story_maps: dict[str, int] = {}
        deployments: dict[tuple, int] = {}
        for index, level in enumerate(order, 1):
            w, h = self.grid(level)
            kind, folder, files = self.kind(level), self.folder(level), done.get(level, [])
            map_folder = self.map_folder(level)
            note, cell, note_html = '', '', ''
            units = self.out / '_capture' / f'LEVEL{level:03d}' / 'units.json'
            # Same map, same units on the same cells: the same opening (animated objects aside).
            deployment = (self.map_key(level), tuple(sorted((u['actor_id'], u['role'], tuple(u['cell'])) for u in read_json(units).get('units', []) if u['living']))) \
                if kind == '剧情战' and units.exists() else None
            if kind == '过场' and self.map_key(level) in story_maps:
                earlier = story_maps[self.map_key(level)]
                note = f'地图同 {self.name(earlier)}（LEVEL{earlier:03d}）'
                note_html = link(self.folder(earlier) + '/', note)
            elif deployment in deployments:
                earlier = deployments[deployment]
                note = f'开局与第 {self.numbers.get(earlier, "?")} 场相同'
                note_html = link(self.folder(earlier) + '/', note)
            elif files:
                src = self.out / folder / ('开局.png' if kind == '剧情战' else '地图.png')
                label = f'第 {self.numbers[level]} 场' if kind == '剧情战' and level in self.numbers else f'{self.name(level)}（LEVEL{level:03d}）'
                cell, seen = thumb(src, f'LEVEL{level:03d}.jpg', f'{folder}/{src.name}', label)
                if seen:
                    note = f'开局与{seen}相同' if kind == '剧情战' else f'图同 {seen}'
                    note_html = escape(note)
            if kind == '过场':
                story_maps.setdefault(self.map_key(level), level)
            if deployment is not None:
                deployments.setdefault(deployment, level)
            md.append(f'| {index} | {self.who(level)} | {self.name(level)} | LEVEL{level:03d} | {kind} | {w}×{h} | {self.win_line(level)} | '
                      f'[原图]({quote(map_folder)}/) | ' + (f'[{folder}]({quote(folder)}/)' if files else '未拍') + f' | {note} |')
            html.append(f'<tr><td>{cell}{note_html}</td><td>{escape(self.who(level))}</td><td>{escape(self.name(level))}</td><td>LEVEL{level:03d}</td><td>{kind}</td>'
                        f'<td>{w}×{h}</td><td>{escape(self.win_line(level))}</td><td>{link(map_folder + "/", "原图")}</td>'
                        f'<td>{" ".join(link(folder + "/" + f, f.rstrip("/")) for f in files) or "未拍"}</td></tr>')
        html.append('</table>')
        # 遭遇战: one row per borrowed map
        md += ['', '## 遭遇战（每张借用的地图一行）', '', '遭遇战一律：全灭胜，雷歐納德死亡败；没有对白、没有增援（docs/ORIGINAL_LEVELS.md 1.2）。三场连号借同一张图，敌人配置不同。', '',
               '| 借用的地图 | 格数 | 地图原图 | 三场（文件号 · 开局敌人数 · 文件夹） |', '| --- | --- | --- | --- |']
        html.append('<h2>遭遇战（每张借用的地图一行）</h2><table><tr><th>开局（第一场）</th><th>借用的地图</th><th>格数</th><th>地图原图</th><th>三场</th></tr>')
        by_map: dict[str, list[int]] = {}
        for level in encounters:
            by_map.setdefault(self.map_key(level), []).append(level)
        for key, members in by_map.items():
            owner = self.owner_of_map(members[0])
            name = self.name(owner) if owner else self.name(members[0])
            w, h = self.grid(members[0])
            map_folder = self.map_folder(members[0])
            cells_md, cells_html = [], []
            for level in members:
                enemies = sum(1 for u in self.scenarios[level].get('playable_units', []) if u.get('battle_actor_role') == 'enemy_ai')
                folder, files = self.folder(level), done.get(level, [])
                cells_md.append(f'LEVEL{level:03d} · 敌 {enemies} · ' + (f'[文件夹]({quote(folder)}/)' if files else '未拍'))
                cells_html.append(f'LEVEL{level:03d}（敌 {enemies}）' + ' '.join(link(folder + '/' + f, f.rstrip('/')) for f in files if f in ('开局.png', '标注.png', '说明.md')))
            first_done = next((lv for lv in members if '开局.png' in done.get(lv, [])), None)
            cell, seen = thumb(self.out / self.folder(first_done) / '开局.png', f'LEVEL{first_done:03d}.jpg', f'{self.folder(first_done)}/开局.png', f'遭遇战 LEVEL{first_done:03d}') if first_done else ('', '')
            md.append(f"| {name}（LEVEL{owner or 0:03d}） | {w}×{h} | [原图]({quote(map_folder)}/) | {'；'.join(cells_md)} |")
            html.append(f'<tr><td>{cell}{escape("图同 " + seen) if seen else ""}</td><td>{escape(name)}（LEVEL{owner or 0:03d}）</td><td>{w}×{h}</td>'
                        f'<td>{link(map_folder + "/", "原图")}</td><td>{"<br>".join(cells_html)}</td></tr>')
        html.append('</table>')
        (self.out / 'README.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
        page = ['<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><title>幻世錄第一章关卡素材库</title>',
                '<style>body{font-family:sans-serif;margin:16px;background:#111;color:#ddd}table{border-collapse:collapse;margin-bottom:24px}'
                'td,th{border:1px solid #333;padding:4px 6px;vertical-align:top;font-size:13px}img{max-width:160px;max-height:160px;display:block}'
                'a{color:#8cf}th{background:#222}</style></head><body>',
                f'<h1>《幻世錄》第一章关卡素材库</h1><p>生成于 {stamp}，提交 {escape(commit)}；已拍 {len(done)} 项，不同的地图 {len(maps)} 张。'
                '目录约定见 <a href="README.md">README.md</a>。点缩略图看大图；同一张图只放一次缩略图，再出现时写「同 …」。</p>',
                *html, '</body></html>']
        (self.out / 'index.html').write_text('\n'.join(page) + '\n', encoding='utf-8')
        return thumbs


def assemble(out: Path) -> int:
    if not (out / '_capture').is_dir():
        print(f'LEVEL_ATLAS_ASSEMBLE FAIL no captures under {out}/_capture (run capture first)')
        return 1
    return Atlas(out).build()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
