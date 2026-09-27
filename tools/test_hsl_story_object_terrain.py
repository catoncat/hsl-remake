"""Census of script-inserted terrain stand objects (mapobjBlock／mapobjClearWall).

Every actInsertStoryObject(XRange) of such an object in any level seed's STORY／WINFAIL must
be accounted for: a STORY insert (opening, before first control) is a `terrain_overrides`
entry of the level's battle; a WINFAIL insert is a token the winfail interpreter turns into
a loop terrain edit when its event fires (game/sim/TerrainEditRules.gd,
tests/run_story_object_terrain_tests.gd levels 28／39／80), never an opening override, and
the ids its event checks resolve in the battle (STORY028 re-codes its door guards 5000..5003).
docs/evidence_packets/static_reverse/original_story_object_terrain.md
"""
import json
import unittest
from pathlib import Path

from hsltools.levels.scenario import STORY_OBJECT_TERRAIN, apply_terrain_overrides, story_object_terrain_inserts, terrain_overrides

ROOT = Path(__file__).resolve().parents[1]
SEEDS = sorted((ROOT / 'content/generated/hsl/chapter01').glob('battle*_seed.json'))
# WINFAIL terrain inserts WinfailActions turns into loop terrain edits when they fire.
RUNTIME_EDIT_TOKENS = {'actInsertStoryObjectXRange', 'actInsertStoryObject'}
CHECK_TOKENS = {'actCheckEnemy', 'actCheckPlayer'}


class StoryObjectTerrainTests(unittest.TestCase):
    def test_every_terrain_insert_is_applied_or_listed(self):
        seen_levels = set()
        for seed_path in SEEDS:
            level = int(seed_path.name[len('battle'):len('battle') + 3])
            seed = json.loads(seed_path.read_text(encoding='utf-8'))
            inserts = story_object_terrain_inserts(seed)
            if not inserts:
                continue
            seen_levels.add(level)
            battle_path = ROOT / f'content/battles/battle_{level:03d}.json'
            battle = json.loads(battle_path.read_text(encoding='utf-8')) if battle_path.exists() else {}
            applied = {tuple(o['cell']) for o in battle.get('terrain_overrides', [])}
            for insert in inserts:
                cells = {tuple(c) for c in insert['cells']}
                if insert['source'] == 'winfail':
                    self.assertIn(insert['token'], RUNTIME_EDIT_TOKENS, f'level {level}: {insert} is not a token the interpreter edits the map for')
                    self.assertFalse(cells & applied, f'level {level}: a mid-battle edit must not be applied from the start: {insert}')
                    for token in self._event_check_tokens(seed, insert['section']):
                        bound = any(key.split('/')[0] == token for key in battle['opening']['actor_bindings'])
                        self.assertTrue(bound or token.startswith('SID_ENEMY'), f'level {level}: {insert["section"]} checks {token}, which names no unit')
                else:
                    self.assertTrue(battle, f'level {level}: {insert} has no battle to apply it')
                    self.assertTrue(cells <= applied, f'level {level}: {insert} not in terrain_overrides')
        self.assertEqual(seen_levels, {28, 39, 53, 80})

    @staticmethod
    def _event_check_tokens(seed: dict, section_key: str) -> list[str]:
        tokens = []
        for section in seed['scripts']['winfail']['sections']:
            if section['name'] + ('_' + section['codes'][0] if section.get('codes') else '') != section_key:
                continue
            for action in section.get('actions', []):
                for step in action.get('chain', []):
                    if step.get('name') in CHECK_TOKENS:
                        tokens += [str(arg) for arg in step.get('args', [])[1:]]
        return tokens

    def test_overrides_edit_the_grid(self):
        grid = [[{'t': 0x4001, 'b': 0, 'h': 0}, {'t': 2, 'b': 0, 'h': 0}]]
        edited = apply_terrain_overrides(grid, [{'cell': [0, 0], 'clear_flags': 0x4000}, {'cell': [1, 0], 'height': 255}])
        self.assertEqual(edited[0][0]['t'], 1)
        self.assertEqual((edited[0][1]['h'], edited[0][1]['b']), (255, 1))
        self.assertEqual(grid[0][0]['t'], 0x4001, 'the tracked grid is not modified')
        self.assertEqual(set(STORY_OBJECT_TERRAIN), {'mapobjBlock', 'mapobjClearWall'})

    def test_story_block_is_static_and_winfail_walls_are_runtime_edits(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle053_seed.json').read_text(encoding='utf-8'))
        self.assertEqual([(o['cell'], o['evidence_tier']) for o in terrain_overrides(53, seed)], [([20, 21], 'static-derived')])
        for level in (28, 80):
            seed = json.loads((ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json').read_text(encoding='utf-8'))
            self.assertEqual(terrain_overrides(level, seed), [], f'level {level}: its ClearWall doors open when their events fire')
        battle = json.loads((ROOT / 'content/battles/battle_028.json').read_text(encoding='utf-8'))
        self.assertEqual({key: b['unit_id'] for key, b in battle['opening']['actor_bindings'].items() if 'object_id' in b},
                         {'5000/1': 'guard050_6', '5001/1': 'guard050_7', '5002/1': 'guard050_8', '5003/1': 'guard050_9'})


if __name__ == '__main__':
    unittest.main()
