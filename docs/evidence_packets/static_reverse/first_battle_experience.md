# First-battle experience and growth

> evidence: resource-derived; provisional · status: live · tools: hsltools/data/progression.py · updated: 2026-09-05

2026-09-05. Source template data is resource-derived; the live reward/automatic-growth policy is a remake design, not a recovered native formula.

`tools/hsltools/data/progression.py` reproduces level/exp/kill_exp for the five live templates from PLAYERS.TXT. All templates start at level 1 with zero EXP. Kill rewards are 20 for actor 021, 16 for 026, 20 for 023 and 25 for 024; Leonard's source kill_exp is 30. Existing static evidence at 0x404098 clips experience's damage base to actual HP lost. Native level-gap/random/kill-multiplier arithmetic remains unresolved.

The live player receives actual HP damage plus the source kill reward on a defeat. Misses and rejected repeat actions give nothing. The same award path serves normal attacks, counterattacks and 氣刃斬. AI units do not level during this chapter. PlayLoop owns all mutations; ProgressionRules returns a grown unit, and the existing strike receipt carries the presentation-only earned amount and before/after level.

The native stat-refresh threshold is min(2000, (level+1)*50), retaining overflow. It replaces the earlier provisional 100 + 20*(level-1) threshold. At 0x44b678 the level field +0x9c is incremented, multiplied by 5 twice and 2 once, then capped at 2000 and written to +0x8c. The level-up path at 0x43a235..0x43a243 subtracts that field from EXP +0x88. Both instruction sequences can be checked against the local EXE with PYTHONPATH=tools python3 -m hsltools.data.progression --check --check-exe PATH. The remaining growth policy is a remake design. Each level adds 2 max HP and 1 live attack/defense. Current HP increases only by the cap increment, preserving missing HP. This automatic growth replaces the unused speculative kill-chain multiplier and unspendable pending-stat-point state; manual allocation and native class change are not live. Verification confirms no chain bonus, live combat-stat changes, input immutability, overkill clipping and no repeat rewards.

Actual-scene visual fixtures at EXP 99 against a one-HP enemy show EXP +21, level 2, max HP 34, attack 24 and defense 7, with remaining EXP 20/150 in Status. Fixture inputs are controlled verification data, not a natural playthrough. Screenshots are under ignored/experience-review/. No original level-up audio binding has been claimed.
