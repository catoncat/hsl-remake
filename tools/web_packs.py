#!/usr/bin/env python3
"""Web build packs: a small core export plus resource packs fetched when a scene needs them.

plan   Scans a project directory (a checkout or a web staging copy; same layout) and writes the
       split: which game files leave the core export (`core_exclude`, Godot export
       exclude_filter wildcards), the packs that own them (`packs`: res:// files, bytes, deps)
       and the groups the runtime asks for (`groups`: level:<n>, movie:<name>, music:<stem>,
       scene:<path>), plus the scenario path → group map and the next-scenario hints the
       runtime prefetches. Ownership goes by directory: a level's battleNNN/ tree, its scenario
       JSON, seed, terrain and treasure tables are level_NNN; the film sheets and sound are
       movie_<name>; every music track but the title's is music_<stem>; the rest stays core. A
       pack depends on every other pack its JSON files name by res:// path (a level borrowing
       another level's map, the music its timeline plays, the film a movie_play event names);
       a reference to another scenario file is a hand-off, not a dependency. The plan checks and
       prints its invariants: each game file is core or in exactly one pack, the exclude
       wildcards match exactly the pack files, groups are closed over deps.
build  Packs every plan pack with PCKPacker in one headless Godot run (tools/web/pack_builder.gd)
       as <id>-<sha8>.pck and writes OUT_DIR/manifest.json (file, bytes, sha256 per pack; groups;
       scenarios; next) for game/web/PackManager.gd.

Sizes are the files as they sit in the project (imported textures/streams from .godot/imported,
JSON as written), so a staging copy with rewritten JSON plans and packs by its own bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN_SCHEMA = "hsl_web_packs_plan.v1"
MANIFEST_SCHEMA = "hsl_web_packs_manifest.v1"
# Top-level entries the web export never carries (the core preset excludes them too).
SKIP_TOP = {"docs", "tests", "tools", "ignored", "asset-dumps", "legal-assets", "addons_disabled"}
TITLE_MANIFEST = "content/imported/hsl/global/title/manifest.json"
CAMPAIGN = "content/battles/campaign.json"
CAMPAIGN_REGISTRY = "content/authored/campaigns.json"
MOVIE_DIR = "content/imported/hsl/movie/"
BIG_MAP_LEVEL = 49  # game/world/WorldMapRules.gd BIG_MAP_LEVEL
LEVEL_RULES = [
    re.compile(r"^content/imported/hsl/chapter01/battle(\d+)/"),
    re.compile(r"^content/battles/(?:battle|story)_(\d+)\.json$"),
    re.compile(r"^content/battles/levels/(\d+)\.json$"),
    re.compile(r"^content/generated/hsl/chapter01/battle(\d+)_seed\.json$"),
    re.compile(r"^content/generated/hsl/static/hsl01/level(\d+)_terrain\.json$"),
    re.compile(r"^content/generated/hsl/treasures/battle_(\d+)\.json$"),
    re.compile(r"^content/generated/hsl/authored/battle(\d+)(?:/|_seed\.json$)"),
    re.compile(r"^content/authored/level(\d+)/"),
]
# Battle-only presentation data every scene in BattleSceneRuntime (battles, stories, towns, the
# big map) and the GameClear showcase may draw, but no title-side screen does: one pack every
# level and scene group depends on, so the title needs only core.
BATTLE_COMMON = ("content/imported/hsl/chapter01/combat_animation/", "content/generated/hsl/skills/effect_motion.json")
DEST_RE = re.compile(r'^dest_files=\[(.*)\]', re.M)
IMPORTER_RE = re.compile(r'^importer="([^"]*)"', re.M)


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _movie_names(value):
    """Film names a scene can play: {"movie": "<name>"} in movie_play params and skip_battle."""
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "movie" and isinstance(item, str) and item:
                yield item
            else:
                yield from _movie_names(item)
    elif isinstance(value, list):
        for item in value:
            yield from _movie_names(item)


def godot_match(path: str, pattern: str) -> bool:
    """String.matchn: case-insensitive, `*` any run (slashes too), `?` one character."""
    regex = "".join(".*" if c == "*" else "." if c == "?" else re.escape(c) for c in pattern.lower())
    return re.fullmatch(regex, path.lower(), re.S) is not None


class Project:
    def __init__(self, root: Path):
        self.root = root
        self.units: dict[str, list[str]] = {}  # source rel path -> files packed (rel paths)
        self.bytes: dict[str, int] = {}
        self.other_bytes = 0  # exported files outside content/ (scripts, scenes, UI assets)
        self._scan()

    def _size(self, rel: str) -> int:
        try:
            return (self.root / rel).stat().st_size
        except OSError:
            return 0

    def _scan(self) -> None:
        for dirpath, dirnames, filenames in os.walk(self.root):
            rel_dir = os.path.relpath(dirpath, self.root).replace(os.sep, "/")
            rel_dir = "" if rel_dir == "." else rel_dir + "/"
            if ".gdignore" in filenames and rel_dir:
                dirnames[:] = []
                continue
            dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and not (rel_dir == "" and d in SKIP_TOP))
            names = set(filenames)
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                rel = rel_dir + name
                if name.endswith(".import"):
                    source = rel[: -len(".import")]
                    if source.rsplit("/", 1)[-1] not in names:
                        continue  # an orphan .import (its source moved away) exports nothing
                    text = (self.root / rel).read_text(encoding="utf-8", errors="replace")
                    importer = IMPORTER_RE.search(text)
                    if importer and importer.group(1) == "skip":
                        continue
                    files = [rel]
                    match = DEST_RE.search(text)
                    if match:
                        files += [d for d in re.findall(r'"res://([^"]+)"', match.group(1)) if (self.root / d).exists()]
                    if importer and importer.group(1) == "keep":
                        files.append(source)
                    self._add(source, files)
                elif name + ".import" in names:
                    continue
                elif rel.startswith("content/"):
                    if name.endswith((".json", ".tres", ".res", ".tscn")):
                        self._add(rel, [rel])
                elif rel_dir.startswith("game/") or rel_dir == "":
                    if name.endswith((".gd", ".tscn", ".tres", ".res", ".gdshader", ".json", ".godot", ".cfg")):
                        self.other_bytes += self._size(rel)

    def _add(self, source: str, files: list[str]) -> None:
        if not source.startswith("content/"):
            self.other_bytes += sum(self._size(f) for f in files)
            return
        self.units[source] = files
        self.bytes[source] = sum(self._size(f) for f in files)


def _campaigns(root: Path) -> list[dict]:
    rows = []
    main = _read_json(root / CAMPAIGN)
    if isinstance(main, dict):
        rows.append(main)
    registry = _read_json(root / CAMPAIGN_REGISTRY)
    for row in (registry or {}).get("campaigns", []) if isinstance(registry, dict) else []:
        data = _read_json(root / str(row.get("campaign", "")).removeprefix("res://"))
        if isinstance(data, dict):
            rows.append(data)
    return rows


def _rel(res: str) -> str:
    return res.removeprefix("res://")


def plan(root: Path) -> dict:
    project = Project(root)
    units = project.units
    campaigns = _campaigns(root)
    title = _read_json(root / TITLE_MANIFEST) or {}
    title_music = {_rel(s) for s in _strings(title.get("music", {})) if s.endswith(".ogg")}
    named_levels: dict[str, int] = {}  # scenario rel path -> campaign level key (ohm_village_battle.json ...)
    for campaign in campaigns:
        for key, entry in campaign.get("battles", {}).items():
            scenario = _rel(str(entry.get("scenario", "")))
            if key.isdigit() and scenario.startswith("content/battles/") and scenario.endswith(".json"):
                named_levels.setdefault(scenario, int(key))

    owner: dict[str, str] = {}
    for source in units:
        pack = "core"
        if source.startswith(BATTLE_COMMON):
            pack = "battle_common"
        elif source.startswith(MOVIE_DIR) and not source.endswith(".json"):
            stem = source[len(MOVIE_DIR):].split("_sheet_")[0].split(".")[0]
            pack = "movie_" + stem
        elif source.endswith(".ogg") and source not in title_music:
            pack = "music_" + Path(source).stem
        else:
            for rule in LEVEL_RULES:
                match = rule.match(source)
                if match:
                    pack = "level_%03d" % int(match.group(1))
                    break
            else:
                if source in named_levels:
                    pack = "level_%03d" % named_levels[source]
        owner[source] = pack
    music_dirs = defaultdict(set)
    for source, pack in owner.items():
        if pack.startswith("music_"):
            music_dirs[pack].add(source)
    for pack, sources in music_dirs.items():
        if len(sources) > 1:
            raise SystemExit(f"music stem collision for {pack}: {sorted(sources)}")

    lower_units = {s.lower(): s for s in units}
    dirs_index: dict[str, list[str]] = defaultdict(list)
    for source in units:
        parts = source.split("/")
        for i in range(1, len(parts)):
            dirs_index["/".join(parts[:i])].append(source)

    def resolve(ref: str) -> list[str]:
        rel = _rel(ref).split("#")[0].split("?")[0]
        if rel in units:
            return [rel]
        if rel.lower() in lower_units:
            return [lower_units[rel.lower()]]
        # A directory path is a base the code joins file names to; one that spans several packs
        # (an evidence note naming content/imported/hsl/chapter01) is no dependency.
        under = dirs_index.get(rel.rstrip("/"), [])
        return under if len({owner[u] for u in under}) == 1 else []

    def is_scenario(source: str) -> bool:
        return source.startswith("content/battles/") and source.endswith(".json") and "/" not in source[len("content/battles/"):]

    packs: dict[str, dict] = {}
    for source, pack in owner.items():
        if pack != "core":
            row = packs.setdefault(pack, {"files": [], "bytes": 0, "deps": set(), "sources": []})
            row["files"] += units[source]
            row["bytes"] += project.bytes[source]
            row["sources"].append(source)
    movie_packs = {p[len("movie_"):] for p in packs if p.startswith("movie_")}

    unresolved: dict[str, int] = defaultdict(int)
    core_into_packs: dict[str, set] = defaultdict(set)
    handoffs: dict[str, set] = defaultdict(set)

    def refs_of(source: str) -> tuple[set, set]:
        data = _read_json(root / source)
        found, movies = set(), set()
        if data is None:
            return found, movies
        for text in _strings(data):
            # Bare content/... strings are provenance notes (an actor template's source seed);
            # the runtime loads res:// paths.
            if not text.startswith("res://content/"):
                continue
            targets = resolve(text)
            if not targets:
                unresolved[source] += 1
            found.update(targets)
        movies.update(m for m in _movie_names(data) if m in movie_packs)
        return found, movies

    json_refs: dict[str, tuple[set, set]] = {}
    for source, pack in owner.items():
        if source.endswith(".json"):
            json_refs[source] = refs_of(source)
    for source, (targets, movies) in json_refs.items():
        pack = owner[source]
        for target in targets:
            target_pack = owner[target]
            if target_pack in ("core", pack):
                continue
            if is_scenario(target):
                handoffs[source].add(target)
                continue
            if pack == "core":
                core_into_packs[source].add(target_pack)
            else:
                packs[pack]["deps"].add(target_pack)
        if pack != "core":
            packs[pack]["deps"].update("movie_" + m for m in movies)
    for pack, row in packs.items():
        if pack.startswith("level_"):
            row["deps"].add("battle_common")

    def closure(seed: set) -> list[str]:
        seen, stack = set(), list(seed)
        while stack:
            item = stack.pop()
            if item in seen:
                continue
            seen.add(item)
            stack += sorted(packs[item]["deps"])
        return sorted(seen)

    def scene_group(source: str) -> list[str]:
        """Packs a core scene file (a world map JSON, the GameClear title-manifest section) needs."""
        targets, movies = json_refs.get(source, (set(), set()))
        seed = {owner[t] for t in targets if owner[t] != "core" and not is_scenario(t)}
        return closure(seed | {"movie_" + m for m in movies} | {"battle_common"})

    groups: dict[str, list[str]] = {}
    for pack in packs:
        if pack.startswith("level_"):
            groups["level:%d" % int(pack[len("level_"):])] = closure({pack})
        elif pack.startswith("movie_"):
            groups["movie:" + pack[len("movie_"):]] = closure({pack})
        elif pack.startswith("music_"):
            groups["music:" + pack[len("music_"):]] = closure({pack})
    clear_refs = {owner[t] for s in _strings(title.get("game_clear", {})) for t in resolve(s) if owner[t] != "core"}
    groups["scene:game_clear"] = closure(clear_refs | {"battle_common"})

    scenarios: dict[str, str] = {}
    for source, pack in owner.items():
        if is_scenario(source) and pack.startswith("level_"):
            scenarios["res://" + source] = "level:%d" % int(pack[len("level_"):])
    next_hints: dict[str, list[str]] = {}
    for campaign in campaigns:
        battles = campaign.get("battles", {})
        world_map = _rel(str((campaign.get("world_map") or {}).get("scenario", "")))
        point_range = (campaign.get("world_map") or {}).get("point_level_range", [])
        entries = [(key, _rel(str(entry.get("scenario", "")))) for key, entry in battles.items()]
        if world_map:
            entries.append(("", world_map))
        for key, scenario in entries:
            if scenario.endswith(".tscn"):
                scenarios["res://" + scenario] = "scene:game_clear"
                continue
            if not scenario or scenario not in units:
                continue
            res = "res://" + scenario
            if owner[scenario] == "core":
                group = "scene:" + scenario.removesuffix(".json")
                groups[group] = scene_group(scenario)
                scenarios[res] = group
            data = _read_json(root / scenario) or {}
            nexts: list[str] = []
            for event in _next_level_events(data):
                if event == BIG_MAP_LEVEL and world_map:
                    target = world_map
                else:
                    target = _rel(str(battles.get(str(event), {}).get("scenario", "")))
                if target and target != scenario and "res://" + target not in nexts:
                    nexts.append("res://" + target)
            if not nexts and world_map and key.isdigit() and len(point_range) == 2 and point_range[0] <= int(key) <= point_range[1]:
                nexts.append("res://" + world_map)
            if nexts:
                next_hints[res] = nexts

    # Development scenarios outside every campaign (trials, the first_battle fixture) borrow
    # level art too; a direct launch of one asks for its scene group.
    for source, pack in owner.items():
        if is_scenario(source) and pack == "core" and source != CAMPAIGN and "res://" + source not in scenarios:
            group = "scene:" + source.removesuffix(".json")
            groups[group] = scene_group(source)
            scenarios["res://" + source] = group

    core_exclude = _exclude_patterns(owner)
    core_bytes = sum(project.bytes[s] for s, p in owner.items() if p == "core") + project.other_bytes
    out_packs = {}
    for pack in sorted(packs):
        row = packs[pack]
        out_packs[pack] = {"files": ["res://" + f for f in sorted(row["files"])], "bytes": row["bytes"], "deps": sorted(row["deps"])}
    result = {
        "schema": PLAN_SCHEMA,
        "core_exclude": core_exclude,
        "packs": out_packs,
        "groups": dict(sorted(groups.items())),
        "scenarios": dict(sorted(scenarios.items())),
        "next": dict(sorted(next_hints.items())),
        "core": {"bytes": core_bytes, "content_files": sum(1 for p in owner.values() if p == "core")},
        "report": {
            "unresolved_refs": dict(sorted(unresolved.items())),
            "core_json_into_packs": {k: sorted(v) for k, v in sorted(core_into_packs.items())},
            "handoff_refs": {k: sorted(v) for k, v in sorted(handoffs.items())},
        },
    }
    errors = _check(result, owner, units)
    result["report"]["errors"] = errors
    return result


def _next_level_events(data) -> list[int]:
    events = []
    stack = [data]
    while stack:
        value = stack.pop()
        if isinstance(value, dict):
            if value.get("kind") == "next_level_event" or value.get("script_action_name") == "actSetNextPlayLevelEvent":
                args = value.get("args", [])
                token = str(args[1] if len(args) > 1 else args[0]) if args else ""
                event = BIG_MAP_LEVEL if token == "gameBigMapLevel" else int(token) if token.isdigit() else None
                if event is not None and event not in events:
                    events.append(event)
            stack += list(value.values())[::-1]
        elif isinstance(value, list):
            stack += value[::-1]
    return events


def _exclude_patterns(owner: dict[str, str]) -> list[str]:
    """Shortest wildcard list: a directory whose every game file is one pack's becomes `dir/*`."""
    dir_owners: dict[str, set] = defaultdict(set)
    for source, pack in owner.items():
        parts = source.split("/")
        for i in range(1, len(parts)):
            dir_owners["/".join(parts[:i])].add(pack)
    patterns = []
    covered: set[str] = set()
    for source in sorted(owner):
        pack = owner[source]
        if pack == "core":
            continue
        parts = source.split("/")
        chosen = source
        for i in range(2, len(parts)):
            directory = "/".join(parts[:i])
            if dir_owners[directory] == {pack}:
                chosen = directory + "/*"
                break
        if chosen not in covered:
            covered.add(chosen)
            patterns.append(chosen)
    return patterns


def _check(result: dict, owner: dict[str, str], units: dict) -> list[str]:
    errors = []
    patterns = result["core_exclude"]
    prefix_patterns = [p[:-1].lower() for p in patterns if p.endswith("/*") and "*" not in p[:-2] and "?" not in p]
    exact = {p.lower() for p in patterns if "*" not in p and "?" not in p}
    other = [p for p in patterns if not (p.endswith("/*") and "*" not in p[:-2] and "?" not in p) and ("*" in p or "?" in p)]
    for source, pack in owner.items():
        low = source.lower()
        matched = low in exact or any(low.startswith(p) for p in prefix_patterns) or any(godot_match(source, p) for p in other)
        if matched != (pack != "core"):
            errors.append(f"exclude mismatch: {source} owner={pack} matched={matched}")
    seen: dict[str, str] = {}
    for pack, row in result["packs"].items():
        for res in row["files"]:
            if res in seen:
                errors.append(f"{res} in {seen[res]} and {pack}")
            seen[res] = pack
        for dep in row["deps"]:
            if dep not in result["packs"]:
                errors.append(f"{pack} depends on unknown {dep}")
    for group, members in result["groups"].items():
        for pack in members:
            missing = set(result["packs"][pack]["deps"]) - set(members)
            if missing:
                errors.append(f"group {group} not closed: {pack} needs {sorted(missing)}")
    for scenario, group in result["scenarios"].items():
        if group not in result["groups"]:
            errors.append(f"scenario {scenario} names unknown group {group}")
    return errors


def _mb(value: int) -> str:
    return f"{value / 1e6:.1f} MB"


def print_summary(result: dict) -> None:
    packs = result["packs"]
    sizes = sorted(row["bytes"] for row in packs.values())
    total = result["core"]["bytes"] + sum(sizes)
    median = sizes[len(sizes) // 2] if sizes else 0
    print(f"WEB_PACKS_PLAN core={_mb(result['core']['bytes'])} packs={len(packs)} pack_min={_mb(sizes[0])} "
          f"pack_median={_mb(median)} pack_max={_mb(sizes[-1])} total={_mb(total)} exclude_patterns={len(result['core_exclude'])}")
    kinds = defaultdict(lambda: [0, 0])
    for pack, row in packs.items():
        kind = pack.split("_")[0]
        kinds[kind][0] += 1
        kinds[kind][1] += row["bytes"]
    print("WEB_PACKS_KINDS " + " ".join(f"{k}={v[0]}/{_mb(v[1])}" for k, v in sorted(kinds.items())))
    biggest = sorted(packs.items(), key=lambda kv: -kv[1]["bytes"])[:5]
    print("WEB_PACKS_LARGEST " + " ".join(f"{p}={_mb(r['bytes'])}" for p, r in biggest))
    cross = sorted((p, d) for p, r in packs.items() if p.startswith("level_") for d in r["deps"] if d.startswith("level_"))
    print(f"WEB_PACKS_CROSS_LEVEL_DEPS {len(cross)} " + " ".join(f"{p}->{d}" for p, d in cross[:12]))
    report = result["report"]
    print(f"WEB_PACKS_CORE_JSON_INTO_PACKS {len(report['core_json_into_packs'])} files " + " ".join(
        f"{k}:{len(v)}" for k, v in list(report["core_json_into_packs"].items())[:8]))
    print(f"WEB_PACKS_UNRESOLVED_REFS {sum(report['unresolved_refs'].values())} in {len(report['unresolved_refs'])} files")
    errors = report["errors"]
    for line in errors[:20]:
        print("WEB_PACKS_ERROR " + line)
    print("WEB_PACKS_INVARIANTS " + ("PASS" if not errors else f"FAIL {len(errors)}"))


def group_bytes(result: dict, groups: list[str]) -> int:
    members = {p for g in groups for p in result["groups"].get(g, [])}
    return sum(result["packs"][p]["bytes"] for p in members)


def build(root: Path, plan_path: Path, out: Path, godot: str) -> int:
    data = json.loads(plan_path.read_text(encoding="utf-8"))
    out.mkdir(parents=True, exist_ok=True)
    work = out / ".build"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    jobs = {"packs": []}
    for pack, row in data["packs"].items():
        jobs["packs"].append({"id": pack, "out": str((work / f"{pack}.pck").resolve()),
                              "files": [[res, str((root / _rel(res)).resolve())] for res in row["files"]]})
    job_file = work / "jobs.json"
    job_file.write_text(json.dumps(jobs), encoding="utf-8")
    command = [godot, "--headless", "--script", "res://tools/web/pack_builder.gd", "--", str(job_file.resolve())]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    sys.stdout.write(completed.stdout[-4000:])
    if completed.returncode != 0 or "PACK_BUILDER_DONE" not in completed.stdout:
        sys.stderr.write(completed.stderr[-4000:])
        print("WEB_PACKS_BUILD FAIL")
        return 1
    manifest = {"schema": MANIFEST_SCHEMA, "packs": {}, "groups": data["groups"], "scenarios": data["scenarios"], "next": data["next"]}
    keep = {"manifest.json"}
    for pack in data["packs"]:
        built = work / f"{pack}.pck"
        digest = hashlib.sha256(built.read_bytes()).hexdigest()
        name = f"{pack}-{digest[:8]}.pck"
        os.replace(built, out / name)
        keep.add(name)
        manifest["packs"][pack] = {"file": name, "bytes": (out / name).stat().st_size, "sha256": digest}
    shutil.rmtree(work)
    for stale in out.glob("*.pck"):
        if stale.name not in keep:
            stale.unlink()
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    total = sum(row["bytes"] for row in manifest["packs"].values())
    print(f"WEB_PACKS_BUILD PASS packs={len(manifest['packs'])} bytes={_mb(total)} out={out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    plan_cmd = sub.add_parser("plan")
    plan_cmd.add_argument("--project", type=Path, default=ROOT)
    plan_cmd.add_argument("--out", type=Path, required=True)
    plan_cmd.add_argument("--first-path", default="movie:start,level:51",
                          help="groups the first play path downloads after core (printed as WEB_PACKS_FIRST_PATH)")
    build_cmd = sub.add_parser("build")
    build_cmd.add_argument("--project", type=Path, default=ROOT)
    build_cmd.add_argument("--plan", type=Path, required=True)
    build_cmd.add_argument("--out", type=Path, required=True)
    build_cmd.add_argument("--godot", default=str(ROOT / "tools/godot.sh"))
    args = parser.parse_args(argv)
    if args.command == "plan":
        result = plan(args.project.resolve())
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print_summary(result)
        first = [g for g in args.first_path.split(",") if g]
        first_bytes = group_bytes(result, first)
        print(f"WEB_PACKS_FIRST_PATH groups={','.join(first)} packs={_mb(first_bytes)} "
              f"with_core={_mb(first_bytes + result['core']['bytes'])}")
        return 0 if not result["report"]["errors"] else 1
    return build(args.project.resolve(), args.plan, args.out, args.godot)


if __name__ == "__main__":
    sys.exit(main())
