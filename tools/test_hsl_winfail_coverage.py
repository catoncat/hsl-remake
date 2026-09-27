import json
import tempfile
import unittest
from pathlib import Path

import hsltools.data.winfail_coverage as coverage


FAKE_RULES = '''extends RefCounted
const RULES_SCHEMA := "hsl_winfail_script_rules.v1"
const SUPPORTED_CONDITIONS := [
\t"actCheckPlayer",  # dead-unit check
\t"actTRUE",
]
const KNOWN_UNSUPPORTED_CONDITIONS := [
\t"actFALSE",
]
const APPLIED_ACTIONS := [
\t"actMessage",
\t"actInsertObject",
]
const WORLD_FLAG_ACTIONS := [
\t"actAddTE",
]
const PRESENTATION_ACTIONS := [
\t"actDelay",
]
'''

FAKE_ACTION_H = '''#define actDelay                \t1   // [delay counter]
#define actMessage\t\t\t\t\t10\t// [player code][serial][message code]
#define actInsertObject \t\t\t18\t// [code][x][y]
#define actCheckPlayer          \t38  // [num][id1][id2][...]
#define actTRUE\t\t\t\t\t\t67
#define actAddTE \t\t\t\t\t80\t// [town id][parent][num][child1][...]
'''


def fake_level(level, tokens):
    return {
        "level": level,
        "member": f"@:\\\\data\\\\winfail{level:03d}.txt",
        "byte_length": 10,
        "sha256": "0" * 64,
        "section_counts": {"win": 1},
        "tokens": tokens,
    }


class WinfailCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.rules = Path(self.tmp.name) / "WinfailScenarioRules.gd"
        self.rules.write_text(FAKE_RULES, encoding="utf-8")
        self.sets = coverage.support_sets(self.rules)

    def tearDown(self):
        self.tmp.cleanup()

    def test_support_sets_come_from_gd_constants(self):
        self.assertEqual(self.sets["SUPPORTED_CONDITIONS"], ["actCheckPlayer", "actTRUE"])
        self.assertEqual(self.sets["APPLIED_ACTIONS"], ["actMessage", "actInsertObject"])
        self.assertEqual(self.sets["PRESENTATION_ACTIONS"], ["actDelay"])
        self.assertEqual(coverage.applied_tokens(self.sets), {"actCheckPlayer", "actTRUE", "actMessage", "actInsertObject"})
        self.assertEqual(coverage.recorded_tokens(self.sets), {"actAddTE", "actDelay"})

    def test_missing_constant_or_wrong_schema_fails(self):
        broken = Path(self.tmp.name) / "broken.gd"
        broken.write_text(FAKE_RULES.replace("const PRESENTATION_ACTIONS", "const OTHER"), encoding="utf-8")
        with self.assertRaises(ValueError):
            coverage.support_sets(broken)
        broken.write_text(FAKE_RULES.replace("hsl_winfail_script_rules.v1", "v2"), encoding="utf-8")
        with self.assertRaises(ValueError):
            coverage.support_sets(broken)

    def test_level_tokens_count_every_chain_command(self):
        metadata = {
            "section_blocks": [
                {"name": "win", "actions": [{"chain": [{"name": "actCheckPlayer", "args": ["1", "SID_ENEMY025"]}]}, {"chain": [{"name": "actMessage", "args": []}]}]},
                {"name": "event", "actions": [{"chain": [{"name": "actTRUE", "args": []}]}, {"chain": [{"name": "actMessage", "args": []}, {"name": "actDelay", "args": ["20"]}]}]},
            ]
        }
        tokens, sections = coverage.level_tokens(metadata)
        self.assertEqual(tokens, {"actCheckPlayer": 1, "actDelay": 1, "actMessage": 2, "actTRUE": 1})
        self.assertEqual(sections, {"event": 1, "win": 1})

    def test_classification_distinguishes_applied_recorded_and_unsupported(self):
        verdict = coverage.classify({"actCheckPlayer": 1, "actMessage": 2}, self.sets)
        self.assertEqual(verdict, {"unsupported_tokens": [], "recorded_only_tokens": [], "fully_supported": True, "fully_applied": True})
        verdict = coverage.classify({"actCheckPlayer": 1, "actDelay": 3, "actAddTE": 1}, self.sets)
        self.assertTrue(verdict["fully_supported"])
        self.assertFalse(verdict["fully_applied"])
        self.assertEqual(verdict["recorded_only_tokens"], ["actAddTE", "actDelay"])
        verdict = coverage.classify({"actFALSE": 1, "actUseItem": 1, "actMessage": 1}, self.sets)
        self.assertEqual(verdict["unsupported_tokens"], ["actFALSE", "actUseItem"])
        self.assertFalse(verdict["fully_supported"])

    def test_report_totals_and_check_roundtrip(self):
        levels = [
            fake_level(1, {"actCheckPlayer": 1, "actMessage": 1}),
            fake_level(2, {"actCheckPlayer": 1, "actDelay": 2}),
            fake_level(3, {"actCheckPlayer": 1, "actUseItem": 1}),
            fake_level(501, {"actCheckPlayer": 1, "actUseItem": 1, "actGetItem": 1}),
            fake_level(502, {"actTRUE": 1}),
        ]
        report = coverage.build_report(levels, self.sets, self.rules)
        totals = report["totals"]
        self.assertEqual(totals["file_count"], 5)
        self.assertEqual(totals["main_level_count"], 3)
        self.assertEqual(totals["main_fully_supported"], 2)
        self.assertEqual(totals["main_fully_applied"], 1)
        self.assertEqual(totals["all_fully_supported"], 3)
        self.assertEqual(totals["unsupported_token_main_level_counts"], {"actUseItem": 1})
        self.assertEqual(totals["token_totals"]["actCheckPlayer"], 4)
        self.assertFalse(report["levels"]["501"]["main_level"])
        self.assertEqual(coverage.check(json.loads(json.dumps(report)), self.sets), [])

    def test_check_detects_stale_verdicts_and_support_set_drift(self):
        report = coverage.build_report([fake_level(1, {"actCheckPlayer": 1, "actDelay": 1})], self.sets, self.rules)
        stale = json.loads(json.dumps(report))
        stale["levels"]["001"]["fully_applied"] = True
        self.assertTrue(any("fully_applied is stale" in error for error in coverage.check(stale, self.sets)))
        stale = json.loads(json.dumps(report))
        stale["totals"]["main_fully_supported"] = 0
        self.assertIn("totals are stale", coverage.check(stale, self.sets))
        drifted = dict(self.sets)
        drifted["PRESENTATION_ACTIONS"] = []
        errors = coverage.check(json.loads(json.dumps(report)), drifted)
        self.assertTrue(any("PRESENTATION_ACTIONS differs" in error for error in errors))
        self.assertTrue(any("unsupported_tokens is stale" in error for error in errors))

    def test_tracked_report_matches_current_interpreter(self):
        output = coverage.DEFAULT_OUTPUT
        if not output.exists():
            self.skipTest("tracked coverage report not generated")
        report = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(coverage.check(report, coverage.support_sets()), [])
        self.assertEqual(report["totals"]["main_level_count"], 47)
        self.assertTrue(report["levels"]["053"]["fully_applied"])
        self.assertTrue(report["levels"]["052"]["fully_supported"])


    def test_token_meanings_come_from_trailing_comments(self):
        meanings = coverage.parse_gd_token_meanings(FAKE_RULES, "SUPPORTED_CONDITIONS")
        self.assertEqual(meanings, {"actCheckPlayer": "dead-unit check", "actTRUE": ""})
        self.assertEqual(coverage.parse_gd_token_meanings(FAKE_RULES, "MISSING"), {})

    def test_action_header_shapes_join_opcode_and_argument_comment(self):
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        shapes = coverage.action_header_shapes(header)
        self.assertEqual(shapes["actMessage"], (10, "[player code][serial][message code]"))
        self.assertEqual(shapes["actTRUE"], (67, ""))

    def test_token_table_rows_report_missing_meaning_and_missing_define(self):
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        shapes = coverage.action_header_shapes(header)
        rows, problems = coverage.token_table_rows(self.rules, shapes, {"actCheckPlayer": 4, "actDelay": 2})
        self.assertEqual([row["token"] for row in rows], ["actCheckPlayer", "actTRUE", "actMessage", "actInsertObject", "actAddTE", "actDelay"])
        self.assertEqual(rows[0]["occurrences"], 4)
        self.assertEqual(rows[0]["args"], "[num][id1][id2][...]")
        self.assertEqual(rows[1]["occurrences"], 0)
        # every token but actCheckPlayer lacks its comment; actAddTE is in the header, actInsertObject too
        self.assertEqual(len([p for p in problems if "no `# meaning`" in p]), 5)
        self.assertFalse(any("not defined in ACTION.H" in p for p in problems))
        del shapes["actDelay"]
        _, problems = coverage.token_table_rows(self.rules, shapes, {})
        self.assertTrue(any(p == "PRESENTATION_ACTIONS: actDelay is not defined in ACTION.H" for p in problems))

    def test_token_table_renders_one_row_per_token_in_constant_order(self):
        documented = FAKE_RULES.replace('\t"actTRUE",', '\t"actTRUE",  # always holds').replace('\t"actMessage",', '\t"actMessage",\t# push a line')
        rules = Path(self.tmp.name) / "documented.gd"
        rules.write_text(documented, encoding="utf-8")
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        report = coverage.build_report([fake_level(1, {"actCheckPlayer": 1, "actMessage": 3})], self.sets, rules)
        rows, _ = coverage.token_table_rows(rules, coverage.action_header_shapes(header), report["totals"]["token_totals"])
        table = coverage.render_token_table(rows, report)
        self.assertIn("| `actTRUE` | — | always holds | 0 |", table)
        self.assertIn("| `actMessage` | `[player code][serial][message code]` | push a line | 3 |", table)
        self.assertEqual(table.count("\n| `act"), 6)
        self.assertLess(table.index("## 条件"), table.index("## 动作"))
        self.assertEqual(coverage.token_table_summary("X", rows), "X tokens=6 conditions=2 applied=2 world_flags=1 presentation=1")

    def test_inline_empty_array_does_not_swallow_next_constant(self):
        source = 'const A := []\nconst B := [\n\t"x",\n\t"y",\n]\nconst C := [\n]\n'
        self.assertEqual(coverage.parse_gd_string_array(source, 'A'), [])
        self.assertEqual(coverage.parse_gd_string_array(source, 'B'), ['x', 'y'])
        self.assertEqual(coverage.parse_gd_string_array(source, 'C'), [])


if __name__ == "__main__":
    unittest.main()
