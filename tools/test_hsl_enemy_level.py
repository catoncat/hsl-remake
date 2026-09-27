"""_enemy_level round referee: the draw-point map covers the tracked first-battle sample and names
real remake functions, mapped lines keep draws, the comparator counts agreement; with unicorn and
the documented hsl01.exe present, level 51 enters by the new-level branch and plays round 1 of
the recorded r1 board."""
import copy
import importlib.util
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes._enemy_level as el  # noqa: E402
import hsltools.probes.enemy_turn as et  # noqa: E402
from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402

R1_ORDER = ['actor021_3', 'actor023_2', 'actor021_1', 'actor021_2', 'actor021_4', 'actor021_5', 'actor023_1',
            'actor024_2', 'actor024_1', 'actor026_1', 'actor026_2']


def sample_turns() -> list[dict]:
    return json.loads(et.PACKET.read_text(encoding='utf-8'))['turns']


def remake_functions() -> set[str]:
    names = set()
    for path in (ROOT / 'game').rglob('*.gd'):
        for match in re.finditer(r'^\s*(?:static\s+)?func\s+(\w+)', path.read_text(encoding='utf-8'), re.M):
            names.add(f'{path.stem}.{match.group(1)}')
    return names


class SiteMapTests(unittest.TestCase):
    def test_every_sample_site_is_mapped(self):
        for turn in sample_turns():
            draws = [d for a in turn['actions'] for d in a['draws']] + turn['meta']['handoff']['draws']
            for draw in draws:
                table = et.SITE_MAP if draw['stream'] == 'global' else et.DAMAGE_SITE_MAP
                self.assertIn(draw['site'], table, f'{draw["stream"]} site {draw["site"]} has no remake draw point')

    def test_mapped_names_are_remake_functions(self):
        functions = remake_functions()
        names = [name for name, _, _ in et.SITE_MAP.values() if name] + [v.split(' ')[0] for v in et.DAMAGE_SITE_MAP.values()]
        for name in names:
            self.assertIn(name, functions)
        self.assertEqual([site for site, (name, _, _) in et.SITE_MAP.items() if name is None], [])

    def test_mapped_lines_keep_draws(self):
        turn = sample_turns()[0]
        lines = et.round_lines(turn, et.SITE_MAP)
        draws = [d for line in lines for a in line['actions'] for d in a['draws']]
        self.assertTrue(draws)
        self.assertTrue(all(set(d) == {'site', 'n', 'value'} for d in draws))
        self.assertFalse([d for d in draws if d['site'] in et.DAMAGE_SITE_MAP])
        raw = [d for d in draws if d['site'] in ('AIDecisionRules.select_target', 'AINavigationRules._nearest_stoppable')]
        self.assertTrue(raw and all(d['n'] == 2 and d['value'] in (0, 1) for d in raw))
        self.assertTrue(all(a['draws'] == [] for line in et.round_lines(turn) for a in line['actions']))

    def test_compare_counts_agreement(self):
        lines = et.round_lines(sample_turns()[0], et.SITE_MAP)
        report, totals = el.compare(lines, lines)
        self.assertEqual(totals['agree'], 11)
        self.assertEqual((totals['order'], totals['draws_same'], totals['values_same']), (11, 11, 11))
        self.assertIn('ORACLE_MATCH total agree=11/11', report[-1])
        moved = copy.deepcopy(lines)
        moved[0]['actions'][1]['to'] = [0, 0]
        moved[0]['actions'][2]['draws'] = moved[0]['actions'][2]['draws'][1:]
        report, totals = el.compare(sample_turns()[:1], moved)   # a raw original record is mapped on the fly
        self.assertEqual((totals['agree'], totals['draws_same']), (10, 10))
        self.assertEqual(sum('first differs at #' in line for line in report), 1)

    def test_board_edits(self):
        self.assertEqual(et.edits_board([et.parse_edit('021_4.cell=12/9'), et.parse_edit('023_1.dead=1'),
                                         et.parse_edit('026_1.target=leonard'), et.parse_edit('021_4.hp=5')]),
                         {'units': {'021_4': [12, 9]}, 'dead': ['023_1'], 'targets': {'026_1': 'leonard'},
                          'live': {'021_4': {'hp': 5}}})


@unittest.skipUnless(importlib.util.find_spec('unicorn') and ORIGINAL_EXE.is_file(),
                     'needs unicorn (uv run --with unicorn==2.1.4) and the documented hsl01.exe')
class LevelExecutionTests(unittest.TestCase):
    def test_level51_round1_from_the_recorded_board(self):
        board = el.load_board(el.BOARDS, 'r1')
        turn = el.run_level(ORIGINAL_EXE, 51, board, 1, (1, 2))
        meta = turn['meta']
        self.assertEqual((meta['stop'], meta['rounds'], meta['unattributed_draws'], meta['unnamed']), ('round_end', [1, 1], {}, []))
        self.assertEqual([a['actor'] for a in turn['actions']], R1_ORDER)
        cells = {u['id']: u['coord'] for u in json.loads(el.battle_path(51).read_text())['playable_units']}
        self.assertEqual({a['actor']: a['from'] for a in turn['actions']}, {a: cells[a] for a in R1_ORDER})
        self.assertEqual([h['actor'] for h in meta['handoffs']], ['leonard'])
        self.assertEqual(meta['board'], ['actor021_3.speed=16', 'actor023_2.speed=16', 'actor024_2.speed=13'])


if __name__ == '__main__':
    unittest.main()
