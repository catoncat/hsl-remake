#!/usr/bin/env python3
"""Playtest kit: saves that drop a human tester straight into chosen campaign battles.

generate  Runs the seeded chapter autoplay (tests/run_chapter_autoplay_tests.gd) in an
          isolated HOME and keeps every campaign position the product writes
          (user://campaign_progress.json, CampaignProgress.save_progress). Each kit slot is
          the first saved position entering its battle, i.e. the party exactly as the
          commander brought it there through the product's own hand-offs.
install   Copies the kit into a playtest profile (its own HOME, so the tester's normal saves
          are untouched) as the eight 回憶錄 slots, and points the title's 戰場記錄 at one slot.

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

# Kit slots, in 回憶錄 order. "entry" = the first saved position entering the battle (level 51
# has none: a fresh campaign start); "before" = the last big-map position before that entry,
# so the tester can shop and re-equip first.
SLOTS = [
    ("驗收1 第51關 棄卒", BATTLES + "battle_051.json", "entry"),
    ("驗收2 第52關 惡夢的終曲", BATTLES + "battle_052.json", "entry"),
    ("驗收3 第53關 逃出克萊恩城", BATTLES + "battle_053.json", "entry"),
    ("驗收4 第3關 盜賊洞窟", BATTLES + "battle_003.json", "entry"),
    ("驗收5 第5關 呼嘯平原", BATTLES + "battle_005.json", "entry"),
    ("驗收6 第6關 席達鎮", BATTLES + "battle_006.json", "entry"),
    ("驗收7 大地圖 第6關前（可整備）", BATTLES + "battle_006.json", "before"),
    ("驗收8 第2關 戈爾山道", BATTLES + "gol_road_battle.json", "entry"),
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
    env = dict(os.environ, HOME=str(home), HSL_CHAPTER_TRIES=str(args.tries), HSL_CHAPTER_BUDGET_SECONDS=str(args.budget))
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
    return 0


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
    for index, (label, scenario, mode) in enumerate(SLOTS):
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
    tail = [line for line in (KIT / "generate.log").read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith("CHAPTER_AUTOPLAY")]
    count = len(records)
    manifest = {"schema": "hsl_playtest_kit.v1", "snapshots": count, "slots": kit_slots, "chapter_lines": tail[-40:]}
    (KIT / "kit.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    for slot in kit_slots:
        extra = f" party={json.dumps(slot.get('party', {}), ensure_ascii=False)} gold={slot.get('gold')}" if slot["status"] == "ok" else ""
        print(f"PLAYTEST_KIT_SLOT slot={slot['slot'] + 1} status={slot['status']} label={slot['label']}{extra}")
    print(f"PLAYTEST_KIT_GENERATED snapshots={count} ok={sum(1 for s in kit_slots if s['status'] == 'ok')}/{len(kit_slots)}")
    return 0


def install(args: argparse.Namespace) -> int:
    saves = KIT / "saves"
    if not saves.is_dir() or not any(saves.glob("memoir_*.json")):
        print(f"No kit in {KIT}: run python3 tools/hsl_playtest_kit.py generate", file=sys.stderr)
        return 1
    target = user_dir(Path(args.profile).expanduser())
    target.mkdir(parents=True, exist_ok=True)
    for old in target.glob("memoir_*.json"):
        old.unlink()
    for save in sorted(saves.glob("memoir_*.json")):
        shutil.copy2(save, target / save.name)
    slot_file = saves / f"memoir_{args.slot - 1:02d}.json"
    if not slot_file.exists():
        print(f"Kit slot {args.slot} was not generated (see {KIT / 'kit.json'})", file=sys.stderr)
        return 1
    record = json.loads(slot_file.read_text(encoding="utf-8"))
    record.pop("memoir_label", None)
    (target / "campaign_progress.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    # A battle checkpoint would win over the campaign position on the title's 戰場記錄.
    for checkpoint in target.glob("*.save"):
        checkpoint.unlink()
    print(f"PLAYTEST_KIT_INSTALLED profile={args.profile} title_resume_slot={args.slot}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("--tries", type=int, default=5)
    gen.add_argument("--budget", type=int, default=0)
    gen.add_argument("--force-win", action="store_true", help="force-win a battle lost on every try and walk on (HSL_CHAPTER_FORCE_WIN=1)")
    sub.add_parser("select", help="rebuild the slots from the kept snapshots without replaying the chapter")
    inst = sub.add_parser("install")
    inst.add_argument("--profile", default=str(PROFILE))
    inst.add_argument("--slot", type=int, default=1)
    args = parser.parse_args()
    return {"generate": generate, "select": select, "install": install}[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
