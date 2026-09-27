# 戈爾山道（level 2）重制运行回执：两阶段战斗、事件入队与营地承接

> evidence: runtime-measured; provisional: 整事件原子提交、出生随机流与入队调度的组合 · status: live · tools: run_gol_road_tests.gd · updated: 2026-09-27

## 结论

- 原版 WINFAIL002 在事件条件满足后安装緹娜（Player2）与四名追兵、旧强盗离场、进入第二阶段；安装分派、启用槽、缺省字段与坐标前段见 [original_player_install](../../static_reverse/original_player_install.md)（static-derived）。
- 重制 `content/battles/gol_road_battle.json` 从大地图点 2 进入，初始只有琥、雷歐納德与五名强盗，事件后整批安装提交到唯一 PlayLoop；四条窗口路线（自然胜利、事件到达、緹娜被捕、营地承接）实际跑通（runtime-measured）。
- 差异：整事件原子提交、玩家先建／NPC 取队伍平均、合法格调整、独立出生随机流、新角色加入既有下一轮队列是重制组合，不声称原版全局随机序列或调度相同（provisional）。

## 证据

### runtime-measured：四条路线（[receipt.json](receipt.json)）

| 路线 | 起点与输入 | 实际结果 |
| --- | --- | --- |
| `natural` | 未改正式编队，从原开场开始；真实菜单、移动、射击、毒魔箭、物品、加点、等待及 F5／F9；不替换战斗随机源 | 196.923 s，第 10 回合胜利；源事件安装緹娜与四名 023 各一次，三次保存／读回；緹娜以安全走位存活，未使用治疗 |
| `arrival` | 前置夹具：三名先前强盗阵亡、下一目标 1 HP、受伤 Leonard、较快且装备白光之翼的琥；待生追兵 `no_attack`，只隔离支援／队列验收 | 真实弓击触发入队／追兵对白与走位，五次安装按 token 揭示；领取结束后才得独立第二行动；新队员实际用治癒之水，扣 6 MP、增患者 HP 并发真实贡献 EXP；三次 F5／F9 不重生或重抽 |
| `defeat_tina` | 事件已播完的夹具（游标与对白记录一起保存）；緹娜 1 HP、相邻追兵加源攻击／速度与命中补偿、琥先动 | 玩家等待后 AI 击倒緹娜，触发 `fail_2`，结果「緹娜 被捕」，终态不再生成；F9 后按重开按钮回第一阶段七人、无旧緹娜 |
| `campaign` | 新进程 F9 读 `natural` 的胜利存档，不手造胜利 | 快照精确恢复；结果页按钮进 55 → 56 → 大地图，三名受控角色的装备／库存／已分配点／永久与学习记录、钱包和生成游标经 JSON 持久化保持，地图停在点 2 |

两个进程均 exit 0、无 Godot 错误或退出资源泄漏：第一个只跑 `natural`（14,485 项逐帧／事务检查），第二个跑其余三条（75.075 s，4,699 项）；覆盖以四条路线与收据为准，逐帧检查数不是覆盖率。原关没有玩家逃出区，重制不添加撤离胜利。

| 帧 | 内容 |
| --- | --- |
| [natural-first-control](natural-first-control.png) | 正式七人场景首次控制 |
| [natural-install-1](natural-install-1.png)／[natural-install-5](natural-install-5.png) | 源 Player2 安装 token 才揭示緹娜；四名追兵依次出现 |
| [natural-arrow-impact-1](natural-arrow-impact-1.png) | 毒魔箭命中 |
| [arrival-experience-2](arrival-experience-2.png) | 新队员治疗后的真实经验 |
| [natural-result](natural-result.png) | 两阶段胜利与营地按钮 |
| [defeat_tina-result](defeat_tina-result.png)／[defeat_tina-restarted](defeat_tina-restarted.png) | 事件后新增的败北条件；重开回第一阶段 |
| [campaign-stage-story_055](campaign-stage-story_055.png)／[campaign-stage-story_056](campaign-stage-story_056.png)／[campaign-carried-party](campaign-carried-party.png) | 黄昏营地、清晨营地、回到戈爾山道点位 |

11 帧均按原始 640×480 检查：现有角色在事件前维持旧位置、新角色在对应安装 token 前不显示、交锋／领取／消息结束后才交接菜单。音效记录来自播放中的源音频流，不测量混音、墙钟或扬声器输出。

## 重制接线

- 场景 `content/battles/gol_road_battle.json`（`python3 tools/hsl.py check gol_road_data`：正式七人编队、两个待安装源模板与 WINFAIL002 两阶段）；开发入口 `game/battle/development/GolRoad.tscn`；独立 `story_002` 开场预览回归保留。
- 安装走 `ScriptActorCreationRules` 的整批事务提交到唯一 PlayLoop；现有角色的永久／装备／临时状态／学习层沿共享事务，不把安装当作重复成长。
- `tests/run_gol_road_tests.gd` 62 项：初始与事件角色分离、整批失败回滚、重复安装不补满、合法落点、真实击杀后生成、新队员费用／禁魔／麻痺拒绝、多级成长、白光之翼与领取边界、出生与脚本动作篡改拒绝、静止游标 F9 与终态。

## 复现

`tools/godot.sh --headless --script res://tests/run_gol_road_tests.gd`；四条窗口路线的驱动已退役，回执为历史记录。

## 边界

- 原函数前段不证明完整对象分配器或整个 VM；调度与随机流组合是重制选择（provisional）。
- 条件成员跨全部剧情的在队状态、复活／离队再加入、宝箱开启与拾取不在本回执范围。
- `arrival`／`defeat_tina` 是明示夹具，不是自然打法。
