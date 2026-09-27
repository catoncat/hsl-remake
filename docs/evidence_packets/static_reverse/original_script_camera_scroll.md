# 剧情脚本的镜头：居中缓动、走路跟随与 actScrollBG 步进

> evidence: static-derived; resource-derived: 脚本 token 与参数; provisional: 16 ms 设计值与 19.4 ms 实测的取舍（R24 负责人决定） · status: live · functions: 0x42dc50, 0x43bf30, 0x43c140, 0x44fcf0, 0x44fd90, 0x44ff50, 0x4501f0, 0x450450, 0x450840, 0x453b90, 0x45e80d · tools: hsltools/data/story_corpus.py, run_camera_panel_motion_tests.gd · updated: 2026-09-28

## 结论

- 原版剧情镜头每 tick 的位置可从原指令读出：`0x43bf30` 把对象放到 640×384 视口正中 (320,192)，经 `0x45e80d` 逐轴走 `clamp(剩余/2, ±step)`（剧情 step 16、战斗 32、快进 +12，容差 4）；`actScrollBGToPosSpeed` 用 `0x43c140`（容差 1、step＝speed）；脚本行走 speed→1／2／4／8 px/tick，只有 Wait 变体先居中（到位才开走）并在越界时同步跟随，不带 Wait 的行走不碰镜头；actWalkAndDelete(Wait)、actMoveDispWait 与 actWalkFollow(Wait) 走同一行走状态、同一规则（static-derived）。
- 重制 `OpeningStoryObjects._start_story_walk`：Wait 变体先 `OpeningCinematics._centre_camera_on_walker`（演员像素、步进 16、容差 4）缓动，到位后由 `BattleOpeningCoordinator._defer_walk` 开走并跟随（`_walk_follow` 的 Wait 形式同此）；不带 Wait 的行走不请求镜头。`OpeningCinematics.camera_scroll_seconds` 逐 tick 模拟 `0x45e80d`，`BattleOpeningCoordinator.walk_pixels_per_tick` 用 `0x4543d8` 表，`BattleCameraController.focus_centre`（点＋(0,48)）与 `scroll_to(目标, speed, 1)` 照原点位（static-derived）。
- 差异：秒数取 16 ms/tick 设计值而非本机 19.4 ms（provisional）；插入演员「拉进画面」是重制补充（remake-invented）；actScrollBGToRandomPos 未读。

## 证据

EXE `hsl01.exe` sha256 `f0b5f835…`，只读反汇编／反编译，未做有界执行。

### 三条镜头入口（static-derived）

| 入口 | 谁调用 | 读法 |
| --- | --- | --- |
| `0x43bf30(obj, flag)` 居中缓动 | 剧情 VM `0x450840` 的 actScrollBGToPos／ToObject 阶段（case 0x13／0x14，经伪对象 `0x4c3860`）；脚本行走 `0x453b90` 状态 0x32 sub 0／1（`0x453d44 cmp [ebx+0x50], 0` → 仅 **Wait 变体**，`0x453d4b call 0x43bf30`）；经验结算 `0x442720`、共用施法序列 `0x442a90`、玩家对象过程 `0x443330` 与 AI 过程 `0x43ede0` 的对准（全部 51 个调用点见 [镜头包 §1](../runtime_observations/camera_panel_motion/README.md)） | 目标 = 对象像素 (`+4`,`+8`) − (0x140, 0xc0)（`0x43bf71`／`0x43bf76`：把对象放在 640×384 地图视口正中），夹到 `[0, *0x4c0958]`／`[0, *0x4c095c]`；`flag & 0x7fffffff != 0` 时 `0x46be92` 直接落位。否则每 tick：步长 `0x20`（`0x43bffa`），`*0x4c1b00 & 0x4000000`（剧情阶段位）时 `0x10`（`0x43bfff`／`0x43c007`），`*0x4c6390 & 0x600` 或 `*0x4c1d78`（快进）再 `+0xc`（`0x43c022`）；`0x45e80d(cur, target, tol 4, step, &next)`（`0x43c030 push 4`）→ `0x42dc50(next − cur)` 累计滚动请求（`0x43c064`／`0x43c091`）；到位返回 1 并清 `+0x80` 的 0x8000 锁 |
| `0x43c140(tx, ty, speed, &state)` 定速滚动 | actScrollBGToPosSpeed（case 0x4b） | 同一目标换算与夹取，`0x45e80d(..., tol 1, step = speed)`；到位 `0x46be92` 落位返回 1 |
| `0x42dc50(dx, dy)` 滚动请求累计 | 上两者与走路跟随 | 只加到 `0x4c1b98`／`0x4c1b9c`，不直接写镜头 `0x4c091c`／`0x4c0920`（[机制审计 §3](original_mechanics_audit.md) 52 组完整返回）；主循环 `0x42d8a8..0x42d8b5` 每帧把累计量交给引擎 `0x46bede` 并清零 |

**步进函数 `0x45e80d(cx, cy, tx, ty, tol, step, &nx, &ny)`**：`|tx−cx| <= tol && |ty−cy| <= tol` → 到位（返回 1，next = target）；否则**逐轴** `delta = clamp((t − c) >> 1, −step, +step)`，即每 tick 走剩余距离的一半、上限 `step` 像素——远处线性 `step`／tick，近处指数缓出，最后一步由 `tol` 吞掉。剧情阶段的居中缓动因此是「16 px／tick 直到剩余 < 32 px，然后 16→8→4→2，剩 ≤4 时落位」；两轴独立，斜向目标不是直线而是先对角后单轴。`0x46bede` 引擎侧只做加法与地图范围夹取（[tick 计数 §3](original_tick_counts.md)）；边界全局 `0x4c0960..0x4c096c` 为常量 320／240／地图宽−320／地图高−240（[镜头与面板动效](../runtime_observations/camera_panel_motion/README.md)）。

### 剧情 VM 的 token（`0x450840`；参数 resource-derived）

| token（ACTION.H） | opcode 分派 | 阶段 |
| --- | --- | --- |
| `actScrollBGToPos x y`（19） | case 0x13：`+0x8c = 0x130000`，存 x／y | 阶段 0：`*0x4c3864/*0x4c3868 = (v & ~0x1f) + 0x10`（格心），清 `*0x4c38e0`；阶段 1：每 tick `0x43bf30(0x4c3860, 0)`，返回非零才前进 |
| `actScrollBGToObject code serial`（20） | case 0x14：存 code／serial | 阶段 0：`0x44fad0` 找对象，取其像素进 `+0x9c/+0xa0`，转入 0x13 的阶段 |
| `actScrollBGToPosSpeed x y speed`（75） | case 0x4b：多存 speed | 阶段 0 同 0x13；阶段 1：`0x43c140(*0x4c3864, *0x4c3868, speed, 0x4c38e0)` |
| `actWalk*`（2–7）／`actWalkDisp*` | case 2..7：`0x44fcf0`（绝对格）／`0x44fd90`（**Disp = 相对当前像素的位移**，不是「显示」）把目的格心写进对象 `+0x4a/+0x48`，速度写 `+0x98`，Wait 变体把 VM 指针写 `+0x50` | 走路本体在 `0x453b90` 状态 0x32（下节） |

case 0x61（actSetBGToPos）用原值、case 0x15（actSetBGToObject）`0x43bf30(对象, 1)` 用原始点落位，都把点放在视口 (320,192)。

脚本语料（`content/imported/hsl/story_corpus/scripts/`，resource-derived）：actScrollBGToPos 出现于 56 个脚本、actScrollBGToObject 22、actScrollBGToPosSpeed 18、actScrollBGToRandomPos 1（STORY037，未读）、actWalkDisp／DispWait 34／33。**STORY051（第一战开场）没有任何 actScrollBG token，只有 `actWalkDispWait SID_PLAYER0 1 0 -96 2`**——第一战的镜头曲线全部来自下节的走路跟随。

### 脚本行走的镜头跟随（`0x453b90` 状态 0x32）

| sub | 读法 |
| --- | --- |
| 0 | `+0x50 != 0`（Wait 变体）→ 先 `0x43bf30(actor, 0)` 把镜头缓动到以演员为中心（上节曲线），到位才算路径 `0x4111d0(actor, dest, 0x12, 0xc)`；非 Wait 变体跳过居中 |
| 1 | 同样先居中（`0x453de6`），再取形态帧 |
| 2 | 速度换算（跳转表 `0x4543d8`）：speed 1 → 1 px／tick、帧延迟 6；2／3 → 2 px／tick、延迟 4；0／4／其他 → 4 px／tick、延迟 2；8 → 8 px／tick、延迟 1；`+0x9e = 0x20 / 步长` = 每格 tick 数（`0x453eb8`） |
| 3／6 | 每 tick 演员亚像素偏移 ±步长；**Wait 变体且演员越过屏内边界 `*0x4c0964`／`*0x4c096c` 时 `0x42dc50(0, ±步长)`（`0x454039`）**——镜头以与演员相同的 px／tick 跟着走；非 Wait 变体镜头不动 |

同一组 sub 的其他入口（`0x453b90` 状态跳转表 `0x45432c`：0x32→`0x453d27`、0x33→`0x453bd6`、0x34→`0x453bf7`、0x35→`0x453c62`、0x36→`0x453d01`）：

- actWalkAndDelete(Wait)：`0x450450` 写 `+0x50`（Wait 时 VM 指针）并置 `+0x8c = 0x360063`；状态 0x36 的 sub 表（字节表 `0x454354`→`0x454340`）sub 0x63 置 sub 0，sub 0..6 跳回 `0x453d27` 的行走 sub——居中与跟随同样只看 `+0x50`；sub 7 置 `+0x28 = 16`，sub 8 数完 16 tick 才放行 VM 并删除对象。
- actMoveDispWait：`0x4501f0` 同样写 `+0x50` 并进状态 0x32（见 [tick 计数 §4](original_tick_counts.md)），镜头规则相同。
- actWalkFollow(Wait)（opcode 0x32／0x33）：见下节，从 sub 1 进同一组 sub，镜头规则相同。
- 不带 Wait 的形式 `+0x50 = 0`：sub 0 跳过 `0x43bf30`（`0x453d47`），跟随不请求，镜头停在原处。

### actWalkFollow／actWalkFollowWait（`0x44ff50`，static-derived）

| 项 | 读法 |
| --- | --- |
| opcode | VM 处理器表 `0x4537f4`：0x32 actWalkFollow → `0x450a3c`，当 tick 调 `0x44ff50(code, serial, 领队 code, 领队 serial, speed, 0)`；0x33 actWalkFollowWait → 共用存参 `0x45136a` 进 VM 状态 0x33，阶段 0 `0x452ddf cmp ax, 0x33` 把 VM 指针作第 6 参（`0x452dec`）再调 `0x44ff50`（`0x452e12`） |
| 置位 | `0x44ff50` 找跟随者与领队（`0x44fad0`）；跟随者 `+0x8c != 0`（正忙）则什么也不做返回 0。否则目的 `+0x4a／+0x48` = 领队目的 + (跟随者像素 − 领队像素)，`+0x8c = 0x320001`（行走状态 0x32、**sub 1**），分配 0x194 字节并复制领队的路径缓冲 `+0x4c`（不另算路径），`word[+0x98]` = 第 5 参（速度，0 → 4 px／tick），`+0x50` = 第 6 参 |
| 镜头分支 | 与 actWalkDispWait 只差入口 sub：跳过 sub 0 的算路径，sub 1（`0x453ddf`）同样 `cmp [ebx+0x50], 0` → Wait 时 `0x453de6 call 0x43bf30(跟随者, 0)` 居中到位才往下走；sub 3／6 越界跟随同查 `+0x50`（`0x454039`）。不带 Wait 时两处都跳过，镜头不动 |
| 等待条件 | 非 Wait：`0x450a3c` 调完即 `jmp 0x4511e9` 放行 VM。Wait：`0x452c14` 起 `0x44ff50` 返回对象且第 6 参非零时 VM 停在状态 0x33，由行走过程到达后放行；返回 0（找不到或跟随者正忙）则直接前进 |
| 样本关 | STORY058（沃斯菲塔王座廳，LEVEL058 剧情场）与 STORY060（王座廳・俘虜，LEVEL060 剧情场）各一对：`actWalkFollow SID_ENEMY024 4 SID_PLAYER0 1 0` 紧接 `actWalkFollowWait SID_ENEMY024 3 SID_PLAYER0 1 0`（速度 0 → 4 px／tick）；两名士兵随主角走，第二名的 Wait 让镜头先缓动到它身上再跟 |

重制 `OpeningStoryObjects._walk_follow`：Wait 形式经 `_start_story_walk` 先居中到跟随者、到位开走并 `_camera_follows_last_walk`，非 Wait 不请求镜头；速度取第 5 参。目的格同上式（领队起点代领队像素），路径由 `ScriptWalkPath.route` 自算而非复制领队路径缓冲（差异见边界）。

第一战开场（static-derived 读法，未原执行）：雷歐納德 的 `actWalkDispWait(…, 0, −96, 2)` 先让镜头按 16 px／tick 上限＋半程缓出居中到他身上，再以 2 px／tick 向北走 3 格（48 tick），镜头只在他要越过上边界 `*0x4c096c` 时同步上移 2 px／tick。静帧锚点即 雷歐納德 的居中目标 (x−320, y−192) 夹取后的值，不需要从录像猜。

runtime-measured 旁证：录屏 212.45 s AI 回合被对准的法师站在 (320,192)。

### 秒数换算

按 [原版 tick 率](../runtime_observations/original_tick_rate/README.md) 的 16 ms／tick（本机 Wine 实测 19.4 ms）：剧情居中缓动上限 16 px／tick＝**1000 px／s**（近处半程缓出，32 px 内 16→8→4→2 共约 5 tick≈80 ms）；脚本行走 speed 2＝2 px／tick＝**125 px／s**（一格 16 tick＝0.256 s），speed 4＝250 px／s，speed 8＝500 px／s，speed 1＝62.5 px／s；快进时居中步长 28 px／tick。

## 重制接线

| 重制 | 原读法 | 等级 |
| --- | --- | --- |
| `OpeningCinematics.camera_scroll_seconds` 逐 tick 模拟 `0x45e80d`（步进 16、容差 4） | 逐轴 `min(step, 剩余/2)`，剩余 ≤ 4 px 落位 | static-derived（[tick 映射表](../runtime_observations/original_tick_rate/tick_mapping.md) 行 27／28） |
| `BattleOpeningCoordinator.walk_pixels_per_tick` 用 `0x4543d8` 表；`OpeningStoryObjects` 的 Wait 行走按同一步长请求镜头（`0x453fbd..0x454039`） | speed → 1／2／2／4／8 px／tick | static-derived |
| Wait 变体（`actWalkWait`／`actWalkDispWait`／`actWalkPrevInsertObjectWait`／`actWalkAndDeleteWait`／`actMoveDispWait`／`actWalkFollowWait`）先 `_centre_camera_on_walker` 缓动到演员（`0x43bf30(actor, 0)`：演员像素、步进 16、容差 4），`_defer_walk` 在滑动 tick 过后开走，走路时按同一组边界逐 tick 跟随；不带 Wait 的变体不请求镜头 | sub 0／1／3／6 都查 `+0x50`（actWalkFollow 从 sub 1 进，`0x44ff50`） | static-derived |
| `OpeningCinematics.script_position_camera_centre`：位置 token 的点放在视口中心（重制 640×480 视口＝点＋(0,48)） | case 0x13／0x4b 先取格心再经 `0x43bf30` 放到 (320,192) | static-derived；普查 `run_camera_panel_motion_tests.gd`：82 次「位置镜头后插入的演员」旧读法（视口左上角）仅 12 次完整在画面内，新读法 81 次，余下 WINFAIL041 event 0 的水怪在原版读法下也只露脚——重制对插入演员加「拉进画面」（remake-invented） |
| `BattleCameraController.focus_centre`（点＋(0,48)）供战斗对准、结算对准、位置／对象 token、对白与走前瞬切共用 | `0x43bf30` 对任何对象都把点放在 (320,192) | static-derived |
| `scroll_to(目标, speed, 1)` | case 0x4b → `0x43c140`，`tol 1, step = speed` | static-derived |

provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md`（`BattleOpeningCoordinator`、`BattleCameraController`、`OpeningStoryObjects`、`OpeningCinematics`、`BattleAftermath`；测试 `run_camera_panel_motion_tests.gd`、`run_camera_panel_motion_tests.gd`）。

## 复现

`tools/godot.sh --headless --script tests/run_camera_panel_motion_tests.gd`（位置镜头与插入演员普查）；静态部分 `r2 -q -e scr.color=0 -c 'pd 90 @ 0x43bf30; pd 40 @ 0x45e80d; pxw 32 @ 0x4543d8; pd 60 @ 0x44ff50; pxw 32 @ 0x4543b8' hsl01.exe`。

## 边界

- 秒数取 16 ms 设计值，本机 19.4 ms 的体验时长不作目标（provisional）。
- 居中到位与开走之间原版可能差 1 tick（sub 0 到位当 tick 算路径，sub 2 起步），重制到位即开走。
- actWalkFollow(Wait) 的原版复制领队路径缓冲（同形平移），重制按目的格自算路径；领队已走出几步时原版取领队当前像素、重制取领队起点——镜头规则不受影响。actWalkAndDeleteWait 到达后原版再停 16 tick 才删（sub 7／8），重制的删除时机不在本读法内。
- `*0x4c1b1c` 对 `0x43bf30` 负 flag 的语义、actScrollBGToRandomPos、非剧情阶段（战斗中玩家光标）的镜头路径不在本读法内。
- 不支持的结论：旧的 0.6 s tween／160 px／s 与原版秒数一致。
