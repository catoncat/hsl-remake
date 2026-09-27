# ANIMAL 完整动作程序与分派计数

> evidence: resource-derived; static-derived · status: live · tools: hsl_native_animal_probe.py, hsltools/assets/animal_programs.py, hsltools/assets/combat_animation.py, run_skill_effect_script_tests.gd, test_hsl_animal_programs.py · updated: 2026-09-27

## 结论

- 原版：`data\ANIMAL.TXT` 的 66 个角色定义含 action 66／m_action 18／s_action 19 段、663 条有效指令（resource-derived）；过程表 slot 22 `0x401c20` 按 `0x4037b0` 分发表执行，Delay 装入与等待各占调用、SetShape 让出、InsertAttackFlash 同 call 继续取指，37 段施法引导全部是「位移→阴影底→移到中心→施法对象」同一形状（static-derived）。
- 重制：`hsltools/assets/animal_programs.py` 完整解析并核对原包，`combat_animation.py` 把 action 编成 `dispatch`、s_action／m_action 编成 `cast_program` 写进 combat manifest；`game/battle/scene/AnimalCastLead.gd` 按 handler 读法逐 call 播放施法引导，雷歐納德 139 call、緹娜 002 130 call（static-derived）。
- 差异：施法对象子状态 4 的过渡／外部释放、阴影底画法、第五帧受击绑定与切入背景布局是重制读法（provisional）；loader 的隐式结束符与 m/s 资源选择未读。

## 证据

### 源身份（resource-derived）

| 来源 | SHA-256 / 说明 |
| --- | --- |
| 本机 `hsl01.exe` | `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；其他版本立即拒绝 |
| 原包 `data\ANIMAL.TXT` | `e27783ef3148bad8523af95c7d111f1a3ed66c7c0844c7b7cfdabefb4ef9b4ea`；与已有完整导入文本逐字节相等 |
| 原包 `data\ANIMAL.H` | `88959ec91256978d74b9b10138cb12d4505e54789c6e0cfc3d52af0cc38a97e6`；逐字节相等（`.gitattributes` 按 byte-exact source 保留 CRLF） |
| 原包 `data\SHAPEDEF.H` | 原包 `7472343668711a1f9db825b3d72100ee11759a2dc55c212934a9d081bdb1ab1c`（4984 字节 CRLF）；导入 `73b5592fd2ba7d09d835b9ec0a72afd719a48e3f8219a7da9393a73586a1aee4`（4802 字节 LF）；只对这一来源做 CRLF→LF 后相等，JSON 记 `pak_comparison`，另两个来源为 `exact_bytes` |

### 从 header 到完整程序（resource-derived）

ANIMAL.H 定义 `aniOver=0`、`aniDelay=1`、`aniSetShape=7`、`aniSetZoom=9`、`aniSetXYDisp=10`、`aniInsertAttackFlash=11`、`aniShadowBG=12`、`aniMoveToCenter=13`、`aniInsertCastObject=14` 等，直到 35；参数数量来自各定义的 `// [参数]` 注释。`aniKStop/Right/Left` 是受击位移方向旗，不是动作 opcode。

| 内容 | 数量 |
| --- | ---: |
| `[animal]` 角色定义 | 66 |
| `action` 程序 | 66 |
| `m_action` 程序 | 18 |
| `s_action` 程序 | 19 |
| 有效指令 | 663 |
| 实际使用的 opcode 种类 | 11 |
| header 声明的 opcode 种类 | 36 |

解析保留 `action`／`m_action`／`s_action` 原字段名；重复同名行按原顺序追加；每条指令带 `op`、`opcode`、整数 `args`、原文 `arg_tokens` 与 `source_line`，负数和十六进制不经过浮点。拒绝未知字段／opcode、参数个数不符、非整数、超出 32-bit、重复角色或单值字段、缺 shape/count/program、越界 aniSetShape；缺省的 m_action／s_action 不从别的角色或通道补。

| 例子 | 原文 | 要点 |
| --- | --- | --- |
| 雷歐納德普攻（行 10–11） | `aniDelay,12 → aniSetShape,1 → aniDelay,8 → aniSetShape,2 → aniDelay,3 → aniInsertAttackFlash,-90,-120 → aniSetShape,3 → aniDelay,30` | 闪光在最后一次换帧之前；源里没有 aniPlaySound，不能据此说普攻无声 |
| 雷歐納德特殊技（行 14–15） | `aniSetXYDisp,-640,0` `aniShadowBG` `aniMoveToCenter` `aniInsertCastObject,-160,-150,2,6,6` | 位移、背景、施法对象整段保留 |
| PLAYER5（行 83–85） | 六条 aniSetZoom `0x00011000`..`0x00016000`，中间无 aniDelay | 每条各占一次调用（下文） |
| 其他 | PLAYER7 换帧多次回到 0／1；PLAYER9 旧闪光偏移被注释，有效值 `[-300,-60]`；Enemy026 的 m_shape／m_number／m_action 全被注释；Enemy024 无有效 fh_shape 但有 aniInsertAttackFlash | 不排序去重、不导入被注释的程序、事件与贴图绑定分开 |

第一战五类角色（SID_PLAYER0、SID_ENEMY021／023／024／026）的 `ANIMAL\Pnnn_001.SHP` 各 5 帧；第五帧（后仰／失衡）由重制绑定为受击姿态，是图像判读，不是原版受击 handler（provisional）。`obj-051.obs` 对象 199 绑定 `ANIMAL\BG051.SHP`（640×320，一帧），重制作第一战切入背景、y=80 不拉伸，上下黑边与结果位置是重制布局（provisional）。

### EXE 分派（static-derived）

过程表 `0x477c2c` slot 22 → `0x401c20`，slot 23 → AnimalDefense `0x4038a0`。`0x401f3b` 从对象 `+0xa4` 读程序指针，`0x401f41` 取 32-bit opcode 并前移 4 字节，`0x401f46` 检查 0..33，`0x401f58` 进 `0x4037b0` 表：

| opcode | 名称 | handler |
| ---: | --- | --- |
| 0 | aniOver | `0x402295` |
| 1 | aniDelay | `0x4022aa` |
| 5 | aniSetStopSpeed | `0x4023d5` |
| 6 | aniNextShape | `0x4023ef` |
| 7 | aniSetShape | `0x402415` |
| 8 | aniProcShapeToEnd | `0x402453` |
| 9 | aniSetZoom | `0x402476` |
| 10 | aniSetXYDisp | `0x402180` |
| 11 | aniInsertAttackFlash | `0x4021df` |
| 12 | aniShadowBG | `0x402499` |
| 13 | aniMoveToCenter | `0x4024c1` |
| 14 | aniInsertCastObject | `0x4024d3` |

完整表在 [animal_program_execution.json](animal_program_execution.json)。数个值落到共同路径 `0x402709`；34／35 不在本过程分发表内，header 的 36 条定义不等于 36 个已实现动作。`0x402278` 继续取后继 opcode 并可同一次调用再次分派；其余 handler 保存指针后跳共享尾部 `0x4034c6` 让出（r2 显示的 `jmp case.default.0x402a55` 实际目标是 `0x4034c6`）。aniSetShape 经可选残影调用后在 `0x40243d..0x40244e` 更新帧并让出；aniInsertAttackFlash 分支经 `0x402264` 进入继续取指。

### 原指令隔离执行（static-derived）

探针从 `0x401c20` 执行合成对象与 dword 程序，每次在共享尾部 `0x4034c6` 前停止，记录 phase、counter、cursor 与两个 zoom；每次最多 512 条指令、每组最多 64 次更新；EXE 哈希不符、跳入未检查的 callee、预算耗尽都失败，不给未知函数写 stub。

aniDelay：`0x4022aa..0x4022c6` 置 phase 1、D 写 `+0xa0`、保存后继指针并让出；phase 1 经 `0x402714` 每次减一，≤0 清状态后仍让出，下一次才读指令。程序 `[aniDelay,2,aniSetZoom,0x13000,aniOver]`：

| 调用后 | phase | counter | cursor word | zoom |
| --- | ---: | ---: | ---: | ---: |
| 初始 | 0 | 0 | 0 | `0x10000` |
| 第 1 次：装入 delay | 1 | 2 | 2 | `0x10000` |
| 第 2 次：等待 | 1 | 1 | 2 | `0x10000` |
| 第 3 次：等待归零 | 0 | 0 | 2 | `0x10000` |
| 第 4 次：执行 zoom | 0 | 0 | 4 | `0x13000` |
| 第 5 次：执行 Over | 101 | 0 | 5 | `0x13000` |

D＝0、1、2、12、30 都执行过：后继指令首次可见的调用下标为 `max(D,1)+2`（D＝0 也走一次等待，计数减为 −1）。这是调用下标，不是秒数，也不等同 SHP helper 的「D+1 次更新换帧」。PLAYER5 的六条连续 zoom 逐次写出 `0x11000`..`0x16000`（两轴同时），显式补的 aniOver 置 phase 101；原文不含 aniOver，资源 JSON 也不追加。

### 8. 施法引导程序（m_action／s_action）的解释

#### 8.1 逐通道 opcode 普查（resource-derived）

| opcode | op | action（66 段） | m_action（18 段） | s_action（19 段） | 解释状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| aniDelay | 1 | 255 | 0 | 0 | action：`compile_action`（setup 1 call ＋ max(D,1) 等待 call） |
| aniSetShape | 7 | 182 | 0 | 0 | action：`compile_action` → manifest `dispatch.poses`，切入按 update 换帧（`0x402415` 更新 +0x30 后让出） |
| aniInsertAttackFlash | 11 | 59 | 0 | 0 | action：同一 call 继续取指（`0x402264` → `0x402278`），release 标记 |
| aniSetSubSpeed／aniSetAddSpeed／aniSetStopSpeed | 4／3／5 | 4／1／1 | 0 | 0 | action：`compile_action`（002 起跳／落地，[原祭司](original_priest.md)） |
| aniSetXYDisp | 10 | 7 | 18 | 19 | action：`hsltools/assets/_mobile_animation.py` `compile_mobile_action`；m／s：`AnimalCastLead`（`0x402180`：位移加到 +4／+8，同 call 继续取指；`0x446be0` 为真时 x 取反——live 记录 `+0xa0 & 8`，obj_Data9 互换安装置位、actSetPlayerMode 每次翻转，重制读单位 `side_swapped`；普攻 action 同样取反，见[效果对象运动包 §4b](original_effect_motion.md#4b-普通切入的换边镜像cutin-mirror)）——consumed |
| aniSetZoom | 9 | 6 | 0 | 0 | action：`compile_mobile_action`（`0x402476` 写 +0x20／+0x24 并置 0x8000000） |
| aniShadowBG | 12 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x402499`：+0x80 \|= 0x1000、phase 12；`0x402752` 每 call +0x90，计到 bp=8 回 phase 0——共 1＋8 call）——consumed |
| aniMoveToCenter | 13 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x4024c1` phase 13；`0x402771` 每 call 调 `0x45e80d(x, y, base+0x140, base+0xf0, 16, 32)`，到达回 phase 0）——consumed |
| aniInsertCastObject | 14 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x4024d3` phase 102，见 8.2）——consumed |
| 其余 26 个 | — | 0 | 0 | 0 | ANIMAL.TXT 未使用（EFFECTS 脚本另计，见 field_coverage effect 列） |

37 段 m_action／s_action 全是 `aniSetXYDisp,±640,0 → aniShadowBG → aniMoveToCenter → aniInsertCastObject,-160,-150,[起始张],[delay1],[delay2]`；只有 056／059／060 的位移是 +640（从右侧进），其余 −640。

#### 8.2 施法对象 phase 102（`0x4024d3` → `0x402a3e`，static-derived 前段 ＋ provisional 尾段）

对象字段：+0x8e phase（= 触发它的 opcode 号；100／101／102／103 为普通开场／结束／施法对象／链接程序）、+0x8c 子状态、+0x30 当前张、+0x7a 张数、+0x7c／+0x7e 张停留计数／重装值、+0xa0 剩余数、+0x9c／+0x9e 局部图张／肖像张、+0x94..+0x9a 目标与当前坐标。

- 装载（`0x4024d3..0x402637`）：读 xdisp／ydisp／起始张 S／delay1／delay2。全局 `0x4c6f5c = max(S−1, 0)`（肖像张数），`0x4c6fa8 = delay2`（S−1 ≤ 1 时 +20，`0x402517`），`0x4c6faa = delay2`；+0x7c/+0x7e = delay1；+0xa0 = 张数 − S（局部图数）；+0x9c = 当前张(0) + S、+0x9e = 1。`0x4606a9(张, &ox, &oy, &w, &h)` 取该张 SHP 的原点与尺寸；**xdisp 只取符号**（`0x4025bc`：<0 → `0x4c6f64=1`）：局部图目标 x = base + ox + 100（xdisp<0，`0x4025c0`）或 base − w + ox + 540（`0x4025ff`），起点 = base − w + ox（画外左）或 base + 640 + ox（画外右）；目标 y = base + oy（上缘 0）。ydisp 未见读用。
- 子状态 0（`0x402a5c`）：画局部图，`0x45e80d(…,16,32)` 一步；到达 → 子状态 1。
- 子状态 1（`0x402afe`）：画；+0x7c−−，归零时重装 delay1、+0xa0−−；>0 则经 `0x401220` 留残影并 +0x9c++（下一张），≤0 → 子状态 2 并算肖像目标：y = base − h + oy + 480（下缘 480）；xdisp<0 时 x = base + 0x140（w > 440 居中，`0x402c19`）或 base − w + ox + 540（右缘 540），起点 base + 640 + ox；xdisp ≥ 0 时 x = base + ox + 100、起点 base − w + ox（`0x402c58`）。
- 子状态 2（`0x402c87`）：画局部图与肖像，肖像 `0x45e80d(…,16,32)` 一步；到达 → 子状态 3，+0xa0 = 10、+0x28 = 16、`0x4c6f70 = 0x20002`。
- 子状态 3（`0x402d79`）：画；`0x4c6fa8`−−，归零时重装 delay2、`0x4c6f5c`−−（≤0 → 子状态 4；≤1 → 重装值 +20）、+0x9e++（下一张肖像）。
- 子状态 4（`0x402e47`）：+0x84 计到 16 期间以 mode 0 ／>16 以 0x20000000 画（过渡），==16 时 +0xa0(10) 倒数，再看 `0x4c1408`：−1 → phase 101 结束；非零 → 作为新程序指针进 phase 103；0 → 继续等。子状态 5–9（`0x403089..0x4031c7`）本包未读。預備動作 关闭时走的子状态 5–9 见 [menus_ui 預備動作](../runtime_observations/menus_ui/README.md#預備動作0x477c14-bit1)。

**重制解释（`AnimalCastLead.compile`，每 call 一个状态）**：横幅（第 0 张，施法对象本身）从 (320,240)+位移 经 1＋8 call 阴影底、1 call 进 phase 13、逐 call `opening_step(…,16,32)` 到中心；1 call 装载；局部图自起始张滑入（每 call 先画后步）、每张停 delay1；肖像（第 1 张）滑入，第 1…S−1 张每张停 delay2、末张 +20；16 call 淡出＋10 call 停留后引导结束、EFFECTS 攻方脚本开始。雷歐納德（S=2，delay 6／6，条带 7 张）：9＋22＋1＋11＋30＋12＋26＋26 = **139 call**；局部图锚点 (217,92)、肖像锚点 (398,374)。

**已接上的相关读法**：残影 `0x401220`（aniSetXYDisp 作为一次 call 的首条指令时 `0x402187` 留横幅残影、子状态 1 每张局部图到期且还有下一张时 `0x402b68` 留局部图残影；对象 179 层级 6，defProcShadowLeft `0x4010c0` 每 4 call 减一、24 call 消失）与 `0x446be0` 换边镜像（`0x401ddf` x 缩放 −1、`0x4021b8` x 位移取反；单位 `side_swapped` 由组装按 obj_Data9≠0 写入），见[效果对象运动包](original_effect_motion.md)。普攻的 phase 100 开场是 24 tick 缩放（`0x401060` 步进表）＋ 32 tick 叠层，`0x436490(+0xa0, 3, 0)` 是切入身份栏的文字生成（→ `0x434d10` mode 3），不是放声，见 [tick 计数包](original_tick_counts.md)；守方 AnimalDefense `0x4038a0` 中立 32 tick、命中停留 68 ＋ 10×位数 tick、落空 56 tick，之后是未读长度的屏幕过渡（`0x46098f`）——`CombatPresentationTiming` 的 TARGET_PAUSE／hurt_hold 已 static-derived，RECOVERY 仍 provisional；`k_action`（aniKStop／Right／Left）是受击位移方向旗，不是程序。

**m_action 与 s_action 条带**：18 段 m_action 中 16 段的 `m_shape` 条（P0xx_101…，69 张 PNG，manifest 每行 `magic_frames`＋`magic_cast_program`，`MAGIC_FRAME_ACTORS`）已导入，地图法术 presenter（`SkillEffectScriptPlayer._present_effect`）先按同一 `AnimalCastLead.compile` 播放引导再走 effCode 脚本，`released` 在引导结束；緹娜 002（S=2，delay 4／4，7 张）引导 130 tick。未导入的两行：018（SHAPEDEF 走行行被注释、无战斗行）与 068 怨念（无走行组、无战斗行）；没有 m_action 的施法者（026 帝國法師 的 m_shape 被注释）与这两行用 `CombatPresentationTiming.CAST_LEAD_IN` 的 Cast_Star 替身（manifest `magic_cast_program_policy`，按角色列明）。s_action 有程序的行中，004／006／007／009／053／054／055／057 的 `s_shape` 条已导入（053 按 ANIMAL 块声明取 P009_201…204），引导同法播放；仍无条带的只剩 002（P002_201 条归 月花圓舞 导入、不进 combat manifest）与 018（无战斗行），按 manifest `cast_program_policy` 显示站立帧。056 的 ANIMAL 块无 s_shape／s_action，hsl.pak 亦无 P056_2xx（negative-evidence）。

## 重制接线

| 文件 | 用途 |
| --- | --- |
| `tools/hsltools/assets/animal_programs.py` | 完整解析 action／m_action／s_action，离线重建／校验，可直接核对原包 |
| `content/generated/hsl/animation/animal_programs.json` | 66 个角色定义、103 段程序、663 条有效指令 |
| `content/imported/hsl/global/tables/ANIMAL.H` | 原始 opcode 定义头文件，原字节 |
| `tools/hsl_native_animal_probe.py` → `animal_program_execution.json` | 分派前段六组有界执行、EXE 哈希、分发表、短指令锚点 |
| `tools/hsltools/assets/combat_animation.py` | 绑定进 `content/imported/hsl/chapter01/combat_animation/manifest.json`（`action` → `dispatch`，`s_action` → `cast_program`）；`ACTION_OPCODES` 之外的操作拒绝绑定 |
| `game/battle/scene/AnimalCastLead.gd` | `CAST_OPCODES`，施法引导逐 call 播放 |

- Godot 只读 combat manifest；演出播放器只拥有表现状态，HP、目标、行动预算归 PlayLoop，只结算一次。
- `hsl check field_coverage` 的 animal 表按通道取消费点：action → `combat_animation.ACTION_OPCODES`／`compile_action`；s_action 与 m_action → `AnimalCastLead.gd` 的 `CAST_OPCODES`。
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/animal_program_execution.md`。`AnimalCastLead.gd` layout：横幅中心 (320,240) `0x401ce1`／`0x402771`；局部图左上 x 100、肖像右缘 540 下缘 480、宽于 440 时居中（`0x4025c0`／`0x4025ff`／`0x402c0b`／`0x402c58`）；画外起点在一个宽度之外或 640。timing：aniShadowBG 1＋8 call（`0x402499`／`0x402752`）；aniMoveToCenter 与两个施法对象滑入每 call 一步 `0x45e80d(16,32)`（`0x402771`／`0x402ac9`／`0x402d27`）；局部图每张停 delay1 call（`0x402b41`）；肖像每张停 delay2 call、末张 +20（`0x402517`／`0x402e30`）；淡出计数 16（`0x402e49`）、停留 10（`0x402d3a`）。
- provisional：子状态 4 的过渡／停留与外部释放 `0x4c1408`（参考录像 `13_leonard_special_skill_cutin` 的横幅→局部→双框→極速線顺序支持先后）；阴影底用地图透出＋压暗 0.35。

## 复现

`python3 tools/hsl.py check animal_programs`（有原作 PAK 时同时核对三份原始来源）；原指令重跑 `uv run --with unicorn==2.1.4 python tools/hsl_native_animal_probe.py --check`；Godot 侧 `tools/godot.sh --headless --script res://tests/run_all.gd -- run_skill_effect_script_tests.gd`（`ANIMAL_PROGRAM_TESTS_PASS checks=386`，以程序数字与 handler 常数独立算出雷歐納德 139 call、緹娜 130 call 并逐相位断言）。

## 边界

- 隔离执行只到共享尾部前：尾部运动积分、绘制、音频、资源 loader 与初始化均未执行，不是完整函数返回、完整游戏更新或原版画面采样。
- ANIMAL.TXT loader 的 token 编译、隐式结束符、m/s 资源选择与缺省未读（线索：入口对 `0x4c1b6c` 表记录与多个通道字段的选择）。
- `aniInsertAttackFlash` 的嵌套效果／声音调用、`aniSetShape` 的残影调用在共享尾部的全部效果未恢复；普攻声音的触发路径未查证。
- phase 101 的清理、对方镜头与回合交接不在六组实验内；每秒更新次数未证明，不把 ANIMAL delay 除以 60。
- 「完整」只指这份 ANIMAL.TXT 的有效内容，不外推到全部效果、`.obs` 或技能脚本；header 有定义不等于有 handler。
