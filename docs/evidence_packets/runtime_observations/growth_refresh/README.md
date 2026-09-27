# Four-attribute growth — rendered Control-input review

> evidence: runtime-measured · status: live · tools: capture_first_battle_review.gd, capture_presentation_reference.gd · updated: 2026-09-13

Observed: 2026-09-13, Godot 4.7.2. This packet reviews the current remake's player-visible adoption of the source-derived five-point/four-attribute growth contract. It is a controlled live-scene fixture, not a natural battle outcome and not proof that every original growth-screen interaction is identical.

Static/native rule evidence is separate: ../../../static_reverse/original_growth_refresh.md and original_growth_refresh.json prove the SwordMan cap/refresh path. This packet proves that the current Godot UI routes actual Control input into the authoritative PlayLoop state without reverting to the former health/attack/defense rule.

## Fixture

tests/capture_first_battle_review.gd instantiates the real BattleSceneRuntime.tscn, enters the existing first-control harness, gives Leonard enough EXP to cross level 1→2 through ProgressionRules.resolve_experience, then opens the live growth panel. It sends mouse motion plus left-button press/release to the real + controls and confirm button.

The tested draft is str +2, dex +1, mind +1, con +1, exactly five points. The fixture asserts that confirmation closes the modal, spends the budget once, commits all four base attributes, recomputes max HP and preserves current HP rather than healing it.

For the visible-window run, CoreGraphics reported the built-in display frame as (1600,251) 1470×956; Godot was explicitly launched at --position 1700,350 with a 640×480 root, keeping the validation window wholly on the built-in display. The PNGs below are saved from that rendered root texture, not from the desktop.

## Reviewed frames

| File | What was checked |
| --- | --- |
| growth-empty.png | Level 2 opens with five unspent points and no committed draft; current HP is not refilled by the level increase. |
| growth-preview.png | Four rows are Strength/Reaction/Mind/Constitution; the five-point 2/1/1/1 draft reaches remaining 0 and previews derived HP/attack/defense/magic/speed without mutating PlayLoop. |
| growth-confirmed.png | Confirmed status reads live 18/17/9/13 base attributes, max HP 33 with current HP still 30, attack 57, defense 43, magic attack 18 and speed 15. Magic attack is displayed as a plain value rather than the old erroneous percent suffix. |
| receipt.json | fixture=true, no failures, real mouse growth confirmation passed. |

Reviewed SHA-256 values after the final formatting fix:

    growth-empty.png      877aede82907015d103fcde255ecfd2bbc2e910069cdb5a0b4487113663f71b5
    growth-preview.png    5a39dcea053aa733574855f1f6a7c3e0c22e8fefb1d4f0eaccc5c95b0638e293
    growth-confirmed.png  46db88b4792456545b6cf9ac5de252b69ede1a08465620dc2ab5c7ba76bea4f3
    receipt.json          e3cbdddb17a6018fb35eb4ef9f1798a36569f5b8b56f76a95caa7efc6fea2a03

tests/capture_presentation_reference.gd with user args growth movie was also migrated to the four-attribute controls and rerun successfully. Its event fixture recorded open→preview→confirm→return with real Control clicks; it remains an ignored movie-maker artifact rather than a second tracked screenshot set.

## Historical boundary

The older first_battle_polish screenshots and prose intentionally remain unchanged historical evidence for the previous three-choice remake. They must not be cited as the current growth contract. Current status and next work are tracked in docs/PROJECT.md and docs/MECHANICS_EVIDENCE_MATRIX.md.
