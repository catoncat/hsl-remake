import copy
import json
import unittest
from hsltools.probes.campaign_actor import PACKET, check
from hsltools.data.campaign_actors import build, OUT
from hsltools.model.jobs import CAMPAIGN_ACTORS
from hsltools.data.role_profiles import build as roles, source_rows
from hsltools.probes.job_stats import sources


class CampaignActorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet=json.loads(PACKET.read_text());cls.templates=build()

    def test_original_proof_and_all_requested_sources(self):
        check(self.packet)
        self.assertEqual(set(self.templates),set(CAMPAIGN_ACTORS))
        for code,value in self.templates.items():
            self.assertEqual(json.loads((OUT/(code+'.json')).read_text()),value)

    def test_corrupted_proof_is_rejected(self):
        for section in ['stats','growth','learning','bindings','anchors']:
            p=copy.deepcopy(self.packet);p[section].pop()
            with self.assertRaises(ValueError):check(p)
        p=copy.deepcopy(self.packet);p['stats'][0]['native'][0]['values']['max_hp']+=1
        with self.assertRaises(ValueError):check(p)
        p=copy.deepcopy(self.packet);p['special_tables']['98']['tier']=2
        with self.assertRaises(ValueError):check(p)

    def test_source_rows_jobs_and_control_are_distinct(self):
        players,_,defines=sources();profiles=roles()['actors'];records=source_rows()
        for code,t in self.templates.items():
            row=players[code];profile=profiles[code]
            self.assertEqual(profile['job_source']['code'],defines[row['job']])
            self.assertEqual(records[code]['fields']['code']['value'],str(int(code)))
            self.assertEqual(profile['evidence_tier'],'static-derived')
            self.assertEqual(profile['initial_level']['declared'],'level' in row)
            self.assertEqual(t['source']['traversal']['flying'],bool(int(row.get('move_fly',0))))
            self.assertEqual(t['source']['traversal']['no_block'],bool(int(row.get('no_block',0))))
        self.assertFalse(self.templates['024']['actor']['player_commandable'])
        self.assertTrue(self.templates['009']['actor']['player_commandable'])
        self.assertEqual(self.templates['064']['actor']['battle_actor_role'],'friendly_ai')

    def test_no_substitute_for_gulu_weapon_or_empty_learning_branch(self):
        gulu=self.templates['008']
        self.assertEqual(gulu['actor']['weapon_code'],32)
        # range3CellCircle is compiled from the source range table now, so the template carries no blocker.
        self.assertEqual(gulu['source']['runtime_blockers'],[])
        self.assertEqual(self.packet['special_tables']['96']['rows'],[])
        self.assertEqual(self.packet['magic_levels']['96'],[])
        self.assertEqual(self.packet['special_tables']['93']['tier'],2)
        self.assertEqual(self.packet['special_tables']['95']['tier'],2)
        self.assertNotEqual(self.packet['special_tables']['98']['address'],self.packet['special_tables']['95']['address'])


if __name__=='__main__':unittest.main()
