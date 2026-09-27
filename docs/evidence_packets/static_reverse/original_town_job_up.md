# Town Job-Up Readings (命運神殿 「升級」)

> evidence: static-derived; runtime-measured: both teCheckJobUp2 successes, the 0x434680 writes and the exchanged records from the native 回憶錄 (original_save_format.md), the 兩棲族部落 menu after the writes; negative-evidence: 018 has no SHAPEDEF row; provisional: 018 keeps 009 frames · status: live · functions: 0x4072b0, 0x414220, 0x42c700, 0x42caa0, 0x434680, 0x434770, 0x4347f0, 0x434830, 0x4348a0, 0x4348f0, 0x4373f0, 0x437a40, 0x448370, 0x448420, 0x448840, 0x44e0e0, 0x454740, 0x4547a0, 0x454870, 0x4548b0, 0x454e20, 0x45b29e, 0x45e307 · tools: hsltools/data/story_corpus.py, hsltools/probes/campaign_actor.py, hsltools/probes/steal_ratio.py · updated: 2026-09-24

Evidence tier: `static-derived` from a bounded read of the town event VM `0x454e20` (`hsl01.exe`, sha256 `f0b5f835…`) plus the resource texts already restored by `tools/hsltools/data/story_corpus.py`. This packet records what the three TOWNDEF job-up tokens do; it does not claim the whole town VM, its window timing or the original GUI.

## Tokens and dispatch

TOWNDEF.H assigns `teCheckJobUp` = 31 (`0x1f`), `teCheckJobUp2` = 32 (`0x20`) and `teCheckJobUpDeny` = 100. The inner token switch of `0x454e20` has 45 cases (0..44); token 100 is **not** dispatched — it reaches the `default` arm, which calls the VM error reporter `0x45b29e` with the string `Town command parameter error !` (`0x4794e4`). No TOWNDEF event uses token 100 either. The remake therefore keeps `teCheckJobUpDeny` recorded-only: there is no original behaviour to restore (`negative-evidence`).

The outer switch of the same function is the *phase* (high word of the VM cursor): phase `0x1f` is the job-up success presentation, phase `100` is the shared failure-message wait. These phase numbers coincide with the token ids but are not tokens.

### `teCheckJobUp [player code][fail message id][fail event]` — case `0x1f`

1. Reads the player code (`*puVar8`), stores the fail event in the global `0x4c1d54` and the fail message id in a local.
2. Calls the condition helper `0x434770(code)` (below).
3. **Success**: builds the announcement into the text buffer of resource `1354` (`0x54a`; the source text is a run of dots that only reserves the buffer):
   ```text
   "@5" + <player name 0x4347f0(code)> + "@1" + <1299 "的稱號由"> + "@3\n"
        + <current title 0x4348a0(code)> + "@1" + <1300 "變成"> + "@3\n"
        + <target title 0x434830(code)>
   ```
   `@1`/`@3`/`@5` are the message renderer's inline colour codes (`0x476c80`, `0x476c50`, `0x47856c`). Then `0x4348f0(code, 0x80000000)` performs the exchange (same helper and same flag as the battle token `actPlayerJobUpProcess`, see [level 37 tokens](original_level37_tokens.md)), `0x45e307(0,0,0x302,0)` starts the presentation object and the VM enters phase `0x1f`: sub-phase 1 re-checks the enabled slot (`0x42caa0`), opens the message window `0x4072b0(…, 0x54a, 0)` and attaches the player's face (`record+0x5c` shape / `record+4`) through `0x414220`; sub-phase 2 waits for the window to close and the script continues with the next token (in TOWNDEF that is `teDelay 60` → `tePlayerMessage [member] 130x` → `teExecEvent 71`).
4. **Failure** (`code_r0x00455d25`): phase 100 — shows the fail message `[fail message id]` as a face message of the same player (`0x4072b0` + `0x414220` with the player's shape/face when the slot is enabled, else without a face), then phase 100 waits for the window to close and jumps to `[fail event]` through `0x44e0e0`; a fail event of `-1` ends the event.

### `teCheckJobUp2 [player code][fail message id][fail event]` — case `0x20`

Identical to case `0x1f` (same condition helper, same announcement, same failure path) except:

- the exchange is `0x4348f0(code, 0x40000000)` — the second-tier flag;
- immediately afterwards `0x434680()` runs: when **both** player slot 0 (雷歐納德) and slot 1 (緹娜) are enabled and both now have job-up code 0 (`record+0x60` == 0, i.e. both have taken their second title), it applies the town writes `0x4548b0(14, 142..145)`, `0x454740(14, 153)`, `0x4547a0(14, 154..156)` and `0x454870(14, 145, {147,150,151})` on town 14 = `town_兩棲族部落` (extras.h). The helpers are the ones the te tokens of the same VM call: `case 1/3` (teAddSelfTE/teAddTE) → `0x4547a0(town, node)` for num 0 and `0x454870(town, parent, child)` per child; `case 2/4` (teDeleteSelfTE/teDeleteTE) → `0x4548b0(town, node)` for num 0; `case 0xb/0x1a` (teSetExecEvent/teSetTownExecEvent) → `0x454740(town, event)`. So the write list is: delete 142 武器店／143 護甲店／144 道具店／145 集會場, exec event 153 (神秘男子 dialogue), add root entries 154／155／156 (closed-shop lines) and 145 → {147, 150, 151}. The remake applies exactly this list through its shared tree/exec-event token handlers — the members, town and writes are data, `content/world/town_job_up_writes.json` (`hsl_town_job_up_writes.v1`, `hsl check town_job_up_writes`), read by `TownEventRules._apply_second_tier_town_writes` — and records a `job_up_town_writes` effect.

   Native observation of the resulting town (`runtime-measured`, 2026-09-21, Wine single-step, frames `ignored/r9-save/frames/presetA/`): a generated 回憶錄 with exactly this write list pre-applied on town 14 ([original_save_format.md](original_save_format.md), `second_tier_at_amphibian_gate`) was loaded through 讀取回憶錄. On load the original entered 兩棲族部落 and ran exec event 153 at once — 1735 as 雷歐納德's face message, then 1736 and 1737 as plain messages (slots 1／2 were not registered in that save, so no face or name). The root menu was four rows in tree order: 武器店 (154), 護甲店 (155), 道具店 (156), 集會場 (145) — none of the original entries 142／143／144 remained and 145 reappeared last, as `0x454870` appends a parent it does not find. 集會場 opened 兩棲族青年 (147: 「在部落的東南方有個沼地，聽說有人在那裡看到過會移動的沼澤。」, NPC face) ／ 兩棲族老人 (150) ／ 人類學者 (151); after a speaker's message the same submenu returned, `Esc` went back to the root. 武器店 (154) played 武器店老板「你們還在幹什麼？快逃命吧！」 as a face message and returned to the root — a closing line, not a shop. The 儲存回憶錄 the original wrote afterwards had town 14's exec event at 0 — event 153's own closing `teSetExecEvent town_兩棲族部落 0` had run.

   Native trigger (`runtime-measured`, 2026-09-21, Wine single-step, frames `ignored/r11-save/frames/`, tracked result [`original_save_format/HSL_second_tier_native.SAV`](original_save_format/HSL_second_tier_native.SAV)): the generated `before_second_tier_at_temple` 回憶錄 (first titles, attributes exactly at cap − 50, 283／284 held, 神殿中樞 76 → {77, 78}) was loaded; 神殿中樞 → 祈求 (77) opened event 87's member menu 雷歐納德／緹娜／離開. 雷歐納德 → 1349 → event 69: the announcement 「雷歐納德的稱號由劍豪變成終焉劍使」 appeared as his face message (the `1354` buffer built as above), then his follow-up line 「這種感覺……現在的我，真的是我嗎？」, and the menu returned as 緹娜／離開 (87 lists a member only while `0x434770` can still pass). 緹娜 → 70: 「緹娜的稱號由神官變成聖主」, 「我終於……終於得到了！」, and the menu held only 離開. The 回憶錄 the original then wrote differs from the loaded one by exactly: slot codes 800／801 → 818／819 (`0x42c700` inside `0x4348f0`), the two records (the exchange rows below, 283／284 removed from the item slots), town 16 rewritten by 79 (76 → {77, 81}, 55 → {85, 57, 86}; 80's tree writes did not run because its `teCheckTEExist 76/81` found 81 and branched to 87), and town 14 rewritten by `0x434680` — the resulting tree is byte-equal to the remake's write list (`content/world/town_job_up_writes.json`, then the `TownEventRules.SECOND_TIER_TOWN_WRITES` constant) replayed through the same helpers (`ORIGINAL_SAVE_NATIVE_SECOND_TIER_PASS`), so the token list above is confirmed item for item.

There is no separate "first job-up completed" test: because `0x4348f0` copies the target template's own `job_up_code` into `record+0x60`, a member whose template chain ends (PLAYERS 012–018 declare job-up 0) simply fails the `+0x60 != 0` test of `0x434770` on the next attempt, and 雷歐納德／緹娜 (010→019 via `obj_Player1Up2`, 011→020 via `obj_Player2Up2`) can pass it a second time. The distinction between the two tokens is only the flag written to `record+0x134` and the `0x434680` follow-up.

## Condition helper `0x434770(code)`

```text
slot enabled (0x42caa0(code) != 0)
and record.job_up_code (+0x60) != 0
and str  (+0x64) >= str_cap  (+0x74) - 50
and dex  (+0x68) >= dex_cap  (+0x78) - 50
and mind (+0x6c) >= mind_cap (+0x7c) - 50
and con  (+0x70) >= con_cap  (+0x80) - 50
```

The four base attributes and their caps are the fields already established by [original_growth_refresh.md](original_growth_refresh.md) (caps are written by `0x448370` from the twenty-row table `0x4786bc`, index `job − 80`). No level, gold, item or over-flag is read. The comparison is `cap − 50 <= value` on signed 32-bit values.

## Exchange helper `0x4348f0(code, flag)`

Already registered as `player_job_up_process`. Field-level reading (record = `[0x4c1bc8] + (code+1)·0x1fc`, target = PLAYERS template row of the resolved job-up code):

| record offset | action | domain (PLAYERS.TXT field) |
| --- | --- | --- |
| +0x8, +0xc, +0x10, +0x14 | copied only when the target value is non-zero | the sound-handle pairs sound_walk／sound_dead, sound_miss／sound_attack, sound_hit／sound_walkwater and the dead_message pair (the PAK handle rule in [original_save_format.md](original_save_format.md), verified on the template dump) |
| +0x18, +0x1c | always copied | job code, class (title) resource id |
| +0x20, +0x22 | copied when non-zero | class word (TYPE.H `classHuman` 101 …) and the sound_shoothit handle (template dump) |
| +0x2c, +0x5c, +0x60 | always copied | shape record, face resource, **job_up_code** |
| +0xa0, +0xec | copied when non-zero | +0xa0 object shape class (also copied unconditionally at the end); +0xec is the first equipment slot (`0x448840` applies `+0xec..+0x100` through `0x448420`) — the target weapon replaces the member's weapon only when declared |
| +0x118..+0x128 | `min(80, record + target)` | five base resists (earth/water/air/fire/mind) |
| +0x130 | `min(12, record + target)` | base move_point |
| +0x194..+0x1a0 | `record + target` on the **low words** only (`add word [esi+0x194], cx` at `0x434aa6`, `0x434ab4`, `0x434ac2`, `0x434ad0`) | PLAYERS loader `0x44b980` writes these four dwords from `steal_ratio` (+0x194), `avoid_hit_ratio` (+0x198), `attack_back` (+0x19c), `attack_damagex2` (+0x1a0); the high words `+0x196`／`+0x19a`／`+0x19e`／`+0x1a2` are `0x448840` work values (low word, or 12 when it is 0) and are not summed. The remake sums `avoid_hit_ratio`／`attack_back`／`attack_damagex2` (`JobUpRules.ADDITIVE_SOURCE_KEYS`) and, since R27, `steal_ratio` as `combat_profile.base_steal_ratio` (the word lives beside the work value `combat_profile.steal_ratio` rather than in `growth_profile.source`, whose shape the native receipts compare byte for byte); `SpecialUtilityRules` reads the refreshed work value. The only affected chain is 漢克斯 004 (steal_ratio 30) → 013 (20) = 50 natively (`resource-derived` PLAYERS.TXT rows), which `run_skill_resolution_tests` replays. Widths are `static-derived` from the listing; the native 回憶錄 does not discriminate them for 001／002. R32 executed `0x4348f0` itself on 004→013／001→010／010→019／013→004 records ([original_steal_ratio.json](original_steal_ratio.json) `job_up`): `+0x194` low word 30+20=50, the inner `0x448840` rewrote `+0x196` to 50 (70 with 131 equipped), 0+0 stays 0 → work value 12 |
| +0x1a4..+0x1b4 | `record + target` (dwords) | the additive PLAYERS numeric layer `0x448840` reads at entry: `+0x1a4` attack_power → attack, `+0x1a8` magic_attack_power → magic attack, `+0x1ac` defense, `+0x1b0` speed, `+0x1b4`/`+0x1b6` signed magic_point／hit_point word pair added to max MP／HP (the template dump pins the packing: PLAYERS 066 declares `hit_point -10000`). The remake sums the template's source fields (attack_power, magic_attack_power, defense, speed, hit_point, magic_point, avoid_hit_ratio, attack_back, attack_damagex2) into the member's growth source |
| +0x134 | `|= flag` | job-up flags (0x80000000 first tier / 0x40000000 second tier) |
| slot code `0x4c4360[slot]` | `0x42c700(slot, up code)` | the registered slot code becomes the consumed `obj_Player<N>Up<tier>` object (800／801 → 818／819 native); the remake keeps the member keyed by `actor_id` and records the target in `job_up_history` |

Level (+0x9c), experience, the four base attributes (+0x64..+0x70), inventory (+0x138..) and the equipment slots other than a non-zero target weapon are **not** touched; `0x448840` is then called so the new job branch derives HP/MP/attack/defence/resists from the unchanged attributes. PLAYERS 010–020 declare no equipment except 017 (weapon 53), so a member keeps its gear.

The remake's town path (`CampaignCarryRules`/`WorldPartyRules` + `JobUpRules`) therefore keeps the carry member's level, exp, attributes, equipment, inventory and learned skills, swaps the actor id / job / class / source profile to the generated target template (`content/generated/hsl/actors/010–020.json`), sums the template's additive source fields into the member's `permanent_gains`-independent job-up layer, and lets the shared `ProgressionRules.refresh_growth_stats` derive the live stats — no second stat refresh is created.

## Job branches needed by the up templates

`0x448840` cases for the target jobs (resistance tuples are `min(cap, pct·mind/100 + con/div)` for earth, water, air, fire, mind; the numeric branch is shared with the base job of the same family, see [original_job_stats.md](original_job_stats.md)):

| job | case | numeric branch | magic bonus | resist cap | resists (pct, div) |
| --- | --- | --- | --- | --- | --- |
| 81 jobSwordMaster | `0x51` | SwordMan (post-switch) | +30 | 45 | (56,3) (32,4) (26,4) (64,3) (20,5) |
| 82 jobSwordKing | `0x52` | SwordMan | +32 | 50 | (62,3) (38,3) (30,3) (66,3) (26,4) |
| 84 jobBowMaster | `0x54` | BowMan `0x4492f3` | — | 46 | (34,4) (30,4) (56,3) (46,4) (40,4) |
| 86 jobPriestMaster | `0x56` | Priest `0x4498c9` | +15 | 56 | (52,3) (58,2) (36,3) (46,3) (44,3) |
| 87 jobWise | `0x57` | Priest `0x4498c9` | +15 | 70 | (70,3) (72,2) (50,3) (58,3) (62,3) |
| 89 jobAssassin | `0x59` | Thief `0x449d1d` | — | 44 | (26,3) (56,3) (32,3) (38,4) (14,3) |
| 97 jobEvilMonster | `0x61` | own (below) | — | 66 | (55,4) (58,3) (52,3) (56,3) (50,5) |

EvilMonster numeric branch: `max_hp = str/3 + 170·hp_level/100 + 240·con/100`, `max_mp = con/3 + 110·mind/100`, `attack += 40·dex/100 + 110·(str/2)/100 + 12`, `defense += con/3 + dex/5 + 28·str/100 + mind/4`, `magic += min(12·mind/100 + 19 + level, 75)`, `speed += 80·dex/100`. Caps rows (`0x4786bc`): 81 [130,112,100,110], 82 [570,690,490,750], 84 [610,750,370,550], 86 [96,102,142,112], 87 [450,570,950,550], 89 [570,730,330,690], 97 [950,850,650,1050]. These branches are checked by the bounded native probe `tools/hsltools/probes/campaign_actor.py` when the up templates are part of `CAMPAIGN_ACTORS`.

## R25 复核：条件与合并的读点（2026-09-24，static-derived，只读反汇编）

矩阵此前把本行标 provisional 的那句是「兩棲族部落 第二次转职后菜单未原生观察」——本包上文已记录 2026-09-21 的两次原生观察（预置写入的 回憶錄 与从 `before_second_tier_at_temple` 触发的两次 `teCheckJobUp2` 成功），该句已过时。本节按矩阵要求把「哪一部分是读出的、哪一部分仍是推断」列清：

| 内容 | 读点 | 等级 |
| --- | --- | --- |
| 条件 `0x434770`：槽启用 → `+0x60 != 0` → 四属性各 `cap − 50 <= value`（有符号）→ 四项全过才返回 1 | `0x434779 call 0x42caa0`；`0x434798 mov ecx,[rec+0x60]; je`；`0x4347a0..0x4347e0` 四组 `mov edx,[rec+0x74／0x78／0x7c／0x80]; sub edx,0x32; cmp edx,[rec+0x64／0x68／0x6c／0x70]; jg`；`0x4347e1 cmp ecx,4` | static-derived（反汇编）；两次原生成功另为 runtime-measured |
| 合并 `0x4348f0`：目标行由 `+0x60` 经 `0x45dbe1` 解析，`0x42c700` 换槽 code，武器 `+0xec` 非零才覆盖 | `0x43495e mov ecx,[tmpl+0xec]; 0x434969 mov [esi+0xec],ecx`（有 `test`/`je` 守卫） | static-derived；801→819 换码由原生 回憶錄 确认 |
| 五抗性 `min(80, a+b)`、移动力 `min(12, a+b)` | `0x434a7b..0x434a99`（`cmp …,0xc`） | static-derived |
| `+0x194..+0x1a0` 四个**字**相加；`+0x1a4..+0x1b4` 五个 DWORD 相加；`+0x134 |= flag` | `0x434aa6／0x434ab4／0x434ac2／0x434ad0 add word`；`0x434ad7..0x434b42 mov／add dword`；`0x434b2c..0x434b48` | static-derived（字段名由 PLAYERS loader `0x44b980` 的同偏移写入给出：`steal_ratio→+0x194`、`avoid_hit_ratio→+0x198`、`attack_back→+0x19c`、`attack_damagex2→+0x1a0`、`attack_power→+0x1a4`、`magic_attack_power→+0x1a8`、`defense→+0x1ac`、`speed→+0x1b0`、`hit_point<<16 | magic_point→+0x1b4`） |
| 保留等级／经验／四属性／背包／其余装备 | 函数体无对应写入（negative：`0x4348f0` 全部 store 列于上表） | static-derived |

仍不是「读出的」：

- 原作对 018（克羅蒂 首个稱號）画什么——SHAPEDEF.TXT 无该行（negative-evidence）；重制保留 009 帧是表现回退（provisional 表现选择）。替换证据：原生 回憶錄 把槽 8 code 写成 817（`obj_Player9Up1`）并进入任意战斗观察行走帧／缺帧行为；实现不支持的结论：原作 018 有任何可见形态。
- `teCheckJobUp2` 的失败路径（fail message／fail event）与城镇内首次 `teCheckJobUp` 未原生观察，只有 `0x454e20` case 0x1f／0x20 的读法。
- `steal_ratio` 的字相加已由 R27 接入（`JobUpRules.merge_source_template` 相加 `combat_profile.base_steal_ratio`，偷窃规则消费刷新后的 `steal_ratio` 工作值；读法见 [技能功能位「偷窃加成字」](original_skill_function_bits.md#偷窃加成字-0x1940x1962026-09-22-lane-r27-读法lane-r32-有界原生执行static-derivednative-receipt)）。

## Limits

- The original message window timing, the `0x45e307` presentation object and the face/shape attachment are not remade; the remake shows the announcement through the existing town face-message effect.
- `0x434680`'s 兩棲族部落 writes are applied through the shared tree helpers; the resulting root menu (154／155／156／145), the 集會場 speakers (147／150／151), event 153's three messages and the 武器店 closing line were observed natively from a generated 回憶錄 with the writes pre-applied, and the trigger itself — both `teCheckJobUp2` successes with their announcements, the `0x434680` town rewrite and the exchanged records — ran natively from the `before_second_tier_at_temple` 回憶錄 (`runtime-measured`, see above). Still not observed natively: a `teCheckJobUp2` **failure** (the fail message / fail event path) and the first-tier `teCheckJobUp` token in a town (its battle form is the level-37 `actPlayerJobUpProcess`).
- The remake keeps the member's `actor_id` as the rules key (skill book, AI, rewards, carry) and stores the target row in `job_up_target_actor_id` / `job_up_history`; the original overwrites job/title/shape/face in place. Presentation follows the target row through `game/battle/runtime/ActorSpriteKey.gd`: the up-title walk frames (`@:\shape\010-…020-….shp`, 30 members each; plus the level-37 052) are imported into the shared `content/imported/hsl/shared/actor_walk_frames/` manifest and drawn in battle, the panel title comes from the target row (劍豪／神官／…), and the portrait follows it only for 020 (`SHAPE\FACE0020.SHP`, whose bytes equal `FACE0001.SHP` — `resource-derived`; rows 010–019 declare the base FACE). Two gaps: SHAPEDEF.TXT carries row 018 (`SID_PLAYER17`, 魍魎劍士) only as a commented-out block, so the engine has no shape binding for 克羅蒂's first title (`negative-evidence`; the PAK does hold 30 `018-*` members) and the remake keeps her 009 frames (`provisional`); the four sound fields the exchange copies are re-bound through the shared job-up audio manifest (`content/imported/hsl/shared/actor_audio.json`, rows 010–020 from the same PLAYERS fields, plus the level-37 guardian 052 whose walk frames share the up-title manifest — `FLY002`／`ATTACK20`／`DEAD0003` from PLAYERS code 52, `resource-derived`; it is fielded only by the script insert, so no level audio manifest carried it and it walked silently until lane J1; only 017 differs from its base row — `FLY002`／`ATTACK20`／`DEAD0003` against 008's `ANIMAL004`／`SHOOT007`／`DEAD0005`; `ActorSpriteKey.audio_binding` looks the level manifest up first); the story-only scenes and the big-map marker draw the carried member's row through the same lookups (`BattleSceneStage._carried_unit_view`) — a remake presentation choice, as the original walker's shape source is not located.
- Learning after the job-up follows the member's current job code: the up-job tables (81/82/84/86/87/89/91/97/99) are `static-derived` from the `0x4373f0`/`0x437a40` dispatch and 714 native learner returns ([上位职业的学习表](original_growth_lifecycle.md#上位职业的学习表static-derived)); skills learned before the job-up stay recorded under the previous job (LearningRules accepts records from any job in `job_up_history`).
- No level or item requirement exists in the original condition; the remake adds none.
