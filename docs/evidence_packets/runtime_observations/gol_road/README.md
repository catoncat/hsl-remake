# 戈爾山道：两阶段战斗、事件入队与营地承接

> evidence: runtime-measured · status: live · tools: capture_gol_road_review.gd, run_gol_road_tests.gd · updated: 2026-09-19

这里记录实际运行的 **Godot 重制版**，不是原 EXE 的完整现场运行。原安装分派、启用槽、缺省字段与坐标前段见[独立原指令包](../../static_reverse/original_player_install.md)；本包不把重制调度、独立随机流或演出时钟称作原版等价。

## 当前可玩的入口

大地图点 2 现进入 `content/battles/gol_road_battle.json`，不再打开预览卡。也可独立运行同一正式配置：

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 0 res://game/battle/development/GolRoad.tscn
```

本次重新枚举显示器后，内建屏为 0；复跑前应重新确认，不能把编号当永久配置。场景仍用真实地图、源角色／装备／初始库存／技能和原 STORY002 开场；没有给正式角色添加测试能力或提高属性。

初始只有琥、雷歐納德与五名强盗。原事件条件满足后，緹娜的 Player2 安装与四名追兵才提交到唯一 PlayLoop，旧强盗离场，随后执行第二阶段。结果页继续到黄昏营地 55、清晨营地 56，再回大地图点 2。原关没有玩家逃出区；这里不添加一个撤离胜利来凑终态覆盖。

## 完整实际进程

[receipt.json](receipt.json)保存四条唯一路线、最终角色与出生游标摘要、当前动作记录、五次安装及帧哈希。原始完整快照和日志留在 `ignored/gol-road/`、`ignored/gol-road-review/`，不是产品依赖。采纳的两个进程均为 exit 0、无 Godot 错误或退出资源泄漏，执行期间工作区差异均未变化。

| 路线 | 起点与输入 | 实际结果 |
| --- | --- | --- |
| `natural` | 未改正式编队，从原开场开始；真实菜单、移动、射击、毒魔箭、物品、加点、等待及 F5/F9；不替换战斗随机源 | 196.923 秒，第 10 回合胜利；源事件安装緹娜及四名023各一次，三次保存／读回；Tina 此路以安全走位存活，**没有声称她使用了治疗** |
| `arrival` | 明示前置夹具：三名先前强盗阵亡、下一目标1HP、受伤 Leonard、较快且装备白光之翼的 Hu；待生追兵设 `no_attack`，仅隔离支援／队列验收，不修改正式配置 | 真实弓击触发原入队／追兵对白与走位，五次安装按 token 揭示；领取结束后才获得独立第二行动；新队员轮到时实际用治癒之水，扣一次6MP、增加患者HP并发放真实贡献EXP；三次F5/F9不重生或重抽 |
| `defeat_tina` | 明示事件已播完的夹具，游标与对白记录一起保存；Tina1HP、相邻追兵增加源攻击／速度和命中补偿、Hu先动 | 玩家真实等待后，AI击倒Tina，触发当前 `fail_2`；结果显示「緹娜 被捕」，终态不继续生成；F9后按实际重开按钮回第一阶段七人、没有旧Tina |
| `campaign` | 新进程通过实际F9加载 `natural` 的胜利存档；不手造胜利，也不重建人物数值 | 完整快照精确恢复；点真实结果页按钮进入55→56→大地图，三个受控角色、装备／库存／已分配点／永久及学习记录、钱包和生成游标经过JSON持久化保持，地图停在点2 |

第一个进程只跑 `natural`，14,485项逐帧／事务检查；第二个跑其余三条，75.075秒、4,699项检查。重复逐帧检查数不是覆盖率，实际覆盖以四条路线、前置条件和收据为准。第二个进程的三条路线各自独立建场；`campaign` 使用前一个进程留下的原胜利文件。

| 进程 | 原日志 SHA256 |
| --- | --- |
| `ignored/gol-road/render-support-natural.log` | `276efa275b095bd935665eb1bc38f0b454bf7b1ac4f25ebbd4b3d83c594b8f2c` |
| `ignored/gol-road/render-extended-final.log` | `b7a5ee00d86838f8ca8ede947e408bbd561cb777716331a753d3fb327d6eec72` |

复跑真实控件路线（隔离每个进程的 Godot user 目录，不覆盖玩家存档）：

```sh
tools/godot.sh --screen 0 --script res://tests/capture_gol_road_review.gd -- natural
tools/godot.sh --screen 0 --script res://tests/capture_gol_road_review.gd -- arrival defeat_tina campaign
```

第二条的 `campaign` 依赖第一条生成的 `ignored/gol-road-review/natural.save`。两条必须顺序执行；这不是发布到用户目录的测试存档。

## 帧与提交时序

![正式七人场景首次控制](natural-first-control.png)

![源Player2安装token才揭示緹娜](natural-install-1.png)

![四名追兵依次出现](natural-install-5.png)

![实际毒魔箭命中](natural-arrow-impact-1.png)

![新队员治疗后的真实经验](arrival-experience-2.png)

![自然两阶段胜利与营地按钮](natural-result.png)

![事件后新增败北条件](defeat_tina-result.png)

![重开回第一阶段](defeat_tina-restarted.png)

![胜利后黄昏营地三人](campaign-stage-story_055.png)

![同一队伍继续清晨营地](campaign-stage-story_056.png)

![返回戈爾山道点位](campaign-carried-party.png)

11张均按原始640×480检查。记录覆盖了现有角色在事件前维持旧位置、新角色在对应安装token前不显示、交锋／领取／消息结束后才交接菜单、实际经验与败北文案、两张源营地图。音效记录来自实际播放中的源音频流；本包不测量原作混音、墙钟或物理扬声器输出。

## 回归与失败记录

`tests/run_gol_road_tests.gd`有62项规则／渲染边界检查：初始与事件角色分离、整批失败回滚、重复安装已有角色不补满、合法落点、真实击杀后生成、新队员费用／禁魔／麻痺拒绝、多级成长／永久来源、白光之翼与领取边界、出生及脚本动作篡改拒绝、静止游标F9和终态。原始安装包、数据生成和本包帧哈希由Python测试核对。

`run_world_map_tests`验证正式目的地；独立 `story_002` 的原开场／预览回归保留。整章 `run_story_mode_walkthrough_tests`在正式Gol段采用**明示阵亡前置条件**，实际执行入队、追兵与胜利程序后接营地；它不冒称完整战斗实玩。旧 `capture_campaign_chain_review`只在其历史预览段隔离注册，正式链由本包覆盖。

早期错误与修复范围保留在ignored：旧输入策略让Tina带着19MP冲锋阵亡，不能算自然通关；定向夹具在未处理战利品时抢第二行动、带着Hu行动资格强换Tina，产品拒绝正确；败北夹具漏了已播对白记录，补齐后不再重复旧对白；跨场比较补上场景id并把双方转到同一JSON表示，**没有放宽字段、数值或小数检验**；同步渲染测试在音频启动未被混音器处理时立即退出导致泄漏，现等待启动／停止完成；一次整章走查因合并后的66地图尚无导入缓存失败，补导入后重测。失败进程不进入上述两个完整通过进程的统计。

完整仓库门禁为 `tools/verify.sh`，覆盖全部旧玩法／第二三战／世界城镇／故事模式及卫生检查，最终退出与稳定diff回执在本片提交说明及 `ignored/gol-road/verify-close.json`；不能用本页62项或窗口过程替代它。

## 原作等价边界

原函数前段不证明完整对象分配器或整个VM。当前整事件原子提交、玩家先创建／NPC随后取队伍平均、合法格调整、独立出生随机流及新角色参加既有下一轮队列是明示重制组合；不会据此宣称原始全局随机序列或调度顺序相同。现有角色的永久／装备／临时状态／学习层沿已有共享事务，不把安装当作重复成长。条件成员跨全部剧情的在队状态、复活／离队再加入、宝箱打开／拾取、其他未实现技能仍为后续独立机制。
