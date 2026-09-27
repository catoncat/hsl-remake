import copy
import json
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.position_equipment as probe
from hsltools.data.equipment import build
from hsltools.data.skill_book import build as book
from hsltools.data.attack_ranges import SOURCE, compile_ranges, weapon_ranges, ITEM_SOURCE


class PositionEquipmentTests(unittest.TestCase):
    def test_original_returns_and_boundaries(self):
        packet=json.loads(probe.PACKET.read_text())
        probe.check(packet)
        for mutate in ['value','boundary','bytes']:
            broken=copy.deepcopy(packet)
            if mutate=='value':broken['cases'][0]['native']['value']+=1
            elif mutate=='boundary':broken['cases'][0]['normal_return']=False
            else:broken['anchors'][0]['bytes']='00'+broken['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):probe.check(broken)

    def test_source_abilities_and_separate_equipment(self):
        items=build()['items'];actors=book()['actors']
        self.assertEqual([k for k,v in actors.items() if v['move_magic_use']],['020','059'])
        for code,move,extra in [('232',True,False),('233',False,True),('236',True,True)]:
            self.assertTrue(items[code]['supported'])
            self.assertEqual((items[code]['move_magic_use'],items[code]['add_attack_range']),(move,extra))
        self.assertTrue(items['69']['supported'])
        self.assertTrue(items['69']['double_attack'])
        self.assertEqual(items['69']['attack_range'], 'range5CellShoot')

    def test_source_range_indices_not_synthetic_dilation(self):
        patterns=compile_ranges(SOURCE.read_bytes().decode('cp950'))
        self.assertEqual([patterns[k]['index'] for k in ['range1Cell','range2Cell','range3Cell']],[1,2,3])
        self.assertEqual(len(patterns['range3Cell']['offsets']),12)
        self.assertNotIn([1,1],patterns['range3Cell']['offsets'])
        weapons = weapon_ranges(ITEM_SOURCE.read_bytes().decode('cp950'))
        self.assertEqual(weapons['0'], 'range0Cell')
        self.assertEqual(weapons['61'], 'range3CellShoot')
        self.assertEqual(weapons['69'], 'range5CellShoot')
        self.assertTrue(set(weapons.values()) <= {'range0Cell','range1Cell','range2Cell','range3CellShoot','range4CellShoot','range5CellShoot','range3CellCircle','range3CellThrust','range5CellCircle'})
