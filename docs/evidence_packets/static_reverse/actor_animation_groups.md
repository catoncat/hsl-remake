# Original actor animation groups

> evidence: resource-derived; static-derived · status: live · functions: 0x446c40, 0x45e525, 0x45e5a6 · tools: hsltools/evidence/actor_walk_manifest.py · updated: 2026-09-28

## 结论

- SHAPEDEF.TXT maps stand to source group 0 and walk_up／down／left／right to groups 3／1／4／2, six frames each (resource-derived).
- The original standing loop reloads delay 10 (11 ticks per frame) and walking reloads delay 2 (3 ticks per frame); `ActorRuntime` plays both in original ticks, and the manifest `fps: 8` is no longer read (static-derived; see [tick_mapping.md](../runtime_observations/original_tick_rate/tick_mapping.md) §36 格映射).

## 证据

Extracted exact original PAK member `@:\data\SHAPEDEF.TXT` to `content/imported/hsl/global/tables/SHAPEDEF.TXT`. For SID_PLAYER0 and the currently imported Enemy021/023/024/026 definitions, the table explicitly maps:

| Field | Source group | Frame count |
| --- | --- | --- |
| stand | 0 | 6 |
| walk_up | 3 | 6 |
| walk_down | 1 | 6 |
| walk_left | 4 | 6 |
| walk_right | 2 | 6 |

Previous importer incorrectly labelled all five source groups as walking directions. Group 0 is a standing sequence, so the former live call walk/0 animated standing poses during displacement.

The importer reads the named fields and frame counts from SHAPEDEF.TXT, records its digest, and rejects missing or unsupported mappings. Numeric `facing_code` is retained solely as the historical source-file group index; named animation keys carry the actual semantics. ActorRuntime selects up/down/left/right at each path segment and returns to stand/0 on arrival. No new gameplay direction state is owned by the actor.

`0x446c40` selects start/count pairs from per-actor shape definitions and calls engine sequence helper `0x45e525`; the delay argument and looping behavior are now traced below; real-time tick frequency remains unconfirmed. The resource table proves state/direction-to-resource association, not movement speed, original timeline cadence, pose blending, or full visual parity. A dominant-axis choice for any non-grid diagonal opening segment remains provisional; battle paths use cardinal grid edges.

Regressions cover right→up corner resources, initial and final standing resources, completion stopping walking frame updates, and original per-frame draw origins. Runtime captures verify displaced walking poses. The six standing frames loop in the live scene at 11 original ticks per frame (the manifest's former provisional 8 fps is superseded and not read).


## Standing loop and delay

Static-derived on EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`:

- State 0 at `0x442139..0x442151` selects the standing sequence with delay 10; nonzero movement states use delay 2 at `0x442153`. `0x4455ee..0x445616` has the corresponding second actor path.
- `0x446c40` selects a shape start/count pair. State 0 uses the first pair at `0x446c64..0x446c6e`; the helper passes the supplied delay unchanged to `0x45e525`.
- `0x45e525` stores current/start frame, current/reset count, and current/reset delay. `0x45e5a6` decrements delay and advances only below zero, then reloads it. At the end it restores the frame count and subtracts that count from the frame index, thereby looping.
- Thus the examined standing path uses 11 animation updates per frame, versus 3 for walking on this path. These counts are per original tick; the tick rate itself is covered by [original_tick_rate](../runtime_observations/original_tick_rate/README.md).

## 重制接线

Live `ActorRuntime` advances standing frames from its process delta at `IDLE_FRAME_TICKS = 11` and walking frames at `WALK_FRAME_TICKS = 3` original ticks, and preserves fractional elapsed time. State changes reset that elapsed time; the idle clock does not touch a walking sequence. Frame drawing continues through the existing original SHP anchors, and there are no standing footstep cues. This is a small direct presentation change with no credible additional abstraction to remove.

Verification covers all five actor types: hold duration, frame advance, complete six-frame wrap, fixed world foot point, walking isolation, and return to the standing loop. A real 640×480 Godot recording (`ignored/idle-review/idle.mp4`) shows Leonard at world `(496,560)` while standing sources progress through frames 1, 2, 4 and 6 in successive samples. Rendered frames were inspected; the original cadence and complete sprite/color parity remain unproven.

## 脚本换形期间的帧推进

**结论**
- 原版：`actChangeShape` 把演员的帧换成脚本给的形状段，第三参数是延迟 D，每帧停 D＋1 tick，按段内帧数循环；朝向与站立状态号不动（static-derived）。
- 原版：随后的 `actMoveDispWait` 移动途中按速度延迟循环；到位后回到状态 0，0x1800 仍置位，帧停在到位时那一帧，直到 `actRestoreShape`（static-derived）。
- 原版：`actRestoreShape` 让站立组从第一帧、延迟 10 重新载入（static-derived）。
- 重制：换形按脚本延迟推进（玩家第 3 场 · 逃出克萊恩城（LEVEL053）緹娜绳索形 D＝4，每帧 5 tick；士兵 023 形 D＝2，每帧 3 tick）；保形移动到位后停帧；恢复时站立序列从头开始（static-derived）。

**证据**（EXE SHA-256 同上节）
- VM 分派 `0x4508a1` 查表 `0x4537f4`：opcode 13／14（actChangeShape／Wait）→ `0x451aa3`，把 code、serial、延迟、形状号、帧数存进 VM `+0x98／+0x94／+0x9c／+0xa0／+0xa4`，逐帧 `0x460058` 预载，VM 状态 ＝ opcode；opcode 17（actRestoreShape）→ `0x451b92`。
- VM 状态分派 `0x45086e`（字节表 `0x453768` → 跳表 `0x453708`）：状态 13／14／17 同入 `0x453370`，调 `0x4502f0(code, serial, 延迟, 形状号, 帧数, Wait 时 VM)`；17 传全 0。
- `0x4502f0` 帧数非 0：只在演员 `+0x8c == 0`（站立）或状态高字 0x34 时生效，否则不写（VM 照常继续）；写 `+0x78／+0x7a` ＝ 帧数（当前／重装计数）、`+0x30` ＝ 形状号（当前帧）、`+0x7c／+0x7e` ＝ 延迟；Wait 版另置 `+0x8c = 0x340000`、`+0x50 = VM`。帧数 0（恢复）：`+0x90 = 0xffff`、`+0x80 &= ~0x1800`、`+0x8c = 0`。
- 站立时的推进：两条演员过程的状态 0 走公共尾（`0x4420ba..0x442169`；`0x4447a7 → 0x4455d4..0x44561f`）：期望形态值（0，或某标志下 6）与 `+0x90` 相同则只调 `0x45e5a6`，不同才 `0x446c40(类型, 值, 值 0 时延迟 10 否则 2)` 重载。换形不动 `+0x90`（普通走位到位时 `0x45420b` 已写 0），所以每 tick 用脚本延迟循环；恢复把 `+0x90` 写成 −1，下一 tick 必重载站立组。
- 公共尾在 `+0x80 & 0x1000` 置位时整段跳过（`0x4420e5`、`0x4455da`），且状态 0 不调 `0x453b90`（其 `0x453ba3` 的 0x1800 每 tick 推进只在脚本状态里跑）。`actMoveDispWait` 末子状态 `0x454262` 写 `+0x8c = 0` 并放行 VM，于是到位后帧不再推进。
- Wait 版状态 0x34 用 `0x45e575`（播到末帧即停在末帧、计数置 1）走一遍后放行 VM、回状态 0；第一章 0 处使用。

**重制接线**
- `OpeningStoryObjects._change_shape` 读第三参数为延迟，以 `TICKS_PER_SECOND／(D＋1)` 传给 `ActorRuntime.set_shape_override`，帧数按第五参数截取；`_restore_shape` 清换形后站立序列从第一帧重来。
- `ActorRuntime._finish_keep_pose_move` 置 `_override_held`，保形移动到位后停帧；再次移动或清除时解除。provenance：`timing: static-derived` 本篇。

**复现**

`r2 -q -e scr.color=0 -c 'pxw 20 @ 0x453828; pd 30 @ 0x453370; pd 40 @ 0x4502f0; pd 40 @ 0x4420ba; pd 20 @ 0x4455c9; pd 8 @ 0x454262' hsl01.exe`

**边界**
- 演员在走动（状态非 0、非 0x34）时原版忽略换形；重制不判此条，照常换（provisional）。
- 公共尾里「值 6」的触发标志（`[esp+0x30] & 0x800`）未读；若脚本演员带该标志，换形可能被站立重载覆盖（provisional）。

## 复现

`python3 tools/hsl.py check actor_walk_manifest:chapter01 actor_walk_manifest:shared`（SHAPEDEF 字段、帧数与摘要）；静态部分 `r2 -q -e scr.color=0 -c 'pd 12 @ 0x442139; pd 20 @ 0x446c40; pd 18 @ 0x45e5a6' hsl01.exe`。

## 边界

- The resource table proves state／direction-to-resource association, not pose blending or full visual parity; a dominant-axis choice for non-grid diagonal opening segments remains provisional.
- Original sprite／color parity of the standing loop is not proven by the remake recording.
