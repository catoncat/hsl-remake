"""hsltools.checks.player_copy_traditional: a simplified character or listed simplified word in a
player-visible string fails; comments, developer calls and developer JSON fields do not; the table
holds only true differences and none of the characters that traditional text uses on their own."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools.checks import player_copy_traditional as copy_check  # noqa: E402
from hsltools import original_content  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

# Characters that traditional text uses on their own (皇后／子曰詩云／鄰里／干涉／系統／傢伙／白痴 …) must
# never be in the table: they would flag the original's own corpus.
TRADITIONAL_ON_THEIR_OWN = '后云里干几系采症伙痴据划蒙涌兹扎凌克斗丑恒挂夸淀迹荐帘苹腊蜡洒尸准愿筑范余灶晒游'


def write(root: Path, relative: str, text: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')


class PlayerCopyTraditionalTests(unittest.TestCase):
    def scan(self, files: dict[str, str]) -> tuple[list[str], dict[str, int]]:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'game').mkdir()
            for relative, text in files.items():
                write(root, relative, text)
            return copy_check.scan(root)

    def test_table_holds_true_differences_only(self) -> None:
        table = copy_check.SIMPLIFIED_TO_TRADITIONAL
        self.assertGreater(len(table), 1000)
        for simplified, traditional in table.items():
            self.assertNotEqual(simplified, traditional)
            self.assertEqual((len(simplified), len(traditional)), (1, 1))
        for char in TRADITIONAL_ON_THEIR_OWN:
            self.assertNotIn(char, table, char)
        for word, traditional in copy_check.SIMPLIFIED_WORDS.items():
            self.assertNotEqual(word, traditional)
        self.assertEqual(copy_check.simplified_in('重新游玩'), ['游玩'])
        self.assertEqual(copy_check.simplified_in('重新挑战'), ['战'])
        self.assertEqual(copy_check.simplified_in('重新挑戰 · 遊玩'), [])

    def test_simplified_in_gd_player_string_fails(self) -> None:
        issues, counts = self.scan({'game/ui/Panel.gd': 'extends Node\nfunc _ready() -> void:\n\tbutton.text = "重新游玩  ·  Enter"\n\tlabel.text = "重新挑战"\n'})
        self.assertEqual(len(issues), 2, issues)
        self.assertIn('game/ui/Panel.gd:3: simplified 游玩→遊玩', issues[0])
        self.assertIn('game/ui/Panel.gd:4: simplified 战→戰', issues[1])
        self.assertEqual(counts['gd_files'], 1)

    def test_comments_and_developer_calls_are_not_player_copy(self) -> None:
        source = ('extends Node\n## 说明：开发者注释\n# 简体注释 "战斗"\nfunc _ready() -> void:\n'
                  '\tassert(ok, "战斗状态错误")\n\tpush_error("简体错误 %s" % x)\n\tprint("调试")\n\tlabel.text = "戰鬥不能"\n')
        issues, counts = self.scan({'game/ui/Panel.gd': source})
        self.assertEqual(issues, [])
        self.assertEqual(counts['strings'], 1)

    def test_json_player_keys_fail_and_developer_fields_pass(self) -> None:
        scene = {'title': '弃卒 · 死守', 'result_labels': {'win_0': '敵軍已清除', 'fail_0': '雷歐納德 阵亡'},
                 'comments': {'story_scene': ['开发者说明，简体也无妨']}, 'notes': ['战斗备注'],
                 'units': [{'name': '雷歐納德', 'dead_message': {'messages': [{'text': '放開我！你們這些傢伙'}]}, 'evidence': '简体证据字段'}]}
        issues, counts = self.scan({'content/battles/battle_099.json': json.dumps(scene, ensure_ascii=False)})
        self.assertEqual(len(issues), 2, issues)
        self.assertIn('content/battles/battle_099.json title: simplified 弃→棄', issues[0])
        self.assertIn('result_labels/fail_0: simplified 阵→陣', issues[1])
        self.assertEqual(counts['json_files'], 1)
        clean = dict(scene, title='棄卒 · 死守', result_labels={'win_0': '敵軍已清除', 'fail_0': '雷歐納德 陣亡'})
        issues, _ = self.scan({'content/battles/battle_099.json': json.dumps(clean, ensure_ascii=False)})
        self.assertEqual(issues, [])

    @unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
    def test_the_original_corpus_never_trips_the_table(self) -> None:
        scripts = sorted((ROOT / 'content/imported/hsl/story_corpus/scripts').glob('*.json'))
        self.assertGreater(len(scripts), 100)
        for path in scripts:
            for json_path, text in copy_check.json_player_strings(json.loads(path.read_text())):
                self.assertEqual(copy_check.simplified_in(text), [], f'{path.name} {json_path}: {text}')


if __name__ == '__main__':
    unittest.main()
