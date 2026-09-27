"""Structural check of the imported chapter-one script IR (content/imported/hsl/chapter01/script_ir_index.json).

Registry task imported_script_ir_check (family checks, CheckTask). Bodies moved verbatim from the former hsl_imported_script_ir_check.py.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.registry import Context


EXPECTED_INDEX_SCHEMA = "hsl_chapter01_script_ir_index.v1"
EXPECTED_SCRIPT_SCHEMA = "hsl_chapter01_script_ir.v1"
EXPECTED_SCRIPTS = {"story051", "winfail051"}


def load_json(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"missing file: {path}"
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}"


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def check_action(action: Any, path: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(action, dict):
        return [f"{path} must be an object"]
    if not is_int(action.get("index")):
        errors.append(f"{path}.index must be an integer")
    primary = action.get("primary")
    if not isinstance(primary, str) or not primary:
        errors.append(f"{path}.primary must be a non-empty string")
    name = action.get("name")
    if name is not None and name != primary:
        errors.append(f"{path}.name must match primary")
    chain = action.get("chain")
    if not isinstance(chain, list) or not chain:
        errors.append(f"{path}.chain must be a non-empty list")
        return errors
    if isinstance(primary, str) and isinstance(chain[0], dict) and chain[0].get("name") != primary:
        errors.append(f"{path}.primary must match first chain action name")
    for index, item in enumerate(chain):
        item_path = f"{path}.chain[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{item_path} must be an object")
            continue
        if not isinstance(item.get("name"), str) or not item.get("name"):
            errors.append(f"{item_path}.name must be a non-empty string")
        if not isinstance(item.get("args"), list):
            errors.append(f"{item_path}.args must be a list")
        elif not all(isinstance(arg, str) for arg in item["args"]):
            errors.append(f"{item_path}.args must contain strings")
    return errors


def check_section(section: Any, path: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(section, dict):
        return [f"{path} must be an object"]
    if not is_int(section.get("index")):
        errors.append(f"{path}.index must be an integer")
    if not isinstance(section.get("name"), str) or not section.get("name"):
        errors.append(f"{path}.name must be a non-empty string")
    if not isinstance(section.get("type"), str) or not section.get("type"):
        errors.append(f"{path}.type must be a non-empty string")
    for key in ("codes", "messages"):
        values = section.get(key)
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            errors.append(f"{path}.{key} must be a list of strings")
    message_ids = section.get("message_ids")
    if message_ids is not None and (
        not isinstance(message_ids, list) or not all(isinstance(item, str) for item in message_ids)
    ):
        errors.append(f"{path}.message_ids must be a list of strings")
    actions = section.get("actions")
    if not isinstance(actions, list):
        errors.append(f"{path}.actions must be a list")
        return errors
    for index, action in enumerate(actions):
        errors.extend(check_action(action, f"{path}.actions[{index}]"))
    return errors


def section_action_chain_count(sections: Any) -> int:
    if not isinstance(sections, list):
        return 0
    return sum(
        len(action.get("chain", []))
        for section in sections
        if isinstance(section, dict) and isinstance(section.get("actions"), list)
        for action in section.get("actions", [])
        if isinstance(action, dict) and isinstance(action.get("chain"), list)
    )


def section_action_line_count(sections: Any) -> int:
    if not isinstance(sections, list):
        return 0
    return sum(
        len(section.get("actions", []))
        for section in sections
        if isinstance(section, dict) and isinstance(section.get("actions"), list)
    )


def check_flat_action(action: Any, path: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(action, dict):
        return [f"{path} must be an object"]
    for key in ("index", "section_index", "action_index", "chain_index"):
        if not is_int(action.get(key)):
            errors.append(f"{path}.{key} must be an integer")
    for key in ("script_id", "source_file", "section_name", "primary", "name", "evidence_tier"):
        if not isinstance(action.get(key), str) or not action.get(key):
            errors.append(f"{path}.{key} must be a non-empty string")
    if action.get("evidence_tier") != "resource-derived":
        errors.append(f"{path}.evidence_tier mismatch: {action.get('evidence_tier')!r}")
    args = action.get("args")
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        errors.append(f"{path}.args must be a list of strings")
    unresolved = action.get("unresolved_semantics")
    if not isinstance(unresolved, list) or not all(isinstance(item, str) for item in unresolved):
        errors.append(f"{path}.unresolved_semantics must be a list of strings")
    return errors


def check_script(script: Any, path: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(script, dict):
        return [f"{path} must be an object"]
    if script.get("schema") != EXPECTED_SCRIPT_SCHEMA:
        errors.append(f"{path}.schema mismatch: expected {EXPECTED_SCRIPT_SCHEMA}, got {script.get('schema')!r}")
    if script.get("evidence_tier") != "resource-derived":
        errors.append(f"{path}.evidence_tier mismatch: {script.get('evidence_tier')!r}")
    policy = script.get("source_policy")
    if (
        not isinstance(policy, str)
        or "action order" not in policy
        or "args" not in policy
        or "message ids" not in policy
    ):
        errors.append(f"{path}.source_policy must describe preserved action order, args, and message ids")
    script_id = script.get("id")
    if not isinstance(script_id, str) or not script_id:
        errors.append(f"{path}.id must be a non-empty string")
    if not isinstance(script.get("source_id"), str) or not script.get("source_id"):
        errors.append(f"{path}.source_id must be a non-empty string")
    if "/" in str(script.get("source_id", "")) or "\\" in str(script.get("source_id", "")):
        errors.append(f"{path}.source_id must be a basename")
    if not isinstance(script.get("source_file"), str) or not script.get("source_file"):
        errors.append(f"{path}.source_file must be a non-empty string")
    if not isinstance(script.get("section_counts"), dict):
        errors.append(f"{path}.section_counts must be an object")
    if not isinstance(script.get("action_counts"), dict):
        errors.append(f"{path}.action_counts must be an object")
    for key in ("includes", "resource_refs"):
        values = script.get(key)
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            errors.append(f"{path}.{key} must be a list of strings")
    sections = script.get("sections")
    if not isinstance(sections, list):
        errors.append(f"{path}.sections must be a list")
        return errors
    for index, section in enumerate(sections):
        errors.extend(check_section(section, f"{path}.sections[{index}]"))
    action_total = section_action_chain_count(sections)
    action_line_total = section_action_line_count(sections)
    if script.get("action_chain_count") != action_total:
        errors.append(f"{path}.action_chain_count {script.get('action_chain_count')!r} != {action_total}")
    if script.get("action_line_count") != action_line_total:
        errors.append(f"{path}.action_line_count {script.get('action_line_count')!r} != {action_line_total}")
    flat_actions = script.get("action_chain")
    if not isinstance(flat_actions, list):
        errors.append(f"{path}.action_chain must be a list")
    else:
        if len(flat_actions) != action_total:
            errors.append(f"{path}.action_chain length {len(flat_actions)} != {action_total}")
        for index, action in enumerate(flat_actions):
            errors.extend(check_flat_action(action, f"{path}.action_chain[{index}]"))
            if isinstance(action, dict) and action.get("index") != index:
                errors.append(f"{path}.action_chain[{index}].index must match list order")
    counted_total = sum(value for value in script.get("action_counts", {}).values() if is_int(value))
    if counted_total and action_total != counted_total:
        errors.append(f"{path}.actions total {action_total} != action_counts total {counted_total}")
    return errors


def check_ir(path: Path | str) -> list[str]:
    path = Path(path)
    doc, error = load_json(path)
    if error:
        return [error]
    if not isinstance(doc, dict):
        return ["script IR root must be an object"]
    errors: list[str] = []
    if doc.get("schema") != EXPECTED_INDEX_SCHEMA:
        errors.append(f"schema mismatch: expected {EXPECTED_INDEX_SCHEMA}, got {doc.get('schema')!r}")
    if doc.get("evidence_tier") != "resource-derived":
        errors.append(f"evidence_tier mismatch: {doc.get('evidence_tier')!r}")
    policy = doc.get("source_policy")
    if not isinstance(policy, str) or "action order" not in policy or "args" not in policy:
        errors.append("source_policy must describe preserved action order and args")
    script_entries = doc.get("scripts")
    if not isinstance(script_entries, list):
        return errors + ["scripts must be a list"]
    ids = set()
    for index, entry in enumerate(script_entries):
        entry_path = f"scripts[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{entry_path} must be an object")
            continue
        script_id = entry.get("id")
        if isinstance(script_id, str):
            ids.add(script_id)
        file_name = entry.get("file")
        if (
            not isinstance(file_name, str)
            or "/" not in file_name
            or Path(file_name).is_absolute()
            or ".." in Path(file_name).parts
        ):
            errors.append(f"{entry_path}.file must point at a script JSON")
            continue
        res_path = entry.get("path")
        if not isinstance(res_path, str) or not res_path.endswith(file_name):
            errors.append(f"{entry_path}.path must be a res:// path ending in {file_name}")
        script_path = path.parent / file_name
        script, load_error = load_json(script_path)
        if load_error:
            errors.append(load_error)
            continue
        errors.extend(check_script(script, file_name))
        if isinstance(script, dict) and script.get("id") != script_id:
            errors.append(f"{entry_path}.id does not match {file_name}.id")
        if isinstance(script, dict) and entry.get("source_id") != script.get("source_id"):
            errors.append(f"{entry_path}.source_id does not match {file_name}.source_id")
        if isinstance(script, dict):
            sections = script.get("sections", [])
            if entry.get("section_count") != len(sections):
                errors.append(f"{entry_path}.section_count {entry.get('section_count')!r} != {len(sections)}")
            line_count = section_action_line_count(sections)
            chain_count = section_action_chain_count(sections)
            if entry.get("action_line_count") != line_count:
                errors.append(f"{entry_path}.action_line_count {entry.get('action_line_count')!r} != {line_count}")
            if entry.get("action_chain_count") != chain_count:
                errors.append(f"{entry_path}.action_chain_count {entry.get('action_chain_count')!r} != {chain_count}")
            if entry.get("evidence_tier") != script.get("evidence_tier"):
                errors.append(f"{entry_path}.evidence_tier does not match {file_name}.evidence_tier")
    missing = EXPECTED_SCRIPTS - ids
    if missing:
        errors.append(f"missing scripts: {sorted(missing)}")
    total_line_count = sum(
        entry.get("action_line_count", 0)
        for entry in script_entries
        if isinstance(entry, dict) and is_int(entry.get("action_line_count"))
    )
    total_chain_count = sum(
        entry.get("action_chain_count", 0)
        for entry in script_entries
        if isinstance(entry, dict) and is_int(entry.get("action_chain_count"))
    )
    if doc.get("total_action_line_count") != total_line_count:
        errors.append(f"total_action_line_count {doc.get('total_action_line_count')!r} != {total_line_count}")
    if doc.get("total_action_chain_count") != total_chain_count:
        errors.append(f"total_action_chain_count {doc.get('total_action_chain_count')!r} != {total_chain_count}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate imported HSL chapter-one script IR.")
    parser.add_argument("script_ir", type=Path)
    args = parser.parse_args(argv)
    errors = check_ir(args.script_ir)
    if errors:
        print(f"FAIL hsl imported script IR ({len(errors)} error(s))")
        for error in errors:
            print(f"- {error}")
        return 1
    print("PASS hsl imported script IR")
    return 0


class ImportedScriptIrCheckTask(CheckTask):
    name = 'imported_script_ir_check'
    family = 'checks'
    inputs = ('content/imported/hsl/chapter01/script_ir_index.json', 'content/imported/hsl/chapter01/scripts/')
    replaces = ('tools/hsl_imported_script_ir_check.py content/imported/hsl/chapter01/script_ir_index.json',)
    scripts = ('tools/hsltools/checks/imported_script_ir.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, ['content/imported/hsl/chapter01/script_ir_index.json'])


def tasks() -> list[ImportedScriptIrCheckTask]:
    return [ImportedScriptIrCheckTask()]


if __name__ == '__main__':
    raise SystemExit(main())
