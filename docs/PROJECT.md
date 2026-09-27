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

夜间自主编排（09-28 00:00–07:30）已收：74 条 lane 合并发布，每条一个原版证据读法加对应改动，差异清单 107→93 条，原版状态表 144 项里 132 项照原版、11 项自定、0 项缺、1 项未核。主要落地：战斗内道具／交換／裝備／丟棄四窗与身份板按原版帧排布；施法引导、特写收尾、绝技对象命令程序（221 对象）与法术效果对象（144／144）全部按原版程序演；剧情走位寻路链、停点提交、跟随者复制路径、换形节拍照原版；AI 追击洪泛与无普攻单位回合规则照原版，盯谁比例经 200 种子核为一致；技能与被动已无重制拒绝项，8 件被拒装备全部可装；安装链随机数顺序与出生张延迟抽数与原版同步；城镇选择窗、菜单悬停、商店音效、标题菜单滑入与火花照原版。门禁加固：直跑测试脚本默认同一随机种子、场景脚本改动必跑 presentation contract 套件、affected 模式对新资产先导入。晨间待办：深门重跑 128 场自动对局核胜负（出生张延迟改变了全局随机流）；实玩核对巴瀚納海峽（LEVEL012）城墙弓兵、牧师高跳特写、标题滑入、城镇选择窗；剩余差异清单 L 级四条（职业模型、胜负脚本读法、通关谢幕版式、阵营覆盖原生观察）。

<a id="next-steps"></a>

## 排队

1. 人工通关验收（含新做的状态页按钮排：上一位／下一位／道具／狀態／魔法／特殊技，与装备说明框悬停显示）：从标题打到 玩家第 3 场 · 逃出克萊恩城（LEVEL053）以后，按 [PLAYTEST](PLAYTEST.md) 格式回报，按类修。
2. 开源剩余：137 个不可再生文件（原版证据帧 104 张迁私有档案等）。

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
