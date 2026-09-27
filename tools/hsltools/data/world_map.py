"""World-map / town data chain from the original PAK (resource-derived, no gameplay).

Promotes the big-map point/track records (bigmap.dat), the track polylines
(TRACK.TXT + TRACK.H), the point names (RESOURCE.TXT), the town symbol table
(extras.h), the town background SHPs and the big-map SHP into
content/imported/hsl/global/world_map/world_map.json, and the town event table
(TOWNDEF.TXT + TOWNDEF.H) into towndef.json next to it.

Everything here is structure read from the resources. Field semantics that the
data does not prove (point field0, track field1, what each bmpm bit makes the
runtime do) stay provisional and are listed in "unresolved_semantics".

Usage:

    PYTHONPATH=tools python3 -m hsltools.data.world_map            # rebuild from ~/.wine-hsl-original/drive_c/hsl
    PYTHONPATH=tools python3 -m hsltools.data.world_map --check    # rebuild and compare with the tracked output;
                                                           # without the PAK: offline consistency check only

Registry task world_map (family world, OriginalArchiveTask): tracked output content/imported/hsl/global/world_map/
(world_map.json, towndef.json, previews); check = the script's --check (offline, or rebuild-and-compare when the
original install is present), generate = rebuild from the original hsl directory. Bodies (main included) moved
verbatim from the former hsl_world_map.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import tempfile
from pathlib import Path
from typing import Any

from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.paths import ORIGINAL_ROOT, ROOT
from hsltools.registry import Context

DEFAULT_PAK_ROOT = ORIGINAL_ROOT
DEFAULT_OUTPUT_DIR = ROOT / "content/imported/hsl/global/world_map"
WORLD_MAP_SCHEMA = "hsl_world_map.v1"
TOWNDEF_SCHEMA = "hsl_towndef.v1"
ENCODING = "cp950"

MEMBERS = {
    "bigmap_dat": "@:\\data\\bigmap.dat",
    "track_txt": "@:\\data\\TRACK.TXT",
    "track_h": "@:\\data\\TRACK.H",
    "resource_txt": "@:\\data\\RESOURCE.TXT",
    "extras_h": "@:\\data\\extras.h",
    "type_h": "@:\\data\\TYPE.H",
    "towndef_txt": "@:\\data\\TOWNDEF.TXT",
    "towndef_h": "@:\\data\\TOWNDEF.H",
    "bigmap_shp": "@:\\shape99\\BigMap.SHP",
    "status_bar_shp": "@:\\shape99\\Status_Bar.SHP",
}
POINT_MARKER_MEMBERS = ["@:\\shape99\\m_pnt001.SHP", "@:\\shape99\\m_pnt002.SHP", "@:\\shape99\\m_pnt003.SHP"]
TRACK_SPRITE_MEMBER = "@:\\shape99\\m_trk{id:03d}.SHP"
TOWN_BG_PATTERN = re.compile(r"^@:\\shape\\townbg(\d+)\.shp$", re.IGNORECASE)

# bigmap.dat layout (resource-derived from the record stride and the values
# themselves; the field names are this tool's reading, see the evidence packet).
POINT_TABLE_OFFSET = 0
POINT_RECORD_SIZE = 40
POINT_SLOT_COUNT = 100  # 100 * 40 = 4000 bytes up to the track table
TRACK_TABLE_OFFSET = 4000
TRACK_RECORD_SIZE = 16
TRACK_SLOT_COUNT = 100  # 100 * 16 = 1600 bytes up to the 5600-byte end
BIGMAP_DAT_SIZE = TRACK_TABLE_OFFSET + TRACK_SLOT_COUNT * TRACK_RECORD_SIZE
POINT_FIELDS = ["raw_field0", "flags", "point_id", "name_resource_id", "x", "y", "track_id_1", "track_id_2", "track_id_3", "raw_field9"]
TRACK_FIELDS = ["raw_field0", "raw_field1", "from_point", "to_point"]

# bmpm* constants as read from TYPE.H; the build fails if the PAK header disagrees.
BMPM_FLAGS = {
    "bmpmBattle": 0x80000000,
    "bmpmGeneral": 0x40000000,
    "bmpmTown": 0x20000000,
    "bmpmVisit": 0x10000000,
    "bmpmHidden": 0x08000000,
}

# Which argument positions of a te token are message ids, read from the
# TOWNDEF.H signature comments ([player id][message id][if_wait] ...).
MESSAGE_ARG_POSITIONS = {
    "tePlayerMessage": [1],
    "teShapeMessage": [2],
    "teCheckMoney": [3],
    "teCheckJobUp": [1],
    "teCheckJobUp2": [1],
    "teSecretManBuyThing": [2],
}
# teSelectInsertEvent: [player id][num][msg id 1][event 1][msg id 2][event 2]... -> every even index >= 2
SELECT_INSERT_TOKEN = "teSelectInsertEvent"
SHAPE_NAME_ARG_POSITIONS = {"teShapeMessage": 1, "teCheckMoney": 2, "teSecretManBuyThing": 1}

DEFINE_RE = re.compile(r"^\s*#define\s+(\S+)\s+(-?0x[0-9A-Fa-f]+|-?\d+)\b(.*)$")
SECTION_RE = re.compile(r"^\[([A-Za-z_][A-Za-z0-9_]*)\]\s*(.*)$")
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
TE_TOKEN_RE = re.compile(r"^te[A-Z][A-Za-z0-9_]*$")
INTEGER_RE = re.compile(r"-?\d+")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex32(value: int) -> str:
    return f"0x{value & 0xFFFFFFFF:08x}"


# ---------------------------------------------------------------- header parsing
def parse_defines(text: str) -> dict[str, int]:
    """#define NAME VALUE lines (decimal or hex); other lines are ignored."""
    result: dict[str, int] = {}
    for line in text.splitlines():
        match = DEFINE_RE.match(line)
        if match:
            result[match.group(1)] = int(match.group(2), 0)
    return result


def parse_defines_with_comments(text: str) -> dict[str, dict[str, Any]]:
    """#define NAME VALUE // comment -> {name: {value, signature_comment}} (TOWNDEF.H)."""
    result: dict[str, dict[str, Any]] = {}
    for line in text.splitlines():
        match = DEFINE_RE.match(line)
        if not match:
            continue
        rest = match.group(3).strip()
        comment = rest[2:].strip() if rest.startswith("//") else rest
        result[match.group(1)] = {"value": int(match.group(2), 0), "signature_comment": comment or None}
    return result


def decode_flag_names(value: int, flags: dict[str, int]) -> list[str]:
    value &= 0xFFFFFFFF
    return [name for name, bit in flags.items() if bit and value & bit == bit]


def undecoded_bits(value: int, flags: dict[str, int]) -> str | None:
    value &= 0xFFFFFFFF
    for bit in flags.values():
        value &= ~bit
    return _hex32(value) if value else None


# ---------------------------------------------------------------- bigmap.dat
def parse_bigmap(data: bytes, flags: dict[str, int] | None = None) -> dict[str, Any]:
    """Point (40-byte) and track (16-byte) records; all-zero slots are skipped."""
    flags = flags or BMPM_FLAGS
    if len(data) != BIGMAP_DAT_SIZE:
        raise ValueError(f"bigmap.dat is {len(data)} bytes, expected {BIGMAP_DAT_SIZE}")
    points: list[dict[str, Any]] = []
    for slot in range(POINT_SLOT_COUNT):
        rec = struct.unpack_from("<10i", data, POINT_TABLE_OFFSET + slot * POINT_RECORD_SIZE)
        if not any(rec):
            continue
        points.append(
            {
                "slot": slot,
                "id": rec[2],
                "raw_field0": rec[0],
                "flags_raw": _hex32(rec[1]),
                "flag_names": decode_flag_names(rec[1], flags),
                "flags_undecoded_bits": undecoded_bits(rec[1], flags),
                "name_resource_id": rec[3],
                "name_text": None,
                "x": rec[4],
                "y": rec[5],
                "track_ids": [value for value in rec[6:9] if value],
                "raw_track_fields": list(rec[6:9]),
                "raw_field9": rec[9],
            }
        )
    tracks: list[dict[str, Any]] = []
    for slot in range(TRACK_SLOT_COUNT):
        rec = struct.unpack_from("<4i", data, TRACK_TABLE_OFFSET + slot * TRACK_RECORD_SIZE)
        if not any(rec):
            continue
        tracks.append(
            {
                "slot": slot,
                "id": slot,
                "raw_field0": _hex32(rec[0]),
                "field0_flag_names": decode_flag_names(rec[0], flags),
                "raw_field1": _hex32(rec[1]),
                "field1_flag_names": decode_flag_names(rec[1], flags),
                "from_point": rec[2],
                "to_point": rec[3],
            }
        )
    return {"points": points, "tracks": tracks}


# ---------------------------------------------------------------- TRACK.TXT
def _strip_comment(line: str) -> str:
    return line.split(";", 1)[0].strip()


def parse_track_txt(text: str, track_defines: dict[str, int]) -> list[dict[str, Any]]:
    """[track] code = bmTrackNN / data = x,y,x,y,... -> polylines with the TRACK.H code value as id."""
    tracks: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    in_track = False
    for raw_line in text.splitlines():
        line = _strip_comment(raw_line)
        if not line or line.startswith("#"):
            continue
        section = SECTION_RE.match(line)
        if section:
            in_track = section.group(1).lower() == "track"
            if in_track:
                current = {"code": None, "id": None, "polyline": []}
                tracks.append(current)
            continue
        key_match = KEY_RE.match(line)
        if not key_match or not in_track or current is None:
            continue
        key, value = key_match.group(1).lower(), key_match.group(2).strip()
        if key == "code":
            current["code"] = value
            if value in track_defines:
                current["id"] = track_defines[value]
            elif INTEGER_RE.fullmatch(value):
                current["id"] = int(value)
        elif key == "data":
            numbers = [int(part) for part in value.split(",") if part.strip()]
            if len(numbers) % 2:
                raise ValueError(f"odd coordinate count in track {current.get('code')}")
            current["polyline"] = [[numbers[i], numbers[i + 1]] for i in range(0, len(numbers), 2)]
    return tracks


# ---------------------------------------------------------------- TOWNDEF.TXT
def split_events(value: str) -> list[dict[str, Any]]:
    """'teA,1,2,teB,3' -> [{token: teA, args: [1,2]}, {token: teB, args: [3]}]; a new
    command starts at every element spelled like a te token. Trailing empty
    arguments ('...,0,') are dropped."""
    parts = [part.strip() for part in value.split(",")]
    while parts and parts[-1] == "":
        parts.pop()
    commands: list[dict[str, Any]] = []
    for part in parts:
        if TE_TOKEN_RE.match(part) or not commands:
            commands.append({"token": part, "args": []})
        else:
            commands[-1]["args"].append(part)
    return commands


def parse_towndef(text: str) -> dict[str, Any]:
    """[item] and [town_event] records of TOWNDEF.TXT. Section-header trailing
    comments are kept as 'comment' (they label the shop / town); other comments
    and fully commented lines are dropped."""
    items: list[dict[str, Any]] = []
    town_events: list[dict[str, Any]] = []
    includes: list[str] = []
    other_sections: dict[str, int] = {}
    current: dict[str, Any] | None = None
    kind = ""
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        if stripped.startswith("#include"):
            includes.append(stripped.split(None, 1)[1].strip() if len(stripped.split(None, 1)) > 1 else stripped)
            continue
        section = SECTION_RE.match(stripped)
        if section:
            kind = section.group(1).lower()
            rest = section.group(2).strip()
            comment = rest[1:].strip() if rest.startswith(";") else None
            if kind == "item":
                current = {"code": None, "comment": comment or None, "item_ids": []}
                items.append(current)
            elif kind == "town_event":
                current = {"code": None, "comment": comment or None, "show_name": None, "item_code": None, "events": []}
                town_events.append(current)
            else:
                other_sections[kind] = other_sections.get(kind, 0) + 1
                current = None
            continue
        line = _strip_comment(stripped)
        key_match = KEY_RE.match(line)
        if not key_match or current is None:
            continue
        key, value = key_match.group(1).lower(), key_match.group(2).strip()
        if kind == "item":
            if key == "code":
                current["code"] = int(value)
            elif key == "item_id":
                current["item_ids"].extend(int(part) for part in value.split(",") if part.strip())
            else:
                current.setdefault("other_keys", {})[key] = value
        elif kind == "town_event":
            if key == "code":
                current["code"] = int(value)
            elif key == "show_name":
                current["show_name"] = {"resource_id": int(value), "text": None}
            elif key == "item_code":
                current["item_code"] = int(value)
            elif key == "event":
                current["events"].extend(split_events(value))
            else:
                current.setdefault("other_keys", {})[key] = value
    return {"includes": includes, "items": items, "town_events": town_events, "other_sections": other_sections}


def _is_symbol(arg: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z_][^,\s\\]*", arg)) and not INTEGER_RE.fullmatch(arg) and not arg.upper().endswith((".SHP", ".WAV"))


def annotate_town_events(parsed: dict[str, Any], token_defs: dict[str, dict[str, Any]], names: dict[str, str]) -> dict[str, Any]:
    """Attach token ids, show_name text and usage / message-id statistics in place."""
    token_usage: dict[str, int] = {name: 0 for name in token_defs}
    unknown_tokens: dict[str, int] = {}
    message_ids: set[str] = set()
    message_id_sources: dict[str, int] = {}
    shape_name_ids: set[str] = set()
    symbols: set[str] = set()
    event_count = 0
    for record in parsed["town_events"]:
        if record["show_name"] is not None:
            record["show_name"]["text"] = names.get(str(record["show_name"]["resource_id"]))
        for command in record["events"]:
            event_count += 1
            token = command["token"]
            if token in token_defs:
                command["token_id"] = token_defs[token]["value"]
                token_usage[token] += 1
            else:
                command["token_id"] = None
                command["unknown"] = True
                unknown_tokens[token] = unknown_tokens.get(token, 0) + 1
            args = command["args"]
            positions = list(range(2, len(args), 2)) if token == SELECT_INSERT_TOKEN else MESSAGE_ARG_POSITIONS.get(token, [])
            for position in positions:
                if position < len(args) and INTEGER_RE.fullmatch(args[position]) and int(args[position]) > 0:
                    message_ids.add(args[position])
                    message_id_sources[token] = message_id_sources.get(token, 0) + 1
            name_position = SHAPE_NAME_ARG_POSITIONS.get(token)
            if name_position is not None and name_position < len(args) and args[name_position].isdigit():
                shape_name_ids.add(args[name_position])
            symbols.update(arg for arg in args if _is_symbol(arg))
    parsed["statistics"] = {
        "item_count": len(parsed["items"]),
        "town_event_count": len(parsed["town_events"]),
        "event_command_count": event_count,
        "token_usage": dict(sorted(token_usage.items(), key=lambda kv: (-kv[1], kv[0]))),
        "unknown_tokens": dict(sorted(unknown_tokens.items())),
        "unknown_token_count": sum(unknown_tokens.values()),
        "message_ids": {"count": len(message_ids), "ids": sorted(message_ids, key=int), "by_token": dict(sorted(message_id_sources.items()))},
        "shape_name_resource_ids": sorted(shape_name_ids, key=int),
    }
    parsed["symbols_used"] = sorted(symbols)
    return parsed


def towndef_self_check(parsed: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    for kind in ("items", "town_events"):
        codes = [record["code"] for record in parsed[kind]]
        if None in codes:
            issues.append(f"{kind}: record without code")
        duplicates = sorted({code for code in codes if code is not None and codes.count(code) > 1})
        if duplicates:
            issues.append(f"{kind}: duplicate codes {duplicates}")
    item_codes = {record["code"] for record in parsed["items"]}
    for record in parsed["town_events"]:
        if record["item_code"] is not None and record["item_code"] not in item_codes:
            issues.append(f"town_event {record['code']}: item_code {record['item_code']} has no [item] record")
        if record.get("other_keys"):
            issues.append(f"town_event {record['code']}: unexpected keys {sorted(record['other_keys'])}")
    for record in parsed["items"]:
        if record.get("other_keys"):
            issues.append(f"item {record['code']}: unexpected keys {sorted(record['other_keys'])}")
    if parsed["other_sections"]:
        issues.append(f"unexpected sections {parsed['other_sections']}")
    return issues


# ---------------------------------------------------------------- self check
def world_map_self_check(points: list[dict[str, Any]], tracks: list[dict[str, Any]], polylines: dict[int, dict[str, Any]]) -> list[str]:
    """Cross-checks between point records, track records and TRACK.TXT polylines."""
    issues: list[str] = []
    point_by_id = {point["id"]: point for point in points}
    track_by_id = {track["id"]: track for track in tracks}
    for point in points:
        if point["id"] != point["slot"]:
            issues.append(f"point slot {point['slot']} carries id {point['id']}")
        if point["raw_field9"] != 0:
            issues.append(f"point {point['id']}: field9 = {point['raw_field9']} (expected 0)")
        if point["flags_undecoded_bits"]:
            issues.append(f"point {point['id']}: flag bits {point['flags_undecoded_bits']} outside bmpm*")
        if not point["track_ids"]:
            issues.append(f"point {point['id']} lists no track ids")
        for track_id in point["track_ids"]:
            track = track_by_id.get(track_id)
            if track is None:
                issues.append(f"point {point['id']}: track id {track_id} has no track record")
            elif point["id"] not in (track["from_point"], track["to_point"]):
                issues.append(f"point {point['id']}: track {track_id} does not touch it ({track['from_point']}->{track['to_point']})")
    referenced = {track_id for point in points for track_id in point["track_ids"]}
    for track in tracks:
        for key in ("from_point", "to_point"):
            if track[key] not in point_by_id:
                issues.append(f"track {track['id']}: {key} {track[key]} is not a point")
        if track["raw_field0"] != "0x00000000":
            issues.append(f"track {track['id']}: field0 = {track['raw_field0']} (all observed tracks carry 0)")
        if track["id"] not in referenced:
            issues.append(f"track {track['id']} is not listed by any point")
        polyline = polylines.get(track["id"])
        if polyline is None:
            issues.append(f"track {track['id']}: no TRACK.TXT polyline")
            continue
        src, dst = point_by_id.get(track["from_point"]), point_by_id.get(track["to_point"])
        if src and dst and polyline["polyline"]:
            first, last = polyline["polyline"][0], polyline["polyline"][-1]
            if first != [src["x"], src["y"]]:
                issues.append(f"track {track['id']}: polyline starts at {first}, from point {src['id']} is at {[src['x'], src['y']]}")
            if last != [dst["x"], dst["y"]]:
                issues.append(f"track {track['id']}: polyline ends at {last}, to point {dst['id']} is at {[dst['x'], dst['y']]}")
    for track_id in sorted(set(polylines) - set(track_by_id)):
        issues.append(f"TRACK.TXT {polylines[track_id]['code']} has no bigmap.dat track record")
    return issues


# ---------------------------------------------------------------- PAK access
class PakReader:
    def __init__(self, pak_root: Path):
        from hsltools.sources.pak import find_decoded_paks_packages

        self.packages = find_decoded_paks_packages(pak_root)
        if not self.packages:
            raise ValueError(f"no PAKS containers under {pak_root}")
        self.by_lower: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
        for package in self.packages:
            for record in package["records"]:
                self.by_lower.setdefault(str(record["name"]).lower(), (package, record))

    def names(self) -> list[str]:
        return [str(record["name"]) for package in self.packages for record in package["records"]]

    def find(self, member: str) -> str | None:
        hit = self.by_lower.get(member.lower())
        return str(hit[1]["name"]) if hit else None

    def read(self, member: str) -> bytes:
        from hsltools.sources.pak import read_paks_record_bytes

        hit = self.by_lower.get(member.lower())
        if hit is None:
            raise ValueError(f"{member} missing from PAK")
        package, record = hit
        return read_paks_record_bytes(package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"]))


def _source_entry(member: str, data: bytes) -> dict[str, Any]:
    return {"member": member, "byte_length": len(data), "sha256": _sha(data)}


def render_shp_png(raw: bytes) -> tuple[dict[str, Any], bytes]:
    """Decode with the shared TLHS decoder (hsltools.sources.shp); returns (metadata, png bytes).
    A TLHS member holds one image (its row table has exactly 'height' entries), so frame_count is 1;
    draw_origin is the signed int32 pair at 0x1C/0x20, read the same way as hsl_level_map_objects."""
    from hsltools.sources.shp import parse_shp, write_shp_preview

    shp = parse_shp(raw)
    if not shp["all_rows_decode"]:
        raise ValueError("row table does not decode with the shared TLHS row-segment reader")
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / "preview.png"
        write_shp_preview(raw, shp, target)
        png = target.read_bytes()
    meta = {
        "width": int(shp["width"]),
        "height": int(shp["height"]),
        "frame_count": 1,
        "draw_origin": list(struct.unpack_from("<ii", raw, 28)),
        "color_key_or_flags_0x10": _hex32(int(shp["color_key_or_flags_0x10"])),
    }
    return meta, png


def decode_shp_preview(reader: PakReader, member: str, preview_rel: str) -> tuple[dict[str, Any], bytes | None]:
    raw = reader.read(member)
    entry: dict[str, Any] = _source_entry(member, raw)
    try:
        meta, png = render_shp_png(raw)
    except Exception as error:  # decoder does not support this variant: record the reason, do not fabricate
        entry.update({"width": None, "height": None, "frame_count": None, "draw_origin": None, "preview": None, "png_sha256": None,
                      "decode_error": f"{type(error).__name__}: {error}"})
        return entry, None
    entry.update({**meta, "preview": preview_rel, "png_sha256": _sha(png), "decode_error": None})
    return entry, png


# ---------------------------------------------------------------- build
def build(pak_root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, bytes]]:
    from hsltools.sources.tables import parse_table

    reader = PakReader(pak_root)
    raw = {key: reader.read(member) for key, member in MEMBERS.items() if key != "bigmap_shp"}
    sources = {key: _source_entry(reader.find(MEMBERS[key]) or MEMBERS[key], data) for key, data in raw.items()}
    type_defines = parse_defines(raw["type_h"].decode(ENCODING, "replace"))
    flags = {name: value & 0xFFFFFFFF for name, value in type_defines.items() if name.startswith("bmpm")}
    if flags != BMPM_FLAGS:
        raise ValueError(f"TYPE.H bmpm constants differ from the tool's table: {flags}")
    names = parse_table(raw["resource_txt"])
    track_defines = parse_defines(raw["track_h"].decode(ENCODING, "replace"))
    extras_defines = parse_defines(raw["extras_h"].decode(ENCODING, "replace"))

    parsed = parse_bigmap(raw["bigmap_dat"], flags)
    points, tracks = parsed["points"], parsed["tracks"]
    for point in points:
        point["name_text"] = names.get(str(point["name_resource_id"]))
    polylines = {track["id"]: track for track in parse_track_txt(raw["track_txt"].decode(ENCODING), track_defines) if track["id"] is not None}
    point_by_id = {point["id"]: point for point in points}
    for track in tracks:
        polyline = polylines.get(track["id"])
        track["code"] = polyline["code"] if polyline else None
        track["polyline"] = polyline["polyline"] if polyline else None
        src, dst = point_by_id.get(track["from_point"]), point_by_id.get(track["to_point"])
        track["endpoints_match_points"] = bool(
            polyline and src and dst and polyline["polyline"]
            and polyline["polyline"][0] == [src["x"], src["y"]] and polyline["polyline"][-1] == [dst["x"], dst["y"]]
        )
    issues = world_map_self_check(points, tracks, polylines)

    previews: dict[str, bytes] = {}

    def asset(member: str, preview_rel: str) -> dict[str, Any] | None:
        found = reader.find(member)
        if found is None:
            return None
        entry, png = decode_shp_preview(reader, found, preview_rel)
        if png is not None:
            previews[preview_rel] = png
        return entry

    big_map_image = asset(MEMBERS["bigmap_shp"], "previews/bigmap.png")
    if big_map_image is None:
        raise ValueError(f"{MEMBERS['bigmap_shp']} missing from PAK")
    for track in tracks:
        member = TRACK_SPRITE_MEMBER.format(id=track["id"])
        track["sprite"] = asset(member, f"previews/m_trk{track['id']:03d}.png")
        if track["sprite"] is None:
            track["sprite_reason"] = f"no {member} member in the PAK"
    point_markers = []
    for index, member in enumerate(POINT_MARKER_MEMBERS, start=1):
        entry = asset(member, f"previews/m_pnt{index:03d}.png")
        point_markers.append(entry if entry is not None else {"member": member, "preview": None, "reason": "member missing from the PAK"})
    status_bar = asset(MEMBERS["status_bar_shp"], "previews/status_bar.png")
    assets = {
        "point_markers": point_markers,
        "status_bar": status_bar if status_bar is not None else {"member": MEMBERS["status_bar_shp"], "preview": None, "reason": "member missing from the PAK"},
        "note": "m_pnt001..003 are three point-marker images and m_trk0NN one pre-drawn image per bmTrackNN; which marker a bmpm point type uses, and how the runtime places the track image relative to its draw_origin, are not established here.",
    }
    town_bg_members = {int(match.group(1)): name for name in reader.names() if (match := TOWN_BG_PATTERN.match(name))}
    towns: list[dict[str, Any]] = []
    for symbol, point_id in sorted(extras_defines.items(), key=lambda kv: kv[1]):
        if not symbol.startswith("town_"):
            continue
        point = point_by_id.get(point_id)
        background = None
        member = town_bg_members.get(point_id)
        if member is not None:
            background, png = decode_shp_preview(reader, member, f"previews/townbg_{point_id:02d}.png")
            if png is not None:
                previews[background["preview"]] = png
        towns.append(
            {
                "symbol": symbol,
                "point_id": point_id,
                "point_name_text": point["name_text"] if point else None,
                "point_flag_names": point["flag_names"] if point else None,
                "background": background,
            }
        )
        if point is None:
            issues.append(f"{symbol} = {point_id} is not a bigmap point")
        elif "bmpmTown" not in point["flag_names"]:
            issues.append(f"{symbol} = {point_id}: point flags {point['flag_names']} lack bmpmTown")
    town_ids = {town["point_id"] for town in towns}
    for point_id in sorted(town_bg_members):
        if point_id not in town_ids:
            issues.append(f"{town_bg_members[point_id]} has no town_* symbol in extras.h")

    world_map = {
        "schema": WORLD_MAP_SCHEMA,
        "evidence_tier": "resource-derived",
        "claim": (
            "Structure read from bigmap.dat, TRACK.TXT/TRACK.H, RESOURCE.TXT, extras.h, TYPE.H and the SHP members named in "
            "'sources'. Field names are this tool's reading of the record stride and cross-references; how the runtime consumes "
            "point field0, track field1 and the bmpm bits is not established here (see 'unresolved_semantics')."
        ),
        "sources": {key: sources[key] for key in ("bigmap_dat", "track_txt", "track_h", "resource_txt", "extras_h", "type_h")},
        "record_layout": {
            "point": {"offset": POINT_TABLE_OFFSET, "record_size": POINT_RECORD_SIZE, "slots": POINT_SLOT_COUNT, "int32_le_fields": POINT_FIELDS, "empty_slots_skipped": True},
            "track": {"offset": TRACK_TABLE_OFFSET, "record_size": TRACK_RECORD_SIZE, "slots": TRACK_SLOT_COUNT, "int32_le_fields": TRACK_FIELDS, "empty_slots_skipped": True, "id_is_slot_index": True},
        },
        "flag_bits": {name: _hex32(value) for name, value in flags.items()},
        "big_map_mode_constants": {name: value for name, value in type_defines.items() if name.startswith("gameBM")},
        "coordinate_space": "BigMap.SHP pixels (point x,y and TRACK.TXT polylines share it)",
        "big_map_image": big_map_image,
        "assets": assets,
        "points": points,
        "tracks": tracks,
        "towns": towns,
        "counts": {
            "points": len(points),
            "tracks": len(tracks),
            "track_polylines": len(polylines),
            "towns": len(towns),
            "town_backgrounds": sum(1 for town in towns if town["background"] and town["background"]["preview"]),
            "track_sprites": sum(1 for track in tracks if track["sprite"] and track["sprite"]["preview"]),
            "point_markers": sum(1 for marker in point_markers if marker.get("preview")),
            "points_by_flag": {name: sum(1 for point in points if name in point["flag_names"]) for name in flags},
            "tracks_with_field1_hidden": sum(1 for track in tracks if "bmpmHidden" in track["field1_flag_names"]),
        },
        "self_check": {"issues": issues, "issue_count": len(issues)},
        "notes": [
            "Point ids equal their slot index; slot 0 is empty. Track ids equal their slot index in the 4000-byte-offset table; slot 0 is empty.",
            "Track field0 is 0 in every record and the bmpmHidden bit appears in field1; the tool decodes bmpm names for both fields and does not assert which one the runtime treats as the flag word.",
            "TownBG<NN>.SHP existence is matched case-insensitively against the PAK directory; towns without a member get background = null.",
        ],
        "unresolved_semantics": [
            "point raw_field0 (2 for point 1, 0 elsewhere): TYPE.H gameBMShow = 2 and TOWNDEF teBMSetPointMode [id][mode] make 'initial point mode' a provisional reading; not proven",
            "track raw_field1: carries bmpmHidden on 18 of 44 tracks; whether it is the track flag word targeted by teBMSetTrackFlag/teBMClearTrackFlag is provisional",
            "runtime effect of bmpmBattle / bmpmGeneral / bmpmTown / bmpmVisit / bmpmHidden on a point (menu, battle entry, visibility) is not established by the data",
            "walk speed along polylines, point hit areas and the level each point enters are not in these members",
            "which of m_pnt001..003 marks which bmpm point type, and the placement rule of m_trk0NN images (draw_origin vs polyline) are recorded, not interpreted",
        ],
    }

    towndef_parsed = parse_towndef(raw["towndef_txt"].decode(ENCODING))
    token_defs = parse_defines_with_comments(raw["towndef_h"].decode(ENCODING, "replace"))
    annotate_town_events(towndef_parsed, token_defs, names)
    symbol_table = {**extras_defines, **{k: v for k, v in type_defines.items() if k.startswith(("bmpm", "gameBM", "gameover", "gameBigMap"))}}
    symbols = {
        symbol: (_hex32(symbol_table[symbol]) if symbol.startswith("bmpm") else symbol_table[symbol]) if symbol in symbol_table else None
        for symbol in towndef_parsed.pop("symbols_used")
    }
    towndef_issues = towndef_self_check(towndef_parsed)
    towndef = {
        "schema": TOWNDEF_SCHEMA,
        "evidence_tier": "resource-derived",
        "claim": (
            "Record structure of TOWNDEF.TXT with te tokens matched to TOWNDEF.H ids and resource ids resolved through RESOURCE.TXT. "
            "Argument meaning follows the TOWNDEF.H signature comments only where a message id is collected; handler behaviour is not established."
        ),
        "sources": {key: sources[key] for key in ("towndef_txt", "towndef_h", "resource_txt", "extras_h", "type_h")},
        "includes": towndef_parsed["includes"],
        "token_ids": {name: entry["value"] for name, entry in token_defs.items()},
        "token_signatures": {name: entry["signature_comment"] for name, entry in token_defs.items()},
        "message_id_argument_positions": {**MESSAGE_ARG_POSITIONS, SELECT_INSERT_TOKEN: "even indexes from 2"},
        "symbols": symbols,
        "items": towndef_parsed["items"],
        "town_events": towndef_parsed["town_events"],
        "statistics": towndef_parsed["statistics"],
        "self_check": {"issues": towndef_issues, "issue_count": len(towndef_issues)},
        "unresolved_semantics": [
            "te handler behaviour, menu layout, shop pricing and event scheduling are not established by the table",
            "argument roles other than the message-id positions listed above are copied from TOWNDEF.H comments without runtime confirmation",
            "symbolic arguments are resolved only through extras.h / TYPE.H defines; unresolved symbols are listed with null",
        ],
    }
    return world_map, towndef, previews


def write_outputs(output_dir: Path, world_map: dict[str, Any], towndef: dict[str, Any], previews: dict[str, bytes]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "world_map.json").write_text(json.dumps(world_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / "towndef.json").write_text(json.dumps(towndef, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for rel, png in previews.items():
        target = output_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(png)


def _preview_entries(world_map: dict[str, Any]) -> list[dict[str, Any]]:
    entries = [world_map.get("big_map_image") or {}]
    entries.extend(town["background"] for town in world_map.get("towns", []) if town.get("background"))
    entries.extend(track["sprite"] for track in world_map.get("tracks", []) if track.get("sprite"))
    assets = world_map.get("assets", {})
    entries.extend(assets.get("point_markers", []))
    entries.append(assets.get("status_bar") or {})
    return [entry for entry in entries if entry.get("preview")]


def check_offline(output_dir: Path) -> list[str]:
    """Consistency of the tracked outputs without the PAK."""
    failures: list[str] = []
    wm_path, td_path = output_dir / "world_map.json", output_dir / "towndef.json"
    if not wm_path.exists() or not td_path.exists():
        return [f"missing tracked output under {output_dir}"]
    world_map = json.loads(wm_path.read_text(encoding="utf-8"))
    towndef = json.loads(td_path.read_text(encoding="utf-8"))
    if world_map.get("schema") != WORLD_MAP_SCHEMA:
        failures.append(f"world_map schema={world_map.get('schema')}")
    if towndef.get("schema") != TOWNDEF_SCHEMA:
        failures.append(f"towndef schema={towndef.get('schema')}")
    points, tracks = world_map.get("points", []), world_map.get("tracks", [])
    polylines = {track["id"]: {"code": track.get("code"), "polyline": track.get("polyline") or []} for track in tracks if track.get("polyline")}
    recorded = set(world_map.get("self_check", {}).get("issues", []))
    if not set(world_map_self_check(points, tracks, polylines)) <= recorded:
        failures.append("world_map self_check issues do not match the tracked records")
    counts = world_map.get("counts", {})
    if counts.get("points") != len(points) or counts.get("tracks") != len(tracks) or counts.get("towns") != len(world_map.get("towns", [])):
        failures.append("world_map counts differ from record lists")
    for entry in _preview_entries(world_map):
        path = output_dir / entry["preview"]
        if not path.is_file() or _sha(path.read_bytes()) != entry.get("png_sha256"):
            failures.append(f"preview missing or hash differs: {entry['preview']}")
    stats = towndef.get("statistics", {})
    if stats.get("item_count") != len(towndef.get("items", [])) or stats.get("town_event_count") != len(towndef.get("town_events", [])):
        failures.append("towndef statistics differ from record lists")
    usage: dict[str, int] = {}
    for record in towndef.get("town_events", []):
        for command in record.get("events", []):
            if command.get("token_id") is not None:
                usage[command["token"]] = usage.get(command["token"], 0) + 1
    if {k: v for k, v in stats.get("token_usage", {}).items() if v} != usage:
        failures.append("towndef token_usage differs from event records")
    return failures


def check(output_dir: Path, pak_root: Path) -> int:
    failures = check_offline(output_dir)
    mode = "offline"
    if pak_root.exists() and not failures:
        mode = "rebuild"
        world_map, towndef, previews = build(pak_root)
        if json.loads((output_dir / "world_map.json").read_text(encoding="utf-8")) != json.loads(json.dumps(world_map)):
            failures.append("world_map.json differs from a fresh build")
        if json.loads((output_dir / "towndef.json").read_text(encoding="utf-8")) != json.loads(json.dumps(towndef)):
            failures.append("towndef.json differs from a fresh build")
        for rel, png in previews.items():
            path = output_dir / rel
            if not path.is_file() or path.read_bytes() != png:
                failures.append(f"{rel} differs from a fresh decode")
    if failures:
        print("WORLD_MAP_CHECK_FAIL " + "; ".join(failures))
        return 1
    world_map = json.loads((output_dir / "world_map.json").read_text(encoding="utf-8"))
    towndef = json.loads((output_dir / "towndef.json").read_text(encoding="utf-8"))
    print(
        f"WORLD_MAP_CHECK_PASS mode={mode} points={world_map['counts']['points']} tracks={world_map['counts']['tracks']} "
        f"towns={world_map['counts']['towns']} town_events={towndef['statistics']['town_event_count']} items={towndef['statistics']['item_count']} "
        f"self_check_issues={len(world_map['self_check']['issues'])}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK_ROOT, help="original hsl directory (or hsl.pak) to read")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--check", action="store_true", help="rebuild and compare with the tracked output (offline consistency only when the PAK is absent)")
    args = parser.parse_args(argv)
    if args.check:
        return check(args.output_dir, args.pak)
    if not args.pak.exists():
        print(f"WORLD_MAP_BUILD_FAIL pak_missing={args.pak}")
        return 1
    world_map, towndef, previews = build(args.pak)
    write_outputs(args.output_dir, world_map, towndef, previews)
    print(
        f"WORLD_MAP_BUILD_PASS output={args.output_dir.relative_to(ROOT)} points={world_map['counts']['points']} tracks={world_map['counts']['tracks']} "
        f"towns={world_map['counts']['towns']} town_backgrounds={world_map['counts']['town_backgrounds']} town_events={towndef['statistics']['town_event_count']} "
        f"items={towndef['statistics']['item_count']} track_sprites={world_map['counts']['track_sprites']} previews={len(previews)} self_check_issues={len(world_map['self_check']['issues'])}"
    )
    return 0


class WorldMapTask(OriginalArchiveTask):
    name = 'world_map'
    family = 'world'
    archive = ORIGINAL_ROOT
    inputs = ()
    outputs = (DEFAULT_OUTPUT_DIR.relative_to(ROOT).as_posix() + '/',)
    replaces = ('tools/hsl_world_map.py --check',)
    scripts = ('tools/hsltools/data/world_map.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check, DEFAULT_OUTPUT_DIR, DEFAULT_PAK_ROOT)

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[WorldMapTask]:
    return [WorldMapTask()]


if __name__ == '__main__':
    raise SystemExit(main())
