"""Compile current skills' function symbols and exact RANGE masks without artwork.

Registry task skill_target_data (family skills): output content/generated/hsl/skills/targeting.json.
Bodies moved verbatim from the former hsl_skill_target_data.py.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from hsltools.data import json_bytes
from hsltools.data.skill_book import build as skill_book
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES

OUT = Path('content/generated/hsl/skills/targeting.json')
LINE_RANGES = ('range3CellDir', 'range4CellDir', 'range5CellDir')


def function_bits() -> dict[str, int]:
    text = (TABLES/'TYPE.H').read_bytes().decode('cp950')
    return {name: int(value, 16) for name, value in
            re.findall(r'^\s*#define\s+(magicFun_\w+)\s+(0x[0-9a-fA-F]+)\b', text, re.M)}


def function_mask(expression: str, bits: dict[str, int]) -> int:
    result = 0
    for token in expression.split(','):
        token = token.strip()
        if not token or token not in bits:
            raise ValueError('Unknown or missing skill function: '+token)
        result |= bits[token]
    return result


def range_pattern(code: str) -> dict:
    text = (TABLES/'RANGE.TXT').read_bytes().decode('cp950')
    matches = [block for block in text.split('[range]')[1:]
               if re.search(r'^code\s*=\s*'+re.escape(code)+r'\s*$',block,re.M)]
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous range: '+code)
    block = matches[0]
    size = int(re.search(r'^size\s*=\s*(\d+)',block,re.M)[1])
    rows = [[int(n.strip()) for n in line.split(',')]
            for line in re.findall(r'^data\s*=\s*([^\r\n;]+)',block,re.M)]
    if code in LINE_RANGES:
        # RANGE.H "N Line"/"E Line": 0x4100e0 (indices 21..23) ignores the rows and writes a
        # straight size-cell line from the chosen cell away from the caster (see
        # docs/evidence_packets/static_reverse/original_line_ranges.md).
        if not 0 < size <= 25 or len(rows) != size or any(len(row) != 1 for row in rows) or [row[0] for row in rows] != list(range(size, 0, -1)):
            raise ValueError('Unsupported line range shape: '+code)
        return {'size':size, 'data':rows, 'shape':'line'}
    if not 0 < size <= 25 or size % 2 == 0 or len(rows) != size or any(len(row)!=size for row in rows):
        raise ValueError('Unsupported range shape: '+code)
    if any(not 0 <= value <= 127 for row in rows for value in row):
        raise ValueError('Unsupported range value: '+code)
    return {'size':size, 'data':rows}


def build() -> dict:
    fields = [entry['fields'] for entry in skill_book()['skills'].values()]
    bits = function_bits()
    for row in fields:
        function_mask(row['function'],bits)
    ranges = {code:range_pattern(code) for code in sorted({r[key] for r in fields for key in ['range','effect_range']})}
    return {'schema':'hsl_skill_target_data.v1','evidence_tier':'resource-derived',
            'sources':{name:hashlib.sha256((TABLES/name).read_bytes()).hexdigest()
                       for name in ['TYPE.H','RANGE.TXT','MAGIC.TXT','SPECIAL.TXT']},
            'function_bits':bits,'ranges':ranges,
            'limits':'Source function symbols and masks only. Line (Dir) ranges carry shape=line and are projected by SkillTargetRules from the caster direction; obstacles, targeting modes and skill effects require separate program evidence.'}


class SkillTargetDataTask(GeneratedFilesTask):
    name = 'skill_target_data'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/generated/hsl/skills/initial_book.json')
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_skill_target_data.py --check',)
    scripts = ('tools/hsltools/data/skill_targeting.py', 'tools/hsltools/data/skill_book.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return f'SKILL_TARGET_DATA_PASS ranges={len(json.loads(rendered[OUT.as_posix()])["ranges"])}'


def tasks() -> list[SkillTargetDataTask]:
    return [SkillTargetDataTask()]
