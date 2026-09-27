# 地图物件云漂移（mapobjCloud）与移動背景视差（mapobjMoveBG）

> evidence: static-derived; runtime-measured: 整镜像进 1／2／6／53 关停首次排序后的逐帧坐标、出界回绕与镜头视差; resource-derived: TYPE.H 的 mapobj 编号与各关 OBS 的角度／速度／范围字段 · status: live · functions: 0x43ccf0, 0x45eb9d, 0x45ebdc, 0x45f5f7, 0x45fa1e, 0x4606a9 · tools: hsltools/probes/_map_object_drift.py · updated: 2026-09-27

本包回答：云每 tick 走多少、朝哪、出界后怎么回来、云影是否跟着走；移動背景同三问。EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。tick 按 [tick 率包](../runtime_observations/original_tick_rate/README.md) 的设计值换算：1 tick ＝ 16 ms ＝ 62.5 tick/s（本机 Wine 录像 19.4 ms/tick，同一 px/tick 在录像里约为下表 px/s 的 0.82 倍）。

## 结论

| 问题 | 云（mapobjCloud） | 移動背景（mapobjMoveBG） |
| --- | --- | --- |
| 速率 | 每 tick 位移 `(cos_tab[obj_Data7]·obj_Data8) >> 16` 与 `(sin_tab[…]·…) >> 16`（1/65536 px，小数累加）；第 1／6 关 雲／雲影 各轴 11585/65536 = **0.1768 px/tick ＝ 11.05 px/s**（斜向 15.6 px/s） | **不随时间动**：没有速度字，位置只由镜头决定 |
| 方向 | 角度 256 等分，0 = 右（+x），64 = 下（+y）；第 1／6 关 32 = 右下；第 2 关 96 = 左下；第 53 关 霧 0 = 右、128 = 左 | 随镜头同向移动 `obj_Score/640`（横）与 `obj_HitPoint/480`（纵）；−1 = 钉在画面上 |
| 出界 | 每 tick 移动后逐轴检查：图左缘越过地图右缘（`x > X2 + 原点x`）就 `x −= X2 + 宽`，右缘越过左缘（`x < X1 − 宽 + 原点x`）就 `x += X2 + 宽`；纵向同理——**回绕**，贴着对边外侧重新进场，不回起点 | 不适用 |
| 同速？云影联动？ | 同一模板同速；同关不同模板可不同（第 2 关 雲01 0x5000、雲02 0x4000）。雲影是独立对象、模板角度速度与雲相同所以同步平移，**没有指针联动**，各按自己的尺寸回绕 | — |

## 静态读法（static-derived）

**分派**：`defProcStandObject`（PROCESS.DEF 2）→ 过程表 `0x477c34` → `0x43ccf0(obj, msg)`；`obj_Data9`（+0xac，TYPE.H：`mapobjCloud 3 // objsData7 = angle, objsData8 = speed`，`mapobjMoveBG 6 // objsScore = x range, objsHitPoint = y range`）在 `0x43ce83` 减一后查跳表 `0x43d8c0`：3 → `0x43ceba`，6 → `0x43d4c1`。字段偏移按 OBS 装载 `0x45dc5c`（[字段覆盖](original_field_coverage.md)）：obj_X1..Y2 +0x10..+0x1c、obj_Score +0x84、obj_HitPoint +0x88、obj_Data7 +0xa4、obj_Data8 +0xa8。对象执行器 `0x45f5f7` 每个主循环调一次，所以云从进关起（剧情段与战斗段一样）每 tick 走一步。

**云初始化**（消息带 `0x20000000` 的首次调用，`0x43cdc4..0x43ce4d`）：清该位、置 `0x100000`；`+0xa8 ≠ 0` 时 `0x45eb9d(angle, speed, obj+0x34)`：`vx = (cos_tab[angle]·speed) >> 16`、`vy = (sin_tab[angle]·speed) >> 16`，两轴小数字清 0。表 `0x4a35fc`／`0x4a39fc` 各 256 个 dword，512 项逐项等于 `round(cos/sin(2π·a/256)·65536)`（四舍五入离 .5 最近也有 0.04，无歧义）。范围恰为模板默认 `0, 0, 640, 480` 时换成 `0, 0, [0x4c0948], [0x4c094c]`（地图宽高；实测见下）；否则 obj_Mode 置 `0x1000000`。起点就是 EVEF 坐标。

**云每 tick**（`0x43ceba` 置局部旗后进公共尾 `0x43d76a`）：
1. `+0xae` 倒数（见「隐藏」）为 0 时，`+0xa8 ≠ 0` 才走 `0x45ebdc`：每轴 `sum = v + frac`、`frac = sum & 0xffff`、`d = sum >> 16`（算术右移），`x += dx`、`y += dy`。
2. 同一块里 `0x4606a9(shape +0x30)` 取帧描述（SHP 装载 `0x45fa1e` 写：+4 = 头 +0x18 高、+8 = +0x14 宽、+0xc／+0x10 = +0x1c／+0x20 绘制原点），`0x43d7e0..0x43d848` 逐轴回绕：`x > X2 + ox → x = x − X2 − W`；否则 `x < X1 − W + ox → x = x + X2 + W`；`y` 用 `Y2／H／oy` 同样。周期用的是 `X2 + W` 而非 `X2 − X1 + W`（全部云的 X1 = Y1 = 0，见普查）。
3. 云的局部旗使它跳过尾部 `0x43d84b` 的全局物件色模式（`[0x4c1cc0]`／`[0x4c1cc4]`）——其他站立物件受它影响，云不受。

**隐藏**：云分支在 `[0x4c1b00] & 0x1400000` 或 `[0x477c14]` bit0 为 0 时写 `+0xae = 2`；公共尾 `+0xae` 减一后仍非零就 `+0x80 |= 0x10000000` 并返回（`0x43d202`，本 tick 不移动）；绘制段 `0x45f716` 见该位不画并清位。所以条件成立期间云不画也不走，条件解除后再过一 tick 恢复。`0x1000000` 由效果 VM `0x442a90` 置／清（[光标包](../runtime_observations/game_cursor/README.md) 同一位）；`0x400000` 的写者未追。`[0x477c14]` 初值 3（bit0 置位），系统选项面板的第一个开关（`0x4247f6` 登记处理函数 `0x424560`，按 `0x445f60` 的结果置／清 bit0）改它；开关文字是图片 0x319–0x31c，未认出是哪一项。

**移動背景**（`0x43d4c1..0x43d573`）：初始化时 `+0x92 = x`、`+0x90 = y`（EVEF 起点 x0、y0）。每 tick：`obj_Score ≠ 0` 时 `x = (score == −1) ? camX : x0 + trunc((camX − x0)·score / 640)`；`obj_HitPoint ≠ 0` 时 `y = (hp == −1) ? camY : y0 + trunc((camY − y0)·hp / 480)`。`camX／camY` 是镜头 `[0x4c091c]／[0x4c0920]`（视口左上角的地图像素，[存档格式](original_save_format.md)）；`/640` 由 `imul 0x66666667` 后 `sar 8`、`/480` 由 `imul 0x88888889` 加回被乘数后 `sar 8`，再加符号位——向零截断。随后进公共尾，但 `+0xa8 = 0`，不走、不回绕。镜头范围 `[0, [0x4c0958]]／[0, [0x4c095c]]` ＝ 地图 − 640／地图 − 480。结果：镜头走 640 px，图只跟着走 `score` px，在画面上相对滑过 `640 − score` px——远景层；`−1` 的图始终贴在画面左上角。

## 各关实例（resource-derived，hsl.pak 全部 OBS 普查）

| 模板 | 关 | 角度 | 速度 | v（1/65536 px/tick） | px/s（62.5） |
| --- | --- | --- | --- | --- | --- |
| 雲 CLOUD101、雲影 CLOUD102 | 1、6 | 32 | 0x4000 | +11585, +11585 | 右 11.05、下 11.05 |
| 雲01 cloud103 | 501–503 | 96 | 0x5000 | −14482, +14481 | 左 13.81、下 13.81 |
| 雲02 cloud104 | 2、501–503 | 96 | 0x4000 | −11586, +11585 | 左 11.05、下 11.05 |
| 霧01 fog01 | 53 | 0 | 0x5000 | +20480, 0 | 右 19.53 |
| 霧02 fog02、霧03 fog03 | 53 | 128 | 0x4000 | −16384, 0 | 左 15.63 |

34 个 mapobjCloud／mapobjMoveBG 模板块都不写 obj_X1..Y2，云的范围一律是地图全幅。移動背景：LVL04_01（2、501–503）180／100；LVL19_01（19、525–527、904）360／240；LVL22_1（22、570–572）180／240；39_BG001（39、561–563）340／240；LVL03_01（53）−1／−1、LVL03_02（53）240／80（obj_Score／obj_HitPoint）。

## 整镜像实测（runtime-measured）

`tools/hsltools/probes/_map_object_drift.py`（诊断，不注册任务）：`_enemy_level.round_sort_machine` 让原映像经 `0x42da60` 进关停在首次排序 `0x407340`（第 1 关已跑 3184 帧开场）。机器的形状装载是桩，停点之前帧描述为空（`0x4606a9` 给 0，停点坐标带着按裸地图尺寸的回绕，不是原版值）；探针在停点按 SHP 头装入帧描述后再测。

- **范围**：四关全部云的 +0x10..+0x1c 为 `0, 0, 地图宽, 地图高`（1：1280×1120；2：768×640；6：1120×896；53：1024×1376），即默认值被替换。
- **速率**：第 1 关原帧循环再跑 1499 帧，四朵雲／雲影各 +265, +265，逐帧步长只有 0 或 1（1499 × 11585 / 65536 = 265.0）；第 2 关 雲02 250 帧 −44, +44；第 6 关同第 1 关；第 53 关 霧 250 帧 +77（0x5000）／−63（0x4000，128）。
- **回绕**（放到出界边缘后直接调 `0x43ccf0`）：第 1 关 雲（560×318，原点 280,159）起点 (1560, 1279)，第 6 tick x 1561 → −279、y 1280 → −158；雲影（580×322，原点 290,161）1571 → −289、1282 → −160；第 2 关 雲02（554×450，原点 226,230）x −329 → 993、y 871 → −219；第 53 关 霧01 1202 → −270、霧02 −190 → 1246。
- **视差**：第 2 关 移動背景01（起点 137,0；180／100）镜头 (0,0)→(99,0)、(128,0)→(135,0)、(0,160)→(99,33)、(128,160)→(135,33)、(64,80)→(117,16)；第 53 关 LVL03_02（240／80）(384,896)→(144,149)，LVL03_01（−1／−1）坐标始终等于镜头。

复跑：`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_map_object_drift.py --level 1 --ticks 1500 --out ignored/clouddrift/L001.json`（首次建停点缓存约 20 s）。

消费者：`game/battle/runtime/MapObjectDrift.gd`（经 `game/battle/scene/BattleSceneStage.gd` 挂到云与移動背景的精灵上）。
