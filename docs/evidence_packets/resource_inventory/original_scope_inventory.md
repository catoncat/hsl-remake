# Original scope inventory versus remake coverage

> evidence: resource-derived; provisional: 500 段战斗桩的触发路线 · status: record-only · tools: hsltools/data/scope_inventory.py, hsltools/data/story_token_coverage.py, hsltools/data/winfail_coverage.py, hsltools/levels/battle.py · updated: 2026-09-28

## 结论

- 原版 `hsl.pak` 共 5,600 条记录：主线 LEVEL 0–99 有 72 个关卡 bin、47 场带 WINFAIL 的战斗、22 个只有 STORY 的剧情关、884 个 actMessage；500–578 为 78 个战斗桩，900+ 为 7 个特殊关（resource-derived）。
- 本篇只计数，不给未实现关卡定语义，也不对已实现关卡声明原版等价（等价看 [机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md)）。重制侧覆盖数随 `campaign.json` 变化，当前数以生成物和 `check scope_inventory` 结果行为准，不写进本篇。

## 证据

原版侧数字由 `tools/hsltools/data/scope_inventory.py` 从 `hsl.pak` 读记录名与 INI 段头得出（resource-derived）。

| Range | Levels (LEVEL*.BIN) | Battles (with WINFAIL) | Story-only (STORY without WINFAIL) | actMessage tokens |
| --- | --- | --- | --- | --- |
| Main story, level 0–99 | 72 | 47 | 22 | 884 |
| Battle stubs, level 500–578 | 78 | 78 | 0 | 0 |
| Specials, level 900+ | 7 | 5 | 0 | 31 |

主线范围内 0、49、54 三个关卡 bin 既无 STORY 也无 WINFAIL，计入关卡数、不计入内容。500 段战斗桩不带对白，读作通用遭遇地图（`provisional`：本扫描不确定它们由随机遭遇还是自由战斗触发）。

全局表（INI 段）：MAGIC.TXT 39 `[magic]`、SPECIAL.TXT 60 `[special]`、ITEM.TXT 239 `[item]`、PLAYERS.TXT 66 `[character]`、TRACK.TXT 44 `[track]`、TOWNDEF.TXT 191 `[town_event]` + 62 `[item]` 商店表、`bigmap.dat` 5,600 字节。

## 重制接线

机读输出 `content/generated/hsl/static/hsl01/scope_inventory.json`（schema `hsl_scope_inventory.v1`）；`--check` 按当前 `content/battles/campaign.json` 重算重制侧（已注册关卡、带战斗场景的主线战斗、已注册关卡内的 actMessage 数），原版侧只在 `--rescan` 时重读 PAK。主线战斗由 `level_battle:N`（`tools/hsltools/levels/battle.py`）从种子、manifest 链与 `content/battles/levels/NNN.json` 统一生成；世界层（bigmap／TOWNDEF／TRACK）的读法见 [world_map_data](../static_reverse/world_map_data.md) 与 [original_world_town](../static_reverse/original_world_town.md)，职业表见 [original_job_stats](../static_reverse/original_job_stats.md)。

## 复现

```bash
PYTHONPATH=. python3 tools/hsl.py generate scope_inventory                 # rebuild from the PAK (needs $WINEPREFIX)
python3 tools/hsl.py check scope_inventory                      # offline: remake side vs campaign.json + internal totals
PYTHONPATH=. PYTHONPATH=tools python3 -m hsltools.data.scope_inventory --check --rescan  # also compare original-side counts with the PAK
```

## 边界

- 「已注册」只表示关卡可经 `campaign.json` 到达；开场预览与暂定场景也计为已注册，不等于原版等价。
- 500 段战斗桩的触发路线未由本扫描确定。
