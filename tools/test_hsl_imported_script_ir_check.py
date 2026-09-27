from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import hsltools.checks.imported_script_ir as imported_script_ir


def valid_script(script_id: str = "story051") -> dict:
    section_name = "story" if script_id == "story051" else "event"
    action_name = "actMessage" if script_id == "story051" else "actCheckRoundNumber"
    source_id = "STORY051.TXT" if script_id == "story051" else "winfail051.txt"
    return {
        "schema": "hsl_chapter01_script_ir.v1",
        "id": script_id,
        "source_file": source_id,
        "source_id": source_id,
        "source_policy": "private remake imported script IR; preserves original script section order, action order, chain args, message ids, resource refs, and includes for Godot import",
        "evidence_tier": "resource-derived",
        "encoding": "cp950",
        "includes": ["common.h"],
        "resource_refs": ["WORD001"],
        "define_values": {},
        "section_counts": {section_name: 1},
        "action_counts": {action_name: 1},
        "action_line_count": 1,
        "action_chain_count": 1,
        "sections": [
            {
                "index": 0,
                "type": section_name,
                "name": section_name,
                "codes": ["0"],
                "messages": ["WORD001"],
                "message_ids": ["WORD001"],
                "actions": [
                    {
                        "index": 0,
                        "primary": action_name,
                        "name": action_name,
                        "chain": [{"name": action_name, "args": ["WORD001"]}],
                    }
                ],
            }
        ],
        "action_chain": [
            {
                "index": 0,
                "script_id": script_id,
                "source_file": source_id,
                "section_index": 0,
                "section_name": section_name,
                "section_type": section_name,
                "section_codes": ["0"],
                "action_index": 0,
                "chain_index": 0,
                "primary": action_name,
                "name": action_name,
                "args": ["WORD001"],
                "evidence_tier": "resource-derived",
                "unresolved_semantics": ["test fixture"],
            }
        ],
    }


def valid_index() -> dict:
    return {
        "schema": "hsl_chapter01_script_ir_index.v1",
        "source_policy": "private reverse-engineering script IR index; per-script files preserve original action order and args for Godot reimplementation",
        "evidence_tier": "resource-derived",
        "scripts": [
            {
                "id": "story051",
                "file": "scripts/story051.json",
                "path": "res://content/imported/hsl/chapter01/scripts/story051.json",
                "source_file": "STORY051.TXT",
                "source_id": "STORY051.TXT",
                "section_count": 1,
                "action_line_count": 1,
                "action_chain_count": 1,
                "evidence_tier": "resource-derived",
            },
            {
                "id": "winfail051",
                "file": "scripts/winfail051.json",
                "path": "res://content/imported/hsl/chapter01/scripts/winfail051.json",
                "source_file": "winfail051.txt",
                "source_id": "winfail051.txt",
                "section_count": 1,
                "action_line_count": 1,
                "action_chain_count": 1,
                "evidence_tier": "resource-derived",
            },
        ],
        "total_action_line_count": 2,
        "total_action_chain_count": 2,
    }


class ImportedScriptIrCheckTests(unittest.TestCase):
    def check(self, index_doc: dict, scripts: dict[str, dict] | None = None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts_dir = root / "scripts"
            scripts_dir.mkdir()
            script_docs = scripts or {
                "story051": valid_script("story051"),
                "winfail051": valid_script("winfail051"),
            }
            for script_id, doc in script_docs.items():
                (scripts_dir / f"{script_id}.json").write_text(json.dumps(doc), encoding="utf-8")
            path = root / "script_ir_index.json"
            path.write_text(json.dumps(index_doc), encoding="utf-8")
            return imported_script_ir.check_ir(path)

    def test_valid_ir_passes(self):
        self.assertEqual(self.check(valid_index()), [])

    def test_detects_missing_script(self):
        doc = valid_index()
        doc["scripts"].pop()

        errors = self.check(doc)

        self.assertTrue(any("missing scripts" in error for error in errors), errors)

    def test_detects_primary_chain_mismatch(self):
        script = valid_script("story051")
        script["sections"][0]["actions"][0]["primary"] = "actDelay"

        errors = self.check(valid_index(), {"story051": script, "winfail051": valid_script("winfail051")})

        self.assertTrue(any("primary must match" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
