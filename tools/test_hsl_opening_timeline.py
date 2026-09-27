import json
import tempfile
import unittest
from pathlib import Path

from hsltools.levels.timeline import check_opening_timeline
from hsltools.levels.timeline import SCHEMA, compile_opening_timeline


class OpeningTimelineTests(unittest.TestCase):
    def test_compiles_story_action_chain_without_claiming_text_or_timing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            story_path = root / "story051.json"
            story_path.write_text(
                json.dumps(
                    {
                        "schema": "hsl_chapter01_script_ir.v1",
                        "source_file": "STORY051.TXT",
                        "action_chain": [
                            _action(0, "actPlayLevelMusic", []),
                            _action(1, "actDelay", ["40"]),
                            _action(2, "actWalkDispWait", ["SID_PLAYER0", "1", "0", "-96", "2"]),
                            _action(3, "actMessage", ["SID_PLAYER0", "1", "363"]),
                            _action(4, "actMessage", ["SID_ENEMY023", "1", "364"]),
                            _action(5, "actMessage", ["SID_ENEMY024", "1", "365"]),
                            _action(6, "actMessage", ["SID_ENEMY023", "2", "366"]),
                            _action(7, "actMessage", ["SID_PLAYER0", "1", "367"]),
                            _action(8, "actMessage", ["SID_ENEMY024", "2", "364"]),
                            _action(9, "actMessage", ["SID_ENEMY021", "2", "1101"]),
                            _action(10, "actSetDeadMessage", ["SID_PLAYER0", "1", "304", "0"]),
                            _action(11, "actShowSectionName", ["SHAPE01\\WORD051.SHP"]),
                            _action(12, "actInsertFailStatus", ["0"]),
                            _action(13, "actInsertEventStatus", ["0"]),
                            _action(14, "actInsertEventStatus", ["1"]),
                            _action(15, "actInsertEventStatus", ["2"]),
                            _action(16, "actInsertEventStatus", ["3"]),
                            _action(17, "actShowWinFailStatus", []),
                        ],
                    }
                ),
                encoding="utf-8",
            )

            timeline = compile_opening_timeline(story_path)
            self.assertEqual(timeline["schema"], SCHEMA)
            self.assertEqual(timeline["events"][0]["kind"], "opening_music")
            self.assertEqual(timeline["events"][-1]["kind"], "first_control_marker")
            self.assertIn("original message box layout", timeline["contract"]["not_proven"])
            self.assertIn("camera curve", timeline["contract"]["not_proven"])
            message_events = [event for event in timeline["events"] if event["kind"] == "dialogue_message_id"]
            self.assertEqual({event["message_id"] for event in message_events}, {"363", "364", "365", "366", "367", "1101"})

            timeline_path = root / "opening_timeline.json"
            timeline_path.write_text(json.dumps(timeline), encoding="utf-8")
            checked = check_opening_timeline(timeline_path)
            self.assertEqual(checked["event_count"], len(timeline["events"]))


class BattleSeedTimelineTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]
    SEED = ROOT / "content/generated/hsl/chapter01/battle052_seed.json"
    EVIDENCE = ROOT / "content/imported/hsl/chapter01/battle052/message_text_evidence.json"

    def test_compiles_level52_seed_with_resource_text_and_explicit_new_tokens(self):
        timeline = compile_opening_timeline(self.SEED, self.EVIDENCE)
        self.assertEqual(timeline["source_script"], "story052")
        self.assertEqual(timeline["source_file"], "STORY052.TXT")
        events = timeline["events"]
        # 57 preserved STORY052 chain tokens plus one synthetic handoff marker.
        self.assertEqual(len(events), 58)
        self.assertEqual(events[0]["kind"], "background_object_target")
        self.assertEqual(events[1]["kind"], "opening_music")
        self.assertEqual(events[-1]["kind"], "first_control_marker")
        self.assertTrue(events[-1]["synthetic"])
        self.assertNotIn("script_action", {event["kind"] for event in events})
        chained = [event for event in events if event["source_action_index"] == 7]
        self.assertEqual([event["script_action_name"] for event in chained], ["actDelay", "actMessage"])
        self.assertEqual([event["source_chain_index"] for event in chained], [0, 1])
        dialogue = [event for event in events if event["kind"] == "dialogue_message_id"]
        self.assertEqual([event["message_id"] for event in dialogue],
                         ["379", "380", "381", "383", "384", "385", "386", "387", "388", "389", "390", "391"])
        self.assertEqual(dialogue[0]["speaker_name"], "帝國法師")
        self.assertEqual(dialogue[1]["message_text"], "........................")
        self.assertEqual(dialogue[0]["presentation_status"], "message_text_resolved_layout_unresolved")
        inserts = [event for event in events if event["kind"] == "object_insert"]
        self.assertEqual(len(inserts), 8)
        self.assertEqual(inserts[0]["args"], ["obj_Story_Level52_Enemy21", "-54", "583"])
        walks = [event for event in events if event["kind"] == "inserted_object_walk_disp_wait"]
        self.assertEqual(walks[0]["args"], ["260", "485", "8"])
        self.assertIn("inserted object lifetime, faction and walk target coordinate space",
                      timeline["contract"]["not_proven"])

    def test_check_profile_rejects_unknown_source_and_unclassified_actions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = compile_opening_timeline(self.SEED, self.EVIDENCE)
            path = root / "ok.json"
            path.write_text(json.dumps(timeline), encoding="utf-8")
            self.assertEqual(check_opening_timeline(path, "story052")["event_count"], 58)
            with self.assertRaises(SystemExit):
                check_opening_timeline(path, "story051")
            unknown = dict(timeline, source_script="story999")
            for event in unknown["events"]:
                if not event["synthetic"]:
                    event["source_script"] = "story999"
            (root / "unknown.json").write_text(json.dumps(unknown), encoding="utf-8")
            with self.assertRaises(SystemExit):
                check_opening_timeline(root / "unknown.json")
            unclassified = json.loads(json.dumps(timeline))
            unclassified["events"][2]["kind"] = "script_action"
            (root / "unclassified.json").write_text(json.dumps(unclassified), encoding="utf-8")
            with self.assertRaises(SystemExit):
                check_opening_timeline(root / "unclassified.json", "story052")


class PostBattleStoryTimelineTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]

    def _compile(self, level: int) -> dict:
        code = f"{level:03d}"
        return compile_opening_timeline(
            self.ROOT / f"content/generated/hsl/chapter01/battle{code}_seed.json",
            self.ROOT / f"content/imported/hsl/chapter01/battle{code}/message_text_evidence.json",
        )

    def test_camp_and_throne_hall_scripts_compile_to_story_scenes(self):
        expectations = {
            55: ([2, 56], {"791", "818"}),
            56: ([2, 49], {"819", "827"}),
            61: ([3, 49], {"847", "857"}),
            62: ([6, 63], {"980", "991"}),
            63: ([6, 49], {"993", "1006"}),
            64: ([7, 49], {"1036", "1051"}),
        }
        for level, (next_args, sample_ids) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["source_script"], f"story{level:03d}")
            self.assertEqual(timeline["level_kind"], "story")
            events = timeline["events"]
            self.assertEqual(events[0]["kind"], "music_track", level)
            self.assertEqual(events[-1]["kind"], "scene_end_marker", level)
            next_events = [event for event in events if event["kind"] == "next_level_event"]
            self.assertEqual(len(next_events), 1, level)
            args = [int(value) if value.isdigit() else 49 for value in next_events[0]["args"]]
            self.assertEqual(args, next_args, level)
            message_ids = {event["message_id"] for event in events if event["kind"] == "dialogue_message_id"}
            self.assertTrue(sample_ids <= message_ids, level)
            for event in events:
                if event["kind"] == "dialogue_message_id":
                    self.assertTrue(event["message_text"], event["id"])
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))

    def test_level_63_shape_messages_keep_text_but_no_speaker_token(self):
        events = self._compile(63)["events"]
        shape = [event for event in events if event["kind"] == "shape_message"]
        self.assertEqual([event["message_id"] for event in shape], ["997", "998", "1000", "1002", "678"])
        self.assertEqual(shape[0]["params"]["shape_file"], "SHAPE\\FACE0054.SHP")
        self.assertEqual(shape[0]["params"]["name"], 306)
        self.assertEqual(shape[0]["actor_token"], "")
        self.assertTrue(shape[0]["message_text"])

    def test_level_901_ambush_opening_compiles_to_a_battle_preview(self):
        # 菲納斯河畔伏擊: level music, five walks from the north edge, the captain's two lines
        # and 雷歐納德's answer, WORD901, fail status, events 0 / 1, board refresh, first control.
        timeline = self._compile(901)
        self.assertEqual(timeline["source_script"], "story901")
        self.assertEqual(timeline["level_kind"], "battle")
        events = timeline["events"]
        kinds = [event["kind"] for event in events]
        self.assertEqual(kinds[0], "opening_music")
        self.assertEqual(kinds[-1], "first_control_marker")
        self.assertEqual(kinds.count("actor_walk"), 4)
        self.assertEqual(kinds.count("actor_walk_wait"), 1)
        self.assertEqual(kinds.count("event_status_enable"), 2)
        self.assertNotIn("win_status_enable", kinds)  # actInsertWinStatus is commented out in STORY901
        dialogue = [(event["args"][0], event["message_id"]) for event in events if event["kind"] == "dialogue_message_id"]
        self.assertEqual(dialogue, [("SID_ENEMY024", "1139"), ("SID_ENEMY024", "1140"), ("SID_雷歐納德", "1141")])
        self.assertTrue(all(event["message_text"] for event in events if event["kind"] == "dialogue_message_id"))
        title = next(event for event in events if event["kind"] == "section_title_resource")
        self.assertEqual(title["args"], ["SHAPE01\\WORD901.SHP"])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "timeline.json"
            path.write_text(json.dumps(timeline), encoding="utf-8")
            self.assertEqual(check_opening_timeline(path, "story901")["event_count"], len(events))
    # lane alt902
    def test_side_route_replacement_openings_compile_to_battle_previews(self):
        # level: (first kind, dialogue (token, id) pairs, section title member)
        expectations = {
            # 哈莫特沙漠 variant: level 24's opening plus 雷特's retort; the WORD024 title is reused.
            903: ("opening_music", [("SID_ENEMY024", "1628"), ("SID_雷特", "1629"), ("SID_雷歐納德", "1630"), ("SID_ENEMY024", "1631"), ("SID_雷歐納德", "1632")], "SHAPE01\\WORD024.SHP"),
            # 艾瓦台地 variant: the party finds the workers dead; its own WORD902 (尋 / SEEK) title.
            902: ("opening_music", [("SID_緹娜", "1422"), ("SID_雷歐納德", "1423"), ("SID_雪拉", "1424"), ("SID_琥", "1425"), ("SID_雷歐納德", "1426")], "SHAPE01\\WORD902.SHP"),
            # 利魯瑪山地 variant: STORY904 is STORY019 byte for byte (track 9 first, level music last, WORD019).
            904: ("music_track", [("SID_ENEMY041", "1487"), ("SID_雷特", "1457"), ("SID_ENEMY041", "1458"), ("SID_雷特", "1459"), ("SID_ENEMY041", "1460"), ("SID_雷特", "1461"), ("SID_ENEMY041", "1462"), ("SID_雷特", "1463")], "SHAPE01\\WORD019.SHP"),
        }
        for level, (first_kind, dialogue, title) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["source_script"], f"story{level:03d}", level)
            self.assertEqual(timeline["level_kind"], "battle", level)
            events = timeline["events"]
            kinds = [event["kind"] for event in events]
            self.assertEqual(kinds[0], first_kind, level)
            self.assertEqual(kinds[-1], "first_control_marker", level)
            self.assertNotIn("script_action", kinds, level)
            self.assertEqual([(event["args"][0], event["message_id"]) for event in events if event["kind"] == "dialogue_message_id"], dialogue, level)
            self.assertTrue(all(event["message_text"] and event["speaker_name"] for event in events if event["kind"] == "dialogue_message_id"), level)
            self.assertEqual([event["args"] for event in events if event["kind"] == "section_title_resource"], [[title]], level)
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))
        # 903 keeps level 24's shape: eight displacement walks (咕嚕's binds to nothing), seven dead messages, events 0 / 1.
        kinds903 = [event["kind"] for event in self._compile(903)["events"]]
        self.assertEqual(kinds903.count("actor_walk_disp"), 8)
        self.assertEqual(kinds903.count("dead_message_registration"), 7)
        self.assertEqual(kinds903.count("event_status_enable"), 2)
        self.assertNotIn("win_status_enable", kinds903)
        # 902 walks the five slots in from the east (four walks and one wait) and arms events 0-5 for the pass search.
        kinds902 = [event["kind"] for event in self._compile(902)["events"]]
        self.assertEqual((kinds902.count("actor_walk"), kinds902.count("actor_walk_wait")), (4, 1))
        self.assertEqual(kinds902.count("event_status_enable"), 6)
        self.assertEqual(kinds902.count("dead_message_registration"), 5)
        # 904 compiles to the same event kinds as level 19 and ends on actPlayLevelMusic before first control.
        kinds904 = [event["kind"] for event in self._compile(904)["events"]]
        self.assertEqual(kinds904, [event["kind"] for event in self._compile(19)["events"]])
        self.assertEqual(kinds904[-2], "opening_music")
    # end lane alt902

    # lane ch2a
    def test_ch2a_chapter_two_previews_and_camps_compile_and_check(self):
        expectations = {
            # level: (level_kind, first kind, last kind, next args or None, sample message ids)
            13: ("battle", "opening_music", "first_control_marker", None, {"1782", "1787", "1834"}),
            15: ("battle", "music_track", "first_control_marker", None, {"1794", "1800"}),
            17: ("battle", "opening_music", "first_control_marker", None, {"1359", "1363"}),
            18: ("battle", "music_track", "first_control_marker", None, {"1436", "1449", "774"}),
            19: ("battle", "music_track", "first_control_marker", None, {"1487", "1463"}),
            21: ("battle", "opening_music", "first_control_marker", None, {"1548", "1550"}),
            22: ("battle", "music_track", "first_control_marker", None, {"2405", "2410"}),
            24: ("battle", "opening_music", "first_control_marker", None, {"1628", "1632"}),
            66: ("story", "music_track", "scene_end_marker", [9, 49], {"1076", "1080", "792"}),
            67: ("story", "music_track", "scene_end_marker", [17, 49], {"1379", "1411", "1410"}),
            68: ("story", "music_track", "scene_end_marker", [17, 49], {"1401", "1410"}),
            69: ("story", "music_track", "scene_end_marker", [19, 49], {"1488", "1547"}),
        }
        for level, (level_kind, first, last, next_args, sample_ids) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["source_script"], f"story{level:03d}")
            self.assertEqual(timeline["level_kind"], level_kind, level)
            events = timeline["events"]
            self.assertEqual(events[0]["kind"], first, level)
            self.assertEqual(events[-1]["kind"], last, level)
            next_events = [event for event in events if event["kind"] == "next_level_event"]
            if next_args is None:
                self.assertEqual(next_events, [], level)
            else:
                self.assertEqual([[int(v) if v.isdigit() else 49 for v in e["args"]] for e in next_events], [next_args], level)
            message_ids = {event["message_id"] for event in events if event["kind"] == "dialogue_message_id"}
            self.assertTrue(sample_ids <= message_ids, level)
            for event in events:
                if event["kind"] == "dialogue_message_id" and not event.get("narration"):
                    self.assertTrue(event["speaker_name"], event["id"])
                self.assertNotEqual(event["kind"], "script_action", event["id"])
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))
        # Level 13's inserts are followed by actWalkDispWait,-1 (previous-insert convention); level 18 deletes the door
        # object and re-inserts it; level 67 grants the pass through actGetItem.
        walk13 = [e for e in self._compile(13)["events"] if e["kind"] == "actor_walk_disp_wait"]
        self.assertEqual({e["actor_token"] for e in walk13}, {"-1"})
        kinds18 = [e["kind"] for e in self._compile(18)["events"]]
        self.assertLess(kinds18.index("actor_delete"), kinds18.index("object_insert"))
        grant = [e for e in self._compile(67)["events"] if e["kind"] == "item_grant"]
        self.assertEqual([e["params"] for e in grant], [{"item_id": 281, "number": 1}])
    # end lane ch2a


# lane ch2b
class Chapter2TimelineTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]

    def _compile(self, level: int) -> dict:
        code = f"{level:03d}"
        return compile_opening_timeline(
            self.ROOT / f"content/generated/hsl/chapter01/battle{code}_seed.json",
            self.ROOT / f"content/imported/hsl/chapter01/battle{code}/message_text_evidence.json",
        )

    def test_chapter2_openings_and_story_scenes_compile_to_their_profiles(self):
        # level: (level_kind, first kind, sample message ids)
        expectations = {
            26: ("battle", "music_track", {"2423", "2427"}),
            28: ("battle", "opening_music", {"2468", "2472"}),
            29: ("battle", "opening_music", {"1655", "1683", "380"}),
            30: ("battle", "opening_music", {"1837", "1865", "1017"}),
            31: ("battle", "music_track", {"1900", "1923", "1919"}),
            32: ("battle", "opening_music", {"1977", "1988"}),
            33: ("battle", "music_track", {"1943", "1972", "728"}),
            34: ("battle", "music_track", {"1997", "2006"}),
            70: ("story", "music_track", {"1691", "1700", "718"}),
            71: ("story", "music_track", {"1927", "1936"}),
            72: ("story", "music_track", {"2041", "2054", "873"}),
        }
        for level, (kind, first_kind, sample_ids) in expectations.items():
            timeline = self._compile(level)
            events = timeline["events"]
            self.assertEqual(timeline["level_kind"], kind, level)
            self.assertEqual(events[0]["kind"], first_kind, level)
            self.assertEqual(events[-1]["kind"], "scene_end_marker" if kind == "story" else "first_control_marker", level)
            message_ids = {event["message_id"] for event in events if event["kind"] == "dialogue_message_id"}
            self.assertTrue(sample_ids <= message_ids, (level, sample_ids - message_ids))
            for event in events:
                self.assertNotEqual(event["kind"], "script_action", (level, event["id"]))
                if event["kind"] == "dialogue_message_id":
                    self.assertTrue(event["message_text"], event["id"])
                    self.assertTrue(event["narration"] or event["speaker_name"], event["id"])
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))
        # STORY071 ends on big-map writes without a next-level token; 70 / 72 return to the big map.
        self.assertEqual([e["kind"] for e in self._compile(71)["events"] if e["kind"] == "next_level_event"], [])
        self.assertIn("bigmap_walk_to_point", {e["kind"] for e in self._compile(71)["events"]})
        for level, point in ((70, "29"), (72, "35")):
            next_events = [e for e in self._compile(level)["events"] if e["kind"] == "next_level_event"]
            self.assertEqual([e["args"] for e in next_events], [[point, "gameBigMapLevel"]], level)
        # STORY072 spells one token actMEssage; it compiles as a dialogue like the others.
        spelled = [e for e in self._compile(72)["events"] if e.get("script_action_spelling") == "actMEssage"]
        self.assertEqual([e["kind"] for e in spelled], ["dialogue_message_id"])
# end lane ch2b


class ExtendedTokenTests(unittest.TestCase):
    def test_extended_tokens_compile_to_explicit_kinds_with_named_params(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            story_path = root / "story001.json"
            story_path.write_text(
                json.dumps(
                    {
                        "schema": "hsl_chapter01_script_ir.v1",
                        "source_file": "STORY001.TXT",
                        "action_chain": [
                            _action(0, "actSetBGToPos", ["512", "160"]),
                            _action(1, "actScrollBGToPosSpeed", ["640", "480", "4"]),
                            _action(2, "actMEssage", ["SID_PLAYER0", "1", "363"]),
                            _action(3, "actMessageIfExist", ["SID_PLAYER0", "1", "369", "370", "2", "SID_ENEMY023", "SID_ENEMY024"]),
                            _action(4, "actWaitPlayer", ["SID_ENEMY023", "2"]),
                            _action(5, "actDeleteObject", ["SID_ENEMY023", "2"]),
                            _action(6, "actDeletePosObject", ["640", "544", "32", "defProcTreasureBox"]),
                            _action(7, "actSetPlayerUndead", ["SID_ENEMY023", "1", "1"]),
                            _action(8, "actAddTE", ["1", "0", "2", "5", "6"]),
                            _action(9, "actPlayDefaultLevelMusic", ["1"]),
                            _action(10, "actSetTownExecEvent", ["town_歐姆村", "9"]),
                            _action(11, "actInsertFailStatus", ["0"]),
                            _action(12, "actShowWinFailStatus", []),
                        ],
                    }
                ),
                encoding="utf-8",
            )
            events = compile_opening_timeline(story_path)["events"]
            kinds = [event["kind"] for event in events]
            self.assertNotIn("script_action", kinds)
            self.assertEqual(kinds[:11], [
                "camera_position_set", "camera_position_target_speed", "dialogue_message_id", "dialogue_message_if_exist",
                "actor_action_wait", "actor_delete", "position_object_delete", "player_undead_flag", "town_event_add",
                "default_level_music", "town_exec_event",
            ])
            self.assertEqual(events[0]["params"], {"x": 512, "y": 160})
            self.assertEqual(events[1]["params"], {"x": 640, "y": 480, "speed": 4})
            self.assertEqual(events[2]["script_action_name"], "actMessage")
            self.assertEqual(events[2]["script_action_spelling"], "actMEssage")
            self.assertEqual(events[2]["message_id"], "363")
            self.assertEqual(events[3]["params"], {
                "player_code": "SID_PLAYER0", "serial": 1, "message_id": 369, "message_id_false": 370,
                "check_number": 2, "check_player_codes": ["SID_ENEMY023", "SID_ENEMY024"],
            })
            self.assertEqual(events[3]["message_id"], "369")
            self.assertEqual(events[3]["message_id_false"], "370")
            self.assertEqual(events[3]["actor_token"], "SID_PLAYER0")
            self.assertEqual(events[4]["actor_token"], "SID_ENEMY023")
            self.assertEqual(events[6]["params"]["proc_code"], "defProcTreasureBox")
            self.assertEqual(events[8]["params"], {"town_id": 1, "parent": 0, "num": 2, "children": [5, 6]})
            self.assertEqual(events[10]["params"], {"town_id": "town_歐姆村", "event": 9})
            self.assertEqual(events[7]["presentation_status"], "state_token_recorded_no_handler")
            for event in events[:11]:
                self.assertTrue(event["unresolved_semantics"], event["id"])
                self.assertTrue(event["display_line"].endswith(event["source_token"]) or event["kind"] in ("dialogue_message_id", "default_level_music"), event["id"])


# lane ch2c
class ChapterTwoOpeningTimelineTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]

    def _compile(self, level: int) -> dict:
        code = f"{level:03d}"
        return compile_opening_timeline(
            self.ROOT / f"content/generated/hsl/chapter01/battle{code}_seed.json",
            self.ROOT / f"content/imported/hsl/chapter01/battle{code}/message_text_evidence.json",
        )

    def test_battle_openings_compile_against_their_profiles(self):
        # level: (first kind, a kind the level introduces, sample message ids)
        expectations = {
            36: ("music_track", "camera_position_target", {"2056", "2069", "1128"}),
            37: ("music_track", "object_insert_random_position", {"2088", "2095"}),
            38: ("opening_music", "show_position_marker", {"2479", "2484"}),
            39: ("opening_music", "camera_position_target_speed", {"2130", "2131"}),
            40: ("opening_music", "actor_action_wait", {"2144", "2148"}),
            41: ("music_track", "actor_walk_wait", {"2155", "2176", "1017"}),
            43: ("opening_music", "actor_walk", {"2554", "2560"}),
            44: ("opening_music", "camera_position_target_speed", {"2248", "2249"}),
            45: ("opening_music", "show_position_marker_clear", {"2265"}),
        }
        for level, (first_kind, introduced_kind, sample_ids) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["level_kind"], "battle", level)
            events = timeline["events"]
            kinds = [event["kind"] for event in events]
            self.assertEqual(kinds[0], first_kind, level)
            self.assertEqual(kinds[-1], "first_control_marker", level)
            self.assertIn(introduced_kind, kinds, level)
            self.assertNotIn("script_action", kinds, level)
            message_ids = {event["message_id"] for event in events if event["kind"] == "dialogue_message_id"}
            self.assertTrue(sample_ids <= message_ids, level)
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))

    def test_level_37_random_position_beats_keep_slot_params(self):
        events = self._compile(37)["events"]
        random_set = [event for event in events if event["kind"] == "random_position_set"]
        self.assertEqual(len(random_set), 1)
        self.assertEqual(random_set[0]["params"]["num"], 5)
        self.assertEqual(random_set[0]["params"]["positions"][:2], [240, 240])
        inserts = [event for event in events if event["kind"] == "object_insert_random_position"]
        self.assertEqual(len(inserts), 10)
        self.assertEqual(inserts[0]["params"], {"code": "obj_Story_Level_Enemy067", "disp_x": 0, "disp_y": 32, "pos_id": 0})
        self.assertEqual([event["params"]["id"] for event in events if event["kind"] == "camera_random_position_target"], [0, 1, 2, 3, 4])

    def test_level_74_inn_scene_compiles_to_a_story_scene(self):
        timeline = self._compile(74)
        self.assertEqual(timeline["level_kind"], "story")
        events = timeline["events"]
        self.assertEqual(events[0]["kind"], "music_track")
        self.assertEqual(events[-1]["kind"], "scene_end_marker")
        next_events = [event for event in events if event["kind"] == "next_level_event"]
        self.assertEqual([event["args"] for event in next_events], [["42", "gameBigMapLevel"]])
        self.assertEqual(sum(1 for event in events if event["kind"] == "dialogue_message_id"), 36)
        town = [event["kind"] for event in events if event["kind"].startswith(("town_", "bigmap_"))]
        self.assertEqual(town, ["town_event_delete", "town_event_add", "town_event_add", "bigmap_track_flag_clear", "bigmap_point_flag_clear"])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "timeline.json"
            path.write_text(json.dumps(timeline), encoding="utf-8")
            self.assertEqual(check_opening_timeline(path, "story074")["event_count"], len(events))
# end lane ch2c


# lane ch3
class FinaleChainTimelineTests(unittest.TestCase):
    ROOT = Path(__file__).resolve().parents[1]

    def _compile(self, level: int) -> dict:
        code = f"{level:03d}"
        return compile_opening_timeline(
            self.ROOT / f"content/generated/hsl/chapter01/battle{code}_seed.json",
            self.ROOT / f"content/imported/hsl/chapter01/battle{code}/message_text_evidence.json",
        )

    def test_finale_battle_openings_compile_against_their_profiles(self):
        # level: (first kind, a kind the level introduces, sample message ids)
        expectations = {
            73: ("music_track", "event_select_insert", {"2182", "2184", "380"}),
            75: ("opening_music", "camera_position_target_speed", {"2269", "2279"}),
            76: ("opening_music", "win_status_enable", {"2291", "2298"}),
            77: ("opening_music", "position_object_delete", {"2350", "2360", "804"}),
            78: ("opening_music", "actor_action_wait", {"2291", "2298"}),
            79: ("opening_music", "actor_delete", {"2383", "2391", "2326"}),
            80: ("opening_music", "actor_walk", {"2486", "2492"}),
            59: ("opening_music", "shape_message", {"2333", "2346"}),
        }
        for level, (first_kind, introduced_kind, sample_ids) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["level_kind"], "battle", level)
            events = timeline["events"]
            kinds = [event["kind"] for event in events]
            self.assertEqual(kinds[0], first_kind, level)
            self.assertEqual(kinds[-1], "first_control_marker", level)
            self.assertIn(introduced_kind, kinds, level)
            self.assertNotIn("script_action", kinds, level)
            message_ids = {event["message_id"] for event in events if event["kind"] == "dialogue_message_id"}
            self.assertTrue(sample_ids <= message_ids, (level, sample_ids - message_ids))
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))
        # STORY073 has no section title / statuses: it is a choice scene, not a battle opening.
        kinds73 = [event["kind"] for event in self._compile(73)["events"]]
        self.assertNotIn("section_title_resource", kinds73)
        self.assertEqual(kinds73.count("dialogue_message_id"), 4)
        # Level 59's four nameless voices stay shape_message tokens with the -1 face argument.
        voices = [event for event in self._compile(59)["events"] if event["kind"] == "shape_message"]
        self.assertEqual([event["args"][0] for event in voices], ["-1"] * 4)
        self.assertEqual([event["args"][2] for event in voices], ["2339", "2341", "2343", "2345"])

    def test_finale_story_scenes_compile_with_their_flow_tokens(self):
        expectations = {
            57: (["next_level_get_over_event"], None, 6),
            81: (["next_level_event"], ["59", "59"], 25),
            82: (["next_level_event"], ["90", "998"], 11),
        }
        for level, (flow_kinds, next_args, dialogue_count) in expectations.items():
            timeline = self._compile(level)
            self.assertEqual(timeline["level_kind"], "story", level)
            events = timeline["events"]
            kinds = [event["kind"] for event in events]
            self.assertEqual(kinds[0], "music_track", level)
            self.assertEqual(kinds[-1], "scene_end_marker", level)
            for kind in flow_kinds:
                self.assertIn(kind, kinds, level)
            next_events = [event["args"] for event in events if event["kind"] == "next_level_event"]
            self.assertEqual(next_events, [next_args] if next_args else [], level)
            self.assertEqual(kinds.count("dialogue_message_id"), dialogue_count, level)
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "timeline.json"
                path.write_text(json.dumps(timeline), encoding="utf-8")
                self.assertEqual(check_opening_timeline(path, f"story{level:03d}")["event_count"], len(events))
        # 57 / 81 carry the storage-window / keep-ST record-only tokens; 82 does not.
        for level, present in ((57, True), (81, True), (82, False)):
            kinds = [event["kind"] for event in self._compile(level)["events"]]
            self.assertEqual("storage_window_enter" in kinds and "player_stamina_keep" in kinds, present, level)
# end lane ch3


def _action(index: int, name: str, args: list[str]) -> dict:
    return {
        "index": index,
        "script_id": "story051",
        "source_file": "STORY051.TXT",
        "action_index": index,
        "chain_index": 0,
        "primary": name,
        "name": name,
        "args": args,
        "evidence_tier": "resource-derived",
        "unresolved_semantics": [
            "dry-run action record preserves original order and args; handler behavior is not fully mapped"
        ],
    }


if __name__ == "__main__":
    unittest.main()
