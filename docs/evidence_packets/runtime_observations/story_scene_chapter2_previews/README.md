# 第二章开场预览与过场（13–45、66–72、74）——批量接入回执（runtime-measured）

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/map_objects.py, hsltools/levels/story_scene.py · updated: 2026-09-19

2026-09-19，presentation 线。数据链由三条并行工具子线（ch2a／ch2b／ch2c，P-048（已删，见 Git 历史））按 P-044 协议建成并由本线合并；
运行时接入（注册、静态物件插入／删除读法、扫描回归）由本线完成。窗口化 `tests/capture_story_scene_review.gd -- --level=13|44` 与 headless 套件的实际运行回执。

## 玩家结果

- 大地图按世界状态揭示的第二章点位到达即进开场预览：25 场战斗关（13／15／17／18／19／21／22／24／26／28／29／30／31／32／33／34／36／37／38／39／40／41／43／44／45）
  播放 STORY 开场（cast、对白、走位、镜头、音效、标题），止于卡片；「略過戰鬥（視為勝利）」施加胜利段的城镇／大地图写入并按 `next_level_event` 续播
  （17→67、19→69、29→70、31→71；41→73／38→80 目标未注册时只回图）。8 段过场（66／67／68／69／70／71／72／74）完整播放并交接。
- 条件成员（「(有才產生)」咕嚕／克羅蒂）在预览中不安装：其走位与对白 token 按设计跳过并计入场景的 unresolved_semantics（队伍成员是否在队未建模）。
- STORY018 的門1（EVEF static_enemy_object）被 actDeleteObject 隐藏、obj_Story_Level_Door（无步行帧的敌方物件）以静态精灵插入——两条读法由本线加入协调器与地图物件工具。

## 帧

1. `01-level13-volcano-1783.png`：龍之息 火山（level 13，shape11 地图）——七人队立于岩浆前，雷歐納德 1783（对白板因队伍在底部改用顶部槽位）。
2. `02-level44-bridge-framed.png`：亞修頓大橋（level 44）——75 名沃斯菲塔军（023／024／027／030／031／044／045／032）列阵桥上。
3. `03-level44-card.png`：两行结束卡（胜利行回图）。

## 自动验证

- `STORY_SCENE_TESTS_PASS`：`_run_registered_story_sweep` 遍历全部注册 story 场景（55 个主范围场景＋900／901）——启动、跑完、交接或卡片；
  跳过 token 仅允许条件成员的走位／对白与原作 -1 物件号（STORY013 `actWalkDispWait(-1,…)`，语义未定位）。
- 全部 55 关 `python3 tools/hsl.py check story_scene`、`python3 tools/hsl.py check level_map_objects`、`STORY_CORPUS_CHECK_PASS`（57 个 evidence 文件）、单测 521 OK。
- 窗口化 `STORY_SCENE_REVIEW_PASS` level 13 shots=14、level 44 shots=6。

## 证据等级与边界

- 地图：自有 shape 者 resource-derived；66–70→55、71→58、32↔33 互指——以 obs 地圖管理員 记录为主证据（resource-derived），引擎 loader 未定位（provisional 尾注）。
- 配乐：按 `0x477b44` 的 track 号复用既有重制曲；track 10／11 等无重制曲的槽位以既有曲 stand-in（各场景 unresolved 注明）。
- 说话人标签：敌方 SID 沿用既有 remake 标签（provisional）；PLAYERS 名字段可解者 resource-derived。
- 战斗本体、条件成员的在队判定、-1 物件号语义、level 39 等的 shapeless 物件均未重制。
