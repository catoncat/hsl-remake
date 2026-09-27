#!/usr/bin/env bash
# Lead merge helper for lane branches — AGENTS.md「Lane 协议」合并节拍 in four steps.
#   tools/lane_merge.sh merge REF MSGFILE   merge one lane commit into pipeline-line (--no-ff); conflicts only in
#                                           generated docs are resolved by re-rendering them (always re-rendered)
#   tools/lane_merge.sh gate [--deep|--fast|--affected]
#                                           verify pipeline-line HEAD with the lead environment (HSL_VERIFY_PRIORITY=1:
#                                           the lead's own verify slot); log: /private/tmp/gate-<HEAD>.log. Default is
#                                           AUTO: when no file changed since main matches OUTCOME_PATHS (rules, battle
#                                           data, harness, verify tooling) it runs only the affected checks and suites
#                                           (tools/lane_verify.sh affected main, ~1-3 min); otherwise the fast gate
#                                           (tools/verify.sh, sweep included). 2026-09-26: a Tab hotkey ran the 128-battle
#                                           sweep twice (lane + lead) — a UI change must never pay for autoplay.
#                                           AUTO first: only *.md changed since an already-gated ancestor → doc
#                                           checks only (whitespace, links, tool references; seconds).
#   tools/lane_merge.sh publish [--dry-run] fast-forward main and presentation-line to pipeline-line, only if
#                                           the gate log for the current HEAD ends in VERIFY_PASS and no target
#                                           worktree has an untracked or edited file the fast-forward would
#                                           overwrite (LANE_PUBLISH_FAIL untracked=|dirty=|not-ff); --dry-run
#                                           runs the checks only (LANE_PUBLISH_SOURCE / LANE_PUBLISH_TARGETS
#                                           override the source branch and the target branches)
#   tools/lane_merge.sh cleanup WORKTREE... remove lane worktrees and their branches once merged into main
# Merge train: several `merge` calls, one `gate`, one `publish`. Bash 3.2 compatible.
set -euo pipefail

REAL_HOME="${HSL_REAL_HOME:-${HOME}}"
GATE_HOME="${HSL_GATE_HOME:-${REAL_HOME}/.pi-worktrees/gate-home}"
JOBS="${HSL_VERIFY_JOBS:-3}"

worktree_of() {
  git worktree list --porcelain | awk -v want="refs/heads/$1" '/^worktree /{p=substr($0,10)} $0=="branch " want {print p}'
}
PIPE="$(worktree_of pipeline-line)"
[ -n "${PIPE}" ] || { echo "LANE_MERGE_FAIL no pipeline-line worktree" >&2; exit 2; }
GENERATED="docs/PROVENANCE.md:provenance docs/KNOWLEDGE_INDEX.md:evidence_index docs/evidence_packets/static_reverse/parity_gap_inventory.md:parity_inventory docs/evidence_packets/static_reverse/parity_gap_inventory.json:parity_inventory content/generated/hsl/original_derived_manifest.json:original_derived_manifest"

cmd="${1:-}"; shift || true
case "${cmd}" in
  merge)
    ref="$1"; msg="$2"
    cd "${PIPE}"
    if out="$(git merge --no-ff --no-commit "${ref}" 2>&1)"; then :; else
      conflicts="$(git diff --name-only --diff-filter=U)"
      if [ -z "${conflicts}" ]; then
        printf '%s\n' "${out}" | tail -5
        echo "LANE_MERGE_FAIL merge ref=${ref} (git merge failed without conflicts)"
        exit 1
      fi
      for f in ${conflicts}; do
        task=""
        for pair in ${GENERATED}; do [ "${pair%%:*}" = "${f}" ] && task="${pair##*:}"; done
        if [ "${f}" = "docs/evidence_packets/static_reverse/parity_gap_inventory.curation.json" ]; then
          # Two lanes adding curation entries collide textually; the JSON union is the right merge.
          python3 tools/merge_curation_json.py || { echo "LANE_MERGE_CONFLICT ${f} (curation union failed)"; exit 1; }
          git add -- "${f}"; continue
        fi
        [ -n "${task}" ] || { echo "LANE_MERGE_CONFLICT ${f} (not generated; resolve by hand)"; exit 1; }
        git checkout --ours -- "${f}"
      done
    fi
    # Always re-render generated docs: two lanes that each add a packet merge without textual conflict
    # but leave the generated block stale.
    tasks=""; files=""
    for pair in ${GENERATED}; do tasks="${tasks} ${pair##*:}"; files="${files} ${pair%%:*}"; done
    tasks="$(printf '%s\n' ${tasks} | awk '!seen[$0]++' | tr '\n' ' ')"
    genlog="$(mktemp /private/tmp/lane-merge-generate.XXXXXX)"
    if ! WINEPREFIX="${WINEPREFIX:-${REAL_HOME}/.wine-hsl-original}" python3 tools/hsl.py generate ${tasks} >"${genlog}" 2>&1; then
      grep -E "FAIL|Error|error:" "${genlog}" | head -10 || tail -10 "${genlog}"
      echo "LANE_MERGE_FAIL generate tasks=${tasks% } log=${genlog} (merge of ${ref} left uncommitted; git merge --abort undoes it)"
      exit 1
    fi
    rm -f "${genlog}"
    # parity_inventory generate also drops classifications of packet sentences that no longer exist.
    git add ${files} docs/evidence_packets/static_reverse/parity_gap_inventory.curation.json
    git commit -q -F "${msg}" || { echo "LANE_MERGE_FAIL commit ref=${ref} (merge left uncommitted)"; exit 1; }
    echo "LANE_MERGE_OK $(git log -1 --format=%h) ref=${ref}"
    ;;
  gate)
    cd "${PIPE}"
    head="$(git rev-parse --short HEAD)"; log="/private/tmp/gate-${head}.log"
    mode="auto"; extra=""
    case "${1:-}" in
      --deep) mode="fast"; extra="--deep"; shift ;;
      --fast) mode="fast"; shift ;;
      --affected) mode="affected"; shift ;;
    esac
    if [ "${mode}" = auto ]; then
      # Docs-only since a gated ancestor → only the doc checks, seconds (2026-09-26: a two-line doc fix reran the
      # 7-minute gate). An ancestor counts when its log passed or reached repository hygiene (every heavy stage
      # passed; hygiene is exactly what this mode reruns). Changed files must all be *.md.
      base=""
      for c in $(git rev-list --max-count=20 HEAD~1 2>/dev/null); do
        cl="/private/tmp/gate-$(git rev-parse --short "${c}").log"
        [ -f "${cl}" ] || continue
        if tail -1 "${cl}" | grep -Eq "VERIFY_PASS|LANE_AFFECTED_PASS|LANE_DOCS_PASS" || grep -q '^== repository hygiene ==' "${cl}"; then base="${c}"; break; fi
      done
      if [ -n "${base}" ] && [ -z "$(git diff --name-only "${base}" HEAD -- | grep -v '\.md$' || true)" ]; then
        b="$(git rev-parse --short "${base}")"
        echo "LANE_GATE_MODE docs (auto: only *.md changed since gated ${b})"
        if { git diff --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- . \
               ':(exclude)content/imported/' ':(exclude)docs/external/' ':(exclude)*.svg' \
             && python3 tools/hsl_docs_check.py \
             && python3 tools/hsl.py check docs:tool_references; } >"${log}" 2>&1; then
          echo "LANE_DOCS_PASS head=${head} base=${b}" >>"${log}"; ec=0
        else ec=1; fi
        grep -E "_FAIL|FAILED" "${log}" | head -5 || true
        echo "LANE_GATE head=${head} mode=docs exit=${ec} $(tail -1 "${log}")"
        exit "${ec}"
      fi
      # Paths whose change can move a battle outcome (rules, data, harness, verify tooling) → fast gate with sweep.
      # Asset importers (tools/hsltools/assets/) only write content/imported/ and never count (2026-09-26: the
      # music importer sent a pure asset merge through the 128-battle sweep).
      OUTCOME_PATHS='^(game/sim/|game/battle/scene/BattleLoop|game/battle/scene/BattlePlayLoop|game/battle/runtime/(Battle|Campaign|Growth|Actor)|content/(battles|generated/hsl/(chapter|treasures|autoplay|static))|tests/support/|tests/run_battle_sweep|tools/verify|tools/hsltools/)'
      changed="$(git diff --name-only main HEAD -- 2>/dev/null || true)"
      outcome_changed="$(printf '%s\n' "${changed}" | grep -Ev '^tools/hsltools/assets/' | grep -E "${OUTCOME_PATHS}" || true)"
      if [ -n "${outcome_changed}" ]; then mode="fast"; else mode="affected"; fi
      echo "LANE_GATE_MODE ${mode} (auto: $(printf '%s' "${outcome_changed}" | grep -c . || true) outcome-path files changed since main)"
    fi
    mkdir -p "${GATE_HOME}"
    set +e
    if [ "${mode}" = affected ]; then
      env HOME="${GATE_HOME}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" XDG_CONFIG_HOME="${REAL_HOME}/.config" \
        PYTHONDONTWRITEBYTECODE=1 HSL_VERIFY_JOBS="${JOBS}" HSL_VERIFY_PRIORITY=1 \
        tools/lane_verify.sh affected main >"${log}" 2>&1
      ec=$?
      # project.godot (autoloads, input map) is referenced by no suite: prove the main path still boots, both presets.
      if [ "${ec}" = 0 ] && printf '%s\n' "${changed}" | grep -qx 'project.godot'; then
        for preset in original comfort; do
          if ! env HOME="${GATE_HOME}" PYTHONDONTWRITEBYTECODE=1 HSL_OPTIONS_PRESET="${preset}" tools/godot.sh --headless --script res://tests/run_scene_smoke.gd >>"${log}" 2>&1; then ec=1; fi
        done
        [ "${ec}" = 0 ] && echo "LANE_AFFECTED_PASS project.godot changed: scene smoke original+comfort ok; $(grep -m1 LANE_VERIFY_PASS "${log}")" >>"${log}"
      fi
      # affected defers the Godot suites when too many are hit (LANE_AFFECTED_GODOT_DEFERRED): that is not a
      # verdict — fall through to the fast gate (2026-09-27: UIFIX published with 39 suites deferred and a red
      # presentation contract).
      if grep -q 'LANE_AFFECTED_GODOT_DEFERRED' "${log}"; then
        echo "LANE_GATE_MODE fast (affected deferred Godot suites: $(grep -o 'LANE_AFFECTED_GODOT_DEFERRED suites=[0-9]*' "${log}" | head -1))"
        mode="fast"
        env HOME="${GATE_HOME}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" XDG_CONFIG_HOME="${REAL_HOME}/.config" \
          PYTHONDONTWRITEBYTECODE=1 HSL_VERIFY_JOBS="${JOBS}" HSL_VERIFY_PRIORITY=1 WINEPREFIX="${REAL_HOME}/.wine-hsl-original" \
          tools/verify.sh ${extra} "$@" >"${log}" 2>&1
        ec=$?
      fi
      false; [ "${ec}" = 0 ]
    else
      env HOME="${GATE_HOME}" GIT_CONFIG_GLOBAL="${REAL_HOME}/.gitconfig" XDG_CONFIG_HOME="${REAL_HOME}/.config" \
        PYTHONDONTWRITEBYTECODE=1 HSL_VERIFY_JOBS="${JOBS}" HSL_VERIFY_PRIORITY=1 WINEPREFIX="${REAL_HOME}/.wine-hsl-original" \
        tools/verify.sh ${extra} "$@" >"${log}" 2>&1
    fi
    ec=$?
    set -e
    grep -E "_FAIL|FAILED" "${log}" | head -5 || true
    echo "LANE_GATE head=${head} mode=${mode} exit=${ec} $(tail -1 "${log}")"
    exit "${ec}"
    ;;
  publish)
    dry=0
    [ "${1:-}" = "--dry-run" ] && dry=1
    source_ref="${LANE_PUBLISH_SOURCE:-pipeline-line}"
    targets="${LANE_PUBLISH_TARGETS:-main presentation-line}"
    head="$(git rev-parse --short "${source_ref}")"; log="/private/tmp/gate-${head}.log"
    if ! tail -1 "${log}" 2>/dev/null | grep -Eq "VERIFY_PASS|LANE_AFFECTED_PASS|LANE_DOCS_PASS"; then
      [ "${dry}" = 1 ] || { echo "LANE_PUBLISH_FAIL no passing gate log for ${head}" >&2; exit 1; }
      echo "LANE_PUBLISH_DRY gate=missing (no passing ${log}; a real publish would stop here)"
    fi
    # Preflight every target before fast-forwarding any: `merge --ff-only` aborts on an untracked file with the
    # name of a file it would bring in, and on local edits to such a file (499cdd2f: an untracked
    # tests/play_battle.gd in the main worktree stopped the publish and main stayed 3.5 h behind unnoticed).
    bad=0; ready=""
    for b in ${targets}; do
      wt="$(worktree_of "${b}")"
      [ -n "${wt}" ] || { echo "LANE_PUBLISH_SKIP ${b} (no worktree)"; continue; }
      tip="$(git -C "${wt}" rev-parse HEAD)"
      git merge-base --is-ancestor "${tip}" "${source_ref}" || { echo "LANE_PUBLISH_FAIL not-ff target=${b} (${b} has commits ${source_ref} lacks)" >&2; bad=1; continue; }
      incoming="$(git -c core.quotepath=false diff --no-renames --name-only "${tip}" "${source_ref}" --)"
      [ -n "${incoming}" ] || { echo "LANE_PUBLISH_SKIP ${b} (already at ${head})"; continue; }
      clash="$( (printf '%s\n' "${incoming}"; git -c core.quotepath=false -C "${wt}" ls-files --others --exclude-standard) | sort | uniq -d)"
      dirty="$( (printf '%s\n' "${incoming}"; git -c core.quotepath=false -C "${wt}" diff --name-only HEAD --) | sort | uniq -d)"
      if [ -n "${clash}${dirty}" ]; then
        [ -z "${clash}" ] || printf '%s\n' "${clash}" | sed "s|^|LANE_PUBLISH_FAIL untracked=|; s|\$| target=${b} worktree=${wt}|" >&2
        [ -z "${dirty}" ] || printf '%s\n' "${dirty}" | sed "s|^|LANE_PUBLISH_FAIL dirty=|; s|\$| target=${b} worktree=${wt}|" >&2
        bad=1; continue
      fi
      ready="${ready} ${b}"
    done
    [ "${bad}" = 0 ] || exit 1
    if [ "${dry}" = 1 ]; then
      echo "LANE_PUBLISH_DRY_OK ${head} targets=${ready# }"
      exit 0
    fi
    for b in ${ready}; do
      git -C "$(worktree_of "${b}")" merge -q --ff-only "${source_ref}" || { echo "LANE_PUBLISH_FAIL merge target=${b}" >&2; exit 1; }
    done
    echo "LANE_PUBLISH_OK ${head} targets=${ready# }"
    ;;
  cleanup)
    for wt in "$@"; do
      br="$(git -C "${wt}" branch --show-current)"
      git merge-base --is-ancestor "${br}" main || { echo "LANE_CLEANUP_SKIP ${br} not in main"; continue; }
      git worktree remove --force "${wt}" && git branch -D "${br}" >/dev/null
      echo "LANE_CLEANUP_OK ${br}"
    done
    ;;
  *)
    sed -n '2,15p' "$0"; exit 2
    ;;
esac
