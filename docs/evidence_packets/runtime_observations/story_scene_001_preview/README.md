# 剧情场景与开场预览：story 模式播放、过场链与略過戰鬥的世界写入

> evidence: runtime-measured; resource-derived: STORY／WINFAIL token、EVEF 坐标、地图管理员记录、对白号; provisional: 走位速度、延时、镜头、地图别名的引擎 loader · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-27

## 结论

- 原版每关 STORY 脚本按 token 顺序播放开场或整段过场，story-only 关（无 WINFAIL）播完由 `actSetNextPlayLevelEvent` 交接；token 顺序、cast、对白号与世界写入可从资源读出，走位速度、延时与镜头曲线未读（resource-derived；provisional）。
- 重制把 `level_kind: story` 场景交给 `BattleOpeningCoordinator` 的 story 模式（不建 PlayLoop），全部注册 story 场景由 `run_story_scene_tests.gd` 的注册扫描逐个播完，除条件成员（「有才產生」咕嚕／克羅蒂）与 -1 物件号外零跳过 token（runtime-measured）。
- 与原版的差异：走位、跟随偏移、删除时机、效果粒子与混色为重制取值；差异清单 `script-walk-path`（provisional）。

## 证据

### resource-derived

| 项 | 读数 |
| --- | --- |
| EVEF 放置坐标 | 按有符号 32 位读（`0xFFFFFFC0` = −64）；地图外候场的 cast 从负坐标或越界处走入（STORY002／003／005／007／009 的开场） |
| 命名玩家 token | `SID_雷歐納德`／`SID_琥` 等经 `player_installs` 绑定到 001／003…，不是 `SID_PLAYERn`；`obj_Story_Player1..4` 由 `actInsertStoryObject` 安装（STORY006、053） |
| 地图别名（`obs` 地圖管理員记录为主证据，`.wrd` 逐字节相同为旁证） | 60→58、61／62／64→55、63→58、66–70→55、71→58、32↔33、73→41、75→57、76–79／81／82→58、901→8；无自有 shape 的 story 关（60、61–64、66–71）WRD 为同一张 1224 字节占位表 |
| 标题图 | WORD901.SHP 实为「狙兵／SNIPER」，卡片标题「菲納斯河畔　伏擊」是重制标签 |
| 脚本人脸 | STORY063 `actShapeMessage,SHAPE\FACE0054|FACE0008.SHP,306,<id>`：脚本自带人脸与名字资源 306（「???」） |
| 拼写 | STORY009 的 `actMEssage` 按大小写不敏感归一为对白 token |
| 船殼 | 巴瀚納海峽 62 个 Enemy101（`SHAPE11\18_DOOR01.SHP`）在原作是 defProcEnemy 进程；预览只画作站立物件 |

### resource-derived：过场链与世界写入

| 起点 | 交接 | 写入 |
| --- | --- | --- |
| STORY008（菲納斯河畔） | `[8,gameBigMapLevel]` | 点 9 → bmpmBattle；点 8 → bmpmVisit；点 8 遭遇率 0 |
| STORY009（廢都） | `[9,65]` | 点 9 → event 0／bmpmTown |
| STORY065（廢都室内） | `[9,66]` | — |
| STORY058 → 060 → 53 | `[60,60]`、`[53,53]` | — |
| 59／79／82 | `[90,998]` → GameClear | STORYOVER 由 `defProcClearBOSS` 加载，见 [original_game_clear_epilogue](../../static_reverse/original_game_clear_epilogue.md) |
| 57 | `actSetNextPlayLevelGetOverEvent 0` → 76／77／78 | 见 [original_ending_dispatch](../../static_reverse/original_ending_dispatch.md) |
| 略過戰鬥（WINFAIL 胜利段） | 2→55→56→点 2；3→61；6→62→63；7→64；17→67；19→69；29→70；31→71；41→73；38→80 | 2：点 2 event 501／Visit、遭遇率 20、路线 3 隐藏；5：点 5 event 507、遭遇率 100、席達鎮 exec 19、路线 6／15 隐藏；10：点 10 event 513；12：揭示点 13；901：点 8 event 516／Visit、遭遇率 20，席達鎮删 酒館 20／護甲店 17、加 護甲店二 45、酒館 20 → [26,27]、exec 25 |

### runtime-measured

`tools/play.sh --script res://tests/capture_story_scene_review.gd -- --level=N` 窗口化运行：

| 场景 | 读数 |
| --- | --- |
| 1 歐姆村 | 18 名 cast、81 token 零跳过、30 对白 token／29 个消息；32 个站立物件＋26 组组合物件的 55 个子物件；镜头中心保持在 [320,960]×[240,880]（`01-village-framed`…`06-not-remade-card`） |
| 2／3／5／6／7 | 32／31／31／51／45 事件零跳过；镜头被夹在地图边缘时对白框改用顶部槽位 |
| 8／9／65 | 完整过场；上表世界写入落入 hand-off 世界状态 |
| 10 帕尼西亞城 廢墟 | 89 事件；效果读法计数 `rain_emitter 2／background_sound 1／flash 2／frame_once 4／glow 2／frame_loop 5`，读法在 `StoryEffectObjects.gd`，由物件字段驱动 |
| 12 巴瀚納海峽 | 39 名 actor；62 个船殼作站立物件，不生成 actor |
| 53 | 受控緹娜同格换身、攀绳 6 帧与 288 px 像素滑动、4 格逃出区标记 |
| 58／60 | 无 PlayLoop 启动；12／15 名 cast；53／43 事件；18／20 个对白 token |
| 73／900 | `actSelectInsertEvent` 以选项按钮呈现，所选 winfail 事件链拼入时间线 |
| 注册扫描 | `STORY_SCENE_TESTS_PASS`：campaign.json 每个 story 场景启动、播完、交接或卡片 |

## 重制接线

- `tools/hsltools/levels/story_scene.py`（`python3 tools/hsl.py generate story_scene:N`）生成 `content/battles/story_NNN.json`；首个 win 段取作 `skip_battle`。
- `game/battle/runtime/BattleOpeningCoordinator.gd`（story 模式）、`game/battle/runtime/StoryEffectObjects.gd`、`game/battle/scene/BattleSceneStage.gd` `_start_background_sounds`。
- 世界写入：`game/world/WorldScriptActions.gd`、`game/sim/TownEventRules.gd` `apply_script_town_actions`；结局分派 `game/sim/EndingDispatchRules.gd`。

## 复现

`tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_story_scene_tests.gd`

## 边界

- 走位速度（160 px/s）、跟随偏移、`actWalkAndDelete` 删除时机、淡黑 0.8 s、雨密度、闪电／光环淡出、火球帧时长均为重制取值（provisional）。
- 地图别名的引擎 level→map loader 未定位；`SID_ENEMY023,8` 这类实例查找按「第 N 名插入者」绑定（provisional）。
- 条件成员在队判定、-1 物件号（STORY013 `actWalkDispWait(-1,…)`）语义未读。
- 「視為勝利」只施加胜利段的城镇／大地图写入，不施加对白、走位、入队与战斗奖励。
- 敌方 SID 的说话人标签（一般兵／重裝兵）沿用重制标签。
