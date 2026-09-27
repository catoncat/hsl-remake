#!/usr/bin/env bash
# Read-only environment and repository preflight. Does not launch Wine or Godot UI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-/opt/homebrew/bin/python3}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
WINE_BIN="${WINE_BIN:-/opt/homebrew/bin/wine}"
CLICLICK_BIN="${CLICLICK_BIN:-/opt/homebrew/bin/cliclick}"
ORIGINAL=0

if [[ "${1:-}" == "--original" ]]; then
  ORIGINAL=1
elif [[ $# -gt 0 ]]; then
  echo "usage: tools/doctor.sh [--original]" >&2
  exit 2
fi

errors=0
warnings=0
ok() { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; errors=$((errors + 1)); }

cd "$ROOT"
[[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" == "$ROOT" ]] && ok "git root: $ROOT" || fail "not inside the expected git repository"
[[ -f project.godot ]] && ok "project.godot present" || fail "project.godot missing"
grep -q 'run/main_scene="res://game/title/TitleScreen.tscn"' project.godot \
  && ok "main scene is the title screen (TitleScreen.tscn -> BattleSceneRuntime.tscn)" \
  || fail "project main scene is not TitleScreen"
[[ -f game/title/TitleScreen.tscn && -f game/battle/scene/BattleSceneRuntime.tscn ]] \
  && ok "title and battle runtime scenes present" \
  || fail "TitleScreen.tscn or BattleSceneRuntime.tscn missing"

for required in README.md AGENTS.md docs/PROJECT.md docs/ARCHITECTURE.md docs/KNOWLEDGE_INDEX.md requirements-dev.txt; do
  [[ -f "$required" ]] && ok "$required present" || fail "$required missing"
done

if git worktree list --porcelain | grep -q '^prunable '; then
  fail "stale/prunable git worktree metadata exists"
else
  ok "git worktree metadata is clean"
fi

if [[ -x "$PYTHON_BIN" ]]; then
  if "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    ok "Python: $($PYTHON_BIN --version 2>&1)"
    if pillow_version=$("$PYTHON_BIN" -c 'import PIL; print(PIL.__version__)' 2>/dev/null); then
      ok "Pillow: $pillow_version"
    else
      fail "Pillow missing; run: $PYTHON_BIN -m pip install -r requirements-dev.txt"
    fi
  else
    fail "Python 3.10+ required: $PYTHON_BIN"
  fi
else
  fail "Python executable missing: $PYTHON_BIN"
fi

if [[ -x "$GODOT_BIN" ]]; then
  godot_version="$($GODOT_BIN --version | head -n 1)"
  required_godot=$(sed -n 's/.*config\/features=PackedStringArray("\([0-9][0-9.]*\)").*/\1/p' project.godot)
  if "$PYTHON_BIN" - "$godot_version" "$required_godot" <<'PY_VERSION'
import re
import sys

def version(text: str) -> tuple[int, int]:
    match = re.search(r"(\d+)\.(\d+)", text)
    if not match:
        raise SystemExit(2)
    return int(match.group(1)), int(match.group(2))

actual = version(sys.argv[1])
required = version(sys.argv[2])
raise SystemExit(0 if actual >= required else 1)
PY_VERSION
  then
    ok "Godot: $godot_version (project requires $required_godot+)"
  else
    fail "Godot $required_godot+ required; found: $godot_version"
  fi
else
  fail "Godot executable missing: $GODOT_BIN"
fi


# Original-derived content absent (a public checkout before the import, hsltools.original_content):
# the scenario check has nothing to read.
if ! "$PYTHON_BIN" -c 'import sys; sys.path.insert(0, "tools"); from hsltools import original_content; sys.exit(0 if original_content.present() else 1)'; then
  ok "SKIP original-absent: first battle scenario not imported (HSL_ORIGINAL_DIR=... python3 tools/hsl.py generate ...)"
elif "$PYTHON_BIN" - <<'PY_SCENARIO'
import json
from pathlib import Path

# The campaign's first battle (campaign.json start_level) is a generic level battle; the
# reviewed formation fixture keeps the same 12-unit roster for the mechanics suites.
campaign = json.loads(Path("content/battles/campaign.json").read_text(encoding="utf-8"))
start = str(campaign["start_level"])
path = Path(str(campaign["battles"][start]["scenario"]).removeprefix("res://"))
assert path == Path("content/battles/battle_051.json"), path
data = json.loads(path.read_text(encoding="utf-8"))
assert data.get("schema") == "hsl_level_battle.v1" and data.get("rule_adapter") == "winfail"
assert data.get("player_unit_id") == "leonard"
assert len(data.get("playable_units", [])) == 12
fixture = json.loads(Path("content/battles/first_battle.json").read_text(encoding="utf-8"))
assert fixture.get("rule_adapter") == "development_battle" and len(fixture.get("playable_units", [])) == 12
for document in (data, fixture):
    for resource in document.get("resources", {}).values():
        assert isinstance(resource, str) and resource.startswith("res://")
        assert Path(resource.removeprefix("res://")).exists(), resource
PY_SCENARIO
then
  ok "first battle (campaign start_level -> battle_051.json) and the formation fixture reference existing resources"
else
  fail "content/battles/battle_051.json / first_battle.json is invalid or references missing resources"
fi

for route in tools/routes/*.txt; do
  if tools/hsl_capture.sh --dry-run "$route" >/dev/null; then
    ok "route syntax: $route"
  else
    fail "invalid route: $route"
  fi
done

tracked_imports=()
while IFS= read -r file; do
  [[ -e "$file" ]] && tracked_imports+=("$file")
done < <(git ls-files -- '*.import')
if [[ ${#tracked_imports[@]} -eq 0 ]]; then
  ok "no tracked Godot .import cache files"
else
  fail "tracked Godot .import cache files: ${tracked_imports[*]}"
fi

missing_uids=()
while IFS= read -r -d '' script; do
  [[ -f "${script}.uid" ]] || missing_uids+=("$script")
done < <(find game tests -type f -name '*.gd' -print0)

orphan_uids=()
while IFS= read -r -d '' uid_file; do
  script="${uid_file%.uid}"
  [[ -f "$script" ]] || orphan_uids+=("$uid_file")
done < <(find game tests -type f -name '*.gd.uid' -print0)

if [[ ${#missing_uids[@]} -eq 0 && ${#orphan_uids[@]} -eq 0 ]]; then
  ok "live GDScript UID sidecars are complete"
else
  [[ ${#missing_uids[@]} -eq 0 ]] || fail "GDScript files missing .uid sidecars: ${missing_uids[*]}"
  [[ ${#orphan_uids[@]} -eq 0 ]] || fail "orphan .gd.uid sidecars: ${orphan_uids[*]}"
fi

if [[ "$ORIGINAL" -eq 1 ]]; then
  prefix="${WINEPREFIX:-$HOME/.wine-hsl-original}"
  [[ -x "$WINE_BIN" ]] && ok "Wine: $($WINE_BIN --version)" || fail "Wine missing: $WINE_BIN"
  [[ -f "$prefix/drive_c/hsl/hsl01.exe" ]] && ok "original hsl01.exe present" || fail "original hsl01.exe missing under $prefix"
  [[ -f "$prefix/drive_c/hsl/ddraw.dll" ]] && ok "cnc-ddraw present" || fail "ddraw.dll missing under $prefix"
  [[ -x "$CLICLICK_BIN" ]] \
    && ok "cliclick: $CLICLICK_BIN ($($CLICLICK_BIN -V 2>&1 | tail -n 1))" \
    || warn "cliclick not found: $CLICLICK_BIN (legacy/manual automation only)"
  if [[ -x tools/hsl_window && -x tools/hsl_input ]]; then
    ok "runtime helpers present"
    [[ ! tools/hsl_window.swift -nt tools/hsl_window ]] \
      && ok "hsl_window binary matches current source timestamp" \
      || fail "hsl_window is stale; run tools/build_runtime_helpers.sh"
    [[ ! tools/hsl_input.swift -nt tools/hsl_input ]] \
      && ok "hsl_input binary matches current source timestamp" \
      || fail "hsl_input is stale; run tools/build_runtime_helpers.sh"
  else
    fail "runtime helpers missing; run tools/build_runtime_helpers.sh"
  fi
  if [[ -f ignored/bin/hsl_win32_memread.exe ]]; then
    ok "optional win32-rpm scalar helper present"
    [[ ! tools/hsl_win32_memread.c -nt ignored/bin/hsl_win32_memread.exe ]] \
      && ok "win32-rpm helper matches current source timestamp" \
      || fail "win32-rpm helper is stale; run tools/build_runtime_helpers.sh --win32-rpm"
  else
    warn "win32-rpm helper missing; run tools/build_runtime_helpers.sh --win32-rpm before scalar memory probes"
  fi
fi

if [[ "$errors" -gt 0 ]]; then
  echo "doctor failed: errors=$errors warnings=$warnings" >&2
  exit 1
fi
echo "doctor passed: warnings=$warnings"
