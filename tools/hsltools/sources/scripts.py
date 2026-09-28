"""Original level scripts and placement tables as the importers read them.

parse_text_metadata: the section / key / action structure of an INI-style script or object
table (STORY*.TXT, winfail*.txt, OBJ-*.OBS / .H) — [Object] blocks keep the words the actor
constructor 0x407ec0 consumes, every `action=` value is split into its act* chain.
parse_evef: the EVEF placement table (0x10 header + 0xD0 records), non-zero words per record.
Every level generator (battle seed, authored levels, story corpus, big-map flow, winfail
coverage, field coverage) parses through these two; tools/hsl_payload_inspector.py is the
report-writing command line around them. Bodies moved verbatim from that script.
"""
from __future__ import annotations

import collections
import re
from typing import Any

from hsltools.sources.shp import read_u32le

EVEF_MAGIC = b"EVEF"
EVEF_HEADER_SIZE = 0x10
EVEF_RECORD_SIZE = 0xD0
TEXT_RESOURCE_RE = re.compile(
    r"\b(?:SHAPE|MAGIC|WAV|DATA)\\[A-Za-z0-9_.-]+\.(?:SHP|WAV|BIN|TXT|OBS|H)\b",
    re.IGNORECASE,
)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]{2,}\b")
ACTION_START_RE = re.compile(r"^act[A-Za-z0-9_]*$")
# Object processes built by the actor constructor 0x407ec0 (3 defProcPlayer / 5 defProcEnemy).
ACTOR_PROCESS_CODES = {"defProcPlayer", "defProcEnemy"}


def decode_text(data: bytes) -> tuple[str, str]:
    try:
        return "ascii", data.decode("ascii")
    except UnicodeDecodeError:
        return "cp950", data.decode("cp950")


def strip_inline_comment(line: str) -> str:
    return line.split(";", 1)[0].strip()


def parse_action_chain(value: str) -> list[dict[str, Any]]:
    value = value.strip()
    if not value:
        return []

    call_match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\((.*)\)", value)
    if call_match:
        args = [part.strip() for part in call_match.group(2).split(",") if part.strip()]
        return [{"name": call_match.group(1), "args": args}]

    chain: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for token in [part.strip() for part in value.split(",") if part.strip()]:
        if ACTION_START_RE.match(token):
            if current is not None:
                chain.append(current)
            current = {"name": token, "args": []}
        elif current is None:
            current = {"name": token, "args": []}
        else:
            current["args"].append(token)
    if current is not None:
        chain.append(current)
    return chain


def parse_text_metadata(data: bytes, encoding: str | None = None) -> dict[str, Any]:
    """Section／action structure of an INI-style script or object table. Original records
    decode as ASCII or cp950; an authored script names its encoding (utf-8)."""
    if encoding is None:
        encoding, text = decode_text(data)
    else:
        text = data.decode(encoding)
    lines = text.splitlines()
    includes = [
        clean.split(None, 1)[1].strip()
        for line in lines
        if (clean := strip_inline_comment(line)).lower().startswith("#include ")
        and len(clean.split(None, 1)) == 2
    ]

    key_counter: collections.Counter[str] = collections.Counter()
    action_names: collections.Counter[str] = collections.Counter()
    object_blocks: list[dict[str, Any]] = []
    section_names: list[str] = []
    section_blocks: list[dict[str, Any]] = []
    current_section: str | None = None
    current_values: dict[str, str] = {}
    current_block: dict[str, Any] | None = None

    def flush_block() -> None:
        if current_section != "Object" or not current_values:
            return
        # obj_X1 (player-mode override) and obj_HitPoint (HP bonus word) are template words
        # the actor constructor 0x407ec0 consumes for actor processes only
        # (docs/evidence_packets/static_reverse/original_field_coverage.md §4); on effect /
        # map objects the same names hold a WAV name / mapobj parameter that nothing reads.
        retained = {"obj_Mode", "obj_X", "obj_Y", "obj_ReadShape", "obj_ZoomX", "obj_ZoomY"}
        if current_values.get("obj_Process_Code") in ACTOR_PROCESS_CODES:
            retained |= {"obj_X1", "obj_HitPoint"}
        # A chest template's obj_Attribute (+0x80) is the shown／hidden choice of 0x415730
        # (docs/evidence_packets/static_reverse/original_treasure.md §隐藏宝物).
        if current_values.get("obj_Process_Code") == "defProcTreasureBox":
            retained |= {"obj_Attribute"}
        # A stand object's objattrATTACKFLAG keeps it on its obj_Plane bucket instead of the
        # per-tick y bucket (0x43ccf0) — docs/evidence_packets/static_reverse/original_draw_order.md.
        if current_values.get("obj_Process_Code") == "defProcStandObject":
            retained |= {"obj_Attribute"}
        # A moving background's obj_Score／obj_HitPoint are its camera-parallax ratios
        # (x/640, y/480; −1 pins it to the view) — docs/evidence_packets/static_reverse/original_map_object_drift.md.
        if current_values.get("obj_Data9") == "mapobjMoveBG":
            retained |= {"obj_Score", "obj_HitPoint"}
        # A flashing light's obj_Score／obj_HitPoint are its dim depth and step delay
        # (0x43cee7) — docs/evidence_packets/static_reverse/original_map_object_flash.md.
        if current_values.get("obj_Data9") == "mapobjFlash":
            retained |= {"obj_Score", "obj_HitPoint"}
        # A round counter's obj_HitPoint is its round count and obj_Score its digit width
        # (0x43d5f5／0x43d652) — docs/evidence_packets/static_reverse/original_round_display.md.
        if current_values.get("obj_Data9") == "mapobjRoundNumberCounter":
            retained |= {"obj_Score", "obj_HitPoint"}
        data_fields = {
            key: value
            for key, value in current_values.items()
            if key.startswith("obj_Data") or key.startswith("obj_Collide_") or key in retained
        }
        object_blocks.append(
            {
                "obj_code": current_values.get("obj_code"),
                "obj_name": current_values.get("obj_name"),
                "obj_plane": current_values.get("obj_Plane"),
                "obj_shape_name": current_values.get("obj_Shape_Name"),
                "obj_shape_number": current_values.get("obj_Shape_Number"),
                "obj_process_code": current_values.get("obj_Process_Code"),
                "obj_data_fields": data_fields,
                "fields_present": sorted(current_values),
            }
        )

    for raw_line in lines:
        clean = strip_inline_comment(raw_line)
        if not clean:
            continue
        if clean.startswith("[") and clean.endswith("]"):
            flush_block()
            current_section = clean[1:-1]
            section_names.append(current_section)
            current_block = {
                "index": len(section_blocks),
                "name": current_section,
                "codes": [],
                "messages": [],
                "message_count": 0,
                "actions": [],
            }
            section_blocks.append(current_block)
            current_values = {}
            continue
        if "=" not in clean:
            continue
        key, value = [part.strip() for part in clean.split("=", 1)]
        key_counter[key] += 1
        if current_section == "Object":
            current_values[key] = value
        if current_block is not None:
            if key == "code":
                current_block["codes"].append(value)
            elif key == "message":
                current_block["messages"].append(value)
                current_block["message_count"] += 1
        if key == "action":
            chain = parse_action_chain(value)
            for action in chain:
                if action["name"]:
                    action_names[action["name"]] += 1
            if current_block is not None:
                current_block["actions"].append(
                    {
                        "primary": chain[0]["name"] if chain else None,
                        "chain": chain,
                    }
                )
    flush_block()

    resources = sorted(set(TEXT_RESOURCE_RE.findall(text)))
    identifiers = sorted(set(IDENTIFIER_RE.findall(text)))
    defines = [
        clean
        for line in lines
        if (clean := strip_inline_comment(line)).lower().startswith("#define ")
    ]
    define_values = {
        parts[1]: parts[2]
        for define in defines
        if len(parts := define.split()) >= 3
    }
    message_count = key_counter.get("message", 0)

    return {
        "kind": "text",
        "encoding": encoding,
        "byte_length": len(data),
        "line_count": len(lines),
        "include_count": len(includes),
        "includes": includes,
        "section_counts": dict(collections.Counter(section_names)),
        "section_blocks": section_blocks,
        "key_counts": dict(key_counter),
        "action_counts": dict(action_names),
        "message_key_count": message_count,
        "resource_refs": resources,
        "identifier_count": len(identifiers),
        "identifier_sample": identifiers[:80],
        "define_count": len(defines),
        "define_names": [define.split()[1] for define in defines if len(define.split()) >= 2],
        "define_values": define_values,
        "object_count": len(object_blocks),
        "objects": object_blocks,
    }


def parse_evef(data: bytes, summary_limit: int | None = 64) -> dict[str, Any]:
    """Parse an EVEF placement table. `summary_limit` keeps the inspector output
    compact (64 summaries); pass None for the complete table (level 1 has 79
    non-zero records, so the battle seed must not truncate)."""
    if not data.startswith(EVEF_MAGIC):
        raise ValueError("not an EVEF payload")
    record_count = read_u32le(data, 0x04)
    declared_size = read_u32le(data, 0x0C)
    expected_size = EVEF_HEADER_SIZE + record_count * EVEF_RECORD_SIZE
    records: list[dict[str, Any]] = []
    record_summaries: list[dict[str, Any]] = []
    for index in range(record_count):
        offset = EVEF_HEADER_SIZE + index * EVEF_RECORD_SIZE
        record = data[offset : offset + EVEF_RECORD_SIZE]
        words = [
            {"field_offset": word_offset, "value": read_u32le(record, word_offset)}
            for word_offset in range(0, len(record), 4)
            if read_u32le(record, word_offset) != 0
        ]
        if words:
            summary = {
                "index": index,
                "offset": offset,
                "field_0x04_code_candidate": read_u32le(record, 0x04),
                "placement_x_candidate_0x08": read_u32le(record, 0x08),
                "placement_y_candidate_0x0c": read_u32le(record, 0x0C),
                "non_zero_u32": words,
            }
            record_summaries.append(summary)
            records.append(summary)
    code_counts = collections.Counter(
        str(record["field_0x04_code_candidate"])
        for record in record_summaries
        if record["field_0x04_code_candidate"] is not None
    )
    return {
        "kind": "evef_binary",
        "magic": "EVEF",
        "byte_length": len(data),
        "record_count": record_count,
        "declared_size_0x0c": declared_size,
        "fixed_record_size_hypothesis": EVEF_RECORD_SIZE,
        "expected_size_from_count": expected_size,
        "size_matches_declared": declared_size == len(data),
        "size_matches_count_times_record_size": expected_size == len(data),
        "non_zero_record_count": len(records),
        "non_zero_records": records[:32],
        "record_code_counts": dict(sorted(code_counts.items(), key=lambda item: int(item[0]))),
        "record_summaries": record_summaries if summary_limit is None else record_summaries[:summary_limit],
    }
