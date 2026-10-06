# 文档索引

根目录 [README](../README.md) 是项目首页；当前进度与 1.0 的条件在 [PROJECT](PROJECT.md)。

## 玩与试玩

- [玩家指南](PLAYING.md) — 操作键、存档位置与格数、三个预设、已知的坑
- [PLAYTEST](PLAYTEST.md) — 跳到某一关试玩、回报问题的格式
- [WEB](WEB.md) — 浏览器版：构建、按需分包、私有发布与网页平台的坑
- [OPTIONS](OPTIONS.md) — 「重製選項」各项、默认值与注册表字段
- [BATTLE_NAMES](BATTLE_NAMES.md) — 战斗称呼对照：玩家第几场、场景名、文件号；提到某一场战斗时照它写
- [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md) — 与原版的已知差异，逐条登记（生成物）
- [CHANGELOG](../CHANGELOG.md) — 按日期记录每次发布改了什么

## 改游戏

- [MODDING](MODDING.md) — 四层结构、换素材、改规则、去掉原版依赖、现在做不到什么
- [MODDING_LEVELS](MODDING_LEVELS.md) — 加关卡、角色、职业、招式，改剧情流转、换配乐，写续集：文件位置、生成命令、改代码入口、验证步骤
- [原作剧情简报](ORIGINAL_STORY.md) — 世界、势力、人物、主线与三个结局，以及原作提到却没有展开的地方；写外传和续集的故事先读。逐句台词全本是内部文档 `docs/internal/ORIGINAL_SCRIPT.md`，不必再从导入件抽取
- [原作人物名录](ORIGINAL_CAST.md) — 有名字的反派、友军和九名队员：身份、出场、三个结局里的下场、战斗数值，以及尾聲之后留下的线
- [原作关卡](ORIGINAL_LEVELS.md) — 127 场战斗怎么出题：胜负条件、增援、事件、地图，以及自制地图和关卡现在能做到哪一步
- [原作关卡的设计](ORIGINAL_LEVEL_DESIGN.md) — 49 场剧情战逐场拆解：每场让玩家做什么决定、棋盘怎么摆、节奏与时钟、几条打法；前面是归纳出的十六种手法和设计新战斗时的用法
- [原作的队伍](ORIGINAL_PARTY.md) — 九名队员在打法里各担什么、什么时候归队、人数一变题怎么变、新人入队怎么演
- [规则数值手册](NUMBERS.md) — 伤害、命中、经验、调级公式，几下打死的参考表，原作等级曲线，手写数据能设到哪一步
- [战棋设计方法](SRPG_DESIGN.md) — 人物组合、数值与关卡的方法和出处，末节「落到我们的规则」对到本作；设计续集的人物、数值与关卡直接读这几份，不重做调查
- 关卡参考素材库 — `tools/hsl_level_atlas.py` 写到主检出的 `ignored/level-atlas/`：逐关整图、开局布阵、标注、说明与原始脚本（原版派生物，不进 Git）
- [WINFAIL_TOKENS](WINFAIL_TOKENS.md) — 胜负脚本词表（生成物）
- [战役总览](evidence_packets/resource_inventory/campaign_overview.md) — 逐关流转（生成物）

## 代码

- [CONTRIBUTING](../CONTRIBUTING.md) — 准备正版、门禁、不提交原版派生物、PR
- [ARCHITECTURE](ARCHITECTURE.md) — 代码分层、状态所有者、术语；改 `game/`、场景或测试先查它的任务路由，再只读命中的下面两份的章节
- [Battle systems](architecture/BATTLE_SYSTEMS.md) — 行动、背包与装备、成长、技能与状态、AI
- [Presentation](architecture/PRESENTATION.md) — 开场、菜单与面板、移动、交锋、地图收尾
- [PROVENANCE](PROVENANCE.md) — 每个模块的来源等级，remake-invented 与 provisional 清单（生成物）
- [测试路由](../tests/README.md)、[工具说明](../tools/README.md) — 每个套件与脚本守什么、怎么跑；选定向检查从这里查
- [AGENTS](../AGENTS.md) — 代理干活的规矩
- [NOTICE](../NOTICE.md) — 合规说明

## 原版研究

- [METHOD](METHOD.md) — 怎么拿原版程序核对：裁判、证据分级、差异清单
- [证据包首页](evidence_packets/README.md) — 怎么读证据包
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md) — 证据包索引（生成物）；查资源、静态分析或原作对照先从这里定位证据包
- [MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md) — 每个机制的证据等级与未恢复边界；改机制状态或等价声明前连同差异清单一起读
- [核心规则证据](first_battle_core_logic_evidence.md) — 核心公式与地址的静态结论
- [原版录像参考](evidence_packets/runtime_observations/original_gameplay_reference/README.md) — 视觉、交互对照按主题看原帧；代码入口查 ARCHITECTURE 的任务路由
- [TypeSafe 用法](../tools/README.md#typesafe-判断分担与全-exe-函数目录) — 开新机制找原函数、筛长文档、自检证据用语（要联网和 key；模型判断只是路由候选，不是证据）

`docs/internal/` 与 `docs/audits/` 是过程文档，不随公开导出，公开文档不得链接它们。
