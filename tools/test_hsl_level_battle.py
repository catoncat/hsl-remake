import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.legacy import authored_levels
from hsltools.levels.battle import (
    ENCOUNTER_PARTY_SLOTS,
    ENCOUNTERS,
    LEVELS,
    LevelBattleTask,
    ROOT,
    _apply_object_install,
    _check_encounter_titles,
    build,
    dead_message_ids,
    install_dead_message,
    install_player_mode,
    script_dead_message,
    script_title_name,
    story_word_writes,
    install_title_name,
    install_word,
    build_encounter,
    cast_gaps,
    missing_portraits,
    placed_actor_ids,
    output_path,
    tasks,
    trace_opening,
    treasure_path,
    treasures,
    unit_id_renames)


class LevelBattleTests(unittest.TestCase):
    def test_level_5_matches_tracked_output_and_source_shape(self):
        result = build(5)
        self.assertEqual(json.loads(output_path(5).read_text()), result)
        units = result['playable_units']
        roles = {}
        for unit in units:
            roles[unit['battle_actor_role']] = roles.get(unit['battle_actor_role'], 0) + 1
        self.assertEqual(roles, {'player_controlled': 4, 'enemy_ai': 9})
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual([by_id[k]['coord'] for k in ['leonard', 'tina', 'hu', 'hanks']], [[12, 9], [14, 12], [10, 11], [9, 10]])
        self.assertEqual(sorted(result['script_actor_templates']), ['obj_Story_Level5_Enemy36', 'obj_Story_Level5_Enemy38'])
        self.assertEqual({k: v['source_actor_id'] for k, v in result['script_actor_templates'].items()},
                         {'obj_Story_Level5_Enemy36': '036', 'obj_Story_Level5_Enemy38': '038'})
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'fail_0', 'win_0'])
        self.assertEqual(result['scenario_rules']['initial_objective_phase'], 'clear')
        self.assertEqual(result['result_labels'], {'win_0': '呼嘯平原 · 敵軍已清除', 'fail_0': '呼嘯平原 · 雷歐納德 陣亡'})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_005.json')
        for key in ['mode', 'end_card', 'skip_battle', 'end_exit', 'next_level_event']:
            self.assertNotIn(key, result['opening'])
        self.assertEqual(result['opening']['first_control_event_id'], 'first_control_ready')
        self.assertEqual(missing_portraits(5, json.loads((ROOT / 'content/generated/hsl/chapter01/battle005_seed.json').read_text()),
                                           json.loads((ROOT / 'content/battles/story_005.json').read_text())), [])

    def test_level_5_treasures_are_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle005_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_005.json').read_text())
        data = treasures(5, seed, preview)
        self.assertEqual(json.loads(treasure_path(5).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['5']['chests']],
                         [('5:17', [9, 18], [257])])
        self.assertEqual(data['levels']['5']['level_sha256'], seed['sources']['level']['sha256'])

    def test_level_3_starts_hanks_enemy_undead_and_wires_win_profile(self):
        result = build(3)
        self.assertEqual(json.loads(output_path(3).read_text()), result)
        self.assertEqual(len(result['playable_units']), 17)
        by_id = {unit['id']: unit for unit in result['playable_units']}
        self.assertEqual(sum(unit['player_commandable'] for unit in result['playable_units']), 3)
        self.assertEqual(by_id['hanks']['battle_actor_role'], 'enemy_ai')
        self.assertFalse(by_id['hanks']['player_commandable'])
        self.assertTrue(by_id['hanks']['undead'])
        self.assertEqual(result['result_labels'], {'win_0': '盜賊洞窟 · 漢克斯加入隊伍'})
        self.assertEqual(result['rule_adapter'], 'winfail')
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_003.json')

    def test_level_6_matches_tracked_output_and_source_shape(self):
        result = build(6)
        self.assertEqual(json.loads(output_path(6).read_text()), result)
        units = result['playable_units']
        roles = {}
        for unit in units:
            roles[unit['battle_actor_role']] = roles.get(unit['battle_actor_role'], 0) + 1
        # STORY006: four registered slots walk in from the north gate, three soldiers
        # and a captain follow; the EVEF cast is twelve villagers and seven soldiers.
        self.assertEqual(roles, {'player_controlled': 4, 'friendly_ai': 12, 'enemy_ai': 11})
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual([by_id[k]['coord'] for k in ['leonard', 'tina', 'hu', 'hanks']], [[23, 8], [22, 6], [20, 7], [21, 9]])
        self.assertEqual(by_id['guard024_1']['position_source']['opening_wait_round'], 3)
        self.assertNotIn('ai_wait_remaining', by_id['guard024_1'], 'the live wait comes from the opening timeline, not the unit')
        # Soldiers are enemy-process objects although PLAYERS 023/024 are pmPlayer rows;
        # villagers follow the level-1 pmNPCPlayer reading.
        self.assertTrue(all(by_id[f'actor023_{n}']['battle_actor_role'] == 'enemy_ai' for n in range(1, 8)))
        self.assertTrue(all(unit['battle_actor_role'] == 'friendly_ai' and not unit['player_commandable'] for unit in units if unit['actor_id'] in ('061', '062')))
        # The villager whose EVEF cell is a 0xff cliff stays on it, as the original installs it
        # (runtime-measured (25,15), docs/evidence_packets/runtime_observations/battle_006/original_units.json).
        villager = by_id['actor061_1']
        self.assertEqual((villager['position_source'].get('install_on_blocked_cell'), villager['coord']), (True, [25, 15]))
        self.assertNotIn('blocked_source_cell', villager['position_source'])
        self.assertTrue(all(unit['position_evidence_tier'] == 'resource-derived' for unit in units))
        # Winfail inserts create units from one npc template per object symbol.
        self.assertEqual({k: (v['kind'], v['token'], v['source_actor_id']) for k, v in result['script_actor_templates'].items()},
                         {'obj_Story_Level6_Enemy23': ('npc', 'SID_ENEMY023', '023'), 'obj_Story_Level6_Enemy24': ('npc', 'SID_ENEMY024', '024')})
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'event_1', 'event_2', 'fail_0', 'win_0', 'win_1', 'win_2'])
        self.assertEqual(result['rule_adapter'], 'winfail')
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_006.json')
        for key in ['mode', 'end_card', 'skip_battle', 'end_exit', 'next_level_event']:
            self.assertNotIn(key, result['opening'])
        self.assertEqual(result['opening']['first_control_event_id'], 'first_control_ready')

    def test_level_7_formal_roster_and_registered_shera(self):
        result = build(7)
        self.assertEqual(json.loads(output_path(7).read_text()), result)
        units = {unit['id']: unit for unit in result['playable_units']}
        self.assertEqual(len(units), 25)
        self.assertEqual(sum(unit['player_commandable'] for unit in units.values()), 4)
        self.assertEqual({unit['battle_actor_role'] for unit in units.values()}, {'player_controlled', 'enemy_ai'})
        self.assertEqual([units[name]['battle_actor_role'] for name in ['leonard', 'tina', 'hu', 'hanks']], ['player_controlled'] * 4)
        self.assertEqual(units['actor036_3']['position_source']['unaligned_story_endpoint'], [160, 120])
        self.assertEqual((units['actor036_3']['position_evidence_tier'], units['actor036_3']['coord']), ('resource-derived', [5, 3]))
        self.assertEqual(result['script_actor_templates']['obj_Story_Player5']['kind'], 'registered_player')
        shera = result['script_actor_templates']['obj_Story_Player5']
        self.assertEqual((shera['source_actor_id'], shera['token'], shera['actor']['id'], shera['actor']['actor_id']), ('005', 'SID_雪拉', 'shera', '005'))
        self.assertTrue(shera['actor']['player_commandable'])
        self.assertEqual(shera['actor']['battle_actor_role'], 'player_controlled')
        self.assertEqual({key: value['source_actor_id'] for key, value in result['script_actor_templates'].items()},
                         {'obj_Story_Player5': '005', 'obj_Story_Level7_Enemy23': '023', 'obj_Story_Level7_Enemy24': '024'})
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'event_1', 'event_2', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '寧靜之森 · 敵軍已清除'})

    def test_level_7_treasures_are_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle007_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_007.json').read_text())
        data = treasures(7, seed, preview)
        self.assertEqual(json.loads(treasure_path(7).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['7']['chests']],
                         [('7:76', [18, 18], [217, 246]), ('7:77', [24, 11], [225])])
    def test_level_10_matches_tracked_output_and_source_shape(self):
        result = build(10)
        self.assertEqual(json.loads(output_path(10).read_text()), result)
        units = result['playable_units']
        roles = {}
        for unit in units:
            roles[unit['battle_actor_role']] = roles.get(unit['battle_actor_role'], 0) + 1
        self.assertEqual(roles, {'player_controlled': 2, 'enemy_ai': 4})
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual([by_id[k]['coord'] for k in ['leonard', 'tina', 'actor034_1', 'actor034_2', 'actor035_1', 'actor035_2']],
                         [[13, 6], [13, 4], [4, 12], [8, 6], [24, 13], [22, 18]])
        self.assertTrue(all(unit['position_evidence_tier'] == 'resource-derived' for unit in units))
        self.assertEqual({k: (v['kind'], v['source_actor_id']) for k, v in result['script_actor_templates'].items()}, {
            'obj_Story_Player3': ('registered_player', '003'),
            'obj_Story_Player4': ('registered_player', '004'),
            'obj_Story_Player5': ('registered_player', '005'),
            'obj_Story_Level10_Enemy034': ('npc', '034'),
            'obj_Story_Level10_Enemy035': ('npc', '035'),
        })
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']),
                         ['event_0', 'event_1', 'event_2', 'event_3', 'event_4', 'event_5', 'event_6', 'event_7', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '帕尼西亞城　廢墟 · 怪物已清除'})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_010.json')

    def test_level_10_treasure_is_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle010_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_010.json').read_text())
        data = treasures(10, seed, preview)
        self.assertEqual(json.loads(treasure_path(10).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['10']['chests']],
                         [('10:13', [25, 7], [4, 238])])

    def test_level_12_matches_tracked_output_and_static_objects(self):
        result = build(12)
        self.assertEqual(json.loads(output_path(12).read_text()), result)
        units = result['playable_units']
        self.assertEqual(len(units), 103)
        self.assertEqual(sum(unit['player_commandable'] for unit in units), 9)
        self.assertEqual([u['id'] for u in units if u.get('install_if_carried')], ['gulu', 'claudie'])
        self.assertEqual({unit['battle_actor_role'] for unit in units}, {'player_controlled', 'enemy_ai', 'friendly_ai'})
        # The 62 Enemy101 hull pieces are registered actors like the original's (no_showshape: not drawn).
        self.assertEqual(sum(unit['actor_id'] == '101' and unit.get('no_showshape', False) for unit in units), 62)
        self.assertEqual([next(unit for unit in units if unit['id'] == name)['coord'] for name in ['leonard', 'tina', 'hu', 'hanks', 'shera', 'rett', 'howl']],
                         [[21, 18], [27, 21], [27, 15], [27, 25], [18, 27], [18, 28], [19, 47]])
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']),
                         ['event_0', 'event_1', 'event_2', 'event_3', 'event_4', 'event_5', 'event_6', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '巴瀚納海峽 · 船戰勝利', 'fail_0': '巴瀚納海峽 · 雷歐納德 陣亡', 'fail_1': '巴瀚納海峽 · 船殼危機'})
        self.assertEqual(set(result['opening']['story_objects']), {'obj_Story_Level_RainBOSS', 'obj_Story_Level_Rain', 'obj_Story_Level_RainSound'})
        self.assertEqual({key: (value['kind'], value['source_actor_id']) for key, value in result['script_actor_templates'].items()},
                         {'obj_Story_Level_Enemy39': ('npc', '039'), 'obj_Story_Level_Enemy48': ('npc', '048'), 'obj_Story_Level_Enemy48_2': ('npc', '048')})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_012.json')

    def test_level_19_matches_tracked_output_and_source_shape(self):
        result = build(19)
        self.assertEqual(json.loads(output_path(19).read_text()), result)
        units = result['playable_units']
        roles = {}
        for unit in units:
            roles[unit['battle_actor_role']] = roles.get(unit['battle_actor_role'], 0) + 1
        self.assertEqual(roles, {'player_controlled': 1, 'enemy_ai': 4})
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual([by_id[k]['coord'] for k in ['rett', 'actor041_1', 'actor041_2', 'actor041_3', 'actor041_4']],
                         [[32, 23], [31, 16], [36, 19], [45, 27], [43, 31]])
        self.assertEqual(by_id['rett']['actor_id'], '006')
        self.assertEqual({k: (v['kind'], v['source_actor_id']) for k, v in result['script_actor_templates'].items()}, {
            'obj_Story_Player1': ('registered_player', '001'),
            'obj_Story_Player2': ('registered_player', '002'),
            'obj_Story_Player3': ('registered_player', '003'),
            'obj_Story_Player4': ('registered_player', '004'),
            'obj_Story_Player5': ('registered_player', '005'),
            'obj_Story_Player7': ('registered_player', '007'),
            'obj_Story_Level_Enemy41': ('npc', '041'),
            'obj_Story_Level_Enemy43': ('npc', '043'),
            'obj_Story_Level_Enemy38': ('npc', '038'),
        })
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']),
                         ['event_0', 'event_1', 'event_2', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '利魯瑪山地 · 敵軍已清除'})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_019.json')

    def test_level_19_treasures_are_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle019_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_019.json').read_text())
        data = treasures(19, seed, preview)
        self.assertEqual(json.loads(treasure_path(19).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['19']['chests']],
                         [('19:9', [1, 2], [228]), ('19:10', [46, 6], [225]), ('19:11', [18, 22], [242, 244])])

    def test_level_26_matches_tracked_output_and_source_shape(self):
        result = build(26)
        self.assertEqual(json.loads(output_path(26).read_text()), result)
        units = result['playable_units']
        roles = {}
        for unit in units:
            roles[unit['battle_actor_role']] = roles.get(unit['battle_actor_role'], 0) + 1
        self.assertEqual(roles, {'player_controlled': 9, 'enemy_ai': 12, 'friendly_ai': 26})
        self.assertEqual(result['conditional_party']['slots'], ['gulu'])
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual([by_id[k]['coord'] for k in ['leonard', 'tina', 'hu', 'hanks', 'shera', 'rett', 'howl', 'claudie']],
                         [[28, 18], [16, 12], [20, 12], [19, 15], [26, 15], [28, 16], [10, 9], [13, 7]])
        self.assertEqual((by_id['actor038_1']['coord'], by_id['actor038_1']['position_source'].get('story_endpoint_on_blocked_cell')), ([16, 5], True))
        self.assertEqual({k: (v['kind'], v['source_actor_id']) for k, v in result['script_actor_templates'].items()},
                         {'obj_Story_Level_Enemy35': ('npc', '035')})
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '亞雷比斯 · 敵軍已清除'})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_026.json')

    def test_level_26_treasures_are_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle026_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_026.json').read_text())
        data = treasures(26, seed, preview)
        self.assertEqual(json.loads(treasure_path(26).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['26']['chests']],
                         [('26:52', [2, 15], [68])])

    def test_level_17_matches_tracked_output_and_exec_mode_source_shape(self):
        result = build(17)
        self.assertEqual(json.loads(output_path(17).read_text()), result)
        self.assertEqual((len(result['playable_units']), sum(u['player_commandable'] for u in result['playable_units'])), (24, 5))
        self.assertEqual(set(result['scenario_rules']['status_timelines']), {'win_0', 'fail_0', 'fail_1', 'fail_2', 'event_0', 'event_1', 'event_2'})
        self.assertEqual(result['result_labels'], {'win_0': '艾瓦台地 · 敵軍已清除', 'fail_0': '艾瓦台地 · 雷歐納德 陣亡', 'fail_1': '艾瓦台地 · 艾瓦遺民 陣亡', 'fail_2': '艾瓦台地 · 嚎 陣亡'})
        self.assertEqual(set(result['script_actor_templates']), {'obj_Story_Player7', 'obj_Story_Level_Enemy35', 'obj_Story_Level_Enemy36', 'obj_Story_Level_Enemy37', 'obj_Story_Level_Enemy38'})
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_017.json')
        win_events = result['scenario_rules']['status_timelines']['win_0']['events']
        self.assertIn('actSetPlayerExecMode', [event['script_action_name'] for event in win_events])


    def test_level_37_wires_job_up_templates_and_formal_roster(self):
        result = build(37)
        self.assertEqual(json.loads(output_path(37).read_text()), result)
        # R6-L10: the ten STORY037 guardians (five 067 gems, five 066) are fielded too.
        self.assertEqual((len(result['playable_units']), sum(u['player_commandable'] for u in result['playable_units'])), (30, 9))
        gems = [u for u in result['playable_units'] if u['actor_id'] == '067']
        self.assertEqual([u['id'] for u in gems], [f'guard067_{n}' for n in range(1, 6)])
        self.assertEqual(result['opening']['actor_bindings']['SID_ENEMY067/5']['unit_id'], 'guard067_5')
        # Slot 4 (176,688) + (0,32) is the cell holding (176,720): (5,22), the gem on its pillar.
        self.assertEqual((gems[4]['coord'], gems[4]['player_mode'], gems[4]['max_hp']), ([5, 22], 0x870000, 1))
        gulu = next(u for u in result['playable_units'] if u['id'] == 'gulu')
        # EVEF record 10 咕嚕(有才產生) at (384,1312), walked (0,-192) by STORY037 → cell (12,35).
        self.assertEqual((gulu['actor_id'], gulu['battle_actor_role'], gulu['install_if_carried'], gulu['coord'], gulu['position_evidence_tier']),
                         ('008', 'player_controlled', True, [12, 35], 'resource-derived'))
        self.assertEqual(gulu['position_source']['evef_record_index'], 10)
        self.assertEqual(result['opening']['actor_bindings']['SID_咕嚕/1'], {'unit_id': 'gulu', 'actor_id': '008', 'placement_xy': [384, 1312]})
        self.assertEqual((result['conditional_party']['policy'], result['conditional_party']['slots'], result['conditional_party']['unavailable_slots']),
                         ('install_if_carried', ['gulu'], []))
        self.assertFalse(any('skipped' in item for item in result['unresolved_semantics']))
        # 0x4348f0: record+0x60 (008 job_up_code obj_Player8Up1 816) → global.obs 816 obj_Data7 = 17 (original_level37_tokens.md).
        self.assertEqual(result['scenario_rules']['job_up_targets'], {'008': '017'})
        self.assertEqual(result['scenario_rules']['job_up_templates']['017']['actor_id'], '017')
        self.assertEqual(result['resources']['battle_seed'], 'res://content/generated/hsl/chapter01/battle037_seed.json')

    def test_level_59_uses_targetable_standing_enemy060(self):
        result = build(59)
        self.assertEqual(json.loads(output_path(59).read_text()), result)
        self.assertEqual((len(result['playable_units']), sum(u['player_commandable'] for u in result['playable_units'])), (10, 9))
        boss = next(unit for unit in result['playable_units'] if unit['actor_id'] == '060')
        self.assertEqual((boss['id'], boss['class_id'], boss['move_point'], boss['coord']), ('actor060_1', 'Enemy060', 0, [40, 16]))
        self.assertEqual(result['opening']['actor_bindings']['SID_ENEMY060/1']['unit_id'], 'actor060_1')
        self.assertEqual(result['scenario_rules']['initial_objective_phase'], 'defeat_boss')
        self.assertNotIn('static_enemy_counts', result['scenario_rules'])

    def test_level_77_late_transform_uses_true_enemy059_template(self):
        result = build(77)
        self.assertEqual(json.loads(output_path(77).read_text()), result)
        template = result['script_actor_templates']['obj_Story_Level_Enemy59']
        self.assertEqual((template['source_actor_id'], template['actor']['actor_id'], template['actor']['class_id']), ('059', '059', 'Enemy059'))

    def test_level_902_matches_tracked_output_and_system_arrival_shape(self):
        result = build(902)
        self.assertEqual(json.loads(output_path(902).read_text()), result)
        self.assertEqual((len(result['playable_units']), sum(u['player_commandable'] for u in result['playable_units'])), (19, 5))
        self.assertEqual(set(result['scenario_rules']['status_timelines']), {'win_0', 'fail_0', 'fail_1', 'event_0', 'event_1', 'event_2', 'event_3', 'event_4', 'event_5', 'event_6', 'event_7', 'event_8', 'event_9', 'event_10', 'event_11'})
        self.assertEqual(set(result['script_actor_templates']), {'obj_Story_Player7', 'obj_Story_Level_Enemy35', 'obj_Story_Level_Enemy36', 'obj_Story_Level_Enemy37', 'obj_Story_Level_Enemy38'})
        self.assertEqual(result['result_labels'], {'win_0': '艾瓦台地　尋 · 找到通路', 'fail_0': '艾瓦台地　尋 · 雷歐納德 陣亡', 'fail_1': '艾瓦台地　尋 · 嚎 陣亡'})
        event_names = [event['script_action_name'] for timeline in result['scenario_rules']['status_timelines'].values() for event in timeline['events']]
        self.assertIn('actRandomSetSysArrivePos', event_names)
        self.assertEqual(result['resources']['treasures'], 'res://content/generated/hsl/treasures/battle_902.json')

    def test_special_formal_profiles_match_tracked_outputs(self):
        expected = {
            15: (19, 8, {'win_0', 'fail_0', 'fail_1', 'event_0', 'event_1', 'event_2', 'event_3', 'event_4', 'event_5'}, {'obj_Story_Player8', 'obj_Story_Level_Enemy34', 'obj_Story_Level_Enemy35', 'obj_Story_Level_Enemy33', 'obj_Story_Level_Enemy38'}),
            18: (22, 6, {'win_0', 'win_1', 'fail_0', 'event_0'}, set()),
            900: (34, 5, {'win_0', 'fail_0', 'fail_1', 'fail_2', 'event_0', 'event_1'}, set()),
            904: (5, 1, {'win_0', 'fail_0', 'fail_1', 'event_0', 'event_1', 'event_2'}, {'obj_Story_Level_Enemy41', 'obj_Story_Level_Enemy43', 'obj_Story_Level_Enemy38'}),
            901: (22, 5, {'win_0', 'fail_0', 'event_0', 'event_1', 'event_2', 'event_3', 'event_4', 'event_5'}, {'obj_Story_Enemy31', 'obj_Story_Enemy27', 'obj_Story_Enemy30'}),
            41: (25, 9, {'win_0', 'fail_0', 'event_0', 'event_1', 'event_2'}, {'obj_Story_Level_Enemy33', 'obj_Story_Level_Enemy35', 'obj_Story_Level_Enemy34'}),
            78: (24, 8, {'fail_0', 'event_0', 'event_1', 'event_2'}, set()),
        }
        for level, (unit_count, player_count, statuses, templates) in expected.items():
            result = build(level)
            self.assertEqual(json.loads(output_path(level).read_text()), result)
            self.assertEqual((len(result['playable_units']), sum(u['player_commandable'] for u in result['playable_units'])), (unit_count, player_count))
            self.assertEqual(set(result['scenario_rules']['status_timelines']), statuses)
            self.assertEqual(set(result.get('script_actor_templates', {})), templates | ({k for k in result.get('script_actor_templates', {}) if k.startswith('obj_Story_Player')} if level == 904 else set()))
            self.assertTrue(result['resources']['treasures'].endswith(f'battle_{level:03d}.json'))
        self.assertEqual({k: v['source_actor_id'] for k, v in build(904)['script_actor_templates'].items() if k.startswith('obj_Story_Player')},
                         {f'obj_Story_Player{slot}': actor for slot, actor in [('1', '001'), ('2', '002'), ('3', '003'), ('4', '004'), ('5', '005'), ('7', '007')]})
    def test_level_29_formal_roster_and_conditional_party_slot(self):
        result = build(29)
        self.assertEqual(json.loads(output_path(29).read_text()), result)
        units = {unit['id']: unit for unit in result['playable_units']}
        self.assertEqual(len(units), 26)
        self.assertEqual(sum(unit['player_commandable'] for unit in units.values()), 8)
        # EVEF 咕嚕(有才產生): fielded install_if_carried, walked by STORY029 like the rest of the cast.
        self.assertTrue(units['gulu']['install_if_carried'])
        self.assertEqual(units['gulu']['position_evidence_tier'], 'resource-derived')
        self.assertEqual([t['action'] for t in units['gulu']['position_source']['story_movements']], ['actWalk'])
        self.assertEqual(result['conditional_party']['slots'], ['gulu'])
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'event_1', 'fail_0', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '約瑟河 · 敵軍已清除', 'fail_0': '約瑟河 · 雷歐納德 陣亡'})
        self.assertNotIn('script_actor_templates', result)
        self.assertFalse(any('skipped' in item for item in result['unresolved_semantics']))

    def test_level_34_formal_roster_and_player_mode_event(self):
        result = build(34)
        self.assertEqual(json.loads(output_path(34).read_text()), result)
        units = {unit['id']: unit for unit in result['playable_units']}
        self.assertEqual(len(units), 23)
        self.assertEqual(sum(unit['player_commandable'] for unit in units.values()), 4)
        self.assertEqual({key: value['source_actor_id'] for key, value in result['script_actor_templates'].items()}, {
            'obj_Story_Level_Enemy23': '023',
            'obj_Story_Level_Enemy44': '044',
        })
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['event_0', 'event_1', 'fail_0', 'fail_1', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '沙羅尼亞近郊 · 敵軍已清除', 'fail_0': '沙羅尼亞近郊 · 緹娜 陣亡'})
        # win_0 is armed by WINFAIL034 event_1, never at hand-off (an early arm ends the battle at once).
        self.assertNotIn('initial_status_overrides', result['scenario_rules'])
        event_one = result['scenario_rules']['status_timelines']['event_1']['events']
        mode_changes = [event for event in event_one if event.get('script_action_name') == 'actSetPlayerMode']
        self.assertEqual(len(mode_changes), 9)
        self.assertTrue(all(event['params']['mode'] == 'pmEnemy' and event['params']['flag'] == 0 for event in mode_changes))
        self.assertTrue(any('event_1' in item and 'pmEnemy' in item for item in result['unresolved_semantics']))

    def test_install_player_mode_follows_the_constructor_order(self):
        # 0x407ec0: PLAYERS mode, obj_Data9 != 0 swaps pmPlayer<->pmEnemy, obj_X1 overrides.
        players = {'023': {'mode': 'pmPlayer'}, '036': {'mode': 'pmEnemy'}, '062': {'mode': 'pmNPCPlayer'}}
        defines = {'pmPlayer': 0x10000, 'pmEnemy': 0x20000, 'pmNPC': 0x40000, 'pmPlayerEnemy': 0x30000, 'pmNPCPlayer': 0x50000}
        self.assertEqual(install_player_mode('023', {}, players, defines)[0], 0x10000)
        self.assertEqual(install_player_mode('023', {'obj_Data9': '1'}, players, defines)[0], 0x20000)
        self.assertEqual(install_player_mode('036', {'obj_Data9': '1'}, players, defines)[0], 0x10000)
        self.assertEqual(install_player_mode('062', {'obj_Data9': '1'}, players, defines)[0], 0x50000, 'the swap only touches pmPlayer / pmEnemy')
        self.assertEqual(install_player_mode('062', {'obj_X1': 'pmPlayerEnemy'}, players, defines)[0], 0x30000)
        self.assertEqual(install_player_mode('036', {'obj_X1': 'pmNPC'}, players, defines)[0], 0x40000)
        self.assertEqual(install_player_mode('023', {'obj_Data9': '1', 'obj_X1': 'pmNPC'}, players, defines),
                         (0x40000, 'PLAYERS pmPlayer, obj_Data9 1 swaps pmPlayer<->pmEnemy, obj_X1 pmNPC overrides (0x407ec0)'))
        with self.assertRaises(ValueError):
            install_player_mode('023', {'obj_X1': 'WAV\\BOMB0004.WAV'}, players, defines)
        actor = {'growth_profile': {'source': {'hit_point': 2}}, 'max_hp': 43, 'hp': 43}
        _apply_object_install(actor, '023', {'obj_Data9': '1', 'obj_HitPoint': '50'}, players, defines)
        self.assertEqual((actor['player_mode'], actor['object_hit_point'], actor['growth_profile']['source']['hit_point'], actor['max_hp'], actor['hp']),
                         (0x20000, 50, 52, 93, 93))
        plain = {'growth_profile': {'source': {'hit_point': 2}}, 'max_hp': 43, 'hp': 43}
        _apply_object_install(plain, '023', {}, players, defines)
        self.assertNotIn('object_hit_point', plain)
        self.assertEqual((plain['player_mode'], plain['max_hp']), (0x10000, 43))

    def test_install_title_name_follows_the_constructor_words(self):
        # 0x407ec0 at 0x408004..0x408036: obj_Data5 low word -> live +0x1c 稱號, non-zero high
        # word -> live +0x04 name; the panel name is that +0x04 text verbatim (portraits.panel_name).
        from hsltools.native.sources import sources
        players, _, _ = sources()
        self.assertEqual(install_title_name('062', {'obj_Data7': '62'}, players), {})
        worker = install_title_name('062', {'obj_Data7': '62', 'obj_Data5': '1235'}, players)
        self.assertEqual((worker['title'], worker['display_name']), ('搬運工人', '???'), 'a nameless row keeps name 306 ??? (0x434d10 verbatim); only the 稱號 changes')
        self.assertEqual(worker['name_source'], 'obj_Data5 1235: low word 1235 → live +0x1c 稱號 (0x407ec0)')
        named = install_title_name('064', {'obj_Data7': '64', 'obj_Data5': '1235'}, players)
        self.assertEqual((named['title'], named['display_name']), ('搬運工人', '克里夫'), 'a named row keeps its name; only the 稱號 changes')
        renamed = install_title_name('062', {'obj_Data7': '62', 'obj_Data5': str((382 << 16) | 656)}, players)
        self.assertEqual((renamed['title'], renamed['display_name']), ('村民', '法蘭克'), 'a high word installs the name id')
        title_only_name = install_title_name('062', {'obj_Data7': '62', 'obj_Data5': str(382 << 16)}, players)
        self.assertEqual(title_only_name, {'display_name': '法蘭克', 'name_source': 'obj_Data5 25034752: low word 0 → live +0x1c 稱號, high word 382 → live +0x04 name (0x407ec0)'},
                         'a zero low word leaves the 稱號 alone')
        self.assertEqual((install_word('x', {'obj_Data8': '0x08d708d8'}, 'obj_Data8'), install_word('x', {'obj_Data8': '-1'}, 'obj_Data8'), install_word('x', {}, 'obj_Data8')),
                         (0x08d708d8, -1, 0))
        with self.assertRaises(ValueError):
            install_word('x', {'obj_HitPoint': 'WAV\\BOMB0004.WAV'}, 'obj_HitPoint')

    def test_install_dead_message_follows_the_constructor_and_death_reads(self):
        # 0x407ec0 at 0x407fd0..0x407fe7 writes obj_Data8 to live +0x14 (−1 → 0); the death
        # branches 0x43ef91 / 0x4434b2 read first = high word, second = low word, a zero half
        # copying the other, and pick between two with 0x458c10 & 1.
        self.assertEqual(dead_message_ids(0), [])
        self.assertEqual(dead_message_ids(373), [373], 'a low-word-only id speaks itself for both picks')
        self.assertEqual(dead_message_ids(304 << 16), [304], 'a high-word-only id (the player install word) likewise')
        self.assertEqual(dead_message_ids(0x08d708d8), [2263, 2264])
        self.assertEqual(dead_message_ids((374 << 16) | 375), [374, 375], 'the PLAYERS pair order: hi = first, lo = second')
        from hsltools.native.sources import sources
        players, _, _ = sources()
        self.assertEqual(install_dead_message('062', {'obj_Data7': '62'}, players, None), {})
        installed = install_dead_message('062', {'obj_Data7': '62', 'obj_Data8': '373'}, players, None)
        villager = installed['dead_message']
        self.assertEqual((villager['speaker'], [(m['id'], m['text']) for m in villager['messages']]), ('村民', [('373', '啊--------------！')]))
        self.assertEqual(installed['dead_message_source'], 'obj_Data8 373 → live +0x14 (0x407ec0); death read 0x43ef91／0x4434b2 offers [373] (0x458c10 & 1 picks between two)')
        worker = install_dead_message('062', {'obj_Data7': '62', 'obj_Data8': '374'}, players, '搬運工人')['dead_message']
        self.assertEqual(worker['speaker'], '搬運工人', 'the speaker is the installed 稱號 (live +0x1c) when obj_Data5 set one')
        cleared = install_dead_message('024', {'obj_Data7': '24', 'obj_Data8': '-1'}, players, None)
        self.assertEqual(cleared, {'dead_message': {'speaker': '', 'messages': []}, 'dead_message_source': 'obj_Data8 -1 → live +0x14 (0x407ec0); −1 clears the PLAYERS dead_message pair'})
        packed = install_dead_message('021', {'obj_Data7': '21', 'obj_Data8': '0x08d708d8'}, players, None)['dead_message']
        self.assertEqual((packed['speaker'], [m['id'] for m in packed['messages']]), ('拉爾斯帝國兵', ['2263', '2264']))

    def test_install_words_reach_placed_and_inserted_units(self):
        # Level 6: twelve pmPlayerEnemy villagers (obj_X1), ten swapped 023 soldiers and the
        # +30 HP captain 024 inserted by STORY006; level 24: six placed 024 with +50 HP and
        # three pmNPC riders inserted by WINFAIL024; level 34: 023 arrive pmPlayer (+20 HP).
        six = {unit['id']: unit for unit in build(6)['playable_units']}
        self.assertTrue(all(six[f'actor06{n}_{i}']['player_mode'] == 0x30000 for n in (1, 2) for i in range(1, 6)))
        self.assertEqual(six['actor062_1']['player_mode_source'], 'PLAYERS pmNPCPlayer, obj_X1 pmPlayerEnemy overrides (0x407ec0)')
        self.assertTrue(all(six[f'actor023_{n}']['player_mode'] == 0x20000 for n in range(1, 8)))
        # The max_hp snapshot follows the installed side (align_birth_hp): the obj_Data9-swapped
        # pmEnemy 024 lose the HP level term — 72／92, the original's opening board (lane DATA9,
        # runtime-measured); 73／93 before CUTMIRROR were the template-mode snapshot.
        self.assertEqual((six['guard024_1']['object_hit_point'], six['guard024_1']['max_hp'], six['guard024_1']['growth_profile']['source']['hit_point']), (30, 72, 40))
        self.assertEqual(six['leonard']['player_mode'], 0x10000)
        twenty_four = build(24)
        placed = [unit for unit in twenty_four['playable_units'] if unit['actor_id'] == '024']
        self.assertEqual(len(placed), 6)
        self.assertTrue(all((unit['object_hit_point'], unit['max_hp'], unit['battle_actor_role']) == (50, 92, 'enemy_ai') for unit in placed))
        riders = {symbol: spec['actor'] for symbol, spec in twenty_four['script_actor_templates'].items() if spec['source_actor_id'] in ('049', '053', '054')}
        self.assertEqual(len(riders), 3)
        self.assertTrue(all(actor['player_mode'] == 0x40000 and actor['battle_actor_role'] == 'enemy_ai' for actor in riders.values()))
        thirty_four = build(34)['script_actor_templates']
        arriving = thirty_four['obj_Story_Level_Enemy23']['actor']
        self.assertEqual((arriving['player_mode'], arriving['battle_actor_role'], arriving['object_hit_point'], arriving['max_hp']), (0x10000, 'friendly_ai', 20, 49))
        self.assertEqual(thirty_four['obj_Story_Level_Enemy44']['actor']['player_mode'], 0x10000, 'obj_Data9 swaps this pmEnemy row to pmPlayer until WINFAIL034 event 4')
        thirty = {unit['id']: unit for unit in build(30)['playable_units']}
        klodi = thirty['actor053_1']
        self.assertEqual((klodi['actor_id'], klodi['class_id'], klodi['player_mode'], klodi['battle_actor_role'], klodi['growth_profile']['job_code'], klodi['growth_profile']['source']['hit_point']),
                         ('053', 'Enemy053', 0x20000, 'enemy_ai', 99, 220), 'Enemy053(克羅蒂) is built from its obj_Data7 row 053 (jobDarkSwordMan, 220 HP), though the preview draws SHAPE\\009')
        three = {unit['id']: unit for unit in build(3)['playable_units']}
        self.assertEqual((three['hanks']['player_mode'], three['hanks']['battle_actor_role']), (0x20000, 'enemy_ai'))
        self.assertTrue(three['hanks']['player_mode_source'].endswith('; profile role_overrides enemy_ai'))
        # obj_Data5: level 17's three placed workers (062, 1235) and the inserted 隊長 024 (977)
        # of levels 6 / 7 / 901 carry their own 稱號; every other unit leaves the row's.
        seventeen = build(17)
        workers = [unit for unit in seventeen['playable_units'] if unit['actor_id'] == '062']
        self.assertEqual(len(workers), 3)
        self.assertTrue(all((unit['title'], unit['display_name']) == ('搬運工人', '???') for unit in workers))
        self.assertTrue(all('title' not in unit and 'display_name' not in unit for unit in seventeen['playable_units'] if unit['actor_id'] != '062'))
        self.assertEqual(six['guard024_1']['title'], '兵隊長')
        nine_o_one = build(901)['playable_units']
        self.assertEqual([unit['title'] for unit in nine_o_one if unit['actor_id'] == '024'], ['兵隊長'] * 3)
        self.assertTrue(all('title' not in unit for unit in nine_o_one if unit['actor_id'] == '023'))
        # obj_Data8: level 34's villagers speak 373 (their row has no dead_message); level 24's
        # placed 024 and level 44's placed 023 carry −1 (silent); level 44's inserted 021 / 022
        # pack 2263 / 2264; level 17's workers speak 374 under their installed 稱號; units
        # whose object leaves the word alone (level 6's villagers) carry no dead_message.
        villagers = [unit for unit in build(34)['playable_units'] if unit['actor_id'] == '062']
        self.assertEqual([(unit['dead_message']['speaker'], [m['id'] for m in unit['dead_message']['messages']]) for unit in villagers], [('村民', ['373'])] * 3)
        self.assertTrue(all((unit['dead_message'], unit['dead_message_source']) == ({'speaker': '', 'messages': []}, 'obj_Data8 -1 → live +0x14 (0x407ec0); −1 clears the PLAYERS dead_message pair') for unit in placed))
        forty_four = build(44)
        self.assertEqual(len([unit for unit in forty_four['playable_units'] if unit['actor_id'] == '023' and unit['dead_message']['messages'] == []]), 19)
        self.assertEqual([m['id'] for m in forty_four['script_actor_templates']['obj_Story_Level_Enemy21']['actor']['dead_message']['messages']], ['2263', '2264'])
        self.assertEqual([(unit['dead_message']['speaker'], [m['id'] for m in unit['dead_message']['messages']]) for unit in workers], [('搬運工人', ['374'])] * 3)
        self.assertTrue(all('dead_message' not in unit for unit in six.values() if unit['actor_id'] == '062'))
        self.assertEqual([m['id'] for m in six['guard024_1']['dead_message']['messages']], ['957'])

    def test_story_dead_message_is_the_last_writer(self):
        # actSetDeadMessage (opcode 60 → 0x452197 via 0x44fad0(code, serial)) writes live +0x14 =
        # msg1 << 16 | msg2 after the constructor: the STORY opening's lines replace the object
        # word (level 29's two 023 lose their −1 clear for 1684 / 1686 by serial; level 19's
        # 041 keep only 1455 of the row pair) and give the party its lines (741 …) that no
        # PLAYERS row carries; the fail page's dead_messages keep the same lines by token.
        from hsltools.native.sources import sources
        players, _, _ = sources()
        writes = story_word_writes(json.loads((ROOT / 'content/generated/hsl/chapter01/battle029_seed.json').read_text()))
        self.assertEqual([write for write in writes if write[1] == 'SID_ENEMY023'],
                         [('actSetPlayerName', 'SID_ENEMY023', '1', [1659, 376]), ('actSetDeadMessage', 'SID_ENEMY023', '1', [1684, 0]),
                          ('actSetPlayerName', 'SID_ENEMY023', '2', [1662, 376]), ('actSetDeadMessage', 'SID_ENEMY023', '2', [1686, 0])],
                         'each 023 is named (opcode 89) before it gets its farewell')
        twenty_nine = {unit['id']: unit for unit in build(29)['playable_units']}
        # actSetPlayerName (0x451590: [name] → live +0x04, [job name] → +0x1c): 梅爾 and 凱文 under 一般兵,
        # the other two 023 keep the row's panel name; the only two uses in the corpus.
        self.assertEqual([(twenty_nine[f'actor023_{n}'].get('display_name'), twenty_nine[f'actor023_{n}'].get('title')) for n in (1, 2, 3, 4)],
                         [('梅爾', '一般兵'), ('凱文', '一般兵'), (None, None), (None, None)])
        self.assertEqual(twenty_nine['actor023_2']['name_source'], 'STORY029 actSetPlayerName SID_ENEMY023,2,1662,376 → live +0x04 name 1662, +0x1c 稱號 376 (0x451590, after install: last writer wins)')
        self.assertEqual(script_title_name({'actor_id': '023'}, '023', 1659, 377, players, 'test'), {'display_name': '梅爾', 'title': '重裝兵', 'name_source': 'test → live +0x04 name 1659, +0x1c 稱號 377 (0x451590, after install: last writer wins)'})
        self.assertEqual([(twenty_nine[f'actor023_{n}']['dead_message']['speaker'], [m['id'] for m in twenty_nine[f'actor023_{n}']['dead_message']['messages']]) for n in (1, 2, 3, 4)],
                         [('一般兵', ['1684']), ('一般兵', ['1686']), ('', []), ('', [])], 'serial 1 / 2 take the script words, 3 / 4 keep the −1 clear')
        self.assertEqual(twenty_nine['actor023_1']['dead_message']['messages'][0]['text'], '團長........永別了，最後還能見到你......真的太好了..........。')
        self.assertEqual(twenty_nine['actor023_1']['dead_message_source'],
                         'STORY029 actSetDeadMessage SID_ENEMY023,1,1684,0 → live +0x14 = 0x6940000 (0x452197, after install: last writer wins); death read 0x43ef91／0x4434b2 offers [1684]')
        self.assertEqual((twenty_nine['leonard']['dead_message']['speaker'], [m['id'] for m in twenty_nine['leonard']['dead_message']['messages']]), ('雷歐納德', ['741']))
        six = {unit['id']: unit for unit in build(6)['playable_units']}
        self.assertEqual([m['id'] for m in six['guard024_1']['dead_message']['messages']], ['957'], 'WINFAIL006 addresses the inserted 隊長 at run time, not the placed one')
        self.assertEqual([(six[unit_id]['dead_message']['speaker'], [m['id'] for m in six[unit_id]['dead_message']['messages']]) for unit_id in ('leonard', 'tina', 'hu', 'hanks')],
                         [('雷歐納德', ['741']), ('緹娜', ['846']), ('琥', ['742']), ('漢克斯', ['906'])])
        nineteen = [unit for unit in build(19)['playable_units'] if unit['actor_id'] == '041']
        self.assertEqual([[m['id'] for m in unit['dead_message']['messages']] for unit in nineteen], [['1455']] * 4, 'the script word replaces the PLAYERS pair 1454 / 1455')
        # The writer helper: a packed pair keeps first = high, second = low; the installed 稱號 stays the speaker.
        packed = script_dead_message({'actor_id': '023', 'title': '守衛'}, '023', 374, 375, players, 'test')
        self.assertEqual((packed['dead_message']['speaker'], [m['id'] for m in packed['dead_message']['messages']]), ('守衛', ['374', '375']))
        self.assertEqual(script_dead_message({'actor_id': '023'}, '023', 0, 0, players, 'test')['dead_message'], {'speaker': '', 'messages': []})

    def test_level_6_treasures_are_the_evef_override_words(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle006_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_006.json').read_text())
        data = treasures(6, seed, preview)
        self.assertEqual(json.loads(treasure_path(6).read_text()), data)
        self.assertEqual([(c['id'], c['coord'], c['items']) for c in data['levels']['6']['chests']],
                         [('6:52', [25, 21], [205, 253]), ('6:53', [12, 10], [255, 210])])
        self.assertEqual(data['levels']['6']['level_sha256'], seed['sources']['level']['sha256'])

    def test_opening_trace_follows_inserts_and_walks(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle006_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_006.json').read_text())
        trace = trace_opening(seed, preview)
        self.assertEqual(trace['state']['leonard'], [736, 256])
        self.assertEqual(trace['inserted']['leonard'], {'symbol': 'obj_Story_Player1', 'insert_xy': [1024, 224], 'kind': 'player_slot_install'})
        self.assertEqual(trace['state']['guard024_1'], [992, 256])
        self.assertEqual(trace['wait_rounds'], {'guard024_1': 3})
        self.assertEqual((trace['deleted'], trace['skipped']), (set(), []))
        seed18 = json.loads((ROOT / 'content/generated/hsl/chapter018/battle018_seed.json').read_text()) if (ROOT / 'content/generated/hsl/chapter018/battle018_seed.json').exists() else json.loads((ROOT / 'content/generated/hsl/chapter01/battle018_seed.json').read_text())
        preview18 = json.loads((ROOT / 'content/battles/story_018.json').read_text())
        trace18 = trace_opening(seed18, preview18)
        self.assertIn('actor100_1', trace18['deleted'])
        self.assertEqual(trace18['inserted']['actor100_2']['kind'], 'object_insert')
        self.assertEqual([t['action'] for t in trace['traces']['guard023_2']], ['actInsertObject', 'actWalkPrevInsertObject'])
        # Level 13's opening walks 咕嚕／克羅蒂 (EVEF 有才產生 records the preview leaves out): the
        # trace binds them to their EVEF placement so the walks resolve; object id -1 for
        # the objects inserted last is resolved, not fatal.
        seed13 = json.loads((ROOT / 'content/generated/hsl/chapter01/battle013_seed.json').read_text())
        preview13 = json.loads((ROOT / 'content/battles/story_013.json').read_text())
        trace13 = trace_opening(seed13, preview13)
        self.assertEqual(trace13['skipped'], [])
        self.assertEqual(sorted(trace13['conditional']), ['claudie', 'gulu'])
        self.assertEqual(trace13['bindings']['SID_咕嚕/1']['unit_id'], 'gulu')
        self.assertEqual(len(trace13['inserted']), 9)
        # A party token with neither a preview binding nor an EVEF record is still skipped, not fatal.
        no_record = copy.deepcopy(seed13)
        no_record['placements']['records'] = [r for r in no_record['placements']['records'] if r.get('object_data_fields', {}).get('obj_Data8') != '1']
        self.assertEqual(sorted({s['args'][0] for s in trace_opening(no_record, preview13)['skipped']}), ['SID_克羅蒂', 'SID_咕嚕'])

    def test_level_52_reproduces_the_former_second_battle_roster(self):
        # The former dedicated second_battle.json, now assembled from content/battles/levels/052.json:
        # ids by unit_ids; start cells and reinforcements take the generic readings (traced STORY
        # endpoints, script actor templates). The two 069 winged warriors are fielded as enemies
        # (obj_Data9 1 swaps pmPlayer to pmEnemy, 0x407ec0); the original stands them at (15,14)
        # and (6,13) as enemies (runtime-measured, hsltools/probes/_enemy_level.py level 52).
        result = build(52)
        self.assertEqual(json.loads(output_path(52).read_text()), result)
        self.assertEqual(result['id'], 'battle_002_level52')
        units = result['playable_units']
        self.assertEqual([unit['id'] for unit in units],
                         ['emperor025', 'enemy026_1', 'enemy026_2', 'leonard', 'ally023_1', 'ally023_2', 'ally024_1', 'ally024_2',
                          'enemy069_1', 'enemy069_2', 'enemy021_1', 'enemy021_2', 'enemy021_3', 'enemy021_4', 'enemy021_5', 'enemy021_6', 'enemy021_7', 'enemy021_8'])
        by_id = {unit['id']: unit for unit in units}
        self.assertEqual((by_id['emperor025']['actor_id'], by_id['emperor025']['coord'], by_id['emperor025']['max_hp']), ('025', [10, 13], 91))
        self.assertEqual(by_id['emperor025']['evef_instance']['overrides'], {'find_range': 10, 'wait_round': 8})
        self.assertEqual([by_id[k]['coord'] for k in ('leonard', 'ally023_1', 'ally023_2', 'ally024_1', 'ally024_2')], [[10, 35], [12, 37], [8, 37], [6, 39], [14, 39]])
        self.assertEqual([by_id[k]['battle_actor_role'] for k in ('ally023_1', 'ally024_2', 'enemy026_1', 'enemy021_1')], ['friendly_ai', 'friendly_ai', 'enemy_ai', 'enemy_ai'])
        # The four rear inserts walk to cell-boundary pixels (256,800) / (192,864) / (480,800) /
        # (416,864): integer division like every other STORY endpoint, no profile pin.
        self.assertEqual([by_id[f'enemy021_{n}']['coord'] for n in range(1, 9)], [[8, 15], [10, 17], [12, 15], [13, 18], [8, 25], [6, 27], [15, 25], [13, 27]])
        for n in range(5, 9):
            self.assertEqual(by_id[f'enemy021_{n}']['position_evidence_tier'], 'resource-derived')
            self.assertNotIn('profile_coord', by_id[f'enemy021_{n}']['position_source'])
        self.assertEqual(by_id['enemy021_5']['position_source']['story_endpoint'], [256, 800])
        self.assertEqual(by_id['leonard']['dead_message']['messages'][0]['id'], '394')
        self.assertNotIn('excluded_source_actors', result)
        self.assertEqual([(by_id[k]['actor_id'], by_id[k]['coord'], by_id[k]['battle_actor_role']) for k in ('enemy069_1', 'enemy069_2')],
                         [('069', [15, 14], 'enemy_ai'), ('069', [6, 13], 'enemy_ai')])
        self.assertEqual(result['result_labels'], {'win_0': '惡夢的終曲 · 法蘭克已擊敗', 'fail_0': '惡夢的終曲 · 雷歐納德 陣亡'})
        rules = result['scenario_rules']
        # WINFAIL052 event 1 inserts are script actor templates like every other level's; no
        # spawn-cell policy and no win / fail / event mirror of the WINFAIL.
        template = result['script_actor_templates']['obj_Story_Level52_Enemy21']
        self.assertEqual((template['kind'], template['token'], template['actor']['class_id'], template['actor']['battle_actor_role']), ('npc', 'SID_ENEMY021', 'Enemy021', 'enemy_ai'))
        self.assertEqual(list(result['script_actor_templates']), ['obj_Story_Level52_Enemy21'])
        for key in ('reinforcement_class_id', 'reinforcement_placement_evidence', 'win', 'fail'):
            self.assertNotIn(key, rules)
        self.assertEqual((rules['events'], rules['reinforcements'], rules['reinforcement_spawn_cells']), ({}, [], []))
        self.assertEqual(rules['status_timelines']['event_1']['playable_event_count'], 8, 'the four insert / walk pairs are played by the cutscene from the committed transaction')
        bindings = result['opening']['actor_bindings']
        self.assertEqual((bindings['SID_ENEMY025/1']['unit_id'], bindings['SID_PLAYER0/1']['unit_id']), ('emperor025', 'leonard'))
        self.assertEqual(bindings['obj_Story_Level52_Enemy21/insert8']['unit_id'], 'enemy021_8')
        self.assertNotIn('story_actors', result)

    def test_level_53_reproduces_the_former_third_battle_roster(self):
        # obj_Story_Player2 installs registered slot 1 = PLAYERS 002 (the preview draws 029);
        # actMoveDispWait slides her down the tower; the pursuers carry
        # actSetPrevInsertObjectAdjustLevel 0,0; the cinematic princess is opening-only cast.
        result = build(53)
        self.assertEqual(json.loads(output_path(53).read_text()), result)
        units = result['playable_units']
        self.assertEqual([unit['id'] for unit in units], ['enemy023_1', 'tina', 'enemy023_2', 'enemy023_3'])
        by_id = {unit['id']: unit for unit in units}
        tina = by_id['tina']
        self.assertEqual((tina['actor_id'], tina['class_id'], tina['coord'], tina['growth_profile']['job_code'], tina['weapon_code']), ('002', 'Player002', [20, 23], 85, 82))
        self.assertEqual([t['action'] for t in tina['position_source']['story_movements']], ['actInsertStoryObject', 'actWalkDispWait', 'actMoveDispWait'])
        self.assertEqual(tina['position_source']['story_endpoint'], [640, 736])
        self.assertEqual(tina['dead_message']['messages'][0]['id'], '694')
        self.assertNotIn('script_insert', by_id['enemy023_1'])
        for guard in ('enemy023_2', 'enemy023_3'):
            self.assertEqual(by_id[guard]['script_insert']['adjust_level'], [0, 0])
            self.assertEqual(by_id[guard]['script_insert']['evidence_tier'], 'resource-derived')
            self.assertEqual(by_id[guard]['battle_actor_role'], 'enemy_ai')
        self.assertEqual([by_id[k]['coord'] for k in ('enemy023_1', 'enemy023_2', 'enemy023_3')], [[30, 36], [29, 24], [27, 23]])
        self.assertEqual([actor['id'] for actor in result['story_actors']], ['actor029_1'])
        self.assertFalse(result['story_actors'][0]['battle_unit'])
        opening = result['opening']
        self.assertEqual(opening['actor_bindings']['SID_PLAYER1/1'], {'unit_id': 'tina', 'actor_id': '002', 'spawn_on_story_object': 'obj_Story_Player2'})
        self.assertEqual(opening['actor_bindings']['SID_ENEMY023/1']['unit_id'], 'enemy023_2')
        self.assertEqual(opening['story_objects']['obj_Story_Player2']['actor_id'], '002')
        rules = result['scenario_rules']
        self.assertEqual(rules['script_fallback']['escape_zone'], [[30, 35], [31, 35], [30, 36], [31, 36]])
        self.assertEqual((rules['events'], rules['reinforcements'], rules['reinforcement_spawn_cells']), ({}, [], []))
        for key in ('reinforcement_class_id', 'reinforcement_placement_evidence', 'win', 'fail'):
            self.assertNotIn(key, rules)
        template = result['script_actor_templates']['obj_Story_Level53_Enemy23']
        self.assertEqual((template['kind'], template['token'], template['actor']['class_id'], template['actor']['battle_actor_role']), ('npc', 'SID_ENEMY023', 'Enemy023', 'enemy_ai'))
        self.assertEqual([m['id'] for m in template['actor']['dead_message']['messages']], ['374', '693'], 'the pursuers keep the obj_Data8 pair of their object row')
        self.assertEqual([rules['status_timelines'][key]['playable_event_count'] for key in ('event_0', 'event_1', 'event_2')], [2, 2, 2])
        self.assertEqual(result['result_labels'], {'win_0': '逃出克萊恩城 · 緹娜 逃出', 'fail_0': '逃出克萊恩城 · 緹娜 被捕'})

    def test_unit_id_renames_follow_opening_order_and_reject_unfielded_tokens(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle053_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_053.json').read_text())
        trace = trace_opening(seed, preview)
        self.assertEqual(trace['adjust_levels'], {'guard023_1': [0, 0], 'guard023_2': [0, 0]})
        self.assertEqual(unit_id_renames(LEVELS[53], trace, preview), {'actor023_1': 'enemy023_1', 'guard023_1': 'enemy023_2', 'guard023_2': 'enemy023_3'})
        self.assertEqual(unit_id_renames({}, trace, preview), {})
        with self.assertRaises(ValueError):
            unit_id_renames({'unit_ids': {'SID_ENEMY999': 'ghost_{n}'}}, trace, preview)
        with self.assertRaises(ValueError):
            unit_id_renames({'unit_ids': {'SID_ENEMY023': 'tina'}}, trace, preview)

    def test_opening_only_cast_is_kept_as_story_actors(self):
        # Level 79: STORY079 deletes the EVEF 058 before first control; the battle keeps the
        # entry for the opening (OpeningStoryObjects._spawn_story_actors) and fields no unit.
        result = json.loads(output_path(79).read_text())
        self.assertEqual([actor['id'] for actor in result['story_actors']], ['actor058_1'])
        self.assertNotIn('actor058_1', {unit['id'] for unit in result['playable_units']})

    def test_winfail_speakers_have_portraits(self):
        seed = json.loads((ROOT / 'content/generated/hsl/chapter01/battle006_seed.json').read_text())
        preview = json.loads((ROOT / 'content/battles/story_006.json').read_text())
        # WINFAIL006's cutscenes are spoken by the party (001-004) and the soldiers; the
        # level manifest (hsl_level_actors.py LEVEL_CASTS[6] speakers) must carry them all.
        self.assertEqual(missing_portraits(6, seed, preview), [])
        manifest = json.loads((ROOT / preview['resources']['portraits'].removeprefix('res://')).read_text())
        self.assertTrue({'001', '002', '003', '004', '023', '024'} <= set(manifest['actors']))

    def test_fieldable_actors_are_cast_and_death_line_speakers_have_portraits(self):
        # Every tracked scenario passes the presentation cast contract; a scenario whose fieldable
        # actor is outside the level cast (encounter 552's Wosfita soldiers 023 before the pool
        # carried them: no walk frames, and a death-line speaker without a portrait) is refused.
        for level in (36, 44, 552):
            document = json.loads(output_path(level).read_text())
            self.assertEqual(cast_gaps(level, document), [], level)
        document = json.loads(output_path(552).read_text())
        self.assertIn('023', placed_actor_ids(document))
        stranger = copy.deepcopy(document)
        stranger['playable_units'][0]['actor_id'] = '025'  # a death-line row the pool does not cast
        gaps = cast_gaps(552, stranger)
        self.assertTrue(gaps)
        self.assertTrue(gaps[0].startswith('025: no walk frames'))
        self.assertTrue(gaps[1].startswith('025: PLAYERS walk sound without a binding'))
        self.assertTrue(gaps[2].startswith('025: death-line speaker without a portrait'))
        # Level 37's script-inserted 052 guardian is bound by the shared job-up audio manifest
        # beside its shared walk frames; without that row it would walk silently.
        level37 = json.loads(output_path(37).read_text())
        self.assertIn('052', placed_actor_ids(level37))
        self.assertEqual(cast_gaps(37, level37), [])
        pool = json.loads((ROOT / 'content/imported/hsl/chapter01/battle500/portraits/manifest.json').read_text())
        self.assertTrue({'001', '008', '023', '024', '041', '043', '048', '049'} <= set(pool['actors']))
        self.assertNotIn('032', pool['actors'])  # cast for walk frames, but 032 has no death line

    def test_encounter_titles_are_derived_from_story_and_world_map(self):
        _check_encounter_titles()
        self.assertEqual(ENCOUNTERS[507], {'point_id': 5, 'title': '呼嘯平原 · 遭遇戰'})
        self.assertEqual(ENCOUNTERS[516], {'point_id': 8, 'title': '菲納斯河畔 · 遭遇戰'})
        self.assertEqual(ENCOUNTERS[537], {'point_id': 12, 'title': '巴瀚納海峽 · 遭遇戰'})
        self.assertIn('008', ENCOUNTER_PARTY_SLOTS)

    def test_profiles_cover_only_assembled_levels(self):
        # Authored levels (content/authored/levelNNN/) carry a battle profile too but are assembled by hsltools.levels.authored.
        self.assertEqual(sorted(level for level in LEVELS if level not in authored_levels()), [3, 5, 6, 7, 10, 12, 13, 15, 17, 18, 19, 21, 22, 24, 26, 28, 29, 30, 31, 32, 33, 34, 36, 37, 38, 39, 40, 41, 43, 44, 45, 51, 52, 53, 59, 73, 75, 76, 77, 78, 79, 80, 900, 901, 902, 903, 904])
        self.assertEqual(sorted(ENCOUNTERS), list(range(501, 579)))
        for level, profile in LEVELS.items():
            self.assertTrue(output_path(level).exists() and (treasure_path(level).exists() or not profile.get('treasures', True)))
            timeline_keys = set(json.loads(output_path(level).read_text())['scenario_rules']['status_timelines'])
            self.assertTrue(set(profile['result_labels']) <= timeline_keys)
        for level in ENCOUNTERS:
            self.assertEqual(json.loads(output_path(level).read_text()), build_encounter(level))

    def test_level38_escape_zone_is_assembled_from_winfail(self):
        scenario = json.loads(output_path(38).read_text())
        self.assertEqual(scenario['scenario_rules']['script_fallback']['escape_zone'], [[7, 3], [7, 4], [7, 5]])

    def test_level51_assembles_the_reviewed_first_battle_formation(self):
        # The first battle runs through the same assembler as every other level: its
        # roster is the EVEF formation after STORY051's 96 px walk (the reviewed
        # first_battle.json template positions), the winfail arrival cell is the gate
        # (267,209) and every WINFAIL051 status compiles to a status timeline.
        scenario = json.loads(output_path(51).read_text())
        first = json.loads((ROOT / 'content/battles/first_battle.json').read_text())
        assembled = [(u['actor_id'], u['battle_actor_role'], tuple(u['coord']), u['hp']) for u in scenario['playable_units']]
        reviewed = [(u['actor_id'], u['battle_actor_role'], tuple(u['coord']), u['hp']) for u in first['playable_units']]
        self.assertEqual(assembled, reviewed)
        self.assertEqual(scenario['rule_adapter'], 'winfail')
        self.assertEqual(scenario['player_unit_id'], 'leonard')
        self.assertEqual(scenario['scenario_rules']['script_fallback']['escape_zone'], [[8, 6]])
        self.assertEqual(sorted(scenario['scenario_rules']['status_timelines']), ['event_0', 'event_1', 'event_2', 'event_3', 'fail_0', 'win_0', 'win_1'])
        self.assertEqual(sorted(scenario['script_actor_templates']), ['obj_Story_Level51_Enemy21', 'obj_Story_Level51_Enemy26', 'obj_Story_Level51_Object1'])

    def test_encounter_504_is_assembled_from_the_seed_alone(self):
        result = build_encounter(504)
        units = result['playable_units']
        # EVEF: nine 有才產生 installs (slots 0-8), all reviewed source slots are
        # conditional player units, plus three Enemy036.
        self.assertEqual([u['id'] for u in units], ['leonard', 'tina', 'hu', 'hanks', 'shera', 'rett', 'howl', 'gulu', 'claudie', 'actor036_1', 'actor036_2', 'actor036_3'])
        self.assertTrue(all(u.get('install_if_carried') for u in units if u['battle_actor_role'] == 'player_controlled'))
        self.assertTrue(all('install_if_carried' not in u for u in units if u['battle_actor_role'] == 'enemy_ai'))
        self.assertEqual({u['actor_id'] for u in units if u['battle_actor_role'] == 'player_controlled'}, set(ENCOUNTER_PARTY_SLOTS))
        self.assertEqual([u['coord'] for u in units[:2]], [[11, 14], [12, 13]])  # EVEF (352,448) / (384,416)
        party = result['conditional_party']
        self.assertEqual(party['policy'], 'install_if_carried')
        self.assertEqual(party['slots'], ['leonard', 'tina', 'hu', 'hanks', 'shera', 'rett', 'howl', 'gulu', 'claudie'])
        self.assertEqual(party['unavailable_slots'], [])
        # Base level 3 map / terrain, the shared encounter pool, the level's own timeline.
        res = result['resources']
        self.assertEqual(res['map_texture'], 'res://content/imported/hsl/chapter01/battle003/level3.png')
        self.assertEqual(res['terrain'], 'res://content/generated/hsl/static/hsl01/level003_terrain.json')
        self.assertTrue(res['actor_walk_manifest'].startswith('res://content/imported/hsl/chapter01/battle500/'))
        self.assertEqual(res['opening_timeline'], 'res://content/imported/hsl/chapter01/battle504/opening_timeline.json')
        self.assertNotIn('script_actor_templates', result)
        self.assertNotIn('treasures', res)
        self.assertEqual(sorted(result['scenario_rules']['status_timelines']), ['fail_0', 'win_0'])
        self.assertEqual(result['result_labels'], {'win_0': '盜賊洞窟 · 敵軍已清除', 'fail_0': '雷歐納德 陣亡'})
        self.assertEqual(result['provenance']['base_level'], 3)

    def test_task_inputs_exist_and_encounters_declare_no_story_preview(self):
        # `hsl affected` maps changed paths onto inputs: every declared input is a tracked
        # path, story levels name their story_NNN.json, encounters (no preview file) do not.
        for task in tasks():
            for path in task.inputs:
                self.assertTrue((ROOT / path).exists(), f'{task.name}: {path}')
        self.assertIn('content/battles/story_005.json', LevelBattleTask(5).inputs)
        self.assertNotIn('content/battles/story_504.json', LevelBattleTask(504).inputs)
        self.assertIn('content/generated/hsl/chapter01/battle504_seed.json', LevelBattleTask(504).inputs)

    def test_encounter_seeds_share_the_base_level_outputs(self):
        for level, base in [(501, 2), (502, 2), (503, 2), (504, 3), (505, 3), (506, 3)]:
            seed = json.loads((ROOT / f'content/generated/hsl/chapter01/battle{level}_seed.json').read_text())
            self.assertEqual((seed['map']['alias_of_level'], seed['map']['shared_png_of_level'], seed['terrain']['shared_packet_of_level']), (base, base, base))
            self.assertEqual(seed['map']['decoded_png'], f'res://content/imported/hsl/chapter01/battle{base:03d}/level{base}.png')
            self.assertEqual(seed['script_objects'], [], 'OBJ-ALL.H-headed encounters keep only script-inserted symbols')


if __name__ == '__main__':
    unittest.main()
