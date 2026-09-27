# Level 53 opening preview（逃出克萊恩城）runtime observation

> evidence: runtime-measured; provisional · status: live · tools: capture_story_scene_review.gd, hsltools/levels/actors.py · updated: 2026-09-18

- 采集日期：2026-09-18；分支 presentation-line；Godot 4.7.2 可见窗口 640×480（`tools/play.sh --screen 0 --script res://tests/capture_story_scene_review.gd -- --level=53`），正常重制节奏，总时长 18.3 s。
- 证据等级：**runtime-measured**（重制版自身行为）；对原作的关系全部 **provisional**。完整原始输出（13 张 PNG＋manifest）留在 `ignored/story-scene-053-review/`；本包提升 8 帧。

## 这是什么、不是什么

level 53 是**战斗关**（`winfail053.txt`：緹娜到达 (960,1120)–(992,1152) 逃出胜利、緹娜死亡失败、第 5／7 回合与 023 数量增援、胜利后 `[1,1]`）。目前只重制了 `STORY053` 开场：`content/battles/story_053.json` 以 story mode（无 PlayLoop）播放 46 事件到 `first_control_marker`，然后显示「戰鬥部分（level 53）尚未重製」卡片并可回到第一战。它**不是**可玩的第三战，也不宣称任何战斗规则。

## 数据链（resource-derived）

- 角色：EVEF 只有 029 緹娜的剧情副本 (640,448) 与门卫 023 (960,1152)；受控緹娜由 `actInsertStoryObject,obj_Story_Player2,640,416`（OBJ-ALL.H code 7 = 玩家槽 2 = SID_PLAYER1 = PLAYERS 29）安装；两名追兵由 `actInsertObject,obj_Story_Level53_Enemy23,1056,768` 从画面右侧插入并走到 (928,768)／(864,736)。
- 攀绳：`actChangeShape,SID_PLAYER1,1,4,SHAPE\002-30001.SHP,6` 的 6 帧由 `tools/hsltools/levels/actors.py` 解码为 `battle053/actor_shape_sets/`（含 SHP 头 draw origin）；`actMoveDispWait,0,288,2` 为无步行循环的像素滑动。
- 繩子 `SHAPE41\53_ROPE001.SHP`（obj-053.h code 25）按 map-object alignment 原点插入 (656,464)；`obj_Story_Block`（701）无 shape，只记录不绘制。
- 对白 698–703（含 defNoOne 叙述 698）、章节标题 WORD053「決意」、死亡消息 694 注册、win/fail/event 状态 token 均按脚本顺序执行，无跳过。

## 观察到的结果（帧）

1. `00-tower-framed`：`actScrollBGToPos,0,0` 读作视口左上角 → 月夜塔楼；`actPlayMusic,8` 复用《沃斯菲塔王座廳》。帧于 2026-09-18 随 level 2 一并重拍：`移動背景01／02`（`LVL03_01/02.SHP`，`mapobjMoveBG`）改画在地图底图之下（`backdrop` 层），月夜只从地图透明区透出，塔墙与左下屋顶不再被天空图盖住；漂移仍未重现。
2. `leaving`：剧情副本 029 说完 699 后 `actWalkAndDeleteWait` 到 (640,416) 消失，同格插入受控緹娜（无缝换身）。
3. `rope-climb`：繩子悬挂、緹娜以攀绳帧下滑 288 px 到 (640,736)；`actRestoreShape` 后恢复行走帧。
4. `dialogue-700`／`guard-enters-it`／`dialogue-702`：叙述「公主逃跑了」、追兵从右侧入场、追兵以 023 肖像说 702。
5. `escape-zone-marked`：四个 `actInsertShowPosObject` 格以原版 obj_Story_Show_Pos 的魔法格外观（黄色脉动填充＋`I_rect31..38` 边框，见[范围格包](../../static_reverse/original_range_cells.md)）标出城门逃出区，镜头滚到 (960,1120)，随后 `actDeleteShowPosObject` 清除。
6. `chapter-end-card`：预览止于首次玩家控制点；无 next_level_event、无战役交接。脚本末尾 `actPlayLevelMusic` 当时由 court 主题切到重制原创曲（2026-09-26 起改放原曲，原创曲已删），卡片期间继续循环。

## 边界（不支持的结论）

- `SID_ENEMY023,1` 绑定到第一名插入追兵而非 EVEF 门卫（原引擎实例查找未知）；`actScrollBGToPos` 的视口语义、`actMoveDispWait` 速度单位（按 2 px/帧 @60 Hz 读）、攀绳帧率均为重制取值。
- `actSetPrevInsertObjectAdjustLevel` 只记录无处理；level 53 战斗本体待 P-016 REQUEST 的热文件协作。
