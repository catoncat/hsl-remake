# 第二战（level 52）输入：seed、STORY052 开场脚本与 WINFAIL052 胜负事件

> evidence: resource-derived; provisional · status: live · tools: hsl_chapter_dialogue.py, hsltools/levels/battle.py, hsltools/levels/message_text.py, hsltools/levels/seed.py, hsltools/levels/source_texts.py, hsltools/levels/timeline.py · updated: 2026-09-27

## 结论

- 原版 level 52 的地图、EVEF 编队、STORY052 的 57 个有效 token 与 WINFAIL052 的 win／fail／两个 event 段都可从 PAK 逐字节读出（resource-derived）。
- 重制由 `hsltools/levels/seed.py` 与 `hsltools/levels/battle.py` 组装 `content/battles/battle_052.json`，开场由 `BattleOpeningCoordinator` 按 `opening_timeline.json` 播放，胜负事件由 `WinfailScenarioRules` 现场解释（resource-derived 输入；表现 provisional）。
- 差异：handler 时序、镜头、坐标空间、条件极性未读；差异清单 `winfail-readings`（provisional）。

## 证据

### resource-derived：seed

| 项 | 读数 |
| --- | --- |
| 源成员 | `STORY052.TXT`、`winfail052.txt`、`level052.bin`、`level052.wrd`、`obj-052.h`、`obj-052.obs`、`shape01/level52.shp`（长度与 SHA-256 记在 `battle052_seed.json` 的 `sources`） |
| 地图 | LEVEL52 SHP 640×1280；WRD 20×40（800 格），23 格带 `0xff` 阻挡属性；像素／格 = 32×32 |
| EVEF | 36 条记录、35 条非零：2 条 battle-manager、23 条站立／地图物件、9 条 `defProcEnemy`、1 条 `defProcPlayerInstall`；`defProcEnemy` 是对象过程分类，不是阵营（023／024 随 Leonard 行进） |
| 放置 | object 97／`Enemy025` (320,320)；两条 object 98／`Enemy026` 约 (384,384)／(256,384)；两条 object 94／sprite 022 约 (480,448)／(192,416)；Leonard（object 6）(320,1344)；两名 023 在 y=1408、两名 024 在 y=1472（均在 1280 px 地图下缘外） |
| 插入对象 | `obj_Story_Level52_Enemy21` → object code 99（`Enemy021`） |

### resource-derived：STORY052 有效 action 流（57 token）

被 `;` 注释掉的备用动作（一组 `(194,580)` 插入、`actChangeShapeWait`、`actDEMO`、`actCheckEnemyNumber(...,3)`）不在 seed 与 timeline 中。

| 阶段 | token（顺序） | 说明 |
| --- | --- | --- |
| A 皇帝营帐 | `actSetBGToObject(SID_ENEMY025,1)`、`actPlayLevelMusic`、`actDelay(40)`、message 379／380／381、`actWalkDispWait(SID_ENEMY025,1,0,96,1)`、`actDelay(20)`+message 383、`actWalkDispWait(SID_ENEMY026,1,0,32,0)`、message 384、`actPlaySound(WAV\CLIP001.WAV)`+`actDelay(60)` | 镜头先落在 025 |
| B 镜头转向队伍 | `actScrollBGToObject(SID_PLAYER0,1)`、五个 `actWalkDispWait(...,0,-224,*)`（PLAYER0／023×2／024×2）、message 385、`actScrollBGToObject(SID_ENEMY026,2)`、`actWalkDispWait(SID_ENEMY026,2,32,64,0)`、message 386、`actWalkDispWait(SID_ENEMY026,1,0,32,0)`、message 387 | 五名玩家侧角色由地图下缘外上移 224 px |
| C 卫兵进场 | 8 组 `actInsertObject(obj_Story_Level52_Enemy21,x,y)`（前 4 组带 `actSetPrevInsertObjectWaitRound(2)`）＋`actWalkPrevInsertObjectWait(x,y,8)`、`actDelay(20)` | 插入点在地图左右外侧（x=-54／650），目标像素非 32 对齐 |
| D 收尾与状态注册 | message 388／389／390／391、`actSetDeadMessage(SID_PLAYER0,1,394,0)`、`actShowSectionName(SHAPE01\WORD052.SHP)`、`actInsertWinStatus(0)`、`actInsertFailStatus(0)`、`actInsertEventStatus(0)`、`actInsertEventStatus(1)`、`actShowWinFailStatus` | 比 STORY051 多 `actInsertWinStatus` |

相对 STORY051 新增的 token 种类及编译 kind：`actSetBGToObject`（`background_object_target`）、`actScrollBGToObject`（`camera_object_target`）、`actPlaySound`（`sound_effect`）、`actInsertObject`（`object_insert`）、`actSetPrevInsertObjectWaitRound`（`inserted_object_wait_round`）、`actWalkPrevInsertObjectWait`（`inserted_object_walk_disp_wait`）、`actInsertWinStatus`（`win_status_enable`）。

### resource-derived：对白与说话人

| 说话人 token | 标签 | 依据 |
| --- | --- | --- |
| SID_PLAYER0 | 雷歐納德（0） | 与 051 相同 |
| SID_ENEMY025 | 法蘭克（382） | `PLAYERS.TXT` character 25 的 name 字段 = 382 |
| SID_ENEMY026 | 帝國法師（307） | PLAYERS name 字段为 306「???」；307 是重制说话人标签（provisional） |
| SID_ENEMY021／023／024 | 拉爾斯帝國兵／一般兵／重裝兵 | 与 051 相同的重制标签 |

开场 12 句：379（026）、380（025，原文即省略号）、381（026）、383（025）、384（026）、385（PLAYER0）、386（026）、387（026）、388（PLAYER0）、389（023）、390（025）、391（PLAYER0）。胜利 378（PLAYER0）、event0 392（025）／393（PLAYER0）、Leonard 死亡遗言 394、死亡状态文字 122。

### resource-derived：WINFAIL052

| 段 | 条件 token | 后续 token |
| --- | --- | --- |
| win 0 | `actCheckPlayer(1,SID_ENEMY025)`；结果文字 `SID_ENEMY025,122` | `actSetUseShapeWait(SID_PLAYER0,1)`、message 378、`actSetNextPlayLevelEvent(58,58)` |
| fail 0 | `actCheckPlayer(1,SID_PLAYER0)`；结果文字 `SID_PLAYER0,122` | — |
| event 0 | `actCheckPlayerAttacked(SID_PLAYER0,SID_ENEMY025)` | message 392（025）、393（PLAYER0） |
| event 1 | `actCheckEnemyNumber(SID_ENEMY021,2)` | 4 组 `actInsertObject`＋`actWalkPrevInsertObjectWait`：(227,1356)→(227,1228)、(403,1356)→(403,1228)、(-58,987)→(134,987)、(655,987)→(463,987) |

### provisional：坐标候选

`actWalkDispWait` 的 (x,y) 视为相对位移时的 32 px 格候选：025 (10,10)→(10,13)；026/1 (12,12)→(12,13)→(12,14)；026/2 (8,12)→(9,14)；PLAYER0 (10,42)→(10,35)；023 (12,44)→(12,37)、(8,44)→(8,37)；024 (6,46)→(6,39)、(14,46)→(14,39)。八个 `actWalkPrevInsertObjectWait` 目标除以 32 均非整数（如 (260,485)→(8.125,15.16)），只作量化候选。

## 重制接线

| 文件 | 内容 |
| --- | --- |
| `content/generated/hsl/chapter01/battle052_seed.json`、`content/generated/hsl/static/hsl01/level052_terrain.json`、`content/imported/hsl/chapter01/battle052/level52.png` | `hsltools/levels/seed.py`（`battle_seed:52`） |
| `content/imported/hsl/chapter01/battle052/source_texts/{STORY052.TXT,winfail052.txt,obj-052.h}` | 原始脚本字节，SHA-256 与 seed 一致 |
| `content/imported/hsl/chapter01/battle052/message_text_evidence.json` | 23 条 message 正文与 6 个说话人标签，与 `RESOURCE.TXT` 逐字节核对 |
| `content/imported/hsl/chapter01/battle052/section_title.png` | `SHAPE01\WORD052.SHP`（惡夢的終曲 / NIGHTMARE FINALE） |
| `content/imported/hsl/chapter01/battle052/opening_timeline.json` | 57 个 token ＋ 合成 `first_control_ready` |
| `content/battles/battle_052.json` | `level_battle:52` 从预览 `story_052.json`＋seed＋`content/battles/levels/052.json` 生成 |

`BattleScenarioRuleAdapter` 把 seed 驱动的关卡交给 `WinfailScenarioRules`；`events.event0.messages` 与 `[58,58]` 跨关交接已接入，`use_shape_wait` 只记录。重制侧回执见 [second_battle_opening](../runtime_observations/second_battle_opening/README.md)。

## 复现

`python3 tools/hsl.py check battle_seed:52 level_source_texts:52 message_text_evidence_check:52 opening_timeline_compile:52 story_scene:52 level_battle:52`

## 边界

- 脚本 token 不证明镜头曲线、延迟单位、行走速度／朝向或消息框布局。
- `actCheckPlayer` 参数 1 的存活极性、`actCheckEnemyNumber` 的比较关系与一次性执行、`actCheckPlayerAttacked` 是否含反击／技能未读。
- `defProcEnemy`／`obj_Story_Level52_Enemy21` 不证明阵营；023／024 的友军映射是 scenario 的明示选择。
- WRD 32×32 与地图尺寸一致，不单独证明原生命中测试、移动消耗或镜头映射。
