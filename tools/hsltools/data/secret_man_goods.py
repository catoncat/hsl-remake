"""Compile the original tavern secret man's goods table (teSecretManBuyThing).

hsl01.exe 0x454e20 case 0x27 (te token 39) prices the "神秘的禮物" from a .data table
at 0x4793b0: nine rows of one int32 price followed by fifteen int16 item codes
(row stride 0x22), indexed by the purchase counter 0x4c1bd4 (0..8). The same
counter picks the pitch event from the nine int16 table at 0x479398. Without the
EXE the tracked output is cross-checked offline: prices strictly increase and
equal the "$N" in pitch messages 1608..1616, every code exists in ITEM.TXT. With
--exe the table bytes are re-read from the SHA-locked image and must match.
Static reading only: docs/evidence_packets/static_reverse/original_secret_man.md.

Registry task secret_man_goods (family static, OriginalArchiveTask over hsl01.exe): tracked output
content/generated/hsl/static/hsl01/secret_man_goods.json; check = the script's --check (offline cross-checks, plus the
EXE bytes when present), generate re-reads the table from the EXE. Bodies moved verbatim from the former hsl_secret_man_goods.py.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import struct

from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ORIGINAL_EXE, ROOT
from hsltools.registry import Context
from hsltools.sources.tables import TABLES, blocks

OUTPUT = ROOT / "content/generated/hsl/static/hsl01/secret_man_goods.json"
TOWN_MESSAGES = ROOT / "content/imported/hsl/global/world_map/town_messages.json"
DEFAULT_EXE = ORIGINAL_EXE
SCHEMA = "hsl_secret_man_goods.v1"
TABLE_ADDRESS = 0x4793B0
ROW_STRIDE = 0x22
ROWS = 9
SLOTS = 15
EVENTS_ADDRESS = 0x479398
# teAppearSecretMan's event per counter value; the pitch message each event shows.
PITCH_MESSAGE_IDS = (1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615, 1616)


def read_table(executable: Path) -> tuple[list[dict], list[int]]:
    base, mapped = image(executable.read_bytes())
    rows = []
    for index in range(ROWS):
        offset = TABLE_ADDRESS - base + index * ROW_STRIDE
        price = struct.unpack_from("<i", mapped, offset)[0]
        items = list(struct.unpack_from("<%dh" % SLOTS, mapped, offset + 4))
        rows.append({"index": index, "price": price, "items": items})
    events = list(struct.unpack_from("<%dh" % ROWS, mapped, EVENTS_ADDRESS - base))
    return rows, events


def payload(rows: list[dict], events: list[int]) -> dict:
    for row, event, pitch in zip(rows, events, PITCH_MESSAGE_IDS):
        row["event"] = event
        row["pitch_message_id"] = pitch
    return {
        "schema": SCHEMA,
        "evidence_tier": "static-derived",
        "exe_sha256": EXE_SHA,
        "source": {
            "handler": "hsl01.exe 0x454e20 case 0x27 (teSecretManBuyThing, te token 39)",
            "table_address": hex(TABLE_ADDRESS), "row_stride": ROW_STRIDE, "rows": ROWS, "slots": SLOTS,
            "events_address": hex(EVENTS_ADDRESS), "counter_global": "0x4c1bd4",
            "packet": "docs/evidence_packets/static_reverse/original_secret_man.md",
        },
        "rows": rows,
        "rules": {
            "price_check": "gold (0x4c1bcc) < row.price -> face message [fail msg], then jump to [fail event] when non-zero",
            "pick": "n = count of non-zero slots; item = items[rand(n)] (positional; duplicates weigh twice)",
            "grant": "important item -> 0x44ef70(item, 1) list, else 0x44f100(item, 1) list (the teGetItem split); message 1621 獲得 + item name",
            "counter": "0x4c1bd4 += 1 while < 8; zeroed by the new-game initialiser 0x42c7e0, saved by 0x42e070 / loaded by 0x42e640",
        },
        "claim_limit": "Static reading of the VM case, no bounded execution; rand(n) is the original global RNG, the remake samples its own.",
    }


def offline_issues(data: dict) -> list[str]:
    issues = []
    if data.get("schema") != SCHEMA or data.get("exe_sha256") != EXE_SHA:
        issues.append("schema or EXE identity differs")
    rows = data.get("rows", [])
    if len(rows) != ROWS:
        issues.append(f"expected {ROWS} rows, found {len(rows)}")
    items = {int(row["code"]) for row in blocks((TABLES / "ITEM.TXT").read_bytes(), "item")}
    messages = json.loads(TOWN_MESSAGES.read_text(encoding="utf-8")).get("messages", {})
    previous = 0
    for row in rows:
        price = int(row.get("price", 0))
        if price <= previous:
            issues.append(f"row {row.get('index')}: price {price} does not increase")
        previous = price
        pitch = messages.get(str(row.get("pitch_message_id", 0)), "")
        match = re.search(r"\$(\d+)", pitch)
        if not match or int(match.group(1)) != price:
            issues.append(f"row {row.get('index')}: pitch message {row.get('pitch_message_id')} does not quote undefined")
        codes = [int(code) for code in row.get("items", [])]
        if len(codes) != SLOTS or any(code and code not in items for code in codes):
            issues.append(f"row {row.get('index')}: item codes are not all in ITEM.TXT")
        if not any(codes):
            issues.append(f"row {row.get('index')}: no goods")
    return issues


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE, help="original hsl01.exe (default: the local Wine install)")
    parser.add_argument("--check", action="store_true", help="compare the tracked output (with the EXE when present) and run the offline cross-checks")
    args = parser.parse_args(argv)
    if args.check:
        tracked = json.loads(OUTPUT.read_text(encoding="utf-8"))
        issues = offline_issues(tracked)
        mode = "offline"
        if args.exe.is_file():
            rows, events = read_table(args.exe)
            if payload(rows, events) != tracked:
                issues.append("tracked table differs from the EXE bytes")
            mode = "exe"
        if issues:
            for issue in issues:
                print("SECRET_MAN_GOODS_CHECK_FAIL", issue)
            return 1
        print(f"SECRET_MAN_GOODS_CHECK_PASS mode={mode} rows={len(tracked['rows'])}")
        return 0
    if not args.exe.is_file():
        print(f"SECRET_MAN_GOODS_BUILD_FAIL exe_missing={args.exe}")
        return 1
    rows, events = read_table(args.exe)
    data = payload(rows, events)
    issues = offline_issues(data)
    if issues:
        for issue in issues:
            print("SECRET_MAN_GOODS_BUILD_FAIL", issue)
        return 1
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"SECRET_MAN_GOODS_BUILD_PASS rows={len(rows)} prices={[row['price'] for row in rows]}")
    return 0


class SecretManGoodsTask(OriginalArchiveTask):
    name = 'secret_man_goods'
    family = 'static'
    archive = ORIGINAL_EXE
    inputs = ('content/imported/hsl/global/tables/', TOWN_MESSAGES.relative_to(ROOT).as_posix())
    outputs = (OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_secret_man_goods.py --check',)
    scripts = ('tools/hsltools/data/secret_man_goods.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[SecretManGoodsTask]:
    return [SecretManGoodsTask()]


if __name__ == '__main__':
    raise SystemExit(main())
