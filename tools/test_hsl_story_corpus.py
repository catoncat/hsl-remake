"""Unit tests for hsltools.data.story_corpus: small-sample parsing, tracked-corpus
consistency (offline, no PAK) and message-evidence agreement."""
from __future__ import annotations

import json
import sys
import tempfile
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import hsltools.data.story_corpus as corpus  # noqa: E402
from hsltools.levels.message_text import SPEAKER_IDS  # noqa: E402
from hsltools.levels.timeline import ACTION_KIND  # noqa: E402

TABLE = {"0": "雷歐納德", "306": "???", "371": "現在，才是真正的開始....", "396": "第一句", "397": "第二句",
         "121": "消滅所有敵人", "999": "臉圖對白", "500": "城鎮台詞", "501": "選項一", "502": "選項二"}
EXTRAS = {"SID_雷歐納德": 0, "SID_緹娜": 1}

SAMPLE_SCRIPT = "\r\n".join([
    "#include ACTION.H",
    "[win]                   ; sample",
    "code = 0",
    "message = -1,121",
    "action = actCheckEnemyTotalNumber,0",
    "action = actMEssage,SID_PLAYER0,1,371,actDelay,10   ; odd spelling",
    "action = actMessageIfExist,SID_PLAYER0,1,396,397,2,SID_ENEMY023,SID_ENEMY024",
    "action = actShapeMessage,SHAPE\\FACE0054.SHP,306,999",
    "action = actSetNextPlayLevelEvent,52,gameBigMapLevel",
    "[event]",
    "code = 0",
    "action = actMessage,defNoOne,1,12345",
]).encode("cp950")

SAMPLE_TOWNDEF = "\r\n".join([
    "#include TOWNDEF.H",
    "[town_event]   ; 測試鎮",
    "code = 1",
    "show_name = 0",
    "event = tePlayerMessage,SID_雷歐納德,500,0",
    "event = teShapeMessage,SHAPE\\FACE0073.SHP,306,999,0",
    "event = teSelectInsertEvent,SID_緹娜,2,501,7,502,8",
    "event = teSetNextPlayLevelEvent,6,6",
]).encode("cp950")


class SmallSampleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.flow = {"gameBigMapLevel": 49}

    def test_act_script_messages_speakers_and_edges(self) -> None:
        script = corpus.build_act_script("winfail", 51, "@:\\data\\winfail051.txt", SAMPLE_SCRIPT, TABLE, self.flow)
        by_id = {}
        for entry in script["messages"]:
            by_id.setdefault(entry["id"], entry)
        self.assertEqual(script["message_ids"], ["121", "371", "396", "397", "999", "12345"])
        self.assertEqual(script["missing_text_ids"], ["12345"])
        self.assertTrue(by_id["121"]["board_label"])
        # case-insensitive token spelling resolves to the ACTION.H name; SPEAKER_IDS[51] names slot 0
        self.assertEqual(by_id["371"]["command"], "actMessage")
        self.assertEqual(by_id["371"]["speaker_name"], TABLE[SPEAKER_IDS[51]["SID_PLAYER0"]])
        self.assertEqual(by_id["397"]["alternate_of"], "396")
        self.assertEqual(by_id["999"]["speaker_name_id"], "306")
        self.assertEqual(by_id["999"]["speaker_name"], "???")
        self.assertIsNone(by_id["999"]["sid_token"])
        self.assertTrue(by_id["12345"]["narration"])
        self.assertIsNone(by_id["12345"]["text"])
        self.assertEqual(script["action_counts"]["actMessage"], 2)  # actMEssage + actMessage
        self.assertEqual(script["unmapped_action_tokens"], ["actCheckEnemyTotalNumber"])
        self.assertEqual([e["to_big_map"] for e in script["next_level_events"]], [True])
        self.assertEqual(script["next_level_events"][0]["event"], 49)
        self.assertEqual(script["sid_tokens"], ["SID_ENEMY023", "SID_ENEMY024", "SID_PLAYER0"])

    def test_script_without_speaker_table_keeps_tokens_only(self) -> None:
        script = corpus.build_act_script("story", 999, "@:\\data\\STORY999.TXT", SAMPLE_SCRIPT, TABLE, self.flow)
        self.assertIsNone(script["speaker_table"])
        self.assertTrue(all("speaker_name" not in e for e in script["messages"] if e["sid_token"] is not None))

    def test_towndef_messages(self) -> None:
        script = corpus.build_towndef("@:\\data\\TOWNDEF.TXT", SAMPLE_TOWNDEF, TABLE, self.flow)
        self.assertEqual(script["message_ids"], ["500", "999", "501", "502"])
        entries = {e["id"]: e for e in script["messages"]}
        self.assertEqual(entries["500"]["sid_token"], "SID_雷歐納德")
        self.assertEqual(entries["999"]["speaker_name"], "???")
        self.assertEqual((entries["501"]["choice_index"], entries["501"]["choice_event"]), (0, "7"))
        self.assertEqual(entries["502"]["sid_token"], "SID_緹娜")
        self.assertEqual(script["town_events"][0]["show_name"], "雷歐納德")
        self.assertEqual(script["sid_tokens"], ["SID_緹娜", "SID_雷歐納德"])
        self.assertEqual(script["next_level_events"][0]["command"], "teSetNextPlayLevelEvent")

    def test_number_gaps_are_listed_per_hundred_block(self) -> None:
        self.assertEqual(corpus._number_gaps([1, 2, 5, 501, 503, 900]), [3, 4, 502])

    def test_corpus_files_are_deterministic_and_index_rows_match(self) -> None:
        script = corpus.build_act_script("winfail", 51, "@:\\data\\winfail051.txt", SAMPLE_SCRIPT, TABLE, self.flow)
        sources = {"resource_table": {"member": "x"}, "extras_header": {"member": "y"}}
        files_a = corpus.build_corpus([script], sources, EXTRAS)
        files_b = corpus.build_corpus([json.loads(json.dumps(script))], sources, EXTRAS)
        self.assertEqual(files_a, files_b)
        self.assertEqual(set(files_a), {"index.json", "scripts/WINFAIL051.json"})
        index = json.loads(files_a["index.json"])
        self.assertEqual(index["summary"]["missing_text_ids"], ["12345"])
        self.assertEqual(index["scripts"][0]["message_id_count"], 6)
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            corpus.write_files(files_a, out)
            self.assertEqual(corpus.check_offline(out), [])
            self.assertEqual(corpus.compare_with_tracked(files_a, out), [])
            tampered = json.loads(files_a["scripts/WINFAIL051.json"])
            tampered["messages"][0]["text"] = "changed"
            (out / "scripts/WINFAIL051.json").write_text(corpus._dumps(tampered), encoding="utf-8")
            self.assertTrue(any("digest" in e for e in corpus.check_offline(out)))
            self.assertTrue(any("differs" in e for e in corpus.compare_with_tracked(files_a, out)))


class TrackedCorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.index = corpus.load_index(corpus.OUTPUT_DIR)

    def test_offline_check_passes(self) -> None:
        self.assertEqual(corpus.check_offline(corpus.OUTPUT_DIR), [])

    def test_claim_limits_are_ids_into_the_packet_table(self) -> None:
        # The boundary text lives only in the packet; index.json and the code carry ids.
        self.assertEqual(self.index["claim_limits"], corpus.CLAIM_LIMIT_IDS)
        self.assertEqual(self.index["claim_limits_packet"], corpus.CLAIM_LIMITS_PACKET)
        packet = (ROOT / corpus.CLAIM_LIMITS_PACKET).read_text(encoding="utf-8")
        heading = re.search(r"^#{2,3} .*claim limits.*$", packet, re.M | re.I)
        table = packet[heading.end():].split("\n## ", 1)[0].split("\n### ", 1)[0]
        rows = [line.split("|")[1].strip().strip("`") for line in table.splitlines() if line.startswith("| `")]
        self.assertEqual(rows, corpus.CLAIM_LIMIT_IDS)

    def test_family_counts_and_totals(self) -> None:
        families = self.index["summary"]["families"]
        self.assertEqual({f: s["script_count"] for f, s in families.items()}, {"story": 152, "winfail": 130, "storyover": 1, "towndef": 1})
        self.assertEqual(self.index["summary"]["script_count"], 284)
        self.assertEqual(self.index["summary"]["missing_text_ids"], [])
        self.assertEqual(self.index["summary"]["winfail_without_story"], [])
        self.assertEqual(self.index["next_level_symbols"]["gameBigMapLevel"], 49)
        self.assertEqual(self.index["extras_sid_defines"]["SID_雷歐納德"], 0)
        self.assertEqual(len(self.index["extras_sid_defines"]), 9)

    def test_index_rows_are_invariant_with_script_files(self) -> None:
        members = set()
        for row in self.index["scripts"]:
            self.assertNotIn(row["member"], members)
            members.add(row["member"])
            self.assertEqual(row["resolved_text_count"] + len(row["missing_text_ids"]), row["message_id_count"])
            self.assertLessEqual(row["message_id_count"], row["message_reference_count"])
            for token in row["unmapped_action_tokens"]:
                self.assertNotIn(token, ACTION_KIND)
            if row["family"] in ("story", "winfail"):
                self.assertEqual(row["speaker_table_level"], row["number"] if row["number"] in SPEAKER_IDS else None)
        self.assertEqual(len(members), 284)

    def test_unmapped_tokens_are_only_winfail_conditions(self) -> None:
        unmapped = self.index["summary"]["unmapped_action_tokens"]
        self.assertTrue(unmapped)
        for token in unmapped:
            self.assertTrue(token.startswith("actCheck") or token in {"actTRUE", "actFALSE"}, token)
        for row in self.index["scripts"]:
            if row["family"] in ("story", "storyover"):
                self.assertEqual(row["unmapped_action_tokens"], [], row["member"])

    def test_first_battle_chain_and_level_51_texts(self) -> None:
        texts, speakers = corpus.level_texts(corpus.OUTPUT_DIR, 51)
        self.assertEqual(texts["371"], "現在，才是真正的開始....")
        self.assertEqual(speakers["SID_PLAYER0"], "雷歐納德")
        row = next(r for r in self.index["scripts"] if r["family"] == "winfail" and r["number"] == 51)
        self.assertEqual([(e["level"], e["event"]) for e in row["next_level_events"]], [(52, 52), (52, 52)])

    def test_tracked_message_evidence_matches_corpus(self) -> None:
        errors, stats = corpus.compare_with_evidence(corpus.OUTPUT_DIR)
        self.assertEqual(errors, [])
        self.assertGreaterEqual(stats["files"], 13)
        self.assertGreater(stats["compared_messages"], 300)

    @unittest.skipUnless(corpus.DEFAULT_PAK.is_file(), "original PAK not available")
    def test_pak_rebuild_matches_tracked_corpus(self) -> None:
        self.assertEqual(corpus.compare_with_tracked(corpus.build_from_pak(corpus.DEFAULT_PAK), corpus.OUTPUT_DIR), [])


if __name__ == "__main__":
    unittest.main()
