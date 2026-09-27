# Winfail Exec Mode and System Arrival Position

> evidence: static-derived · status: live · functions: 0x44fad0, 0x450840, 0x458c10, 0x458c80 · updated: 2026-09-20

## Scope

This packet records the resource-derived argument shapes and bounded static-derived reads for the three winfail tokens added for levels 17 and 902. The native global random sequence is not reconstructed; the remake boundary is explicit below.

## Resource uses

`ACTION.H` assigns the `0x450840` dispatcher cases:

- `actSetPlayerExecMode` = 83 (`0x53`), arguments `[code][serial][mode]`;
- `actRandomSetSysArrivePos` = 86 (`0x56`), arguments `[num][x1][y1][x2][y2]...`;
- `actCheckPlayerArriveSysPos` = 87 (`0x57`), arguments `[code][serial]`.

`WINFAIL017` uses `actSetPlayerExecMode SID_嚎,1,0` in its win section and mode 1 after the scripted arrival. `WINFAIL902` uses mode 1 after installing 嚎, chooses five system-arrival candidates, and checks the selected point for each party actor before granting item 281. These script uses are resource-derived.

## Static dispatcher read

The available decompilation of `0x450840.c` shows:

- Case `0x53` resolves the actor by `0x44fad0(code, serial)` and writes object offset `+0x64` (decimal 100) to 3 when the third argument is zero, or 5 when it is nonzero. This is separate from case `0x42` / `actSetPlayerMode`, which writes the player-table mode and changes the presentation/AI role. The remake therefore records the source execution mode on the unit and does not change `battle_actor_role` or `player_commandable`.
- Case `0x56` reads the first argument as a candidate count, calls `0x458c80(count)`, selects the corresponding (x,y) pair, and writes both coordinates to globals `0x4c2968` and `0x4c296c` after masking each with `0xffffffe0`. The low five bits are therefore discarded and the stored system point is 32-pixel aligned.
- Case `0x57` resolves the actor and compares its object x/y fields at `+0x4` and `+0x8`, each masked with `0xffffffe0`, to those two globals. The condition is an aligned pixel comparison, not a direct grid-coordinate comparison.
- `0x458c80` returns zero for a zero bound; otherwise it calls `0x458c10` and returns the low 16 bits modulo the bound for bounds below `0x10000`, or the full value modulo the bound for larger bounds. The original global RNG state and sequence are not established here.

## Runtime boundary

`WinfailScenarioRules` applies `actSetPlayerExecMode` to the resolved unit(s) as `player_exec_mode` plus the native 3/5 value, with an immutable `exec_mode_changes` receipt. It intentionally leaves faction and commandability untouched because those belong to `actSetPlayerMode`.

`actRandomSetSysArrivePos` stores the aligned candidate list, selected index, selected pixel position, firing index, and RNG before/after values in `winfail_runtime.system_arrival_position` and `system_arrival_position_changes`. The pick is one `rand(N)` (0x458c80, called at 0x451787) on the loop's global stream `global_rng` (`GlobalRandomStream`, the original's words 0x4795d4／0x4795d8; lane RNG-A 2026-09-25), and the before/after values are that stream's two words. The draw itself is static-derived; which pair a given clock seed picks stays provisional, because the global draws before it (AI decision chain, animation delays) are not yet the original's. `actCheckPlayerArriveSysPos` compares the live resolved unit's grid position converted by `cell_size` to the same aligned pixel position.
