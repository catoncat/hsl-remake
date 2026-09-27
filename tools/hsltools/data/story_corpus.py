"""Promote every original story script into one reproducible dialogue/action corpus.

Reads the original PAK (read-only, outside the repository) and compresses all
narrative scripts into tracked imported data:

  * DATA\\STORYnnn.TXT   (family "story")      opening / cutscene scripts
  * DATA\\winfailnnn.txt (family "winfail")    win / fail / event condition scripts
  * DATA\\STORYOVER.TXT  (family "storyover")  the ending script
  * DATA\\TOWNDEF.TXT    (family "towndef")    town event table (te* commands)

Message text comes from the [name] section of DATA\\RESOURCE.TXT
(hsltools.sources.tables.parse_table); speaker slot symbols come from
DATA\\EXTRAS.H (SID_* defines). Script parsing is the existing chain
hsltools.sources.scripts.parse_text_metadata -> hsltools.levels.seed._compact_script;
message-id extraction follows hsltools.levels.message_text (MESSAGE_ACTIONS /
ALTERNATE_MESSAGE_ACTIONS, case-insensitive token spelling) and TOWNDEF parsing is
tools.hsl_world_map.parse_towndef with its te message-argument positions. Token
coverage is measured against tools.hsl_opening_timeline_compile.ACTION_KIND.

Outputs (content/imported/hsl/story_corpus/):
  index.json                 hsl_story_corpus.v1 -- one row per script + totals
  scripts/<FAMILY><nnn>.json hsl_story_corpus_script.v1 -- compact actions + messages

--check rebuilds the corpus in memory and compares it byte-for-byte with the
tracked files (when the PAK is present; otherwise an offline consistency check),
and always compares the corpus text with every tracked message_text_evidence.json.

Claim limits: the corpus restores message text and action order only. Timing,
branch conditions (actCheck*/teCheck*), camera, handler side effects and speaker
labels for unnamed actors are not proven by this data.

Registry task story_corpus (family static, OriginalArchiveTask): tracked output content/imported/hsl/story_corpus/;
check rebuilds in memory when hsl.pak is present (offline consistency otherwise) and compares with the tracked corpus
and message evidence, generate rewrites the corpus from hsl.pak. Bodies moved verbatim from the former hsl_story_corpus.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from hsltools.levels.message_text import (
    ALTERNATE_MESSAGE_ACTIONS,
    MESSAGE_ACTIONS,
    SPEAKER_IDS,
    _MESSAGE_ACTIONS_LOWER,
    seed_message_ids,
)
from hsltools.levels.seed import _compact_script
from hsltools.levels.timeline import ACTION_KIND, canonical_action_name
from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.data.big_map_flow import resolve as resolve_symbol, symbols as flow_symbols
from hsltools.data.world_map import MESSAGE_ARG_POSITIONS, SELECT_INSERT_TOKEN, SHAPE_NAME_ARG_POSITIONS, parse_towndef
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import Context
from hsltools.sources.scripts import parse_text_metadata
from hsltools.sources.tables import parse_table

DEFAULT_PAK = ORIGINAL_PAK
OUTPUT_DIR = ROOT / "content/imported/hsl/story_corpus"
INDEX_NAME = "index.json"
SCRIPTS_DIR = "scripts"
INDEX_SCHEMA = "hsl_story_corpus.v1"
SCRIPT_SCHEMA = "hsl_story_corpus_script.v1"
EVIDENCE_TIER = "resource-derived"

RESOURCE_MEMBER = "@:\\data\\RESOURCE.TXT"
EXTRAS_MEMBER = "@:\\data\\EXTRAS.H"
STORYOVER_MEMBER = "@:\\data\\STORYOVER.TXT"
TOWNDEF_MEMBER = "@:\\data\\TOWNDEF.TXT"
NUMBERED_RE = re.compile(r"^@:\\data\\(story|winfail)(\d+)\.txt$", re.IGNORECASE)
FAMILIES = ("story", "winfail", "storyover", "towndef")
# STORY numbers are grouped by hundreds (1-99 main line, 5xx encounters, 9xx endings);
# gaps are listed inside each block between its lowest and highest number.
NUMBER_BLOCK = 100
NEXT_LEVEL_ACTIONS = {"actsetnextplaylevelevent": "actSetNextPlayLevelEvent", "tesetnextplaylevelevent": "teSetNextPlayLevelEvent"}
NARRATION_TOKEN = "defNoOne"
TOWN_PLAYER_MESSAGE_TOKENS = {"tePlayerMessage", SELECT_INSERT_TOKEN}
# Tracked message evidence files whose text must match the corpus word for word.
EVIDENCE_GLOBS = ("content/imported/hsl/chapter01/message_text_evidence.json", "content/imported/hsl/chapter01/*/message_text_evidence.json")
EVIDENCE_ROOT_LEVEL = 51

# Claim-limit ids; the text of each boundary and its evidence tier live in the packet's
# "Claim limits" table (same order). index.json records the ids and the packet path.
CLAIM_LIMITS_PACKET = "docs/evidence_packets/resource_inventory/original_story_corpus.md"
CLAIM_LIMIT_IDS = [
    "text_and_action_order_only",
    "tokens_not_engine_semantics",
    "speaker_name_from_speaker_ids_tables",
    "numbers_are_resource_naming",
]


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _dumps(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def _int_or_none(value: str) -> int | None:
    try:
        return int(str(value).strip(), 10)
    except ValueError:
        return None


def _source(member: str, data: bytes) -> dict[str, Any]:
    return {"member": member, "byte_length": len(data), "sha256": _sha(data), "evidence_tier": EVIDENCE_TIER}


def script_file_name(family: str, number: int | None) -> str:
    if number is None:
        return f"{family.upper()}.json"
    return f"{family.upper()}{number:03d}.json"


# --------------------------------------------------------------------------- act scripts

def _message_entry(order: int, section: dict[str, Any], action_index: int, chain_index: int, command_name: str,
                   message_id: str, sid_token: str | None, table: dict[str, str], speakers: dict[str, str] | None,
                   **extra: Any) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "order": order,
        "section_index": int(section.get("index", 0)),
        "section": str(section.get("name", "")),
        "action_index": action_index,
        "chain_index": chain_index,
        "command": command_name,
        "id": message_id,
        "sid_token": sid_token,
    }
    entry.update(extra)
    if sid_token is not None:
        entry["narration"] = sid_token == NARRATION_TOKEN
        if speakers is not None and sid_token in speakers and speakers[sid_token] in table:
            entry["speaker_name"] = table[speakers[sid_token]]
    entry["text"] = table.get(message_id)
    return entry


def script_messages(compact: dict[str, Any], table: dict[str, str], speakers: dict[str, str] | None) -> list[dict[str, Any]]:
    """Every message reference of a compact STORY/WINFAIL script in source order:
    'message =' board labels, actMessage/actSetDeadMessage/actShapeMessage ids and the
    actMessageIfExist true/false pair (0 = no alternate)."""
    result: list[dict[str, Any]] = []
    for section in compact.get("sections", []):
        for line in section.get("messages", []):
            parts = [part.strip() for part in str(line).split(",")]
            if len(parts) >= 2 and parts[1].isdigit():
                result.append(_message_entry(len(result), section, -1, -1, "message", parts[1], parts[0], table, speakers, board_label=True))
        for action_index, action in enumerate(section.get("actions", [])):
            for chain_index, command in enumerate(action.get("chain", [])):
                raw_name = str(command.get("name", ""))
                if raw_name == "actSelectInsertEvent":
                    # [id][serial][num]([choice message id][event code]) * num: the choice labels
                    # are messages spoken as the player's options.
                    select_args = [str(arg) for arg in command.get("args", [])]
                    count = int(select_args[2]) if len(select_args) > 2 and select_args[2].isdigit() else 0
                    for k in range(count):
                        position = 3 + 2 * k
                        if len(select_args) > position and select_args[position].isdigit():
                            result.append(_message_entry(len(result), section, action_index, chain_index, raw_name, select_args[position], select_args[0], table, speakers,
                                                         select_event=select_args[position + 1] if len(select_args) > position + 1 else None))
                    continue
                name = _MESSAGE_ACTIONS_LOWER.get(raw_name.lower())
                if name not in MESSAGE_ACTIONS:
                    continue
                args = [str(arg) for arg in command.get("args", [])]
                if len(args) < 3 or not args[2].isdigit():
                    continue
                if name == "actShapeMessage":
                    # [shape file][name id][message id]: the speaker is named by resource id.
                    extra: dict[str, Any] = {"speaker_shape": args[0], "speaker_name_id": args[1]}
                    if args[1].isdigit() and args[1] in table:
                        extra["speaker_name"] = table[args[1]]
                    result.append(_message_entry(len(result), section, action_index, chain_index, name, args[2], None, table, speakers, **extra))
                    continue
                result.append(_message_entry(len(result), section, action_index, chain_index, name, args[2], args[0], table, speakers))
                if name in ALTERNATE_MESSAGE_ACTIONS and len(args) >= 4 and args[3].isdigit() and int(args[3]) > 0:
                    result.append(_message_entry(len(result), section, action_index, chain_index, name, args[3], args[0], table, speakers, alternate_of=args[2]))
    return result


def _next_level_events(compact: dict[str, Any], table: dict[str, int]) -> list[dict[str, Any]]:
    edges: list[dict[str, Any]] = []
    for section in compact.get("sections", []):
        for action in section.get("actions", []):
            for command in action.get("chain", []):
                canonical = NEXT_LEVEL_ACTIONS.get(str(command.get("name", "")).lower())
                if canonical is None:
                    continue
                args = [str(arg) for arg in command.get("args", [])]
                edges.append(_edge(str(section.get("name", "")), canonical, args, table))
    return edges


def _edge(section: str, command: str, args: list[str], table: dict[str, int]) -> dict[str, Any]:
    level = resolve_symbol(args[0], table) if args else None
    event = resolve_symbol(args[1], table) if len(args) > 1 else None
    return {"section": section, "command": command, "args": args, "level": level, "event": event,
            "event_symbol": args[1] if len(args) > 1 else None, "to_big_map": event == table["gameBigMapLevel"]}


def _token_coverage(action_counts: dict[str, int]) -> tuple[dict[str, int], list[str]]:
    canonical_counts: dict[str, int] = {}
    for name, count in action_counts.items():
        canonical = canonical_action_name(str(name))
        canonical_counts[canonical] = canonical_counts.get(canonical, 0) + int(count)
    unmapped = sorted(name for name in canonical_counts if name not in ACTION_KIND)
    return dict(sorted(canonical_counts.items())), unmapped


def _sid_tokens(compact: dict[str, Any]) -> list[str]:
    tokens: set[str] = set()
    for section in compact.get("sections", []):
        for line in section.get("messages", []):
            first = str(line).split(",")[0].strip()
            if first.startswith("SID_"):
                tokens.add(first)
        for action in section.get("actions", []):
            for command in action.get("chain", []):
                tokens.update(str(arg) for arg in command.get("args", []) if str(arg).startswith("SID_"))
    return sorted(tokens)


def build_act_script(family: str, number: int | None, member: str, data: bytes, table: dict[str, str],
                     flow_table: dict[str, int]) -> dict[str, Any]:
    metadata = parse_text_metadata(data)
    compact = _compact_script(metadata)
    speakers = SPEAKER_IDS.get(number) if number is not None else None
    messages = script_messages(compact, table, speakers)
    # The dedicated seed reader must agree with the per-message walk (shared oracle).
    oracle: list[str] = []
    for ids in seed_message_ids({"scripts": {"story": compact}}).values():
        oracle.extend(ids)
    distinct = list(dict.fromkeys(entry["id"] for entry in messages))
    if sorted(distinct, key=int) != sorted(set(oracle), key=int):
        raise ValueError(f"{member}: message-id walk disagrees with hsltools.levels.message_text.seed_message_ids")
    canonical_counts, unmapped = _token_coverage(compact.get("action_counts", {}))
    sid_tokens = _sid_tokens(compact)
    return {
        "schema": SCRIPT_SCHEMA,
        "family": family,
        "number": number,
        "source": _source(member, data),
        "encoding": compact.get("encoding"),
        "line_count": compact.get("line_count"),
        "includes": compact.get("includes", []),
        "section_counts": compact.get("section_counts", {}),
        "action_counts": canonical_counts,
        "unmapped_action_tokens": unmapped,
        # The source label is tracked corpus bytes; the table now lives in hsltools.levels.message_text.SPEAKER_IDS
        # (the former script), and the label changes with the next intentional corpus regeneration.
        "speaker_table": {"source": "tools/hsl_chapter_dialogue.SPEAKER_IDS", "level": number, "tokens": dict(speakers)} if speakers else None,
        "sid_tokens": sid_tokens,
        "next_level_events": _next_level_events(compact, flow_table),
        "message_ids": distinct,
        "missing_text_ids": [message_id for message_id in distinct if message_id not in table],
        "messages": messages,
        "sections": compact.get("sections", []),
    }


# --------------------------------------------------------------------------- TOWNDEF

def town_messages(parsed: dict[str, Any], table: dict[str, str]) -> list[dict[str, Any]]:
    """te message references in TOWNDEF order: tePlayerMessage [SID][id], teShapeMessage
    [shape][name id][id], teCheckMoney / teCheckJobUp* / teSecretManBuyThing ids and every
    teSelectInsertEvent choice label; show_name ids are menu labels, not messages."""
    result: list[dict[str, Any]] = []
    for record in parsed.get("town_events", []):
        for event_index, command in enumerate(record.get("events", [])):
            token = str(command.get("token", ""))
            args = [str(arg) for arg in command.get("args", [])]
            positions = list(range(2, len(args), 2)) if token == SELECT_INSERT_TOKEN else MESSAGE_ARG_POSITIONS.get(token, [])
            for position in positions:
                if position >= len(args) or not args[position].isdigit() or int(args[position]) <= 0:
                    continue
                entry: dict[str, Any] = {
                    "order": len(result),
                    "town_event_code": record.get("code"),
                    "event_index": event_index,
                    "command": token,
                    "id": args[position],
                    "sid_token": args[0] if token in TOWN_PLAYER_MESSAGE_TOKENS and args and args[0].startswith("SID_") else None,
                }
                if token == SELECT_INSERT_TOKEN:
                    entry["choice_index"] = (position - 2) // 2
                    entry["choice_event"] = args[position + 1] if position + 1 < len(args) else None
                name_position = SHAPE_NAME_ARG_POSITIONS.get(token)
                if name_position is not None and name_position < len(args):
                    entry["speaker_shape"] = args[name_position - 1] if name_position >= 1 else None
                    entry["speaker_name_id"] = args[name_position]
                    if args[name_position].isdigit() and args[name_position] in table:
                        entry["speaker_name"] = table[args[name_position]]
                entry["text"] = table.get(args[position])
                result.append(entry)
    return result


def build_towndef(member: str, data: bytes, table: dict[str, str], flow_table: dict[str, int]) -> dict[str, Any]:
    parsed = parse_towndef(data.decode("cp950"))
    messages = town_messages(parsed, table)
    distinct = list(dict.fromkeys(entry["id"] for entry in messages))
    token_counts: dict[str, int] = {}
    edges: list[dict[str, Any]] = []
    sid_tokens: set[str] = set()
    events: list[dict[str, Any]] = []
    for record in parsed.get("town_events", []):
        show = record.get("show_name") or {}
        show_id = str(show.get("resource_id")) if isinstance(show, dict) and show.get("resource_id") is not None else None
        events.append({
            "code": record.get("code"),
            "comment": record.get("comment"),
            "show_name_id": show_id,
            "show_name": table.get(show_id) if show_id else None,
            "item_code": record.get("item_code"),
            "events": [{"token": str(c.get("token", "")), "args": [str(a) for a in c.get("args", [])]} for c in record.get("events", [])],
        })
        for command in record.get("events", []):
            token = str(command.get("token", ""))
            args = [str(arg) for arg in command.get("args", [])]
            token_counts[token] = token_counts.get(token, 0) + 1
            sid_tokens.update(arg for arg in args if arg.startswith("SID_"))
            canonical = NEXT_LEVEL_ACTIONS.get(token.lower())
            if canonical is not None:
                edges.append(_edge(f"town_event {record.get('code')}", canonical, args, flow_table))
    return {
        "schema": SCRIPT_SCHEMA,
        "family": "towndef",
        "number": None,
        "source": _source(member, data),
        "encoding": "cp950",
        "line_count": len(data.decode("cp950").splitlines()),
        "includes": parsed.get("includes", []),
        "section_counts": {"item": len(parsed.get("items", [])), "town_event": len(parsed.get("town_events", []))},
        "action_counts": dict(sorted(token_counts.items())),
        "unmapped_action_tokens": [],
        "action_token_note": "te* tokens belong to the town interpreter (game/sim/TownEventRules.gd); ACTION_KIND coverage applies to act* tokens only",
        "speaker_table": None,
        "sid_tokens": sorted(sid_tokens),
        "next_level_events": edges,
        "message_ids": distinct,
        "missing_text_ids": [message_id for message_id in distinct if message_id not in table],
        "messages": messages,
        "town_events": events,
    }


# --------------------------------------------------------------------------- corpus

def _index_row(script: dict[str, Any], file_name: str, file_sha: str) -> dict[str, Any]:
    return {
        "family": script["family"],
        "number": script["number"],
        "member": script["source"]["member"],
        "byte_length": script["source"]["byte_length"],
        "sha256": script["source"]["sha256"],
        "script_file": f"{SCRIPTS_DIR}/{file_name}",
        "script_file_sha256": file_sha,
        "line_count": script["line_count"],
        "section_counts": script["section_counts"],
        "action_counts": script["action_counts"],
        "message_reference_count": len(script["messages"]),
        "message_id_count": len(script["message_ids"]),
        "resolved_text_count": len(script["message_ids"]) - len(script["missing_text_ids"]),
        "missing_text_ids": script["missing_text_ids"],
        "speaker_table_level": (script.get("speaker_table") or {}).get("level"),
        "sid_tokens": script["sid_tokens"],
        "next_level_events": script["next_level_events"],
        "unmapped_action_tokens": script["unmapped_action_tokens"],
    }


def _number_gaps(numbers: list[int]) -> list[int]:
    gaps: list[int] = []
    blocks: dict[int, list[int]] = {}
    for number in numbers:
        blocks.setdefault(number // NUMBER_BLOCK, []).append(number)
    for block in sorted(blocks):
        present = set(blocks[block])
        gaps.extend(n for n in range(min(present), max(present) + 1) if n not in present)
    return gaps


def build_corpus(scripts: list[dict[str, Any]], sources: dict[str, dict[str, Any]], extras: dict[str, int]) -> dict[str, str]:
    """Return {relative path: file text} for the index and every per-script file."""
    files: dict[str, str] = {}
    rows: list[dict[str, Any]] = []
    order = {family: index for index, family in enumerate(FAMILIES)}
    for script in sorted(scripts, key=lambda s: (order[s["family"]], s["number"] if s["number"] is not None else -1)):
        name = script_file_name(script["family"], script["number"])
        text = _dumps(script)
        files[f"{SCRIPTS_DIR}/{name}"] = text
        rows.append(_index_row(script, name, _sha(text.encode("utf-8"))))
    families: dict[str, dict[str, Any]] = {}
    all_ids: set[str] = set()
    missing_ids: set[str] = set()
    unmapped_usage: dict[str, dict[str, Any]] = {}
    for row in rows:
        family = families.setdefault(row["family"], {"script_count": 0, "message_reference_count": 0, "message_id_count": 0, "distinct_message_ids": set(), "missing_text_ids": set(), "section_count": 0})
        family["script_count"] += 1
        family["message_reference_count"] += row["message_reference_count"]
        family["message_id_count"] += row["message_id_count"]
        family["section_count"] += sum(int(v) for v in row["section_counts"].values())
        script = next(s for s in scripts if s["source"]["member"] == row["member"])
        family["distinct_message_ids"].update(script["message_ids"])
        family["missing_text_ids"].update(row["missing_text_ids"])
        all_ids.update(script["message_ids"])
        missing_ids.update(row["missing_text_ids"])
        for token in row["unmapped_action_tokens"]:
            usage = unmapped_usage.setdefault(token, {"scripts": 0, "occurrences": 0})
            usage["scripts"] += 1
            usage["occurrences"] += int(row["action_counts"].get(token, 0))
    for family in families.values():
        family["distinct_message_id_count"] = len(family.pop("distinct_message_ids"))
        family["missing_text_ids"] = sorted(family["missing_text_ids"], key=int)
    story_numbers = sorted(row["number"] for row in rows if row["family"] == "story")
    winfail_numbers = sorted(row["number"] for row in rows if row["family"] == "winfail")
    index = {
        "schema": INDEX_SCHEMA,
        "evidence_tier": EVIDENCE_TIER,
        "source_policy": "Compact script structure and RESOURCE.TXT [name] text only; raw PAK records stay outside the repository.",
        "sources": sources,
        "extras_sid_defines": {token: extras[token] for token in sorted(extras, key=lambda t: extras[t])},
        "coverage_table": "tools/hsl_opening_timeline_compile.ACTION_KIND (imported; actCheck*/actTRUE/actFALSE belong to the winfail interpreter)",
        "next_level_symbols": {"gameBigMapLevel": flow_symbols()["gameBigMapLevel"]},
        "summary": {
            "script_count": len(rows),
            "families": {family: families[family] for family in FAMILIES if family in families},
            "distinct_message_id_count": len(all_ids),
            "missing_text_id_count": len(missing_ids),
            "missing_text_ids": sorted(missing_ids, key=int),
            "story_numbers": story_numbers,
            "story_number_gaps": _number_gaps(story_numbers),
            "winfail_numbers": winfail_numbers,
            "story_without_winfail": [n for n in story_numbers if n not in set(winfail_numbers)],
            "winfail_without_story": [n for n in winfail_numbers if n not in set(story_numbers)],
            "next_level_event_count": sum(len(row["next_level_events"]) for row in rows),
            "to_big_map_count": sum(1 for row in rows for edge in row["next_level_events"] if edge["to_big_map"]),
            "unmapped_action_tokens": dict(sorted(unmapped_usage.items(), key=lambda kv: (-kv[1]["scripts"], kv[0]))),
        },
        "scripts": rows,
        "claim_limits": CLAIM_LIMIT_IDS,
        "claim_limits_packet": CLAIM_LIMITS_PACKET,
    }
    files[INDEX_NAME] = _dumps(index)
    return files


# --------------------------------------------------------------------------- PAK access

def _read_member(packages: list[dict[str, Any]], member: str) -> bytes:
    from hsltools.sources.pak import find_paks_record_by_name, read_paks_record_bytes
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p["records"], member))]
    if len(matches) != 1:
        raise ValueError(f"missing or ambiguous PAK member: {member}")
    package, record = matches[0]
    return read_paks_record_bytes(package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"]))


def build_from_pak(pak: Path) -> dict[str, str]:
    from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes
    packages = find_decoded_paks_packages(pak)
    if not packages:
        raise ValueError(f"no PAKS container found at {pak}")
    resource = _read_member(packages, RESOURCE_MEMBER)
    extras_data = _read_member(packages, EXTRAS_MEMBER)
    table = parse_table(resource)
    extras = {name: value for name, value in ((str(k), _int_or_none(v)) for k, v in parse_text_metadata(extras_data).get("define_values", {}).items())
              if name.startswith("SID_") and value is not None}
    flow_table = flow_symbols()
    scripts: list[dict[str, Any]] = []
    for package in packages:
        for record in package["records"]:
            member = str(record["name"])
            match = NUMBERED_RE.match(member)
            if match is None:
                continue
            data = read_paks_record_bytes(package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"]))
            scripts.append(build_act_script(match.group(1).lower(), int(match.group(2)), member, data, table, flow_table))
    storyover = _read_member(packages, STORYOVER_MEMBER)
    scripts.append(build_act_script("storyover", None, STORYOVER_MEMBER, storyover, table, flow_table))
    towndef = _read_member(packages, TOWNDEF_MEMBER)
    scripts.append(build_towndef(TOWNDEF_MEMBER, towndef, table, flow_table))
    sources = {
        "resource_table": {**_source(RESOURCE_MEMBER, resource), "section": "[name]", "encoding": "cp950", "name_count": len(table)},
        "extras_header": _source(EXTRAS_MEMBER, extras_data),
    }
    return build_corpus(scripts, sources, extras)


def write_files(files: dict[str, str], output_dir: Path) -> None:
    (output_dir / SCRIPTS_DIR).mkdir(parents=True, exist_ok=True)
    for stale in (output_dir / SCRIPTS_DIR).glob("*.json"):
        if f"{SCRIPTS_DIR}/{stale.name}" not in files:
            stale.unlink()
    for relative, text in files.items():
        (output_dir / relative).write_text(text, encoding="utf-8")


# --------------------------------------------------------------------------- checks

def load_index(output_dir: Path) -> dict[str, Any]:
    return json.loads((output_dir / INDEX_NAME).read_text(encoding="utf-8"))


def compare_with_tracked(files: dict[str, str], output_dir: Path) -> list[str]:
    errors: list[str] = []
    for relative, text in files.items():
        path = output_dir / relative
        if not path.is_file():
            errors.append(f"missing tracked file {relative}")
        elif path.read_bytes() != text.encode("utf-8"):
            errors.append(f"tracked file differs from rebuild: {relative}")
    tracked = {f"{SCRIPTS_DIR}/{p.name}" for p in (output_dir / SCRIPTS_DIR).glob("*.json")}
    for extra in sorted(tracked - set(files)):
        errors.append(f"stale tracked script file {extra}")
    return errors


def check_offline(output_dir: Path) -> list[str]:
    """Consistency of the tracked corpus without the PAK."""
    errors: list[str] = []
    index = load_index(output_dir)
    if index.get("schema") != INDEX_SCHEMA:
        errors.append(f"index schema {index.get('schema')!r} != {INDEX_SCHEMA}")
        return errors
    rows = index.get("scripts", [])
    summary = index.get("summary", {})
    if summary.get("script_count") != len(rows):
        errors.append("summary.script_count differs from the script rows")
    tracked = {f"{SCRIPTS_DIR}/{p.name}" for p in (output_dir / SCRIPTS_DIR).glob("*.json")}
    listed = {row["script_file"] for row in rows}
    for extra in sorted(tracked - listed):
        errors.append(f"script file not listed in the index: {extra}")
    all_ids: set[str] = set()
    families: dict[str, int] = {}
    for row in rows:
        path = output_dir / row["script_file"]
        if not path.is_file():
            errors.append(f"missing script file {row['script_file']}")
            continue
        text = path.read_text(encoding="utf-8")
        if _sha(text.encode("utf-8")) != row["script_file_sha256"]:
            errors.append(f"script file digest differs from the index: {row['script_file']}")
            continue
        script = json.loads(text)
        families[row["family"]] = families.get(row["family"], 0) + 1
        if script.get("schema") != SCRIPT_SCHEMA or script.get("family") != row["family"] or script.get("number") != row["number"]:
            errors.append(f"script header differs from the index: {row['script_file']}")
        if script["source"]["sha256"] != row["sha256"] or script["source"]["member"] != row["member"]:
            errors.append(f"script source differs from the index: {row['script_file']}")
        ids = list(dict.fromkeys(entry["id"] for entry in script["messages"]))
        if ids != script["message_ids"] or len(ids) != row["message_id_count"] or len(script["messages"]) != row["message_reference_count"]:
            errors.append(f"message counts differ from the messages list: {row['script_file']}")
        missing = [message_id for message_id in ids if all(entry["text"] is None for entry in script["messages"] if entry["id"] == message_id)]
        if missing != script["missing_text_ids"] or missing != row["missing_text_ids"]:
            errors.append(f"missing_text_ids differ from the messages list: {row['script_file']}")
        if row["resolved_text_count"] != len(ids) - len(missing):
            errors.append(f"resolved_text_count is stale: {row['script_file']}")
        if row["family"] != "towndef":
            _, unmapped = _token_coverage(script["action_counts"])
            if unmapped != row["unmapped_action_tokens"] or unmapped != script["unmapped_action_tokens"]:
                errors.append(f"unmapped_action_tokens are stale against ACTION_KIND: {row['script_file']}")
        all_ids.update(ids)
    for family, stats in summary.get("families", {}).items():
        if stats.get("script_count") != families.get(family):
            errors.append(f"family {family} script_count is stale")
    if summary.get("distinct_message_id_count") != len(all_ids):
        errors.append("summary.distinct_message_id_count is stale")
    story_numbers = sorted(row["number"] for row in rows if row["family"] == "story")
    if summary.get("story_numbers") != story_numbers or summary.get("story_number_gaps") != _number_gaps(story_numbers):
        errors.append("story number list or gaps are stale")
    return errors


def level_texts(output_dir: Path, level: int) -> tuple[dict[str, str], dict[str, str]]:
    """{message id: text} and {sid token: speaker_name} of one level's STORY + WINFAIL corpus files."""
    texts: dict[str, str] = {}
    speakers: dict[str, str] = {}
    for family in ("story", "winfail"):
        path = output_dir / SCRIPTS_DIR / script_file_name(family, level)
        if not path.is_file():
            continue
        script = json.loads(path.read_text(encoding="utf-8"))
        for entry in script["messages"]:
            if entry["text"] is not None:
                texts.setdefault(entry["id"], entry["text"])
            if entry.get("sid_token") and entry.get("speaker_name") is not None:
                speakers.setdefault(entry["sid_token"], entry["speaker_name"])
    return texts, speakers


def evidence_paths() -> list[Path]:
    paths: set[Path] = set()
    for pattern in EVIDENCE_GLOBS:
        paths.update(ROOT.glob(pattern))
    return sorted(paths)


def compare_with_evidence(output_dir: Path) -> tuple[list[str], dict[str, int]]:
    """Every tracked message_text_evidence.json must agree with the corpus word for word."""
    errors: list[str] = []
    stats = {"files": 0, "compared_messages": 0, "compared_speakers": 0}
    for path in evidence_paths():
        evidence = json.loads(path.read_text(encoding="utf-8"))
        level = int(evidence.get("level", EVIDENCE_ROOT_LEVEL))
        texts, speakers = level_texts(output_dir, level)
        relative = path.relative_to(ROOT).as_posix()
        if not texts:
            errors.append(f"{relative}: no corpus script for level {level}")
            continue
        stats["files"] += 1
        script_ids: set[str] = set()
        for source in evidence.get("script_message_sources", []):
            script_ids.update(str(message_id) for message_id in source.get("message_ids", []))
        for message_id in sorted(script_ids, key=int):
            if message_id not in texts:
                errors.append(f"{relative}: script message id {message_id} is not in the corpus for level {level}")
        compared = 0
        for message_id, text in evidence.get("messages", {}).items():
            if message_id in texts:
                compared += 1
                if texts[message_id] != text:
                    errors.append(f"{relative}: message {message_id} text differs from the corpus")
        if compared == 0:
            errors.append(f"{relative}: no message shared with the corpus for level {level}")
        stats["compared_messages"] += compared
        for token, name in evidence.get("speaker_names", {}).items():
            if token in speakers:
                stats["compared_speakers"] += 1
                if speakers[token] != name:
                    errors.append(f"{relative}: speaker {token} differs from the corpus ({speakers[token]!r} != {name!r})")
    if stats["files"] == 0:
        errors.append("no tracked message_text_evidence.json found")
    return errors, stats


def check(output_dir: Path, pak: Path) -> tuple[list[str], str]:
    if pak.is_file():
        errors = compare_with_tracked(build_from_pak(pak), output_dir)
        mode = "pak-rebuild"
    else:
        errors = check_offline(output_dir)
        mode = "offline"
    evidence_errors, stats = compare_with_evidence(output_dir)
    errors.extend(evidence_errors)
    return errors, f"mode={mode} evidence_files={stats['files']} compared_messages={stats['compared_messages']} compared_speakers={stats['compared_speakers']}"


def summary_line(prefix: str, index: dict[str, Any], suffix: str = "") -> str:
    summary = index["summary"]
    families = " ".join(f"{family}={stats['script_count']}" for family, stats in summary["families"].items())
    return (f"{prefix} scripts={summary['script_count']} {families} message_ids={summary['distinct_message_id_count']} "
            f"missing_text={summary['missing_text_id_count']} next_level_events={summary['next_level_event_count']} "
            f"unmapped_tokens={len(summary['unmapped_action_tokens'])}{(' ' + suffix) if suffix else ''}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--check", action="store_true", help="rebuild in memory (PAK present) or check offline, then compare with the tracked corpus and message evidence")
    args = parser.parse_args(argv)
    if args.check:
        errors, detail = check(args.output_dir, args.pak)
        if errors:
            for error in errors:
                print(f"STORY_CORPUS_CHECK_FAIL {error}")
            return 1
        print(summary_line("STORY_CORPUS_CHECK_PASS", load_index(args.output_dir), detail))
        return 0
    if not args.pak.is_file():
        parser.error(f"original PAK not found: {args.pak}")
    files = build_from_pak(args.pak)
    write_files(files, args.output_dir)
    evidence_errors, stats = compare_with_evidence(args.output_dir)
    if evidence_errors:
        for error in evidence_errors:
            print(f"STORY_CORPUS_BUILD_FAIL {error}")
        return 1
    print(summary_line("STORY_CORPUS_BUILD_PASS", load_index(args.output_dir), f"evidence_files={stats['files']} compared_messages={stats['compared_messages']}"))
    return 0


class StoryCorpusTask(OriginalArchiveTask):
    name = 'story_corpus'
    family = 'static'
    inputs = ('content/imported/hsl/global/world_map/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',
              'content/battles/levels/', 'tools/hsltools/levels/timeline.py', 'tools/hsltools/levels/message_text.py')
    outputs = (OUTPUT_DIR.relative_to(ROOT).as_posix() + '/',)
    replaces = ('tools/hsl_story_corpus.py --check',)
    scripts = ('tools/hsltools/data/story_corpus.py', 'tools/hsltools/data/big_map_flow.py', 'tools/hsltools/data/world_map.py', 'tools/hsltools/levels/timeline.py', 'tools/hsltools/levels/message_text.py')

    def verify(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[StoryCorpusTask]:
    return [StoryCorpusTask()]


if __name__ == '__main__':
    raise SystemExit(main())
