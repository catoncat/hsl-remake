import json
import unittest

import hsltools.data.secret_man_goods as goods


class SecretManGoodsTests(unittest.TestCase):
    def test_tracked_table_passes_offline_cross_checks(self):
        data = json.loads(goods.OUTPUT.read_text(encoding="utf-8"))
        self.assertEqual(goods.offline_issues(data), [])
        self.assertEqual([row["price"] for row in data["rows"]], [5000, 7500, 10000, 15000, 20000, 30000, 40000, 60000, 99999])
        self.assertEqual([row["event"] for row in data["rows"]], [123, 113, 114, 115, 116, 117, 118, 119, 120])
        self.assertEqual(data["rows"][0]["items"][:2], [8, 145])
        self.assertEqual(data["rows"][8]["items"][-1], 301)
        self.assertTrue(all(len(row["items"]) == goods.SLOTS and all(row["items"]) for row in data["rows"]))

    def test_corrupted_rows_are_reported(self):
        data = json.loads(goods.OUTPUT.read_text(encoding="utf-8"))
        data["rows"][1]["price"] = 5000
        data["rows"][2]["items"][0] = 99999
        issues = goods.offline_issues(data)
        self.assertTrue(any("does not increase" in issue for issue in issues), issues)
        self.assertTrue(any("does not quote" in issue for issue in issues), issues)
        self.assertTrue(any("not all in ITEM.TXT" in issue for issue in issues), issues)

    def test_check_uses_offline_mode_without_the_exe(self):
        self.assertEqual(goods.main(["--check", "--exe", "/nonexistent/hsl01.exe"]), 0)


if __name__ == "__main__":
    unittest.main()
