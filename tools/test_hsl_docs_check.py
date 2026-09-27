"""Broken navigation must fail on real local files, including new untracked docs."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from tools.hsl_docs_check import check_files, markdown_files


class DocsCheckTests(unittest.TestCase):
    def check(self, source, target="# Hello world\n", extra_files=()):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'docs').mkdir()
            entry = root / 'README.md'
            entry.write_text(source)
            (root / 'docs' / 'guide.md').write_text(target)
            for path in extra_files:
                (root / path).write_bytes(b'fixture')
            return check_files(root, [entry])

    def test_relative_root_paths_images_references_and_encoded_headings(self):
        errors, count = self.check(
            '[Guide](docs/guide.md#hello-world)\n'
            '[Again](/docs/guide.md#hello-world-1)\n'
            '[中文](docs/guide.md#%E7%8A%B6%E6%80%81)\n'
            '![Image](<docs/a frame.png> "Frame")\n'
            '[Shared][guide]\n[guide]: docs/guide.md#explicit\n',
            target='# Hello world\n# Hello world\n## 状态\n<a id="explicit"></a>\n',
            extra_files=('docs/a frame.png',),
        )
        self.assertEqual(errors, [])
        self.assertEqual(count, 5)

    def test_missing_file_and_stale_heading_report_source_lines(self):
        errors, _ = self.check('[File](gone.md)\n[Heading](docs/guide.md#old)\n')
        self.assertEqual(len(errors), 2)
        self.assertIn('README.md:1: missing target', errors[0])
        self.assertIn('README.md:2: missing heading', errors[1])

    def test_unknown_reference_and_outside_repository_are_rejected(self):
        errors, _ = self.check('[Guide][gone]\n[Outside](../outside.md)\n')
        self.assertEqual(len(errors), 2)
        self.assertIn('undefined reference', errors[0])
        self.assertIn('leaves repository', errors[1])

    def test_git_discovery_includes_untracked_docs_and_ignores_raw_archives(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / '.gitignore').write_text('ignored/\n')
            (root / 'README.md').write_text('# Entry\n')
            subprocess.run(['git', '-C', str(root), 'add', 'README.md'], check=True)
            (root / 'new.md').write_text('[Bad](missing.md)\n')
            (root / 'ignored').mkdir()
            (root / 'ignored' / 'raw.md').write_text('[Bad](also-missing.md)\n')
            files = markdown_files(root)
            self.assertEqual([path.name for path in files], ['README.md', 'new.md'])
            errors, _ = check_files(root, files)
            self.assertEqual(len(errors), 1)
            self.assertIn('new.md:1:', errors[0])


if __name__ == '__main__':
    unittest.main()
