# 寧靜之森（level 7）：正式战斗窗口回执

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, run_battle_sweep_tests.gd, run_campaign_tests.gd, run_level7_runtime_tests.gd, run_script_wait_tests.gd, run_story_mode_walkthrough_tests.gd, test_hsl_level_battle.py · updated: 2026-09-20

记录的是 **Godot 重制版**的实际窗口化运行（`tests/capture_battle_review.gd -- --level=7`，remake pacing），不是原 EXE 现场。WINFAIL007 的回合事件、角色来源和地图／宝藏输入为 resource-derived；画面、镜头时钟、对白分页和强制胜利夹具是 runtime-measured 的重制读法，不能据此声称原版等价。

## 入口

大地图 席達鎮战斗后的路线进入 `content/battles/battle_007.json`。该正式战斗由 level 7 的 opening preview、battle seed、WINFAIL007 脚本和已审核演员模板组装；campaign 注册从 `battle_007.json` 继续到 `story_064.json`。

- 首次控制帧记录 25 名初始单位、4 名受控单位，且交互状态为 `action_menu`。
- 窗口化回放在强制清场前驱动真实队列至第 5／6 回合：第 5 回合由现有 script actor path 安装 6 名 023 士兵和 2 名 024 队長；第 6 回合安装 actor_id 005 的雪拉，并保持 `player_controlled`。
- WINFAIL007 的 1010--1033 以及 380 对白按 coordinator 的 cutscene path 捕获；结果为 `victory_boss`，resolved key 为 `win_0`。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | battle_007 窗口和开场地图 |
| [first-control.png](first-control.png) | 开场后首次控制：25 名单位、4 名受控、`interaction=action_menu` |
| [win-dialogue-1010.png](win-dialogue-1010.png) | 第 5 回合增援对白段开始 |
| [win-dialogue-1015.png](win-dialogue-1015.png) | 第 6 回合雪拉加入对白段 |
| [win-dialogue-1033.png](win-dialogue-1033.png) | WINFAIL007 结果前对白段 |
| [result.png](result.png) | 结果页：`victory_boss`／`win_0` |

[manifest.json](manifest.json) 保存了本次 31 帧捕获的相机位置、motion 标记、首次控制摘要和结果摘要；目录只提升上表 6 帧，其余 1010--1033／380 对白帧留在仓库外的 `ignored/battle-007-review/`，不作为 tracked 证据。自动验证包括 `tests/run_level7_runtime_tests.gd`、`tests/run_battle_sweep_tests.gd`、`tests/run_story_mode_walkthrough_tests.gd`、`tests/run_campaign_tests.gd`、`tests/run_script_wait_tests.gd` 和 `tools/test_hsl_level_battle.py`。

## 边界

- 这是 runtime-measured 的重制版窗口回执；它证明当前产品路径渲染并完成该脚本阶段，不证明原版像素、相机曲线、对白时钟、AI、平衡或原版等价。
- 强制胜利夹具只用于验证脚本事件、结果页和 campaign hand-off，不是实际战斗节奏或玩家策略回执。
- 雪拉中途加入和 actor036_3 的网格量化仍按任务书标为 provisional；capture 不新增原版语义。
