"""Original chest lifecycle across a level re-entry under the _enemy_level machine (diagnostic;
registers no task).

The level is entered by the original new-level branch 0x42da60 (load flag clear) and halted at
the first round sort (_enemy_level.round_sort_machine). Then, in the same process:

1. every live pool object (base [0x4a19c0], count [0x4a19c4], stride [0x4a19c8]; in use =
   +0x80 bit 31) whose process word +0x64 is 41 (defProcTreasureBox) is listed with +0x80 and
   the eight content words +0x90 (shape word +0x30 = 0xffff: hidden, as 0x415730 leaves it);
2. the first chest is collected by the original 0x4156d0 run whole (queue add 0x44f2d0 and the
   object free 0x45e3ed included) — draws are counted at the generator entry 0x458c10 (both
   streams go through it: 0x42c720／0x42c780 swap the damage words into 0x4795d4／0x4795d8),
   and every changed dword of the EXE image is listed;
3. the same level is entered again by 0x42da60 in that machine (as the WinMain loop 0x42f7dd
   does for the next level) up to its first round sort, and the chest list is read again.

Each chest row also carries its object code +0x54, the EVEF record it was placed from (joined
by pixel with the level seed) and the +0x80 of its template 0x4a2728[code] (obj_Attribute): the
dispatcher 0x45f655 hands the object's +0x80 to 0x415730 as the message, so the template bit
0x10000 (objattrATTACKFLAG) is the visible／hidden choice. --census runs step 1 only for many
levels, one TREASURE_HIDDEN line each.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_treasure_reentry.py --level 3 --out ignored/treasure/L003.json
  … _treasure_reentry.py --census 1,2,28,80

Readings: docs/evidence_packets/static_reverse/original_treasure.md (level entry section).
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_treasure_reentry.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402
from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_treasure_reentry.v1'
POOL_BASE, POOL_COUNT, POOL_STRIDE, POOL_LIVE = 0x4a19c0, 0x4a19c4, 0x4a19c8, 0x4a19dc
IN_USE, OPENED, PROCESS, TREASURE = 0x80000000, 0x08000000, 0x64, 41
CODE, TEMPLATES, ATTACKFLAG = 0x54, 0x4a2728, 0x10000
COLLECT, GENERATOR = 0x4156d0, 0x458c10
QUEUE, QUEUE_COUNT = 0x4c1d28, 0x4c1d2c


def chest_records(level: int) -> dict[tuple, int]:
    """EVEF chest records of the level seed by 32-aligned pixel (0x415730 aligns the origin)."""
    seed = json.loads((ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json').read_text(encoding='utf-8'))
    return {tuple(v & ~31 for v in r['placement_xy_candidate']): r['record_index']
            for r in seed['placements']['records'] if r.get('object_process') == 'defProcTreasureBox'}


def chests(m, records: dict[tuple, int] | None = None) -> list[dict]:
    base, count, stride = m.get(POOL_BASE), m.get(POOL_COUNT), m.get(POOL_STRIDE)
    rows = []
    for index in range(count):
        obj = base + index * stride
        flags = m.get(obj + 0x80)
        if flags & IN_USE and m.get16(obj + PROCESS) == TREASURE:
            pixel, code = [m.geti(obj + 4), m.geti(obj + 8)], m.get(obj + CODE)
            rows.append(dict(object=hex(obj), pixel=pixel, record=(records or {}).get(tuple(pixel)), code=code,
                             template_attribute=hex(m.get(m.get(TEMPLATES + 4 * code) + 0x80)), flags=hex(flags),
                             hidden=m.get16(obj + 0x30) == 0xffff,
                             opened=bool(flags & OPENED), words=[m.get(obj + 0x90 + 4 * i) for i in range(8)]))
    return rows


def census(level: int, use_cache: bool) -> str:
    try:
        m, _driver, _info = lv.round_sort_machine(ORIGINAL_EXE, level, True, use_cache, tuple(lv.carried_slots(level)))
    except RuntimeError as error:   # 900-904 open with a menu: take its first option
        if 'select_menu' not in str(error):
            raise
        m, _driver, _info = lv.round_sort_machine(ORIGINAL_EXE, level, True, use_cache, tuple(lv.carried_slots(level)), (1,))
    rows = chests(m, chest_records(level))
    bit = all(r['hidden'] == (not int(r['template_attribute'], 16) & ATTACKFLAG) for r in rows)
    return (f"TREASURE_HIDDEN level={level} chests={len(rows)} "
            f"hidden={[(r['record'], r['code']) for r in rows if r['hidden']]} "
            f"shown={[(r['record'], r['code']) for r in rows if not r['hidden']]} "
            f"template_bit_10000_decides={bit} unjoined={sum(r['record'] is None for r in rows)}")


def queue(m) -> list[list[int]]:
    table = m.get(QUEUE)
    return [[m.get(table + 8 * i), m.get(table + 8 * i + 4)] for i in range(m.get(QUEUE_COUNT))] if table else []


def rng(m) -> list[int]:
    return [m.get(a) for a in (*et.GLOBAL_STATE, *et.DAMAGE_STATE)]


def run(level: int, use_cache: bool) -> dict:
    from hsltools.native.battle_machine import FIRST_FRAME_FN, FRAME_FN, LEVEL_START, LOAD_FLAG, LEVEL_NUMBER
    m, driver, info = lv.round_sort_machine(ORIGINAL_EXE, level, True, use_cache, tuple(lv.carried_slots(level)))
    draws = []
    m.hook(GENERATOR, lambda: draws.append(hex(m.return_address())))
    records = chest_records(level)
    first = chests(m, records)
    if not first:
        raise SystemExit(f'level {level}: no live process-41 object at the round-1 halt')
    target = int(first[0]['object'], 16)
    base, size = m.image_range
    image_before = bytes(m.mu.mem_read(base, size))
    before = dict(queue=queue(m), rng=rng(m), live=m.get(POOL_LIVE))
    m.call_nested(COLLECT, target)
    image_after = bytes(m.mu.mem_read(base, size))
    changed = [hex(base + at) for at in range(0, size, 4)
               if image_before[at:at + 4] != image_after[at:at + 4]]
    collect = dict(object=hex(target), draws=list(draws), rng_before=before['rng'], rng_after=rng(m),
                   queue_before=before['queue'], queue_after=queue(m), live_before=before['live'], live_after=m.get(POOL_LIVE),
                   flags_after=hex(m.get(target + 0x80)), image_dwords_changed=changed, chests_after=chests(m, records))
    # Re-enter the same level in this process: a fresh call of the new-level branch, frame shims,
    # dialogue clicks and the round-sort halt as the first entry (the halted frame loop is dropped).
    draws.clear()
    sort = m.hook(et.QUEUE_SORT, lambda: m.halt('round_sort'))
    driver.limit = driver.frame + lv.OPENING_FRAMES
    m.put(LEVEL_NUMBER, level)
    m.put(LOAD_FLAG, 0)
    m.put(FRAME_FN, FIRST_FRAME_FN)
    m.call(LEVEL_START, level, budget=0)
    m.unhook(sort)
    if m.halted != 'round_sort':
        raise SystemExit(f'level {level} re-entry: {m.halted or m.stop_reason}')
    return dict(schema=SCHEMA, level=level, opening=dict(frame=info['frame'], clicks=info['clicks'], cache=info['cache']),
                first_entry=first, collect=collect,
                reentry=dict(chests=chests(m, records), queue=queue(m), live=m.get(POOL_LIVE), frame=driver.frame,
                             generator_calls=len(draws)))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--level', type=int)
    parser.add_argument('--census', help='comma-separated levels: first-entry chest visibility only')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--no-cache', action='store_true')
    args = parser.parse_args(argv)
    if args.census:
        for level in map(int, args.census.split(',')):
            print(census(level, not args.no_cache), flush=True)
        return 0
    if args.level is None:
        parser.error('--level or --census is required')
    result = run(args.level, not args.no_cache)
    text = json.dumps(result, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    c = result['collect']
    print(f"TREASURE_REENTRY level={args.level} chests={len(result['first_entry'])} draws={len(c['draws'])} "
          f"rng_same={c['rng_before'] == c['rng_after']} queue={c['queue_before']}->{c['queue_after']} "
          f"live={c['live_before']}->{c['live_after']} flags_after={c['flags_after']} changed={len(c['image_dwords_changed'])} "
          f"reentry_chests={[(r['pixel'], r['flags'], 'hidden' if r['hidden'] else 'shown', [w for w in r['words'] if w]) for r in result['reentry']['chests']]} "
          f"reentry_queue={result['reentry']['queue']} reentry_draws={result['reentry']['generator_calls']}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
