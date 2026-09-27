"""Opening snapshot, original side: every registered object's whole live record at the first
round-queue sort, per level — the input of hsltools.probes.opening_snapshot (the diff).

Diagnostic tool beside the enemy_turn referee (no registry task of its own). It enters each
level exactly as _enemy_level.py does (round_sort_machine: WinMain boot, carried slots enabled
by 0x42cb30, 0x42da60 with the load flag clear, the level's own frame loop with the dialogue
clicks and opening menu picks, halt at the first 0x407340 entry — after the opening scripts and
every opening birth 0x407cc0, before round 1's queue is built) and reads, for each non-empty
registry slot 0x4c34c0[0..199]:

- the object: pixel cell (+4／+8 >> 5), flags +0x80, process mode +0x8c, held target +0x88,
  registry word +0xa0, PLAYERS row +0xa2, live index +0xa4, the frame-delay word +0x7c
  (0x407dba rand(24));
- the live record [0x4c1bc8] + (+0xa4)·0x1fc, all 0x1fc bytes (hex). The diff decodes it by its
  field table; nothing is interpreted here.

Levels 18／53／79 are read at the second 0x407340 entry instead (LATE_LEVELS).

Two growth modes:

- g0 (growth false, _enemy_level's LevelDriver): the opening level-up growth words live
  +0x1f8／+0x1fa are zeroed where 0x40e870 is called (0x43eefb NPC, 0x44345d player), so every
  birth keeps its template level (base-level inference 0x40e800 and the refresh still run);
  the carry roll 0x407c40 and the frame delay still draw. Cached per level (ignored/native_cache).
- g1 SEED (the real opening): before 0x42da60 the global words 0x4795d4／0x4795d8 are written
  [SEED, SEED ^ 0xe54a231c] with the seeded flag 0x4c1e8c = 1 — the lazy seed 0x458bb0 stores
  for clock value SEED, the start the remake's export_opening_snapshot.gd --seeds gives
  GlobalRandomStream.seeded(SEED). Not cached (the seed is written before the level).

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
      tools/hsltools/probes/_opening_snapshot.py --levels 3,51,52 --modes g0,g1 --seeds 1,2,3 --jobs 3
  (default --levels: every level of content/generated/hsl/development/autoplay/results.json;
   output ignored/opening_snapshot/original/L051_g0.json, L051_g1_s1.json, ..., one per run)
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_opening_snapshot.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402

OUT = ROOT / 'ignored/opening_snapshot/original'
LEVELS_SOURCE = ROOT / 'content/generated/hsl/development/autoplay/results.json'
SEED_XOR = 0xe54a231c   # 0x458c20: the lazy seed stores [t, t ^ 0xe54a231c]
# Levels whose first 0x407340 comes one round before anyone acts (the round counter reads 1 and the
# first acting round is 2, _enemy_level.LevelRun.acting_round; BATCH126): the opening script is
# still inserting units then (level 53 has one registered object at that sort). Their snapshot is
# taken at the next 0x407340 entry — the first acting round's sort — with player turns in between
# ended as the referee ends them (LevelRun: +0x8c = 0x10000 when the idle menu runs).
LATE_LEVELS = (18, 53, 79)
OBJECT_WORDS = {'flags': (0x80, 4), 'mode': (0x8c, 4), 'held': (0x88, 2), 'registry_word': (0xa0, 2),
                'row': (0xa2, 2), 'live_index': (0xa4, 4), 'frame_delay': (0x7c, 4)}


def default_levels() -> list[int]:
    return sorted(int(level) for level in json.loads(LEVELS_SOURCE.read_text(encoding='utf-8'))['levels'])


def run_name(level: int, mode: str, seed: int | None) -> str:
    return f'L{level:03d}_{mode}' + (f'_s{seed}' if seed is not None else '')


def snapshot(exe: Path, level: int, mode: str, seed: int | None = None, use_cache: bool = True) -> dict:
    """One run: the level entered to its round-1 halt, every registry object and its live record."""
    from hsltools.probes import _enemy_level as el
    from hsltools.probes import enemy_turn as et

    def seed_global(machine) -> None:
        machine.put(et.GLOBAL_STATE[0], seed & 0xffffffff)
        machine.put(et.GLOBAL_STATE[1], (seed ^ SEED_XOR) & 0xffffffff)
        machine.put(et.SEEDED, 1)

    started = time.time()
    growth = mode == 'g1'
    machine, driver, info = el.round_sort_machine(exe, level, growth, use_cache and not growth, tuple(el.carried_slots(level)),
                                                  el.MENU_CHOICES.get(level, ()), seed_global if growth else None)
    names = et.remake_names(machine, el.battle_path(level), by_coord=True)
    sorts = 1
    if level in LATE_LEVELS:
        el.LevelRun(machine, names, driver, machine.get16(et.ROUND) + 8, el.ROUND_FRAMES)   # ends player turns
        if not growth:   # the births after the first sort keep their growth words zeroed too (LevelDriver's hooks)
            driver._growth_hooks = [machine.hook(el.NPC_GROWTH_READ, lambda: driver._zero(driver._record(machine.mu.reg_read(driver._ebp)))),
                                    machine.hook(el.PLAYER_GROWTH_READ, lambda: driver._zero(machine.eax()))]
        seen = [0]

        def at_sort() -> None:
            seen[0] += 1
            if seen[0] > 1:
                machine.halt('round_sort')
        hook = machine.hook(el.ROUND_SORT, at_sort)
        machine.resume()
        machine.unhook(hook)
        driver.stop_growth_off()
        if machine.halted != 'round_sort':
            raise RuntimeError(f'level {level}: no second 0x407340 ({machine.halted or machine.stop_reason})')
        sorts = 2
        names = et.remake_names(machine, el.battle_path(level), by_coord=True)
    live = machine.get(et.LIVE_TABLE)
    units = []
    for slot in range(et.REGISTRY_SLOTS):
        obj = machine.get(et.REGISTRY + 4 * slot)
        if not obj:
            continue
        words = {key: (machine.get16(obj + offset) if size == 2 else machine.get(obj + offset)) for key, (offset, size) in OBJECT_WORDS.items()}
        record = live + et.LIVE_SIZE * words['live_index']
        units.append({'slot': slot, 'object': f'{obj:#x}', 'name': names.get(obj),
                      'cell': [machine.geti(obj + et.OBJ_X) >> 5, machine.geti(obj + et.OBJ_Y) >> 5], 'object_words': words,
                      'record': bytes(machine.mu.mem_read(record, et.LIVE_SIZE)).hex()})
    opening = {key: info[key] for key in ('frame', 'clicks', 'round', 'carried_slots', 'cache') if key in info}
    opening.update(sort=sorts, round_at_snapshot=machine.get16(et.ROUND), frame_at_snapshot=driver.frame)
    opening['zeroed'] = len(driver.zeroed)
    return {'schema': 'hsl_opening_snapshot_original.v1', 'level': level, 'mode': mode, 'seed': seed,
            'global_after': [machine.get(et.GLOBAL_STATE[0]), machine.get(et.GLOBAL_STATE[1])],
            'opening': opening, 'seconds': round(time.time() - started, 1), 'units': units}


def _job(job: tuple) -> dict:
    exe, level, mode, seed, out = job
    name = run_name(level, mode, seed)
    started = time.time()
    try:
        data = snapshot(Path(exe), level, mode, seed)
    except Exception as error:   # a level the referee cannot enter: a row, not a batch failure
        data = {'schema': 'hsl_opening_snapshot_original.v1', 'level': level, 'mode': mode, 'seed': seed,
                'error': f'{type(error).__name__}: {error}', 'seconds': round(time.time() - started, 1)}
    Path(out, name + '.json').write_text(json.dumps(data, ensure_ascii=False) + '\n', encoding='utf-8')
    return {'run': name, 'units': len(data.get('units', [])), 'seconds': data['seconds'], 'error': data.get('error')}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Original opening snapshots at the round-1 queue sort, one JSON per level run.')
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    parser.add_argument('--levels', help='comma list (default: the autoplay results.json levels)')
    parser.add_argument('--modes', default='g0,g1')
    parser.add_argument('--seeds', default='1,2,3', help='g1 global seeds (clock value t)')
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--skip-existing', action='store_true')
    args = parser.parse_args(argv)
    from concurrent.futures import ProcessPoolExecutor
    args.out.mkdir(parents=True, exist_ok=True)
    levels = [int(x) for x in args.levels.split(',')] if args.levels else default_levels()
    modes = args.modes.split(',')
    seeds = [int(x) for x in args.seeds.split(',')]
    jobs = [(str(args.exe), level, mode, seed, str(args.out)) for level in levels for mode in modes
            for seed in ([None] if mode == 'g0' else seeds)]
    if args.skip_existing:
        jobs = [job for job in jobs if not (args.out / (run_name(job[1], job[2], job[3]) + '.json')).exists()]
    started = time.time()
    failed = 0
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        for row in pool.map(_job, jobs):
            failed += bool(row['error'])
            print(f'{row["run"]} units={row["units"]} seconds={row["seconds"]}' + (f' error={row["error"]}' if row['error'] else ''), flush=True)
    print(f'OPENING_SNAPSHOT_ORIGINAL runs={len(jobs)} failed={failed} jobs={args.jobs} wall={round(time.time() - started, 1)}s')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
