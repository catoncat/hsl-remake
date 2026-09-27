#!/usr/bin/env bash
# Seed one checkout's Godot import cache from another checkout of this project, so the
# first `tools/godot.sh --headless --import` there only reconciles what differs instead of
# importing ~16k images from scratch (lane worktrees, fresh clones). Copies .godot/ (APFS
# clones on macOS, so no extra disk) plus the ignored *.import sidecars whose resource
# exists in the target. tools/godot.sh runs this with --auto whenever .godot/imported is
# missing; the target still imports once afterwards to reconcile anything that differs.
#
#   tools/godot_cache_seed.sh SOURCE_CHECKOUT [TARGET_CHECKOUT]   (target defaults to this repo)
#   tools/godot_cache_seed.sh --auto [TARGET_CHECKOUT]            source: $HSL_GODOT_SEED, else the
#       worktree of this repository whose last successful import finished most recently
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: tools/godot_cache_seed.sh SOURCE_CHECKOUT|--auto [TARGET_CHECKOUT]" >&2
  exit 2
fi
if [[ $# -eq 2 ]]; then
  DST="$(cd "$2" && pwd)"
else
  DST="$(cd "$(dirname "$0")/.." && pwd)"
fi

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }  # GNU first: GNU `stat -f` prints file-system info before failing

if [[ "$1" == --auto ]]; then
  SRC=""
  if [[ -n "${HSL_GODOT_SEED:-}" ]]; then
    SRC="$(cd "$HSL_GODOT_SEED" && pwd)"
  else
    # Rank the other worktrees: a completed import (tools/godot.sh stamp) beats a bare cache.
    best=-1
    while IFS= read -r line; do
      [[ "$line" == "worktree "* ]] || continue
      tree="${line#worktree }"
      [[ "$tree" != "$DST" && -d "$tree/.godot/imported" ]] || continue
      if [[ -f "$tree/.godot/hsl-import/end" ]]; then
        rank=$(( $(mtime "$tree/.godot/hsl-import/end") + 1000000000 ))
      else
        rank=$(mtime "$tree/.godot/imported")
      fi
      if (( rank > best )); then best=$rank; SRC="$tree"; fi
    done < <(git -C "$DST" worktree list --porcelain 2>/dev/null || true)
  fi
  [[ -n "$SRC" ]] || exit 0  # nothing to seed from: the import runs cold
else
  SRC="$(cd "$1" && pwd)"
fi
if [[ ! -d "$SRC/.godot/imported" ]]; then
  echo "no import cache at $SRC/.godot (run tools/godot.sh --headless --import there first)" >&2
  exit 1
fi
if [[ "$SRC" == "$DST" ]]; then
  echo "source and target are the same checkout" >&2
  exit 1
fi

started=$SECONDS
clone_tree() {  # copy the contents of $1 into $2 (clonefile on APFS, plain copy elsewhere)
  cp -cR "$1/." "$2/" 2>/dev/null || cp -R "$1/." "$2/"
}
if [[ -e "$DST/.godot" ]]; then
  clone_tree "$SRC/.godot" "$DST/.godot"
else
  # Build beside the target and rename, so a concurrent godot.sh never sees half a cache.
  tmp="$(mktemp -d "$DST/.godot-seed.XXXXXX")"
  clone_tree "$SRC/.godot" "$tmp"
  [[ -e "$DST/.godot" ]] || mv "$tmp" "$DST/.godot"
  # No `rm -rf`: a lane sandbox without a TTY blocks that spelling mid-script (STATUSPAGE 2026-09-27:
  # the seed then stopped here, every resource failed to load and lane_verify idled 18 min).
  [[ -e "$tmp" ]] && python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$tmp"
fi
# The source's import stamps describe the source's files; the target must import once itself.
python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$DST/.godot/hsl-import"

# Sidecars: every *.import outside hidden directories (.git, .godot, nested .claude worktrees)
# whose resource also exists in the target.
list="$(mktemp "${TMPDIR:-/tmp}/hsl-seed.XXXXXX")"
trap 'rm -f -- "$list"' EXIT
(cd "$SRC" && find . -name '.?*' -prune -o -name '*.import' -type f -print) | while IFS= read -r rel; do
  if [[ -e "$DST/${rel%.import}" ]]; then printf '%s\0' "${rel#./}"; fi
done > "$list"
sidecars="$(tr -cd '\0' < "$list" | wc -c | tr -d ' ')"
rsync -a --from0 --files-from="$list" "$SRC/" "$DST/"
echo "GODOT_CACHE_SEEDED from=$SRC to=$DST sidecars=$sidecars seconds=$((SECONDS - started))" >&2
