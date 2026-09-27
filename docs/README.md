# Documentation Map

Checked: 2026-09-27

先按你要做的事选一条路径；不需要通读全部资料。根目录 [README](../README.md) 是第一页，现状与下一步只看 [PROJECT](PROJECT.md)。

## 玩

| 需要 | 读 |
| --- | --- |
| 装好就玩、操作键位 | [README「怎么跑」](../README.md) |
| 跳到某一关、按固定格式报问题 | [PLAYTEST](PLAYTEST.md) |
| 「重製選項」各项是什么（默认照原版） | [OPTIONS](OPTIONS.md) |
| 现在能玩到哪、和原版还差什么 | [PROJECT](PROJECT.md)、[差异清单](evidence_packets/static_reverse/parity_gap_inventory.md) |

## 改游戏

按顺序读：MODDING → MODDING_LEVELS → WINFAIL_TOKENS（参考区）→ OPTIONS → ARCHITECTURE。

| 需要 | 读 |
| --- | --- |
| 总入口：四层结构、换素材、改规则、去掉原版依赖、现在做不到什么 | [MODDING](MODDING.md) |
| 加关卡与角色逐步表：从零写一关一个角色（续集示范）、改剧情流转、换配乐、加脚本 opcode 表现 | [MODDING_LEVELS](MODDING_LEVELS.md)、[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（逐关流转，生成物） |
| 胜负脚本词表（参考区） | [WINFAIL_TOKENS](WINFAIL_TOKENS.md)（`hsl generate winfail_token_table` 生成） |
| 选项注册表字段与默认值 | [OPTIONS](OPTIONS.md) |
| 要改代码时去哪 | [ARCHITECTURE](ARCHITECTURE.md) |
| 战斗怎么称呼：玩家第几场 · 场景名（文件号） | [BATTLE_NAMES](BATTLE_NAMES.md) |

## 贡献代码

| 需要 | 读 |
| --- | --- |
| 准备正版、门禁口径、不提交原版派生物、PR 流程 | [CONTRIBUTING](../CONTRIBUTING.md)、[NOTICE](../NOTICE.md) |
| 代理（Claude Code、Codex 等）的工作手册：阅读顺序、硬规则、lane 流程 | [AGENTS](../AGENTS.md) |
| 代码分层、状态所有者、任务路由 | [ARCHITECTURE](ARCHITECTURE.md) |
| 行动、背包／装备、成长、技能／状态与 AI 事务 | [Battle systems](architecture/BATTLE_SYSTEMS.md)；只读命中章节 |
| 开场、菜单／面板、移动、交锋与地图收尾 | [Presentation](architecture/PRESENTATION.md)；只读命中章节 |
| 某类改动要跑什么、如何判断通过 | [测试路由](../tests/README.md)、[工具说明](../tools/README.md) |
| 证据用语的唯一定义 | [CONTEXT](../CONTEXT.md) |
| 每个 game 模块五维度来源、remake-invented 与 provisional 清单 | [PROVENANCE](PROVENANCE.md)（由模块头生成，`hsl check provenance` 强制） |

## 研究附录

| 需要 | 读 |
| --- | --- |
| 资源、静态包、原图与具体来源 | [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md)（证据包索引，生成块由 `hsl check evidence_index` 维护） |
| 机制证据等级与未恢复边界 | [MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md) |
| 证据包目录说明 | [evidence_packets](evidence_packets/README.md) |
| 核心公式／地址的静态结论 | [核心规则证据](first_battle_core_logic_evidence.md) |
| 第一战资源／脚本的早期结论（09-01，已被逐关导入链与各证据包覆盖） | [资源证据](first_battle_static_resource_evidence.md) |

## 内部（不随公开导出）

`docs/internal/`（lane 任务书模板、时间账、轮次记录 ROUNDS、各轮决策记录、开源计划）与 `docs/audits/`（审计报告）是我们自己的过程文档，`tools/oss_export.sh` 导出公开树时整目录去掉；公开文档不得链接它们（`tools/hsl_docs_check.py` 拦），需要提到时写成代码样式的路径。

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
