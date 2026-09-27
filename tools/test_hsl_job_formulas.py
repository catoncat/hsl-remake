"""The job formula table contract: hsltools.model.jobs evaluates the authored rows, the job_formulas
task projects them for the runtime, and malformed rows are rejected instead of silently defaulting."""
import copy
import json
import unittest
from pathlib import Path

from hsltools.data.job_formulas import JobFormulasTask, OUT, job_symbols
from hsltools.model import jobs
from hsltools.registry import Context


class JobFormulasTests(unittest.TestCase):
    def test_generated_table_is_the_authored_rows_joined_to_their_symbols(self):
        rendered = json.loads(JobFormulasTask().render(Context())[OUT.as_posix()])
        self.assertEqual(rendered['schema'], jobs.FORMULAS_SCHEMA)
        self.assertEqual(rendered['authored'], jobs.FORMULAS)
        symbols = job_symbols()
        symbols.update({code: symbol for symbol, code in jobs.authored_job_symbols().items()})
        for key, row in rendered['jobs'].items():
            self.assertEqual(row['symbol'], symbols[int(key)])
            self.assertEqual({k: v for k, v in row.items() if k != 'symbol'}, {k: v for k, v in jobs.formulas()[int(key)].items() if k != 'symbol'})
        self.assertEqual(json.loads(Path(OUT).read_text()), rendered, 'tracked runtime table is stale; run hsl generate job_formulas')

    def test_term_semantics_pre_divisor_cap_soft_knee_and_bonus(self):
        variables = dict(str=19, dex=9, mind=50, con=7, level=30, hp_level=0)
        # [mul, var, div] is mul*var/div; [mul, var, div, pre] divides the variable first; a bare int is a constant.
        self.assertEqual(jobs.sum_terms([[116, 'str', 100, 2], [36, 'dex', 100], 16], variables), 116 * (19 // 2) // 100 + 36 * 9 // 100 + 16)
        self.assertNotEqual(jobs.sum_terms([[116, 'str', 100, 2]], variables), jobs.sum_terms([[116, 'str', 200]], variables))
        row = dict(jobs.formulas()[85])  # soft knee 44 then +45, as the priest branch folds high magic
        base = jobs.base_values(85, variables, 30, 0)
        magic = 30 * 50 // 100 + 2 * 30
        self.assertGreater(magic, row['magic_attack']['soft_knee'])
        self.assertEqual(base['magic_attack'], (magic - 44) // 2 + 44 + 45)
        capped = jobs.base_values(80, variables, 99, 99)  # cap 76 applies before the bonus
        self.assertEqual(capped['magic_attack'], 76)
        self.assertEqual(capped["max_hp"], 99 + 180 * 7 // 100 + 19 // 8)

    def test_malformed_rows_are_rejected(self):
        good = json.loads(json.dumps(jobs.formulas()[80]))
        jobs.validate_row(80, good)
        for mutate in [lambda r: r['max_hp'].append([1, 'luck', 1]),           # unknown variable
                       lambda r: r['attack'].append([1, 'str', 0]),            # zero divisor
                       lambda r: r['resist']['rows'].pop(),                    # not five elements
                       lambda r: r.__setitem__('allocation_quota', [1, 1, 1]),
                       lambda r: r['magic_attack'].pop('bonus'),
                       lambda r: r['caps'].pop('con')]:
            broken = json.loads(json.dumps(good))
            mutate(broken)
            with self.assertRaises(ValueError):
                jobs.validate_row(80, broken)

    def test_authored_job_names_itself_without_type_h(self):
        # 101 has no TYPE.H `#define`; its row declares jobDragonLord and the character tables resolve it.
        self.assertNotIn(101, job_symbols())
        self.assertEqual(jobs.authored_job_symbols(), {'jobDragonLord': 101})
        from hsltools.native.sources import sources
        _, _, defines = sources()
        self.assertEqual(defines['jobDragonLord'], 101)
        self.assertEqual(defines['jobDarkAngel'], 100)
        profile = jobs.source_profile({'code': '102', 'job': 'jobDragonLord', 'mode': 'pmPlayer', 'evidence_tier': 'authored'}, defines)
        self.assertEqual(profile['job_code'], 101)
        self.assertNotIn('evidence', profile)

    def test_authored_job_symbol_may_not_shadow_type_h(self):
        table = copy.deepcopy(jobs.formulas())
        for job, symbol in [(101, 'jobDarkAngel'), (100, 'jobDarkAngelTwo'), (101, 'DragonLord')]:
            broken = copy.deepcopy(table)
            broken[job]['symbol'] = symbol
            jobs.authored_job_symbols.cache_clear()
            original = jobs.formulas
            jobs.formulas = lambda: broken
            try:
                with self.assertRaises(ValueError):
                    jobs.authored_job_symbols()
            finally:
                jobs.formulas = original
                jobs.authored_job_symbols.cache_clear()
        unnamed = copy.deepcopy(table)
        unnamed[101].pop('symbol')
        original = jobs.formulas
        jobs.formulas = lambda: unnamed
        try:
            with self.assertRaises(ValueError):
                jobs.authored_job_symbols()
        finally:
            jobs.formulas = original
            jobs.authored_job_symbols.cache_clear()

    def test_unknown_job_has_no_profile(self):
        with self.assertRaises(ValueError):
            # jobAll 1000 is a TYPE.H selector, not a class: no row in the formula table.
            jobs.source_profile({'code': '150', 'job': 'jobAll', 'mode': 'pmEnemy'}, {'jobAll': 1000, 'pmEnemy': 0x20000})


if __name__ == '__main__':
    unittest.main()
