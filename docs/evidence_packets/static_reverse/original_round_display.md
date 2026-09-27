# Round Display and X-Range Actions

> evidence: static-derived · status: live · functions: 0x4074a0, 0x407510, 0x408370, 0x42c180, 0x42c400, 0x42c640, 0x42fff0, 0x430020, 0x44e7b0, 0x44ebf0, 0x44ecb0, 0x44ee20, 0x44fa80, 0x450840, 0x453ac0, 0x453b30, 0x45e307 · updated: 2026-09-28

**static-derived**：本包只记录 ACTION.H 的参数形状、hsl01.exe 的剧情 VM bridge 0x450840 分支和重制接线边界；测试通过不等于原版等价。

## Token table

content/imported/hsl/global/tables/ACTION.H gives:

- actCheckRoundDisp 94 `[number]`
- actDeletePosPlayerXRange 104 `[x][y][x number][proc code]`
- actInsertStoryObjectXRange 105 `[code][x][y][x number]`
- actPlayMovie 120 `[over delay]`
- actInsertLevelUpStar 123 `[sound id]`
- actDetectRoundDispDisp 124 `[num]`

## 0x450840 cases

- Case 0x5e (actCheckRoundDisp) reads the packed script round-display counter at 0x4c1bbc and its 16-bit display baseline at 0x4c1bbe. When the baseline is unset it establishes a threshold from the current counter plus the argument; the branch continues only after the packed counter reaches that threshold, then clears the low counter word. The remake exposes this as a provisional battle-turn threshold so a condition is false before N and true at N.
- Case 0x7c (actDetectRoundDispDisp) compares the low 16 bits of 0x4c1bbc with 0x4c1bbe + num and does not perform the case 0x5e reset. The remake keeps a separate display baseline and records the signed offset; exact native VM re-entry timing remains provisional.
- Case 0x68 (actDeletePosPlayerXRange) rounds the source pixel x and y down to a cell and adds 16, then calls the position selector once per x number cell with process code proc code. Thus the parameters are world pixels, not grid coordinates. The first quantized cell is included and the count covers exactly that many cells; there is no extra geometric endpoint. The remake resolves matching living units into the existing departure ledger.
- Case 0x69 (actInsertStoryObjectXRange) uses the same pixel-to-cell-center sequence and calls the object installer once for each counted x cell. It is an object/presentation insertion, not a player or enemy unit creation; the remake records each selected position through the existing script-object request path.
- Case 0x78 (actPlayMovie) loads the fixed END.ANI / END.SND pair and waits using the supplied over-delay. The existing MoviePlayer handles the imported end film; headless or unavailable playback is recorded as an explicit skipped status.
- Case 0x7b (actInsertLevelUpStar) sends the sound id through the native effect helper and then the effect renderer. It changes no actor, HP, queue, or winfail state, so the remake treats it as presentation-only and records an explicit skipped reason when no dedicated star sprite is available.

## Round counter `0x4c1bbc` and `actCheckRoundNumber` (static-derived, lane E1 2026-09-27)

Only-read disassembly／decompilation of `hsl01.exe` (sha256 `f0b5f835…70f7`); no bounded execution. `axt 0x4c1bbc` lists every reference to the counter:

| Address | Function | Access | Reading |
| --- | --- | --- | --- |
| `0x42c6b9` | `0x42c640` battle-state reset | `mov dword [0x4c1bbc], 1` | The counter starts at **1** when a battle is set up (same function clears `0x4c1d44`, the action counter `0x4c1ad4` and sets `0x4c1b00 \|= 0x2000000`) |
| `0x4074f1` | `0x4074a0` turn-queue advance | `inc word [0x4c1bbc]` | Increments the **low word** only after the 200-slot turn table `0x4c3948` (stride 0xc, cursor `0x4c6e48`) has been scanned twice without a ready slot (forward from the cursor, then again from −1), i.e. when the round is exhausted; the same branch first calls `0x407340` (queue rebuild by live speed, [initial_battle_initiative.md](initial_battle_initiative.md)). A found slot clears its ready flag and returns without touching the counter |
| `0x4524fd`, `0x45252f`, `0x452572` | `0x450840` script VM | read | case 0x28 = `actCheckRoundNumber [num]` (ACTION.H 40): `if ((word)[0x4c1bbc] < num) → not yet` (pc rewinds, status stays armed); otherwise the status continues into its action chain. Cases 0x5e／0x7c (round display) read the same low word against the display baseline `0x4c1bbe` (the high word of the same dword, see above) |
| `0x43d610`／`0x43d625` | round-display countdown object | read | prints `baseline − counter` (itoa base 10 into `0x4c1e98`) — the on-screen 「剩餘回合」 number of actCheckRoundDisp; the plain round number is not displayed anywhere else (negative-evidence over the `axt` list) |
| `0x42e2a1`／`0x42e8e0` | save write／read | copy | Save header offset `0x20` ([original_save_format.md](original_save_format.md)) |

**Evaluation cadence.** Every completed action ends in `0x407510` ([action state machine](original_action_state_machine.md) `0x443c1a`／`0x443c38` and the seven other callers), which runs in this order: `0x408370` → `jmp 0x44ee20` (win scan `0x44ebf0`, fail scan `0x44ecb0`, event scan — skipped only while `0x4c1b00 & 0x4000000` story phase or no current level object `0x4c1ba0`), then `0x44f4e0`, `inc word [0x4c1ad4]` (action counter), then `0x4074a0` (queue advance, round increment at wrap). So a status conditioned on `actCheckRoundNumber N` fires on the **first scan whose counter already reads N — the scan after the first completed action of round N**, not at the round boundary itself: the boundary scan still sees N−1, the wrap that makes the counter N happens after it. The two other callers of `0x44ee20` are the story→battle handoff `0x4082a6` (after `0x407340` builds the first queue, only when `0x4c1d44` was set by `actShowWinFailStatus`, case 0x44) and the status-object tick `0x453b7c` (right after a fired status chain that ran `actShowWinFailStatus` completes).

**Remake mapping.** `BattleLoopInit` sets `turn = 1`; `BattlePlayLoop._finish_ai_or_continue` sets `turn = turn_queue.round + 1` when `CoreTurnQueue.end_turn` wrapped (the same rebuild-at-wrap structure as `0x4074a0`／`0x407340`, `run_tests.gd` narrow regression); `WinfailConditions.actCheckRoundNumber` is `turn >= num`. Counter origin, increment point and comparison therefore match the original (static-derived) — 「visible turn mapping」 is settled: WINFAIL051 event 2 (`actCheckRoundNumber 4`) and event 3 (`actCheckRoundNumber 6`) fire in the remake's round 4／6 as they do in the original's. **Cadence (aligned, lane R36 2026-09-28):** `BattlePlayLoop._advance_current_actor` runs, for a living actor, the status tail (the `0x40b910` counterpart: poison, durations, kill chain), then `run_event_hooks` (non-attack `round` context) and `_resolve_outcome` (win／fail), and only then `CoreTurnQueue.end_turn`; the wrap in `_finish_ai_or_continue` only bumps `turn`. A round-N event therefore fires after round N's first completed action, as in the original, and count／HP／arrival conditions are re-read after every completed action (Wait, item use, paralysis skip, offense), with an outcome decided there frozen before the queue advances. A skipped dead slot scans nothing (the original retires it through `0x407720` → `0x4074a0` without `0x407510`); the first half of an extra action does not scan either (its completion skips the tail and the queue call). `tests/run_event_cadence_tests.gd` pins the level-51 round-4／6 events, the poisoned Wait and the item-use win, each with an ablation. Both scheduling differences R36 recorded are aligned below: the per-strike `attack` scan («Attack context») and every holding event starting in one scan («Scan shape»).

## Scan shape (static-derived, lane R37 2026-09-28)

Only-read decompilation／disassembly of the same `hsl01.exe`; no bounded execution.

| Address | Reading |
| --- | --- |
| `0x408370` (= `0x44ee20` behind a guard) | Runs only while a level object is current (`0x4c1ba0 != 0`) and no status chain is running (`0x4c1b00 & 0x4000000` clear). Calls the win scan `0x44ebf0`, the fail scan `0x44ecb0`, then walks the 20 event slots at `*0x4c1d0c` (stride `0xb4`: code at `+0`, script pc at `+0x94`) in **slot order**. For each armed slot it runs the condition prefix through `0x450840`; if it holds the slot is disarmed (`code = -1`), its chain is started with `0x453ac0(pc, 4, 0)` and the function **returns** — the remaining slots are not read in this scan. A failed prefix rewinds the pc and the walk continues |
| `0x44ebf0`／`0x44ecb0` | Same shape over the 10 win／10 fail slots (stride `0xb4`): the first holding status is disarmed and started (`0x453ac0(pc, 1／2, 0)`, falling back to `0x453a80(1／2)` when no object can be created), then that scan returns. Neither guards on the story flag, so one `0x44ee20` call can start at most one win, one fail and one event chain |
| `0x453ac0` | Creates the status object (`0x45e307(…, 799, …)`), stores the chain pc at `+0x90` and the kind at `+0xac`, clears `0x4c1ba0` and sets `0x4c1b00 \|= 0x4000000` — so no further completed-action scan (`0x408370`) runs while the chain plays |
| `0x453b30` (status object tick) | Steps the chain through `0x450840`; when it ends, `0x453a80(kind)` (kind 4 restores `0x4c1ba0 = 1` and clears the story flag), then **if `0x4c1d44` is set it clears it and calls `0x44ee20`** (`0x453b69..0x453b7c`) — one immediate rescan of the same shape — and deletes the object |
| `0x450840` case `0x44` | `actExecWinFailProcess` (ACTION.H 68) sets `0x4c1d44 = 1`; the second switch's case `0x4f` (`actSelectInsertEvent`, 79) inserts the chosen event (`0x44e7b0`) and sets it too. `actShowWinFailStatus` (31) is case `0x1f`: it waits on the board display (`0x407320`) and does **not** set `0x4c1d44` |
| `0x44e7b0` | `actInsertEventStatus` writes the code into the **first free** slot (no duplicate check); `0x44e8d0` (`actDeleteEventStatus`) frees the last slot holding the code |

So a completed action starts **at most one event**; a second event that holds at the same time starts at the next completed action — unless the first chain ran `actExecWinFailProcess`, whose end rescans once (again at most one event), which chains until a chain without it ends the sequence. WINFAIL051's events 0／1 therefore refill 021 and 026 on two different actions when one kill leaves both counts short (event 0 keeps the lower slot, so while 021 stays short 026 waits). WINFAIL032 event 9 (`actCheckNextSerialNumber 3` → gas object → `actInsertEventStatus 9` → `actExecWinFailProcess`) re-arms itself in its own rescan, but its condition is a timer on the handoff counter `0x4c1ad4`, so the rescan only sets the next deadline: one gas burst every fourth handoff ([poison gas](original_poison_gas.md)).

**Remake mapping (aligned).** `WinfailScenarioRules._evaluate` walks the armed events in section order and stops at the first one that fires; the next pass runs only when that chain returned the `actExecWinFailProcess` request (`WinfailActions.apply_actions`), bounded by `MAX_PASSES` (the original has no bound; raised from 8 to 32 because one pass now starts one event, and WINFAIL038's nine arrival events plus its all-evacuated event chain end to end when the whole party reaches the exit — the battle-sweep fixture for level 38 does exactly that). `run_event_cadence_tests` pins both halves on the live level 51 (events 0 then 1 on consecutive completions) and on a four-event fixture (only the `actExecWinFailProcess` chain pulls the next event into the same action), each with an ablation (firing every holding event: 7 failures; dropping the rescan: 4 failures and 11 in `run_winfail_rules_tests`). Sweep／chapter impact: none — in the 128-battle sweep and the seeded chapter walk no scan ever had two armed events holding at once (lane R37 `HOLD_DBG` census) and every battle's fired sequence (key, round, step, context) is line-for-line the one R36 logged before the change, so `results.json`／`chapter.json` are unchanged. **Not aligned (remake boundary):** (a) scan order — the remake reads section order, the original slot order; they agree while no event is re-inserted into a lower hole than its section rank (a self re-arming chain reuses its own slot; `0x44e7b0` fills holes first), and the census found no scan where the difference could matter; (b) the win／fail scans — the remake still decides a win armed by an event chain within the same completion (`_evaluate` commits the terminal status and `_resolve_outcome` re-reads `victory_state` after every settled action or strike), where the original, scanning win／fail before events and not again unless `0x4c1d44` is set, decides it at the next completed action; (c) the story-flag guard — remake chains apply at once, so there is no scan to skip while one plays.

## Attack context (static-derived, lane R37 2026-09-28)

The three attack conditions are read by the same completed-action scan as every other status; there is no scan after a strike. `r2 axt 0x4c1ce8` lists every access of the attacker global:

| Address | Access | Reading |
| --- | --- | --- |
| `0x42c673` | write 0 | battle-state reset `0x42c640` |
| `0x43f559` | write 0 | AI object process, phase 0 (the action's decision entry) |
| `0x443a36` | write 0 | player object process, low state 0 (`0x443a0d`: camera centre `0x43bf30`, `0x42fff0`, then the action menu `0x43ea30`) |
| `0x440272`, `0x441871`, `0x441b7b` | write attacker | AI attack starts (with target `0x4c1cec`, then `0x430020`) |
| `0x444382`, `0x44515f` | write attacker | player attack／special starts |
| `0x442b36` | write caster | shared cast routine `0x442a90` (magic, support included) |
| `0x452750`, `0x4527d7` | read | `0x450840` cases `0x2a`／`0x74` only |

The attacked list — codes `0x4c29a0[80]`, objects `0x4c2b00[80]`, count `0x4c1cf4` — is appended by `0x430020(target)` at each of those attack starts (and per target inside `0x442a90`) and reset by `0x42fff0`, called only at the player's state 0 (`0x443a2d`) and the AI's state 1 (`0x43f534`). So when an action's completion reaches `0x407510`, `0x4c1ce8` names the actor that attacked in that action (or 0 if it did not) and the list holds the targets of that action; the next action's entry clears both before its own attack. An extra action's first completion re-enters phase 0 (bounded native execution in [original_extra_action.json](original_extra_action.json): `again` → phase 0), so its first half's attack is cleared before any scan reads it. Case semantics:

- case `0x2a` `actCheckPlayerAttacked [attacker][attacked]`: unless the attacker argument is `-1`, `0x4c1ce8` must be set and `0x44fa80(0x4c1ce8)` (the object's player code; −1 for a dead-flagged object or one whose `+0x64` is not 3／5) must equal it; then the attacked code must be in the list and `0x44fad0(code, 1)` must find a registered object.
- case `0x6e` `actCheckSerialPlayerAttacked [attacked][serial]`: walks the list for entries with that code whose object equals `0x44fad0(code, serial)`; `0x4c1ce8` is not read.
- case `0x74` `actCheckNotPlayerAttacker [player]`: fails only when `0x4c1ce8` is set and its code equals the argument — it **holds when nobody attacked** in the action.

An actor that dies in its own action (killed by the counter) never reaches its completion states; its death sequence retires it and calls `0x407510` (`0x43f190`／`0x44369e`, R36), with `0x4c1ce8` still naming it. An undead actor revived there calls `0x407510` directly when it is the current actor (`0x43ee92..0x43ee9b`).

**Remake mapping (aligned).** `attack_target` and the AI step no longer scan after a strike; they record `action_attacker_id` (the remake's `0x4c1ce8`) next to `last_attack` (the attacked list). `BattlePlayLoop._advance_current_actor` consumes that mark (`_takes_attack_scan`: the finishing actor's own attack only) and runs the completion scan in the `attack` context — once, after the status tail — for a living actor, and for an actor that died in its own attack (without the tail); a skipped dead slot and the first half of an extra action (whose repeat clears the mark) still scan nothing. `WinfailConditions` reads the attacked targets as the strike's `defender_id` plus every `affected_targets` receipt (area skills), accepts `-1` as any attacker for `actCheckPlayerAttacked`, and lets `actCheckNotPlayerAttacker` hold at a completion without an attack. `run_event_cadence_tests` pins the completion-only read on the live level 51 (not fired after Leonard's strike, fired once in the `attack` context at its completion, not re-read by the next action); `run_departure_tests`／`run_entry_growth_tests`／`run_ohm_village_tests`／`run_gol_road_tests` pin the extra-action halves (the first half's attack and the arrival a kill satisfies both wait for the second half's completion); `run_winfail_rules_tests` pins the `-1` attacker, the area-skill target list and `actCheckNotPlayerAttacker` at a completion without an attack. Ablations: restoring the per-strike scan fails 17 checks across the four rule suites plus `run_gol_road_tests`, a completion scan without the attack context 15, keeping the first half's mark on repeat 1. **Not aligned (remake boundary):** `0x44fad0(code, 1)` requires the attacked unit to be still registered at the scan, and the victim's death sequence may already have unregistered a unit the attack killed; the remake does not model that registration race (its token lookup includes the fallen unit). Counters are not in the attacked list (the counter strike calls no `0x430020`) — same in the remake.

## Remake boundary

actCheckRoundDisp and actDetectRoundDispDisp are supported conditions in WinfailScenarioRules; the current battle turn is the remake's stand-in for the native packed display counter whose low word is the round counter above (same origin and increment; the baseline word `0x4c1bbe` handling of case 0x5e is read but the re-entry timing of the display object is not). X-range deletion is committed through BattlePresenceRules using the requested process side and pixel-derived cells. X-range insertion and level-up stars are receipts consumed by the presentation layer; they do not create a second combat-state owner. The movie route is allowed to skip in headless mode and must retain skipped_<reason> in its receipt.

## Sources

- content/imported/hsl/global/tables/ACTION.H (resource-derived)
- hsl01.exe 0x450840 cases 0x28, 0x5e, 0x68, 0x69, 0x78, 0x7b, 0x7c (static-derived)
- direct callees 0x42c400, 0x45e307, and 0x42c180 (static-derived)
- round counter writers／readers 0x42c640, 0x4074a0, 0x407510 → 0x408370 → 0x44ee20 (static-derived, r2 `axt 0x4c1bbc` and the decompiled catalog in `ignored/static/hsl01/catalog/`)
- attack context: `axt 0x4c1ce8`／`0x4c29a0`／`0x42fff0`, 0x430020, 0x44fa80, 0x450840 cases 0x2a／0x6e／0x74, `pd` at 0x443a0d and 0x43f4f0 (static-derived, lane R37)
- scan shape 0x44ebf0, 0x44ecb0, 0x44ee20, 0x453ac0, 0x453b30 (`pd` at 0x453b30), 0x44e7b0, 0x44e8d0 and 0x450840 cases 0x1f／0x44／0x4f (static-derived, lane R37)
