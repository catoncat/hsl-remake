import json
import unittest
from pathlib import Path

from hsltools.levels import story_scene

ROOT = Path(__file__).resolve().parents[1]


class StorySceneTests(unittest.TestCase):
    def test_level_58_scene_matches_tracked_output_and_binds_cast(self) -> None:
        scenario = story_scene.build(58)
        tracked = json.loads((ROOT / "content/battles/story_058.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertEqual(scenario["level_kind"], "story")
        self.assertEqual(scenario["rule_adapter"], "story_scene")
        self.assertEqual(len(scenario["story_actors"]), 12)
        self.assertEqual(scenario["opening"]["next_level_event"], [60, 60])
        bindings = scenario["opening"]["actor_bindings"]
        self.assertEqual(bindings["SID_PLAYER0/1"]["unit_id"], "leonard")
        self.assertEqual(bindings["SID_ENEMY058/1"]["actor_id"], "058")
        self.assertEqual(sum(1 for key in bindings if key.startswith("SID_ENEMY024/")), 8)
        self.assertIn("obj_Story_Level58_Star", scenario["opening"]["story_objects"])

    def test_referenced_resources_exist(self) -> None:
        for level in sorted(story_scene.LEVELS):
            scenario = story_scene.build(level)
            for key, res_path in scenario["resources"].items():
                self.assertTrue(res_path.startswith("res://"), key)
                self.assertTrue((ROOT / res_path[len("res://"):]).exists(), f"level {level} {key}: {res_path}")
            for spec in scenario["opening"]["story_objects"].values():
                if "preview" in spec:
                    self.assertTrue((ROOT / spec["preview"][len("res://"):]).exists())

    def test_level_60_captive_scene_has_no_player_and_points_to_level_53(self) -> None:
        scenario = story_scene.build(60)
        tracked = json.loads((ROOT / "content/battles/story_060.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertIsNone(scenario["player_unit_id"])
        self.assertEqual(len(scenario["story_actors"]), 15)
        self.assertEqual(scenario["opening"]["next_level_event"], [53, 53])
        self.assertEqual(scenario["opening"]["actor_bindings"]["SID_ENEMY029/1"]["actor_id"], "029")

    def test_level_53_opening_preview_installs_the_player_slot_and_ends_on_a_card(self) -> None:
        scenario = story_scene.build(53)
        tracked = json.loads((ROOT / "content/battles/story_053.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertEqual(scenario["status"], "opening-preview-provisional")
        self.assertEqual(scenario["opening"]["end_event_id"], "first_control_ready")
        self.assertEqual(scenario["opening"]["end_behavior"], "battle_not_remade_card")
        self.assertIsNone(scenario["opening"]["next_level_event"], "the opening sets no next level; winfail053 owns [1,1]")
        bindings = scenario["opening"]["actor_bindings"]
        self.assertEqual(bindings["SID_PLAYER1/1"], {"unit_id": "tina", "actor_id": "029", "spawn_on_story_object": "obj_Story_Player2"})
        self.assertEqual(bindings["obj_Story_Level53_Enemy23/insert1"]["insert_xy"], [1056, 768])
        self.assertEqual(bindings["obj_Story_Level53_Enemy23/insert2"]["unit_id"], "guard023_2")
        self.assertEqual(bindings["SID_ENEMY023/1"]["unit_id"], "guard023_1", "the speaking soldier is the first inserted guard (remake binding)")
        objects = scenario["opening"]["story_objects"]
        self.assertEqual(objects["obj_Story_Player2"]["kind"], "player_slot_install")
        self.assertEqual(objects["obj_Story_Block"]["kind"], "shapeless_no_draw")
        self.assertEqual(objects["obj_Story_Level53_Rope"]["object_code"], 25)
        self.assertEqual([a["id"] for a in scenario["script_inserted_actors"]], ["guard023_1", "guard023_2"])
        self.assertTrue(scenario["resources"]["actor_shape_sets"].endswith("battle053/actor_shape_sets/manifest.json"))

    def test_post_battle_camp_and_throne_hall_scenes_match_tracked_output(self) -> None:
        expected = {
            55: ("leonard", [2, 56], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1"}, "battle055/level55.png"),
            56: ("leonard", [2, 49], {"SID_雷歐納德/1", "SID_琥/1", "SID_緹娜/1"}, "battle056/level56.png"),
            61: ("leonard", [3, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1"}, "battle061/level61.png"),
            62: ("leonard", [6, 63], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_漢克斯/1"}, "battle062/level62.png"),
            63: (None, [6, 49], {"SID_ENEMY058/1", "SID_ENEMY027/1", "SID_ENEMY027/2", "SID_ENEMY023/1"}, "battle063/level63.png"),
            64: ("leonard", [7, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1"}, "battle064/level64.png"),
        }
        for level, (player, next_level, bindings, map_suffix) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "story-scene-provisional", level)
            self.assertEqual(scenario["player_unit_id"], player, level)
            self.assertEqual(scenario["opening"]["next_level_event"], next_level, level)
            self.assertEqual(set(scenario["opening"]["actor_bindings"]), bindings, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(map_suffix), level)
            self.assertNotIn("end_card", scenario["opening"], level)
        # 緹娜 enters level 56 through obj_Story_Player2, 漢克斯 walks into 61 / 62 from off the west edge.
        self.assertEqual(story_scene.build(56)["opening"]["story_objects"]["obj_Story_Player2"]["kind"], "player_slot_install")
        self.assertEqual(story_scene.build(61)["opening"]["actor_bindings"]["SID_漢克斯/1"]["placement_xy"], [-64, 192])
        # Alias levels carry the seed's provisional map sentence; level 63 records the unhandled shape messages.
        self.assertTrue(any(item.startswith("map alias: level 61") for item in story_scene.build(61)["unresolved_semantics"]))
        self.assertTrue(any("actShapeMessage" in item for item in story_scene.build(63)["unresolved_semantics"]))

    # lane ch2c
    def test_chapter_two_previews_match_tracked_output_and_offer_skip_battle(self) -> None:
        # level: (players in EVEF order, skip_battle next level, world_actions count)
        expected = {
            36: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl"], [36, 49], 2),
            37: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl", "claudie"], [37, 49], 3),
            38: (["leonard", "tina", "hanks", "shera", "rett", "howl", "hu"], [80, 80], 2),
            39: (["leonard", "tina", "hanks", "hu", "howl", "shera", "rett"], [39, 49], 2),
            40: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl", "claudie"], [40, 49], 2),
            41: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl", "claudie"], [41, 73], 2),
            43: (["leonard", "tina", "hu", "hanks", "rett", "howl", "shera"], [43, 49], 2),
            44: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl"], [44, 49], 3),
            45: (["leonard", "tina", "hu", "hanks", "shera", "rett", "howl", "claudie"], [75, 75], 3),
        }
        for level, (players, next_level, writes) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "opening-preview-provisional", level)
            self.assertEqual(scenario["player_unit_id"], "leonard", level)
            self.assertEqual([a["id"] for a in scenario["story_actors"] if a["role"] == "player"], players, level)
            self.assertIsNone(scenario["opening"]["next_level_event"], level)
            self.assertEqual(scenario["opening"]["end_behavior"], "battle_not_remade_card", level)
            self.assertEqual(scenario["opening"]["end_exit"], {"kind": "world_map"}, level)
            self.assertIn(f"（level {level}）尚未重製", scenario["opening"]["end_card"]["hint"], level)
            skip = scenario["opening"]["skip_battle"]
            self.assertEqual(skip["next_level_event"], next_level, level)
            self.assertEqual(len(skip["world_actions"]), writes, level)
            # 咕嚕 (and 克羅蒂 where marked) are 「有才產生」 conditional installs and stay out.
            self.assertTrue(any(item.startswith("conditional installs left out") and "咕嚕" in item for item in scenario["unresolved_semantics"]), level)
            self.assertNotIn("gulu", [a["id"] for a in scenario["story_actors"]], level)
        # 傲 055 / 席德爾 056 are EVEF enemies bound by token; 39's winfail obj_Story_Block is shapeless.
        self.assertEqual(story_scene.build(36)["opening"]["actor_bindings"]["SID_ENEMY055/1"]["actor_id"], "055")
        self.assertEqual(story_scene.build(41)["opening"]["actor_bindings"]["SID_ENEMY056/1"]["placement_xy"], [672, -64])
        self.assertEqual(story_scene.build(39)["opening"]["story_objects"]["obj_Story_Block"]["kind"], "shapeless_no_draw")
        self.assertTrue(any("random-position" in item for item in story_scene.build(37)["unresolved_semantics"]))
        self.assertEqual(len(story_scene.build(44)["story_actors"]), 82)

    def test_level_74_inn_scene_returns_to_the_big_map(self) -> None:
        scenario = story_scene.build(74)
        tracked = json.loads((ROOT / "content/battles/story_074.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertEqual(scenario["status"], "story-scene-provisional")
        self.assertEqual(scenario["player_unit_id"], "leonard")
        self.assertEqual(scenario["opening"]["next_level_event"], [42, 49])
        self.assertEqual(len(scenario["story_actors"]), 8)
        self.assertNotIn("end_card", scenario["opening"])
        self.assertTrue(any(item.startswith("conditional installs left out") for item in scenario["unresolved_semantics"]))
        self.assertTrue(scenario["resources"]["map_texture"].endswith("battle074/level74.png"))
    # end lane ch2c

    # lane ch2b
    def test_chapter2_battle_previews_match_tracked_output(self) -> None:
        # level: (player_unit_id, skip_battle next_level_event, skip_battle world_action count, binding sample, map suffix)
        expected = {
            26: ("leonard", [26, 49], 6, {"SID_雷歐納德/1", "SID_克羅蒂/1", "SID_ENEMY039/4", "SID_ENEMY038/8"}, "battle026/level26.png"),
            28: ("leonard", [28, 49], 4, {"SID_雷歐納德/1", "SID_嚎/1", "obj_Story_Level_Enemy50/insert9"}, "battle028/level28.png"),
            29: ("leonard", [29, 70], 2, {"SID_雷歐納德/1", "SID_嚎/1", "SID_ENEMY024/2", "SID_ENEMY023/4", "SID_ENEMY044/3", "SID_ENEMY031/3", "SID_ENEMY030/4", "SID_ENEMY027/2"}, "battle029/level29.png"),
            30: ("leonard", None, 5, {"SID_雷歐納德/1", "SID_嚎/1", "SID_ENEMY053/1", "SID_ENEMY049/6"}, "battle030/level30.png"),
            31: ("leonard", [31, 71], 2, {"SID_雷歐納德/1", "SID_雷特/1", "SID_嚎/1", "SID_ENEMY055/1", "SID_ENEMY049/5"}, "battle031/level31.png"),
            32: ("leonard", None, 6, {"SID_雷歐納德/1", "SID_ENEMY023/10", "SID_ENEMY044/6", "SID_ENEMY027/3"}, "battle032/level32.png"),
            33: ("tina", None, 5, {"SID_緹娜/1", "SID_雪拉/1", "SID_ENEMY056/1", "SID_ENEMY049/3", "SID_ENEMY033/2", "SID_ENEMY034/3", "SID_ENEMY035/2"}, "battle033/level33.png"),
            34: ("tina", None, 14, {"SID_緹娜/1", "SID_琥/1", "SID_ENEMY062/3", "SID_ENEMY036/5", "SID_ENEMY037/5", "SID_ENEMY038/6"}, "battle034/level34.png"),
        }
        for level, (player, next_level, writes, bindings, map_suffix) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "opening-preview-provisional", level)
            self.assertEqual(scenario["player_unit_id"], player, level)
            self.assertEqual(scenario["opening"]["end_behavior"], "battle_not_remade_card", level)
            self.assertEqual(scenario["opening"]["end_exit"], {"kind": "world_map"}, level)
            self.assertEqual(scenario["opening"]["end_card"]["hint"], f"戰鬥部分（level {level}）尚未重製　　空格／點擊：回到大地圖（{scenario['opening']['end_card']['title']}）", level)
            skip = scenario["opening"]["skip_battle"]
            self.assertEqual(skip["next_level_event"], next_level, level)
            self.assertEqual(len(skip["world_actions"]), writes, level)
            self.assertEqual(skip["source"], f"winfail{level:03d} win section 1 of 1", level)
            self.assertTrue(bindings <= set(scenario["opening"]["actor_bindings"]), (level, bindings - set(scenario["opening"]["actor_bindings"])))
            self.assertTrue(scenario["resources"]["map_texture"].endswith(map_suffix), level)
            self.assertIsNone(scenario["opening"]["next_level_event"], level)
        # 咕嚕(有才產生) is a conditional install and stays out; the 26 船殼 pieces are registered actors like the original's.
        scene26 = story_scene.build(26)
        self.assertTrue(any("咕嚕(有才產生)" in item for item in scene26["unresolved_semantics"]))
        self.assertEqual(sum(key.startswith("SID_ENEMY101/") for key in scene26["opening"]["actor_bindings"]), 26)
        # Level 28's nine Enemy050 enter by actInsertObject after a white-light story object.
        scene28 = story_scene.build(28)
        self.assertEqual(len(scene28["script_inserted_actors"]), 9)
        self.assertEqual({actor["actor_id"] for actor in scene28["script_inserted_actors"]}, {"050"})
        self.assertIn("obj_Story_Level_WhiteLight", scene28["opening"]["story_objects"])
        # Level 30's Enemy053(克羅蒂) draws the 009 sprite its obs names; the PLAYERS code stays as source_actor_code.
        binding = story_scene.build(30)["opening"]["actor_bindings"]["SID_ENEMY053/1"]
        self.assertEqual((binding["actor_id"], binding["source_actor_code"]), ("009", "053"))
        # 咕嚕 speaks in STORY031 although his install is conditional: the speaker row stays.
        self.assertEqual(story_scene.build(31)["opening"]["speaker_resource_ids"]["SID_咕嚕"], "7")
        # Levels 32 / 33 play on each other's shape (obs 地圖管理員) and say so.
        for level, other in ((32, 33), (33, 32)):
            scene = story_scene.build(level)
            self.assertTrue(any(item.startswith(f"map alias: level {level}'s obs 地圖管理員 names level {other}'s shape") for item in scene["unresolved_semantics"]), level)
            self.assertEqual(scene["view"]["grid_projection"]["cell_size"], [32, 32])
        # No 雷歐納德 in 33 / 34: 緹娜 leads (34's EVEF lists 琥 first, the spec names her).
        self.assertNotIn("SID_雷歐納德/1", story_scene.build(34)["opening"]["actor_bindings"])

    def test_chapter2_story_scenes_match_tracked_output(self) -> None:
        expected = {
            70: ("leonard", [29, 49], {"SID_雷歐納德/1", "SID_緹娜/1"}, "battle070/level70.png"),
            71: (None, None, {"SID_ENEMY058/1", "SID_ENEMY053/1"}, "battle071/level71.png"),
            72: ("leonard", [35, 49], {"SID_雷歐納德/1", "SID_緹娜/1"}, "battle072/level72.png"),
        }
        for level, (player, next_level, bindings, map_suffix) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "story-scene-provisional", level)
            self.assertEqual(scenario["player_unit_id"], player, level)
            self.assertEqual(scenario["opening"]["next_level_event"], next_level, level)
            self.assertEqual(set(scenario["opening"]["actor_bindings"]), bindings, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(map_suffix), level)
            self.assertNotIn("skip_battle", scenario["opening"], level)
        # 70 / 71 play on the obs-named maps 55 / 58; 71 has no next-level token and ends on a card.
        self.assertTrue(any(item.startswith("map alias: level 70 has no level70.shp") and "地圖管理員" in item for item in story_scene.build(70)["unresolved_semantics"]))
        scene71 = story_scene.build(71)
        self.assertTrue(any(item.startswith("map alias: level 71 has no level71.shp") and "LEVEL58.SHP" in item for item in scene71["unresolved_semantics"]))
        self.assertEqual(scene71["opening"]["end_exit"], {"kind": "world_map"})
        self.assertEqual(scene71["opening"]["end_card"]["title"], "王座廳")
        self.assertEqual(scene71["opening"]["actor_bindings"]["SID_ENEMY053/1"]["source_actor_code"], "053")
        self.assertNotIn("end_card", story_scene.build(70)["opening"])
    # end lane ch2b

    def test_level_901_ambush_preview_plays_on_the_riverside_map_and_offers_the_win_writes(self) -> None:
        scenario = story_scene.build(901)
        tracked = json.loads((ROOT / "content/battles/story_901.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertEqual(scenario["status"], "opening-preview-provisional")
        self.assertEqual(scenario["player_unit_id"], "leonard")
        self.assertTrue(scenario["resources"]["map_texture"].endswith("battle901/level901.png"))
        self.assertTrue(scenario["resources"]["terrain"].endswith("level901_terrain.json"))
        opening = scenario["opening"]
        self.assertEqual(opening["end_event_id"], "first_control_ready")
        self.assertEqual(opening["preview_of_battle_level"], 901)
        self.assertEqual(opening["end_card"]["title"], "菲納斯河畔　伏擊")
        self.assertEqual(opening["end_exit"], {"kind": "world_map"})
        self.assertIsNone(opening["next_level_event"], "STORY901 sets no next level; winfail901 owns 8,gameBigMapLevel")
        # The win section returns to big-map point 8 and rewrites point 8 / 席達鎮 (static-derived).
        skip = opening["skip_battle"]
        self.assertEqual(skip["next_level_event"], [8, 49])
        self.assertEqual([(row["name"], row["args"]) for row in skip["world_actions"]], [
            ("actBMSetPointEvent", ["8", "516", "bmpmVisit"]),
            ("actBMSetPointEncounterRatio", ["8", "20"]),
            ("actDeleteTE", ["town_席達鎮", "20", "0"]),
            ("actDeleteTE", ["town_席達鎮", "17", "0"]),
            ("actAddTE", ["town_席達鎮", "45", "0"]),
            ("actAddTE", ["town_席達鎮", "20", "2", "26", "27"]),
            ("actSetTownExecEvent", ["town_席達鎮", "25"]),
        ])
        bindings = opening["actor_bindings"]
        self.assertEqual({key for key in bindings if not key.startswith("SID_ENEMY")},
                         {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1"})
        self.assertEqual(sum(1 for key in bindings if key.startswith("SID_ENEMY023/")), 14)
        self.assertEqual(sum(1 for key in bindings if key.startswith("SID_ENEMY024/")), 3)
        self.assertEqual(bindings["SID_雷歐納德/1"]["placement_xy"], [448, -32], "the party starts off the north edge")
        self.assertEqual(len(scenario["story_actors"]), 22)
        self.assertNotIn("script_inserted_actors", scenario, "the 031 / 027 / 030 arrivals belong to winfail901, not the opening")
        # A preview on an aliased map keeps the seed's alias sentence visible.
        self.assertTrue(any(item.startswith("map alias: level 901") for item in scenario["unresolved_semantics"]))
    # lane ch2a
    def test_ch2a_battle_opening_previews_match_tracked_output(self) -> None:
        expected = {
            # level: (player, skip next, world writes, story actors, inserted)
            13: ("leonard", [13, 49], 4, 7, 9),
            15: ("leonard", [15, 49], 2, 18, 0),
            17: ("leonard", [17, 67], 4, 24, 0),  # + actAddOverScore gameoverID1,3 / gameoverID3,1
            18: ("leonard", [18, 49], 10, 22, 1),
            19: ("rett", [19, 69], 6, 5, 0),
            21: ("leonard", [21, 49], 9, 20, 0),  # + actAddOverScore gameoverID2,2 (win 0)
            22: ("leonard", [22, 49], 2, 15, 0),
            24: ("leonard", [24, 49], 2, 38, 0),
        }
        for level, (player, next_level, writes, actors, inserted) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "opening-preview-provisional", level)
            self.assertEqual(scenario["player_unit_id"], player, level)
            self.assertEqual(scenario["opening"]["end_behavior"], "battle_not_remade_card", level)
            self.assertEqual(scenario["opening"]["end_exit"], {"kind": "world_map"}, level)
            self.assertIn(f"（level {level}）尚未重製", scenario["opening"]["end_card"]["hint"], level)
            self.assertIsNone(scenario["opening"]["next_level_event"], level)
            self.assertEqual(scenario["opening"]["skip_battle"]["next_level_event"], next_level, level)
            self.assertEqual(len(scenario["opening"]["skip_battle"]["world_actions"]), writes, level)
            self.assertEqual(len(scenario["story_actors"]), actors, level)
            self.assertEqual(len(scenario.get("script_inserted_actors", [])), inserted, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(f"battle{level:03d}/level{level}.png"), level)
        # Conditional installs stay out; level 13's nine inserts are bound by insert order; 19 has 雷特 alone.
        self.assertTrue(any("conditional installs left out" in item and "咕嚕" in item for item in story_scene.build(13)["unresolved_semantics"]))
        self.assertEqual(story_scene.build(13)["opening"]["actor_bindings"]["obj_Story_Level_Enemy50/insert3"]["unit_id"], "guard050_3")
        self.assertEqual(set(story_scene.build(19)["opening"]["actor_bindings"]), {"SID_雷特/1", "SID_ENEMY041/1", "SID_ENEMY041/2", "SID_ENEMY041/3", "SID_ENEMY041/4"})
        # Level 18's door 100 is a registered actor like the original's: the EVEF door actor100_1 keeps SID_ENEMY100/1
        # (STORY018 deletes it), the obj_Story_Level_Door re-insert is actor100_2; level 22 keeps the waterfall ambience.
        bindings18 = story_scene.build(18)["opening"]["actor_bindings"]
        self.assertEqual((bindings18["SID_ENEMY100/1"]["unit_id"], bindings18["obj_Story_Level_Door/insert1"]["unit_id"]), ("actor100_1", "actor100_2"))
        self.assertTrue(any("瀑布聲" in item for item in story_scene.build(22)["unresolved_semantics"]))

    def test_ch2a_camp_story_levels_match_tracked_output(self) -> None:
        expected = {
            66: ([9, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1"}),
            67: ([17, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1", "SID_嚎/1", "SID_ENEMY064/1"}),
            68: ([17, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1", "SID_嚎/1"}),
            69: ([19, 49], {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1", "SID_雷特/1", "SID_嚎/1"}),
        }
        for level, (next_level, bindings) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "story-scene-provisional", level)
            self.assertEqual(scenario["player_unit_id"], "leonard", level)
            self.assertEqual(scenario["opening"]["next_level_event"], next_level, level)
            self.assertEqual(set(scenario["opening"]["actor_bindings"]), bindings, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(f"battle{level:03d}/level{level}.png"), level)
            self.assertNotIn("end_card", scenario["opening"], level)
            alias = [item for item in scenario["unresolved_semantics"] if item.startswith(f"map alias: level {level}")]
            self.assertEqual(len(alias), 1, level)
            self.assertIn("地圖管理員", alias[0], level)
        self.assertTrue(any("actGetItem 281" in item for item in story_scene.build(67)["unresolved_semantics"]))
    # end lane ch2a

    # lane ch3
    def test_level_73_choice_scene_chains_both_branches_into_event_2(self) -> None:
        scenario = story_scene.build(73)
        tracked = json.loads((ROOT / "content/battles/story_073.json").read_text(encoding="utf-8"))
        self.assertEqual(scenario, tracked)
        self.assertEqual(scenario["status"], "opening-preview-provisional")
        self.assertEqual(scenario["player_unit_id"], "leonard")
        self.assertTrue(scenario["resources"]["map_texture"].endswith("battle073/level73.png"))
        self.assertTrue(scenario["resources"]["actor_shape_sets"].endswith("battle073/actor_shape_sets/manifest.json"))
        opening = scenario["opening"]
        self.assertEqual(opening["end_exit"], {"kind": "world_map"})
        self.assertNotIn("skip_battle", opening, "winfail073 has no win section and its only next-level event is a select-branch tail")
        self.assertIsNone(opening["next_level_event"])
        branches = opening["select_event_timelines"]
        self.assertEqual(set(branches), {"event_0", "event_1"})
        for key, branch in branches.items():
            self.assertEqual(branch["chained_event_codes"], [2], key)
            kinds = [event["kind"] for event in branch["events"]]
            self.assertEqual(kinds[-1], "next_level_event", key)
            self.assertEqual(branch["events"][-1]["args"], ["41", "gameBigMapLevel"], key)
            self.assertEqual(kinds.count("town_event_add"), 5, key)
            self.assertIn("event_2", branch["claim_limit"], key)
        self.assertIn("actor_shape_change", [event["kind"] for event in branches["event_0"]["events"]])
        self.assertEqual([event["kind"] for event in branches["event_1"]["events"]][0], "game_over_flag")
        self.assertEqual(set(opening["actor_bindings"]) - {"SID_ENEMY056/1"},
                         {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1", "SID_雷特/1", "SID_嚎/1", "SID_克羅蒂/1"})
        self.assertEqual(opening["story_objects"]["obj_Story_Level_RedLight"]["process"], "defProcScreenFlash")
        self.assertTrue(any(item.startswith("map alias: level 73 has no level73.shp") and "LEVEL41.SHP" in item for item in scenario["unresolved_semantics"]))
        self.assertTrue(any("gameoverflagFreeEnemy" in item for item in scenario["unresolved_semantics"]))
        # Level 900's branches end otherwise and stay byte-identical.
        self.assertNotIn("chained_event_codes", story_scene.build(900)["opening"]["select_event_timelines"]["event_0"])

    def test_finale_battle_previews_match_tracked_output_and_offer_skip_battle(self) -> None:
        # level: (skip_battle next level, skip source prefix, story actors, card title, map suffix, alias map)
        expected = {
            75: ([57, 57], "winfail075 win section 1 of 1", 28, "自覺與宿命", "battle075/level75.png", 57),
            76: ([81, 81], "winfail076 win section 1 of 1", 21, "最終的序曲", "battle076/level76.png", 58),
            77: ([82, 82], "winfail077 win section 1 of 1", 26, "破滅的命運", "battle077/level77.png", 58),
            78: ([79, 79], "winfail078 event (no win section", 24, "接觸", "battle078/level78.png", 58),
            79: ([90, 998], "winfail079 win section 1 of 1", 10, "終焉", "battle079/level79.png", 58),
            80: ([38, 49], "winfail080 win section 1 of 1", 31, "禁忌之魂", "battle080/level80.png", None),
            59: ([90, 998], "winfail059 win section 1 of 1", 8, "劫數", "battle059/level59.png", None),
        }
        for level, (next_level, source, actors, title, map_suffix, alias) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "opening-preview-provisional", level)
            self.assertEqual(scenario["player_unit_id"], "leonard", level)
            self.assertEqual(scenario["opening"]["end_behavior"], "battle_not_remade_card", level)
            self.assertEqual(scenario["opening"]["end_exit"], {"kind": "world_map"}, level)
            self.assertEqual(scenario["opening"]["end_card"]["title"], title, level)
            self.assertIn(f"（level {level}）尚未重製", scenario["opening"]["end_card"]["hint"], level)
            self.assertIsNone(scenario["opening"]["next_level_event"], level)
            skip = scenario["opening"]["skip_battle"]
            self.assertEqual(skip["next_level_event"], next_level, level)
            self.assertEqual(skip["world_actions"], [], level)
            self.assertTrue(skip["source"].startswith(source), (level, skip["source"]))
            self.assertEqual(len(scenario["story_actors"]), actors, level)
            if level == 59:
                self.assertEqual([actor["actor_id"] for actor in scenario["script_inserted_actors"]], ["060"], level)
            else:
                self.assertNotIn("script_inserted_actors", scenario, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(map_suffix), level)
            alias_notes = [item for item in scenario["unresolved_semantics"] if item.startswith(f"map alias: level {level}")]
            if alias is None:
                self.assertEqual(alias_notes, [], level)
            else:
                self.assertEqual(len(alias_notes), 1, level)
                self.assertIn(f"level {alias}'s map", alias_notes[0], level)
                self.assertIn("地圖管理員", alias_notes[0], level)
        # 78 has no win section: skip_battle stands on the round-10 event and says so.
        scene78 = story_scene.build(78)
        self.assertTrue(any("battle-time event section (no win section)" in item for item in scene78["unresolved_semantics"]))
        self.assertNotIn("SID_咕嚕/1", scene78["opening"]["actor_bindings"])
        self.assertNotIn("gulu", [actor["id"] for actor in scene78["story_actors"]])
        # 79 / 59 hand off to the game-clear level 998 and record what it is.
        for level in (79, 59):
            self.assertTrue(any("level998" in item and "game-clear" in item for item in story_scene.build(level)["unresolved_semantics"]), level)
        # 59 keeps the standing-only source shape for the opening presentation, then binds
        # its script insertion to the targetable PlayLoop actor.
        scene59 = story_scene.build(59)
        self.assertEqual(scene59["opening"]["story_objects"]["obj_Story_Level_Enemy60"]["shape_resource_id"], "60-10001.SHP")
        self.assertEqual(scene59["opening"]["actor_bindings"]["obj_Story_Level_Enemy60/insert1"]["unit_id"], "actor060_1")
        self.assertEqual(scene59["opening"]["actor_bindings"]["SID_ENEMY060/1"]["actor_id"], "060")
        self.assertEqual(scene59["opening"]["speaker_resource_ids"]["SID_ENEMY060"], "655")
        # 80's 怨念體 068 (EVEF record 45, standing-only 68-001 with a generated template) is a
        # cast actor since R6-L10; its four treasure boxes are recorded, 克羅蒂 / 咕嚕 stay out.
        scene80 = story_scene.build(80)
        self.assertEqual(scene80["opening"]["actor_bindings"]["SID_ENEMY068/1"], {"unit_id": "actor068_1", "actor_id": "068", "coord": [23, 11], "placement_xy": [736, 352]})
        self.assertTrue(any(item.startswith("the 4 寶藏") for item in scene80["unresolved_semantics"]))
        self.assertTrue(any("克羅蒂(有才產生), 咕嚕(有才產生)" in item for item in scene80["unresolved_semantics"]))
        # 77's dead elf king is a stand object (058-P) and 席德爾 056 is bound; 79 binds both 057 and 058.
        self.assertEqual(story_scene.build(77)["opening"]["actor_bindings"]["SID_ENEMY056/1"]["placement_xy"], [272, 304])
        self.assertEqual({key for key in story_scene.build(79)["opening"]["actor_bindings"] if key.startswith("SID_ENEMY")}, {"SID_ENEMY057/1", "SID_ENEMY058/1"})
        self.assertEqual(story_scene.build(75)["opening"]["actor_bindings"]["SID_ENEMY054/1"]["placement_xy"], [448, 128])

    def test_finale_story_scenes_match_tracked_output(self) -> None:
        # level: (next_level_event, end_card title, end_exit, enemy binding)
        expected = {
            57: (None, "自覺與宿命", {"kind": "world_map"}, "SID_ENEMY054/1"),
            81: ([59, 59], "王座廳", {"kind": "world_map"}, "SID_ENEMY058/1"),
            82: ([90, 998], "幻世錄　完", None, "SID_ENEMY059/1"),
        }
        for level, (next_level, title, end_exit, enemy) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "story-scene-provisional", level)
            self.assertEqual(scenario["player_unit_id"], "leonard", level)
            self.assertEqual(scenario["opening"]["next_level_event"], next_level, level)
            self.assertEqual(scenario["opening"]["end_card"]["title"], title, level)
            self.assertEqual(scenario["opening"].get("end_exit"), end_exit, level)
            self.assertNotIn("skip_battle", scenario["opening"], level)
            self.assertIn(enemy, scenario["opening"]["actor_bindings"], level)
            self.assertEqual(set(scenario["opening"]["actor_bindings"]) - {enemy},
                             {"SID_雷歐納德/1", "SID_緹娜/1", "SID_琥/1", "SID_漢克斯/1", "SID_雪拉/1", "SID_雷特/1", "SID_嚎/1", "SID_克羅蒂/1"}, level)
            self.assertTrue(any(item.startswith("conditional installs left out") and "咕嚕" in item for item in scenario["unresolved_semantics"]), level)
        # 57 ends on the over-score hand-off (EndingDispatchRules picks among opening.end_routes);
        # 81 / 82 record the storage window / game-clear tokens.
        scene57 = story_scene.build(57)
        self.assertTrue(any("actSetNextPlayLevelGetOverEvent 0 picks the finale" in item and "EndingDispatchRules" in item for item in scene57["unresolved_semantics"]))
        routes = scene57["opening"]["end_routes"]
        self.assertEqual([(route["next_level_event"], route["over_score_id"]) for route in routes], [([76, 76], 1), ([77, 77], 2), ([78, 78], 3)])
        self.assertEqual(scene57["opening"]["end_routes_evidence"]["evidence_tier"], "static-derived")
        self.assertTrue(scene57["resources"]["map_texture"].endswith("battle057/level57.png"))
        self.assertTrue(any("actEnterStorageWindow opens the hosted between-battle 整理裝備 screen" in item and "actKeepPlayerST (recorded as player_stamina_keep) keeps" in item for item in story_scene.build(81)["unresolved_semantics"]))
        scene82 = story_scene.build(82)
        self.assertTrue(any("obj_gameclearBOSS" in item for item in scene82["unresolved_semantics"]))
        self.assertTrue(any("confirm restarts the campaign" in item for item in scene82["unresolved_semantics"]))
        self.assertTrue(scene82["resources"]["map_texture"].endswith("battle082/level82.png"))
        for level in (81, 82):
            self.assertTrue(any(item.startswith(f"map alias: level {level} has no level{level}.shp") and "LEVEL58.SHP" in item for item in story_scene.build(level)["unresolved_semantics"]), level)
    # end lane ch3

    # lane alt902
    def test_side_route_replacement_previews_match_tracked_output_and_offer_the_win_writes(self) -> None:
        # level: (base map level, players in EVEF order, skip next, world writes, story actors, card title)
        expected = {
            903: (24, ["leonard", "tina", "hu", "hanks", "shera", "rett", "howl"], [24, 49],
                  [("actBMSetPointEvent", ["24", "531", "bmpmVisit"]), ("actBMSetPointEncounterRatio", ["24", "16"])],
                  38, "哈莫特沙漠　魔騎士團"),
            902: (17, ["leonard", "tina", "hu", "hanks", "shera"], [17, 68],
                  [("actAddOverScore", ["gameoverID2", "3"]), ("actBMSetPointEvent", ["19", "904", "0"]), ("actBMSetPointEvent", ["17", "519", "bmpmVisit"]), ("actBMSetPointEncounterRatio", ["17", "40"])],
                  19, "艾瓦台地　尋"),
            904: (19, ["rett"], [19, 69],
                  [("actDeleteTE", ["town_薛維斯港", "36", "0"]), ("actDeleteTE", ["town_薛維斯港", "41", "0"]),
                   ("actAddTE", ["town_薛維斯港", "36", "3", "127", "128", "129"]), ("actAddTE", ["town_薛維斯港", "41", "3", "133", "131", "132"]),
                   ("actBMSetPointEvent", ["19", "525", "bmpmVisit"]), ("actBMSetPointEncounterRatio", ["19", "100"])],
                  5, "利魯瑪山地　再訪"),
        }
        for level, (base, players, next_level, writes, actors, title) in expected.items():
            scenario = story_scene.build(level)
            tracked = json.loads((ROOT / f"content/battles/story_{level:03d}.json").read_text(encoding="utf-8"))
            self.assertEqual(scenario, tracked, level)
            self.assertEqual(scenario["status"], "opening-preview-provisional", level)
            self.assertEqual([a["id"] for a in scenario["story_actors"] if a["role"] == "player"], players, level)
            self.assertEqual(len(scenario["story_actors"]), actors, level)
            self.assertNotIn("script_inserted_actors", scenario, level)
            opening = scenario["opening"]
            self.assertEqual(opening["end_event_id"], "first_control_ready", level)
            self.assertEqual(opening["preview_of_battle_level"], level, level)
            self.assertEqual(opening["end_card"]["title"], title, level)
            self.assertIn(f"（level {level}）尚未重製", opening["end_card"]["hint"], level)
            self.assertEqual(opening["end_exit"], {"kind": "world_map"}, level)
            self.assertIsNone(opening["next_level_event"], level)
            skip = opening["skip_battle"]
            self.assertEqual(skip["source"], f"winfail{level:03d} win section 1 of 1", level)
            self.assertEqual(skip["next_level_event"], next_level, level)
            self.assertEqual([(row["name"], row["args"]) for row in skip["world_actions"]], writes, level)
            self.assertTrue(scenario["resources"]["map_texture"].endswith(f"battle{level:03d}/level{level}.png"), level)
            self.assertTrue(scenario["resources"]["terrain"].endswith(f"level{level:03d}_terrain.json"), level)
            # The base level's map through the obs 地圖管理員 binding.
            alias = [item for item in scenario["unresolved_semantics"] if item.startswith(f"map alias: level {level} has no level{level}.shp")]
            self.assertEqual(len(alias), 1, level)
            self.assertIn(f"level {base}'s map", alias[0], level)
            self.assertIn(f"Level{base:02d}.SHP".lower(), alias[0].lower(), level)
        # 903: the eight-slot party of level 24 (咕嚕 stays out), the same 31 EVEF enemies; the winfail arrivals belong to the battle.
        scene903 = story_scene.build(903)
        self.assertEqual(scene903["player_unit_id"], "leonard")
        self.assertTrue(any(item.startswith("conditional installs left out") and "咕嚕" in item for item in scene903["unresolved_semantics"]))
        self.assertEqual(sum(1 for key in scene903["opening"]["actor_bindings"] if key.startswith("SID_ENEMY")), 31)
        self.assertEqual(scene903["opening"]["actor_bindings"]["SID_雷歐納德/1"]["placement_xy"], [224, -32])
        self.assertEqual(scene903["opening"]["speaker_resource_ids"]["SID_ENEMY054"], "650")
        self.assertTrue(any("WORD024.SHP" in item for item in scene903["unresolved_semantics"]))
        # 902: the party starts off the east edge of the 1280px map, no 克里夫 / workers, two closed treasure boxes; the
        # win section's over-score / 嚎 join / pass grant are not part of skip_battle.
        scene902 = story_scene.build(902)
        self.assertEqual(scene902["opening"]["actor_bindings"]["SID_雷歐納德/1"]["placement_xy"], [1344, 672])
        self.assertFalse(any(key.startswith(("SID_ENEMY062/", "SID_ENEMY064/")) for key in scene902["opening"]["actor_bindings"]))
        self.assertEqual(sum(1 for key in scene902["opening"]["actor_bindings"] if key.startswith("SID_ENEMY")), 14)
        self.assertTrue(any(item.startswith("the 2 寶藏") for item in scene902["unresolved_semantics"]))
        self.assertTrue(any("actAddOverScore gameoverID2,3" in item for item in scene902["unresolved_semantics"]))
        self.assertFalse(any(item.startswith("conditional installs left out") for item in scene902["unresolved_semantics"]))
        # 904: 雷特 alone as in level 19 (same EVEF anchor), and the only script difference from 19
        # (薛維斯港 event 41 child 133) reaches skip_battle.
        scene904 = story_scene.build(904)
        self.assertEqual(scene904["player_unit_id"], "rett")
        self.assertEqual(scene904["opening"]["actor_bindings"]["SID_雷特/1"]["placement_xy"], story_scene.build(19)["opening"]["actor_bindings"]["SID_雷特/1"]["placement_xy"])
        self.assertNotEqual(scene904["opening"]["skip_battle"]["world_actions"], story_scene.build(19)["opening"]["skip_battle"]["world_actions"])
        self.assertTrue(any(item.startswith("the 3 寶藏") for item in scene904["unresolved_semantics"]))
        self.assertTrue(any("WORD019.SHP" in item for item in scene904["unresolved_semantics"]))
    # end lane alt902

    def test_unregistered_levels_are_rejected(self) -> None:
        with self.assertRaises(KeyError):
            story_scene.build(54)


if __name__ == "__main__":
    unittest.main()
