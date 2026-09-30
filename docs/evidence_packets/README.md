# 研究附录：证据包

原版规则、时序与画面的恢复记录。每篇只回答一个机制，结论先行；产品现状看 [PROJECT](../PROJECT.md)，这里只放能复核的证据。

## 从哪进

| 想找 | 去 |
| --- | --- |
| 按主题、地址（搜 `0x4…`）或工具名找包 | [KNOWLEDGE_INDEX 证据包索引](../KNOWLEDGE_INDEX.md#evidence-packet-index)（由包头生成） |
| 某机制的证据等级与未恢复边界 | [机制矩阵](../MECHANICS_EVIDENCE_MATRIX.md) |
| 与原版的已知差异 | [差异清单](static_reverse/parity_gap_inventory.md)（生成物） |
| EXE 静态读法与规则结论 | `static_reverse/`：一机制一篇，文件名 `original_<机制>.md` |
| 原版实测与重制回执 | [runtime_observations](runtime_observations/README.md)；原版参考帧按主题见 [original_gameplay_reference](runtime_observations/original_gameplay_reference/README.md) |
| 资源清单、影片、战役总览 | [resource_inventory](resource_inventory/README.md) |

## 怎么读一篇

六块，顺序固定：包头 → **结论**（≤10 行：原版怎样／重制怎样／差异，每句带等级）→ **证据**（地址、资源字段、实测读数）→ **重制接线**（模块与 provenance 写法）→ **复现**（一条命令，或「不可再生：原版侧唯一记录」「驱动已退役，回执为历史记录」）→ **边界**。`status: superseded` 的篇是存根，只剩一行指向结论所在的包。

## 证据用语

证据等级共七级，定义和在模块头里的写法见 [METHOD](../METHOD.md#证据分级)。

## Packet header

每篇 H1 下一行，字段按序、以 ` · ` 分隔：

```text
> evidence: static-derived; provisional: synthetic initialization · status: live · functions: 0x448840 · tools: hsl_native_stats_probe.py · updated: 2026-09-10
```

| 字段 | 规则 |
| --- | --- |
| `evidence` | 七级之一或多项，`; ` 分隔，可带范围 `provisional: <哪部分>`；主等级在前 |
| `status` | `live`（正文点名消费它的 `game/` 模块、`*Rules`／`*Runtime` 类或 `tests/` 套件）｜`record-only`（索引、原版侧记录、历史）｜`superseded: <相对路径>`（目标必须存在） |
| `functions` | 可选；`hsl01.exe` 函数入口 `0x4xxxxx`，小写、去重、升序 |
| `tools` | 可选；`tools/` 或 `tests/` 下的复现入口文件名，去重、排序；不列 `godot.sh`／`play.sh`／`verify.sh` |
| `updated` | `YYYY-MM-DD`，内容最后变动日 |

包头是唯一来源：改包头后跑 `python3 tools/hsl.py generate evidence_index`，与 `docs/KNOWLEDGE_INDEX.md` 一起提交；`check evidence_index` 在门禁比对，`--lint` 给出未知函数、缺失工具等提示。生成的包（`campaign_overview.md`、`first_scene_opening_choreography_packet.md`）由生成器写包头。原始录像、长反汇编与临时导出不入库，放 `ignored/`。
