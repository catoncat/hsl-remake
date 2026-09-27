import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.data.skill_book import OUT, aliases, build, declared_mask


class InitialSkillBookTests(unittest.TestCase):
    def test_generated_book_matches_source_and_exact_identity(self):
        book = build()
        self.assertEqual(json.loads(OUT.read_text()),book)
        self.assertEqual(book['actors']['001']['supported_initial_ids'],['special:magicOTHER:magicCode01'])
        self.assertEqual(book['actors']['026']['supported_initial_ids'],['magic:magicAIR:magicCode01','magic:magicFIRE:magicCode01'])
        self.assertEqual(book['actors']['025']['supported_initial_ids'],['magic:magicWATER:magicCode01','magic:magicAIR:magicCode05'])
        for code in ['021','023','024']:
            self.assertEqual(book['actors'][code]['declarations'],{})
            self.assertEqual(book['actors'][code]['supported_initial_ids'],[])

    def test_unrecognized_alias_is_not_a_grant(self):
        symbols = aliases()
        self.assertEqual(declared_mask('風刃,酸蝕幻霧',symbols),17)
        self.assertEqual(declared_mask('0',symbols),0)
        for value in ['', 'unknown', '1', '風刃,']:
            with self.assertRaisesRegex(ValueError,'Unknown skill alias'):
                declared_mask(value,symbols)

    def test_initial_declaration_is_not_full_runtime_parity(self):
        book = build()
        self.assertEqual(book['evidence_tier'],'resource-derived')
        for entry in book['skills'].values():
            if entry['damage_policy'].startswith('native_'):
                self.assertEqual(entry['formula_evidence'], 'static-derived')
                self.assertEqual(entry['damage_bounds'], 'native_triangular')
                continue
            self.assertEqual(entry['formula_evidence'],'provisional')
            self.assertEqual(entry['damage_bounds'],'inclusive')


if __name__=='__main__': unittest.main()
