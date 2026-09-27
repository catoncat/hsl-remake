import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.checks.function_catalog as catalog


SAMPLE = """int fcn.00409a60(int param_1,int param_2)
{
    iVar3 = *0x4c1bc8 + *(param_1 + 0xa4) * 0x1fc;
    iVar2 = (*(iVar3 + 0x50) - *(iVar1 + 0x50)) / 2;
    iVar2 = *(iVar3 + 0xbc) + iVar2 - *(iVar1 + 0x19a);
    fcn.0042c780(100);
    return iVar2;
}
"""


class FunctionCatalogTests(unittest.TestCase):
    def test_symbolize_names_globals_callees_and_actor_fields(self):
        known = catalog.load_known()
        actor, item = catalog.load_field_maps()
        text = catalog.symbolize(SAMPLE, "0x409a60", known, actor, item)
        self.assertIn("g_live_actors", text)
        self.assertIn("rand_range(100)", text)
        self.assertIn("/*actor.live_hit_ratio*/", text)
        self.assertIn("/*actor.avoid_hit_ratio*/", text)
        self.assertNotIn("calc_hit_chance", text, "a function never renames itself")

    def test_features_extract_callees_and_globals(self):
        result = catalog.features(SAMPLE, "0x409a60")
        self.assertEqual(result["callees"], ["0x42c780"])
        self.assertEqual(result["globals"], ["0x4c1bc8"])

    def test_known_functions_registry_is_well_formed(self):
        known = catalog.load_known()
        self.assertGreaterEqual(len(known), 41)
        for address, row in known.items():
            self.assertRegex(address, r"^0x4[0-9a-f]{5}$")
            self.assertIn(row["role"], catalog.ROLES)
            self.assertTrue(row["name"] and row["source"])

    def test_build_and_check_reject_leaks_and_bad_roles(self):
        with tempfile.TemporaryDirectory() as tmp:
            decompiled = Path(tmp) / "decompiled"
            decompiled.mkdir()
            (decompiled / "0x409a60.c").write_text(SAMPLE * 3)
            (decompiled / "0x40f8b0.failed").write_text("crash")
            judgments = Path(tmp) / "judgments.jsonl"
            answers = {"role": {"type": "choice", "choice": "combat_resolution", "confidence": 0.9, "probabilities": {"combat_resolution": 0.9, "unknown": 0.1}}}
            answers.update({name: {"type": "noul", "noul": 0.5} for name in catalog.PROPERTIES})
            judgments.write_text(json.dumps({"address": "0x409a60", "model": "jev-1.13.0", "answers": answers}) + "\n")
            exe = Path(tmp) / "fake.exe"
            exe.write_bytes(b"MZ")
            built = catalog.build_catalog(exe, decompiled, judgments)
            catalog.check(built)
            self.assertEqual(built["functions"]["0x409a60"]["name"], "calc_hit_chance")
            self.assertTrue(built["functions"]["0x40f8b0"]["decompile_failed"])
            self.assertEqual(built["judged_count"], 1)
            broken = json.loads(json.dumps(built))
            broken["functions"]["0x409a60"]["role"] = "not_a_role"
            with self.assertRaises(ValueError):
                catalog.check(broken)
            leaked = json.loads(json.dumps(built))
            leaked["functions"]["0x409a60"]["callees"] = ["~/drive_c"]
            with self.assertRaises(ValueError):
                catalog.check(leaked)

    def test_judge_all_rejudges_only_new_or_changed_symbolization(self):
        known = catalog.load_known()
        actor, item = catalog.load_field_maps()
        with tempfile.TemporaryDirectory() as tmp:
            decompiled = Path(tmp) / "decompiled"
            decompiled.mkdir()
            (decompiled / "0x401000.c").write_text(SAMPLE * 3)   # judged before, text unchanged
            (decompiled / "0x401100.c").write_text(SAMPLE * 3)   # judged before a symbol was registered
            (decompiled / "0x401200.c").write_text(SAMPLE * 3)   # never judged
            (decompiled / "0x401300.c").write_text("short")      # below MIN_CODE_CHARS
            answers = {"role": {"type": "choice", "choice": "unknown", "confidence": 0.5, "probabilities": {"unknown": 0.5}}}
            answers.update({name: {"type": "noul", "noul": 0.1} for name in catalog.PROPERTIES})
            unchanged = catalog.symbol_hash(catalog.symbolize(SAMPLE * 3, "0x401000", known, actor, item))
            judgments = Path(tmp) / "judgments.jsonl"
            judgments.write_text(
                json.dumps({"address": "0x401000", "symbol_hash": unchanged, "model": "jev-1.13.0", "answers": answers}) + "\n"
                + json.dumps({"address": "0x401100", "symbol_hash": "0000000000000000", "model": "jev-1.13.0", "answers": answers}) + "\n")

            preview = catalog.judge_all(decompiled, judgments, "jev-1.13.0", 2, None, dry_run=True)
            self.assertEqual({k: preview[k] for k in ("unchanged", "stale", "new", "pending")}, {"unchanged": 1, "stale": 1, "new": 1, "pending": 2})
            self.assertEqual(len(judgments.read_text().splitlines()), 2, "dry run must not write")

            sent = []

            def fake_many(requests, model, workers):
                sent.extend(state["decompiled_c"] for state, _ in requests)
                return [{"model": model, "answers": answers, "usage": {"input_tokens": 7}} for _ in requests]

            original = catalog.typesafe.system_one_many
            catalog.typesafe.system_one_many = fake_many
            try:
                counts = catalog.judge_all(decompiled, judgments, "jev-1.13.0", 2, None)
            finally:
                catalog.typesafe.system_one_many = original
            self.assertEqual((counts["judged"], counts["input_tokens"], counts["errors"]), (2, 14, 0))
            self.assertEqual(len(sent), 2)
            rows = [json.loads(line) for line in judgments.read_text().splitlines()]
            self.assertEqual([row["address"] for row in rows], ["0x401000", "0x401100", "0x401100", "0x401200"])
            self.assertTrue(all("symbol_hash" in row for row in rows))
            exe = Path(tmp) / "fake.exe"
            exe.write_bytes(b"MZ")
            built = catalog.build_catalog(exe, decompiled, judgments)
            self.assertEqual(built["judged_count"], 3, "newest row per address wins; short function stays unjudged")
            again = catalog.judge_all(decompiled, judgments, "jev-1.13.0", 2, None, dry_run=True)
            self.assertEqual(again["pending"], 0)

    def test_query_filters_by_role_property_and_unknown(self):
        functions = {
            "0x401000": {"role": "pathfinding_terrain", "role_confidence": 0.9, "properties": {"iterates_neighbors": 0.95}, "chars": 10, "callees": []},
            "0x401100": {"role": "pathfinding_terrain", "role_confidence": 0.4, "properties": {"iterates_neighbors": 0.2}, "chars": 10, "callees": [], "name": "known"},
            "0x401200": {"role": "ai_decision", "role_confidence": 0.9, "properties": {"iterates_neighbors": 0.9}, "chars": 10, "callees": []},
        }
        rows = catalog.query({"functions": functions}, "pathfinding_terrain", ["iterates_neighbors>=0.8"], True, 0.5, 10)
        self.assertEqual([address for address, _ in rows], ["0x401000"])


if __name__ == "__main__":
    unittest.main()
