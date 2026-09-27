# WINFAIL Previous-Insert ID, Fixed Position, and Fly Flags

> evidence: static-derived · status: live · functions: 0x44fa80, 0x44fad0, 0x450840 · tools: run_ai_navigation_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-23

**evidence_tier: static-derived**. This packet is a bounded read of the original hsl01.exe dispatcher and tracked action declarations; it does not claim full native battle equivalence or wall-clock timing.

## Source contract

content/imported/hsl/global/tables/ACTION.H declares:

- actChangePrevInsertObjectID = 32: `[id]`
- actSetPlayerFixPos = 84: `[code][serial][x][y][distance]`
- actSetPlayerFly = 92: `[code][serial][mode]`

The source level-12 WINFAIL uses the first token six times with id 10000, fixed positions for all 32 SID_ENEMY038 instances at round 8, and fly mode 1 on the eight SID_ENEMY048 instances before their scripted departure.

## Dispatcher read

The script interpreter is 0x450840; the opcode values select the following switch cases:

- **case 0x20** (actChangePrevInsertObjectID) consumes one word and writes it to the current level previous-insert/player record at offset +0x84. The handler advances the script cursor by one argument. This is a record identity mutation, not a new object insertion. The level-12 sixfold 10000 writes therefore remain in the interpreter as an explicit runtime receipt; the remake has no separate visual use for this source id.
- **case 0x54** (actSetPlayerFixPos) resolves fcn.0044fad0(code, serial). On a found object it writes x to object offset +0x46 and y to object offset +0x44; when distance is nonzero it also writes the distance word to the player-side record at +0x1d0 indexed by the resolved actor slot. The five arguments are consumed together.
- **case 0x5c** (actSetPlayerFly) resolves the same code + serial pair and toggles bit 0 in the player-side record at +0xa0: mode 0 clears it and any nonzero mode sets it. The three arguments are consumed together.

The resolver 0x44fad0 scans registered object slots by actor code and decrements the requested serial among matching objects; serial 1 is the first matching instance. Its helper 0x44fa80 rejects a removed/unusable slot, so deleted objects no longer resolve. Existing static evidence and the tracked catalog retain that helper as a bounded slot-liveness filter, not as a complete object lifecycle claim.

## Remake mapping

WinfailActions keeps one unit dictionary as battle truth. A fixed-position write resolves the requested instance and writes what the handler writes: the object's guard anchor (`+0x46`/`+0x44`, the pair the fixed-point walk `0x4111a0` reads — [original_ai_navigation.md](original_ai_navigation.md#证据)) becomes the unit's `ai_home_coord = floor(pixel / 32)`, and a nonzero distance becomes the live `ai_fixed` (`+0x1d0`) as `ai_fixed_radius`, read last by `AINavigationRules.instance_profile`. **The unit is not moved.** On its next turns the guard branch (`0x440ef1`: a foe outside the anchor radius is no target) sends it toward the anchor through `approach_home`; an anchor beyond the map edge (WINFAIL012 round 8: `-160,1824`, `576,-160`, `1632,608`, `736,2112` on the 45×60 map) is a retreat point — the unit walks to the nearest edge cell and stays a participant until the round-10 `actWalkAndDelete` removes it. The receipt in `winfail_runtime.fixed_position_changes` keeps `coord`, `distance` and `off_map` (anchor outside the map) for inspection only.

Lane R23 replaced the earlier provisional reading (teleport to `coord`, `off_map` marker excluded from battle counts): the teleport put thirty-two 038 outside the map at round 8 and the next AI preflight failed with `unsupported_ai_coordinates` (autoplay `dead_end reason=exception`, level 12 under the lookahead brain). A living unit outside the map is now an explicit `ai_unit_off_map:<id>` scenario error naming that unit (`BattleLoopAI._prepare_ai_turn`).

Fly mode is represented by the existing unit fly field (created only when this source token is applied); no second actor state is introduced. Previous-insert id changes are recorded in winfail_runtime.previous_insert_id_changes and also update the pending insert receipt source id when one exists. No presentation behavior is inferred from the numeric id alone.

## Boundaries

- static-derived: opcode numbers, argument order, resolver call, field offsets, bit operation, and cursor consumption.
- provisional: 32px pixel-to-grid quantization of the anchor (the EVEF fixed-point install snaps to the cell centre `(word & ~0x1f) + 0x10`, so the cell is the same), the refinement walk's flood metric (see original_ai_navigation.md), and the absence of a visible remake effect for id 10000.
- negative-evidence: this dispatcher read does not establish native collision resolution, animation timing, fly physics, or whether the handler sets object flag 0x4000 (the EVEF install does; without it the arrival release `0x43fbf1..0x43fc0e` never clears the script radius, so the remake keeps the unit a guard of that radius after arrival). A bounded runtime probe (level 12 round 8–10 in Wine) is the replacement evidence for those claims.

Re-run target: `tools/godot.sh --headless --script res://tests/run_all.gd -- run_winfail_rules_tests.gd` (`_level_twelve_opcode_actions`), `tools/godot.sh --headless --script res://tests/run_ai_navigation_tests.gd` (`script_anchor_cases`) and the level-12 battle assembly checks.
