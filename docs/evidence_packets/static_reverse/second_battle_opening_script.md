# 第二战（level 52）STORY052 开场脚本与胜负事件

> evidence: resource-derived; provisional · status: live · tools: hsl_chapter_dialogue.py, hsltools/levels/battle.py, hsltools/levels/message_text.py, hsltools/levels/source_texts.py, hsltools/levels/timeline.py · updated: 2026-09-18

Checked: 2026-09-18。证据等级 `resource-derived`，除单独标注 `provisional` 的表现／语义结论。本包只提升原脚本的 token 顺序、参数与对白正文；handler 时序、镜头、坐标空间与条件极性均未证明，第二战 live 开场尚未由这些数据驱动。

## 复跑入口

```sh
python3 tools/hsl.py check level_source_texts:52
python3 tools/hsl.py check message_text_evidence_check:52
python3 tools/hsl.py check opening_timeline_compile:52
PYTHONPATH=tools python3 -m hsltools.levels.timeline content/imported/hsl/chapter01/battle052/opening_timeline.json --source-script story052
python3 tools/hsl.py check story_scene:52 level_battle:52
```

重建需要本机原版 PAK（默认 `$HSL_ORIGINAL_DIR/hsl.pak`）：`PYTHONPATH=. python3 tools/hsl.py generate level_source_texts:52`、`PYTHONPATH=. python3 tools/hsl_chapter_dialogue.py --pak <hsl.pak> --level 52`，再运行上面的 compile（不带 `--check`）与 `python3 tools/hsl.py generate story_scene:52 level_battle:52`。

## Tracked 输出

| 文件 | 内容 | 来源与校验 |
| --- | --- | --- |
| `content/imported/hsl/chapter01/battle052/source_texts/{STORY052.TXT,winfail052.txt,obj-052.h}` | 原始脚本／头文件字节 | 与 `battle052_seed.json` 的 `sources` SHA-256 一致 |
| `content/imported/hsl/chapter01/battle052/message_text_evidence.json` | 23 条 message 正文与 6 个说话人标签 | message id 全部来自 seed 的 story／winfail 脚本与说话人表；正文与 tracked `RESOURCE.TXT` 逐字节核对 |
| `content/imported/hsl/chapter01/battle052/section_title.png` | `SHAPE01\WORD052.SHP`（惡夢的終曲 / NIGHTMARE FINALE） | 源与 PNG SHA-256 记录在 evidence |
| `content/imported/hsl/chapter01/battle052/opening_timeline.json` | 57 个 STORY052 token ＋ 1 个合成 `first_control_ready` | 与 051 共用 `hsl_first_scene_opening_timeline.v1`；对白事件附带 resource-derived 正文与说话人 |
| `content/battles/battle_052.json` | `resources.opening_timeline/message_text_evidence`、`opening.actor_bindings`、`scenario_rules.win/fail/events`（落点策略镜像） | 由 `level_battle:52`（`hsltools/levels/battle.py`）从预览 `story_052.json`＋seed＋`content/battles/levels/052.json` 生成 |

## STORY052 有效 action 流（57 token）

被 `;` 注释掉的备用动作（一组 `(194,580)` 插入、`actChangeShapeWait`、`actDEMO`、`actCheckEnemyNumber(...,3)`）不在 seed 与 timeline 中。

| 阶段 | token（顺序） | 说明 |
| --- | --- | --- |
| A 皇帝营帐 | `actSetBGToObject(SID_ENEMY025,1)`、`actPlayLevelMusic`、`actDelay(40)`、message 379／380／381、`actWalkDispWait(SID_ENEMY025,1,0,96,1)`、`actDelay(20)`+message 383、`actWalkDispWait(SID_ENEMY026,1,0,32,0)`、message 384、`actPlaySound(WAV\CLIP001.WAV)`+`actDelay(60)` | 镜头先落在 025；026 两次进言，025 沉默后表态 |
| B 镜头转向队伍 | `actScrollBGToObject(SID_PLAYER0,1)`、五个 `actWalkDispWait(...,0,-224,*)`（PLAYER0／023×2／024×2）、message 385、`actScrollBGToObject(SID_ENEMY026,2)`、`actWalkDispWait(SID_ENEMY026,2,32,64,0)`、message 386、`actWalkDispWait(SID_ENEMY026,1,0,32,0)`、message 387 | 五名玩家侧角色由地图下缘外上移 224px；两名法师察觉入侵 |
| C 卫兵进场 | 8 组 `actInsertObject(obj_Story_Level52_Enemy21,x,y)`（前 4 组带 `actSetPrevInsertObjectWaitRound(2)`）＋`actWalkPrevInsertObjectWait(x,y,8)`、`actDelay(20)` | object code 99；插入点在地图左右外侧（x=-54／650），目标像素非 32 对齐 |
| D 收尾与状态注册 | message 388／389／390／391、`actSetDeadMessage(SID_PLAYER0,1,394,0)`、`actShowSectionName(SHAPE01\WORD052.SHP)`、`actInsertWinStatus(0)`、`actInsertFailStatus(0)`、`actInsertEventStatus(0)`、`actInsertEventStatus(1)`、`actShowWinFailStatus` | 与 STORY051 同类的状态注册尾部，多出 `actInsertWinStatus` |

STORY052 与 STORY051 相比新增的 token 种类：`actSetBGToObject`、`actScrollBGToObject`、`actPlaySound`、`actInsertObject`、`actSetPrevInsertObjectWaitRound`、`actWalkPrevInsertObjectWait`、`actInsertWinStatus`。编译器为它们建立显式 kind（`background_object_target`、`camera_object_target`、`sound_effect`、`object_insert`、`inserted_object_wait_round`、`inserted_object_walk_disp_wait`、`win_status_enable`），不再落入泛化的 `script_action`；检查器对 052 profile 拒绝任何未分类 token。

## 对白与说话人

| 说话人 token | 标签 | 依据 |
| --- | --- | --- |
| SID_PLAYER0 | 雷歐納德（0） | 与 051 相同 |
| SID_ENEMY025 | 法蘭克（382） | `PLAYERS.TXT` character 25 的 name 字段 = 382，resource-derived |
| SID_ENEMY026 | 帝國法師（307） | PLAYERS name 字段为 306「???」；307 是重制说话人标签，`provisional`，沿用 051 对 021→305 的做法 |
| SID_ENEMY021／023／024 | 拉爾斯帝國兵／一般兵／重裝兵 | 与 051 相同的重制标签 |

开场 12 句：379（026）、380（025，原文即省略号，不得替换）、381（026）、383（025）、384（026）、385（PLAYER0）、386（026）、387（026）、388（PLAYER0）、389（023）、390（025）、391（PLAYER0）。胜利 378（PLAYER0）、event0 392（025）／393（PLAYER0）、Leonard 死亡遗言 394、死亡状态文字 122。正文见 evidence JSON。

## winfail052 结构（保存在 `second_battle.json.scenario_rules`）

| 段 | 条件 token | 后续 token |
| --- | --- | --- |
| win 0 | `actCheckPlayer(1,SID_ENEMY025)`；结果文字 `SID_ENEMY025,122` | `actSetUseShapeWait(SID_PLAYER0,1)`、message 378、`actSetNextPlayLevelEvent(58,58)` |
| fail 0 | `actCheckPlayer(1,SID_PLAYER0)`；结果文字 `SID_PLAYER0,122` | — |
| event 0 | `actCheckPlayerAttacked(SID_PLAYER0,SID_ENEMY025)` | message 392（025）、393（PLAYER0） |
| event 1 | `actCheckEnemyNumber(SID_ENEMY021,2)` | 4 组 `actInsertObject`＋`actWalkPrevInsertObjectWait`：(227,1356)→(227,1228)、(403,1356)→(403,1228)、(-58,987)→(134,987)、(655,987)→(463,987) |

当前 win／fail／engaged／count 的 token 由通用解释器 `WinfailScenarioRules` 直接从 seed 现场解释（手写 `SecondBattleScenarioRules` 已退役）；`events.event0.messages` 与 `[58,58]` 的跨关 handoff 已接入，`use_shape_wait` 与逐个插入／行走的表现仍为记录项。`actCheckPlayer` 参数 1 的存活极性、`actCheckEnemyNumber` 的比较关系与一次性执行、`actCheckPlayerAttacked` 是否含反击／技能，均为 `provisional`。

## 坐标候选（provisional）

`actWalkDispWait` 的 (x,y) 视为相对位移时的 32px 格候选：025 (10,10)→(10,13)；026/1 (12,12)→(12,13)→(12,14)；026/2 (8,12)→(9,14)；PLAYER0 (10,42)→(10,35)；023 (12,44)→(12,37)、(8,44)→(8,37)；024 (6,46)→(6,39)、(14,46)→(14,39)。这些与 `second_battle.json` 的初始 `coord` 一致，但脚本只证明参数存在，不证明其为位移、脚点或路径。八个 `actWalkPrevInsertObjectWait` 目标除以 32 均非整数（如 (260,485)→(8.125,15.16)），只能作为量化候选，不能直接宣称为逻辑格。

## 不支持的结论

- 不能由脚本 token 推断镜头曲线、延迟单位、行走速度／朝向或消息框布局。
- `defProcEnemy`／`obj_Story_Level52_Enemy21` 不证明阵营；023／024 的友军映射仍是 scenario adapter 的明示选择。
- 第二战开场 live、event 表现与跨关承接不因本包完成而成立；见 [PROJECT Next steps](../../PROJECT.md#next-steps)。
