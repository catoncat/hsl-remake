#!/usr/bin/env bash
# Machine-wide cap on concurrent tools/verify.sh runs; sourced by tools/verify.sh, not run directly.
#
# Two mkdir slots under $HSL_VERIFY_LOCK_DIR (default /tmp/hsl-verify-slots):
#   lead     only for HSL_VERIFY_PRIORITY=1 (tools/lane_merge.sh gate), so the lead never queues behind lanes
#   shared   every other run (lane fast gates, ad-hoc runs); a lead run also takes it when "lead" is busy
# A waiting run polls every 2 s and prints `VERIFY_WAIT slot=<wanted> waiting=<N>s holders=...` at once and
# then every 30 s; `VERIFY_SLOT slot=<name> waited=<N>s` once it holds a slot. A slot whose owner process is
# gone (or whose PID was reused: different start time) is reaped. The slot is released on exit.
# Why: on 2026-09-25 17:21-17:44 four fast gates overlapped on this 10-core / 16 GB machine and stretched the
# Python unit tests 32->246 s, the source checks 42->324 s and the Godot import 5->109 s.
# Bash 3.2 compatible.

VERIFY_SLOT_DIR="${HSL_VERIFY_LOCK_DIR:-/tmp/hsl-verify-slots}"
VERIFY_SLOT_HELD=""
VERIFY_SLOT_OWNER=""

verify_slot_lstart() {
  ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//' || true
}

# 0 when PATH is held by a live owner (or was created in the last 10 s and its owner file is not written yet).
verify_slot_alive() {
  local path="$1" owner pid recorded mtime
  [ -d "$path" ] || return 1
  if [ ! -f "$path/owner" ]; then
    mtime="$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0)"  # GNU first (see godot_cache_seed.sh)
    [ $(( $(date +%s) - mtime )) -lt 10 ]
    return
  fi
  owner="$(cat "$path/owner" 2>/dev/null)" || return 0
  pid="${owner%%|*}"
  recorded="$(printf '%s' "$owner" | cut -d'|' -f2)"
  kill -0 "$pid" 2>/dev/null || return 1
  [ "$(verify_slot_lstart "$pid")" = "$recorded" ]
}

verify_slot_reap() {
  local path="$1" stale="$1.reap.$$"
  mv "$path" "$stale" 2>/dev/null || return 0
  if verify_slot_alive "$stale"; then
    # Lost a race (the slot was re-taken between the check and the rename): hand it back.
    [ -e "$path" ] || mv "$stale" "$path" 2>/dev/null || true
  fi
  rm -rf "$stale"
}

verify_slot_try() {
  local path="$VERIFY_SLOT_DIR/$1"
  if ! mkdir "$path" 2>/dev/null; then
    verify_slot_alive "$path" && return 1
    verify_slot_reap "$path"
    mkdir "$path" 2>/dev/null || return 1
  fi
  VERIFY_SLOT_OWNER="$$|$(verify_slot_lstart $$)|$PWD"
  printf '%s\n' "$VERIFY_SLOT_OWNER" >"$path/owner"
  VERIFY_SLOT_HELD="$path"
}

verify_slot_holders() {
  local s owner out=""
  for s in lead shared; do
    owner="$(cat "$VERIFY_SLOT_DIR/$s/owner" 2>/dev/null || true)"
    [ -n "$owner" ] && out="$out $s=pid${owner%%|*}:$(basename "${owner##*|}")"
  done
  printf '%s' "${out# }"
}

verify_slot_release() {
  if [ -n "$VERIFY_SLOT_HELD" ] && [ "$(cat "$VERIFY_SLOT_HELD/owner" 2>/dev/null)" = "$VERIFY_SLOT_OWNER" ]; then
    rm -rf "$VERIFY_SLOT_HELD"
  fi
  VERIFY_SLOT_HELD=""
}

verify_slot_acquire() {
  local slots s started=$SECONDS next=0 waited
  if [ "${HSL_VERIFY_PRIORITY:-0}" = 1 ]; then slots="lead shared"; else slots="shared"; fi
  mkdir -p "$VERIFY_SLOT_DIR"
  trap verify_slot_release EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while :; do
    for s in $slots; do
      if verify_slot_try "$s"; then
        echo "VERIFY_SLOT slot=$s waited=$((SECONDS - started))s"
        return 0
      fi
    done
    waited=$((SECONDS - started))
    if [ "$waited" -ge "$next" ]; then
      echo "VERIFY_WAIT slot=${slots// /|} waiting=${waited}s holders=$(verify_slot_holders)"
      next=$((next + 30))
    fi
    sleep 2
  done
}
