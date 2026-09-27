"""Exact Water Strike definition and its own original local-effect resources.

Registry task water_strike_data (family skills, OriginalArchiveTask): tracked output
content/imported/hsl/chapter01/water_strike/; generate re-imports from hsl.pak through the
support_magic importer. Bodies moved verbatim from the former hsl_water_strike.py.
"""
from pathlib import Path
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.data.support_magic import build, check
from hsltools.registry import Context
from hsltools.sources.tables import TABLES, blocks, parse_table

OUT = Path('content/imported/hsl/chapter01/water_strike')
SKILL_ID = 'magic:magicWATER:magicCode01'


def definitions():
    names = parse_table(Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT').read_bytes())
    rows = [row for row in blocks((TABLES/'MAGIC.TXT').read_bytes(), 'magic')
            if row['type'] == 'magicWATER' and row['code'] == 'magicCode01']
    if len(rows) != 1:
        raise ValueError('Missing or ambiguous source Water Strike')
    row = rows[0]
    expected = {'range':'range3CellCircle','effect_range':'range1Cell','expend':'8',
                'damage':'16,24','hit_ratio':'94','function':'magicFun_Attack',
                'effect_proc':'eff_proc_Local','effect_code':'effCode08'}
    if any(row.get(k) != value for k, value in expected.items()):
        raise ValueError('Water Strike source contract changed')
    return {'water': {'skill_id':SKILL_ID,'name':names[row['name']],'fields':row}}


class WaterStrikeTask(OriginalArchiveTask):
    name = 'water_strike_data'  # 'water_strike' is the native probe task (hsltools.probes.water_strike)
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',
              'content/imported/hsl/shared/first_skill/')
    outputs = (OUT.as_posix() + '/',)
    replaces = ('tools/hsl_water_strike.py --check',)
    scripts = ('tools/hsltools/data/water_strike.py', 'tools/hsltools/data/support_magic.py')

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check, definitions(), OUT)

    def rebuild(self, ctx: Context) -> None:
        build(self.archive, definitions(), OUT, 'hsl_water_strike_resources.v1')


def tasks() -> list[WaterStrikeTask]:
    return [WaterStrikeTask()]
