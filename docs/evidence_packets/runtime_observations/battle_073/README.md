# 悲嘆之湖・兄弟的抉擇（level 73）：正式戰鬥

> evidence: runtime-measured; resource-derived; provisional · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版的窗口化运行回执（`tests/capture_battle_review.gd -- --level=73`），属于 **runtime-measured**，不是原 EXE 现场。WINFAIL073 的事件结构与演员资源为 **resource-derived**；事件分支时序、对象生命周期和世界状态消费属于 **provisional**。

## 入口

`content/battles/campaign.json` 将 level 73 注册为 `content/battles/battle_073.json`；正式场景由 `python3 tools/hsl.py generate level_battle:73` 组装，`story_073.json` 保留为独立预览回归。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 事件-only 战斗入口取景；该关没有首次控制阶段 |

`manifest.json` 记录事件完成夹具把 `event_2` 交接到 world map 的运行结果；完整原始输出留在 `ignored/battle-073-review/`。

## 边界

- WINFAIL073 没有 `win`／`fail` 段；`event_0`／`event_1` 两个选择分支都链到无条件 `event_2`，重制以事件结束交接，不伪造胜利条件。
- 对白、红光／冲击表现、town／big-map 写入与原版 object lifetime 仍是 **provisional**。
