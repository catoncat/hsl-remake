# 原版逻辑 tick 率：设计 16 ms（1000/60 整除）、本机 Wine 实测 19.4 ms

> evidence: static-derived: frame pacer and per-tick dispatch; runtime-measured: live pacer registers, tick counting, walk and idle cadence; resource-derived: cnc-ddraw configuration · status: record-only · functions: 0x42c110, 0x42d240, 0x42d280, 0x42da60, 0x457830, 0x458760, 0x45f4b9, 0x45f50d, 0x45f5f7 · tools: hsl_runtime_probe.py, hsl_win32_memread.c · updated: 2026-09-22

lane R24-tick-rate（2026-09-22）。回答一个问题：原版「一个逻辑 tick」是多少毫秒——它是 `aniDelay`／`actDelay`／对象 `shape_delay`、脚本离场的 16 tick、资源恢复数字的 40 tick、`defProcGameOverBOSS` 的 60 tick 等一切计数的单位。EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，原作 v1.06，Wine 11.0，cnc-ddraw `renderer=gdi`。

## 结论

| 量 | 值 | 层级 |
| --- | --- | --- |
| 设计 tick 周期 | **16 ms**（`1000 / 60` 无符号整除；不是 16.667）→ 62.5 tick/s | static-derived（`0x45f4b9`），runtime-measured（周期寄存器 `0x4a41fc` 在标题 12 个样本全读得 16） |
| 本机 Wine 实测 tick | **19.40 ms**（1654 tick / 32.08 s，战斗待机；标题拟合 18.3 ms）→ 51.6 tick/s | runtime-measured；偏离原因是本机 `GetTickCount` 步进粗（见下），不是游戏逻辑 |
| 一次主循环 = 一个 tick = 每个对象过程调用一次 | 是 | static-derived（`0x42da60`→`[0x4c1b24]`=`0x42d600`→`0x45f5f7`） |
| 逐帧绘制可跳、逻辑不跳 | 落后 ≥2 周期时最多连跳 6 帧不呈现，逻辑仍每圈一 tick | static-derived（`0x45f50d` 参数 6）；本次实测跳帧计数 `0x4a4208` 始终 0 |

**给替换 lane 的换算**：原版 N tick ＝ N × 16 ms（设计值）。用户在本机 Wine 上实际看到的时长是 N × 19.4 ms（慢 21%）；参考录像包 `original_gameplay_reference` 也是这台机器录的，用它量出的秒数应按 19.4 ms/tick 折回 tick，再乘 16 ms 才是设计时长。哪个作为重制目标是产品决定（见「边界」）。

## 静态读法（static-derived）

主循环与节拍器全部围绕 `GetTickCount`（唯一计时导入；`timeSetEvent(250,250,0x459f60)` 是 DirectSound 流缓冲回填，与逻辑无关）：

| 函数 | 作用 |
| --- | --- |
| `0x457830` game_time_ms | `GetTickCount() − [0x4c2310]`；`0x4c2310` 是失焦暂停累计（`0x458760` 在 `0x4c22d8` bit 0x20 置／清时用 `0x4c2314` 记起点）。游戏时钟 = 墙钟减暂停。 |
| `0x45f4b9(fps)` frame_pacer_set_rate | `[0x4a41fc] = 1000 / fps`（`div`，整除）；`[0x4a4200] = now`；`[0x4a4204] = 0`。**全部 50 个调用点都传 60** → 周期恒为 16 ms。 |
| `0x45f50d(max_skip)` frame_pacer_wait | 入口 `elapsed = now − last + carry` 写 `[0x4a420c]`；若 `< period` 则忙等 `while (now − last) < period`（忙等条件不含 carry），退出后 `carry = (now − last) − period`、`last = now`、`skip = 0`、返回 1（呈现）；若 `≥ period`：`last = now`、`carry = elapsed − period`；落后不足两个周期→返回 1；落后 ≥2 周期→ `skip++`，`skip ≤ max_skip` 时返回 0（本帧不呈现、逻辑照跑），超过则强制呈现。 |
| `0x42d280` present_frame_if_due | `push 6; call 0x45f50d`；返回非零才锁面／blit／flip（`0x457d40`／`0x457ca0`／`0x4613a6`／`0x46b821`／`0x457de0`／`0x457e00`），`[0x4c1b1c]=1` 标记已绘。 |
| `0x42da60` main_loop | `0x42dbf5: call [0x4c1b24]` 循环直到退出；`0x4c1b24` 由 `0x42d7a0` 设为 `0x42d600`。 |
| `0x42d600` 帧体 | 依次：`0x42dc80` 清滚动请求、`0x42c110` UI 脉冲计数、`0x42d240` 游玩秒计数、`0x415910` 键盘扫描、影片检查、`0x46141c` 清精灵表、`0x45f5f7(0)` **对象过程执行器**（遍历优先级链表 `0x4a35ec[0..0x4a35f4]`，对每个对象调用 `0x4a19bc[obj+0x64](obj, flags)` 一次）、`0x460a06` 光标、`0x42d280` 节拍＋呈现、`0x46bede` 滚动。 |
| `0x42c110` ui_pulse_counter_step | `[0x4c1c70]++`，`> 16` 时回 `−16`：33 tick 一周的三角波，`0x42c130` 用 `|v|×2` 做菜单／光标亮度脉冲（18 处调用）。**它是每 tick 加一的计数器，本包用它数 tick。** |
| `0x42d240` play_time_seconds_step | 游戏时钟每满 1000 ms `[0x4c1bc0]++`（存档里的游玩时长）。 |

因此：对象过程里的 `shape_delay` 递减（`0x45e5a6`）、ANIMAL `aniDelay`（`0x4022aa`）、STORY `actDelay`、离场 16 tick（`0x454286`）、`defProcShowNumber` 等全部以「主循环圈」为单位；一圈的设计长度是 16 ms。

`ddraw.ini`（resource-derived，未改动）：`maxfps=-1`、`vsync=false`、`maxgameticks=0`、`limiter_type=0`——cnc-ddraw 不节流游戏循环，测得的节拍完全由游戏自身的 `0x45f50d` 决定。

## 运行时测量（runtime-measured）

方法：`tools/build_runtime_helpers.sh --win32-rpm` 后，用 `hsl_win32_memread.exe --repeat N --interval-ms M`（本 lane 新增的重复采样：同一进程内 `Sleep` 间隔读同一组地址，附 `GetTickCount`／`QueryPerformanceCounter` 主机时间戳）只读采样；`hsl_runtime_probe.py --read-backend win32-rpm` 做低频采样。不写内存、不改存档（四个 `.SAV` 前后 sha1 相同）。Wine 会话 01:42–01:58（约 16 分钟，超出任务书建议的 10 分钟：其中约 5 分钟耗在下文的录屏工具故障上）。raw 采样在 `ignored/tick-rate/`（不入库）。

### 1. 节拍器寄存器（标题 12 样本；战斗 300 样本）

标题：`0x4a41fc` 12 个样本全读得 `16`。标题与战斗：`0x4a4208`（跳帧计数）全部 0；`0x4a4204`（carry）0–6（战斗众数 4）；`0x4a420c`（入口 elapsed）标题 0–2 ms、战斗 4–6 ms（另有少量 16–20 是忙等结束后的写入被采到）——即帧体开销 0–6 ms，其余时间在忙等。战斗未重读 `0x4a41fc`，但 carry／elapsed 分布与 16 ms 周期一致。`play_seconds` 与主机墙钟同步推进（标题 21.8 s 内 34→54；战斗 32 s 内 605→636）。

### 2. 用脉冲计数器数 tick（战斗待机，300 样本 × 100 ms）

`0x4c1c70` 每 100 ms 前进 5 或 6（147／147 次，4 次 7，1 次 9），无歧义解包：

```text
1654 tick / 32080 ms (GetTickCount) = 32079.9 ms (QPC)  →  19.395 ms/tick = 51.56 tick/s
pace_last 跨度 32079 ms（帧边界时间戳与主机钟一致）
```

标题 12 样本（间隔 ~1.9 s，只能对 33 取模）对 15–26 ms 逐 0.02 ms 拟合，最优 18.3 ms/tick（帧体更轻，超调更小）。

### 3. 为什么实测不是 16：本机 `GetTickCount` 粒度

独立小程序在同一 Wine 前缀里忙读 `GetTickCount` 3 s：594 次步进，均值 5.0 ms/步，直方图 `1 ms ×235、2–8 ms ×159、9 ms ×76、10 ms ×117、11–12 ms ×7`。忙等条件 `now − last ≥ 16` 在粗步进的钟上平均超调 3–4 ms（战斗样本 carry 众数 4），而超调只进入 carry，忙等路径又不消费 carry → 每帧 ≈ 16 + 超调。这是宿主时钟效应：在 1 ms 粒度的时钟上（Win9x 时代的目标机）帧 ≈ 16–17 ms；在 15.6 ms 粒度的 NT 时钟上按同一算法会是 31.25 ms（static-derived 推论，未实测）。

### 4. 可对照的动画／等待时长样本

全部从内存按 tick 数出（录屏见「工具摩擦」），设计秒 = tick × 16 ms，本机秒 = 实测。

| # | 现象 | tick 数（实测） | 设计时长 | 本机实测 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 1 | 待机站立循环（雷歐納德、SID 20 号敌兵） | 6 帧 × 11 tick = **66 tick**（`+0x7c` 延迟 10→0 后换帧，`+0x78` 6→1 循环） | 1.056 s | 1.259 s（状态 tick 0 与 tick 66 逐字节相同） | 与 [actor_animation_groups](../../static_reverse/actor_animation_groups.md) 的静态读法（delay 10 → 11 次更新／帧）一致；重制 manifest 8 fps 应为 62.5/11 = 5.68 fps |
| 2 | 玩家移动一格 | **8 tick**：`obj+4` 每 tick +4 px，32 px 一格；3 格横走 96 px = 24 tick，随后 1 格纵走 32 px = 8 tick | 128 ms／格 | 155 ms／格（4 格共 32 tick ≈ 620 ms） | 行走帧 `+0x7c` 延迟 2 → 3 tick／帧（静态读法 delay 2 一致）；重制 `MOVE_CELL_PRESENTATION_SECONDS = 0.20` |
| 3 | UI 亮度脉冲（菜单／光标高亮） | **33 tick** 一周（−16…16） | 528 ms | 640 ms | `0x42c130` 的 18 个消费者共用 |
| 4 | 帧节拍 | 1 tick | 16 ms | 19.4 ms | 周期寄存器 16；跳帧 0 |
| 5 | 游玩秒计数 | 每 1000 游戏 ms +1 | 1 s | 1 s（与墙钟同步） | 证明游戏时钟＝墙钟−暂停；存档游玩时长单位就是秒 |
| 6 | 城门火焰 `obj_Shape_Delay=3`、10 帧 | 40 tick 一周（resource + static，本次未采样其对象） | 640 ms，15.6 显示帧/s | 776 ms | [gate_fire_animation](../../static_reverse/gate_fire_animation.md)；重制 60 更新/s 应为 62.5 |
| 7 | 脚本离场 16 tick／资源恢复 MP 数字延迟 40 tick／GAME OVER 保持 60 tick | 16／40／60 tick（static） | 256／640／960 ms | 310／776／1164 ms | [original_script_departure](../../static_reverse/original_script_departure.md)、[original_resource_recovery](../../static_reverse/original_resource_recovery.md)、[PRESENTATION](../../../architecture/PRESENTATION.md) |

### 5. 静态与运行时的一致性

一致：周期 16、每圈一 tick、待机 11 tick／帧、行走 3 tick／帧、脉冲 33 tick 周期均在内存中按静态读法出现。不一致且已解释：实测 19.4 ms ≠ 16 ms，来源是宿主 `GetTickCount` 粒度（第 3 节），不是游戏另有时钟。

## 复跑

```sh
tools/doctor.sh --original
tools/build_runtime_helpers.sh --win32-rpm          # ignored/bin/hsl_win32_memread.exe
tools/run_original_hsl.sh                           # 标题；戰場記錄 进第一战首次行动菜单
PID=$(wine tasklist 2>/dev/null | awk '/hsl01.exe/{print $2}')
wine ignored/bin/hsl_win32_memread.exe --pid $PID \
  --read-u32 pulse=0x4c1c70 --read-u32 pace_period=0x4a41fc --read-u32 pace_last=0x4a4200 \
  --read-u32 pace_carry=0x4a4204 --read-u32 pace_skip=0x4a4208 --read-u32 pace_elapsed=0x4a420c \
  --repeat 300 --interval-ms 100 > ignored/tick-rate/pulse.jsonl
# ticks = Σ((pulse_i − pulse_{i−1}) mod 33)；ms/tick = Δtick_ms / ticks
```

站立／行走取样：`0x4c34c0` 对象指针表（200 槽）取活对象，读 `obj+4/+8`（像素）、`+0x30`（形号）、`+0x78`（余帧）、`+0x7c`（延迟低字／重载高字），`--repeat 300 --interval-ms 25`，期间发一次 移動 目标点击。

## 边界

- 本包只证明「主循环节拍与 tick 单位」，不证明任何具体演出的帧内容、混色或坐标等价。
- 19.4 ms 是**本机** Wine 11.0 + macOS 的实测；不同宿主的 `GetTickCount` 粒度不同，原作在 1990 年代目标机上更接近 16–17 ms。重制该用 16（设计值）还是用户实际体验的 19.4，是负责人的产品决定；本包推荐 16 ms/tick（62.5 tick/s）为「原版设计时钟」，并把参考录像的秒数按 19.4 折算成 tick 后再对照。
- 未测：对白逐字节奏、`defProcShowNumber` 数字寿命、`mapobjFlash` 过程、菜单展开步进的 tick 数、脚本 `actWalk` 速度参数与像素/tick 的关系（玩家行走 4 px/tick 不自动等于脚本行走）。这些是「已知以 tick 计但计数未读」，见 [映射表](tick_mapping.md)。
- 36 格 remake-invented 时序的逐格换算见 [tick_mapping.md](tick_mapping.md)。

## 工具摩擦

- `hsl_record_window`（ScreenCaptureKit 单窗口录制）对 Wine 窗口只送出前 ~0.9 s 的 53 帧就停止（30／10／6 s 三次、`--no-audio` 也一样；Godot 窗口正常）。原因未定位（怀疑 winemac.drv 的窗口表面更新不被 SCK 视为内容变化）。本 lane 给它加了 `--no-audio` 选项（排除音频停滞假设，保留），tick 测量改走内存采样。若后续需要录屏，先用 Godot 窗口验证工具，再排查 Wine 窗口。
- `hsl_win32_memread.exe` 每次 `wine` 启动约 1.9 s，原先每次只能读一组值；新增 `--repeat`／`--interval-ms` 后可在进程内 25–100 ms 间隔连续采样，单次输出保持原格式（`repeat=1` 时无新字段）。
- 首次 `--dry-run`／`inspect` 在游戏窗口尚未创建时报 `game_window_not_found`，等 5 s 再查即可。误右键会打开系统卷轴（原版右键＝系统菜单），再点会落到 讀取戰場記錄 的 確定／取消——用 `key escape` 关卷轴。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/title/GameOverScreen.gd` timing：defProcGameOverBOSS 0x42aea0 holds 60 ticks = 0.96 s before it can be left; the fade-in spans that hold
