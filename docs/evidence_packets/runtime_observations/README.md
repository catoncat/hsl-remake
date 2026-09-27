# 运行实测目录

> evidence: runtime-measured · status: record-only · updated: 2026-09-27

## 结论

- 本目录放两类实测：原版程序跑出的读数与画面（不可再生，只重排文字、不删数据）与重制侧窗口回执（能重跑，结论归对应的 `static_reverse/original_<机制>.md`）（runtime-measured）。
- 按主题找包用 [KNOWLEDGE_INDEX 证据包索引](../../KNOWLEDGE_INDEX.md#evidence-packet-index)；读法见 [研究附录首页](../README.md)。

## 证据

| 入口 | 内容 |
| --- | --- |
| [original_gameplay_reference](original_gameplay_reference/README.md) | 原版录像按主题切出的参考帧与接触表（生成物） |
| `first_battle_visual_evidence_index.json`／`.md`、`first_battle_visuals/` | 第一战原版静帧基准；以每条记录的 `status`、`visual_state`、`use_for`、`not_for` 为准，文件名不带语义；空间合同工作必看 `move_overlay_primary` |
| `first_scene_opening_choreography_packet.json`／`.md` | 开场片段合同：时间线、静帧、角色／地图资源证据与 Godot 截图状态；缺的截图记为 `missing_generated_capture`，不推断 |
| 原版侧实测（`camera_panel_motion`、`cutin_floaters`、`effect_motion`、`menus_ui`、`original_control`、`original_tick_rate`、`original_title_ornaments` 等） | 原版窗口的逐帧坐标、时序与内存读数 |

## 重制接线

各子目录的 README 点名消费它的 `game/` 模块；本页不直接被代码消费。

## 复现

不可再生：原版侧读数以各包记录的录像与窗口为准；重制回执各自写复现命令。

## 边界

- 新的原始截图、录像与 trace 留在 `ignored/`，只把压缩后的结论与少量帧提升到这里。
- 单次录像的读数不升级为全局规则；参考帧存在不等于重制已修复。
