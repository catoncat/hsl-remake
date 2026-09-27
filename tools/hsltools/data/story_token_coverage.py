"""Measure how many original STORY script action tokens the opening-timeline
compiler maps to explicit presentation kinds.

Build mode reads the original PAK: `DATA\\ACTION.H` (the script VM's token
catalogue with opcode numbers and argument comments) and every `DATA\\STORY*.TXT`.
It writes one tracked coverage report plus the two script-global headers
(`ACTION.H`, `EXTRAS.H`) next to the other original tables. `--check` validates
the tracked report against the current compiler mapping without the PAK.

Only STORY scripts are scanned: winfail scripts (actCheck* conditions) belong to
the winfail interpreter and are not counted here.

Registry task story_token_coverage (family static, OriginalArchiveTask): tracked output
content/generated/hsl/static/hsl01/story_token_coverage.json; check validates the tracked report against the current
compiler mapping (no PAK), generate rescans hsl.pak. Bodies moved verbatim from the former hsl_story_token_coverage.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from hsltools.levels.timeline import ACTION_KIND, canonical_action_name
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import Context

DEFAULT_PAK = ORIGINAL_PAK
OUTPUT = ROOT / 'content/generated/hsl/static/hsl01/story_token_coverage.json'
TABLES = ROOT / 'content/imported/hsl/global/tables'
HEADERS = ('ACTION.H', 'EXTRAS.H')
SCHEMA = 'hsl_story_token_coverage.v1'
# STORY numbers below this are the main campaign levels; 5xx/9xx scripts are
# alternate or test variants (resource naming only, not a proven engine rule).
MAIN_LEVEL_LIMIT = 500
STORY_RE = re.compile(r'^@:\\DATA\\STORY(\d+)\.TXT$', re.I)
DEFINE_RE = re.compile(r'^\s*#define\s+(act\w+)\s+(\d+)\s*(?://\s*(.*))?$')
TOKEN_RE = re.compile(r'\b(act[A-Za-z0-9_]+)')


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_action_header(text: str) -> dict[str, dict[str, Any]]:
    """`#define actName  opcode // [arg][arg]...` lines; commented-out defines are skipped."""
    catalog: dict[str, dict[str, Any]] = {}
    for line in text.splitlines():
        match = DEFINE_RE.match(line)
        if not match:
            continue
        name, opcode, comment = match.group(1), int(match.group(2)), (match.group(3) or '').strip()
        catalog[name] = {'opcode': opcode, 'arg_doc': comment}
    return catalog


def scan_story_tokens(text: str) -> list[str]:
    """Action tokens of one STORY script in source order (`action = ...` lines only,
    comment lines and inline comments removed, duplicates kept)."""
    tokens: list[str] = []
    for raw in text.splitlines():
        line = raw.split(';', 1)[0].strip()
        if not line:
            continue
        match = re.match(r'action\s*=\s*(.*)$', line, re.I)
        if not match:
            continue
        tokens.extend(TOKEN_RE.findall(match.group(1)))
    return tokens


def build_report(catalog: dict[str, dict[str, Any]], stories: dict[str, str], header_digests: dict[str, str]) -> dict[str, Any]:
    """stories: STORY level code (e.g. '001') -> decoded script text."""
    usage: dict[str, dict[str, Any]] = {}
    levels: dict[str, dict[str, Any]] = {}
    for code in sorted(stories, key=int):
        tokens = scan_story_tokens(stories[code])
        unmapped: list[str] = []
        distinct: list[str] = []
        for token in tokens:
            canonical = canonical_action_name(token)
            entry = usage.setdefault(canonical, {'levels': set(), 'spellings': set(), 'occurrences': 0})
            entry['levels'].add(code)
            entry['spellings'].add(token)
            entry['occurrences'] += 1
            if canonical not in distinct:
                distinct.append(canonical)
            if canonical not in ACTION_KIND and canonical not in unmapped:
                unmapped.append(canonical)
        levels[code] = {
            'story_member': f'DATA\\STORY{code}.TXT',
            'token_occurrences': len(tokens),
            'distinct_tokens': distinct,
            'unmapped_tokens': unmapped,
            'fully_mapped': not unmapped,
        }
    tokens_out: dict[str, dict[str, Any]] = {}
    for name in sorted(set(catalog) | set(usage)):
        entry = usage.get(name, {'levels': set(), 'spellings': set(), 'occurrences': 0})
        level_codes = sorted(entry['levels'], key=int)
        tokens_out[name] = {
            'opcode': catalog.get(name, {}).get('opcode'),
            'arg_doc': catalog.get(name, {}).get('arg_doc', ''),
            'in_catalog': name in catalog,
            'story_level_count': len(level_codes),
            'story_main_level_count': sum(1 for code in level_codes if int(code) < MAIN_LEVEL_LIMIT),
            'story_levels': level_codes,
            'story_occurrences': entry['occurrences'],
            'source_spellings': sorted(entry['spellings']),
            'compiler_kind': ACTION_KIND.get(name),
            'mapped': name in ACTION_KIND,
        }
    used = [name for name, row in tokens_out.items() if row['story_level_count'] > 0]
    unmapped_used = [name for name in used if not tokens_out[name]['mapped']]
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'source_policy': 'Token names, opcodes and argument comments come from DATA\\ACTION.H; usage counts come from the action= lines of every DATA\\STORY*.TXT (comments removed). Winfail scripts are not scanned. Mapping is the current tools/hsl_opening_timeline_compile.py ACTION_KIND table; a mapped kind names the source intent, not a proven handler.',
        'sources': {
            'headers': {name: {'path': f'content/imported/hsl/global/tables/{name}', 'sha256': header_digests[name]} for name in HEADERS},
            'story_file_count': len(stories),
            'main_level_limit': MAIN_LEVEL_LIMIT,
        },
        'summary': {
            'catalog_token_count': len(catalog),
            'story_used_token_count': len(used),
            'story_used_mapped_count': len(used) - len(unmapped_used),
            'story_used_unmapped_count': len(unmapped_used),
            'story_used_unmapped_tokens': sorted(unmapped_used, key=lambda n: (-tokens_out[n]['story_level_count'], n)),
            'compiler_mapped_token_count': len(ACTION_KIND),
            'fully_mapped_level_count': sum(1 for row in levels.values() if row['fully_mapped']),
            'level_count': len(levels),
        },
        'tokens': tokens_out,
        'levels': levels,
        'claim_limit': 'Counts are script-structure facts; they say nothing about which tokens the original engine executes at runtime or how.',
    }


def _read_member(packages, member: str) -> bytes:
    from hsltools.sources.pak import find_paks_record_by_name, read_paks_record_bytes
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError(f'missing or ambiguous PAK member: {member}')
    package, record = matches[0]
    return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))


def build(pak: Path, output: Path) -> dict[str, Any]:
    from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes
    packages = find_decoded_paks_packages(pak)
    digests: dict[str, str] = {}
    TABLES.mkdir(parents=True, exist_ok=True)
    header_text = ''
    for name in HEADERS:
        data = _read_member(packages, f'@:\\data\\{name}')
        (TABLES / name).write_bytes(data)
        digests[name] = _sha(data)
        if name == 'ACTION.H':
            header_text = data.decode('cp950', 'replace')
    stories: dict[str, str] = {}
    for package in packages:
        for record in package['records']:
            match = STORY_RE.match(str(record['name']))
            if not match:
                continue
            data = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
            stories[match.group(1)] = data.decode('cp950', 'replace')
    report = build_report(parse_action_header(header_text), stories, digests)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return report


def check(output: Path) -> dict[str, int]:
    report = json.loads(output.read_text(encoding='utf-8'))
    if report.get('schema') != SCHEMA:
        raise SystemExit('story token coverage report has an unexpected schema')
    for name, row in report['sources']['headers'].items():
        path = ROOT / row['path']
        if not path.is_file() or _sha(path.read_bytes()) != row['sha256']:
            raise SystemExit(f'tracked header differs from the coverage report: {path}')
    catalog = parse_action_header((ROOT / report['sources']['headers']['ACTION.H']['path']).read_text(encoding='cp950', errors='replace'))
    tokens: dict[str, dict[str, Any]] = report['tokens']
    for name, row in tokens.items():
        if row['mapped'] != (name in ACTION_KIND) or row['compiler_kind'] != ACTION_KIND.get(name):
            raise SystemExit(f'coverage report is stale for {name}: rebuild with the original PAK')
        if row['in_catalog'] != (name in catalog) or (name in catalog and row['opcode'] != catalog[name]['opcode']):
            raise SystemExit(f'coverage catalog entry differs from the tracked ACTION.H: {name}')
    used = [name for name, row in tokens.items() if row['story_level_count'] > 0]
    unmapped = [name for name in used if not tokens[name]['mapped']]
    summary = report['summary']
    if summary['story_used_token_count'] != len(used) or summary['story_used_unmapped_count'] != len(unmapped):
        raise SystemExit('coverage summary counts do not match the token table')
    if sorted(summary['story_used_unmapped_tokens']) != sorted(unmapped):
        raise SystemExit('coverage summary unmapped list is stale')
    if summary['compiler_mapped_token_count'] != len(ACTION_KIND) or summary['catalog_token_count'] != len(catalog):
        raise SystemExit('coverage summary totals are stale')
    for code, level in report['levels'].items():
        expected = [name for name in level['distinct_tokens'] if name not in ACTION_KIND]
        if level['unmapped_tokens'] != expected or level['fully_mapped'] != (not expected):
            raise SystemExit(f'level {code} unmapped list is stale')
    if summary['fully_mapped_level_count'] != sum(1 for level in report['levels'].values() if level['fully_mapped']):
        raise SystemExit('fully mapped level count is stale')
    return {'tokens': len(tokens), 'used': len(used), 'unmapped': len(unmapped), 'levels': len(report['levels'])}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pak', type=Path, default=DEFAULT_PAK)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--check', action='store_true', help='validate the tracked report against the current compiler mapping (no PAK)')
    args = parser.parse_args(argv)
    if args.check:
        summary = check(args.output)
        print(f"STORY_TOKEN_COVERAGE_CHECK_PASS tokens={summary['tokens']} used={summary['used']} unmapped={summary['unmapped']} levels={summary['levels']}")
        return 0
    if not args.pak.is_file():
        parser.error(f'original PAK not found: {args.pak}')
    report = build(args.pak, args.output)
    summary = report['summary']
    print(f"STORY_TOKEN_COVERAGE_BUILD_PASS catalog={summary['catalog_token_count']} used={summary['story_used_token_count']} "
          f"mapped={summary['story_used_mapped_count']} unmapped={summary['story_used_unmapped_count']} levels={summary['level_count']} "
          f"fully_mapped_levels={summary['fully_mapped_level_count']}")
    return 0


class StoryTokenCoverageTask(OriginalArchiveTask):
    name = 'story_token_coverage'
    family = 'static'
    inputs = ('content/imported/hsl/global/tables/', 'tools/hsltools/levels/timeline.py')
    outputs = (OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_story_token_coverage.py --check',)
    scripts = ('tools/hsltools/data/story_token_coverage.py', 'tools/hsltools/levels/timeline.py')

    def verify(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[StoryTokenCoverageTask]:
    return [StoryTokenCoverageTask()]


if __name__ == '__main__':
    raise SystemExit(main())
