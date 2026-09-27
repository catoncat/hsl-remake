# 幻火的地图演出：原版录屏与原生 effProc 轨迹逐帧对照

> evidence: runtime-measured: 2026-09-24 原版录屏 471.6–474.6 s 帧（落光首现、火团与光球爆散的时刻、落光下落速度、特效原点）; static-derived: 对照的另一侧是 content/generated/hsl/skills/effect_motion.json 的原生轨迹; provisional: 六团火的随机位置与落光摆动相位 · status: live · tools: hsltools/probes/effect_motion.py, run_skill_effect_script_tests.gd · updated: 2026-09-27

## 结论

- 原版幻火（effCode23）在地图上的时序与运动：落光首现到第一团火 0.95 s、到 FireBomb2 光球爆散 2.13 s，落光约 56 px/s 下落，特效原点约 (326,190)、比目标格中心高约 2 px（runtime-measured）。
- 重制 `game/battle/scene/SkillEffectScriptPlayer.gd` 经 `EffectObjectMotion.gd` 回放 [原生 effProc 轨迹](../../static_reverse/original_effect_motion.md)：50 tick、112 tick、每 tick 1 px，按本机 19.4 ms/tick 换算与录屏一致（static-derived）。
- 差异：六团火位置与落光摆动相位各取随机数，录屏与轨迹不同是预期（provisional）；像素级亮度不宣称一致。

## 证据

**runtime-measured**（原版侧唯一记录）

- 录屏：`录屏2026-09-24 中午12.03.22.mov`（私有档案，只读），游戏区 `crop=1280:960:112:140` 缩到 640×480；第一战敌方帝國法師（026）对桥上一般兵放幻火，471.6 s 镜头滚到目标并压暗地图，474.3 s 出现受损血条。
- 抽帧：ffmpeg 30 fps（471.0–474.6 s）；对照渲染把原生轨迹按加法混合画在 471.72 s 的压暗底图上（底图里录屏自己的落光像素已抹去）。

| 量 | 录屏 | 原生轨迹 | 判定 |
| --- | --- | --- | --- |
| 落光首现 → 第一团火首现 | 471.70 s → 472.65 s（0.95 s） | 50 tick | 本机 19.4 ms/tick（[tick 率](../original_tick_rate/README.md)）下 0.97 s，一致 |
| 落光首现 → FireBomb2 光球爆散 | 471.70 s → 473.83 s（2.13 s） | 112 tick（FireBomb2 在 100 插入，第 12 次调用抛 164 光球） | 19.4 ms/tick 下 2.17 s，一致 |
| 落光下落 | 顶边 471.87 s y=112 → 472.40 s y=142（约 56 px/s） | 每 tick 1 px（19.4 ms/tick 即 51.5 px/s） | 一致（落光换帧使顶边抖动 ±3 px） |
| 光球爆散 | 473.83–474.6 s：一个大光团后 10 余颗光球四散、逐渐变暗 | 12 颗 Spray（FIR04，2 倍缩放）匀速四散，七张后 engMIX 淡出 16 级 | 一致 |
| 特效原点 | 落光首帧中心 y≈101–103 | 首个可见帧在原点上方 88 px | 原点 ≈ (326,190)，比目标脚下（y≈204）高约 14 px；脚下在锚点（格中心）下约 12 px，即比格中心高约 2 px（[地图普攻与受击包 §2](../../static_reverse/original_map_strike.md#2-录屏对照)），与静态读法"目标格中心"一致 |

录屏（上）与原生轨迹（下）（原版帧见私有档案：`runtime_observations/effect_motion/huanhuo_recording_vs_native.png`）

上排录屏、下排原生轨迹（按 19.4 ms/tick 对齐到 471.68 s = tick 0）：tick 2–34 落光摆动下落，52–70 六团火升起并缩小，114–122 FireBomb2 的光球爆散，135–150 光球四散淡出、SprayUpDown 小火花沿抛物线落下。

**static-derived**：对照侧是 `content/generated/hsl/skills/effect_motion.json`；原点由 `0x443087` 取目标对象坐标（格中心），见 [地图普攻与受击包](../../static_reverse/original_map_strike.md)。

## 重制接线

- `game/battle/scene/SkillEffectScriptPlayer.gd` layout：效果对象及其派生火花／子弹／残影按原生 effProc* 轨迹经 `EffectObjectMotion` 绘制；effInsertRandomObject 的偏移由 rand(range) 折算（`0x4238b1`）。
- provenance 写法：`runtime-measured docs/evidence_packets/runtime_observations/effect_motion/README.md`。

## 复现

不可再生：原版侧唯一记录（录屏读数）。轨迹侧：`python3 tools/hsl.py check effect_motion`。

## 边界

- 不证明像素级亮度一致（录屏经 cnc-ddraw 与缩放；Godot 加法混合不是 RGB565 饱和加法）。
- 录屏只有这一次幻火；其余法术的等价性来自原指令执行本身，没有逐个录屏对照。
