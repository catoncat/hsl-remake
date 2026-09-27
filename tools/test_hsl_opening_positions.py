"""Opening positions of every battle: no unit starts on a cell it could not stand on, and
no unit's foot point sits on an opaque pixel of a stand-object sprite (a house, a well, a
tree trunk) — the class of 「人和房子的贴图站在一起」 (level 1 歐姆村).

Passability is the WRD terrain plus the battle's terrain_overrides read with the generator's
own rule (hsltools.levels.scenario.impassable: height 0xff or the 0x74000 map flags). A STORY
walk endpoint never ends on such a cell; an install cell (EVEF or actInsertObject, no STORY
movement) may, because the original installs without a terrain test (static-derived
0x45e307 / 0x407cc0 / 0x4080b0; level 6's villager 061_1 on the 0xff cell (25,15),
runtime-measured). The opening rosters of levels 5 and 6 are compared cell by cell with the
original's live records (runtime_observations/battle_005, battle_006 original_units.json).
Building sprites (houses, graves, doors, wells) are checked against each unit's feet.
Ablations: every recorded blocked source cell is refused by the same rule; moving the
install cells off blocked terrain (the pre-R5-L4b generator) breaks the level 6 receipt;
level 1's combined objects placed with the pre-P8 offset reading put units on house pixels.
"""
import glob
import json
import os
import re
import unittest
from pathlib import Path

from PIL import Image

from hsltools.levels.battle import nearest_free
from hsltools.levels.scenario import apply_terrain_overrides, impassable

ROOT = Path(__file__).resolve().parents[1]
CELL = 32
# Hand-written development trials (GrowthLifecycleTrial, PriestTrial, WaterStrikeTrial,
# MobileJobsTrial) reuse the level-51 map with template cells on a 0xff cliff; they are not
# campaign battles and keep their explicit fixture placement.
DEVELOPMENT_TRIALS = {'growth_lifecycle_trial.json', 'mobile_jobs_trial.json', 'priest_trial.json', 'water_strike_trial.json'}
# Hand-built fixtures on the level-51 map (not campaign battles): the first-battle template
# roster and two development trials standing in the level-51 foliage.
FIXTURES = {'first_battle.json', 'large_actor_trial.json', 'weapon_effect_trial.json'}
# Building sprites (houses, graves, doors, the well) a unit's feet may not sit under.
BUILDING_SHAPES = ('HOUSE', 'WELL', 'DOOR')
# Units whose walkable start cell lies north of a building whose foreground sprite then
# covers their feet (the building's own cells are the WRD 0x4000 / 0xff cells the
# passability test already refuses). Level 1's villager behind the well roof is the same
# case. Whether the building is drawn over the unit follows the original draw order
# (docs/evidence_packets/static_reverse/original_draw_order.md): the ground units stand
# behind it as in the original; 雷特 in 576–578 flies and is drawn over it.
SPRITE_OVERLAP_ALLOWED = {
    ('battle_038.json', 'actor034_1'), ('battle_059.json', 'hu'), ('battle_576.json', 'rett'), ('battle_577.json', 'rett'), ('battle_578.json', 'rett'),
    ('battle_059.json', 'claudie'), ('battle_075.json', 'actor049_2'),
    ('battle_900.json', 'hanks'), ('battle_900.json', 'actor062_3'), ('battle_900.json', 'actor062_4'), ('battle_900.json', 'actor031_2'), ('battle_900.json', 'actor030_2'),
    ('ohm_village_battle.json', 'actor061_3'),
}
# Points of a standing unit around its cell-centre foot (the feet a foreground sprite would hide).
BODY_PROBES = [(0, 0), (-8, -8), (8, -8)]
# Flying actors' extra depth rows (ActorRuntime.FLYING_DEPTH_ROWS, read from the script).
FLYING_DEPTH_ROWS = int(re.search(r'const FLYING_DEPTH_ROWS := (\d+)', (ROOT / 'game/battle/runtime/ActorRuntime.gd').read_text(encoding='utf-8')).group(1))
FLYING_ACTORS = {code for code, row in json.loads((ROOT / 'content/generated/hsl/skills/initial_book.json').read_text(encoding='utf-8'))['actors'].items()
                 if row.get('traversal', {}).get('flying')}
# The original's live roster at the opening (runtime-measured, lane M1／R5-L6): battle →
# (receipt, snapshot label). Live records carry the PLAYERS code; grid = object +4/+8 ÷ 32.
ORIGINAL_OPENINGS = {
    'battle_005.json': ('docs/evidence_packets/runtime_observations/battle_005/original_units.json', 'm2-first-control'),
    'battle_006.json': ('docs/evidence_packets/runtime_observations/battle_006/original_units.json', 'l6-open'),
}


def _res(path: str) -> Path:
    return ROOT / path.removeprefix('res://')


def _foreground(record: dict) -> bool:
    """BattleSceneStage._map_object_runtime_layer: foreground sprites draw over every actor."""
    hint = record.get('runtime_layer_hint', '')
    if hint in ('foreground', 'back', 'backdrop'):
        return hint == 'foreground'
    return record.get('object_fields', {}).get('obj_plane', {}).get('value') == 'planeObject20'


def _battles():
    for path in sorted(glob.glob(str(ROOT / 'content/battles/*.json'))):
        battle = json.loads(Path(path).read_text(encoding='utf-8'))
        if battle.get('playable_units') and battle.get('resources', {}).get('terrain'):
            yield os.path.basename(path), battle


class OpeningPositionTests(unittest.TestCase):
    def test_every_unit_starts_on_a_free_cell_story_walks_on_passable_ones(self):
        checked = on_blocked_installs = 0
        for name, battle in _battles():
            if name in DEVELOPMENT_TRIALS:
                continue
            grid = apply_terrain_overrides(json.loads(_res(battle['resources']['terrain']).read_text())['grid'], battle.get('terrain_overrides', []))
            seen = set()
            for unit in battle['playable_units']:
                x, y = unit['coord']
                checked += 1
                self.assertTrue(0 <= y < len(grid) and 0 <= x < len(grid[0]), f'{name} {unit["id"]} starts outside the map {unit["coord"]}')
                if impassable(grid[y][x]):
                    source = unit.get('position_source', {})
                    # An object only inserted by the STORY (no walk) starts on its install pixel too
                    # (R6-L10: STORY037's gems sit on their pillars); a STORY walker on its walk
                    # endpoint (OPENFIX: the opening snapshot's cell:blocked walkers).
                    walks = [step for step in source.get('story_movements', []) if not str(step.get('action', '')).startswith('actInsertObject')]
                    self.assertTrue(source.get('install_on_blocked_cell') and not walks or source.get('story_endpoint_on_blocked_cell') and walks,
                                    f'{name} {unit["id"]} starts on an impassable cell {unit["coord"]} without the recorded reason')
                    on_blocked_installs += 1
                self.assertNotIn((x, y), seen, f'{name} {unit["id"]} shares its start cell')
                seen.add((x, y))
        self.assertGreater(checked, 2000)
        self.assertGreater(on_blocked_installs, 0)

    def test_level_5_and_6_openings_match_the_original_cell_by_cell(self):
        for name, (receipt, label) in ORIGINAL_OPENINGS.items():
            battle = json.loads((ROOT / 'content/battles' / name).read_text(encoding='utf-8'))
            self.assertEqual(self._roster_cells(battle['playable_units']), self._original_cells(receipt, label), name)

    def test_ablation_relocating_blocked_install_cells_breaks_the_level6_receipt(self):
        battle = json.loads((ROOT / 'content/battles/battle_006.json').read_text(encoding='utf-8'))
        grid = apply_terrain_overrides(json.loads(_res(battle['resources']['terrain']).read_text())['grid'], battle.get('terrain_overrides', []))
        units = [dict(unit) for unit in battle['playable_units']]
        taken = {tuple(unit['coord']) for unit in units}
        for unit in units:
            if unit.get('position_source', {}).get('install_on_blocked_cell'):
                taken.discard(tuple(unit['coord']))
                unit['coord'] = list(nearest_free(grid, tuple(unit['coord']), taken))
                taken.add(tuple(unit['coord']))
        relocated = self._roster_cells(units)
        original = self._original_cells(*ORIGINAL_OPENINGS['battle_006.json'])
        self.assertEqual(sorted(set(relocated) ^ set(original)), [(61, 24, 14), (61, 25, 15)])

    @staticmethod
    def _roster_cells(units: list) -> list:
        return sorted((int(unit['actor_id']), *unit['coord']) for unit in units)

    @staticmethod
    def _original_cells(receipt: str, label: str) -> list:
        snapshots = json.loads((ROOT / receipt).read_text(encoding='utf-8'))['snapshots']
        units = next(snapshot['units'] for snapshot in snapshots if snapshot['label'] == label)
        return sorted((unit['code'], *unit['grid']) for unit in units if not unit['removed'])

    def test_recorded_blocked_sources_are_refused(self):
        refused = 0
        for name, battle in _battles():
            grid = apply_terrain_overrides(json.loads(_res(battle['resources']['terrain']).read_text())['grid'], battle.get('terrain_overrides', []))
            for unit in battle['playable_units']:
                blocked = unit.get('position_source', {}).get('blocked_source_cell') or unit.get('attack_range_evidence', {}).get('blocked_source_cell')
                if blocked and unit.get('coord') != blocked:
                    bx, by = blocked
                    if 0 <= by < len(grid) and 0 <= bx < len(grid[0]) and impassable(grid[by][bx]):
                        refused += 1
        # Large-footprint starts (13's 051, 59's 060, 80's 068) keep their blocked cells too, like the original's.
        self.assertEqual(refused, 0)

    def test_no_unit_stands_under_a_building_sprite(self):
        overlaps = self._sprite_overlaps(old_combined_reading=False)
        self.assertEqual(overlaps, SPRITE_OVERLAP_ALLOWED)

    def test_building_overlaps_follow_the_original_draw_order(self):
        """Original (0x4300f0 / 0x43f31e / 0x443849): depth bucket = foot row + 1, +10 for a
        flyer; a non-ATTACKFLAG stand object's bucket = (anchor y + 16) >> 5; lower buckets
        draw first. Remake: z = foot y (+ FLYING_DEPTH_ROWS * 32 for a flyer) against the
        object's anchor y. Ablation: without the flying rows the remake draws 576–578's
        雷特 under the grave the original draws him over."""
        details = {}
        self._sprite_overlaps(old_combined_reading=False, details=details)
        self.assertEqual(set(details), SPRITE_OVERLAP_ALLOWED)
        original_front, ablated = set(), set()
        for key, (unit, anchor_y) in details.items():
            flying = unit['actor_id'] in FLYING_ACTORS
            foot_y = unit['coord'][1] * CELL + CELL // 2
            original_behind = unit['coord'][1] + 1 + (10 if flying else 0) < (anchor_y + 16) >> 5
            remake_behind = foot_y + (FLYING_DEPTH_ROWS * CELL if flying else 0) < anchor_y
            self.assertEqual(remake_behind, original_behind, f'{key}: remake and original draw order differ')
            if not original_behind:
                original_front.add(key)
            if (foot_y < anchor_y) != original_behind:
                ablated.add(key)
        rett_576_578 = {(f'battle_{level}.json', 'rett') for level in (576, 577, 578)}
        self.assertEqual(original_front, rett_576_578)
        self.assertEqual(ablated, rett_576_578)

    def test_ablation_old_combined_offset_puts_level1_units_on_houses(self):
        overlaps = self._sprite_overlaps(old_combined_reading=True, only={'ohm_village_battle.json'})
        self.assertTrue({('ohm_village_battle.json', 'leonard'), ('ohm_village_battle.json', 'hu')} <= overlaps, f'the pre-P8 reading (EVEF point + child offset) put 雷歐納德 and 琥 under a house: {sorted(overlaps)}')

    def _sprite_overlaps(self, old_combined_reading: bool, only=None, details=None) -> set:
        shared = json.loads((ROOT / 'content/imported/hsl/chapter01/map_object_alignment.json').read_text())['shapes']
        images = {}
        found = set()
        for name, battle in _battles():
            if (only and name not in only) or name in DEVELOPMENT_TRIALS | FIXTURES or not battle['resources'].get('map_objects'):
                continue
            manifest = json.loads(_res(battle['resources']['map_objects']).read_text())
            alignment = battle['resources'].get('map_object_alignment')
            shapes = json.loads(_res(alignment).read_text())['shapes'] if alignment else shared
            previews = manifest.get('previews', {})
            objects = [(p, 0, 0) for p in manifest.get('placements', []) if p.get('role') == 'map_object']
            for combined in manifest.get('combined_placements', []):
                first = combined['children'][0]['offset_xy_candidate'] if combined['children'] else [0, 0]
                for child in combined['children']:
                    shift = (first[0], first[1]) if old_combined_reading else (0, 0)
                    objects.append((child, shift[0], shift[1]))
            for unit in battle['playable_units']:
                fx, fy = unit['coord'][0] * CELL + CELL // 2, unit['coord'][1] * CELL + CELL // 2
                for obj, sx, sy in objects:
                    sid = obj['shape_resource_id']
                    if not _foreground(obj) or not any(word in sid.upper() for word in BUILDING_SHAPES) or sid not in shapes:
                        continue
                    preview = previews.get(sid, {}).get('res_path', f'res://content/imported/hsl/shared/shape_previews/map_object/{sid}.png')
                    if preview not in images:
                        path = _res(preview)
                        images[preview] = Image.open(path).convert('RGBA') if path.exists() else None
                    image = images[preview]
                    if image is None:
                        continue
                    ox, oy = shapes[sid]['draw_origin']
                    for bx, by in BODY_PROBES:
                        lx, ly = fx + bx - (obj['candidate_x'] + sx - ox), fy + by - (obj['candidate_y'] + sy - oy)
                        if 0 <= lx < image.width and 0 <= ly < image.height and image.getpixel((int(lx), int(ly)))[3] > 128:
                            found.add((name, unit['id']))
                            if details is not None:
                                details[(name, unit['id'])] = (unit, obj['candidate_y'] + sy)
                            break
        return found


if __name__ == '__main__':
    unittest.main()
