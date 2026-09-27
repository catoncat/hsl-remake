"""Campaign overview: one table row per registered level, generated from
content/battles/campaign.json and the scenario files it names - kind, title, map, how the
scene ends (next level event / skip-battle target) - so the game's story graph can be read
in one place when extending or reordering the campaign. Counts only; no original-equivalence
claim follows from this file. --check recomputes and compares with the tracked document.

Registry task campaign_overview (family static, GeneratedFilesTask): output
docs/evidence_packets/resource_inventory/campaign_overview.md, rendered with the tracked `updated` date while the rows
are unchanged and with today's date when they changed.
"""
from __future__ import annotations

import datetime
import json
from pathlib import Path

from hsltools.evidence import index as evidence_index
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
CAMPAIGN = ROOT / 'content/battles/campaign.json'
OUTPUT = ROOT / 'docs/evidence_packets/resource_inventory/campaign_overview.md'
BIG_MAP = 49


def _event(value) -> str:
    if not value:
        return '—'
    level = int(value[0])
    event = int(value[1]) if len(value) > 1 else level
    return f'回图点 {level}' if event == BIG_MAP else f'→ {event}'


def rows() -> list[dict]:
    campaign = json.loads(CAMPAIGN.read_text(encoding='utf-8'))
    result = []
    for key, entry in campaign['battles'].items():
        level = int(key)
        scenario_ref = str(entry.get('scenario', ''))
        kind = str(entry.get('kind', 'battle'))
        row = {'level': level, 'title': str(entry.get('title', '')), 'kind': kind, 'map': '', 'ends': '', 'skip': '', 'status': ''}
        if scenario_ref.endswith('.json'):
            scenario = json.loads((ROOT / scenario_ref[len('res://'):]).read_text(encoding='utf-8'))
            opening = scenario.get('opening', {})
            row['status'] = str(scenario.get('status', ''))
            row['map'] = str(scenario.get('resources', {}).get('map_texture', '')).split('/')[-1].replace('.png', '')
            if kind == 'story':
                if opening.get('preview_of_battle_level') is not None:
                    row['kind'] = 'preview'
                    skip = opening.get('skip_battle') or {}
                    row['skip'] = _event(skip.get('next_level_event')) if skip else '—'
                    row['ends'] = '卡片：續播／回图'
                else:
                    row['ends'] = _event(opening.get('next_level_event')) if opening.get('next_level_event') else ('卡片回图' if opening.get('end_exit') else '卡片')
            else:
                row['ends'] = '战斗（winfail 解释器）'
        else:
            row['ends'] = scenario_ref.split('/')[-1]
        result.append(row)
    result.sort(key=lambda r: r['level'])
    return result


def header(updated: str) -> str:
    """The machine-readable packet header (tools/evidence_index.py); an index, not live evidence."""
    return evidence_index.format_header({
        'evidence': [{'tier': 'resource-derived', 'scope': None}], 'status': 'record-only', 'superseded_by': None,
        'functions': [], 'tools': ['hsltools/data/campaign_overview.py'], 'updated': updated,
    })


def tracked_updated() -> str | None:
    """The `updated` date already carried by the tracked document, if it has a valid header."""
    if not OUTPUT.is_file():
        return None
    try:
        _, _, line = evidence_index.split_header(OUTPUT.read_text(encoding='utf-8'))
        return evidence_index.parse_header_line(line)['updated'] if line else None
    except evidence_index.HeaderError:
        return None


def render(table: list[dict], updated: str) -> str:
    kinds: dict[str, int] = {}
    for row in table:
        kinds[row['kind']] = kinds.get(row['kind'], 0) + 1
    lines = [
        '# 战役总览（campaign.json 生成）',
        '',
        header(updated),
        '',
        '由 `python3 tools/hsl.py generate campaign_overview` 从 `content/battles/campaign.json` 与其引用的场景文件生成；`hsl check campaign_overview` 随门禁比对。'
        f' 注册 {len(table)} 项：正式战斗 {kinds.get("battle", 0)}、完整过场 {kinds.get("story", 0)}、开场预览 {kinds.get("preview", 0)}、谢幕 {kinds.get("game_clear", 0)}。'
        ' 只是流转与状态的索引，不含任何原版等价声明；预览的「視為勝利去向」是「略過戰鬥（視為勝利）」施加胜利段写入后的去向。',
        '',
        '| 关 | 标题 | 类型 | 地图 | 结束 | 視為勝利去向 | 场景状态 |',
        '| --- | --- | --- | --- | --- | --- | --- |',
    ]
    for row in table:
        lines.append(f"| {row['level']} | {row['title']} | {row['kind']} | {row['map'] or '—'} | {row['ends']} | {row['skip'] or '—'} | {row['status'] or '—'} |")
    return '\n'.join(lines) + '\n'


class CampaignOverviewTask(GeneratedFilesTask):
    name = 'campaign_overview'
    family = 'static'
    inputs = (CAMPAIGN.relative_to(ROOT).as_posix(), 'content/battles/')
    outputs = (OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_campaign_overview.py --check',)
    scripts = ('tools/hsltools/data/campaign_overview.py', 'tools/hsltools/evidence/index.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        today = datetime.date.today().isoformat()
        text = render(rows(), tracked_updated() or today)
        if not (OUTPUT.is_file() and OUTPUT.read_text(encoding='utf-8') == text):
            text = render(rows(), today)  # `updated` means "content last changed"
        return {self.outputs[0]: text.encode('utf-8')}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return f'CAMPAIGN_OVERVIEW_CHECK_PASS rows={len(rows())}' if mode == 'check' else f'CAMPAIGN_OVERVIEW_BUILD_PASS output={OUTPUT.relative_to(ROOT)} rows={len(rows())}'


def tasks() -> list[CampaignOverviewTask]:
    return [CampaignOverviewTask()]
