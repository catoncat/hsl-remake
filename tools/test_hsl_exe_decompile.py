import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.hsl_exe_decompile import decompile


class DecompileTests(unittest.TestCase):
    def test_missing_plugin_is_not_promoted_as_c(self):
        diagnostic = subprocess.CompletedProcess([], 0, 'You need to install the plugin with r2pm -ci r2ghidra\n', '')
        with tempfile.TemporaryDirectory() as directory, patch('tools.hsl_exe_decompile.subprocess.run', return_value=diagnostic):
            with self.assertRaises(RuntimeError):
                decompile(Path('original.exe'), '0x4423c0', Path(directory), 'hsl01_core', 'pdg')
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_nonzero_partial_output_is_not_promoted(self):
        diagnostic = subprocess.CompletedProcess([], 1, 'incomplete output', 'analysis failed')
        with tempfile.TemporaryDirectory() as directory, patch('tools.hsl_exe_decompile.subprocess.run', return_value=diagnostic):
            with self.assertRaises(RuntimeError):
                decompile(Path('original.exe'), '0x4423c0', Path(directory), 'hsl01_core', 'pdg')
            self.assertEqual(list(Path(directory).iterdir()), [])
