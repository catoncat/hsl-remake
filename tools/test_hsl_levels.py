"""hsltools.levels: the per-level families replace their legacy commands one for one, and the per-level
products (opening timeline, story scene, message text, chapter dialogue); one segment per former file."""
from __future__ import annotations

# ---- from test_hsl_levels.py ----
# hsltools.levels: the per-level data chain families replace their legacy commands one for one.
#
# Parity: every native task's replaces command is a ledger check command, no ledger command of
# the family survives in all_tasks(), and the in-process check line equals what the CLI
# (`hsl check <task>`) prints for a sample level.
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.legacy import check_commands  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

# family -> (ledger script name, sample ledger commands whose task's PASS line must match the CLI's)
FAMILIES: dict[str, tuple[str, tuple[str, ...]]] = {
    'battle_seed': ('tools/hsl_battle_seed.py', ('tools/hsl_battle_seed.py --level 37 --check', 'tools/hsl_battle_seed.py --level 501 --check')),
    'opening_timeline_compile': ('tools/hsl_opening_timeline_compile.py', (
        'tools/hsl_opening_timeline_compile.py --check',
        'tools/hsl_opening_timeline_compile.py content/generated/hsl/chapter01/battle037_seed.json --message-evidence content/imported/hsl/chapter01/battle037/message_text_evidence.json --output content/imported/hsl/chapter01/battle037/opening_timeline.json --check')),
    'opening_timeline_check': ('tools/hsl_opening_timeline_check.py', (
        'tools/hsl_opening_timeline_check.py',
        'tools/hsl_opening_timeline_check.py content/imported/hsl/chapter01/battle578/opening_timeline.json --source-script story578')),
    'message_text_evidence_check': ('tools/hsl_message_text_evidence_check.py', (
        'tools/hsl_message_text_evidence_check.py', 'tools/hsl_message_text_evidence_check.py --level 37')),
    'level_map_objects': ('tools/hsl_level_map_objects.py', ('tools/hsl_level_map_objects.py --level 1 --check', 'tools/hsl_level_map_objects.py --level 12 --check')),
    'level_sounds': ('tools/hsl_level_sounds.py', ('tools/hsl_level_sounds.py --level 22 --check',)),
    'level_source_texts': ('tools/hsl_level_source_texts.py', ('tools/hsl_level_source_texts.py --level 22 --check',)),
    'level_actors': ('tools/hsl_level_actors.py', ('tools/hsl_level_actors.py --level 53 --check', 'tools/hsl_level_actors.py --level 500 --check')),
    'story_scene': ('tools/hsl_story_scene.py', ('tools/hsl_story_scene.py --level 1 --check', 'tools/hsl_story_scene.py --level 73 --check')),
}


class LevelFamilyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = registry.all_tasks()
        cls.commands = check_commands()
        cls.ctx = registry.Context()

    def native(self, family: str) -> list[registry.Task]:
        return [task for task in self.tasks if task.family == family]

    def test_every_family_command_is_replaced(self):
        for family, (script, _) in FAMILIES.items():
            with self.subTest(family=family):
                native = self.native(family)
                replaced = sorted(command for task in native for command in task.replaces)
                expected = sorted(command for command in self.commands if command.split()[0] == script)
                self.assertEqual(replaced, expected)
                self.assertEqual(len(native), len(expected))

    def test_levels_come_from_the_data(self):
        imported = sorted(int(p.name[6:]) for p in (ROOT / 'content/imported/hsl/chapter01').glob('battle[0-9][0-9][0-9]') if p.is_dir() and p.name != 'battle500')
        self.assertEqual(sorted(task.level for task in self.native('battle_seed')), imported)
        story = [level for level in imported if not 501 <= level <= 578]
        self.assertEqual(sorted(task.level for task in self.native('level_sounds')), story)
        self.assertEqual(sorted(task.level for task in self.native('level_source_texts')), story)
        self.assertEqual(sorted(task.level for task in self.native('level_actors')), sorted(story + [500]))
        self.assertEqual(sorted(task.level for task in self.native('story_scene')), story)

    def test_native_check_line_matches_the_cli(self):
        by_replaces = {command: task for task in self.tasks for command in task.replaces}
        sampled = [by_replaces[command] for _, samples in FAMILIES.values() for command in samples]
        cli = registry.cli_check_lines([task.name for task in sampled])
        for task in sampled:
            with self.subTest(task=task.name):
                self.assertEqual(task.check(self.ctx), cli[task.name])

    def test_generated_families_render_the_tracked_bytes(self):
        for name in ('opening_timeline_compile:51', 'opening_timeline_compile:578', 'story_scene:53', 'story_scene:52', 'level_battle:52', 'level_battle:53'):
            task = registry.select(self.tasks, [name])[0]
            rendered = task.render(self.ctx)
            self.assertEqual(set(rendered), set(task.outputs))
            for path, data in rendered.items():
                self.assertEqual((ROOT / path).read_bytes(), data, f'{name}: {path}')

    def test_generate_without_the_original_pak_fails_and_names_it(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for family in ('battle_seed', 'level_map_objects', 'level_sounds', 'level_source_texts', 'level_actors'):
            task = self.native(family)[0]
            with self.subTest(task=task.name):
                code, output, _ = registry.run_task(task, 'generate', ctx)
                self.assertEqual(code, 1, output)
                self.assertIn('/nonexistent/hsl.pak', output)

    def test_generate_of_a_pure_checker_is_skipped_not_failed(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for family in ('opening_timeline_check', 'message_text_evidence_check'):
            task = self.native(family)[0]
            with self.subTest(task=task.name):
                code, output, _ = registry.run_task(task, 'generate', ctx)
                self.assertEqual(code, 2, output)
                self.assertIn('pure checker', output)


# ---- from test_hsl_opening_timeline.py ----

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


# ---- from test_hsl_story_scene.py ----

import json
import unittest
from pathlib import Path

from hsltools.levels import story_scene

ROOT_story_scene = Path(__file__).resolve().parents[1]


class StorySceneTests(unittest.TestCase):
    def test_level_58_scene_matches_tracked_output_and_binds_cast(self) -> None:
        scenario = story_scene.build(58)
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
                self.assertTrue((ROOT_story_scene / res_path[len("res://"):]).exists(), f"level {level} {key}: {res_path}")
            for spec in scenario["opening"]["story_objects"].values():
                if "preview" in spec:
                    self.assertTrue((ROOT_story_scene / spec["preview"][len("res://"):]).exists())

    def test_level_60_captive_scene_has_no_player_and_points_to_level_53(self) -> None:
        scenario = story_scene.build(60)
        self.assertIsNone(scenario["player_unit_id"])
        self.assertEqual(len(scenario["story_actors"]), 15)
        self.assertEqual(scenario["opening"]["next_level_event"], [53, 53])
        self.assertEqual(scenario["opening"]["actor_bindings"]["SID_ENEMY029/1"]["actor_id"], "029")

    def test_level_53_opening_preview_installs_the_player_slot_and_ends_on_a_card(self) -> None:
        scenario = story_scene.build(53)
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


# ---- from test_hsl_message_text_evidence_check.py ----

import json
from pathlib import Path
import tempfile
import unittest
from hsltools.sources.tables import parse_table
from hsltools.levels.message_text import DEFAULT_EVIDENCE, check_message_text_evidence


class MessageTextTest(unittest.TestCase):
    def test_controls_and_commas(self):
        raw = '[other]\nitem = 1,ignored\n[name]\nitem = 1,@4帝國@1萬歲！#快,走\n'
        self.assertEqual(parse_table(raw.encode('cp950')), {'1': '帝國萬歲！\n快,走'})

    def test_duplicate_rejected(self):
        with self.assertRaises(ValueError):
            parse_table(b'[name]\nitem = 1,a\nitem = 1,b')

    def test_tampering_and_missing_source(self):
        evidence = json.loads(DEFAULT_EVIDENCE.read_text())
        source = Path(evidence['sources']['text_table'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / source).parent.mkdir(parents=True)
            (root / source).write_bytes((DEFAULT_EVIDENCE.parent / source).read_bytes())
            path = root / 'evidence.json'
            evidence['messages']['363'] = 'invented speech'
            path.write_text(json.dumps(evidence))
            with self.assertRaisesRegex(ValueError, 'differs'):
                check_message_text_evidence(path)
            (root / source).unlink()
            with self.assertRaises(FileNotFoundError):
                check_message_text_evidence(path)


# ---- from test_hsl_chapter_dialogue.py ----

import json
import unittest
from pathlib import Path

from hsltools.levels.message_text import (SPEAKER_IDS, chapter_paths, check_message_text_evidence, level_message_ids, level_paths,
                                          seed_message_ids)
from hsltools.sources.tables import parse_table

ROOT_chapter_dialogue = Path(__file__).resolve().parents[1]


class ChapterDialogueTests(unittest.TestCase):
    def test_parse_table_strips_color_controls_and_keeps_line_breaks(self):
        data = "[name]\r\nitem = 5,@1你好#世界@0\r\n[other]\r\nitem = 6,ignored\r\n".encode("cp950")
        self.assertEqual(parse_table(data), {"5": "你好\n世界"})

    def test_level52_message_ids_come_from_seed_scripts_and_speakers(self):
        seed = json.loads((ROOT_chapter_dialogue / "content/generated/hsl/chapter01/battle052_seed.json").read_text(encoding="utf-8"))
        per_script = seed_message_ids(seed)
        self.assertEqual(per_script["story"], ["379", "380", "381", "383", "384", "385", "386", "387", "388", "389", "390", "391", "394"])
        self.assertEqual(per_script["winfail"], ["122", "378", "392", "393"])
        ids = level_message_ids(52, seed)
        self.assertEqual(ids[:3], ["0", "122", "305"])
        self.assertIn("382", ids)
        self.assertEqual(set(SPEAKER_IDS[52]), {"SID_PLAYER0", "SID_ENEMY021", "SID_ENEMY023", "SID_ENEMY024", "SID_ENEMY025", "SID_ENEMY026"})

    def test_tracked_evidence_matches_the_original_table(self):
        # The chapter-wide evidence keeps the hand-listed IDS (23); each level's own file
        # carries exactly the ids its seed scripts and speaker table name.
        chapter = check_message_text_evidence(ROOT_chapter_dialogue / chapter_paths()["evidence"], None)
        self.assertEqual(chapter["message_id_count"], 23)
        for level, count in ((51, 21), (52, 23)):
            summary = check_message_text_evidence(ROOT_chapter_dialogue / level_paths(level)["evidence"], level)
            self.assertEqual(summary["level"], level)
            self.assertEqual(summary["message_id_count"], count)

    def test_level51_evidence_names_the_messenger_speaker(self):
        evidence = json.loads((ROOT_chapter_dialogue / level_paths(51)["evidence"]).read_text(encoding="utf-8"))
        self.assertEqual(evidence["speaker_names"]["10000"], "拉爾斯帝國兵")
        self.assertEqual(evidence["section_title"]["source_member"], "SHAPE01\\WORD051.SHP")

    def test_level52_speaker_labels_are_declared_with_policy(self):
        evidence = json.loads((ROOT_chapter_dialogue / level_paths(52)["evidence"]).read_text(encoding="utf-8"))
        self.assertEqual(evidence["speaker_names"]["SID_ENEMY025"], "法蘭克")
        self.assertEqual(evidence["speaker_names"]["SID_ENEMY026"], "帝國法師")
        self.assertEqual(evidence["section_title"]["source_member"], "SHAPE01\\WORD052.SHP")


if __name__ == "__main__":
    import unittest
    unittest.main()
