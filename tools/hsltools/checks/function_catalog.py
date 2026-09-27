"""Whole-executable function catalog: r2ghidra decompile, symbolize, model-judge, query.

Purpose: stop hunting one function per mechanic. Every function in hsl01.exe gets a
candidate role and a few atomic property probabilities so an agent can start a new
mechanic from a short candidate list instead of reading raw disassembly.

Pipeline (each step is repeatable and cached under ignored/):
  decompile  r2 + r2ghidra (r2dec fallback on crash) for every analysed function
             -> ignored/static/hsl01/catalog/decompiled/<addr>.c
  judge      symbolize each function with tracked names (known_functions.json, core_logic.json
             struct maps) and ask TypeSafe Jev one request per function -> judgments.jsonl;
             only functions whose symbolized text is new or changed are (re)judged, so
             registering names makes their callers stale and cheap to refresh (--dry-run counts)
  build      compact tracked catalog content/generated/hsl/static/hsl01/function_catalog.json
  query      filter the tracked catalog by role / property / unknown status
  --check    offline integrity check of the tracked catalog (no network, no r2)

The catalog is a routing aid at the existing "static_export_candidate" tier. A role label
from a model is not evidence: confirm with a bounded native probe before any claim.
Raw decompiled text and private paths never enter the tracked packet.

Registry task function_catalog (family checks, CheckTask): offline integrity check of the tracked
content/generated/hsl/static/hsl01/function_catalog.json (`hsl check function_catalog`); the decompile /
judge / build / query commands run through the module command line:

  PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query --role pathfinding_terrain --unknown
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

from hsltools import typesafe
from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.paths import ORIGINAL_EXE, ROOT
from hsltools.registry import Context

DEFAULT_EXE = ORIGINAL_EXE
RAW_DIR = ROOT / "ignored/static/hsl01/catalog"
KNOWN_FUNCTIONS = ROOT / "content/generated/hsl/static/hsl01/known_functions.json"
CORE_LOGIC = ROOT / "content/generated/hsl/static/hsl01/core_logic.json"
CATALOG = ROOT / "content/generated/hsl/static/hsl01/function_catalog.json"
SCHEMA = "hsl_function_catalog.v1"
MIN_CODE_CHARS = 100
JUDGE_CODE_CHARS = 80000  # ~32k tokens of dense C; documented limit for state + longest question

ROLES = {
    "combat_resolution": {"what": "计算命中、伤害、暴击、反击、追加攻击或把伤害应用到 HP 的战斗结算", "not_for": "选择目标或行动的 AI 决策；经验/属性刷新"},
    "growth_experience_stats": {"what": "经验发放、升级、属性成长、装备加成后的派生属性刷新（攻防速移动力等）", "not_for": "单次攻击的伤害计算"},
    "ai_decision": {"what": "非玩家单位决定目标、行动类型、是否用药/施法、扫描友军或敌人的决策逻辑", "not_for": "路径搜索本身；伤害结算"},
    "turn_queue_action_state": {"what": "回合/行动顺序队列、按速度排序、行动就绪位、回合开始/结束交接、状态倒计时", "not_for": "AI 选择目标"},
    "pathfinding_terrain": {"what": "地图格可达性洪水填充、移动代价、邻格扩展、地形阻挡位判断", "not_for": "AI 决定去哪；绘制地图"},
    "ui_menu_input": {"what": "菜单/按钮/状态窗口构建与响应、鼠标键盘输入聚合、UI 命中测试", "not_for": "精灵动画播放；脚本解释"},
    "script_vm_dispatch": {"what": "剧情脚本解释器、opcode 分派表、对象进程按名称/槽位分派与生成", "not_for": "菜单 UI；战斗计算"},
    "data_table_resource_loading": {"what": "读取/解析 ITEM、PLAYERS 等数据表，加载 PAK/资源文件、模板或地图数据，按名称解析资源", "not_for": "使用这些数据做战斗或 AI 判断"},
    "animation_render_sound": {"what": "精灵帧序列/动作程序播放、绘制、音效播放", "not_for": "UI 菜单逻辑"},
    "utility_rng_math_memory": {"what": "随机数、通用数学、内存/字符串工具等与游戏语义无关的小工具", "not_for": "任何带游戏字段语义的逻辑"},
    "object_lifecycle_install": {"what": "创建/安装/销毁游戏对象或玩家单位实例、初始化其进程槽位", "not_for": "对象每帧行为"},
    "unknown": {"what": "从代码看不出属于以上任何一类"},
}
PROPERTIES = {
    "uses_random": "`decompiled_c` 是否调用随机数函数或用随机值做概率判断（例如 rand_range、与百分比比较）？",
    "clamps_range": "`decompiled_c` 是否把某个整数夹在上下限之间（小于下限取下限、大于上限取上限）？",
    "iterates_neighbors": "`decompiled_c` 是否遍历地图格子或四/八方向邻格（如 x±1, y±1 循环）？",
    "sorts_or_ranks": "`decompiled_c` 是否按某个数值对多个单位/元素排序、比较大小取最优或建立顺序？",
    "draws_or_blits": "`decompiled_c` 是否进行绘制：拷贝像素/表面、画精灵、显示文字或设置显示矩形？",
    "reads_input": "`decompiled_c` 是否读取鼠标位置、鼠标按键或键盘按键状态？",
    "hp_arithmetic": "`decompiled_c` 是否对生命值/HP 字段做减法或写回（造成伤害或回复）？",
    "loops_over_equipment_slots": "`decompiled_c` 是否遍历角色的多个装备槽并累加装备表中的加成字段？",
    "tests_capability_bits": "`decompiled_c` 是否对 actor.capability_flags 做按位测试（& 某个位掩码）来决定行为？",
}
GLOBALS = {"0x4c1bc8": "g_live_actors", "0x4c1b40": "g_item_table", "0x4c1afc": "g_player_templates", "0x4c1ba0": "g_battle_active", "0x4c6d80": "g_turn_sidecar", "0x4c3040": "g_prng_state"}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_known() -> dict[str, dict]:
    return {row["address"].lower(): row for row in json.loads(KNOWN_FUNCTIONS.read_text(encoding="utf-8"))["functions"]}


def load_field_maps() -> tuple[dict[str, str], dict[str, str]]:
    core = json.loads(CORE_LOGIC.read_text(encoding="utf-8"))["struct_maps"]
    actor = {offset: name for name, offset in core["live_actor_combat_fields"]["fields"].items()}
    for name, field in core["player_template"]["fields"].items():
        actor.setdefault(field["byte"], name)
    item = {offset: name for name, offset in core["item_record"]["fields"].items()}
    return actor, item


def r2(exe: Path, commands: str, timeout: int = 900) -> subprocess.CompletedProcess:
    return subprocess.run(["r2", "-e", "bin.cache=true", "-e", "scr.color=0", "-qc", commands, str(exe)],
                          check=False, capture_output=True, text=True, timeout=timeout)


def list_functions(exe: Path) -> list[dict]:
    completed = r2(exe, "aaa; aflj")
    text = completed.stdout[completed.stdout.index("["):]
    rows = json.loads(text)
    return [{"address": f"0x{row.get('addr', row.get('offset')):x}", "size": row.get("size", 0)} for row in rows]


def decompile_all(exe: Path, functions: list[dict], out_dir: Path, chunk: int = 40) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    pending = [f["address"] for f in functions if not (out_dir / f"{f['address']}.c").exists()]
    for stale in out_dir.glob("0x*.failed"):
        if stale.stem in pending:
            stale.unlink()
    counts = {"cached": len(functions) - len(pending), "decompiled": 0, "failed": 0}
    for start in range(0, len(pending), chunk):
        batch = pending[start:start + chunk]
        script = "aaa; " + "; ".join(f"s {a}; af; echo ===FN {a}; pdg" for a in batch)
        completed = r2(exe, script)
        got = _split_functions(completed.stdout)
        for address in batch:
            code = got.get(address, "")
            if len(code.strip()) < MIN_CODE_CHARS or "You need to install" in code:
                single = r2(exe, f"aaa; s {address}; af; pdg", timeout=300)
                code = single.stdout if single.returncode == 0 else ""
                if len(code.strip()) < MIN_CODE_CHARS or "You need to install" in code:
                    # r2ghidra crashes on a few functions; r2dec pseudo-C is a usable fallback.
                    fallback = r2(exe, f"aaa; s {address}; af; pdd", timeout=300)
                    if fallback.returncode == 0 and fallback.stdout.strip():
                        code = "/* backend: pdd (r2dec fallback after r2ghidra crash) */\n" + fallback.stdout
            if code.strip():
                (out_dir / f"{address}.c").write_text(code, encoding="utf-8")
                counts["decompiled"] += 1
            else:
                (out_dir / f"{address}.failed").write_text("decompiler crashed or produced no output\n", encoding="utf-8")
                counts["failed"] += 1
    return counts


def _split_functions(stdout: str) -> dict[str, str]:
    parts = {}
    for chunk in stdout.split("===FN ")[1:]:
        newline = chunk.find("\n")
        parts[chunk[:newline].strip()] = chunk[newline + 1:].strip()
    return parts


def features(code: str, address: str) -> dict:
    callees = sorted({f"0x{m}" for m in re.findall(r"fcn\.00([0-9a-f]{6})", code)} - {address})
    globals_ = sorted(set(re.findall(r"0x4c[0-9a-f]{4}", code)))
    return {"chars": len(code), "callees": callees, "globals": globals_}


def symbolize(code: str, address: str, known: dict[str, dict], actor_fields: dict[str, str], item_fields: dict[str, str]) -> str:
    text = code
    for raw, name in GLOBALS.items():
        text = text.replace(f"*{raw}", name).replace(raw, name)
    for other, row in known.items():
        if other != address:
            text = text.replace(f"fcn.00{other[2:]}", row["name"])
    if "g_live_actors" in text or "0x1fc" in text:
        text = re.sub(r"\+ (0x[0-9a-f]+)\)", lambda m: f"+ {m[1]} /*actor.{actor_fields[m[1]]}*/)" if m[1] in actor_fields else m[0], text)
    if "g_item_table" in text or "* 0xb0" in text:
        text = re.sub(r"\+ (0x[0-9a-f]+)\)(?!\s*/\*)", lambda m: f"+ {m[1]} /*item.{item_fields[m[1]]}*/)" if m[1] in item_fields else m[0], text)
    return text


def questions() -> dict:
    result = {"role": {"type": "choice", "instructions": {"question": "`decompiled_c` 这个从 32 位游戏 EXE 反编译出的函数，主要职责属于哪一类？", "focus": "看它读写哪些字段、做什么计算、调用什么已命名函数，判断功能类别"}, "criteria": ROLES}}
    for name, instructions in PROPERTIES.items():
        result[name] = {"type": "noul", "instructions": instructions}
    return result


def symbol_hash(symbolized: str) -> str:
    return hashlib.sha1(symbolized.encode("utf-8")).hexdigest()[:16]


def judge_all(decompiled_dir: Path, raw_out: Path, model: str, workers: int, limit: int | None, dry_run: bool = False) -> dict[str, int]:
    """Judge every function whose symbolized text is new or changed since its last judgment.

    Registering a name in known_functions.json rewrites the text of every caller, so those
    callers become stale and are re-judged on the next run; unchanged functions cost nothing.
    Rows are appended; build_catalog keeps the newest row per address.
    """
    known = load_known()
    actor_fields, item_fields = load_field_maps()
    current: dict[str, str | None] = {}
    if raw_out.exists():
        for line in raw_out.read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                current[row["address"]] = row.get("symbol_hash")
    jobs = []
    counts = {"unchanged": 0, "stale": 0, "new": 0, "judged": 0, "errors": 0, "input_tokens": 0}
    for path in sorted(decompiled_dir.glob("0x*.c")):
        address = path.stem
        code = path.read_text(encoding="utf-8")
        if len(code) < MIN_CODE_CHARS:
            continue
        text = symbolize(code, address, known, actor_fields, item_fields)[:JUDGE_CODE_CHARS]
        digest = symbol_hash(text)
        if current.get(address) == digest:
            counts["unchanged"] += 1
            continue
        counts["stale" if address in current else "new"] += 1
        jobs.append((address, text, digest))
    if limit:
        jobs = jobs[:limit]
    counts["pending"] = len(jobs)
    if dry_run:
        return counts
    with raw_out.open("a", encoding="utf-8") as handle:
        for start in range(0, len(jobs), workers * 4):
            batch = jobs[start:start + workers * 4]
            responses = typesafe.system_one_many([({"decompiled_c": code}, questions()) for _, code, _ in batch], model=model, workers=workers)
            for (address, _, digest), response in zip(batch, responses):
                if "error" in response:
                    counts["errors"] += 1
                    print(f"{address}: {response['error'][:160]}", file=sys.stderr)
                    continue
                counts["judged"] += 1
                counts["input_tokens"] += response.get("usage", {}).get("input_tokens", 0)
                handle.write(json.dumps({"address": address, "symbol_hash": digest, "model": response["model"], "answers": response["answers"], "judged_at": time.strftime("%Y-%m-%dT%H:%M:%S")}, ensure_ascii=False) + "\n")
    return counts


def build_catalog(exe: Path, decompiled_dir: Path, raw_judgments: Path) -> dict:
    known = load_known()
    judgments = {}
    for line in raw_judgments.read_text(encoding="utf-8").splitlines():
        if line.strip():
            row = json.loads(line)
            judgments[row["address"]] = row
    functions = {}
    models = set()
    for path in sorted(decompiled_dir.glob("0x*.c")):
        address = path.stem
        code = path.read_text(encoding="utf-8")
        entry = {"decompiled": len(code) >= MIN_CODE_CHARS, **features(code, address)}
        if address in known:
            entry["name"] = known[address]["name"]
            entry["known_role"] = known[address]["role"]
        judged = judgments.get(address)
        if judged:
            role = judged["answers"]["role"]
            models.add(judged["model"])
            entry["role"] = role["choice"]
            entry["role_confidence"] = round(role["confidence"], 3)
            entry["role_probabilities"] = {k: round(v, 3) for k, v in role["probabilities"].items() if v >= 0.05}
            entry["properties"] = {name: round(judged["answers"][name]["noul"], 3) for name in PROPERTIES if name in judged["answers"]}
        functions[address] = entry
    for path in sorted(decompiled_dir.glob("0x*.failed")):
        entry = {"decompiled": False, "chars": 0, "callees": [], "globals": [], "decompile_failed": True}
        if path.stem in known:
            entry["name"] = known[path.stem]["name"]
            entry["known_role"] = known[path.stem]["role"]
        functions.setdefault(path.stem, entry)
    return {
        "schema": SCHEMA,
        "evidence_tier": "static_export_candidate",
        "policy": "Model-judged role candidates and property probabilities for routing only. Not evidence of behaviour; confirm with a bounded native probe or instruction anchors before any claim. No raw decompiled text or private paths.",
        "exe_sha256": sha256_file(exe),
        "judge_models": sorted(models),
        "roles": sorted(ROLES),
        "properties": sorted(PROPERTIES),
        "known_function_count": len(known),
        "function_count": len(functions),
        "judged_count": sum(1 for f in functions.values() if "role" in f),
        "functions": dict(sorted(functions.items(), key=lambda kv: int(kv[0], 16))),
    }


def check(catalog: dict) -> None:
    if catalog.get("schema") != SCHEMA or catalog.get("evidence_tier") != "static_export_candidate":
        raise ValueError("Catalog schema or tier differs")
    known = load_known()
    functions = catalog["functions"]
    if catalog["function_count"] != len(functions) or catalog["known_function_count"] != len(known):
        raise ValueError("Catalog counts differ from content")
    judged = 0
    for address, entry in functions.items():
        if not re.fullmatch(r"0x4[0-9a-f]{5}", address):
            raise ValueError(f"Bad function address {address}")
        if "role" in entry:
            judged += 1
            if entry["role"] not in ROLES or not 0 <= entry["role_confidence"] <= 1:
                raise ValueError(f"Bad role for {address}")
            if any(not 0 <= p <= 1 for p in entry["properties"].values()) or set(entry["properties"]) - set(PROPERTIES):
                raise ValueError(f"Bad properties for {address}")
        if address in known and entry.get("name") != known[address]["name"]:
            raise ValueError(f"Known function {address} missing its registered name")
        for text in json.dumps(entry).split("\""):
            if "/Users/" in text or "drive_c" in text:
                raise ValueError("Private path leaked into catalog")
    if judged != catalog["judged_count"]:
        raise ValueError("judged_count differs")


def query(catalog: dict, role: str | None, min_prop: list[str], unknown: bool, min_confidence: float, limit: int) -> list[tuple[str, dict]]:
    rows = []
    for address, entry in catalog["functions"].items():
        if "role" not in entry:
            continue
        if unknown and "name" in entry:
            continue
        if role and entry["role"] != role:
            continue
        if entry["role_confidence"] < min_confidence:
            continue
        ok = True
        for spec in min_prop:
            name, threshold = spec.split(">=")
            ok &= entry["properties"].get(name, 0.0) >= float(threshold)
        if ok:
            rows.append((address, entry))
    rows.sort(key=lambda kv: -(kv[1]["role_confidence"] + sum(kv[1]["properties"].get(s.split(">=")[0], 0) for s in min_prop)))
    return rows[:limit]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--check", action="store_true", help="offline integrity check of the tracked catalog")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("decompile", help="decompile every analysed function into ignored/ (r2 + r2ghidra)")
    judge = sub.add_parser("judge", help="model-judge decompiled functions (needs TYPESAFE_API_KEY)")
    judge.add_argument("--model", default=typesafe.DEFAULT_MODEL)
    judge.add_argument("--workers", type=int, default=8)
    judge.add_argument("--limit", type=int, default=None)
    judge.add_argument("--dry-run", action="store_true", help="only count new/stale/unchanged functions; no network")
    sub.add_parser("build", help="write the compact tracked catalog from raw judgments")
    q = sub.add_parser("query", help="filter the tracked catalog")
    q.add_argument("--role", choices=sorted(ROLES))
    q.add_argument("--prop", action="append", default=[], help="property>=threshold, quote it in a shell: 'iterates_neighbors>=0.8'")
    q.add_argument("--unknown", action="store_true", help="only functions without a registered name")
    q.add_argument("--min-confidence", type=float, default=0.0)
    q.add_argument("--limit", type=int, default=30)
    args = parser.parse_args(argv)
    decompiled = RAW_DIR / "decompiled"
    raw_judgments = RAW_DIR / "judgments.jsonl"
    if args.check:
        check(json.loads(CATALOG.read_text(encoding="utf-8")))
        print("FUNCTION_CATALOG_CHECK_PASS")
        return 0
    if args.command == "decompile":
        functions = list_functions(args.exe)
        print(json.dumps({"functions": len(functions), **decompile_all(args.exe, functions, decompiled)}))
    elif args.command == "judge":
        print(json.dumps(judge_all(decompiled, raw_judgments, args.model, args.workers, args.limit, args.dry_run)))
    elif args.command == "build":
        catalog = build_catalog(args.exe, decompiled, raw_judgments)
        check(catalog)
        CATALOG.write_text(json.dumps(catalog, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"FUNCTION_CATALOG_BUILT functions={catalog['function_count']} judged={catalog['judged_count']}")
    elif args.command == "query":
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        for address, entry in query(catalog, args.role, args.prop, args.unknown, args.min_confidence, args.limit):
            props = " ".join(f"{k[:6]}={v:.2f}" for k, v in entry["properties"].items() if v >= 0.5)
            print(f"{address} {entry.get('name', '-'):28} {entry['role']:28} conf={entry['role_confidence']:.2f} chars={entry['chars']:6} callees={len(entry['callees']):2} {props}")
    else:
        parser.print_help()
        return 2
    return 0


class FunctionCatalogTask(CheckTask):
    name = 'function_catalog'
    family = 'checks'
    inputs = (CATALOG.relative_to(ROOT).as_posix(), KNOWN_FUNCTIONS.relative_to(ROOT).as_posix(), CORE_LOGIC.relative_to(ROOT).as_posix())
    replaces = ('tools/hsl_function_catalog.py --check',)
    scripts = ('tools/hsltools/checks/function_catalog.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])


def tasks() -> list[FunctionCatalogTask]:
    return [FunctionCatalogTask()]


if __name__ == '__main__':
    raise SystemExit(main())
