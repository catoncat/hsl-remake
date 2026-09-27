import unittest

import hsltools.data.town_initial_trees as tt


def _event(code, comment, show=30, tokens=()):
    return {
        "code": code,
        "comment": comment,
        "show_name": {"resource_id": show, "text": "x"} if show is not None else None,
        "item_code": None,
        "events": [{"token": token, "args": [str(a) for a in args]} for token, args in tokens],
    }


def _towndef(events):
    return {
        "schema": "hsl_towndef.v1",
        "symbols": {"town_A": 1, "town_B": 4, "SID_x": 0},
        "town_events": events,
    }


class TownInitialTreesTests(unittest.TestCase):
    def test_roots_nesting_and_exclusions(self):
        events = [
            _event(1, "A武器店", 32, [("teShapeMessage", ["S", 1, 2, 0]), ("teCreateShop", [32])]),
            _event(2, "A酒館", 31, [("teCreateSubEventMenu", [])]),
            _event(3, "A酒館老闆", 875, [("teShapeMessage", ["S", 1, 2, 0]), ("teDeleteSelfTE", [2, 1, 3]), ("teAddSelfTE", [2, 1, 4])]),
            _event(4, "A酒館老闆二", 875, [("teShapeMessage", ["S", 1, 2, 0])]),
            _event(5, "A完成", 30, [("teSetExecEvent", ["town_A", 0])]),
            _event(6, "A酒館旅人", 900, [("teSelectInsertEvent", ["SID_x", 2, 10, 7, 11, 8])]),
            _event(7, "A酒館旅人選一", 900),
            _event(8, "A酒館旅人選二", 900),
            _event(9, None, None, [("teExecEvent", [5])]),
            # town B: shop is script-added -> whole town starts empty; 11 is dead data
            _event(10, "B武器店", 32, [("teCreateShop", [32])]),
            _event(11, "B港口", 1281, [("teCreateSubEventMenu", [])]),
            _event(12, "B港口船長", 1223, [("teShapeMessage", ["S", 1, 2, 0])]),
        ]
        actions = [
            {"script": "winfail001", "token": "actSetTownExecEvent", "args": ["town_A", "5"]},
            {"script": "winfail012", "token": "actAddTE", "args": ["town_B", "10", "0"]},
            {"script": "winfail012", "token": "actAddTE", "args": ["town_B", "11", "1", "12"]},
        ]
        data = tt.build_trees(_towndef(events), actions)
        self.assertEqual(data["schema"], tt.SCHEMA)
        self.assertEqual(data["evidence_tier"], "static-derived")
        town_a = data["towns"]["town_A"]
        self.assertEqual(town_a["tree"], {"0": [1, 2], "2": [3, 6]})
        excluded = {entry["code"]: [r["reason"] for r in entry["reasons"]] for entry in town_a["excluded"]}
        self.assertEqual(excluded[4], ["added_at_runtime"])
        self.assertEqual(excluded[5], ["exec_target_only"])
        self.assertEqual(excluded[7], ["exec_target_only"])
        self.assertEqual([(e["code"], [r["reason"] for r in e["reasons"]]) for e in data["unassigned"]], [(9, ["no_show_name"])])
        self.assertIn("winfail001 actSetTownExecEvent", next(e for e in town_a["excluded"] if e["code"] == 5)["reasons"][0]["by"])
        town_b = data["towns"]["town_B"]
        self.assertEqual(town_b["tree"], {"0": []})
        reasons_b = {entry["code"]: entry["reasons"][0]["reason"] for entry in town_b["excluded"]}
        self.assertEqual(reasons_b, {10: "added_at_runtime", 11: "town_script_populated", 12: "added_at_runtime"})
        self.assertEqual(data["statistics"]["root_entries"], 2)
        self.assertEqual(data["statistics"]["nested_entries"], 2)

    def test_chained_act_line_split(self):
        line = "actAddTE,town_B,10,0,actAddTE,town_B,11,1,12 ; comment"
        found = [(m.group(1), [p for p in m.group(2).split(",")[1:]]) for m in tt.ACT_LINE_RE.finditer(line.split(";")[0])]
        self.assertEqual(found, [("actAddTE", ["town_B", "10", "0"]), ("actAddTE", ["town_B", "11", "1", "12 "])])

    def test_rejects_wrong_schema(self):
        with self.assertRaises(ValueError):
            tt.build_trees({"schema": "other", "town_events": []}, [])


if __name__ == "__main__":
    unittest.main()
