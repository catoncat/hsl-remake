# Level 3 Player Mode and Undead Flags

> evidence: static-derived; provisional: 反击击杀 undead 攻击者时的结算（重制未对齐） · status: live · functions: 0x40a5d0, 0x40e390, 0x43ede0, 0x4423c0, 0x442720, 0x446bb0, 0x44f580, 0x44fad0, 0x450710, 0x450840, 0x452885 · tools: run_battle_scene_runtime_tests.gd, run_winfail_rules_tests.gd, run_winnability_census_tests.gd · updated: 2026-09-28

## Scope

This packet records the `STORY003` / `WINFAIL003` token uses and the bounded static read used by the level-3 battle implementation. The script structure is `resource-derived`; the dispatcher and callee field operations are `static-derived`. It does not claim full native battle parity.

## Resource uses

`STORY003` has one `actSetPlayerMode` chain in its opening section:

```text
actSetPlayerMode SID_漢克斯, 1, pmEnemy, 1
actSetPlayerUndead SID_漢克斯, 1, 1
```

This is the opening state: 漢克斯 is hostile and marked undead. `STORY003` also arms fail statuses 0/1 and event statuses 0/1/2; the opening mode/undead pair is adjacent to the initial music action, before the scripted walks and dialogue.

`WINFAIL003` uses the same pair once in its win section:

```text
actSetPlayerMode SID_漢克斯, 1, pmPlayer, 1
actSetPlayerUndead SID_漢克斯, 1, 0
```

The win section is unconditional (`actTRUE`), follows the six dialogue groups and the final message 774, and precedes the point-3 writes and `actSetNextPlayLevelEvent 61,61`. The battle profile therefore starts 漢克斯 as `enemy_ai`; the win action changes the sole PlayLoop unit to `player_controlled` and clears its undead marker before campaign carry capture.

`WINFAIL003` condition uses are:

| section | condition | arguments | interpretation in the live interpreter |
| --- | --- | --- | --- |
| fail 0 | `actCheckPlayer` | `1, SID_雷歐納德` | 雷歐納德 is defeated |
| fail 1 | `actCheckPlayer` | `1, SID_緹娜` | 緹娜 is defeated |
| event 0 | `actCheckPlayerHPLow` | `SID_漢克斯, 1, 30` | current HP is at most 30% of max HP; the comparison is provisional relative to the native handler timing |
| event 1 | `actCheckPlayerAttacked` | `SID_緹娜, SID_漢克斯` | last settled attack has 緹娜 as attacker and 漢克斯 as defender |
| event 2 | `actCheckPlayerAttacked` | `SID_漢克斯, SID_緹娜` | last settled attack has 漢克斯 as attacker and 緹娜 as defender |
| event 3 | `actCheckPlayerAttacked` | `SID_緹娜, SID_漢克斯` | same direction as event 1 |
| event 4 | `actCheckPlayerAttacked` | `SID_漢克斯, SID_緹娜` | same direction as event 2 |

The event chains delete the opposite event status, print messages 834/835, and insert win status 0; event 0 additionally deletes events 1-4, prints 836, inserts win 0, and executes the winfail process. The event and win action order is retained in the generated seed and is evaluated by `WinfailScenarioRules`.

## Static dispatcher read

`content/imported/hsl/global/tables/ACTION.H` gives the case numbers for the script VM at `0x450840`:

- `actCheckPlayerAttacked = 42` (`0x2a`)
- `actSetPlayerUndead = 64` (`0x40`)
- `actCheckPlayerHPLow = 65` (`0x41`)
- `actSetPlayerMode = 66` (`0x42`)

In `0x450840.c`:

- case `0x40` resolves the player by `0x44fad0(code, serial)`, then sets or clears `PLAYER_TABLE[player_index] + 0xa0` bit `0x4` from the third argument. This is the source undead flag.
- case `0x41` resolves the same player and computes `PLAYER_TABLE + 0xdc * ratio / 100`, clamps the threshold to at least one, and accepts when current HP at `+0xd8` is not greater than that threshold.
- case `0x42` resolves the player and calls `0x450710(player_object, mode, flag)`. The caller advances four 32-bit arguments. `0x450710.c` writes the mode at `PLAYER_TABLE + 0x28` (`0x450763`, between `0x40ba20`／`0x411b90` before and `0x411a30` after), resets the process code `+0x64` (3 or 5) and tint, but never calls the stat refresh `0x448840`: max HP keeps the value computed under the old mode (lane HANKS3, emulator level 3: 漢克斯 L7 50/50 unchanged after STORY003 pmEnemy). It treats `0x10000` (`pmPlayer`) and `0x20000` (`pmEnemy`) as separate presentation/AI branches. The nonzero fourth argument also updates a global player-mode marker.
- case `0x2a` resolves the two `(code, serial)` arguments and calls `0x450710`'s adjacent script-object lookup path only after the attack pair is available; the live remake keeps this condition scoped to the settled `last_attack` record.

`TYPE.H` defines `pmPlayer = 0x00010000`, `pmEnemy = 0x00020000`, `pmNPCPlayer = 0x00050000`, and the combined mode constants. The level-3 pair uses only `pmEnemy` and `pmPlayer`.

`0x446bb0.c` returns `(live record + 0xa0) & 4 != 0` (`*0x4c1bc8 + obj[+0xa4] × 0x1fc`), confirming that bit `0x4` is queried as the undead trait. The decompiled catalog located one caller, `0x44f580.c`, which skips an eight-slot item/equipment processing loop when this getter is true; r2 `axt 0x446bb0` (lane E1, 2026-09-27) lists two more inside code r2 had not split into functions:

| caller | process | reading (static-derived) |
| --- | --- | --- |
| `0x43ee66` | enemy／AI object process `0x43ede0`, dead branch `0x43ee1f` (`+0x80 & 0x8000000` death flag set, `0x4000000` processed flag clear) | undead → `and [+0x80], ~0x8000000` (clear death flag), `mov [rec+0xd8], 1` (live HP = 1, `0x43ee88`), if `0x407540()` (current turn-queue slot object) is this object → `0x407510` (end its action), `inc word [[+0xac]+0x8c]` when a linked object is set, clear `+0x9c／+0xa8／+0xac／+0x8c`, continue as a living object. Not undead → `0x43ef36`: processed flag, `+0x8c = 0`, known byte `0x4c6d80[+0xa2] = 1`, dead message `0x446b60` unless `+0x80 & 0x800`, and the removal path |
| `0x4433b6` | player object process (`0x443390`) | the same revive sequence (`0x4433d8 mov [rec+0xd8], 1`, `0x4433e2 call 0x407540`, `0x4433eb call 0x407510`) |

So the undead trait is the **HP-zero survival** the earlier negative-evidence looked for: the damage paths still write the death flag (`0x4415d4`／`0x441da5`／`0x44448d`, [目标计数读法](original_check_targets.md)), and on the object's next tick the flag is undone and the record stands at 1 HP; nothing about damage reduction or immunity is read. The remake (lane E1): `BattleLoopCombat._undead_revives` — a defender or skill target with the `undead` marker whose HP reaches 0 is set to 1 HP instead of `_set_unit_defeated`, receipt `undead_revived` (`run_battle_scene_runtime_tests._test_undead_survives_lethal_strike`). The lethal hit still settles as a kill in the remake (series truncation, stamina tail, kill chain／kill EXP) before the revive.

**Kill credit on an undead victim (static-derived, lane R37 2026-09-28; only-read disassembly, no bounded execution).** The EXP of a strike is computed inside the strike itself: `0x4423c0(striker, victim, &acc, mode)` state 4 adds `0x40a5d0(striker, victim)` to the accumulator, and `0x40a5d0` adds the victim's kill EXP (record `+0x90`, kill-chain factor `+0xa8` capped at 8) when the victim's live HP (record `+0xd8`) is already below 1 — the ordinary hit EXP and the kill EXP are one number. The attacker's main strike accumulates into `0x4c2c7c` (player `0x4445c8`, AI `0x441499`), the counter into `0x4c2970` (player `0x4445fb` mode 1, AI `0x4414cc` mode 3); both, with the gold accumulators `0x4c2c84`／`0x4c2978`, are zeroed at the attack start (`0x444370..0x44437c`, `0x441431..0x441443`). Right after the strike the attacker's own process runs the kill section when the victim's HP ≤ 0 (player `0x4446ab`: `gold += 0x40e390(victim)` into `0x4c2c84`, victim `+0x80 |= 0x8000000`); the victim's undead revive happens later, in the victim's own process tick (`0x43ee66`, above), and retracts nothing. The attacker's completion states then pay through `0x442720(recipient, exp, gold)` (state 0 adds EXP to record `+0x88`, doubled by `0x40e2c0`; state 2 adds gold to the party `0x4c1bcc` or the record `+0x98`): first the attacker with `0x4c2c7c`／`0x4c2c84` (`0x4447d8..0x4447e6`, AI `0x4416bc..0x4416ca`), then the countering target `0x4c1cec` with `0x4c2970` (`0x44483c..0x44484b`, AI `0x441724..0x441738`). **So killing an undead defender pays the attacker its full strike EXP including the kill EXP, and the kill gold — on every lethal hit, since `0x40e390` only reads `+0x98` — while `0x44f580` rolls no drops for the still-undead record (`0x446bb0`).** The spell kill sections read `+0xd8` the same way (`0x442e4e..0x442e69`, `0x443126..0x44313d`), and the AI main strike too (`0x4415ac..0x4415ce`). The remake's EXP order was already the original's; its gold was not — the exchange path paid nothing (the strike's `defender_hp_after` is rewritten to 1) and the skill path settled the revived target as a death (drops, an emptied bag, and a death-ledger entry the checkpoint then refused with `invalid_saved_death_ledger`). Lane REWARD: `BattleRewardRules.undead_kill` pays the kill gold on both paths, rolls no bag and records no death (`run_battle_reward_tests.undead_victim_cases`). The death-sequence payout R36 found (`0x43f0f2..0x43f150`: `0x442720(killer +0x50, 0x4c2970, 0x4c2978)`) is the other case — an attacker killed by the counter, whose own completion states never run, pays its killer the counter accumulators from its death sequence.

**Where an AI recipient's gold goes (static-derived, lane GOLD2; only-read r2 disassembly).** `0x442720` state 2 (`0x442805..0x442890`): gold 0 skips (`0x442812`); `0x40e2d0` (gold ×2) doubles it; when `0x40ba20(recipient)` is exactly `0x10000` the gold goes to the party `0x4c1bcc` (capped at `0x3b9ac9ff`), otherwise it is added to the recipient's own record `+0x98` (`0x442856..0x442875`, record = `[0x4c1bc8] + obj+0xa4 × 0x1fc`, no cap), then a `$` float is spawned either way (`0x44287b..0x442890`). `0x4c2c84` is the action's gold accumulator, paid out through this state by the completion award: on the AI path the main-strike kill adds `0x40e390(victim)` (`0x4415bc`), an AI StealGold adds its take — capped by the party gold and subtracted from `0x4c1bcc` (`0x40b562..0x40b578`) — and `0x4416bc..0x4416ca` pays `0x442720(ebp, [0x4c2c7c], [0x4c2c84])`; an AI initiator killed by the counter pays its killer `0x4c2978` from its death sequence (`0x44151d`, `0x43f150`); a player-process initiator killed by the counter pays nothing (`0x444641` has no `0x40e390`, `0x443660` passes gold 0). Neither StealGold branch lowers the target's `+0x98`. The remake: `BattleRewardRules.accrues`／`accrue` add the victim's `carried_gold` to a non-commandable, non-party killer's `carried_gold_gained` (a controlled initiator killed by the counter adds nothing), `BattleLoopRewards._apply_gold_effects` adds an AI StealGold's party-gold take the same way, and `carried_gold` (kill payout and StealGold cap) reads template／instance gold + entry growth + `carried_gold_gained`; the field is saved in the battle checkpoint and checked by `data_error` (`invalid_carried_gold`). Tests: `run_battle_reward_tests.carried_gold_cases`, `run_skill_resolution_tests` (竊殺 against a grown killer, a robber killed after draining the party). Lane REWARD modelled gold ×2 (ITEM `gold_x2`, row 230 黃金的聖杯, → `BattleRewardRules.gold_multiplier`, applied before either branch and before the cap, also to a StealGold take; `run_battle_reward_tests.gold_double_cases`), the friendly AI whose `0x40ba20` is exactly `0x10000` paying the party (`party_recipient`／`pay_party`, capped; `party_recipient_cases`) and the pending-item handoff below. Still not modelled: the `$` float over an AI recipient; the only modelled source of the `+0x18c` bit 0x20 is equipment.

**Pending items for an AI recipient (static-derived, lane REWARD; only-read r2 disassembly).** `0x442720` sets its player flag from the recipient's object `+0x64 == 3` (`0x44272b..0x44273a`). State 4 (`0x4428b1`) skips an empty collection (`0x44f4d0`); for a recipient that is not a player process it calls `0x44f600(recipient)` (`0x4428cd`) instead of the get-item window, then `0x44f4e0` (`0x4428d5`) empties the collection. `0x44f600` walks the collection entries with `0x44f3b0` — one `(code, count)` entry per distinct code, because `0x44f2d0` adds a repeated code to the existing entry's count (`0x44f290`／`0x44f39b`) — and inserts **one** of each code with `0x436e30` (first empty slot); if that fails, `0x44f510` removes the first non-empty slot whose item `+0xa0` lacks `0x8000000` (important) through `0x436e80` and the insert is retried once; a second failure ends the walk, and whatever was left is lost with the collection. The collection is filled by the kill sections' drop roll `0x44f580` whoever the killer is (AI `0x441587` counter-killed initiator, `0x44163e` main-strike defender, `0x441e2a`／`0x441e49` spells; player-side `0x44469e` initiator killed by the counter, `0x44474d`, `0x4453e9`, `0x445408`) — so an enemy that counter-kills a controlled initiator takes its rolled items even though `0x443660` pays it gold 0 — and by StealItem (`0x40b629` → `0x44f2d0`). The remake: `BattleRewardRules.generate` rolls the victim's bag for an AI killer into `taken`, `BattleLoopRewards._commit_rewards` adds an AI caster's 金之手 take, and `hand_over` applies the rule above to each recipient's bag after the victims' bags are emptied; receipt `rewards.taken` lists `code`／`slot` (−1 lost)／`discarded`／`sources` (`run_battle_reward_tests.ai_handoff_cases`). The order of kill drops ahead of a StealItem take within one receipt is remake order (provisional).

**Undead attacker killed by the counter (lane REWARD, now matched):** an **undead attacker killed by the counter** revives in its own tick, resets its state (`0x43eec9`) and, as the current actor, ends the action through `0x407510` (`0x43ee92..0x43ee9b` enemy, `0x4433e2..0x4433eb` player): neither its completion award (its own strike EXP `0x4c2c7c`) nor the death-sequence payout to the countering unit (`0x4c2970` EXP, `0x4c2978` kill gold) runs, so nobody is paid for that exchange. The remake used to pay both; `BattleLoopCombat._attacker_revived` now makes `_resolve_exchange` pay neither EXP (settlement reason `undead_action_ended`), and `BattleRewardRules.undead_kill` excludes that victim from kill gold (`run_battle_reward_tests.undead_counter_cases`). Still open (unverified): the remake revives an undead defender inside the strike, so the exchange then lets it counter; whether the original's lethal branch skips the counter (`0x4415b5`／`0x4446cc`: `+0xd8 > 0` jumps to `0x441fa4`／`0x443b19`, the lethal side runs the kill section) was not traced. Confirmation = a Wine level-3 route where 漢克斯 (undead, STORY003) attacks and dies to 緹娜's counter, reading both units' EXP (record `+0x88`) before and after. `0x44f580`'s equipment skip and the `+0xac` linked object are outside this claim.

## HPLow threshold (static-derived, lane R6-L8)

Re-read with capstone on the same `hsl01.exe` (only disassembly, Wine not started): the action dispatcher's second switch `0x4508a1 jmp [edi*4 + 0x4537f4]` sends case `0x41` to `0x452885`:

| address | instruction effect |
| --- | --- |
| `0x452885`..`0x452899` | reads `code`, `serial`, `ratio` and resolves the object with `0x44fad0(code, serial)` |
| `0x4528a4` | lookup miss (`-1`) → the "does not hold" exit `0x4527c3` |
| `0x4528cc`..`0x4528e0` | `max HP (+0xdc) × ratio`, signed divide by 100 (`0x51eb851f`, `sar 5`, sign fix) |
| `0x4528e2`..`0x4528e7` | threshold below 1 → 1 |
| `0x4528ec`..`0x4528f8` | live HP `+0xd8` greater than the threshold → not held; otherwise held (`0x452794`) |

Consequence for the scripts: `actCheckPlayerHPLow code,serial,0` holds at **HP ≤ 1**, not only after death. Every such use targets a unit the script made undead (STORY／WINFAIL 030／031／032／033／036／037／041／059／075／076／077／078／079), and an undead unit revives at 1 HP instead of dying (table above), so in the original the condition fires on the blow that would have killed it. Before R6-L8 the remake read ratio 0 as "HP ≤ 0": the revive left HP 1 and the win／event never fired, which made the boss fights of 41／59／75／76／77／79 and the undead-gated events of 30–37 unwinnable or unreachable. `WinfailConditions.hp_low_threshold` now uses the threshold above; `tests/run_winnability_census_tests.gd` checks, for every HPLow condition of all registered battles, that its target satisfies it at the revive HP.

provisional: a **defeated** unit is still read as HP 0 (holds) in the remake; the original lookup no longer finds an unregistered object (`0x4528a4`), but whether the scan runs before the death unregisters it (`0x43ef36`) is not read. No script uses a non-undead ratio-0 target in a way where the difference decides a battle.

## Runtime boundary

`WinfailScenarioRules` applies mode changes to the units in the sole `BattlePlayLoop` dictionary. It maps `pmPlayer` to `player_controlled`, `pmNPCPlayer` to `friendly_ai`, and `pmEnemy` to `enemy_ai`, updating `player_commandable` with the same role transition. `actSetPlayerUndead` updates the same unit's `undead` field and keeps an immutable runtime receipt. `ActorRuntime` only mirrors the resulting role/visibility; it does not own either field.

The initial level-3 `hanks` role override is resource-derived from `STORY003`'s opening pair. The level-3 formal battle uses the opening's `actSetPlayerUndead` value as an initial unit flag. Both the initial flag and the win-section clear are explicit product wiring; exact native opening-to-battle timing remains provisional.

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/loop/BattleLoopRewards.gd` rules：0x442720 state 2 pays kill gold and the StealGold take 0x4c2c84 to the same recipient branch — the party capped at 0x3b9ac9ff for exactly 0x10000, else the caster／killer's record +0x98 — both doubled first by the recipient's gold_x2 bit, 0x442819..0x442825; 0x442720 state 4 gives a recipient that is not a player process the pending collection through 0x44f600 — kill drops and an AI caster's StealItem take, 0x44f2d0 — instead of the get-item window: RewardRules.hand_over
- `game/sim/BattleRewardRules.gd` rules：0x442720 state 2 pays a recipient whose 0x40ba20 is not exactly 0x10000 into its own record +0x98 — accrues／CARRIED_GAINED; exactly 0x10000 pays the party 0x4c1bcc capped at 0x3b9ac9ff, 0x442837..0x44284a — party_recipient／pay_party; before either branch 0x442819..0x442825 doubles the payment when 0x40e2d0 finds the recipient's live +0x18c bit 0x20, the ITEM gold_x2 bit 0x447e7c OR-ed in by 0x448709..0x448717 — gold_multiplier; equipment is the only modelled source of the bit; a killer that is not a player process rolls its victim's bag like any kill — 0x44f580 from 0x441587／0x44163e／0x441e2a／0x441e49 and 0x44469e, undead skipped — and 0x442720 state 4 hands the collection to it through 0x44f600 instead of the get-item window, 0x44272b／0x4428c3: one of each distinct code 0x44f290／0x44f39b, first empty slot 0x436e30, a full bag drops its first non-important item 0x44f510／0x436e80 and retries once, then 0x44f4e0 empties the collection — taken／hand_over; a lethal hit on an undead defender pays its kill gold like any kill — 0x4415bc／0x4446d3 and the spell kills 0x442e5c／0x443130 read the victim's +0xd8 <= 0 before its own tick revives it, 0x43ee66／0x4433b6, and 0x40e390 only reads +0x98, so every such hit pays again — but 0x44f580 rolls no drops for an undead bag (0x446bb0) and the revived unit is no death — undead_kill
