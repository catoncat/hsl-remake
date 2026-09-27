"""Original Earth Binding local-effect shapes/sounds through the shared importer.

Registry task paralysis_assets (family assets): output content/imported/hsl/chapter01/paralysis_magic/
through hsl_support_magic's build / check. Bodies moved verbatim from the former hsl_paralysis_assets.py.
"""
from pathlib import Path
from hsltools.data.support_magic import build, check
from hsltools.data.skill_book import build as skill_book
from hsltools.registry import Context, ScriptCheckTask, original_archive

OUT = Path('content/imported/hsl/chapter01/paralysis_magic')

def definitions():
    sid='magic:magicEARTH:magicCode05'
    entry=skill_book()['skills'][sid]
    return {'paralysis':{'skill_id':sid,'name':entry['name'],'fields':entry['fields']}}


class ParalysisAssetsTask(ScriptCheckTask):
    name = 'paralysis_assets'
    family = 'assets'
    inputs = ('content/imported/hsl/global/tables/', 'content/generated/hsl/skills/initial_book.json')
    outputs = (OUT.as_posix() + '/',)
    replaces = ('tools/hsl_paralysis_assets.py --check',)
    scripts = ('tools/hsltools/assets/paralysis_assets.py', 'tools/hsltools/data/support_magic.py')

    def verify(self, ctx: Context) -> None:
        check(definitions(),OUT)

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx),definitions(),OUT,'hsl_paralysis_magic_resources.v1')


def tasks() -> list[ParalysisAssetsTask]:
    return [ParalysisAssetsTask()]
