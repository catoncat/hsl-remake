# 地图物件闪烁（mapobjFlash）：步进节拍、变暗深度与加色画法

> evidence: static-derived: 站立物件过程 0x43ccf0 的 mapobjFlash 分支与像素例程 0x462240 的加色两路; resource-derived: TYPE.H mapobjFlash、hsl.pak 全部 OBS 的 obj_Score／obj_HitPoint／obj_Data; provisional: 层级表逐项值与 16 位通道舍入未逐像素对照 · status: live · functions: 0x43ccf0, 0x43cee7, 0x43d84b, 0x462240, 0x4623e1 · tools: hsltools/sources/scripts.py · updated: 2026-09-28

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 只读。tick 按 [tick 率包](../runtime_observations/original_tick_rate/README.md) 的设计值 16 ms 换算。

## 结论

- 原版闪烁物件以加色＋层级画（engADDCOLOR_MIX：`dst + src × 层级/16`），层级从 16 起每 `obj_HitPoint` tick 走一步：先降 `obj_Score` 级，再升回 16，在 16 多停一步；一周 `2·obj_Score + 1` 步（static-derived）。
- 第 52 关（light06–08）8／4：层级 16→8→16，一周 17 步 × 4 tick ＝ 68 tick ≈ 1.09 s，最暗时加色量减半；第 3、504–506 关 light11 11／15（23 步 × 15 ＝ 345 tick）、light12 11／12（276 tick）；第 28 关火 4／4（36 tick）；第 74、80 关 6／4（52 tick）；第 13 关 BALL001 3／8（56 tick）；第 59 关 AIR16_01 4／6（54 tick）（resource-derived）。
- 闪烁不改深度：`+0xc` 仍由分派前的 `0x43ce77` 按锚点 y 写（static-derived）。
- 普通 engADDCOLOR（火焰等 mapobjNextShape 物件）不带 engMIX 位，走不乘层级的饱和加法（static-derived）。
- 重制 `MapObjectFlash` 按同一计数器逐 tick 走、`modulate = 层级/16` 配加色混合；`MapObjectAnimation` 保持纯加色。改前是 0.55 s 双正弦、深度 0.22 的估值。

## 证据

| 地址 | 读法 |
| --- | --- |
| `0x43ce7c` | `obj_Data9`（+0xac）减一查跳表 `0x43d8c0`；4（mapobjFlash）→ `0x43cee7` |
| `0x43cee7` 首次调用（`edi = 消息 & 0x20000000`） | 模式 `|= 0x24000000`（engADDCOLOR_MIX）；层级 `+0x28` 为 0 时置 16（非 0 即 obj_Data 预置值保留）；`+0x8a = +0x88`（延迟备份）。同一次调用接着走每 tick 段 |
| `0x43cf1a` 每 tick | `+0x88` 减一，仍 > 0 就结束；否则 `+0x88 = +0x8a`，取 `c = +0x86`（obj_Score 高半字，初 0）、`L = +0x84`（obj_Score 低半字）：`c < L ? c+1 : −c`；`c > 0` 层级减一（不低于 0），`c < 0` 层级加一（不高于 16），`c = 0` 不变；写回 `+0x86` |
| `0x43d84b` 尾部 | 全局物件色模式 `[0x4c1cc0]` 只改不带 `0x4000000` 的物件，闪烁物件不受影响 |
| `0x462240` | 像素例程加色种类：模式带 `0x20000000` 跳 `0x4623e1`——`[0x4bfbf0 + 层级·4]` 取每通道缩放表，`dst + T(src)` 饱和；否则 `0x462258` 直接 `dst + src` 饱和。层级表按 [效果运动包](original_effect_motion.md) 为 `src × 层级/16` |

计数器序列（L = 8）：`1..8`（层级 15..8）、`−8..−1`（9..16）、`0`（16 不变）、再 `1`……所以最暗 8 停一步、满 16 停两步。

OBS 普查（hsl.pak 全部 obj-*.obs 中 `obj_Data9 = mapobjFlash`）：52 关码 33–35、54 关码 30–31 为 8／4；3、504–506 关码 30 为 11／15、码 31 为 11／12；13 关码 18 为 3／8；28 关码 15、16、20、21 为 4／4；59 关码 23 为 4／6；74 关码 15、80／97 关码 16–17 为 6／4；65 关码 15 无 obj_Score／obj_HitPoint、`obj_Data = 12`——计数器恒 0，层级常驻 12。

## 重制接线

- 导入：`hsltools/sources/scripts.py` 为 mapobjFlash 块保留 obj_Score／obj_HitPoint（obj_Data 本来就保留），各关 `map_objects.json` 的 `object_fields` 带出。
- `game/battle/scene/BattleSceneStage.gd` 把三字交给 `game/battle/runtime/MapObjectFlash.gd`：`configure` 同原版首次调用（层级、延迟、当次即计一 tick），`_process` 按 `OriginalTick.TICK_SECONDS` 逐 tick 走同一计数器，`modulate` 取层级/16，材质 `BLEND_MODE_ADD`。provenance：layout／timing 都 static-derived 指向本包。
- `game/battle/runtime/MapObjectAnimation.gd` 的纯加色注为 static-derived（`0x462240` 不乘层级）。

## 复现

`r2 -q -c 'pd 60 @ 0x43cee7; pd 40 @ 0x462240' hsl01.exe`；跳表 `pxw 60 @ 0x43d8c0`。

## 边界

- 层级表 `0x4bfbf0` 的逐项值沿用效果运动包的 `src × 层级/16` 读法，本包未逐项核对；16 位像素的通道舍入与 Godot 浮点加色未逐像素对照（provisional）。
- 物件进场首个过程调用与首帧绘制的先后未追，相位最多差一 tick。
- 54、65、97 关不在当前导入范围，只列 OBS 值。
