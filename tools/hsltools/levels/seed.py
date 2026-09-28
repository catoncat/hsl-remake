"""Promote one original HSL battle into compact, reproducible remake inputs (battle_seed:N).

The original PAK stays outside the repository. This tool reads exact named PAKS
records in memory, writes only a decoded map PNG, a compact WRD terrain packet,
and a machine-readable seed with hashes / script structure / placement joins.
It does not infer gameplay semantics from object names or execute the original.

Registry task battle_seed:N (tools/hsl.py check|generate battle_seed:N): check validates the tracked seed, terrain
packet and map PNG against each other and the reviewed map bindings without the PAK;
generate rebuilds them from the original hsl.pak next to the documented EXE.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image

from hsltools.sources.scripts import parse_evef, parse_text_metadata
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.wrd import decode_wrd
from hsltools.checks.source_map_binding import (
    source_map_member,
    alias_metadata,
    check_seed_binding,
    reviewed_bindings)
from hsltools.legacy import imported_levels
from hsltools.levels import original_pak
from hsltools.paths import ORIGINAL_PAK
from hsltools.registry import Context, NotGeneratable, Task


DEFAULT_PAK = ORIGINAL_PAK


def paths_for_level(level: int) -> dict[str, Path]:
    code = f"{level:03d}"
    return {
        "seed": Path(f"content/generated/hsl/chapter01/battle{code}_seed.json"),
        "terrain": Path(f"content/generated/hsl/static/hsl01/level{code}_terrain.json"),
        "map": Path(f"content/imported/hsl/chapter01/battle{code}/level{level}.png"),
    }


# Story-only levels (no winfail script) still promote through the same seed; a
# level without its own obj-NNN.h borrows the header its STORY script includes.
OPTIONAL_RECORDS = {"winfail", "object_header", "level_header"}
# Global object table: OBJ-ALL.H names engine-wide symbols (obj_Effect_*, obj_Story_Block,
# obj_Story_PlayerN) that level scripts insert without defining them in obj-<code>.h;
# global.obs carries their object records. Read only when a level's scripts use one.
GLOBAL_RECORDS = {"global_object_header": "@:\\data\\OBJ-ALL.H", "global_objects": "@:\\data\\global.obs"}
INSERT_ACTIONS = {"actinsertstoryobject", "actinsertobject", "actinsertrandomobject"}
# lane ch2c: STORY037 spawns its temple guardians through the random-position insert
# variants (actSetRandomPos slots) and winfail039 through actInsertStoryObjectXRange;
# they name header symbols exactly like actInsertObject. No earlier tracked level uses
# these tokens, so their seeds are unchanged.
INSERT_ACTIONS |= {"actinsertobjectrandompos", "actinsertstoryobjectrandompos", "actinsertstoryobjectxrange"}
# end lane ch2c
# Legacy candidate names remain an API for older provenance tests. build() never
# selects from these folders: the source OBS object's full path is authoritative.
MAP_MEMBER_FOLDERS = ("shape01", "shape11", "shape21", "shape31", "shape41")
# Map shapes carry a two-digit level number (shape01\level01.shp for level 1,
# shape01\level52.shp for level 52) while data records keep three digits.
MAP_MEMBER_DIGITS = 2
# Historical seed annotations, not the map-selection mechanism. Each alias
# names the map level and preserves the old evidence sentence (WRD similarity,
# missing same-number shapes or matching stand objects). The now-confirmed OBS
# consumer is documented in original_map_binding.md; these older provisional
# annotations are retained only to avoid rewriting unchanged seed provenance.
_CAMP_WRD = "the 20x15 camp table shared by levels 55/56/61/62/64"
MAP_ALIASES: dict[int, dict[str, Any]] = {
    # lane ch2b
    # Levels 32 / 33 each have a shape of their own, but the obj-NNN.obs 地圖管理員
    # (defProcIconBG) record — the per-level map table consistent across the PAK —
    # names the other level's shape, and only that shape matches the level's WRD grid
    # (level032.wrd 22x37 -> Level33.SHP 704x1184; level033.wrd 30x30 -> Level32.SHP 960x960).
    32: {
        "map_level": 33,
        "evidence": "obj-032.obs 地圖管理員 (defProcIconBG) names SHAPE31\\LEVEL33.SHP and level032.wrd is 22x37 = Level33.SHP 704x1184 at 32px (Level32.SHP is 960x960, no match); resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    33: {
        "map_level": 32,
        "evidence": "obj-033.obs 地圖管理員 (defProcIconBG) names SHAPE31\\LEVEL32.SHP and level033.wrd is 30x30 = Level32.SHP 960x960 at 32px (level33.SHP is 704x1184, no match); resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    # end lane ch2b
    60: {
        "map_level": 58,
        "evidence": "level060.wrd is byte-identical to level058.wrd and the PAK has no level60.shp; the engine level->map table is not located (provisional)",
    },
    # STORY063: the elf king's spies report in the throne hall (SID_ENEMY058 克里歐司,
    # two 027 and a 023 guard in the EVEF), same 30x22 terrain as level 58 / 60.
    63: {
        "map_level": 58,
        "evidence": "level063.wrd is byte-identical to level058.wrd (30x22 throne hall) and the PAK has no level63.shp; its EVEF places SID_ENEMY058 克里歐司 with 027 / 023 attendants like level 60, so the level58 hall is reused; the engine level->map table is not located (provisional)",
    },
    # Post-battle camp talks (winfail003 -> 61, winfail006 -> 62, winfail007 -> 64): no
    # shape of their own; the terrain is the camp table and the EVEF repeats level 55's
    # campfire 火01 (146,279) and night ambience 夜晚聲 NIGHT001.WAV, so the dusk camp
    # level55.SHP is chosen over the morning camp level56.SHP (鳥聲 YELL010.WAV).
    61: {
        "map_level": 55,
        "evidence": f"level061.wrd is byte-identical to level055.wrd ({_CAMP_WRD}) and the PAK has no level61.shp; its EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV night ambience, so the dusk camp level55.SHP is chosen over the morning camp level56.SHP; the camp choice is provisional (the engine level->map table is not located), the other candidate is level 56",
    },
    62: {
        "map_level": 55,
        "evidence": f"level062.wrd is byte-identical to level055.wrd ({_CAMP_WRD}) and the PAK has no level62.shp; its EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV night ambience and STORY062 ends with 晚安 (messages 987/988), so the dusk camp level55.SHP is chosen over the morning camp level56.SHP; the camp choice is provisional (the engine level->map table is not located), the other candidate is level 56",
    },
    64: {
        "map_level": 55,
        "evidence": f"level064.wrd is byte-identical to level055.wrd ({_CAMP_WRD}) and the PAK has no level64.shp; its EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV night ambience, so the dusk camp level55.SHP is chosen over the morning camp level56.SHP; the camp choice is provisional (the engine level->map table is not located), the other candidate is level 56",
    },
    # Level 901 (菲納斯河畔伏擊): winfail010's win section rearms big-map point 8 with
    # actBMSetPointEvent 8,901,bmpmGeneral, so the ambush is fought on the level 8
    # riverside map. The PAK has no level901 shape at all; obj-901.obs's 地圖管理員
    # (defProcIconBG) record names SHAPE01\LEVEL08.SHP and level901.wrd is the level 8
    # terrain table byte for byte (the point-8 encounter levels 516-518 share both).
    # lane parent-900: 曼多力亞 event 900 (TOWNDEF event 30 teBMSetPointEvent town_曼多力亞,900,
    # bmpmGeneral) — the confrontation in the ruined city; the obs map manager names
    # SHAPE01\LEVEL09.SHP and level900.wrd is the level 9 table (50x37) with one cell changed.
    900: {
        "map_level": 9,
        "evidence": "obj-900.obs's 地圖管理員 (defProcIconBG) record names SHAPE01\\LEVEL09.SHP and level900.wrd is the level 9 table (7424 bytes, 50x37) differing from level009.wrd in one terrain cell only; its EVEF repeats level 9's seventeen house / well stand objects at the same anchors and the PAK has no level900 shape in any shapeNN folder (resource-derived map choice); that the engine draws the map manager's shape is read from this consistency, not from a located loader routine (provisional)",
    },
    901: {
        "map_level": 8,
        "evidence": "level901.wrd is byte-identical to level008.wrd (47x25 riverside table, also shared by the point-8 encounter levels 516/517/518) and the PAK has no level901 shape in any shapeNN folder; obj-901.obs's 地圖管理員 (defProcIconBG) record names SHAPE01\\LEVEL08.SHP as its shape, the same record that names each level's own map on levels 8/55/58/65 (resource-derived map choice); that the engine draws the map manager's shape is read from this consistency, not from a located loader routine (provisional)",
    },
    # lane ch2a
    # Camp story levels 66 (STORY065 -> 9,66), 67 (winfail017 -> 17,67), 68 (winfail902 -> 17,68)
    # and 69 (winfail019 -> 19,69): each level's obj-NNN.obs carries a 地圖管理員 (defProcIconBG)
    # record whose shape names the map the level uses — the same record names
    # SHAPE41\LEVEL55.SHP for all four, so the alias is resource-derived rather than a
    # WRD-similarity guess; only the engine loader that reads it is not located.
    66: {
        "map_level": 55,
        "evidence": "obj-066.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL55.SHP as this level's map (resource-derived, the same record every level's .obs uses to name its map) and the PAK has no level66.shp; level066.wrd is the same 20x15 grid as level055.wrd (one cell (9,3) unblocked, shared byte-for-byte by levels 66/67/68/69/70) and the EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV at (320,416); STORY066 has the party sit in silence after 廢都 and 緹娜 says 帕尼西雅城 is near (messages 1076-1080); the engine map loader that reads the record is not located (provisional tail note)",
    },
    67: {
        "map_level": 55,
        "evidence": "obj-067.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL55.SHP as this level's map (resource-derived, the same record every level's .obs uses to name its map) and the PAK has no level67.shp; level067.wrd is the same 20x15 grid as level055.wrd (one cell (9,3) unblocked, shared byte-for-byte by levels 66/67/68/69/70) and the EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV at (320,416); STORY067 (winfail017 -> 17,67) has 克里夫 064 hand over the pass by the fire and 嚎 question 雷歐納德 (messages 1379-1411, 1401-1410); the engine map loader that reads the record is not located (provisional tail note)",
    },
    68: {
        "map_level": 55,
        "evidence": "obj-068.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL55.SHP as this level's map (resource-derived, the same record every level's .obs uses to name its map) and the PAK has no level68.shp; level068.wrd is the same 20x15 grid as level055.wrd (one cell (9,3) unblocked, shared byte-for-byte by levels 66/67/68/69/70) and the EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV at (320,416); STORY068 (winfail902 -> 17,68) is the camp half of STORY067 alone: 嚎 questions 雷歐納德 (messages 1401-1410); the engine map loader that reads the record is not located (provisional tail note)",
    },
    69: {
        "map_level": 55,
        "evidence": "obj-069.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL55.SHP as this level's map (resource-derived, the same record every level's .obs uses to name its map) and the PAK has no level69.shp; level069.wrd is the same 20x15 grid as level055.wrd (one cell (9,3) unblocked, shared byte-for-byte by levels 66/67/68/69/70) and the EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV at (320,416); STORY069 (winfail019 / winfail904 -> 19,69) is the seven-member camp council on 那可那魯 and 冀羅 (messages 1488-1547); the engine map loader that reads the record is not located (provisional tail note)",
    },
    # end lane ch2a
    # lane ch2b
    # Story-only levels 70 (camp on the way to 克萊恩城, winfail029 -> 29,70) and 71 (the
    # throne hall, winfail031 -> 31,71) have no shape of their own; their obj-NNN.obs
    # 地圖管理員 (defProcIconBG) record names the map shape directly.
    70: {
        "map_level": 55,
        "evidence": "obj-070.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL55.SHP and level070.wrd is the same 20x15 grid (one height byte differs from level055.wrd; byte-identical to level066-069.wrd); the PAK has no level70.shp and the EVEF repeats level 55's 火01 campfire at (146,279) and 夜晚聲 NIGHT001.WAV; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    71: {
        "map_level": 58,
        "evidence": "obj-071.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level071.wrd is byte-identical to level058.wrd (30x22 throne hall); the PAK has no level71.shp and the EVEF places SID_ENEMY058 克里歐司 at (256,256); resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    # end lane ch2b
    # lane ch3
    # Finale chain: the epilogue / final battles have no shape of their own and their
    # obj-NNN.obs 地圖管理員 (defProcIconBG) record names the map directly — 73 (the
    # 席德爾 choice after 悲嘆之湖) on LEVEL41, 75 (塔克斯 duel, winfail045 -> 75) on the
    # level-57 hall, 76 / 77 / 78 / 79 (the elf king / 席德爾 / 魔神 battles) and the
    # story epilogues 81 / 82 on the LEVEL58 throne hall. Every WRD grid matches the
    # named shape at 32px; the engine loader that reads the record is not located.
    73: {
        "map_level": 41,
        "evidence": "obj-073.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL41.SHP and level073.wrd is byte-identical to level041.wrd (40x30 = Level41.SHP 1280x960 at 32px); the PAK has no level73.shp; STORY073 / winfail073 is the 雷特-席德爾 choice played where winfail041 ends (actSetNextPlayLevelEvent 41,73); resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    75: {
        "map_level": 57,
        "evidence": "obj-075.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL57.SHP and level075.wrd is the same 30x22 grid as level057.wrd (960x704 at 32px; 250 bytes differ — the battle's own height / blocking edits of the hall); the PAK has no level75.shp; winfail045 -> 75,75 and winfail075 -> 57,57 play on the same hall; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    76: {
        "map_level": 58,
        "evidence": "obj-076.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level076.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level76.shp and the EVEF places SID_ENEMY058 (the elf king) on the dais; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    77: {
        "map_level": 58,
        "evidence": "obj-077.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level077.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level77.shp and the EVEF places SID_ENEMY056 席德爾 on the dais; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    78: {
        "map_level": 58,
        "evidence": "obj-078.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level078.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level78.shp and the EVEF places SID_ENEMY058 (the elf king) on the dais; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    79: {
        "map_level": 58,
        "evidence": "obj-079.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level079.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level79.shp and the EVEF places SID_ENEMY057 (咕嚕's final form) with the elf king; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    81: {
        "map_level": 58,
        "evidence": "obj-081.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level081.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level81.shp; STORY081 (winfail076 -> 81,81) is the dying elf king's confession in the hall; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    82: {
        "map_level": 58,
        "evidence": "obj-082.obs 地圖管理員 (defProcIconBG) names SHAPE41\\LEVEL58.SHP and level082.wrd is the 30x22 throne-hall grid shared byte-for-byte by levels 76/77/78/79/81/82 (34 bytes differ from level058.wrd: height / blocking edits for the final battles); the PAK has no level82.shp; STORY082 (winfail077 -> 82,82) is 席德爾's death and the party's farewell in the hall; resource-derived from the obs record, the engine loader that reads it is not located (provisional)",
    },
    # end lane ch3
}


def map_alias(level: int) -> dict[str, Any] | None:
    return MAP_ALIASES.get(level)


def record_names(level: int) -> dict[str, str | list[str]]:
    code = f"{level:03d}"
    alias = map_alias(level)
    map_level = int(alias["map_level"]) if alias else level
    return {
        "story": f"@:\\data\\STORY{code}.TXT",
        "winfail": f"@:\\data\\winfail{code}.txt",
        "level": f"@:\\data\\level{code}.bin",
        "terrain": f"@:\\data\\level{code}.wrd",
        "object_header": f"@:\\data\\obj-{code}.h",
        # Optional per-level header naming the EVEF combined-object slots (cmb* defines).
        "level_header": f"@:\\data\\level{code}.h",
        "objects": f"@:\\data\\obj-{code}.obs",
        "map": [f"@:\\{folder}\\level{map_level:0{MAP_MEMBER_DIGITS}d}.shp" for folder in MAP_MEMBER_FOLDERS],
    }


def _map_manager_shape(objects: dict[str, Any]) -> str | None:
    """The obj-<code>.obs 地圖管理員 record (defProcIconBG) names the map shape the level
    loads (SHAPE01\\LEVEL08.SHP, ...); every level with a shape of its own names that
    shape here, and alias levels name the borrowed one (60/63 -> LEVEL58, 61/62/64 ->
    LEVEL55, 901 -> LEVEL08). Used as a consistency check on MAP_ALIASES."""
    for obj in objects.get("objects", []):
        if isinstance(obj, dict) and str(obj.get("obj_process_code") or "") == "defProcIconBG":
            return str(obj.get("obj_shape_name") or "") or None
    return None


def _included_object_header(story: dict[str, Any]) -> str | None:
    for include in story.get("includes", []):
        name = str(include)
        if name.lower().startswith("obj-") and name.lower().endswith(".h"):
            return f"@:\\data\\{name.lower()}"
    return None


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _integer(value: Any) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if not isinstance(value, str):
        return None
    try:
        return int(value.strip(), 0)
    except ValueError:
        return None


def _compact_script(metadata: dict[str, Any]) -> dict[str, Any]:
    sections: list[dict[str, Any]] = []
    for block in metadata.get("section_blocks", []):
        if not isinstance(block, dict):
            continue
        sections.append(
            {
                "index": int(block.get("index", 0)),
                "name": str(block.get("name", "")),
                "codes": list(block.get("codes", [])),
                "messages": list(block.get("messages", [])),
                "actions": list(block.get("actions", [])),
            }
        )
    return {
        "encoding": metadata.get("encoding"),
        "line_count": metadata.get("line_count"),
        "includes": metadata.get("includes", []),
        "section_counts": metadata.get("section_counts", {}),
        "action_counts": metadata.get("action_counts", {}),
        "resource_refs": metadata.get("resource_refs", []),
        "sections": sections,
    }


def _object_lookup(metadata: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for obj in metadata.get("objects", []):
        if not isinstance(obj, dict):
            continue
        code = _integer(obj.get("obj_code"))
        if code is not None:
            result[code] = obj
    return result


def _role_for_object(obj: dict[str, Any] | None) -> str:
    if obj is None:
        return "unmatched"
    process = str(obj.get("obj_process_code") or "")
    if process == "defProcPlayerInstall":
        return "player_install"
    if process == "defProcEnemy":
        return "enemy_object"
    if process == "defProcStandObject":
        return "map_object"
    if process in {"defProcBattleBOSS", "defProcIconBG", "defProcCursor", "defProcPlayerReversePos"}:
        return "battle_manager"
    return "other"


# EVEF records whose code has the top bit set reference a combined object: the
# level BIN carries a trailing table after the fixed records (offset list, then
# per entry a child count and [code, x, y] triples). LEVEL<code>.H names the slots
# (cmb樹和影01 = 0, ...). Child x/y are relative to the first child: the original
# installer 0x46bd67 places child 0 on the EVEF point and every other child at the
# same delta (static-derived); the table layout decodes consistently across the
# level BINs that carry it. Every child is installed as template `code & 0x7fffffff`
# (0x46bdc1); the top bit marks the chain head (+0x80 |= 0x40000000, 0x46bde1) and each
# child is linked under the one before it (0x45e485) — the head is what a
# mapobjWaterFall's parallax measures from (0x45ef11).
COMBINED_CODE_FLAG = 0x80000000
EVEF_HEADER_SIZE = 0x10
EVEF_RECORD_SIZE = 0xD0


def _combined_objects(level_data: bytes, evef: dict[str, Any], objects: dict[str, Any], level_header: dict[str, Any] | None) -> list[dict[str, Any]]:
    import struct

    body_end = EVEF_HEADER_SIZE + int(evef.get("record_count", 0)) * EVEF_RECORD_SIZE
    tail = level_data[body_end:]
    if len(tail) < 4:
        return []
    first_offset = struct.unpack_from("<I", tail, 0)[0]
    if first_offset % 4 or first_offset == 0 or first_offset > len(tail):
        raise ValueError(f"unexpected combined-object table header: first offset {first_offset} in {len(tail)} trailing bytes")
    offsets = struct.unpack_from(f"<{first_offset // 4}I", tail, 0)
    names: dict[int, str] = {}
    for symbol, value in (level_header or {}).get("define_values", {}).items():
        code = _integer(value)
        if code is not None:
            names[code] = str(symbol)
    lookup = _object_lookup(objects)
    result: list[dict[str, Any]] = []
    for index, offset in enumerate(offsets):
        count = struct.unpack_from("<I", tail, offset)[0]
        children: list[dict[str, Any]] = []
        for child_index in range(count):
            code, x, y = struct.unpack_from("<3I", tail, offset + 4 + child_index * 12)
            obj = lookup.get(code & ~COMBINED_CODE_FLAG)
            children.append(
                {
                    "child_index": child_index,
                    "object_code": code & ~COMBINED_CODE_FLAG,
                    **({"chain_head": True} if code & COMBINED_CODE_FLAG else {}),
                    "offset_xy_candidate": [x, y],
                    "join_status": "joined" if obj is not None else "unmatched",
                    "object_name": obj.get("obj_name") if obj else None,
                    "object_process": obj.get("obj_process_code") if obj else None,
                    "shape_resource": obj.get("obj_shape_name") if obj else None,
                    "role_from_process": _role_for_object(obj),
                    "object_data_fields": obj.get("obj_data_fields", {}) if obj else {},
                    **({"plane": obj.get("obj_plane")} if obj and obj.get("obj_process_code") == "defProcStandObject" else {}),
                }
            )
        result.append({"index": index, "symbol": names.get(index), "table_offset": offset, "child_count": count, "children": children})
    return result


def _signed32(value: Any) -> int:
    number = int(value or 0)
    return number - (1 << 32) if number >= (1 << 31) else number


# Actor EVEF instance override words (static-derived, 0x42bd50 actor branch for object
# processes 3 defProcPlayer / 5 defProcEnemy): record dwords 0x10..0x2C are compacted into
# the live record's eight item slots (+0x138); dwords 0x50 + 4*i are dispatched through the
# jump table 0x42c0a8 onto the live record. Index 15 sets object flag 0x4000, ai_fixed = 8
# and the object's fixed point (+0x46 x / +0x44 y pixels: hi16/lo16 & ~0x1f, + 0x10);
# indices 16/17 write 16-bit words. docs/evidence_packets/static_reverse/original_ai_navigation.md.
ACTOR_INSTANCE_PROCESSES = ("defProcPlayer", "defProcEnemy")
ACTOR_INSTANCE_ITEMS_OFFSET = 0x10
ACTOR_INSTANCE_OVERRIDES_OFFSET = 0x50
ACTOR_INSTANCE_OVERRIDE_COUNT = 0x20
ACTOR_INSTANCE_OVERRIDE_FIELDS = {
    0: "gold", 1: "find_type", 2: "find_flag", 3: "find_range", 4: "ai_call_range", 5: "ai_fixed",
    6: "ai_check_dying", 7: "ai_check_hp", 8: "ai_help_otherhp", 9: "ai_help_status", 10: "ai_help_attack",
    11: "ai_lock", 12: "ai_att_special", 13: "ai_att_magic", 14: "wait_round", 15: "fixed_point",
    16: "level_adjust_range", 17: "level_adjust_disp_range", 18: "weapon", 19: "armor", 20: "head",
    21: "foot", 22: "other1", 23: "other2", 24: "stamina",
}
ACTOR_INSTANCE_WORD_FIELDS = ("level_adjust_range", "level_adjust_disp_range")


def _fixed_point_cell(value: int) -> list[int]:
    x_pixels = ((value >> 16) & 0xFFE0) + 0x10
    y_pixels = (value & 0xFFE0) + 0x10
    return [x_pixels // 32, y_pixels // 32]


def _actor_instance(row: dict[str, Any]) -> dict[str, Any]:
    values = {int(w["field_offset"]): int(w["value"]) for w in row.get("non_zero_u32", []) if isinstance(w, dict)}
    items = [values[ACTOR_INSTANCE_ITEMS_OFFSET + 4 * i] for i in range(8) if values.get(ACTOR_INSTANCE_ITEMS_OFFSET + 4 * i)]
    overrides: dict[str, Any] = {}
    unknown: dict[str, int] = {}
    for index in range(ACTOR_INSTANCE_OVERRIDE_COUNT):
        value = values.get(ACTOR_INSTANCE_OVERRIDES_OFFSET + 4 * index)
        if not value:
            continue
        field = ACTOR_INSTANCE_OVERRIDE_FIELDS.get(index)
        if field is None:
            unknown[str(index)] = value
        elif field == "fixed_point":
            overrides[field] = _fixed_point_cell(value)
        elif field in ACTOR_INSTANCE_WORD_FIELDS:
            overrides[field] = value & 0xFFFF
        else:
            overrides[field] = _signed32(value)
    result: dict[str, Any] = {}
    if items:
        result["items"] = items
    if overrides:
        result["overrides"] = overrides
    if unknown:
        result["unknown_override_words"] = unknown
    return result


def _placements(evef: dict[str, Any], objects: dict[str, Any], combined: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    lookup = _object_lookup(objects)
    result: list[dict[str, Any]] = []
    for row in evef.get("record_summaries", []):
        if not isinstance(row, dict):
            continue
        code = _integer(row.get("field_0x04_code_candidate"))
        if code is None:
            continue
        obj = lookup.get(code)
        placement = {
            "record_index": int(row.get("index", 0)),
            "object_code": code,
            # Placements are signed 32-bit: level 3 installs its party off the west
            # edge at x = -64 / -96 / -128 (the raw u32 reads 0xFFFFFFC0...).
            "placement_xy_candidate": [
                _signed32(row.get("placement_x_candidate_0x08", 0)),
                _signed32(row.get("placement_y_candidate_0x0c", 0)),
            ],
            "join_status": "joined" if obj is not None else "unmatched",
            "object_name": obj.get("obj_name") if obj else None,
            "object_process": obj.get("obj_process_code") if obj else None,
            "shape_resource": obj.get("obj_shape_name") if obj else None,
            "role_from_process": _role_for_object(obj),
            "object_data_fields": obj.get("obj_data_fields", {}) if obj else {},
        }
        if obj is not None and obj.get("obj_process_code") == "defProcStandObject":
            # obj_Plane: the stand object's plane list (same-bucket order), with ATTACKFLAG its bucket.
            placement["plane"] = obj.get("obj_plane")
        if obj is not None and obj.get("obj_process_code") == "defProcTreasureBox":
            # The eight per-instance EVEF override words (record offsets 0x10..0x2C) are
            # the chest's item codes; the original copy compacts the non-zero words
            # (docs/evidence_packets/static_reverse/original_treasure.json, 0x42bd50).
            values = {int(w["field_offset"]): int(w["value"]) for w in row.get("non_zero_u32", []) if isinstance(w, dict)}
            placement["treasure_words"] = [values.get(0x10 + 4 * i, 0) for i in range(8)]
        if obj is not None and obj.get("obj_process_code") in ACTOR_INSTANCE_PROCESSES:
            instance = _actor_instance(row)
            if instance:
                placement["actor_instance"] = instance
        if obj is None and code & COMBINED_CODE_FLAG and combined is not None:
            slot = code & ~COMBINED_CODE_FLAG
            entry = combined[slot] if slot < len(combined) else None
            if entry is not None:
                placement.update(
                    {
                        "join_status": "joined",
                        "object_name": entry.get("symbol"),
                        "role_from_process": "combined_map_object",
                        "combined_object_index": slot,
                    }
                )
        result.append(placement)
    return result


def _script_object_entry(symbol: str, code: int | None, obj: dict[str, Any] | None, source: str | None) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "symbol": str(symbol),
        "object_code": code,
        "join_status": "joined" if obj is not None else "unmatched",
        "object_name": obj.get("obj_name") if obj else None,
        "object_process": obj.get("obj_process_code") if obj else None,
        "shape_resource": obj.get("obj_shape_name") if obj else None,
        "role_from_process": _role_for_object(obj),
        "object_data_fields": obj.get("obj_data_fields", {}) if obj else {},
    }
    if obj is not None:
        # obj_Shape_Number frames (1 = single image), obj_Plane token and, when the
        # record carries it, obj_Shape_Delay ticks between frames, read as written;
        # their engine timing is not inferred here.
        entry["shape_number"] = _integer(obj.get("obj_shape_number"))
        entry["plane"] = obj.get("obj_plane")
        if _integer(obj.get("obj_shape_delay")) is not None:
            entry["shape_delay"] = _integer(obj.get("obj_shape_delay"))
    if source is not None:
        entry["definition_source"] = source
    return entry


def _inserted_symbols(*scripts: dict[str, Any] | None) -> list[str]:
    """Symbols the STORY/WINFAIL scripts pass to actInsert*Object, in first-use order."""
    seen: list[str] = []
    for script in scripts:
        for block in (script or {}).get("section_blocks", []):
            for action in block.get("actions", []) if isinstance(block, dict) else []:
                for command in action.get("chain", []):
                    if str(command.get("name", "")).lower() in INSERT_ACTIONS and command.get("args"):
                        symbol = str(command["args"][0])
                        if symbol not in seen:
                            seen.append(symbol)
    return seen


def _script_objects(
    object_header: dict[str, Any],
    objects: dict[str, Any],
    inserted_symbols: list[str] | None = None,
    global_header: dict[str, Any] | None = None,
    global_objects: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Objects the level's STORY/WINFAIL scripts insert by header symbol (not EVEF-placed):
    every obj-<code>.h define, then the script-inserted OBJ-ALL.H symbols the level
    header does not define (joined to global.obs; obj_Story_PlayerN slots stay unmatched)."""
    lookup = _object_lookup(objects)
    result: list[dict[str, Any]] = []
    defines = object_header.get("define_values", {})
    for symbol, value in defines.items():
        code = _integer(value)
        result.append(_script_object_entry(symbol, code, lookup.get(code) if code is not None else None, None))
    if global_header is not None:
        global_defines = global_header.get("define_values", {})
        global_lookup = _object_lookup(global_objects or {})
        for symbol in inserted_symbols or []:
            if symbol in defines or symbol not in global_defines:
                continue
            code = _integer(global_defines[symbol])
            result.append(_script_object_entry(symbol, code, global_lookup.get(code) if code is not None else None, "OBJ-ALL.H/global.obs"))
    return result


def _encounter_script_objects(level: int, entries: list[dict[str, Any]], inserted_symbols: list[str]) -> list[dict[str, Any]]:
    """Encounter levels (501-578) have no obj-5NN.h: their STORY includes the engine-wide
    OBJ-ALL.H (598 UI / effect / slot objects), so only the symbols the level's scripts
    insert are kept (usually none — encounters place everything through the EVEF); other
    levels keep every header define (their headers are per level)."""
    if level not in ENCOUNTER_RANGE:
        return entries
    inserted = set(inserted_symbols)
    return [e for e in entries if e.get("symbol") in inserted]


def _global_symbols_used(object_header: dict[str, Any], inserted_symbols: list[str]) -> list[str]:
    defines = object_header.get("define_values", {})
    return [symbol for symbol in inserted_symbols if symbol not in defines and symbol.startswith("obj_")]


def _placed_role_counts(placements: list[dict[str, Any]]) -> dict[str, int]:
    result: dict[str, int] = {}
    for placement in placements:
        role = str(placement.get("role_from_process", "unmatched"))
        result[role] = result.get(role, 0) + 1
    return dict(sorted(result.items()))


def _read_records(pak: Path, requested: dict[str, str | list[str]]) -> dict[str, dict[str, Any]]:
    packages = find_decoded_paks_packages(pak)
    if not packages:
        raise ValueError(f"no PAKS container found at {pak}")
    result: dict[str, dict[str, Any]] = {}
    for key, members in requested.items():
        candidates = [members] if isinstance(members, str) else list(members)
        matches: list[tuple[dict[str, Any], dict[str, int | str]]] = []
        for member in candidates:
            for package in packages:
                record = find_paks_record_by_name(package["records"], member)
                if record is not None:
                    matches.append((package, record))
            if matches:
                break
        if not matches and key in OPTIONAL_RECORDS:
            continue
        if len(matches) != 1:
            raise ValueError(f"expected one PAK record for {candidates}, found {len(matches)}")
        package, record = matches[0]
        data = read_paks_record_bytes(
            package["path"],
            record,
            data_end_offset=int(package["paks"]["candidate_index_offset"]),
        )
        result[key] = {
            "data": data,
            "member": str(record["name"]),
            "length": len(data),
            "sha256": _sha(data),
            "package": Path(package["path"]).name,
        }
    return result


ENCOUNTER_RANGE = range(500, 600)


def _shared_alias_outputs(level: int, alias: dict[str, Any], terrain_sha: str, map_data: bytes, map_metadata: dict[str, Any]) -> dict[str, Path]:
    """Random-encounter levels (501-578) fight on a base level's map: obj-5NN.obs's 地圖管理員
    names the base shape and, for all but 525-527, level5NN.wrd is the base table byte for
    byte. When the base level's tracked terrain packet carries the same WRD sha256 and its
    tracked PNG has the same pixels, the encounter seed references those files instead of
    writing 50 KB / multi-megabyte duplicates. Only what matches is shared."""
    import tempfile

    shared: dict[str, Path] = {}
    base = alias.get("alias_of_level")
    if level not in ENCOUNTER_RANGE or base is None:
        return shared
    # The shape's own level number is the first owner candidate; a main level whose obs
    # names that same shape (MAP_ALIASES map_level, e.g. level 33 fights on Level32.SHP)
    # tracks the identical pixels under its own folder, so 549-551 share battle033/level33.png.
    owners = [int(base)] + [owner for owner, spec in MAP_ALIASES.items()
                           if spec.get("map_level") == int(base) and owner not in ENCOUNTER_RANGE]
    for owner in owners:
        owner_paths = paths_for_level(owner)
        if "terrain" not in shared and owner_paths["terrain"].is_file():
            tracked = json.loads(owner_paths["terrain"].read_text(encoding="utf-8"))
            if tracked.get("source", {}).get("sha256") == terrain_sha:
                shared["terrain"] = owner_paths["terrain"]
        if "map" not in shared and owner_paths["map"].is_file():
            with tempfile.TemporaryDirectory() as folder:
                candidate = Path(folder) / owner_paths["map"].name
                write_shp_preview(map_data, map_metadata, candidate)
                with Image.open(candidate) as fresh, Image.open(owner_paths["map"]) as tracked_png:
                    if fresh.size == tracked_png.size and fresh.convert("RGBA").tobytes() == tracked_png.convert("RGBA").tobytes():
                        shared["map"] = owner_paths["map"]
    return shared


def build(level: int, pak: Path, seed_path: Path, terrain_path: Path | None, map_path: Path | None) -> dict[str, Any]:
    requested = record_names(level)
    requested.pop("map")
    records = _read_records(pak, requested)
    # The original OBS loader reads obj_Shape_Name before resolving the shape.
    # Select that exact archive path, including its folder; neither same-basename
    # search nor a manually registered level alias may override the source.
    objects = parse_text_metadata(records["objects"]["data"])
    records.update(_read_records(pak, {"map": source_map_member(objects)}))
    story = parse_text_metadata(records["story"]["data"])
    winfail = parse_text_metadata(records["winfail"]["data"]) if "winfail" in records else None
    if "object_header" not in records:
        included = _included_object_header(story)
        if included is None:
            raise ValueError(f"level {level} has neither obj-{level:03d}.h nor an OBJ-*.H include in its STORY script")
        records["object_header"] = _read_records(pak, {"object_header": included})["object_header"]
    object_header = parse_text_metadata(records["object_header"]["data"])
    level_header = parse_text_metadata(records["level_header"]["data"]) if "level_header" in records else None
    inserted_symbols = _inserted_symbols(story, winfail)
    global_header = global_objects = None
    if _global_symbols_used(object_header, inserted_symbols):
        records.update(_read_records(pak, dict(GLOBAL_RECORDS)))
        global_header = parse_text_metadata(records["global_object_header"]["data"])
        global_objects = parse_text_metadata(records["global_objects"]["data"])
    evef = parse_evef(records["level"]["data"], summary_limit=None)
    combined = _combined_objects(records["level"]["data"], evef, objects, level_header)
    map_metadata = parse_shp(records["map"]["data"])
    terrain = decode_wrd(records["terrain"]["data"])
    placements = _placements(evef, objects, combined)

    terrain["source"] = {
        "member": records["terrain"]["member"],
        "byte_length": records["terrain"]["length"],
        "sha256": records["terrain"]["sha256"],
        "storage_policy": "raw PAK record remains outside tracked project data",
    }
    alias = alias_metadata(level, records["map"]["member"], map_alias(level))
    defaults = paths_for_level(level)
    shared = _shared_alias_outputs(level, alias, records["terrain"]["sha256"], records["map"]["data"], map_metadata) if terrain_path is None or map_path is None else {}
    if terrain_path is None:
        terrain_path = shared.get("terrain", defaults["terrain"])
    if map_path is None:
        map_path = shared.get("map", defaults["map"])
    if "terrain" not in shared:
        terrain_path.parent.mkdir(parents=True, exist_ok=True)
        terrain_path.write_text(json.dumps(terrain, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if "map" not in shared:
        map_path.parent.mkdir(parents=True, exist_ok=True)
        write_shp_preview(records["map"]["data"], map_metadata, map_path)  # keeps the tracked bytes when the pixels match
    with Image.open(map_path) as image:
        image_size = list(image.size)

    terrain_width = int(terrain["source_format"]["width"])
    terrain_height = int(terrain["source_format"]["height"])
    map_width = int(map_metadata["width"])
    map_height = int(map_metadata["height"])
    cell_candidate = [
        map_width // terrain_width if terrain_width and map_width % terrain_width == 0 else None,
        map_height // terrain_height if terrain_height and map_height % terrain_height == 0 else None,
    ]

    source_records = {
        key: {
            "member": value["member"],
            "package": value["package"],
            "byte_length": value["length"],
            "sha256": value["sha256"],
        }
        for key, value in records.items()
    }
    seed = {
        "schema": "hsl_battle_seed.v1",
        "level": level,
        "level_code": f"{level:03d}",
        "level_kind": "battle" if winfail is not None else "story",
        "level_kind_claim_limit": "Presence of a winfail script marks a battle level; absence marks a story-only level whose flow is driven by STORY actions alone.",
        "evidence_tier": "resource-derived",
        "source_policy": "compact derived facts only; original PAK records remain outside the repository",
        "sources": source_records,
        "map": {
            "source_size": [map_width, map_height],
            **alias,
            **({"shared_png_of_level": int(alias["alias_of_level"])} if "map" in shared else {}),
            "decoded_png": "res://" + map_path.as_posix(),
            "decoded_png_size": image_size,
            "decoded_png_sha256": png_sha256(map_path),
            "rows_decode": bool(map_metadata.get("all_rows_decode", False)),
        },
        "terrain": {
            "packet": "res://" + terrain_path.as_posix(),
            **({"shared_packet_of_level": int(alias["alias_of_level"])} if "terrain" in shared else {}),
            "grid_size": [terrain_width, terrain_height],
            "tile_count": int(terrain["stats"]["tile_count"]),
            "blocking_count": int(terrain["stats"]["blocking_count"]),
            "cell_size_from_map_division_candidate": cell_candidate,
            "cell_size_candidate_status": (
                "dimension-consistent" if None not in cell_candidate else "not-integral"
            ),
            "cell_size_claim_limit": "Map/WRD dimensions support a grid-size candidate only; they do not independently prove native hit testing or movement semantics.",
        },
        "placements": {
            "evef_record_count": int(evef.get("record_count", 0)),
            "non_zero_record_count": int(evef.get("non_zero_record_count", 0)),
            "role_counts_from_object_process": _placed_role_counts(placements),
            "records": placements,
            "claim_limit": "EVEF x/y fields are resource-derived placement candidates; object process identifies object class, not final faction/control semantics or post-opening position.",
        },
        "object_header": {
            "defines": object_header.get("define_values", {}),
        },
        "script_objects": _encounter_script_objects(level, _script_objects(object_header, objects, inserted_symbols, global_header, global_objects), inserted_symbols),
        "scripts": {
            "story": _compact_script(story),
            "winfail": _compact_script(winfail) if winfail is not None else None,
            "claim_limit": "Action names, order and arguments are source script structure; their engine-side timing/effects are not inferred beyond explicit action tokens.",
        },
    }
    if combined:
        # Only levels whose BIN carries the trailing table get these keys, so
        # seeds of levels without combined objects stay byte-identical.
        seed["level_header"] = {"defines": level_header.get("define_values", {}) if level_header else {}}
        seed["combined_objects"] = {
            "table_byte_length": len(records["level"]["data"]) - (EVEF_HEADER_SIZE + int(evef.get("record_count", 0)) * EVEF_RECORD_SIZE),
            "entries": combined,
            "claim_limit": "Trailing level BIN table decoded as offset list + [count, (code,x,y)...]; slot names come from LEVEL<code>.H. Child x/y are relative to the first child, which the installer 0x46bd67 places on the EVEF point (static-derived); placements with the 0x80000000 flag join by slot index (provisional).",
        }
    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(json.dumps(seed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return seed


def check(level: int, seed_path: Path, terrain_path: Path | None, map_path: Path | None) -> str:
    seed = json.loads(seed_path.read_text(encoding="utf-8"))
    check_seed_binding(seed, reviewed_bindings())
    # Encounter seeds may reference their base level's tracked terrain / PNG (shared_*_of_level).
    if terrain_path is None:
        terrain_path = Path(str(seed["terrain"]["packet"]).removeprefix("res://"))
    if map_path is None:
        map_path = Path(str(seed["map"]["decoded_png"]).removeprefix("res://"))
    terrain = json.loads(terrain_path.read_text(encoding="utf-8"))
    assert seed["schema"] == "hsl_battle_seed.v1"
    assert int(seed["level"]) == level
    assert seed.get("level_kind", "battle") == ("battle" if seed["scripts"].get("winfail") is not None else "story")
    assert seed["terrain"]["packet"] == "res://" + terrain_path.as_posix()
    assert seed["map"]["decoded_png"] == "res://" + map_path.as_posix()
    assert png_sha256(map_path) == seed["map"]["decoded_png_sha256"]
    assert terrain["source"]["sha256"] == seed["sources"]["terrain"]["sha256"]
    assert terrain["source_format"]["width"] == seed["terrain"]["grid_size"][0]
    assert terrain["source_format"]["height"] == seed["terrain"]["grid_size"][1]
    with Image.open(map_path) as image:
        assert list(image.size) == seed["map"]["decoded_png_size"] == seed["map"]["source_size"]
    cell = seed["terrain"]["cell_size_from_map_division_candidate"]
    if seed["terrain"]["cell_size_candidate_status"] == "dimension-consistent":
        assert seed["map"]["source_size"] == [
            seed["terrain"]["grid_size"][0] * cell[0],
            seed["terrain"]["grid_size"][1] * cell[1],
        ]
    assert all(record["join_status"] == "joined" for record in seed["placements"]["records"])
    return "BATTLE_SEED_CHECK_PASS level={} placements={} map={}x{} terrain={}x{}".format(
        level,
        len(seed["placements"]["records"]),
        *seed["map"]["source_size"],
        *seed["terrain"]["grid_size"],
    )


class BattleSeedTask(Task):
    """check: the tracked seed, terrain packet and map PNG agree with each other and with the
    reviewed map bindings (no PAK needed); generate: rebuild them from the original hsl.pak.
    Encounter levels (501-578) resolve terrain / map to their base level's tracked files when
    identical (build) or to the paths the seed records (check); other levels keep their own."""
    family = 'battle_seed'

    def __init__(self, level: int, seed: Path | None = None, terrain: Path | None = None, map_path: Path | None = None) -> None:
        self.level = level
        self.name = f'battle_seed:{level}'
        defaults = paths_for_level(level)
        encounter = level in ENCOUNTER_RANGE
        self.seed_path = seed or defaults['seed']
        self.terrain_path = terrain or (None if encounter else defaults['terrain'])
        self.map_path = map_path or (None if encounter else defaults['map'])
        self.outputs = tuple(path.as_posix() for path in (self.seed_path, self.terrain_path, self.map_path) if path is not None)
        self.inputs = ('docs/evidence_packets/static_reverse/original_map_binding.json',)
        self.replaces = (f'tools/hsl_battle_seed.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/seed.py', 'tools/hsltools/checks/source_map_binding.py', 'tools/hsltools/sources/scripts.py', 'tools/hsltools/sources/wrd.py')

    def check(self, ctx: Context) -> str:
        return check(self.level, self.seed_path, self.terrain_path, self.map_path)

    def generate(self, ctx: Context) -> str:
        pak = original_pak(ctx)
        if not pak.is_file():
            raise NotGeneratable(f'{self.name}: original PAK not found at {pak}')
        seed = build(self.level, pak, self.seed_path, self.terrain_path, self.map_path)
        return "BATTLE_SEED_BUILD_PASS level={} placements={} map={} terrain={}".format(
            self.level,
            len(seed["placements"]["records"]),
            str(seed["map"]["decoded_png"]).removeprefix("res://"),
            str(seed["terrain"]["packet"]).removeprefix("res://"),
        )


def tasks() -> list[BattleSeedTask]:
    return [BattleSeedTask(level) for level in imported_levels()]
