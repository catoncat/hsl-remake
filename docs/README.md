# 文档索引

根目录 [README](../README.md) 是项目首页；当前进度与 1.0 的条件在 [PROJECT](PROJECT.md)。

## 玩与试玩

- [玩家指南](PLAYING.md) — 操作键、存档位置与格数、三个预设、已知的坑
- [PLAYTEST](PLAYTEST.md) — 跳到某一关试玩、回报问题的格式
- [WEB](WEB.md) — 浏览器版：构建、按需分包、私有发布与网页平台的坑
- [OPTIONS](OPTIONS.md) — 「重製選項」各项、默认值与注册表字段
- [BATTLE_NAMES](BATTLE_NAMES.md) — 战斗称呼对照：玩家第几场、场景名、文件号
- [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md) — 与原版的已知差异，逐条登记（生成物）
- [CHANGELOG](../CHANGELOG.md) — 按日期记录每次发布改了什么

## 改游戏

- [MODDING](MODDING.md) — 四层结构、换素材、改规则、去掉原版依赖、现在做不到什么
- [MODDING_LEVELS](MODDING_LEVELS.md) — 加关卡、角色、职业、招式，改剧情流转、换配乐，写续集
- [原作剧情简报](ORIGINAL_STORY.md) — 世界、势力、人物、主线与三个结局，以及原作提到却没有展开的地方；写外传和续集的故事先读
- [原作人物名录](ORIGINAL_CAST.md) — 有名字的反派、友军和九名队员：身份、出场、三个结局里的下场、战斗数值，以及尾聲之后留下的线
- [原作关卡](ORIGINAL_LEVELS.md) — 127 场战斗怎么出题：胜负条件、增援、事件、地图，以及自制地图和关卡现在能做到哪一步
- [规则数值手册](NUMBERS.md) — 伤害、命中、经验、调级公式，几下打死的参考表，原作等级曲线，手写数据能设到哪一步
- [战棋设计方法](SRPG_DESIGN.md) — 人物组合、数值与关卡的方法和出处，末节对到本作的规则
- [WINFAIL_TOKENS](WINFAIL_TOKENS.md) — 胜负脚本词表（生成物）
- [战役总览](evidence_packets/resource_inventory/campaign_overview.md) — 逐关流转（生成物）

## 代码

- [CONTRIBUTING](../CONTRIBUTING.md) — 准备正版、门禁、不提交原版派生物、PR
- [ARCHITECTURE](ARCHITECTURE.md) — 代码分层、状态所有者、术语
- [Battle systems](architecture/BATTLE_SYSTEMS.md) — 行动、背包与装备、成长、技能与状态、AI
- [Presentation](architecture/PRESENTATION.md) — 开场、菜单与面板、移动、交锋、地图收尾
- [PROVENANCE](PROVENANCE.md) — 每个模块的来源等级，remake-invented 与 provisional 清单（生成物）
- [测试路由](../tests/README.md)、[工具说明](../tools/README.md) — 每个套件与脚本守什么、怎么跑
- [AGENTS](../AGENTS.md) — 代理的工作手册
- [CONTEXT](../CONTEXT.md) — 项目术语与写结论的规矩
- [NOTICE](../NOTICE.md) — 合规说明

## 原版研究

- [METHOD](METHOD.md) — 怎么拿原版程序核对：裁判、证据分级、差异清单
- [证据包首页](evidence_packets/README.md) — 怎么读证据包
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md) — 证据包索引（生成物）
- [MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md) — 每个机制的证据等级与未恢复边界
- [核心规则证据](first_battle_core_logic_evidence.md) — 核心公式与地址的静态结论

`docs/internal/` 与 `docs/audits/` 是过程文档，不随公开导出，公开文档不得链接它们。
