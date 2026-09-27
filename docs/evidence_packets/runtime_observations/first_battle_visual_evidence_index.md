# First Battle Runtime Visual Evidence Index

> evidence: runtime-measured · status: record-only · tools: hsltools/evidence/visual_index.py · updated: 2026-09-01

Checked: 2026-09-01

本文件索引第一战第一场景的**本机原版 runtime 视觉证据**。所有当前可用图片已经收敛到：

```text
docs/evidence_packets/runtime_observations/first_battle_visuals/
```

不再要求 Agent 在 `asset-dumps/`、`ignored/`、历史 raw 目录或 Godot import cache 中寻找基准图。机器入口：

```text
docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json
/opt/homebrew/bin/python3 tools/hsl.py check visual_evidence_index
```

## 证据恢复说明

清理前发现原索引中的 16 张图片只有一张源 PNG 仍存在，其余多数只剩 Godot `.import` sidecar 或原版窗口录屏。当前 curated set 由以下方式恢复：

- 开场录屏帧：保留仍存在的无损 PNG，其他按原 frame index 从原版 2 fps window-only MP4 恢复。
- 第一可操作阶段、Move 和取消路线：从现有 `.godot/imported/*.ctex` 无损导出。

JSON 中每项都保留 `original_source_path` 和 `curation_provenance`。当前图片均为 1280×1024 宿主窗口截图，其中游戏逻辑内容对应原版 640×480 的 2× 捕获。

## 当前可用 evidence id

### 开场、对白与站位锚点

| Evidence id | 状态 | 用途边界 |
| --- | --- | --- |
| `opening_transition_rain_frame` | confirmed | 开场转场；不是战场站位或 camera curve。 |
| `opening_transition_castle_wall_frame` | confirmed | 城墙转场负例；不是桥上战场镜头。 |
| `opening_lower_formation_before_dialogue` | confirmed | 下方队伍与对白前 crop 候选；不单独证明 first control。 |
| `opening_dialogue_leonard` | confirmed | Leonard 对白 UI 与地图上下文。 |
| `opening_dialogue_map_only_gap` | candidate | 对白切换中的 map-only gap；不能证明已经交控。 |
| `opening_dialogue_soldier` | confirmed | 士兵对白 UI 与 actor focus。 |
| `p1_route_upper_formation_11` | confirmed | 上方城门/桥、单位和前景遮挡锚点。 |
| `p1_route_upper_formation_12` | confirmed | 上方 formation 第二锚点。 |
| `p1_route_action_menu_13` | confirmed | route 到行动菜单后的 first-control/menu cross-check。 |

### 第一可操作阶段与 Move

| Evidence id | 状态 | 用途边界 |
| --- | --- | --- |
| `first_control_action_menu` | confirmed | 行动菜单、角色相对位置和 first-control camera context。 |
| `first_control_action_menu_hover_move` | confirmed | Move command 周边菜单状态；不是蓝格图。 |
| `move_overlay_primary` | confirmed | 当前 Move 蓝格第一基准；空间合同修改必须引用。 |
| `move_select_esc_capture` | negative | 画面仍有蓝格；不能证明 Esc 已取消。 |
| `move_select_rclick_capture` | negative | 画面仍有蓝格；不能证明右键已取消。 |
| `move_select_rclick_return_retry` | confirmed | 已回到菜单的某一帧；不证明精确取消时机。 |
| `move_space_confirm_menu` | confirmed | 移动路线后菜单状态；不证明路径或 timing。 |

## 当前空间合同观测

- `move_overlay_primary` 中的 Move 蓝格、Leonard、其他单位、前景树和 camera crop 必须作为同一空间合同处理。
- 蓝格人工观测约为 64 capture px / 32 logical px pitch；这是 preflight 候选，不是最终投影真值。
- 当前 evidence 可约束屏幕范围、菜单 anchor、脚点候选、hit-test 方向和 z-order review；不能证明完整地形代价、path tie-break、edge scroll 或 WRD 中间 bit 语义。
- 当前仍缺 confirmed `first_control_idle_no_menu`，不得把对白间隙或已打开菜单的画面声明为纯 first-control formation。
- 开场录屏与 p1-route 图片是离散锚点，不是连续 opening camera curve 或完整 actor path timing。

## 使用规则

1. 引用 evidence id 和 curated file，不引用 raw 目录名。
2. 修改 Move overlay、camera crop、projection、actor foot anchor、hit-test 或 foreground z-order 时，`move_overlay_primary` 是强制基准。
3. 文件名不是语义；以 JSON 中 `visual_state`、`status`、`use_for` 和 `not_for` 为准。
4. `confirmed_negative_for_cancel_return` 只能阻止错误声明，不能作为取消成功证据。
5. 旧 Godot、外部视频、未整理 candidate render 和 raw screenshot 不能单独升级成原版视觉事实。
