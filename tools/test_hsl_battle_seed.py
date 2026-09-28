import json
import unittest
from pathlib import Path

import struct

from hsltools.levels.seed import _actor_instance, _combined_objects, _fixed_point_cell, _integer, _placements, record_names


class BattleSeedTests(unittest.TestCase):
    def test_record_names_use_zero_padded_data_and_unpadded_map(self):
        names = record_names(52)
        self.assertEqual(names["story"], "@:\\data\\STORY052.TXT")
        self.assertEqual(names["terrain"], "@:\\data\\level052.wrd")
        # Chapter map folders shape01/11/21/31/41 (the PAK holds level12/13/15 under shape11).
        self.assertEqual(names["map"], [f"@:\\{folder}\\level52.shp" for folder in ("shape01", "shape11", "shape21", "shape31", "shape41")])

    def test_map_member_uses_two_digit_level_and_level_header_is_optional(self):
        from hsltools.levels.seed import OPTIONAL_RECORDS
        names = record_names(1)
        self.assertEqual(names["map"][0], "@:\\shape01\\level01.shp")
        self.assertEqual(len(names["map"]), 5)
        self.assertEqual(names["level_header"], "@:\\data\\level001.h")
        self.assertIn("level_header", OPTIONAL_RECORDS)

    def test_combined_object_table_joins_children_and_flagged_placements(self):
        # Two fixed EVEF records followed by a one-slot combined table: [offset][count][(code,x,y)...]
        header = b"EVEF" + struct.pack("<I", 2) + b"\0" * 8
        records = b"\0" * 0xD0 * 2
        tail = struct.pack("<I", 4) + struct.pack("<I", 2) + struct.pack("<3I", 18, 189, 232) + struct.pack("<3I", 22, 307, 375)
        objects = {
            "objects": [
                {"obj_code": "18", "obj_name": "樹01", "obj_process_code": "defProcStandObject", "obj_shape_name": "SHAPE01\\TREE01.SHP", "obj_data_fields": {}},
                {"obj_code": "22", "obj_name": "樹影02", "obj_process_code": "defProcStandObject", "obj_shape_name": "SHAPE01\\SHADOW02.SHP", "obj_data_fields": {"obj_Data9": "mapobjShadow"}},
            ]
        }
        combined = _combined_objects(header + records + tail, {"record_count": 2}, objects, {"define_values": {"cmb樹和影01": "0"}})
        self.assertEqual(len(combined), 1)
        self.assertEqual(combined[0]["symbol"], "cmb樹和影01")
        self.assertEqual([child["object_name"] for child in combined[0]["children"]], ["樹01", "樹影02"])
        self.assertEqual(combined[0]["children"][1]["offset_xy_candidate"], [307, 375])
        evef = {"record_summaries": [
            {"index": 5, "field_0x04_code_candidate": 0x80000000, "placement_x_candidate_0x08": 512, "placement_y_candidate_0x0c": 160},
            {"index": 6, "field_0x04_code_candidate": 0x80000007, "placement_x_candidate_0x08": 0, "placement_y_candidate_0x0c": 0},
        ]}
        rows = _placements(evef, objects, combined)
        self.assertEqual(rows[0]["role_from_process"], "combined_map_object")
        self.assertEqual(rows[0]["join_status"], "joined")
        self.assertEqual(rows[0]["combined_object_index"], 0)
        self.assertEqual(rows[0]["object_name"], "cmb樹和影01")
        self.assertEqual(rows[1]["join_status"], "unmatched")
        self.assertEqual(_combined_objects(header + records, {"record_count": 2}, objects, None), [])

    def test_combined_children_are_placed_relative_to_the_first_child(self):
        # Installer 0x46bd67: delta = EVEF xy - child0 table xy, every child drawn at its table xy + delta.
        from hsltools.levels.map_objects import build_combined_placements
        child = lambda index, code, xy, shape: {"child_index": index, "object_code": code, "offset_xy_candidate": xy, "join_status": "joined",
                                               "role_from_process": "map_object", "shape_resource": shape, "object_name": shape, "object_process": "defProcStandObject"}
        seed = {"combined_objects": {"entries": [{"index": 0, "children": [child(0, 18, [189, 232], "SHAPE01\\TREE01.SHP"), child(1, 22, [307, 375], "SHAPE01\\SHADOW02.SHP")]}]},
                "placements": {"records": [{"record_index": 5, "role_from_process": "combined_map_object", "combined_object_index": 0,
                                             "placement_xy_candidate": [512, 160], "object_name": "cmb樹和影01"}]}}
        children = build_combined_placements(seed)[0]["children"]
        self.assertEqual([(c["candidate_x"], c["candidate_y"]) for c in children], [(512, 160), (630, 303)])

    def test_tracked_level1_seed_joins_every_placement(self):
        seed = json.loads(Path("content/generated/hsl/chapter01/battle001_seed.json").read_text())
        self.assertEqual(seed["level_kind"], "battle")
        self.assertEqual(seed["map"]["source_size"], [1280, 1120])
        self.assertEqual(seed["terrain"]["grid_size"], [40, 35])
        self.assertEqual(seed["placements"]["non_zero_record_count"], 79)
        self.assertEqual(len(seed["placements"]["records"]), 79)
        self.assertEqual(seed["placements"]["role_counts_from_object_process"]["combined_map_object"], 26)
        self.assertEqual(seed["placements"]["role_counts_from_object_process"]["enemy_object"], 16)
        self.assertEqual([entry["symbol"] for entry in seed["combined_objects"]["entries"]],
                         ["cmb樹和影01", "cmb樹和影02", "cmb樹和影03", "cmb房和影01", "cmb房和影02", "cmb房和影03"])
        self.assertTrue(all(row["join_status"] == "joined" for row in seed["placements"]["records"]))

    def test_map_aliases_name_map_level_and_evidence(self):
        from hsltools.levels.seed import MAP_ALIASES, map_alias
        # Level 60 keeps its original sentence byte-for-byte (its tracked seed predates the table).
        self.assertEqual(MAP_ALIASES[60]["map_level"], 58)
        self.assertEqual(MAP_ALIASES[60]["evidence"],
                         "level060.wrd is byte-identical to level058.wrd and the PAK has no level60.shp; the engine level->map table is not located (provisional)")
        # Throne hall 63 -> 58; post-battle camps 61 / 62 / 64 -> dusk camp 55 (56 is the morning camp).
        self.assertEqual(MAP_ALIASES[63]["map_level"], 58)
        for level in (61, 62, 64):
            self.assertEqual(MAP_ALIASES[level]["map_level"], 55)
            self.assertIn("level 56", MAP_ALIASES[level]["evidence"])
        self.assertIsNone(map_alias(55))
        self.assertEqual(record_names(61)["map"][0], "@:\\shape01\\level55.shp")
        self.assertEqual(record_names(63)["map"][-1], "@:\\shape41\\level58.shp")
        self.assertEqual(record_names(55)["terrain"], "@:\\data\\level055.wrd")

    def test_tracked_camp_seeds_share_terrain_and_record_alias(self):
        camp = json.loads(Path("content/generated/hsl/chapter01/battle055_seed.json").read_text())
        self.assertEqual(camp["level_kind"], "story")
        self.assertIsNone(camp["map"]["alias_of_level"])
        self.assertEqual(camp["map"]["source_size"], [640, 480])
        for level in (61, 62, 64):
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertEqual(seed["map"]["alias_of_level"], 55)
            self.assertEqual(seed["sources"]["terrain"]["sha256"], camp["sources"]["terrain"]["sha256"])
            self.assertEqual(seed["sources"]["map"]["sha256"], camp["sources"]["map"]["sha256"])
        hall = json.loads(Path("content/generated/hsl/chapter01/battle063_seed.json").read_text())
        court = json.loads(Path("content/generated/hsl/chapter01/battle058_seed.json").read_text())
        self.assertEqual(hall["map"]["alias_of_level"], 58)
        self.assertEqual(hall["sources"]["terrain"]["sha256"], court["sources"]["terrain"]["sha256"])

    def test_level_901_aliases_the_riverside_map_through_the_obs_map_manager(self):
        from hsltools.levels.seed import MAP_ALIASES, _map_manager_shape
        # 菲納斯河畔伏擊 (winfail010 arms point 8 with 8,901,bmpmGeneral) plays on the level 8 map.
        self.assertEqual(MAP_ALIASES[901]["map_level"], 8)
        self.assertIn("地圖管理員", MAP_ALIASES[901]["evidence"])
        self.assertIn("LEVEL08.SHP", MAP_ALIASES[901]["evidence"])
        self.assertEqual(record_names(901)["map"][0], "@:\\shape01\\level08.shp")
        self.assertEqual(record_names(901)["terrain"], "@:\\data\\level901.wrd")
        self.assertEqual(record_names(901)["object_header"], "@:\\data\\obj-901.h")
        # The obs 地圖管理員 (defProcIconBG) record names the map shape; other processes are ignored.
        objects = {"objects": [
            {"obj_code": "1", "obj_name": "管理員", "obj_process_code": "defProcBattleBOSS", "obj_shape_name": "SHAPE\\I_RECT01.SHP"},
            {"obj_code": "0", "obj_name": "地圖管理員", "obj_process_code": "defProcIconBG", "obj_shape_name": "SHAPE01\\LEVEL08.SHP"},
        ]}
        self.assertEqual(_map_manager_shape(objects), "SHAPE01\\LEVEL08.SHP")
        self.assertIsNone(_map_manager_shape({"objects": objects["objects"][:1]}))
        seed = json.loads(Path("content/generated/hsl/chapter01/battle901_seed.json").read_text())
        riverside = json.loads(Path("content/generated/hsl/chapter01/battle008_seed.json").read_text())
        self.assertEqual(seed["level_kind"], "battle")
        self.assertEqual(seed["map"]["alias_of_level"], 8)
        self.assertEqual(seed["map"]["source_size"], [1504, 800])
        self.assertEqual(seed["terrain"]["grid_size"], [47, 25])
        self.assertEqual(seed["sources"]["terrain"]["sha256"], riverside["sources"]["terrain"]["sha256"])
        self.assertEqual(seed["sources"]["map"]["sha256"], riverside["sources"]["map"]["sha256"])
        self.assertEqual(seed["sources"]["object_header"]["member"], "@:\\data\\OBJ-901.H")
        self.assertEqual(seed["placements"]["role_counts_from_object_process"],
                         {"battle_manager": 2, "enemy_object": 17, "map_object": 9, "other": 2, "player_install": 5})
        self.assertEqual([row["symbol"] for row in seed["script_objects"]],
                         ["obj_Story_Enemy27", "obj_Story_Enemy30", "obj_Story_Enemy31", "obj_Story_Enemy23", "obj_Story_Enemy24"])
        self.assertEqual(seed["scripts"]["winfail"]["section_counts"], {"win": 1, "fail": 1, "event": 6})

    # lane ch2a
    def test_ch2a_camp_aliases_name_the_map_manager_record(self):
        from hsltools.levels.seed import MAP_ALIASES, map_alias
        camp = json.loads(Path("content/generated/hsl/chapter01/battle055_seed.json").read_text())
        for level in (66, 67, 68, 69):
            self.assertEqual(MAP_ALIASES[level]["map_level"], 55)
            self.assertIn("地圖管理員", MAP_ALIASES[level]["evidence"])
            self.assertEqual(record_names(level)["map"][-1], "@:\\shape41\\level55.shp")
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertEqual(seed["level_kind"], "story")
            self.assertEqual(seed["map"]["alias_of_level"], 55)
            self.assertEqual(seed["map"]["source_size"], [640, 480])
            self.assertEqual(seed["sources"]["map"]["sha256"], camp["sources"]["map"]["sha256"])
            # The camp levels share a 20x15 grid that differs from level055.wrd in one cell, so the terrain sha differs.
            self.assertEqual(seed["terrain"]["grid_size"], [20, 15])
            self.assertNotEqual(seed["sources"]["terrain"]["sha256"], camp["sources"]["terrain"]["sha256"])
        for level in (13, 15, 17, 18, 19, 21, 22, 24):
            self.assertIsNone(map_alias(level))
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertEqual(seed["level_kind"], "battle")
            self.assertIsNone(seed["map"]["alias_of_level"])
            self.assertTrue(seed["sources"]["map"]["member"].lower().startswith("@:\\shape11\\" if level < 20 else "@:\\shape21\\"), level)
        # Level 22 carries the cmb瀑布 combined-object table; level 18's door is an enemy-process placement.
        self.assertEqual([entry["symbol"] for entry in json.loads(Path("content/generated/hsl/chapter01/battle022_seed.json").read_text())["combined_objects"]["entries"]], ["cmb瀑布"])
        door = [row for row in json.loads(Path("content/generated/hsl/chapter01/battle018_seed.json").read_text())["placements"]["records"] if row["object_name"] == "門1"]
        self.assertEqual([row["role_from_process"] for row in door], ["enemy_object"])
    # end lane ch2a

    def test_story_only_levels_mark_winfail_optional(self):
        from hsltools.levels.seed import OPTIONAL_RECORDS
        self.assertIn("winfail", OPTIONAL_RECORDS)
        self.assertNotIn("story", OPTIONAL_RECORDS)

    def test_integer_accepts_source_numeric_fields_only(self):
        self.assertEqual(_integer("97"), 97)
        self.assertEqual(_integer("0x61"), 97)
        self.assertIsNone(_integer("SID_ENEMY025"))
        self.assertIsNone(_integer(None))

    def test_placement_join_uses_process_without_inventing_faction(self):
        evef = {
            "record_summaries": [
                {"index": 5, "field_0x04_code_candidate": 97, "placement_x_candidate_0x08": 320, "placement_y_candidate_0x0c": 320},
                {"index": 29, "field_0x04_code_candidate": 6, "placement_x_candidate_0x08": 320, "placement_y_candidate_0x0c": 1344},
            ]
        }
        objects = {
            "objects": [
                {"obj_code": "97", "obj_name": "Enemy025", "obj_process_code": "defProcEnemy", "obj_shape_name": "SHAPE\\025-00001.SHP", "obj_data_fields": {}},
                {"obj_code": "6", "obj_name": "Leonard", "obj_process_code": "defProcPlayerInstall", "obj_shape_name": "SHAPE\\001-00001.SHP", "obj_data_fields": {"obj_Data9": "0"}},
            ]
        }
        rows = _placements(evef, objects)
        self.assertEqual(rows[0]["role_from_process"], "enemy_object")
        self.assertNotIn("team", rows[0])
        self.assertEqual(rows[1]["role_from_process"], "player_install")
        self.assertEqual(rows[1]["placement_xy_candidate"], [320, 1344])

    def test_tracked_level52_seed_preserves_bounded_source_facts(self):
        seed = json.loads(Path("content/generated/hsl/chapter01/battle052_seed.json").read_text())
        self.assertEqual(seed["level"], 52)
        self.assertEqual(seed["map"]["source_size"], [640, 1280])
        self.assertEqual(seed["terrain"]["grid_size"], [20, 40])
        self.assertEqual(seed["terrain"]["cell_size_from_map_division_candidate"], [32, 32])
        self.assertEqual(seed["placements"]["evef_record_count"], 36)
        self.assertEqual(seed["placements"]["non_zero_record_count"], 35)
        self.assertEqual(
            seed["placements"]["role_counts_from_object_process"],
            {"battle_manager": 2, "enemy_object": 9, "map_object": 23, "player_install": 1},
        )
        placed = {
            (row["record_index"], row["object_code"]): row["placement_xy_candidate"]
            for row in seed["placements"]["records"]
        }
        self.assertEqual(placed[(5, 97)], [320, 320])
        self.assertEqual(placed[(29, 6)], [320, 1344])
        self.assertEqual(placed[(30, 95)], [384, 1408])
        self.assertEqual(placed[(32, 96)], [192, 1472])
        story_counts = seed["scripts"]["story"]["action_counts"]
        self.assertEqual(story_counts["actInsertObject"], 8)
        self.assertEqual(story_counts["actWalkDispWait"], 9)
        self.assertEqual(story_counts["actInsertWinStatus"], 1)
        self.assertEqual(seed["scripts"]["winfail"]["section_counts"], {"win": 1, "fail": 1, "event": 2})

    # lane ch2b
    def test_chapter2_map_aliases_follow_the_obs_map_manager_record(self):
        from hsltools.levels.seed import MAP_ALIASES
        # Levels 32 / 33 have shapes of their own but their obs 地圖管理員 names the other level's
        # shape and only that shape matches the WRD grid; 70 / 71 have no shape and name 55 / 58.
        self.assertEqual(MAP_ALIASES[32]["map_level"], 33)
        self.assertEqual(MAP_ALIASES[33]["map_level"], 32)
        self.assertEqual(MAP_ALIASES[70]["map_level"], 55)
        self.assertEqual(MAP_ALIASES[71]["map_level"], 58)
        for level in (32, 33, 70, 71):
            self.assertIn("地圖管理員", MAP_ALIASES[level]["evidence"])
        self.assertEqual(record_names(32)["map"][3], "@:\\shape31\\level33.shp")
        self.assertEqual(record_names(33)["map"][3], "@:\\shape31\\level32.shp")
        self.assertEqual(record_names(70)["map"][4], "@:\\shape41\\level55.shp")
        self.assertEqual(record_names(32)["terrain"], "@:\\data\\level032.wrd")

    def test_tracked_chapter2_seeds_match_their_alias_maps(self):
        seeds = {level: json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text()) for level in (26, 32, 33, 70, 71, 72)}
        self.assertEqual(seeds[26]["level_kind"], "battle")
        self.assertIsNone(seeds[26]["map"]["alias_of_level"])
        self.assertEqual(seeds[26]["map"]["source_size"], [1600, 992])
        self.assertEqual(seeds[32]["map"]["alias_of_level"], 33)
        self.assertEqual(seeds[32]["map"]["source_size"], [704, 1184])
        self.assertEqual(seeds[32]["terrain"]["grid_size"], [22, 37])
        self.assertEqual(seeds[33]["map"]["alias_of_level"], 32)
        self.assertEqual(seeds[33]["map"]["source_size"], [960, 960])
        self.assertEqual(seeds[33]["terrain"]["grid_size"], [30, 30])
        camp = json.loads(Path("content/generated/hsl/chapter01/battle055_seed.json").read_text())
        hall = json.loads(Path("content/generated/hsl/chapter01/battle058_seed.json").read_text())
        self.assertEqual(seeds[70]["level_kind"], "story")
        self.assertEqual(seeds[70]["map"]["alias_of_level"], 55)
        self.assertEqual(seeds[70]["sources"]["map"]["sha256"], camp["sources"]["map"]["sha256"])
        self.assertNotEqual(seeds[70]["sources"]["terrain"]["sha256"], camp["sources"]["terrain"]["sha256"])
        self.assertEqual(seeds[71]["map"]["alias_of_level"], 58)
        self.assertEqual(seeds[71]["sources"]["terrain"]["sha256"], hall["sources"]["terrain"]["sha256"])
        self.assertIsNone(seeds[72]["map"]["alias_of_level"])
        self.assertEqual(seeds[72]["map"]["source_size"], [640, 480])
    # end lane ch2b


    # lane ch2c
    def test_chapter_two_seeds_use_their_own_maps_and_random_inserts_join(self):
        from hsltools.levels.seed import INSERT_ACTIONS, map_alias
        self.assertTrue({"actinsertobjectrandompos", "actinsertstoryobjectrandompos", "actinsertstoryobjectxrange"} <= INSERT_ACTIONS)
        for level in (36, 37, 38, 39, 40, 41, 43, 44, 45, 74):
            self.assertIsNone(map_alias(level))
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertIsNone(seed["map"]["alias_of_level"], level)
            self.assertTrue(seed["sources"]["map"]["member"].lower().endswith(f"\\level{level}.shp"), level)
            self.assertEqual(seed["terrain"]["cell_size_from_map_division_candidate"], [32, 32], level)
            self.assertEqual(seed["level_kind"], "story" if level == 74 else "battle", level)
        temple = json.loads(Path("content/generated/hsl/chapter01/battle037_seed.json").read_text())
        self.assertEqual(temple["scripts"]["story"]["action_counts"]["actInsertObjectRandomPos"], 10)
        self.assertEqual(temple["placements"]["role_counts_from_object_process"]["combined_map_object"], 5)
        hill = json.loads(Path("content/generated/hsl/chapter01/battle039_seed.json").read_text())
        block = next(row for row in hill["script_objects"] if row["symbol"] == "obj_Story_Block")
        self.assertEqual(block["definition_source"], "OBJ-ALL.H/global.obs")
    # end lane ch2c

    # lane ch3
    def test_finale_map_aliases_follow_the_obs_map_manager_record(self):
        from hsltools.levels.seed import MAP_ALIASES
        expected = {73: 41, 75: 57, 76: 58, 77: 58, 78: 58, 79: 58, 81: 58, 82: 58}
        for level, map_level in expected.items():
            self.assertEqual(MAP_ALIASES[level]["map_level"], map_level, level)
            self.assertIn("地圖管理員", MAP_ALIASES[level]["evidence"], level)
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertEqual(seed["map"]["alias_of_level"], map_level, level)
            self.assertTrue(seed["sources"]["map"]["member"].lower().endswith(f"\\level{map_level}.shp"), level)
        self.assertEqual(record_names(73)["map"][4], "@:\\shape41\\level41.shp")
        self.assertEqual(record_names(73)["terrain"], "@:\\data\\level073.wrd")
        # 73 shares level 41's terrain byte for byte; the six hall levels share one variant of the 58 table.
        lake = json.loads(Path("content/generated/hsl/chapter01/battle041_seed.json").read_text())
        hall = json.loads(Path("content/generated/hsl/chapter01/battle058_seed.json").read_text())
        seeds = {level: json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text()) for level in expected}
        self.assertEqual(seeds[73]["sources"]["terrain"]["sha256"], lake["sources"]["terrain"]["sha256"])
        self.assertEqual(seeds[73]["sources"]["map"]["sha256"], lake["sources"]["map"]["sha256"])
        hall_terrain = {seeds[level]["sources"]["terrain"]["sha256"] for level in (76, 77, 78, 79, 81, 82)}
        self.assertEqual(len(hall_terrain), 1)
        self.assertNotEqual(hall_terrain, {hall["sources"]["terrain"]["sha256"]})
        for level in (76, 77, 78, 79, 81, 82):
            self.assertEqual(seeds[level]["sources"]["map"]["sha256"], hall["sources"]["map"]["sha256"], level)
            self.assertEqual(seeds[level]["terrain"]["grid_size"], [30, 22], level)
        self.assertEqual(seeds[75]["terrain"]["grid_size"], [30, 22])
        self.assertEqual(seeds[75]["map"]["source_size"], [960, 704])
        self.assertEqual({seeds[level]["level_kind"] for level in (73, 75, 76, 77, 78, 79)}, {"battle"})
        self.assertEqual({seeds[level]["level_kind"] for level in (81, 82)}, {"story"})
        # 57 / 59 / 80 keep their own shapes; 73 has winfail sections but no win / fail.
        for level, size in ((57, [960, 704]), (59, [1632, 1280]), (80, [1280, 960])):
            seed = json.loads(Path(f"content/generated/hsl/chapter01/battle{level:03d}_seed.json").read_text())
            self.assertIsNone(seed["map"]["alias_of_level"], level)
            self.assertEqual(seed["map"]["source_size"], size, level)
            self.assertTrue(seed["sources"]["map"]["member"].lower().endswith(f"\\level{level}.shp"), level)
        self.assertEqual(seeds[73]["scripts"]["winfail"]["section_counts"], {"event": 3})
        self.assertEqual(seeds[78]["scripts"]["winfail"]["section_counts"], {"fail": 1, "event": 3})
    # end lane ch3


if __name__ == "__main__":
    unittest.main()

    def test_actor_instance_words_decode_items_and_ai_overrides(self):
        # level 17 record 8 (克里夫 064): two 回復藥 and the index-15 fixed point 0x04A00240.
        row = {"non_zero_u32": [{"field_offset": 4, "value": 94}, {"field_offset": 8, "value": 960}, {"field_offset": 12, "value": 448},
                                {"field_offset": 16, "value": 241}, {"field_offset": 20, "value": 241}, {"field_offset": 140, "value": 77595200}]}
        self.assertEqual(_actor_instance(row), {"items": [241, 241], "overrides": {"fixed_point": [37, 18]}})
        self.assertEqual(_fixed_point_cell(0x04A00240), [37, 18])
        # level 34 record 8 (0x00A00260): high word x, low word y, both cell-centred by the callback.
        self.assertEqual(_fixed_point_cell(10486368), [5, 19])
        # level 52 emperor: index 3 find_range, index 14 wait_round; index 16/17 are 16-bit words.
        row = {"non_zero_u32": [{"field_offset": 0x50 + 4 * 3, "value": 10}, {"field_offset": 0x50 + 4 * 14, "value": 8},
                                {"field_offset": 0x50 + 4 * 16, "value": 20}, {"field_offset": 0x50 + 4 * 17, "value": 65536}]}
        self.assertEqual(_actor_instance(row), {"overrides": {"find_range": 10, "wait_round": 8, "level_adjust_range": 20, "level_adjust_disp_range": 0}})
        self.assertEqual(_actor_instance({"non_zero_u32": [{"field_offset": 4, "value": 97}]}), {})
        self.assertEqual(_actor_instance({"non_zero_u32": [{"field_offset": 0x50 + 4 * 30, "value": 7}]}), {"unknown_override_words": {"30": 7}})

    def test_tracked_level17_seed_carries_the_escort_instance_words(self):
        seed = json.loads(Path("content/generated/hsl/chapter01/battle017_seed.json").read_text(encoding="utf-8"))
        by_index = {row["record_index"]: row for row in seed["placements"]["records"]}
        self.assertEqual(by_index[8]["actor_instance"], {"items": [241, 241], "overrides": {"fixed_point": [37, 18]}})
        self.assertEqual(by_index[6]["actor_instance"], {"items": [241]})
        self.assertNotIn("actor_instance", by_index[5])
        self.assertEqual(by_index[15]["actor_instance"], {"overrides": {"wait_round": 3}})
        self.assertNotIn("actor_instance", by_index[29])  # treasure boxes keep treasure_words only
