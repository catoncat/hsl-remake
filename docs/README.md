# Documentation Map

Checked: 2026-09-15

## Current authority

| Need | Read |
| --- | --- |
| 工作规则、开始与结束条件 | [AGENTS](../AGENTS.md) |
| 项目现在做到哪里、下一项交付与验收 | [PROJECT](PROJECT.md)；只在这里维护产品优先级 |
| 第一战交付范围、当前与历史验收 | [FIRST_BATTLE_ACCEPTANCE](FIRST_BATTLE_ACCEPTANCE.md) |
| 当前代码分层、状态所有者、任务路由 | [ARCHITECTURE](ARCHITECTURE.md) |
| 行动、背包／装备、成长、技能／状态与 AI 事务 | [Battle systems](architecture/BATTLE_SYSTEMS.md)；只读命中章节 |
| 开场、菜单／面板、移动、交锋与地图收尾 | [Presentation](architecture/PRESENTATION.md)；只读命中章节 |
| 设置页选项的三层口径（原版／体验改良／开发）与首批候选 | [OPTIONS](OPTIONS.md)（已拍板；B1／S1／S2 已做） |
| 每条 lane 的步骤时间与门禁耗时（效率审计依据） | [LANE_TIMELOG](LANE_TIMELOG.md) |
| 战斗怎么称呼：玩家第几场 · 场景名（文件号）对照表 | [BATTLE_NAMES](BATTLE_NAMES.md) |
| 某类改动要跑什么、如何判断通过 | [测试路由](../tests/README.md)、[工具说明](../tools/README.md) |
| 当前文件认领、跨线请求与确认 | [PARALLEL_WORK](../PARALLEL_WORK.md)；留言不是产品状态 |
| 资源、静态包、原图与具体来源 | [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md) |
| 机制证据等级与未恢复边界 | [MECHANICS_EVIDENCE_MATRIX](MECHANICS_EVIDENCE_MATRIX.md)、[CONTEXT](../CONTEXT.md) |
| 每个 game 模块五维度来源、remake-invented 与 provisional 清单 | [PROVENANCE](PROVENANCE.md)（由模块头生成，`hsl check provenance` 强制） |
| 核心公式／地址的静态结论 | [核心规则证据](first_battle_core_logic_evidence.md) |
| 第一战资源／脚本的详细结论 | [资源证据](first_battle_static_resource_evidence.md) |

所有 Agent 的通用入口仍是根目录 `AGENTS.md` 和 `docs/PROJECT.md`，不需要每次通读全部资料。

更新现行合同所在段落，删除或标明被替换的表述；来源、精确参数和验收过程放对应 evidence packet，再从索引链接。避免把相同事务复制到 PROJECT、架构和协作日志。旧观测只证明当时版本，不能覆盖后来已接入的行为。

## Machine-readable authority

- `content/battles/first_battle.json`：当前 live scenario。
- `content/imported/hsl/`：可复用原版资源、脚本 IR 和 manifest。
- `content/generated/hsl/`：compact generated/static facts。
- `docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json`：curated 原作视觉基准。
- `docs/evidence_packets/resource_inventory/resource_manifest.json`：完整资源成员索引，供机器搜索，不建议整文件塞入上下文。

## History

旧计划、一次性编排文档和对话快照已从活跃仓库删除；完整历史保存在仓库外的清理前 Git bundle。

当前仓库提交后的演进可用 Git 查明；协作日志按消息编号定向读取。不要恢复历史文件树作为冷启动入口。本地导航可单独运行 `python3 tools/hsl_docs_check.py`，也包含在完整门禁中；它检查可跟踪 Markdown 的显式链接和锚点，不联网、不把代码示例或历史裸路径当运行时依赖。
