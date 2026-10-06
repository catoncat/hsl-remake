"""Per-cast asset bundles: Ohm village (003/061/062), the priest slot (002) and the four
mobile jobs (004/006/028/036) — each appends its actors to the shared combat / portrait /
panel imports, and its --check re-runs the shared checkers. The chapter01 walk manifest holding the
priest and mobile-job actors is written by actor_walk_manifest:chapter01 (all its actors in one pass,
never read-modify-write); the casts only verify it.

Registry tasks ohm_assets / priest_assets / mobile_jobs_assets (family assets). The scripts'
composite check_* functions (walk manifest + the three shared checks + the cast's PASS line)
are kept for the tools/hsl_*_assets.py --check entry points; the registry tasks run only the
cast's own piece (its walk-manifest check and PASS line) because combat_animation /
actor_portraits / panel_assets are already tasks of the same check set — this removes the
nine duplicated shared PASS lines the gate used to print (docs/internal/records/CONSOLIDATION.md §6, P1).
build() appends the cast exactly as the former scripts' non-check path did. Statement-for-statement
from the former hsl_ohm_assets.py / hsl_priest_assets.py / hsl_mobile_jobs_assets.py.
"""
from pathlib import Path

from hsltools.probes.mobile_jobs import ACTORS as MOBILE_JOBS_ACTORS
from hsltools.sources.actor_walk_frames import DEFAULT_OUTPUT_ROOT
from hsltools.assets.combat_animation import PROGRAMS, ROOT as COMBAT_ROOT, build as combat, check as check_combat
from hsltools.assets.panel_assets import build as panels, check as check_panels
from hsltools.assets.portraits import build as portraits, check as check_portraits
from hsltools.evidence.actor_walk_manifest import check_actor_walk_manifest
from hsltools.registry import Context, ScriptCheckTask, original_archive

OHM_ACTORS = ['003', '061', '062']
OHM_WALK = Path('content/imported/hsl/chapter01/battle001/actor_walk_frames/actor_walk_manifest.json')
SHARED_WALK = DEFAULT_OUTPUT_ROOT / 'actor_walk_manifest.json'


def check_ohm():
    # The formal battle explicitly consumes this existing level manifest. Promoting
    # identical walking art into the global registry would invalidate every other
    # level-local reference without adding a capability to the Ohm battle.
    check_actor_walk_manifest(OHM_WALK, OHM_ACTORS)
    check_combat(); check_portraits(); check_panels()
    print('OHM_ASSETS_PASS actors=003,061,062')


def build_ohm(pak):
    check_actor_walk_manifest(OHM_WALK, OHM_ACTORS)
    combat(pak, OHM_ACTORS); portraits(pak, OHM_ACTORS); panels(pak)
    print('OHM_ASSETS_PASS actors=003,061,062')


def check_priest():
    check_actor_walk_manifest(SHARED_WALK); check_combat(); check_portraits(); check_panels()
    print('PRIEST_ASSETS_PASS actor002 source_binding=SID_PLAYER1')


def build_priest(pak):
    check_actor_walk_manifest(SHARED_WALK, ['002'])
    combat(pak, ['002']); portraits(pak, ['002']); panels(pak)
    print('PRIEST_ASSETS_PASS actor002 source_binding=SID_PLAYER1')


def check_mobile_jobs():
    check_actor_walk_manifest(SHARED_WALK); check_combat(); check_portraits(); check_panels()
    print('MOBILE_JOBS_ASSETS_PASS actors=004,006,028,036')


def build_mobile_jobs(pak):
    check_actor_walk_manifest(SHARED_WALK, MOBILE_JOBS_ACTORS)
    combat(pak, MOBILE_JOBS_ACTORS); portraits(pak, MOBILE_JOBS_ACTORS); panels(pak)
    print('MOBILE_JOBS_ASSETS_PASS actors=004,006,028,036')


# What a cast appends into: the combat manifest and its own actors' frame directories, the
# portrait and panel imports. The chapter01 walk manifest (priest / mobile jobs) is
# actor_walk_manifest:chapter01's output, verified here.
# Reading the current manifests before appending is a read-modify-write of these outputs, not
# an input another task produces; the cross-task inputs are the compiled ANIMAL programs with
# their tracked source (what combat_animation.build binds). The Ohm cast only verifies the
# battle001 level manifest (level_actors:1's output, which itself reads the portraits this cast
# appends): a precondition checked by verify(), not a production input, so not declared as one.
SHARED_OUTPUTS = ((COMBAT_ROOT / 'manifest.json').as_posix(), 'content/imported/hsl/chapter01/portraits/',
                  'content/imported/hsl/shared/panels/')
CAST_ACTORS = {'ohm_assets': OHM_ACTORS, 'priest_assets': ['002'], 'mobile_jobs_assets': MOBILE_JOBS_ACTORS}


class CastAssetsTask(ScriptCheckTask):
    family = 'assets'

    def __init__(self, name: str, script: str, pass_line: str, builder, walk: Path, walk_actors: list[str] | None) -> None:
        self.name = name
        self.pass_line = pass_line
        self.builder = builder
        self.walk = walk
        self.walk_actors = walk_actors
        self.inputs = (PROGRAMS.as_posix(), (COMBAT_ROOT / 'ANIMAL.TXT').as_posix())
        self.outputs = (SHARED_OUTPUTS + tuple(f'{COMBAT_ROOT.as_posix()}/{actor}/' for actor in CAST_ACTORS[name]))
        self.replaces = (f'{script} --check',)
        self.scripts = ('tools/hsltools/assets/job_casts.py',)

    def verify(self, ctx: Context) -> None:
        check_actor_walk_manifest(self.walk, self.walk_actors)
        print(self.pass_line)

    def build(self, ctx: Context) -> None:
        self.builder(original_archive(ctx))


def tasks() -> list[CastAssetsTask]:
    return [
        CastAssetsTask('ohm_assets', 'tools/hsl_ohm_assets.py', 'OHM_ASSETS_PASS actors=003,061,062', build_ohm, OHM_WALK, OHM_ACTORS),
        CastAssetsTask('priest_assets', 'tools/hsl_priest_assets.py', 'PRIEST_ASSETS_PASS actor002 source_binding=SID_PLAYER1',
                       build_priest, SHARED_WALK, None),
        CastAssetsTask('mobile_jobs_assets', 'tools/hsl_mobile_jobs_assets.py', 'MOBILE_JOBS_ASSETS_PASS actors=004,006,028,036',
                       build_mobile_jobs, SHARED_WALK, None),
    ]
