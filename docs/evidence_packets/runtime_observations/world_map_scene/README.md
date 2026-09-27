# 大地圖（世界地图）场景 — runtime-measured

> evidence: runtime-measured · status: live · tools: capture_world_map_review.gd, hsltools/data/world_map.py, run_world_map_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_world_map_review.gd --resolution 640x480 --screen 0`（`WORLD_MAP_REVIEW_PASS shots=7`，正常重制节奏；headless 回归为 `tests/run_world_map_tests.gd`）。场景文件 `content/world/world_map_scene.json`（`level_kind: world_map`），数据为 `tools/hsltools/data/world_map.py` 解码的 `content/imported/hsl/global/world_map/`（[结构与未解语义](../../static_reverse/world_map_data.md)）。campaign 从 level 1 歐姆村开场预览的「尚未重製」卡确认后进入本场景（`campaign.json` 的 `world_map` 项）。

## 看到什么

采样按 SR-069 原指令合同（[原世界／城镇合同](../../static_reverse/original_world_town.md)）对齐后的场景（`WORLD_MAP_REVIEW_PASS shots=7`）；03／04 两帧为对齐前的早期采样，只留作对照。

0. `00-ohm-village-track-revealing.png`：新游戏只显示歐姆村（bigmap 文件 mode 2），17 个点与 18 条线按原新游戏代码（0x42c86e）带 Hidden；站在歐姆村时它的非 Hidden 路线 bmTrack01 进入揭示阶段（mode 1）——重制以裁剪矩形沿路线长轴展开（0.6 s 重制节奏；原为逐逻辑 tick 展开，无红白插值），底部 STATUS_BAR.SHP 状态栏（camera+(0,412)）显示「完成度： 2%」（1 个已显示点 / 44）与累计游玩时间 h:mm:ss。
1. `01-ohm-village-start.png`：揭示完成后 bmTrack01 转 mode 2、端点戈爾山道以 mode 2 出现（完成度 4%）；点标记按 POINT.H 三帧 M_PNT001＝Battle／002＝General／003＝Town；只给当前点与可达点标名；队伍标记（Leonard 走路帧，半尺寸）站在 (910,527)。
2. `02-travelling-track-1.png`：点击戈爾山道（命中框 ±16）后队伍沿 TRACK.TXT 折线行走，镜头跟随。
3. `03-arrived-gorl-pass.png`：（对齐前采样）到达戈爾山道后的地图；现在到达先按到达前旗标判分支，再标 Visit、揭示该点的非 Hidden 路线（bmTrack02／03 → 盜賊洞窟、米蘭多出现）。
4. `04-ohm-village-town-card.png`：（对齐前采样）城镇卡；现在有 TOWNDEF 数据的城镇点直接开菜单式城镇画面（见[城镇回执](../town_scene/README.md)），城镇卡只留给没有数据的城镇点。
5. `05-gorl-pass-level-2-card.png`：到达戈爾山道（General、未 Visit）按原到达 handler 开其点事件 level 2（bigmap 文件 +8 初值＝点号，SR-069）；level 2 未注册，弹「level 2 · 戈爾山道　此地的關卡尚未重製」卡，空格关闭留在原地。到达分支：event 0 无动作；General 未访→event、已访→先过 encounter ratio（1..100 抽样 ≤ ratio，重制读法）再 event+0..2；Battle→event、已访 +0..2；Town 仅作为选定目的点入城，无数据则停。

## 断言（headless）

45 点／44 线／18 条初始隐藏路线／17 个新游戏隐藏点；只有歐姆村初始显示、路线揭示前不可达、揭示中即可达、揭示完成显示端点、完成度 2%→4%；歐姆村只连戈爾山道；不可达与空点击不移动；旅行记录 track 1、4 顶点；到达后 visited [1,2]、Visit 位与位置落盘；到达表（未访 General／Battle 开 event、无数据城镇停、非目的城镇路过、已访 General 抽样 10≤20 开 501+1、21／100 停、ratio 0 停、event 0 无动作、已访 Battle 5+2、STORY008／009 形态的点事件把城镇点 9 变战斗 9 再变回城镇）；`(town_*, gameBigMapLevel)` 城镇事件只把队伍挪到该点并落盘；`WorldScriptActions.place_party` 首次返回大地图时种状态并站到指定点；点事件 52 → 带 `world`（current_point 2）与 carry（gold 275）的 hand-off 进入 `second_battle.json`；未注册关卡留在原地并显示「尚未重製」卡；携带状态的隐藏路线覆盖去掉路线与邻点，无效世界状态回退到场景起点。

## 边界

- 已按 SR-069 静态合同对齐的项：点／线三字段（mode／bmpm 位／+8 event）、新游戏隐藏点线、到达分支、点事件类型替换、M_PNT 三帧、命中框 ±16、状态栏内容、track 6 配乐槽位。仍为重制值：旅行速度 96 px/s（原为 16.16 速度 2／tick，tick 频率未测）、揭示动画时长、**路线何时进入揭示阶段**（本重制：进图与到达时揭示当前点的非 Hidden 路线，原触发点未定位）、遭遇抽样的比较方向、Leonard 贴图作队伍标记、原创曲《瓦盧西恩大地》。状态栏画法与文字排版已按原版帧对齐（[original_world_town](../original_world_town/README.md) 帧 01／03／04：STATUS_BAR.SHP 从底图里减去而不是盖住它——帧 04 的底图与 BigMap.SHP 在镜头 (640,480) 逐点吻合（平均差 2.2），拟合 dst − 1.04×src、RMS 3.3，重制用整张减法混合；文字为原颜色码 @5 黄「完成度：」自 x 6、数字自 x 114，@1 白时间右对齐 x 634，各带 (+1,+1) 阴影（0x476b44 表），字行 y 427–444）；BigMap.SHP 自带的 1 像素黑色网格线与原版一样在屏幕上可见。
- level 1 战斗未重制，其 winfail001 胜利动作（`actSetTownExecEvent,town_歐姆村,9`、消息 736–738）在从预览进入大地图时**未施加**——机制已就位（战斗 hand-off 经 `WorldScriptActions` 施加脚本记录的城镇／大地图动作，见 world_map／campaign tests），随 level 1 战斗接入即自动生效。
- 点 16 命運的神殿在 bigmap.dat 无任何路线相连，进入方式未解。
