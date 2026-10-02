#!/usr/bin/env python3
"""Playtest kit: saves that drop a human tester straight into chosen campaign battles.

Every slot has a short ASCII name (l053, r012, ...); `list` prints them with the battle names.

generate  Runs the seeded chapter autoplay (tests/run_chapter_autoplay_tests.gd) in an
          isolated HOME and keeps every campaign position the product writes
          (user://campaign_progress.json, CampaignProgress.save_progress). Each kit slot is
          the first saved position entering its battle, i.e. the party exactly as the
          commander brought it there through the product's own hand-offs. Besides the eight
          named slots, every battle or story scene the walk entered becomes a b<level> slot
          (b044, ...) from its first saved position there.
raw       Writes the raw slots: a bare entry position into a battle (empty carry and world, like
          a fresh level 51 start), so the battle opens with the party its own level data sets up.
          Seconds, no chapter walk; slots the walk never reached still get one.
install   Copies the kit into a playtest profile (its own HOME, so the tester's normal saves
          are untouched): the eight walk slots as the 回憶錄 slots, and the chosen slot (any
          name) as the saved position the title's 戰場記錄 resumes. tools/playtest.sh then
          starts the game with HSL_SKIP_TITLE=1, which runs that 戰場記錄 without the title.

Kit, profile and logs live under $HSL_PLAYTEST_HOME (default ~/hsl-playtest), outside any
checkout. tools/playtest.sh is the launcher.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Everything lives outside the checkout so any worktree's launcher finds the same kit and saves.
PLAYTEST_HOME = Path(os.environ.get("HSL_PLAYTEST_HOME", str(Path.home() / "hsl-playtest"))).expanduser()
KIT = PLAYTEST_HOME / "kit"
PROFILE = PLAYTEST_HOME / "home"
USER_DIR_TAIL = Path("Library/Application Support/Godot/app_userdata/HSL Remake")
PROGRESS_SCHEMA = "hsl_campaign_progress_save.v1"

WORLD_MAP = "res://content/world/world_map_scene.json"
BATTLES = "res://content/battles/"

# Walk slots, in 回憶錄 order: (name, 回憶錄 label, what the tester lands on, scenario, mode).
# "entry" = the first saved position entering the battle (level 51 has none: a fresh campaign
# start); "before" = the last big-map position before that entry, so the tester can shop and
# re-equip first.
SLOTS = [
    ("l051", "驗收1 第51關 棄卒", "玩家第 1 场 · 棄卒（LEVEL051）", BATTLES + "battle_051.json", "entry"),
    ("l052", "驗收2 第52關 惡夢的終曲", "玩家第 2 场 · 惡夢的終曲（LEVEL052）", BATTLES + "battle_052.json", "entry"),
    ("l053", "驗收3 第53關 逃出克萊恩城", "玩家第 3 场 · 逃出克萊恩城（LEVEL053）", BATTLES + "battle_053.json", "entry"),
    ("l003", "驗收4 第3關 盜賊洞窟", "玩家第 6 场 · 盜賊洞窟（LEVEL003）", BATTLES + "battle_003.json", "entry"),
    ("l005", "驗收5 第5關 呼嘯平原", "呼嘯平原（LEVEL005）", BATTLES + "battle_005.json", "entry"),
    ("l006", "驗收6 第6關 席達鎮", "席達鎮（LEVEL006）", BATTLES + "battle_006.json", "entry"),
    ("w006", "驗收7 大地圖 第6關前（可整備）", "大地圖，席達鎮（LEVEL006）之前（可进城整備）", BATTLES + "battle_006.json", "before"),
    ("l002", "驗收8 第2關 戈爾山道", "玩家第 5 场 · 戈爾山道（LEVEL002）", BATTLES + "gol_road_battle.json", "entry"),
]
# Raw slots: (name, what the tester lands on, scenario). The party is the level's own set-up
# (no carried levels, equipment or items), fine for looking at a stage, its opening and its
# script; a battle that needs the carried party to be fought fairly uses a walk slot instead.
RAW_SLOTS = [
    ("r012", "巴瀚納海峽（LEVEL012）開場", BATTLES + "battle_012.json"),
    ("r022", "尼布魯瀑布（LEVEL022）開場", BATTLES + "battle_022.json"),
    ("r036", "薩魯司海岸（LEVEL036）開場", BATTLES + "battle_036.json"),
    ("r037", "古代神殿遺跡（LEVEL037）開場", BATTLES + "battle_037.json"),
]


def user_dir(home: Path) -> Path:
    return home / USER_DIR_TAIL


def generate(args: argparse.Namespace) -> int:
    code = walk(args)
    return code if code else select(args)


def walk(args: argparse.Namespace) -> int:
    home = KIT / "gen-home"
    snaps = KIT / "snapshots"
    for path in (home, snaps):
        shutil.rmtree(path, ignore_errors=True)
        path.mkdir(parents=True)
    progress = user_dir(home) / "campaign_progress.json"
    # HSL_REAL_HOME=1 keeps tools/godot.sh from swapping this HOME for ignored/lane-home on a headless
    # run; without it the walk writes its progress there and the watcher below never sees a snapshot.
    env = dict(os.environ, HOME=str(home), HSL_REAL_HOME="1", HSL_CHAPTER_TRIES=str(args.tries), HSL_CHAPTER_BUDGET_SECONDS=str(args.budget))
    if args.force_win:
        # A battle the commander loses on every try is force-won and the walk goes on, so the
        # slots past it are reached (tests/run_chapter_autoplay_tests.gd HSL_CHAPTER_FORCE_WIN).
        env["HSL_CHAPTER_FORCE_WIN"] = "1"
    log = (KIT / "generate.log").open("w")
    cmd = [str(ROOT / "tools" / "godot.sh"), "--headless", "--fixed-fps", "60", "--script", "res://tests/run_chapter_autoplay_tests.gd"]
    proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    last = b""
    count = 0
    while True:
        done = proc.poll() is not None
        try:
            data = progress.read_bytes()
        except OSError:
            data = b""
        if data and data != last:
            last = data
            count += 1
            (snaps / f"{count:04d}.json").write_bytes(data)
        if done:
            break
        time.sleep(0.2)
    log.close()
    # The chapter walk rewrites the tracked chapter.json; the kit must not leave that behind.
    subprocess.run(["git", "checkout", "--", "content/generated/hsl/development/autoplay/chapter.json"], cwd=ROOT, check=False)
    print(f"PLAYTEST_KIT_WALK snapshots={count} exit={proc.returncode}")
    return proc.returncode


def select(args: argparse.Namespace) -> int:
    snaps = KIT / "snapshots"
    records = []
    for snap in sorted(snaps.glob("*.json")):
        try:
            records.append(json.loads(snap.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            continue
    kit_slots = []
    saves = KIT / "saves"
    shutil.rmtree(saves, ignore_errors=True)
    saves.mkdir(parents=True)
    for index, (_name, label, _shown, scenario, mode) in enumerate(SLOTS):
        entry = next((i for i, r in enumerate(records) if r.get("scenario_path") == scenario), None)
        record = None
        if entry is not None and mode == "entry":
            record = records[entry]
        elif entry is not None and mode == "before":
            record = next((r for r in reversed(records[:entry]) if r.get("scenario_path") == WORLD_MAP), None)
        if record is None and mode == "entry" and scenario == BATTLES + "battle_051.json":
            record = {"schema": PROGRESS_SCHEMA, "scenario_path": scenario, "carry": {}, "from_scenario_id": "playtest_kit", "world": {}}
        if record is None:
            kit_slots.append({"slot": index, "label": label, "scenario_path": scenario, "mode": mode, "status": "not_reached"})
            continue
        record = dict(record, memoir_label=label, play_seconds=0.0, schema=PROGRESS_SCHEMA)
        (saves / f"memoir_{index:02d}.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
        carry = record.get("carry") if isinstance(record.get("carry"), dict) else {}
        units = carry.get("units") if isinstance(carry.get("units"), dict) else {}
        party = {uid: unit.get("level") for uid, unit in sorted(units.items()) if isinstance(unit, dict)}
        gold = carry.get("loop", {}).get("gold") if isinstance(carry.get("loop"), dict) else None
        kit_slots.append({"slot": index, "label": label, "scenario_path": record["scenario_path"], "mode": mode, "status": "ok", "party": party, "gold": gold})
    battle_rows = []
    for order, (name, level, scenario, record) in enumerate(battle_entries(records), 1):
        shown = f"{battle_title(scenario)}（LEVEL{level:03d}），走查第 {order} 站"
        (saves / f"walk_{name}.json").write_text(json.dumps(dict(record, play_seconds=0.0, schema=PROGRESS_SCHEMA), ensure_ascii=False, indent=2), encoding="utf-8")
        battle_rows.append({"name": name, "label": shown, "scenario_path": scenario})
    tail = [line for line in (KIT / "generate.log").read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith("CHAPTER_AUTOPLAY")]
    count = len(records)
    manifest = dict(read_manifest(), schema="hsl_playtest_kit.v1", snapshots=count, slots=kit_slots, battle_slots=battle_rows, chapter_lines=tail[-40:])
    (KIT / "kit.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    for slot in kit_slots:
        extra = f" party={json.dumps(slot.get('party', {}), ensure_ascii=False)} gold={slot.get('gold')}" if slot["status"] == "ok" else ""
        print(f"PLAYTEST_KIT_SLOT slot={slot['slot'] + 1} status={slot['status']} label={slot['label']}{extra}")
    print(f"PLAYTEST_KIT_GENERATED snapshots={count} ok={sum(1 for s in kit_slots if s['status'] == 'ok')}/{len(kit_slots)} battles={len(battle_rows)}")
    return 0


def battle_entries(records: list) -> list:
    """Every battle the walk entered as a b<level> slot: its first saved position there, i.e. the
    hand-off with the party the walk carried in (the same record HSL_AUTOPLAY_HANDOFF replays)."""
    campaign = json.loads((ROOT / "content/battles/campaign.json").read_text(encoding="utf-8")).get("battles", {})
    level_of = {str(entry.get("scenario", "")): int(key) for key, entry in campaign.items() if isinstance(entry, dict) and str(key).isdigit()}
    rows, seen = [], set()
    for record in records:
        scenario = str(record.get("scenario_path", ""))
        level = level_of.get(scenario)
        if level is None or level in seen:
            continue
        seen.add(level)
        rows.append((f"b{level:03d}", level, scenario, record))
    return rows


def battle_title(scenario: str) -> str:
    try:
        return str(json.loads((ROOT / scenario.removeprefix("res://")).read_text(encoding="utf-8")).get("title", scenario))
    except (OSError, json.JSONDecodeError):
        return scenario


def read_manifest() -> dict:
    try:
        manifest = json.loads((KIT / "kit.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return manifest if isinstance(manifest, dict) else {}


def raw(_args: argparse.Namespace) -> int:
    saves = KIT / "saves"
    saves.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, shown, scenario in RAW_SLOTS:
        if not (ROOT / scenario.removeprefix("res://")).is_file():
            rows.append({"name": name, "label": shown, "scenario_path": scenario, "status": "missing_scenario"})
            continue
        record = {"schema": PROGRESS_SCHEMA, "scenario_path": scenario, "carry": {}, "from_scenario_id": "playtest_kit", "world": {}, "play_seconds": 0.0}
        (saves / f"raw_{name}.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
        rows.append({"name": name, "label": shown, "scenario_path": scenario, "status": "ok"})
    manifest = dict(read_manifest(), raw_slots=rows)
    manifest.setdefault("schema", "hsl_playtest_kit.v1")
    (KIT / "kit.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    for row in rows:
        print(f"PLAYTEST_KIT_SLOT name={row['name']} status={row['status']} label={row['label']} scenario={row['scenario_path']}")
    print(f"PLAYTEST_KIT_RAW ok={sum(1 for r in rows if r['status'] == 'ok')}/{len(rows)}")
    return 0


def slot_file(slot: str) -> tuple[Path, str] | None:
    """The kit file and landing text for a slot name, or a walk slot's 回憶錄 number 1..8."""
    saves = KIT / "saves"
    for index, (name, _label, shown, _scenario, _mode) in enumerate(SLOTS):
        if slot in (name, str(index + 1)):
            return saves / f"memoir_{index:02d}.json", shown
    for name, shown, _scenario in RAW_SLOTS:
        if slot == name:
            return saves / f"raw_{name}.json", shown
    for row in read_manifest().get("battle_slots", []):
        if slot == row.get("name"):
            return saves / f"walk_{slot}.json", str(row.get("label", slot))
    return None


def list_slots(_args: argparse.Namespace) -> int:
    print("tools/playtest.sh <名>   直达这一条（跳过标题）；tools/playtest.sh title   停在标题")
    if not (KIT / "saves").is_dir():
        print(f"  没有测试包（{KIT}）：python3 tools/hsl_playtest_kit.py generate --force-win，再 python3 tools/hsl_playtest_kit.py raw")
        return 0
    for index, (name, _label, shown, _scenario, _mode) in enumerate(SLOTS):
        ready = "" if (KIT / "saves" / f"memoir_{index:02d}.json").exists() else "  （测试包里没有：整章走查没走到）"
        print(f"  {name}  回憶錄{index + 1}  {shown}{ready}")
    for name, shown, _scenario in RAW_SLOTS:
        ready = "" if (KIT / "saves" / f"raw_{name}.json").exists() else "  （未生成：python3 tools/hsl_playtest_kit.py raw）"
        print(f"  {name}  关卡自带队伍  {shown}{ready}")
    battles = read_manifest().get("battle_slots", [])
    if battles:
        print(f"  走查进过的每一场（带走查队伍，开场进）：{len(battles)} 场")
        for row in battles:
            print(f"  {row['name']}  {row['label']}")
    return 0


def install(args: argparse.Namespace) -> int:
    saves = KIT / "saves"
    if not saves.is_dir() or not any(saves.glob("*.json")):
        print(f"No kit in {KIT}: run python3 tools/hsl_playtest_kit.py generate (or raw)", file=sys.stderr)
        return 1
    target = user_dir(Path(args.profile).expanduser())
    target.mkdir(parents=True, exist_ok=True)
    for old in target.glob("memoir_*.json"):
        old.unlink()
    for save in sorted(saves.glob("memoir_*.json")):
        shutil.copy2(save, target / save.name)
    if args.slot == "title":
        print(f"PLAYTEST_KIT_INSTALLED profile={args.profile} slot=title")
        return 0
    found = slot_file(args.slot)
    if found is None:
        print(f"Unknown slot {args.slot!r}; python3 tools/hsl_playtest_kit.py list", file=sys.stderr)
        return 2
    path, shown = found
    if not path.exists():
        print(f"Slot {args.slot} is not in the kit (see {KIT / 'kit.json'}; raw slots: python3 tools/hsl_playtest_kit.py raw)", file=sys.stderr)
        return 1
    record = json.loads(path.read_text(encoding="utf-8"))
    record.pop("memoir_label", None)
    (target / "campaign_progress.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    # A battle checkpoint would win over the campaign position on the title's 戰場記錄.
    for checkpoint in target.glob("*.save"):
        checkpoint.unlink()
    print(f"PLAYTEST_KIT_INSTALLED profile={args.profile} slot={args.slot} scenario={record.get('scenario_path', '')} label={shown}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("--tries", type=int, default=5)
    gen.add_argument("--budget", type=int, default=0)
    gen.add_argument("--force-win", action="store_true", help="force-win a battle lost on every try and walk on (HSL_CHAPTER_FORCE_WIN=1)")
    sub.add_parser("select", help="rebuild the slots from the kept snapshots without replaying the chapter")
    sub.add_parser("raw", help="write the raw slots (bare battle entries, no chapter walk)")
    sub.add_parser("list", help="print the slot names")
    inst = sub.add_parser("install")
    inst.add_argument("--profile", default=str(PROFILE))
    inst.add_argument("--slot", default="l051", help="slot name, a walk slot's number 1..8, or title (the 回憶錄 slots only)")
    args = parser.parse_args()
    return {"generate": generate, "select": select, "raw": raw, "list": list_slots, "install": install}[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
