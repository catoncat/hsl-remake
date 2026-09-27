# ANIMAL 完整动作程序与分派计数

> evidence: resource-derived; static-derived · status: live · tools: hsl_native_animal_probe.py, hsltools/assets/animal_programs.py, hsltools/assets/combat_animation.py, run_animal_program_tests.gd, test_hsl_animal_programs.py · updated: 2026-09-24

本包承接 [原版表现离线恢复](presentation_source_recovery.md)，交付可复跑的资源解析和原指令有界探针。协作入口：[PARALLEL_WORK.md](../../../PARALLEL_WORK.md)；研究线负责这些新文件，现有 Godot 接入由 presentation 线负责。

研究日期：2026-09-11。资源事实为 `resource-derived`；EXE 指令及其合成输入隔离执行为 `static-derived`。本包没有启动 Wine、控制游戏窗口或修改 live 战斗状态。

## 1. 现在可以直接使用什么

| 文件 | 用途 |
| --- | --- |
| [`tools/hsltools/assets/animal_programs.py`](../../../tools/hsltools/assets/animal_programs.py) | 完整解析全部有效 action／m_action／s_action；离线重建／校验，并可直接核对原包 |
| [`animal_programs.json`](../../../content/generated/hsl/animation/animal_programs.json) | 66 个角色定义、103 段程序、663 条有效指令的机器输入 |
| [`ANIMAL.H`](../../../content/imported/hsl/global/tables/ANIMAL.H) | 新提取的原始 opcode 定义头文件，保留原字节 |
| [`tools/hsl_native_animal_probe.py`](../../../tools/hsl_native_animal_probe.py) | 原动作分派前段的六组有界执行，核对 delay／连续 zoom／Over |
| [`animal_program_execution.json`](animal_program_execution.json) | EXE 哈希、分发表、短指令锚点及六组逐次调用结果 |
| [`tools/test_hsl_animal_programs.py`](../../../tools/test_hsl_animal_programs.py) | 不需要原作安装或 Unicorn 的源解析／异常输入／数据回归 |

`animal_programs.json` 经 `hsltools/assets/combat_animation.py` 绑定进 `content/imported/hsl/chapter01/combat_animation/manifest.json`（`action` → `dispatch`，`s_action` → `cast_program`），Godot 产品只读这份 manifest；§8 记录 2026-09-24 的逐通道 opcode 普查与施法引导程序的解释状态。

## 2. 源身份和核对边界

| 来源 | SHA-256 / 说明 |
| --- | --- |
| 本机 `hsl01.exe` | `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；其他版本立即拒绝 |
| 原包 `data\ANIMAL.TXT` | `e27783ef3148bad8523af95c7d111f1a3ed66c7c0844c7b7cfdabefb4ef9b4ea`；与已有完整导入文本逐字节相等 |
| 原包 `data\ANIMAL.H` | `88959ec91256978d74b9b10138cb12d4505e54789c6e0cfc3d52af0cc38a97e6`；本次提取，逐字节相等 |
| 原包 `data\SHAPEDEF.H` | 原包 `7472343668711a1f9db825b3d72100ee11759a2dc55c212934a9d081bdb1ab1c`；已有导入 `73b5592fd2ba7d09d835b9ec0a72afd719a48e3f8219a7da9393a73586a1aee4` |

最后一项已经逐字节排查：原包 4984 字节使用 CRLF，旧导入 4802 字节使用 LF。只对这个明确命名的来源做 CRLF→LF 后完全相等；不会因此重写公共表，也不会把这个核对结果说成未经转换的源字节相等。JSON 每个来源记录自己的 `pak_comparison`，其他两个来源保持 `exact_bytes`。

新增 `.gitattributes` 仅为 ANIMAL.H 使用仓库既有的 byte-exact source 属性，避免 Git 改写原始 CRLF／空白；人工编写的工具和文档仍接受普通 diff 检查。

## 3. 从 header 到完整程序

ANIMAL.H 直接给出 `aniOver=0`、`aniDelay=1`、`aniSetShape=7`、`aniSetZoom=9`、`aniSetXYDisp=10`、`aniInsertAttackFlash=11`、`aniShadowBG=12`、`aniMoveToCenter=13`、`aniInsertCastObject=14` 等定义，一直到 35。参数数量来自各定义的 `// [参数]` 注释。`aniKStop/Right/Left` 属于单独的 hit-movement 标志，不能当动作 opcode。

解析器保留原有的三个字段名：`action`、`m_action`、`s_action`，不把它们重命名后猜测调用关系。重复同名 action 行按原文件顺序追加；每条指令带 `op`、`opcode`、整数 `args`、原文 `arg_tokens` 与 `source_line`。负数和十六进制不经过浮点数；字段及资源路径也保留源行。

完整覆盖数字为：

| 内容 | 数量 |
| --- | ---: |
| `[animal]` 角色定义 | 66 |
| `action` 程序 | 66 |
| `m_action` 程序 | 18 |
| `s_action` 程序 | 19 |
| 有效指令 | 663 |
| 实际使用的 opcode 种类 | 11 |
| header 声明的 opcode 种类 | 36 |

这里的“完整”只指该份 ANIMAL.TXT 内的有效内容，不能外推成全游戏所有效果、所有 `.obs`、全套人物状态或所有技能脚本都已恢复。header 有定义也不等于该过程有对应 handler。

解析器拒绝未知字段、未知 opcode、参数不足或多余、非整数、超出单个 32-bit word 的参数、重复角色／单值字段、缺少 shape/count/program 中任一项和越界的 aniSetShape。缺省的 m_action／s_action 允许全部不存在，且不会自动从其他角色或另一 channel 补出一段程序。原版 loader 本身可能有选择规则，必须另行恢复。

### 三个会影响实际演出的例子

**雷欧纳德特殊技，原文行 14–15：**

```text
aniSetXYDisp,-640,0
aniShadowBG
aniMoveToCenter
aniInsertCastObject,-160,-150,2,6,6
```

源程序包含位移、背景和施放动作。已有 importer 只生成帧／delay 摘要，并另存 flash_offset，无法靠这份摘要表达整段 s_action。该程序仍需使用各 handler 的真实坐标、时钟及阶段合同，不能仅凭指令名直接做出等价声明。

**普通攻击，原文行 10–11：**

```text
aniDelay,12 → aniSetShape,1 → aniDelay,8 → aniSetShape,2
→ aniDelay,3 → aniInsertAttackFlash,-90,-120 → aniSetShape,3 → aniDelay,30
```

闪光位于最后一次换帧之前；新数据保留这个次序。源代码里没有单独写 aniPlaySound，不能据此宣称普通攻击没有声音：声音可能由 handler 内部或外围过程触发。声音的实际触发路径仍需查证。

**PLAYER5 的连续缩放，原文行 83–85：**六条 aniSetZoom 从 `0x00011000` 到 `0x00016000` 连续出现，中间没有 aniDelay。它们不能在解释器里一口气执行成“只看到最后一个缩放值”，执行边界见下一节。

其他已固定的细节：PLAYER7 的换帧次序多次回到 0／1，不应排序或去重；PLAYER9 的旧闪光偏移被分号注释，当前有效值为 `[-300,-60]`；Enemy026 的 m_shape、m_number、m_action 全被注释，不能导入为有效施法程序；Enemy024 没有有效 fh_shape，但仍有 aniInsertAttackFlash 指令，事件与贴图绑定必须分开处理。

## 4. EXE 分派边界

本机 EXE 过程表 `0x477c2c` 的 slot 22 指向 `0x401c20`，相邻 slot 23 为先前已命名的 AnimalDefense `0x4038a0`。本包直接研究 slot 22 的动作分派行为；没有重新提取 `PROCESS.DEF` 的名字绑定作为新证据。

`0x401f3b` 从对象 `+0xa4` 读取程序指针，`0x401f41` 取 32-bit opcode 并将局部指针前移 4 字节；经 `0x401f46` 检查 0..33 后，`0x401f58` 进入 `0x4037b0` 表。表中关键映射为：

| opcode | 原 header 名称 | handler |
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

完整表在 JSON 中。数个值映射到 `0x402709` 的共同路径，而 34／35 不在本过程的直接分发表范围内。因此不能把 header 的 36 条定义一律当作这个过程的 36 个已实现动作。

**不是所有指令都以相同方式推进。** `0x402278` 会继续取后继 opcode，并可在同一次调用中重新跳到分发表；另一些 handler 保存指针后跳到 `0x4034c6` 共享尾部，从本段让出。后续实现必须明确哪个动作继续、哪个动作等待，不能一律“每条耗一帧”或一律“无 delay 就同 tick 排空”。

例如，aniSetShape 经可选残影调用后在 `0x40243d..0x40244e` 更新帧并让出；aniInsertAttackFlash 所在分支最终经 `0x402264` 进入继续取指路径。这里只确认可见指令控制流，嵌套调用产生的全部效果和声音尚未恢复，不据此把整段 flash／damage 同步关系定为完成。

注意 r2 的显示标签：多处 `jmp case.default.0x402a55` **实际目标是 `0x4034c6`**。本包依据结构化 `jump` 和原始字节，不把临时标签的地址片段误当跳转地址。

## 5. 六组原指令实验的范围和结果

探针从真正入口 `0x401c20` 执行，输入一个合成对象及 dword 程序。每次在共享尾部 `0x4034c6` 执行前停止，保存对象的 phase、counter、cursor、两个 zoom 值。每次最多 512 条指令，每组最多 64 次更新；EXE 哈希不符、跳入未检查的外部 callee、预算耗尽都会失败。

这是**原函数前段指令的隔离实验**。不是完整函数返回，不是完整游戏更新，也不是原版画面采样。没有给未知函数写返回值 stub。尾部运动积分、绘制、音频、资源 loader 和初始化均未执行；不能把省掉的尾部称为无关或证明整段原版等价。

### aniDelay 的明确边界

`0x4022aa..0x4022c6` 将 phase 设置为 1，将 D 写入对象 `+0xa0`，保存后继程序指针并让出。之后 phase 1 经 `0x402714` 每次将计数减一；小于等于 0 时清状态，然后仍让出，下一次才恢复读指令。

合成程序 `[aniDelay,2,aniSetZoom,0x13000,aniOver]` 的结果：

| 调用后的状态 | phase | counter | cursor word | zoom |
| --- | ---: | ---: | ---: | ---: |
| 初始（尚未调用） | 0 | 0 | 0 | `0x10000` |
| 第 1 次：装入 delay | 1 | 2 | 2 | `0x10000` |
| 第 2 次：等待 | 1 | 1 | 2 | `0x10000` |
| 第 3 次：等待归零 | 0 | 0 | 2 | `0x10000` |
| 第 4 次：执行 zoom | 0 | 0 | 4 | `0x13000` |
| 第 5 次：执行 Over | 101 | 0 | 5 | `0x13000` |

已执行 D=0、1、2、12、30。以初始状态为下标 0，后继 zoom 首次可见的结果下标为 `max(D,1)+2`。D=0 也经过一次等待分支，计数会减为 -1，不能直接删除这条 delay。

这个公式描述探针的调用下标，不是秒数，也不能直接等同 SHP helper 的“D+1 更新换帧”。尤其不要把所有 ANIMAL delay 机械地除以 60，更不要只对 delay 加一却忽略换帧等指令自身的让出。

### 连续 zoom 及结束

第六组从 PLAYER5 有效程序取出六条连续 aniSetZoom，再为实验显式补一个 aniOver。逐次结果依次为 `0x11000/0x12000/0x13000/0x14000/0x15000/0x16000`，两轴同时写入；随后 aniOver 将 phase 设为 101。证明这个前段不会在一次调用里吞掉六个缩放步骤。

**原文未包含 aniOver。** 新资源 JSON 也不追加它。实验中的 0 是明确提供的终止指令；本包没有执行原始文本编译器，尚未证明 loader 如何补结束标记、如何分配程序内存。phase 101 的后续清理、对方镜头和回合交接也不在这六组实验内。

## 6. 复跑

在仓库根目录执行。第一组不要求原作安装、Wine、r2 或 Unicorn：

```sh
/opt/homebrew/bin/python3 tools/hsl.py check animal_programs
/opt/homebrew/bin/python3 -m unittest tools.test_hsl_animal_programs -v
```

有原作 PAK 时，进一步核对三份原始来源（SHAPEDEF.H 的明确换行转换见第 2 节）：

```sh
/opt/homebrew/bin/python3 tools/hsl.py check animal_programs
```

重新执行原指令并比较 curated packet；Unicorn 是可选分析依赖，不进入游戏产品：

```sh
uv run --with unicorn==2.1.4 python tools/hsl_native_animal_probe.py --check
```

确认输入需要更新时，分别去掉 `--check` 重建**本工具自己的** JSON。首次构建需要先取得已经记录哈希的三个来源；不能在 checker 缺文件时偷偷下载或从错误安装兜底。

r2 仅供继续人工追踪，不是以上门禁依赖。已跑通的原始指令导出方式（raw 只进 ignored）：

```sh
mkdir -p ignored/animal-program-research
R2_NOPLUGINS=1 r2 -N -e scr.color=0 -e bin.relocs.apply=true -q \
  -c 's 0x401c20' -c af -c pdfj \
  $HSL_ORIGINAL_DIR/hsl01.exe \
  > ignored/animal-program-research/0x401c20.json
```

当前 r2 JSON 使用 `addr`；兼容读取可明确处理旧版本 `offset`。不得把不兼容 decompiler 的空输出当 C 源码。完整反汇编不跟踪，本包 JSON 只保存短字节锚点及表／观察结果。

## 7. 给接入方的使用合同

先选择要支持的角色和 channel，从 `records[].programs` 读取完整顺序，不再只从 `timeline` 的 frame／ticks 推出所有事件。每个 opcode 必须有明确支持状态；未支持的 movement／casting 等操作要明确拒绝或保持该通道未接入，不能静默跳过并宣称播放成功。

普通攻击的 flash、换帧、末段等待按源顺序消费，同时保留 PlayLoop 只结算一次的合同；演出播放器只拥有表现状态，不拥有 HP、目标、行动预算。不要因为观察到 opcode 就扩大玩家命令集合。

涉及跨帧时，先区分 handler 继续取指、handler 让出和等待状态；实际每秒更新次数仍需要追调度器／时钟或一次有界测量。新工具没有给出“原版必定 60Hz”的结论。

以下仍是下一次窄研究的候选，并非本次已完成：

1. ANIMAL.TXT loader 的 token 编译、隐式结束符及 m/s 资源选择／缺省；定位线索为入口对 `0x4c1b6c` 表记录及多个 channel 字段的选择。
2. `aniInsertAttackFlash` 的嵌套效果／声音调用和 `aniSetShape` 的残影调用，及共享尾部对结果的影响。
3. `aniInsertCastObject`、`aniMoveToCenter` 的完整坐标／阶段输出，再与另一条线已有 SHP／移动 helper 证据连接。

本包的完成标准是输入可完整重建、指令行为可按记录重跑、限制清楚且可独立接入。最终画面、音轨和自然游玩仍由既有产品验收处理；研究线不会为此与 presentation 同时控制原作或清理共享缓存。

## 8. 施法引导程序（m_action／s_action）的解释

研究日期：2026-09-24（lane R30）。本节把 §4 的分派表继续读到施法引导用到的四个 handler，并按通道普查全部 663 条指令；解释状态以此为准，`hsl check field_coverage` 的 animal 表按通道取消费点（action → `combat_animation.ACTION_OPCODES`／`compile_action`；s_action 与 m_action → `game/battle/scene/AnimalCastLead.gd` 的 `CAST_OPCODES`——R31 起 m_action 经导入的 m_shape 条带由地图法术 presenter 播放）。

### 8.1 逐通道 opcode 普查（resource-derived）

| opcode | op | action（66 段） | m_action（18 段） | s_action（19 段） | 解释状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| aniDelay | 1 | 255 | 0 | 0 | action：`compile_action`（setup 1 call ＋ max(D,1) 等待 call，§5） |
| aniSetShape | 7 | 182 | 0 | 0 | action：`compile_action` → manifest `dispatch.poses`，切入按 update 换帧（`0x402415` 更新 +0x30 后让出） |
| aniInsertAttackFlash | 11 | 59 | 0 | 0 | action：同一 call 继续取指（`0x402264` → `0x402278`），release 标记 |
| aniSetSubSpeed／aniSetAddSpeed／aniSetStopSpeed | 4／3／5 | 4／1／1 | 0 | 0 | action：`compile_action`（002 起跳／落地，[原祭司](original_priest.md)） |
| aniSetXYDisp | 10 | 7 | 18 | 19 | action：`hsltools/assets/_mobile_animation.py` `compile_mobile_action`；m／s：`AnimalCastLead`（`0x402180`：位移加到 +4／+8，同 call 继续取指；`0x446be0` 为真时 x 取反——live 记录 `+0xa0 & 8`，obj_Data9 互换安装置位、actSetPlayerMode 每次翻转，重制读单位 `side_swapped`，R7-SPELL；普攻 action 同样取反，见[效果对象运动包 §4b](original_effect_motion.md#4b-普通切入的换边镜像cutin-mirror)）——consumed |
| aniSetZoom | 9 | 6 | 0 | 0 | action：`compile_mobile_action`（`0x402476` 写 +0x20／+0x24 并置 0x8000000） |
| aniShadowBG | 12 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x402499`：+0x80 \|= 0x1000、phase 12；`0x402752` 每 call +0x90，计到 bp=8 回 phase 0——共 1＋8 call）——consumed |
| aniMoveToCenter | 13 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x4024c1` phase 13；`0x402771` 每 call 调 `0x45e80d(x, y, base+0x140, base+0xf0, 16, 32)`，到达回 phase 0）——consumed |
| aniInsertCastObject | 14 | 0 | 18 | 19 | m／s：`AnimalCastLead`（`0x4024d3` phase 102，见 8.2）——consumed |
| 其余 26 个 | — | 0 | 0 | 0 | ANIMAL.TXT 未使用（EFFECTS 脚本另计，见 field_coverage effect 列） |

37 段 m_action／s_action 程序全部是同一形状：`aniSetXYDisp,±640,0 → aniShadowBG → aniMoveToCenter → aniInsertCastObject,-160,-150,[起始张],[delay1],[delay2]`；只有 056／059／060 的位移是 +640（从右侧进），其余 −640。

### 8.2 施法对象 phase 102（`0x4024d3` → `0x402a3e`，static-derived 前段 ＋ provisional 尾段）

对象字段：+0x8e phase（= 触发它的 opcode 号；100／101／102／103 为普通开场／结束／施法对象／链接程序）、+0x8c 子状态、+0x30 当前张、+0x7a 张数、+0x7c／+0x7e 张停留计数／重装值、+0xa0 剩余数、+0x9c／+0x9e 局部图张／肖像张、+0x94..+0x9a 目标与当前坐标。

- 装载（`0x4024d3..0x402637`）：读 xdisp／ydisp／起始张 S／delay1／delay2。全局 `0x4c6f5c = max(S−1, 0)`（肖像张数），`0x4c6fa8 = delay2`（S−1 ≤ 1 时 +20，`0x402517`），`0x4c6faa = delay2`；+0x7c/+0x7e = delay1；+0xa0 = 张数 − S（局部图数）；+0x9c = 当前张(0) + S、+0x9e = 1。`0x4606a9(张, &ox, &oy, &w, &h)` 取该张 SHP 的原点与尺寸；**xdisp 只取符号**（`0x4025bc`：<0 → `0x4c6f64=1`）：局部图目标 x = base + ox + 100（xdisp<0，`0x4025c0`）或 base − w + ox + 540（`0x4025ff`），起点 = base − w + ox（画外左）或 base + 640 + ox（画外右）；目标 y = base + oy（上缘 0）。ydisp 未见读用。
- 子状态 0（`0x402a5c`）：画局部图，`0x45e80d(…,16,32)` 一步；到达 → 子状态 1。
- 子状态 1（`0x402afe`）：画；+0x7c−−，归零时重装 delay1、+0xa0−−；>0 则经 `0x401220` 留残影并 +0x9c++（下一张），≤0 → 子状态 2 并算肖像目标：y = base − h + oy + 480（下缘 480）；xdisp<0 时 x = base + 0x140（w > 440 居中，`0x402c19`）或 base − w + ox + 540（右缘 540），起点 base + 640 + ox；xdisp ≥ 0 时 x = base + ox + 100、起点 base − w + ox（`0x402c58`）。
- 子状态 2（`0x402c87`）：画局部图与肖像，肖像 `0x45e80d(…,16,32)` 一步；到达 → 子状态 3，+0xa0 = 10、+0x28 = 16、`0x4c6f70 = 0x20002`。
- 子状态 3（`0x402d79`）：画；`0x4c6fa8`−−，归零时重装 delay2、`0x4c6f5c`−−（≤0 → 子状态 4；≤1 → 重装值 +20）、+0x9e++（下一张肖像）。
- 子状态 4（`0x402e47`）：+0x84 计到 16 期间以 mode 0 ／>16 以 0x20000000 画（过渡），==16 时 +0xa0(10) 倒数，再看 `0x4c1408`：−1 → phase 101 结束；非零 → 作为新程序指针进 phase 103；0 → 继续等。子状态 5–9（`0x403089..0x4031c7`）本包未读。

**重制解释（`AnimalCastLead.compile`，每 call 一个状态）**：横幅（第 0 张，施法对象本身）从 (320,240)+位移 经 1＋8 call 阴影底、1 call 进 phase 13、逐 call `opening_step(…,16,32)` 到中心；1 call 装载；局部图自起始张滑入（每 call 先画后步）、每张停 delay1；肖像（第 1 张）滑入，第 1…S−1 张每张停 delay2、末张 +20；16 call 淡出＋10 call 停留后引导结束、EFFECTS 攻方脚本开始。雷歐納德（S=2，delay 6／6，条带 7 张）：9＋22＋1＋11＋30＋12＋26＋26 = **139 call**；局部图锚点 (217,92)、肖像锚点 (398,374)（`run_animal_program_tests.gd` 以程序数字与 handler 常数独立算出并逐相位断言）。

**仍 provisional**：① 子状态 4 的过渡／停留 cadence 与外部释放 `0x4c1408`（原对象等谁释放、EFFECTS 攻方脚本与它是先后还是并行——参考录像 `13_leonard_special_skill_cutin` 的顺序横幅→局部→双框→極速線支持先后）；② 阴影底的画法（重制为地图透出＋压暗 0.35）；③④ 已由 lane R7-SPELL 接上：残影 `0x401220`（aniSetXYDisp 作为一次 call 的首条指令时 `0x402187` 留横幅残影、子状态 1 每张局部图到期且还有下一张时 `0x402b68` 留局部图残影；对象 179 层级 6，defProcShadowLeft `0x4010c0` 每 4 call 减一、24 call 消失）与 `0x446be0` 换边镜像（`0x401ddf` x 缩放 −1、`0x4021b8` x 位移取反；单位 `side_swapped` 由组装按 obj_Data9≠0 写入），见[效果对象运动包](original_effect_motion.md)；⑤ 已由 lane P3 读出并移入 [tick 计数包 §6／§7](original_tick_counts.md#6-普攻切入的守方对象-defprocanimaldefense0x4038a0slot-23受击停留lane-p3)：普通攻击的 phase 100 开场是 24 tick 缩放（`0x401060` 步进表）＋ 32 tick 叠层，`0x436490(+0xa0, 3, 0)` 是切入身份栏的文字生成（→ `0x434d10` mode 3），不是放声；守方 AnimalDefense `0x4038a0` 中立 32 tick、命中停留 68 ＋ 10×位数 tick、落空 56 tick，之后是未读长度的屏幕过渡（`0x46098f`）——`CombatPresentationTiming` 的 TARGET_PAUSE／hurt_hold 已 static-derived，RECOVERY 仍 provisional；`k_action`（aniKStop／Right／Left）是受击位移方向旗，不是程序。

**m_action（R31）**：18 段中 16 段的 `m_shape` 条（P0xx_101…，69 张 PNG，manifest 每行 `magic_frames`＋`magic_cast_program`，`MAGIC_FRAME_ACTORS`）已导入，地图法术 presenter（`SkillEffectScriptPlayer._present_effect`）先按同一 `AnimalCastLead.compile` 播放引导再走 effCode 脚本，`released` 在引导结束；緹娜 002（S=2，delay 4／4，7 张）引导 130 tick，`run_animal_program_tests.magic_cast_lead_program` 以程序数字与 handler 常数独立算出。未导入的两行：018（SHAPEDEF 走行行被注释、无战斗行）与 068 怨念（无走行组、无战斗行）；没有 m_action 的施法者（026 帝國法師 的 m_shape 被注释）与这两行仍用 `CombatPresentationTiming.CAST_LEAD_IN` 的 Cast_Star 替身（manifest `magic_cast_program_policy`，按角色列明）。s_action 有程序的行中，004／006／007／009／053／054／055／057 的 `s_shape` 条已由 J1 导入（053 按 ANIMAL 块声明取 P009_201…204），引导同法播放；仍无条带的只剩 002（P002_201 条归 月花圓舞 导入、不进 combat manifest）与 018（无战斗行），按 manifest `cast_program_policy` 显示站立帧——按角色列明，不是全局静默回退。056 的 ANIMAL 块无 s_shape／s_action，hsl.pak 亦无 P056_2xx（negative-evidence）。

复跑：`tools/godot.sh --headless --script res://tests/run_all.gd -- run_animal_program_tests.gd`（`ANIMAL_PROGRAM_TESTS_PASS checks=386`）；反汇编入口同 §6（`s 0x401c20; af; pdf`，raw 只进 `ignored/`）。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/AnimalCastLead.gd` layout：banner centre (320,240) 0x401ce1／0x402771; inset top-left x 100, portrait right edge 540 and bottom 480, centred when wider than 440 — 0x4025c0／0x4025ff／0x402c0b／0x402c58; off-screen starts one width outside or at 640
- `game/battle/scene/AnimalCastLead.gd` timing：aniShadowBG 1＋8 calls 0x402499／0x402752; aniMoveToCenter and both cast-object slides one 0x45e80d(16,32) step per call 0x402771／0x402ac9／0x402d27; each inset panel held delay1 calls 0x402b41; each portrait frame held delay2 calls, the last +20 0x402517／0x402e30; fade counter 16 0x402e49, hold 10 0x402d3a
