# First-battle polish — rendered review and playthrough evidence

> evidence: runtime-measured · status: live · tools: audit_first_battle_balance.gd, hsltools/assets/item_art.py, run_first_battle_playthrough.gd · updated: 2026-09-08

Observed 2026-09-08, Godot 4.7.2, current remake. This packet separates source artwork, controlled visual fixtures, normal rendered routes and bounded rules sampling. It does not certify original-game parity, human input hardware, subjective feel or balance across all tactics.

## Player-visible changes

Growth is now a player decision rather than automatic attribute increments. Each level grants three points: HP cap/heal +2, attack +1 or defense +1 per point. Allocating one of each preserves the previous balanced growth budget. The menu supports preview, undo, clear, confirmation and postponement, with a Status entry for unspent points. Only PlayLoop applies changes; preview and closing do not spend a turn or invalidate a pending move. This is a remake three-choice system, **not native strength/dexterity/mind/constitution allocation**.

The item panel uses original `SHAPE\i_use.SHP`, `ICONBOX.SHP` and `ICONRECT.SHP`, with explicit item counts, recipients and before/after HP. `ITEM.TXT` assigns both 241 and 246 to `itemIconUse`; the art is a shared consumable category, not unique potion/antidote illustrations. Source/PNG hashes live in `content/imported/hsl/chapter01/item_art/manifest.json`; `python3 tools/hsl.py check item_art` verifies the offline inputs.

Decoded ANIMAL frames were reviewed separately from `k_action`. The latter is retained as `source_k_action`, not treated as a pixel-facing flag. Reviewed `sprite_facing` is left for 001/023/024 and right for 021/026. The renderer faces fighters inward, retains their sides for counters, uses SHP drawing anchors, and distinguishes travelling crescent, radial contact burst and spark frames. Approach/reaction/recovery and additive light compositing are explicit remake choices, not recovered native blend/timing handlers.

The scene rejects input when a combat receipt is resolved but not yet queued for presentation. This closes the frame between AI resolution and the next presentation refresh, using the existing sequence cursor rather than another combat state.

## Rendered UI and art review

The fixture starts the actual `BattleSceneRuntime.tscn`, then prepares a wounded/near-upgrade actor and an adjacent wounded ally. It uses Godot mouse press/release events on real controls for growth and healing. It asserts that previews leave the loop unchanged, confirmation spends exactly three points, and allied healing changes recipient HP and player inventory. These are controlled fixtures, not natural outcomes claimed for the full playthroughs below.

| Reviewed file | Evidence |
| --- | --- |
| `growth-preview.png` | Choices, remaining budget and real attribute preview inside 640×480. |
| `growth-confirmed-status.png` | Confirmed level/HP/attack/defense in the existing Status panel. |
| `items-self-and-ally.png` | Original category/slot art, target HP previews, disabled antidote and return control. |
| `source-art.png` | Decoded original item/attack images used for the category/facing review. |
| `combat-impact.png` | Inward attack, anchored additive flash and contact reaction. |
| `combat-counter-impact.png` | Counter from the opposite side without swapping fighters. |
| `skill-travel.png` / `skill-impact.png` | Correct crescent direction, no opaque black padding, separate contact/spark phase. |
| `magic-impact.png` | Enemy spell staging and target reaction. |

Raw fixture: `ignored/first-battle-polish-review/capture.gd`; review data does not become a runtime dependency. The production regression suite independently covers preview/commit/postpone, invalid allocations, pending movement, item-art bindings, facing, counter sides, drawing anchors, exactly-once impact and clip reset.

## Normal-speed complete routes

Reproduce using `tests/run_first_battle_playthrough.gd`, with `-- hold` or `-- advance`. The rendered routes use `Engine.time_scale == 1.0`, paired input presses/releases, visible enabled controls and nonzero failure when a requested command/destination is not accepted. They never overwrite HP, inventory, coordinates, EXP, RNG, turns or outcomes. Long-range escape planning uses a copy only; committed destinations stay inside the real movement envelope.

Dialogue is confirmed automatically, not read by a human: elapsed time is an automated-route duration, not a player completion-time estimate. Combat uses production randomness; these are not seeded deterministic replays.

| Route | Observed result | Player state | Restart |
| --- | --- | --- | --- |
| Hold, then retreat | `victory_escape`, turn 9, 122.939 s | 30/30 HP; 3 recovery items | Mouse result-button input restores HP 30, items 3, ST 0, growth points 0, empty outcome. |
| Advance and prioritize attacking | `defeat_leonard`, turn 5, 79.166 s | 0 HP; normal hits accumulated enough ST for one 氣刃斬 before defeat | Same mouse restart contract passed. |

Both passed the seven ordinary opening messages. Observed battle/closing messages and action receipts are in `playthroughs.json`; `hold-result.png` and `advance-result.png` were inspected for readable results and no stale controls. Neither route naturally earned an upgrade or used a potion: those features were exercised by the separate UI fixture and regressions. Successful final logs had no script/resource errors or leak diagnostics.

Earlier exploratory attempts exposed premature input delivery and a bare-assert driver that could print success despite an assertion failure. Those attempts are excluded from success evidence. The delivered driver fails nonzero; the verification wrapper also scans diagnostics instead of trusting exit status alone.

## Bounded difficulty check

`tests/audit_first_battle_balance.gd` runs default rules with seeds 10–29 under three fixed strategies. It uses normal AI/attack functions, no HP/damage/EXP overrides, and public story-departure handling without visual delays. Growth uses the normal allocation rule. Advancing policies use ordinary nearest/reachable AI attacks instead of the rendered driver's special-selection policy: these are different controllers, not the same replay.

| Fixed policy | Outcomes in 20 seeds | Turns | HP / medicine |
| --- | --- | --- | --- |
| Wait, then legal retreat | 20 escape wins | 7–9 | HP 22–30; no potions used. |
| Advance without healing or retreat | 20 defeats | 3–8 | HP 0; no potions used. |
| Heal below half HP, otherwise advance, then retreat | 20 escape wins | 6–8 | HP 18–30; 36 potions across 20 trials. |

All 60 reached a terminal result inside the 500-step bound; data is in `balance.json`. This supports only that retreat/healing materially matter for these controllers, not universal difficulty or optimal tactics. No difficulty values were changed to make this audit pass. Further feel/balance changes should follow real player feedback.

## Integrity and checks

`manifest.json` hashes promoted images/receipts and tested production files. `tools/verify.sh` owns the cold-import, diagnostics-aware non-GUI gate; it cannot substitute for this rendered review or user approval of the remake choices.
