# First-battle playability audit

> evidence: runtime-measured · status: live · tools: audit_first_battle_balance.gd · updated: 2026-09-05

2026-09-05, runtime-measured in headless Godot, current remake rules. This is not original-game parity or a difficulty certification.

Default roster, attributes, terrain and AI were used without health or damage overrides. RNG seeds 10, 11 and 12. Begin with `BattlePlayLoop.begin_battle(create())`, step normal AI turns, and handle scripted departures after the objective becomes escape. A cautious player waits until the switch, then follows the legal terrain/occupancy path to the exit, taking its furthest currently reachable cell and committing Wait. Loop limit 400 actions.

| Policy | Seed | Result | Turn | Leonard HP |
| --- | --- | --- | --- | --- |
| Wait, then follow exit path | 10 | victory_escape | 8 | 1 |
| Wait, then follow exit path | 11 | victory_escape | 7 | 24 |
| Wait, then follow exit path | 12 | victory_escape | 7 | 22 |
| Wait indefinitely | 10/11/12 | defeat_leonard | 9 | 0 |
| Use nearest-foe AI as aggressive player policy | 10/11 | defeat_leonard | 3 | 0 |
| Use nearest-foe AI as aggressive player policy | 12 | defeat_leonard | 5 | 0 |

This establishes an observed legal escape route across three seeds. It does not establish robustness across all RNG or player tactics. No balance values were changed from this sample. The follow-up product change makes team, remaining HP and current actor visible and keeps the opening objective as waiting for reinforcements until the story changes it.

Manual visual acceptance: real scene at first control with marker positions attached to current actor positions; headless regression checks half-health fill, position synchronization, and suppression during opening. Temporary audit/capture scripts and images remain under `ignored/`.

## Actual main-scene route and restart

2026-09-05, runtime-measured in the rendered `BattleSceneRuntime.tscn`. Start at the default opening, confirm dialogue with Space, use normal Wait/Move commands and the recovery-item button when below half HP, and follow legal reachable cells after the escape objective. The audit never writes HP, inventory, turns or outcomes. Timers run at 4× speed for this acceptance route; this does not certify normal-speed pacing. The process starts with seed 10, but presentation also consumes random values, so rendered runs are not deterministic combat replays.

Both observed runs completed the opening, round-4 warning, messenger report, scripted enemy departures and final message 371 before showing `victory_escape`. The first finished on turn 8 with HP 23 and two recovery potions after one use; the second finished on turn 7 with HP 32 and three potions. Message 369 spans three pages. The second run then sent Enter and confirmed a fresh main scene with HP 32, three recovery potions and no battle outcome (`FULL_BATTLE_RESTART_PASS`). No script errors or leaked-object messages appeared in the run log.

The result screenshot was inspected after removing stale objectives, combat text, unit markers and floating damage from the victory display. It shows the chapter title, escape result, elapsed turns and Enter-to-replay instruction. Temporary runner, JSON and screenshot are under `ignored/full-battle-review/`; this evidence concerns the remake's complete escape route, not full chapter feature completion or original-game parity.

## Mage integration follow-up

After enabling source-bound wind/fire spells, the actual main-scene route was rerun at 4× timer speed. The observed second run reached turn 8 `victory_optional_clear` with HP 32 and all three potions, after eight Wait commands; the final message 371 preceded the result, and Enter restored the initial scene (`FULL_BATTLE_RESTART_PASS`). The first run exposed a premature result label while a final moving action was unresolved. Result visibility now also requires combat_ready; a focused check covers that ordering. This verifies the clear-enemy branch for this run, not the escape branch or difficulty across all tactics. No script errors remained in the second run.


## Template HP/MP baseline acceptance

After adopting native-template HP 30/22/29/43/33 and mage MP 30, two actual main-scene routes completed at 4× timer speed, using ordinary scene commands without writing HP, inventory, turns or outcomes. These are remake playability observations, not original NPC-level parity or normal-speed timing proof.

| Route | Result | Turn | Leonard HP | Potions left |
| --- | --- | --- | --- | --- |
| Wait until retreat, then follow legal exit path | victory_escape | 7 | 30/30 | 3 |
| Advance, use 氣刃斬 and normal attacks, recover, then exit | victory_escape | 8 | 22/30 | 2 |

Both included opening 363/364/365/366/367/364/1101, warnings 396/397, messenger 368, four-page rally speech 369, and final 371. Enter restart restored 30 HP, three potions and an empty outcome. The advance route earned 91 EXP. No script errors or resource leaks were reported. Logs `/tmp/hsl-vitals-battle.log` and `/tmp/hsl-vitals-advance.log`; raw routes and receipts remain in `ignored/full-battle-review/`. The earlier 32 HP and three-page observations above are historical receipts, not current initialization.

The importer reuses the existing formation generation/check path; no additional runtime state or loader was needed. Physical attack/defense and ability damage are still a separate unresolved balance slice.


## Attack/defense baseline and elemental magic

After adopting native-template attack/defense/hit and changing magic mitigation to source elemental resistance, both actual rendered routes completed again with normal scene commands and 4× timers. The advance route used two specials, normal attacks and one potion, exited on turn 7 with 30/30 HP, two potions and 70 EXP. The hold route also reached victory_escape; see current raw `result.json` in `ignored/full-battle-review/`. Both delivered message 371 and `FULL_BATTLE_RESTART_PASS`, without script errors or leaks. Logs: `/tmp/hsl-combat-baseline-advance.log`, `/tmp/hsl-combat-baseline-hold.log`.

These are successful observed routes, not a guarantee across all tactics. Special damage and the magic damage equation are still remake rules. A targeted test uses 1000 physical defense and separate wind/fire resistances to ensure armor does not nullify spells and each spell selects its own element.

## Reachable-strike AI follow-up — 2026-09-05

Re-ran the rendered main scene after ordinary AI began preferring minimum-cost reachable attacks and wounded targets at equal cost. Both routes use normal opening/dialogue, movement, attacks, original animation/audio and result/restart, with 4× presentation timers. No outcome, HP, inventory, initiative or combat position was forced. Route planning reads legal movement paths; a copied mover with a large range is used only to plan the escape direction, then each committed move is restricted to the real movement envelope.

| Route | Observed outcome | Player state | Restart |
| --- | --- | --- | --- |
| Hold through warning, then move toward exit | `victory_escape`, turn 8, 2048 frames | HP 30/30, recovery items 3 | Enter resets HP 30, items 3, no outcome |
| Advance into contact, use special/ordinary attacks before healing | `defeat_leonard`, turn 4, 1070 frames | HP 0, recovery items 3 | Enter resets HP 30, items 3, no outcome |

The aggressive helper initially tried opening the item panel after spending the attack action and stopped on an empty panel. Its route now respects the existing one-action contract before trying a potion; no game rule was relaxed. The final runs have no script errors. The aggressive policy deliberately prioritizes attacking and is not an optimal survival strategy. These two observations demonstrate working outcomes and tactical consequences, not statistical balance or original AI equivalence. Non-deterministic live combat RNG can change future outcomes despite the helper's global seed.

Current raw outputs: `ignored/full-battle-review/result.json`, `result.png`, `advance-result.json`, `advance-result.png`. The two screenshots were inspected: original closing dialogue precedes a readable result panel; stale menus and combat prompts are absent.

## Normal-speed feedback-polish acceptance — 2026-09-08

After growth allocation, item artwork and combat-facing/staging changes, two rendered routes ran at `Engine.time_scale=1.0` using real Godot mouse/key input events, no battle-data or RNG overrides. The hold route reached `victory_escape` at turn 9 with 30/30 HP and three potions (122.939 seconds). The advance/attack-first route accumulated ST, used 氣刃斬, and reached `defeat_leonard` at turn 5 (79.166 seconds). Both passed seven opening messages, original closing dialogue and the mouse restart contract, restoring HP 30, potions 3, ST 0 and growth points 0. Dialogue confirmations were automated; durations are not human reading/playing time estimates.

Successful final logs were clean. An earlier driver assertion failure followed by a success headline was rejected, and the delivered driver now checks visible enabled commands and fails nonzero for rejected input. The runtime additionally blocks the pre-cut-in gap between resolved combat and presentation queuing.

`tests/audit_first_battle_balance.gd` sampled seeds 10–29 under three explicit default-rules policies: retreat 20/20 wins, reckless ordinary-AI attacks without healing 20/20 defeats, heal-before-advance then retreat 20/20 wins. This is bounded evidence of tactical consequences, not universal balance. The rules controller differs from the rendered special-selection policy. Current receipts, screenshot hashes, fixture boundaries and reproduction paths are in `first_battle_polish/README.md`; the older accelerated runs above remain historical observations.
