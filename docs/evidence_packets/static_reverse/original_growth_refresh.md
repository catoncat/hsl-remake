# Original four-attribute growth caps and SwordMan stat refresh

> evidence: static-derived · status: live · functions: 0x448370, 0x448840 · tools: hsl_native_growth_probe.py, hsl_native_growth_refresh_probe.py, hsltools/data/first_battle_formation.py · updated: 2026-09-13

Checked: 2026-09-13

This packet closes the two gaps deliberately left by the earlier five-point allowance proof: where the four attribute caps come from, and what the original stat refresh does after level/attribute changes. It is a bounded original-EXE result, not a claim that every job, class-change path or experience-award rule is now restored.

Machine-readable evidence: [original_growth_refresh.json](original_growth_refresh.json). Reproducer: tools/hsl_native_growth_refresh_probe.py. The earlier allowance helper proof remains in original_mechanics_audit_growth.json and tools/hsl_native_growth_probe.py.

## Source and execution boundary

- Original executable: $HSL_ORIGINAL_DIR/hsl01.exe.
- Required SHA-256: f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7.
- Stat refresh entry: 0x448840.
- Cap loader: 0x448370.
- Cap table: 0x4786bc, twenty rows of four unsigned 16-bit values.
- Job dispatch uses TYPE.H codes 80..99; the cap-loader index is job_code - 80.
- Each fixture executes the unchanged original refresh until normal return with a 12,000-instruction budget. Execution is rejected outside 0x448370 <= pc < 0x44b820; there are no success stubs for unexplained callees.
- The emulated actor is synthetic and intentionally contains only the Leonard source template, four base attributes, level/current HP/MP, base resists and optional initial equipment table entries needed by this path.

The probe runs ten fixtures twice, unequipped and with Leonard's initial equipment. They cover the level-1 baseline, level 2 without allocation, one-point changes for each base attribute, a mixed five-point allocation, high values, one-below-cap values and an at-cap fixture with oversized current HP/MP. Every native result is compared to an independent positive-domain SwordMan arithmetic model before the JSON is emitted.

## Cap initialization

Leonard is jobSwordMan = 80, so 0x448370 selects table row 0 and writes:

| Attribute | roster base | roster cap | SwordMan cap |
| --- | ---: | ---: | ---: |
| Strength / str | +0x64 | +0x74 | 90 |
| Dexterity / dex | +0x68 | +0x78 | 88 |
| Mind | +0x6c | +0x7c | 80 |
| Constitution / con | +0x70 | +0x80 | 94 |

These are job-derived caps written during stat refresh, not fields from PLAYERS.TXT, and not the synthetic 99 values used by the earlier allowance-boundary experiment. All twenty job rows are retained in the JSON so later job work does not have to rediscover this table; this slice only models the SwordMan branch.

## SwordMan refresh contract

For positive base attributes, 0x448840 copies the four base values into its working fields, dispatches by job - 80, applies equipment, adds template HP/MP fields, recomputes the EXP threshold, then clamps current HP/MP downward if they exceed the new maxima. The independent model matched all ten original-function fixtures.

For Leonard's SwordMan branch, before equipment deltas:

    max_hp = level + floor(180*con/100) + floor(str/8) + hit_point
    max_mp = floor(80*mind/100) + floor(con/6) + magic_point
             (forced to 0 when the actor has no magic)

    attack = attack_power
           + floor(116*floor(str/2)/100)
           + floor(36*dex/100)
           + 16
           + level_attack_bonus(level)

    defense = defense
            + floor(20*str/100)
            + floor(mind/5)
            + floor(dex/3)
            + floor(con/3)

    magic_attack = magic_attack_power + min(floor(10*mind/100) + level + 16, 76)
    speed = speed + floor(90*dex/100)
    exp_threshold = min(2000, (level + 1) * 50)

The five base resistance bonuses for this branch are respectively capped at 40 and use (40% mind + con/4), (26% mind + con/5), (20% mind + con/5), (46% mind + con/4) and (10% mind + con/6) with the same integer truncation represented by the probe/model.

Leonard's current initial equipment contributes a constant output delta across all ten fixtures: attack +23, defense +24 and hit rate +98; max HP, max MP, speed, magic attack and all five resists are unchanged by that initial equipment set.

This constant delta is sufficient for the current growth slice because equipment is still read-only. It is not a replacement for the later equip transaction model; once equipment can change, live refresh must consume the equipped items rather than preserving this initial delta.

## Level-up and current HP/MP

The existing level-up caller increments level, subtracts the old EXP threshold, clamps negative residual EXP to zero and calls 0x448840. The refresh does not refill current HP/MP when a new level or constitution increases the maximum. It only clamps a current value downward when the new maximum is lower.

The saved fixtures make that distinction explicit:

- level-1 Leonard: current HP 17 / max HP 30, attack 54, defense 43, speed 14;
- level 2 with no allocation: current HP remains 17 while max HP becomes 31 and attack 55;
- level 2 after str+2,dex+1,mind+1,con+1: max HP 33, attack 57, defense 43, speed 15, current HP still 17;
- at SwordMan caps and level 99, an intentionally oversized current HP is clamped to native max 285; MP remains 0 because Leonard has no magic.

## Product adoption and remaining boundary

ProgressionRules.gd now uses the native five-point/four-attribute allocation, SwordMan caps and this refresh model for Leonard. BattlePlayLoop remains the only mutable owner; the growth panel holds only a draft. The status panel reads live mind/con/magic attack rather than a static UI copy. The remake accumulates the points of several crossed levels into one window (the original opens one window per level, same total); the window cannot close before every point is placed, as the original (original_growth_window.md §2).

Still outside this proof and product adoption:

- stat-refresh arithmetic for jobs other than jobSwordMan;
- class change and how it changes job/caps;
- the original complete experience-award formula; current combat award remains the documented remake rule: actual HP damage plus source kill reward;
- equipment mutation; the current Leonard equipment contribution is a proven fixed baseline only;
- temporary status/buff flags and other refresh branches intentionally absent from the synthetic fixtures.

## Reproduce

    uv run --with unicorn==2.1.4 python tools/hsl_native_growth_refresh_probe.py --check
    python3 -m unittest tools.test_hsl_native_growth_refresh_probe -v
    python3 tools/hsl.py check first_battle_formation

The product does not emulate the EXE at runtime. The checked JSON is development evidence; the game consumes tracked scenario data and pure GDScript rules.
