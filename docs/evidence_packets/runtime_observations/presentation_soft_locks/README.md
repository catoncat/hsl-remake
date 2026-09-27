# 自动对局暴露的表现层软锁：遗言模板、绝技切入帧、对白头像（数据合同化）

> evidence: runtime-measured; resource-derived · status: live · tools: hsltools/assets/combat_animation.py, hsltools/data/combat_aftermath.py, hsltools/levels/actors.py, hsltools/levels/battle.py, run_autoplay_sweep_tests.gd, run_presentation_contract_tests.gd · updated: 2026-09-27

## 结论

- 原版：遗言文本、绝技 `s_shape` 条带与对白头像都来自 PLAYERS／ANIMAL／RESOURCE 的逐行字段；PLAYERS 66 行里没有 `dead_message` 的行本来就沉默，ANIMAL 块未声明 `s_shape` 的魔物本来就没有绝技条带（resource-derived）。
- 重制：`content/generated/hsl/combat/aftermath.json` 对全部 66 行声明遗言（`messages: []`＝沉默）、combat manifest 对每个演员行声明 `special_frames`（条带或 `[]`）、`hsltools.levels.battle.cast_gaps` 在装配时校验阵容；运行时 `BattleAftermath`／`BattleCombatCutin`／`BattleDialogue` 遇到声明外的缺失只 `push_error`、不软锁（runtime-measured）。
- 差异：遗言取第一条非零变体与淡出时钟仍是 provisional 编排；53 关 緹娜 winfail 台词的原版画面未采样（provisional）。

## 证据

无夹具自动对局（127 场）日志里 17,982 行 SCRIPT ERROR 全部来自产品表现层；下列表是在 pipeline-line `3861f6af` 上复现的基线量值（runtime-measured，重制侧）。

### 基线复现（3861f6af，`HSL_AUTOPLAY_LEVELS=36,39,552,33,34,44`）

| 关 | 基线 | 根因（与任务书假设的差异） |
| --- | --- | --- |
| 39 | `result_page=false`，`Missing death-message template: 005` | `BattleAftermath.prepare` 在 `stage="queued"` 前 assert 中止，同一收据里先入队的死亡 job 让 `busy()` 永真 → 无结果页 |
| 552 | `Missing death-message template: 044`（这一局到了结果页：044 是收据里唯一死者，jobs 为空） | 同上；是否软锁取决于同一收据里死者顺序 |
| 33／34 | `Missing dialogue portrait: 029` ×2 | **不是遗言**：winfail 剧情台词经 `BattlePresentation.SPEAKER_PORTRAIT_ACTORS` 的 `"1"→029`（公主行，仅 53 关 manifest 有）取头像；同表没有的说话人（3／4／5／652…）被 `push_error` 静默丢行 |
| 36 | `result_page=true`，0 错误 | `special_frames` 已是"切入行→基础行→[]"；只需补数据声明与回归 |
| 44 | 0 错误（这一局无遗言死者） | 阵容表缺 021／022 与遗言头像（见表 C） |

`Missing dialogue portrait` 的 assert 中止 `show_message` 前 aftermath 已置 `stage="dialogue"`——面板不可见却等待确认，是第二种软锁形态。

### A. 可阵亡演员 × 遗言模板（`content/generated/hsl/combat/aftermath.json`）

量法：`content/battles/battle_*.json` 的 `playable_units`＋`script_actor_templates[*].actor` 的 `actor_id`（50 个）对 PLAYERS `[character]` 行（66 个）。基线只声明 15 个演员；现在每个 PLAYERS 行都有模板，`messages: []` 是该行本身没有 `dead_message`（`silent_actors` 列出），不是缺导入。

| actor | speaker | dead_message | 基线有模板 | 出场战斗数 |
| --- | --- | --- | --- | --- |
| 001–004、006 | — | —（沉默） | 有 | 110–120 |
| 005、007、009 | — | —（沉默） | 缺 | 102–117 |
| 008 | 咕嚕（`name_7`→RESOURCE 7；该行无 `job_show_name`） | 1825 | 缺 | 106 |
| 021 | 拉爾斯帝國兵 | 372, 373 | 有 | 2 |
| 023／024 | 一般兵／重裝兵 | 374, 375 | 有 | 11／10 |
| 028 | 盜賊 | 739, 740 | 有 | 1 |
| 041／043 | 翼戰士／翼射手 | 1454, 1455 | 缺 | 11／14 |
| 048 | 海鬥士 | 1728, 739 | 缺 | 2 |
| 049 | 魔騎士 | 1570 | 缺 | 36 |
| 064 | 商人 | 1375 | 缺 | 1 |
| 036、039、061、062 | — | —（沉默） | 有 | 22／3／1／4 |
| 022、027、030–035、037、038、044、045、050–060、065 | — | —（沉默） | 缺 | 1–30 |

025（帝國皇帝，395）、026（帝國法師，372/373）不在 battle JSON 里出场（第二战 first/second_battle 路径），模板保留。

### B. 会施放绝技的演员 × `special_frames`（`content/imported/hsl/chapter01/combat_animation/manifest.json`）

PLAYERS `special_*` 非空的 23 行。manifest 现在对 57 个演员行都写 `special_frames`：9 行为导入的 ANIMAL `s_shape` 条带，48 行为 `[]`（声明"未导入条带，切入用站立帧"，顶层 `special_frames_policy`）。

| actor | 绝技 | combat manifest | special_frames |
| --- | --- | --- | --- |
| 001 | 氣刃斬 | 是 | 7 帧（P001_201–207） |
| 003 | 毒魔箭 | 是 | 6 帧 |
| 017 | 神罰 | 是 | 3 帧 |
| 002 | 月花圓舞 | 是 | []（走 `special_segments`／MoonDancePresentation，不经此路径） |
| 004、006、007、009 | 銀之手、連續突刺、碎岩擊、魔晃斬 | 是 | []（站立帧） |
| 030、032、033、045、048、049、051、053、054、055、056、057、059 | 氣刃斬2、排山倒海2、碎岩擊2、流星降2、慌雨斬2、龍嘯天驅2、魔晃斬、殘影亂斬2、排山倒海2＋碎岩擊2、連續突刺2、虛空無轉、吸血劍2 | 是 | []（站立帧） |
| 022、069 | 氣刃斬 | 否 | —（攻击方不在 manifest → `_process_missing_ordinary_clip` 文字回执） |

上表是基线。其后 004／006／007／009 与 053（ANIMAL 块声明 P009_201）／054／055／057 的 `s_shape` 条已自 hsl.pak 导入，manifest 17 行有条带、40 行 `[]`；表中其余 `[]` 魔物的 ANIMAL 块未声明 `s_shape`（056 另查 hsl.pak 无 P056_2xx 成员，negative-evidence）。

### C. 遗言说话人 × 各关头像／音频（基线，`tools/hsltools/levels/actors.py LEVEL_CASTS` 对 battle JSON 实际放置）

两类缺口（基线量得；前者影响遗言头像，后者影响行走帧＝Leonard 单帧 fallback 与脚步／攻击／死亡音）：

| 缺口 | 关卡 | 演员 |
| --- | --- | --- |
| 有遗言却不在本关 portraits | 18／19／904 | 043 |
| | 21 | 043、049 |
| | 24／31／33／78／903 | 049 |
| | 26／28／29／38／43／59／73／77／80、501–521、534–537、539–542、544、549、555–557、559、562、565、567、569–573、576–578 | 008 |
| | 30／32／36／39／40／41／75／76、533、543、545–548、550–551、553、558、560–561、563–564、566、568、574 | 008、049 |
| | 44 | 008、023、024、049 |
| | 45 | 008、021、049 |
| | 522–525、527–528 | 008、041、043 |
| | 526、529、530 | 008、043 |
| | 531、532 | 008、024、049 |
| | 538 | 008、048 |
| | 552、554 | 008、023 |
| | 575 | 008、023、024、049 |
| | 901 | 023 |
| 可上场却不在本关阵容（无行走帧／音频） | 500 池（78 场遭遇战） | 023、032、033、045、051、065 |
| | 12 | 039 |
| | 15 | 034、035 |
| | 17 | 007 |
| | 22 | 051 |
| | 26／28／29／32 | 008（有条件安装） |
| | 30 | 008、033、034、035 |
| | 36 | 009、065 |
| | 40 | 032、065 |
| | 41 | 033、034、035 |
| | 44／45 | 021、022 |

37 关的 052（守护者）与 017 走共享上位行走表（`content/imported/hsl/shared/actor_walk_frames`），不算缺口。552 的"023 缺音频键"就是第二类：池阵容没有 023，`audio_binding` 找不到 `characters["23"]`。

## 重制接线


| 层 | 声明 | 运行时遇到声明之外的缺失 |
| --- | --- | --- |
| 遗言 | `aftermath.json` 列出全部 66 个 PLAYERS 行，`messages: []`＝沉默，`silent_actors` 汇总 | `BattleAftermath.death_template` `push_error` 后按无台词淡出；`prepare` 本地组队列再一次性发布并置 `stage`，任何中途中止都不会留下 `busy()` 永真 |
| 绝技切入 | 每行 `special_frames`（条带或 `[]`），`special_frames_policy`；`combat_animation` check 断言键必在、非导入行为 `[]` | `BattleCombatCutin.special_frames` `push_error` 并按 `[]` 继续，clip 照常 pop |
| 剧情台词头像 | 台词入队时按说话 token → `winfail_runtime.actor_bindings` 首实例 → 单位当前行（`ActorSpriteKey.row_key`）→ `SID_ENEMYnnn` → 首战名字表 | `BattleDialogue.show_message` `push_error` 后无头像显示台词，可推进 |
| 关卡阵容 | `LEVEL_CASTS[level].actors` 补齐上表；portraits＝脚本说话人 ∪ 阵容里带 `dead_message` 的行（`cast_speakers` 派生）；`hsltools.levels.battle.cast_gaps` 在装配后校验每个可上场演员有行走帧、PLAYERS 声明了脚步声的演员在关卡或共享音频表有绑定、每个带遗言的演员有头像，`hsl check level_battle:N` 守着 | 装配失败（ValueError），不产出 battle JSON |

回执（重制侧）：基线 `HSL_AUTOPLAY_LEVELS=36,39,552,33,34,44` → 4 SCRIPT ERROR，39 `result_page=false`；遗言修正后 39／552 `result_page=true`，剩 `Missing dialogue portrait: 023`（552）；阵容补齐后 `HSL_AUTOPLAY_LEVELS=36,39,552,33,34,44,554,575,30,45` → 0 ERROR，除已知规则 dead_end 575 外全部 `result_page=true`。

provenance 写法：`runtime-measured docs/evidence_packets/runtime_observations/presentation_soft_locks/README.md`。

## 复现

`python3 tools/hsl.py check combat_aftermath_data combat_animation level_battle:44`（数据声明与阵容校验）；运行侧 `tools/godot.sh --headless --script tests/run_autoplay_sweep_tests.gd`（`HSL_AUTOPLAY_LEVELS` 选关）。

## 边界

- 遗言取第一条非零变体、淡出／经验时钟仍是 [combat_aftermath](../combat_aftermath/README.md) 的 provisional 编排；本包只扩数据覆盖。
- 53 关 `SID_PLAYER1`（緹娜，PLAYERS 002）的 winfail 台词现在取其单位行的 FACE0001，不再是 presentation-line 手表的 029 FACE0029；原作对白脸取说话对象自身的 face 字段是 static-derived（`original_town_job_up.md` 的 +0x5c），但 53 关这条台词原生画面未采样。
- 重生成 40 个 `level_actors` 时吸收了共享表增长后的既有漂移：本关副本改为引用 `chapter01/portraits`／`audio_normalized`，056 的面板名按现行 `job_show_name` 规则由 席德爾 变 四魔將（对白说话人标签仍来自脚本的 652 席德爾）；170 个不再被引用的本关 PNG／WAV 副本已删除。
- 演员是否会在某局实际阵亡／施放绝技取决于 AI 与 RNG；上表是"可能"集合，不是单局观察。
