# HSL Remake — Current Project State

Checked: 2026-09-27

## 现状

在 Godot 4.x 中完整重制《幻世录》。终点两个，按顺序：**① 全部 127 场战斗像原版一样从标题玩到结局**（规则一致、节奏一致、画面手感经用户实玩认可）；**② 这套引擎能写续集**——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑。现在整章 127 场战斗、剧情／城镇／大地图交接与三个结局都已注册，从标题可走到章末；规则按"原版程序当裁判"逐项对齐（开局盘面全字段对拍、随机流照原版、AI 行动种类 127 关对拍无可确证的规则差异），演出与界面照原版录屏补齐；续集示范 龍脊隘口（LEVEL200）＋两名新角色只靠 `content/authored/` 数据可玩；公开导出只凭文档能从 `hsl bootstrap` 走到自制一关自动打赢。机器人打关不等于玩家可通关，也不等于原版难度；**已合并项待用户实玩验收，验收前不算"已修好"**。旧战斗存档（v4）在新版本拒读。公开仓库 <https://github.com/catoncat/hsl-remake>（公开，三平台 CI 通过）。所有"像原版"的声明都要能追溯到资源、静态分析或原版运行实测（用语见 [CONTEXT](../CONTEXT.md)）。

## 进度尺

| 尺 | 最新值 | 从哪量 |
| --- | --- | --- |
| 和原版还差什么 | 85 条（2026-09-29；以差异清单为准，本格不逐次改） | [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md)（`hsl check parity_inventory`）；汇报"还剩多少"按它 |
| 128 场自动对局 | win 20／fail 108／dead_end 0（2026-09-29）——伤害算法与敌方集火照原版、贪心机器人不躲，属难度不属回归；前瞻驾驭（lookahead）同种子 win 50／fail 76／dead_end 1（2026-09-30），另 1 场亞修頓大橋 · 橋上的決戰（LEVEL044）单次 590 s 内只到第 22 回合、未跑完；是探索驾驭，不是原版平衡证据。单场扫描用初始队伍，不等于走查难度 | `content/generated/hsl/development/autoplay/results.json`（负责人每批合并后重生成）；前瞻归因 `brain_sweep.json` |
| 整章播种走查 | 机器人卡关时强制判胜，一路走到通关（`game_clear=true`，40 场：自然胜 19、强判胜 21；强判胜照原版结算经验，队伍等级随章节正常上升）。唯一的规则异常已修：自覺與宿命・塔克斯（LEVEL075）第 2 试敌方范围施法挑到墙后无人覆盖的中心，被当空单位拒绝（`invalid_experience_exp`），现按原版 0x40c9a0 跳过这种中心；亞修頓大橋 · 橋上的決戰（LEVEL044）的强化攻击力卡死已修，这次是正常负局。最新一次重走只剩两处机器人僵持（曼多力亞 · 對峙（LEVEL900）、菲納斯河畔 · 伏擊（LEVEL901），双方不再接敌），没有规则拒绝。自然负多半是机器人策略弱、每关只试 3 次，不当规则信号 | 实玩包生成日志（`tools/hsl_playtest_kit.py generate --force-win`，不入库） |
| 剧情可达 | explorer 走遍 22 段注册剧情、三个结局都到 GameClear；剧情可通不等于战斗可通 | 深门 `tests/run_story_mode_explorer_tests.gd` |
| 数据字段未消费 | 22／742（2026-09-22） | `hsl check field_coverage` |

逐关流转见[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（生成物）；各系统的原版证据等级见[机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)。

## 在跑

夜间自主编排（09-28）收 76 条 lane；09-29 白天到 09-30 清晨又合并发布约 75 条，差异清单 86→85。09-29 主要落地：多段绝技逐段结算与演出（段数表、逐段收据、同 tick 先后、末击释放）；AI 濒死优先路径、移动施法威胁站位、自移与用药射程照原版；大地图到点分派、行走者来源与 opcode 96；全部地图法术逐受者接力、8 个施法者侧特效对象、效果阶段位统一由切入持有；五轮面板滑入滑出与说明框就地出现、回憶錄列表、獲得物品窗键盘翻页；剧情雨与落水、城镇事件执行模型、战斗持物窗包满卸到手上、开箱接触矩形；实玩回报的三处（飘字冻住、结算窗闪帧、行动中单位发黑）已修；整章走查强判胜照原版给经验，实玩包每条一键直达。09-30 清晨转向终点②：手写配乐与音效、原版表覆盖层、续集战役与第一章并存（登记、选战役、存档分开）、大地图点位 `level` 字段、转职改写表按战役、界面美术手写层；公开检出一条 `hsl bootstrap` 从正版数据包导入全部游戏要读的派生文件，五份只能从原版程序读出的规则数值随仓库发布，示范角色占位图改为生成任务；只凭公开文档在干净导出里从 bootstrap 到自制一关自动胜已实测（狗糧坡（LEVEL201），不入库），暴露的 11 条摩擦已修回文档与工具。仍待实玩核对：以上凡标「未实玩」的可见变化，尤其施法阴影分层、面板滑动、法术受者条与逐人序列、遮挡顺序、多段绝技特写变长、37 关白光、22／36 关瀑布与海面。

<a id="next-steps"></a>

## 排队

1. 人工通关验收（含新做的状态页按钮排：上一位／下一位／道具／狀態／魔法／特殊技，与装备说明框悬停显示）：从标题打到 玩家第 3 场 · 逃出克萊恩城（LEVEL053）以后，按 [PLAYTEST](PLAYTEST.md) 格式回报，按类修。
2. 公开检出剩余：`hsl bootstrap` 后仍缺 130 个只作证据的文件（原版帧、探针记录，留私有档案），3 个字库文件随仓库文本变化而与清单不同；都不影响游戏。

## 待拍板

- **用户**：上面"已合并待实玩验收"的各项，按 [PLAYTEST](PLAYTEST.md) 的格式回报。
- **负责人**：TOOLS 审计的 L7（研究工具挪 `tools/research/`）与 L8（删旧命令台账）；`hsl check --profile` 分层提议。

## 文档地图

- [README](../README.md) — 项目首页
- [docs/README](README.md) — 全部文档索引
- [MODDING](MODDING.md)、[MODDING_LEVELS](MODDING_LEVELS.md) — 改游戏
- [CONTRIBUTING](../CONTRIBUTING.md)、[ARCHITECTURE](ARCHITECTURE.md)、[AGENTS](../AGENTS.md) — 参与开发
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md)、[MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md)、[BATTLE_NAMES](BATTLE_NAMES.md) — 查表

R1–R8 逐轮流水与合并回执在内部文档 `docs/internal/ROUNDS.md`（不随公开导出）。

<a id="validation"></a>

门禁口径：[CONTRIBUTING §2](../CONTRIBUTING.md) 的表为准，按改动选检查见[测试路由](../tests/README.md)；lane 与合并流程见 [AGENTS](../AGENTS.md)。
