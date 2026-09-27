import json
import unittest
from pathlib import Path

from hsltools.levels.timeline import ACTION_KIND, EXTENDED_TOKENS, canonical_action_name
from hsltools.data.story_token_coverage import build_report, parse_action_header, scan_story_tokens

HEADER = """
#define defNoOne                -3
#define actDelay                	1   // [delay counter]
#define actMessage					10	// [player code][serial][message code]
#define actSetBGToPos	     		97  // [x][y]
#define actCheckPlayer          	38  // [num][id1][id2][...]
//#define actCheckProcObjectNotExist	125	// [proc code]
#define actShowWinFailStatus    	31
"""

STORY = """
#include ACTION.H
[story]
action = actDelay,40,actMEssage,SID_PLAYER0,1,363   ; inline comment with actWalk
;action = actSetBGToPos,64,64
action = actSetBGToPos,128,0,actShowWinFailStatus
action = actUnknownToken,1
"""


class StoryTokenCoverageTests(unittest.TestCase):
    def test_action_header_parses_live_defines_only(self):
        catalog = parse_action_header(HEADER)
        self.assertEqual(catalog["actDelay"], {"opcode": 1, "arg_doc": "[delay counter]"})
        self.assertEqual(catalog["actSetBGToPos"]["opcode"], 97)
        self.assertEqual(catalog["actShowWinFailStatus"]["arg_doc"], "")
        self.assertNotIn("actCheckProcObjectNotExist", catalog)
        self.assertNotIn("defNoOne", catalog)

    def test_story_scan_skips_comments_and_keeps_source_order(self):
        self.assertEqual(
            scan_story_tokens(STORY),
            ["actDelay", "actMEssage", "actSetBGToPos", "actShowWinFailStatus", "actUnknownToken"],
        )

    def test_canonical_name_is_case_insensitive_for_known_tokens(self):
        self.assertEqual(canonical_action_name("actMEssage"), "actMessage")
        self.assertEqual(canonical_action_name("actUnknownToken"), "actUnknownToken")

    def test_report_counts_levels_and_unmapped_tokens_against_the_compiler(self):
        report = build_report(parse_action_header(HEADER), {"001": STORY, "501": STORY}, {"ACTION.H": "a", "EXTRAS.H": "b"})
        tokens = report["tokens"]
        self.assertEqual(tokens["actMessage"]["source_spellings"], ["actMEssage"])
        self.assertEqual(tokens["actMessage"]["story_level_count"], 2)
        self.assertEqual(tokens["actMessage"]["story_main_level_count"], 1)
        self.assertTrue(tokens["actSetBGToPos"]["mapped"])
        self.assertEqual(tokens["actSetBGToPos"]["compiler_kind"], "camera_position_set")
        self.assertFalse(tokens["actUnknownToken"]["in_catalog"])
        self.assertFalse(tokens["actUnknownToken"]["mapped"])
        self.assertFalse(tokens["actCheckPlayer"]["mapped"])
        self.assertEqual(tokens["actCheckPlayer"]["story_level_count"], 0)
        self.assertEqual(report["levels"]["001"]["unmapped_tokens"], ["actUnknownToken"])
        self.assertFalse(report["levels"]["001"]["fully_mapped"])
        self.assertEqual(report["summary"]["story_used_unmapped_tokens"], ["actUnknownToken"])
        self.assertEqual(report["summary"]["story_used_token_count"], 5)
        self.assertEqual(report["summary"]["compiler_mapped_token_count"], len(ACTION_KIND))

    def test_extended_tokens_do_not_claim_winfail_conditions(self):
        for name in EXTENDED_TOKENS:
            self.assertFalse(name.startswith("actCheck"), name)
        self.assertNotIn("actTRUE", ACTION_KIND)
        self.assertNotIn("actFALSE", ACTION_KIND)
        kinds = [spec[0] for spec in EXTENDED_TOKENS.values()]
        self.assertEqual(len(kinds), len(set(kinds)), "extended kinds must be unique")
        self.assertFalse(set(kinds) & {kind for name, kind in ACTION_KIND.items() if name not in EXTENDED_TOKENS})

    def test_tracked_report_covers_every_story_token(self):
        report = json.loads(Path("content/generated/hsl/static/hsl01/story_token_coverage.json").read_text(encoding="utf-8"))
        self.assertEqual(report["schema"], "hsl_story_token_coverage.v1")
        self.assertEqual(report["summary"]["story_used_unmapped_count"], 0)
        self.assertEqual(report["summary"]["level_count"], report["sources"]["story_file_count"])
        self.assertEqual(report["levels"]["001"]["unmapped_tokens"], [])
        self.assertEqual(report["tokens"]["actSetBGToPos"]["story_level_count"], 26)
        self.assertEqual(report["tokens"]["actCheckPlayer"]["story_level_count"], 0)

    def test_coordinator_names_every_compiler_kind(self):
        """Every kind the compiler can emit must be handled or explicitly record-only in
        BattleOpeningCoordinator (a match branch or the RECORD_ONLY_KINDS list); a kind
        missing here would fall into skipped_records at runtime."""
        source = Path("game/battle/runtime/BattleOpeningCoordinator.gd").read_text(encoding="utf-8")
        before, rest = source.split("const RECORD_ONLY_KINDS", 1)
        record_only, after = rest.split("= [", 1)[1].split("]", 1)
        handled = before + after  # match branches and helpers, without the record-only list
        missing = sorted(kind for kind in set(ACTION_KIND.values()) if f'"{kind}"' not in source)
        self.assertEqual(missing, [])
        for name, spec in EXTENDED_TOKENS.items():
            kind = f'"{spec[0]}"'
            self.assertNotEqual(kind in record_only, kind in handled, f"{name} ({spec[0]}) must be either record-only or handled, not both/neither")


if __name__ == "__main__":
    unittest.main()
