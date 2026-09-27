# 城门火焰：第 51 关 FIRE01 的帧序列与换帧节拍

> evidence: resource-derived; static-derived: defProcStandObject 的 mapobjNextShape 分支与 0x45e5a6 计数 · status: live · functions: 0x43ccf0, 0x45e5a6 · tools: hsltools/assets/fire_animation.py · updated: 2026-09-27

## 结论

- 原版第 51 关两处火焰（EVEF 记录 3、6）共用 OBJ-051 对象 22：`obj_Shape_Number=10`、`obj_Shape_Delay=3`、`obj_Data9=mapobjNextShape`、`obj_Mode=engADDCOLOR_ZOOM`、两个缩放字段 `0x0000a000`（resource-derived）；立物过程 `0x43ccf0` 的 mapobjNextShape 分支每次调用 `0x45e5a6`，延迟 3 即每 4 次过程更新换一帧（static-derived）。
- 重制 `game/battle/runtime/MapObjectAnimation.gd` 播放导入的十帧，逐帧套原绘制原点、缩放按 16.16 定点取 0.625、加色模式用 Godot 加法混合（resource-derived）。
- 差异：过程更新按每秒 60 次（显示 15 帧／秒）、初始相位与 RGB565 饱和加法的混色结果都是重制读法。

## 证据

**resource-derived**

| 项 | 读数 |
| --- | --- |
| OBJ-051 对象 22 | `obj_Shape_Number=10`、`obj_Shape_Delay=3`、`obj_Data9=mapobjNextShape`、`obj_Mode=engADDCOLOR_ZOOM`、缩放 `0x0000a000`×2 |
| 帧 | FIRE01 十张 SHP，逐帧绘制原点、源与 PNG 哈希，写入 `content/imported/hsl/chapter01/fire_animation/manifest.json`（带 OBS 源哈希） |
| 编号 | PROCESS.DEF `defProcStandObject=2`；TYPE.H `mapobjNextShape=5` |

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

| 地址 | 读法 |
| --- | --- |
| `0x477c34` | 过程表槽位 2 指向 `0x43ccf0` |
| `0x43ce83` | 过程分派先把选择子减 1，mapobjNextShape 落到表项 `0x43d8d0` → `0x43cf96` |
| `0x43cf97` | 调 `0x45e5a6` |
| `0x45e5ad`／`0x45e5b1` | `+0x7c` 有符号字减 1，非负则不换帧；否则从 `+0x7e` 重载延迟、`+0x30` 帧号加 1、`+0x78` 剩余帧减 1，序列末从 `+0x7a` 重载并回绕 |

## 重制接线

- `tools/hsltools/assets/fire_animation.py` 从原版安装导出帧与 manifest；`MapObjectAnimation.gd` 在固定世界锚点播放、加法混合直接由渲染器实现（manifest 不另记混合标签）。
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/gate_fire_animation.md`。
- 重制读法：每秒 60 次过程更新；替换点是 [原版 tick 速率](../runtime_observations/original_tick_rate/README.md) 的过程节拍实测。延迟 3 不是 3 毫秒，也不是每秒 3 帧。

## 复现

`python3 tools/hsl.py check fire_animation`（帧数、延迟、缩放与 PNG 完整性，不需要 Wine 或 PAK）。

## 边界

- 原版过程的实际频率与两处火焰的初始相位未测。
- 混色不宣称与 RGB565 算术逐像素相同。
