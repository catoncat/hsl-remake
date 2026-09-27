# 文档索引

根目录 [README](../README.md) 是项目首页；当前进度与排队事项在 [PROJECT](PROJECT.md)。

## 玩与试玩

- [PLAYTEST](PLAYTEST.md) — 跳到某一关试玩、回报问题的格式
- [OPTIONS](OPTIONS.md) — 「重製選項」各项、默认值与注册表字段
- [BATTLE_NAMES](BATTLE_NAMES.md) — 战斗称呼对照：玩家第几场、场景名、文件号
- [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md) — 与原版的已知差异，逐条登记（生成物）

## 改游戏

- [MODDING](MODDING.md) — 四层结构、换素材、改规则、去掉原版依赖、现在做不到什么
- [MODDING_LEVELS](MODDING_LEVELS.md) — 加关卡、角色、职业、招式，改剧情流转、换配乐，写续集
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
- [CONTEXT](../CONTEXT.md) — 证据用语的定义
- [NOTICE](../NOTICE.md) — 合规说明

## 原版研究

- [证据包首页](evidence_packets/README.md) — 怎么读证据包
- [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md) — 证据包索引（生成物）
- [MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md) — 每个机制的证据等级与未恢复边界
- [核心规则证据](first_battle_core_logic_evidence.md) — 核心公式与地址的静态结论
- [资源证据](first_battle_static_resource_evidence.md) — 早期第一战资源结论，已被逐关导入链覆盖

`docs/internal/` 与 `docs/audits/` 是过程文档，不随公开导出，公开文档不得链接它们。

## Machine-readable authority

- `content/battles/campaign.json`：战役入口（`start_level "51"` → `content/battles/battle_051.json`，由 `hsl generate level_battle:51` 组装；其余各场同一条数据链）。`content/battles/first_battle.json` 只是名册模板与测试夹具，不是现行场景。
- `content/imported/hsl/`：可复用原版资源、脚本 IR 和 manifest。
- `content/generated/hsl/`：compact generated/static facts。
- `content/authored/`：手写数据（续集关卡与角色、选项注册表等）。
- `docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json`：curated 原作视觉基准。
- `docs/evidence_packets/resource_inventory/resource_manifest.json`：完整资源成员索引，供机器搜索，不建议整文件塞入上下文。

## 写文档的规矩

更新现行合同所在段落，删除或标明被替换的表述；来源、精确参数和验收过程放对应 evidence packet，再从索引链接。避免把相同事务复制到 PROJECT、架构和证据包。旧观测只证明当时版本，不能覆盖后来已接入的行为。

历史用 Git 查；不要恢复旧文件树作为冷启动入口。本地导航可单独运行 `python3 tools/hsl_docs_check.py`（也在完整门禁里）：检查可跟踪 Markdown 的显式链接和锚点、公开文档不链接内部文档，不联网、不把代码示例或历史裸路径当运行时依赖。
