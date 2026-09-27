# HSL Remake — Current Project State

Checked: 2026-09-27

## 现状

在 Godot 4.x 中重制《幻世录》第一章。终点两个，按顺序：**① 第一章 127 场战斗像原版一样从标题玩到章末**（规则一致、节奏一致、画面手感经用户实玩认可）；**② 这套引擎能写续集**——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑。现在整章 127 场战斗、剧情／城镇／大地图交接与三个结局都已注册，从标题可走到章末；规则按"原版程序当裁判"逐项对齐（开局盘面全字段对拍、随机流照原版、AI 行动种类 127 关对拍无可确证的规则差异），演出与界面照原版录屏补齐；续集示范 龍脊隘口（LEVEL200）＋两名新角色只靠 `content/authored/` 数据可玩。机器人打关不等于玩家可通关，也不等于原版难度；**已合并项待用户实玩验收，验收前不算"已修好"**。旧战斗存档（v4）在新版本拒读。公开仓库 <https://github.com/catoncat/hsl-remake>（公开，三平台 CI 通过）。所有"像原版"的声明都要能追溯到资源、静态分析或原版运行实测（用语见 [CONTEXT](../CONTEXT.md)）。

## 进度尺

| 尺 | 最新值 | 从哪量 |
| --- | --- | --- |
| 和原版还差什么 | 107 条（2026-09-27） | [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md)（`hsl check parity_inventory`）；汇报"还剩多少"按它 |
| 128 场自动对局 | win 20／fail 108／dead_end 0（2026-09-26）——伤害算法与敌方集火照原版、贪心机器人不躲，属难度不属回归 | `content/generated/hsl/development/autoplay/results.json`（深门重生成） |
| 整章播种走查 | 卡在 玩家第 3 场 · 逃出克萊恩城（LEVEL053），`game_clear=false` | `content/generated/hsl/development/autoplay/chapter.json` |
| 剧情可达 | explorer 走遍 22 段注册剧情、三个结局都到 GameClear；剧情可通不等于战斗可通 | 深门 `tests/run_story_mode_explorer_tests.gd` |
| 数据字段未消费 | 22／742（2026-09-22） | `hsl check field_coverage` |

逐关流转见[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（生成物）；各系统的原版证据等级见[机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)。

## 在跑

三份审计（`docs/audits/` 的 DOCS／CODE／TOOLS，整理项按审计推荐执行）的整理 lane：文档两条（过程文档进 internal／PROJECT 瘦身／AGENTS 刷新；改游戏文档合并）已合并；砍测试（Godot 套件 96→78、Python 测试 139→74、检查任务分 modder／parity／maintainer 三层）、状态效果目录表（`game/sim/StatusCatalog.gd`）、README 入口重写已合并；拆 4 个超长解释器函数为 token 表、tools/README 按读者重排已合并；规则核心已进 `game/sim/loop/`（共用件 `game/common/`）；技能效果族登记表（`SkillResolutionRules.EFFECTS`）已合并；术语改名＋测试别名统一已合并；三份审计的整理项全部落地。第二批（在跑）：合并重复小工具并把跨文件调用的私有函数改公开（CODE3）；测试按断言再砍一轮已合并（Godot 套件 74→50、Python 74→31）；证据包按逐份处置方案（`docs/audits/EVIDENCE_AUDIT_2026-09-27.md`）分 5 条执行 lane 重写为研究附录：EV4 表现／界面／时序 49 篇、EV3 成长／职业 63 篇、EV2 AI／回合 30 篇已合并，EV1 关卡／剧情／城镇 88 篇已合并，EV5 道具／技能／状态 40 篇＋capture 退役在跑；工具函数合并与私有转公开（Values.gd、read_json、70 个函数去下划线）已合并。

<a id="next-steps"></a>

## 排队

1. 龍脊隘口（LEVEL200）自动对局 3 回合败，而 [MODDING_LEVELS](MODDING_LEVELS.md) 写"机器人 4 回合打赢"——先查是机器人还是数据。
2. 界面小项：状态页页按钮排列、说明框悬停、其他窗口的气力条脉动。
3. AI 分布口径剩两处：`AISupportPlanning.choose` 的 99 号分支；古代神殿遺跡（LEVEL037）的随机落点与行动队列顺序。
4. 开源剩余：137 个不可再生文件（原版证据帧 104 张迁私有档案等）。
5. 审计剩余：CODE 9 条（约 8–9 小时，规则核心移 `game/sim/loop` 改动面最大）、TOOLS 8 条、DOCS 的参考区／研究附录（可选）与入口层重写。

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
