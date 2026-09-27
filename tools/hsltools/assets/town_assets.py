"""Town dialogue assets for the menu-style town: RESOURCE.TXT texts for every message,
name and menu label TOWNDEF.TXT references, plus the FACE*.SHP portraits its
teShapeMessage / teCheckMoney / teSecretManBuyThing tokens name.

Inputs are the tracked towndef.json (hsltools.data.world_map) and the original PAK.
Outputs (content/imported/hsl/global/world_map/):
  town_messages.json   hsl_town_message_text.v1 — messages {id: text}, speaker names for
                       SID_* player tokens (extras.h slot -> PLAYERS name), shape-message
                       name ids and show_name ids, all resolved from RESOURCE.TXT [name].
  town_shop_items.json hsl_town_shop_items.v1 — ITEM.TXT code/name/cost/type/icon/important (all 239)
                       so shop menus can list the TOWNDEF [item] tables with prices.
  town_portraits.json  hsl_actor_portraits.v1-compatible {"actors": {"face_0062": {...}}}
                       so BattleDialogue.configure_portraits can load it directly;
                       PNGs under previews/faces/.
Resource-derived text and pixels; which portrait the original shows for a player
speaker is read from PLAYERS.TXT's picture column (its runtime lookup is not proven).

Registry task town_assets (family assets): outputs town_messages / town_portraits /
town_shop_items.json and previews/faces/ in content/imported/hsl/global/world_map/. Its check
keeps the script's two modes: rebuild-and-compare when the original install is present
(ctx.original_exe's directory), offline consistency otherwise. Bodies moved verbatim from the former hsl_town_assets.py (ROOT resolved from this file's depth).
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from hsltools.data.world_map import DEFAULT_OUTPUT_DIR, DEFAULT_PAK_ROOT, MEMBERS, PakReader, _sha, render_shp_png
from hsltools.registry import Context, NotGeneratable, ScriptCheckTask
from hsltools.sources.shp import png_sha256

ROOT = Path(__file__).resolve().parents[3]

MESSAGES_NAME = "town_messages.json"
PORTRAITS_NAME = "town_portraits.json"
SHOP_ITEMS_NAME = "town_shop_items.json"
SHOP_SCHEMA = "hsl_town_shop_items.v1"
ITEM_TXT = ROOT / "content/imported/hsl/global/tables/ITEM.TXT"
TYPE_H = ROOT / "content/imported/hsl/global/tables/TYPE.H"
FACES_DIR = "previews/faces"
MESSAGE_SCHEMA = "hsl_town_message_text.v1"
PORTRAITS_SCHEMA = "hsl_actor_portraits.v1"
PLAYERS_MEMBER = "@:\\data\\PLAYERS.TXT"
FACE_RE = re.compile(r"^SHAPE\\FACE(\d{4})\.SHP$", re.IGNORECASE)


def _parse_name_table(data: bytes) -> dict[str, str]:
    from hsltools.sources.tables import parse_table

    return parse_table(data)


def _players_by_name(players_text: str, names: dict[str, str], resource_h_names: dict[str, int]) -> dict[str, dict[str, Any]]:
    """PLAYERS.TXT rows keyed by their resolved display name (name field = resource id or resource.h name_N)."""
    rows: dict[str, dict[str, Any]] = {}
    current: dict[str, Any] | None = None
    index = 0
    for raw_line in players_text.splitlines():
        line = raw_line.split(";")[0].strip()
        if not line:
            continue
        if line.startswith("["):
            index += 1
            current = {"row": index}
            continue
        if current is None or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        current[key] = value
        if key == "picture":
            name_field = str(current.get("name", ""))
            if name_field.isdigit():
                text = names.get(name_field, "")
            elif name_field in resource_h_names:
                text = names.get(str(resource_h_names[name_field]), "")
            else:
                text = ""
            if text and text not in rows:
                rows[text] = {"row": index, "picture": value, "name_field": name_field}
    return rows


def shop_items(names: dict[str, str]) -> dict[str, Any]:
    """ITEM.TXT code/name/cost/type/icon/important for the whole 239-item table (resource-derived; the
    tracked table is the same member the equipment generator reads). Selling prices are not in the table."""
    from hsltools.sources.tables import blocks

    constants = {key: int(value, 0) for key, value in re.findall(r"^\s*#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b", TYPE_H.read_bytes().decode("cp950"), re.M)}
    items: dict[str, Any] = {}
    for row in blocks(ITEM_TXT.read_bytes(), "item"):
        items[str(int(row["code"]))] = {
            "name": names.get(str(row.get("name", "")), ""),
            "name_resource_id": int(row["name"]) if str(row.get("name", "")).isdigit() else None,
            "cost": int(row.get("cost", 0)),
            "type": str(row.get("type", "")),
            "type_code": constants.get(str(row.get("type", "")), -1),
            "icon": str(row.get("icon", "")),
            "important": int(row.get("important", 0)) != 0,
        }
    return items


# RESOURCE.TXT ids the shop engine code (hsl01.exe 0x414c00, docs/evidence_packets/static_reverse/
# original_shop_transaction.md) shows without any TOWNDEF script naming them: 606 "not enough
# money" (0x415611, message 0x25e) and 607 "this shop does not buy that" (0x4153c2, 0x25f).
ENGINE_MESSAGE_IDS = (606, 607)


def referenced_ids(towndef: dict[str, Any]) -> dict[str, Any]:
    """Message ids, show_name ids, shape-message name ids, face members and SID_* tokens TOWNDEF references."""
    positions: dict[str, list[int]] = {k: v for k, v in towndef.get("message_id_argument_positions", {}).items() if isinstance(v, list)}
    shape_name_positions = {"teShapeMessage": 1, "teCheckMoney": 2, "teSecretManBuyThing": 1}
    shape_file_positions = {"teShapeMessage": 0, "teCheckMoney": 1, "teSecretManBuyThing": 0}
    message_ids: set[int] = set(ENGINE_MESSAGE_IDS)
    name_ids: set[int] = set()
    faces: set[str] = set()
    player_tokens: set[str] = set()
    for event in towndef.get("town_events", []):
        show = event.get("show_name") or {}
        if isinstance(show, dict) and str(show.get("resource_id", "")).lstrip("-").isdigit():
            name_ids.add(int(show["resource_id"]))
        for command in event.get("events", []):
            token = str(command.get("token", ""))
            args = [str(a) for a in command.get("args", [])]
            for position in positions.get(token, []):
                if position < len(args) and args[position].lstrip("-").isdigit() and int(args[position]) > 0:
                    message_ids.add(int(args[position]))
            if token == "teSelectInsertEvent":
                for position in range(2, len(args), 2):
                    if args[position].lstrip("-").isdigit() and int(args[position]) > 0:
                        message_ids.add(int(args[position]))
            if token in shape_name_positions and shape_name_positions[token] < len(args) and args[shape_name_positions[token]].isdigit():
                name_ids.add(int(args[shape_name_positions[token]]))
            if token in shape_file_positions and shape_file_positions[token] < len(args) and FACE_RE.match(args[shape_file_positions[token]]):
                faces.add(args[shape_file_positions[token]].upper())
            if token in ("tePlayerMessage", "teSelectInsertEvent") and args and args[0].startswith("SID_"):
                player_tokens.add(args[0])
    return {"message_ids": sorted(message_ids), "name_ids": sorted(name_ids), "faces": sorted(faces), "player_tokens": sorted(player_tokens)}


def build(pak_root: Path, output_dir: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, bytes], dict[str, Any]]:
    towndef = json.loads((output_dir / "towndef.json").read_text(encoding="utf-8"))
    reader = PakReader(pak_root)
    resource_raw = reader.read(MEMBERS["resource_txt"])
    names = _parse_name_table(resource_raw)
    players_raw = reader.read(PLAYERS_MEMBER)
    resource_h_raw = reader.read("@:\\data\\resource.h")
    resource_h_names: dict[str, int] = {}
    for match in re.finditer(r"^\s*#define\s+(name_\d+)\s+(\d+)", resource_h_raw.decode("cp950", "replace"), re.M):
        resource_h_names[match.group(1)] = int(match.group(2))
    players = _players_by_name(players_raw.decode("cp950", "replace"), names, resource_h_names)
    refs = referenced_ids(towndef)
    symbols: dict[str, Any] = towndef.get("symbols", {})

    messages: dict[str, str] = {}
    missing: list[int] = []
    for message_id in refs["message_ids"] + refs["name_ids"]:
        text = names.get(str(message_id))
        if text is None:
            missing.append(message_id)
        else:
            messages[str(message_id)] = text

    # SID_* player tokens: extras.h slot -> the PLAYERS row whose name matches the
    # token's suffix (the slot->character table at runtime is party state, not static).
    speakers: dict[str, Any] = {}
    for token in refs["player_tokens"]:
        display = token[len("SID_"):]
        row = players.get(display)
        speakers[token] = {
            "slot": symbols.get(token),
            "name_text": display,
            "players_row": row["row"] if row else None,
            "picture": row["picture"] if row else None,
            "portrait_key": f"face_{int(FACE_RE.match(row['picture']).group(1)):04d}" if row and FACE_RE.match(row["picture"]) else None,
            "policy": "extras.h SID slot; portrait from the PLAYERS.TXT row whose resolved name equals the token suffix (provisional: the runtime slot->character table is party state)",
        }
    faces = set(refs["faces"])
    for speaker in speakers.values():
        if speaker["picture"] and FACE_RE.match(speaker["picture"]):
            faces.add(speaker["picture"].upper())

    portraits: dict[str, Any] = {}
    previews: dict[str, bytes] = {}
    for face in sorted(faces):
        number = int(FACE_RE.match(face).group(1))
        key = f"face_{number:04d}"
        member = "@:\\" + face
        rel = f"{FACES_DIR}/{key}.png"
        found = reader.find(member)
        if found is None:
            portraits[key] = {"source_member": face, "res_path": None, "decode_error": "missing_from_pak"}
            continue
        raw = reader.read(member)
        try:
            meta, png = render_shp_png(raw)
        except Exception as error:  # record, never fabricate pixels
            portraits[key] = {"source_member": face, "res_path": None, "source_sha256": _sha(raw), "decode_error": f"{type(error).__name__}: {error}"}
            continue
        previews[rel] = png
        portraits[key] = {
            "source_member": face,
            "res_path": f"res://content/imported/hsl/global/world_map/{rel}",
            "width": meta["width"],
            "height": meta["height"],
            "source_sha256": _sha(raw),
            "png_sha256": png_sha256(png),
        }

    town_messages = {
        "schema": MESSAGE_SCHEMA,
        "evidence_tier": "resource-derived",
        "source_policy": "Original RESOURCE.TXT [name] table decoded as cp950 with colour controls removed and line breaks preserved; ids come from the tracked towndef.json (te message / name / show_name arguments) plus the shop engine messages ENGINE_MESSAGE_IDS (606/607, static-derived from hsl01.exe 0x414c00).",
        "sources": {
            "resource_txt": {"member": MEMBERS["resource_txt"], "byte_length": len(resource_raw), "sha256": _sha(resource_raw)},
            "players_txt": {"member": PLAYERS_MEMBER, "byte_length": len(players_raw), "sha256": _sha(players_raw)},
            "towndef_json": {"sha256": _sha((output_dir / "towndef.json").read_bytes())},
        },
        "messages": messages,
        "speakers": speakers,
        "counts": {"message_ids": len(refs["message_ids"]), "name_ids": len(refs["name_ids"]), "resolved": len(messages), "missing": len(missing), "speakers": len(speakers)},
        "missing_ids": missing,
        "unresolved_semantics": [
            "if_wait arguments and message pacing are not modelled here",
            "player speaker portraits follow PLAYERS.TXT picture by name match; the original slot->character lookup is party state",
        ],
    }
    town_portraits = {
        "schema": PORTRAITS_SCHEMA,
        "evidence_tier": "resource-derived",
        "actors": portraits,
        "presentation": "Original FACE*.SHP pixels named by TOWNDEF te tokens; dialogue-view placement is remake presentation.",
        "counts": {"faces": len(portraits), "decoded": sum(1 for p in portraits.values() if p.get("res_path"))},
    }
    shop_table = shop_items(names)
    shop_ids: set[int] = set()
    for table in towndef.get("items", []):
        for item_id in table.get("item_ids", []):
            shop_ids.add(int(item_id))
    town_shop = {
        "schema": SHOP_SCHEMA,
        "evidence_tier": "resource-derived",
        "source_policy": "ITEM.TXT code/name/cost/type/icon/important with names resolved through RESOURCE.TXT; TOWNDEF [item] tables reference these codes. Sell prices are not in the table (provisional if the remake offers selling).",
        "sources": {"item_txt": {"path": ITEM_TXT.relative_to(ROOT).as_posix(), "sha256": _sha(ITEM_TXT.read_bytes())}},
        "items": shop_table,
        "counts": {"items": len(shop_table), "referenced_by_shops": len(shop_ids), "missing_from_table": sorted(i for i in shop_ids if str(i) not in shop_table)},
    }
    return town_messages, town_portraits, previews, town_shop


def write_outputs(output_dir: Path, messages: dict[str, Any], portraits: dict[str, Any], previews: dict[str, bytes], shop: dict[str, Any]) -> None:
    (output_dir / MESSAGES_NAME).write_text(json.dumps(messages, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / PORTRAITS_NAME).write_text(json.dumps(portraits, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / SHOP_ITEMS_NAME).write_text(json.dumps(shop, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for rel, png in previews.items():
        target = output_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(png)


def check_offline(output_dir: Path) -> list[str]:
    issues: list[str] = []
    try:
        messages = json.loads((output_dir / MESSAGES_NAME).read_text(encoding="utf-8"))
        portraits = json.loads((output_dir / PORTRAITS_NAME).read_text(encoding="utf-8"))
        shop = json.loads((output_dir / SHOP_ITEMS_NAME).read_text(encoding="utf-8"))
        towndef = json.loads((output_dir / "towndef.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read outputs: {error}"]
    if shop.get("schema") != SHOP_SCHEMA:
        issues.append("town_shop_items schema mismatch")
    for table in towndef.get("items", []):
        for item_id in table.get("item_ids", []):
            if str(int(item_id)) not in shop.get("items", {}):
                issues.append(f"shop item {item_id} (table {table.get('code')}) missing from town_shop_items.json")
    if shop.get("counts", {}).get("missing_from_table"):
        issues.append(f"shop items missing from ITEM.TXT: {shop['counts']['missing_from_table']}")
    if messages.get("schema") != MESSAGE_SCHEMA:
        issues.append("town_messages schema mismatch")
    if portraits.get("schema") != PORTRAITS_SCHEMA:
        issues.append("town_portraits schema mismatch")
    refs = referenced_ids(towndef)
    wanted = {str(i) for i in refs["message_ids"] + refs["name_ids"]}
    have = set(messages.get("messages", {}).keys()) | {str(i) for i in messages.get("missing_ids", [])}
    if wanted - have:
        issues.append(f"message ids referenced by towndef.json but absent from town_messages.json: {sorted(wanted - have)[:10]}")
    if messages.get("missing_ids"):
        issues.append(f"unresolved message ids: {messages['missing_ids']}")
    for key, entry in portraits.get("actors", {}).items():
        res_path = entry.get("res_path")
        if not res_path:
            issues.append(f"portrait {key} not decoded: {entry.get('decode_error')}")
            continue
        png = output_dir / res_path.replace("res://content/imported/hsl/global/world_map/", "")
        if not png.is_file():
            issues.append(f"portrait png missing: {png}")
        elif png_sha256(png) != entry.get("png_sha256"):
            issues.append(f"portrait png sha mismatch: {key}")
    for token, speaker in messages.get("speakers", {}).items():
        if speaker.get("portrait_key") and speaker["portrait_key"] not in portraits.get("actors", {}):
            issues.append(f"speaker {token} portrait {speaker['portrait_key']} missing")
    return issues


def check(output_dir: Path, pak_root: Path) -> int:
    issues = check_offline(output_dir)
    if pak_root.exists():
        messages, portraits, previews, shop = build(pak_root, output_dir)
        if json.loads((output_dir / SHOP_ITEMS_NAME).read_text(encoding="utf-8")) != shop:
            issues.append("town_shop_items.json differs from a rebuild")
        current_messages = json.loads((output_dir / MESSAGES_NAME).read_text(encoding="utf-8"))
        current_portraits = json.loads((output_dir / PORTRAITS_NAME).read_text(encoding="utf-8"))
        if current_messages != messages:
            issues.append("town_messages.json differs from a rebuild")
        if current_portraits != portraits:
            issues.append("town_portraits.json differs from a rebuild")
        for rel, png in previews.items():
            target = output_dir / rel
            if not target.is_file() or target.read_bytes() != png:
                issues.append(f"preview differs from a rebuild: {rel}")
        mode = "rebuild"
    else:
        mode = "offline"
    if issues:
        for issue in issues:
            print(f"TOWN_ASSETS_CHECK_FAIL {issue}")
        return 1
    current = json.loads((output_dir / MESSAGES_NAME).read_text(encoding="utf-8"))
    print(f"TOWN_ASSETS_CHECK_PASS mode={mode} messages={len(current.get('messages', {}))} speakers={len(current.get('speakers', {}))}")
    return 0


class TownAssetsTask(ScriptCheckTask):
    name = 'town_assets'
    family = 'assets'
    inputs = (ITEM_TXT.relative_to(ROOT).as_posix(), TYPE_H.relative_to(ROOT).as_posix(),
              (DEFAULT_OUTPUT_DIR / 'towndef.json').relative_to(ROOT).as_posix())
    outputs = tuple((DEFAULT_OUTPUT_DIR / name).relative_to(ROOT).as_posix() for name in (MESSAGES_NAME, PORTRAITS_NAME, SHOP_ITEMS_NAME)) + (
        (DEFAULT_OUTPUT_DIR / FACES_DIR).relative_to(ROOT).as_posix() + '/',)
    replaces = ('tools/hsl_town_assets.py --check',)
    scripts = ('tools/hsltools/assets/town_assets.py', 'tools/hsltools/data/world_map.py')

    def verify(self, ctx: Context) -> None:
        if check(DEFAULT_OUTPUT_DIR, ctx.original_exe.parent) != 0:
            raise ValueError('town assets differ from the tracked outputs (TOWN_ASSETS_CHECK_FAIL lines above)')

    def build(self, ctx: Context) -> None:
        pak_root = ctx.original_exe.parent
        if not pak_root.exists():
            raise NotGeneratable(f'{self.name}: original install not found at {pak_root}')
        messages, portraits, previews, shop = build(pak_root, DEFAULT_OUTPUT_DIR)
        write_outputs(DEFAULT_OUTPUT_DIR, messages, portraits, previews, shop)


def tasks() -> list[TownAssetsTask]:
    return [TownAssetsTask()]
