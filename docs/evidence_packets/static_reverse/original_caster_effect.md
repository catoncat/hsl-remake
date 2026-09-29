# 施法者侧特效（MAGIC effect_caster）

> evidence: static-derived: 施法 VM 状态 0（0x442ad1）的镜头滑向施法者、起点 0x442c09／0x442ef5、状态 2／0x15 的 0x442c4f 与 0x43bf30 负标志分支、状态 4／0x17 的 0x442c71／0x442f4d 与建对象 0x442f77 逐条静读，MAGIC 解析 0x44dbf5 与取字 0x4098e0; resource-derived: MAGIC.TXT 8 行 effect_caster、global.obs 对象模板; provisional: 施法者对象在施法结束时随片段一起清掉（原版对象自走到删）；0x415ba0 开头两个调用未读；重制的状态 0 滑镜只给有施法者特效的 8 行补上 · status: live · functions: 0x4098e0, 0x409940, 0x415ba0, 0x415c10, 0x415dc0, 0x41e834, 0x42d280, 0x43bf30, 0x442ad1, 0x442c09, 0x442c4f, 0x442c71, 0x442cba, 0x442ef5, 0x442f4d, 0x442f77, 0x442fc7, 0x44dbf5, 0x45e307 · updated: 2026-09-29

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 只读。tick 按 [tick 率包](../runtime_observations/original_tick_rate/README.md) 的设计值 16 ms 换算。

## 结论

- **数据**：MAGIC.TXT 的 effect_caster 写成 `对象名,N`，解析器 0x44dbf5 把对象号写记录 +0x34、N 写 +0x38。8 行：186 `obj_Effect_EarthStone7,140`、174 `obj_Effect_FireBeast2,300`、175／176／177 `obj_Effect_MindWord／MindWord2／MindWord3,60`、185 `obj_Effect_MindWord4,60`、181 `obj_Effect_OtherWord,120`、182 `obj_Effect_OtherWord2,160`（resource-derived）。
- **取字**：0x4098e0(魔法类型, 魔法编号)（调用点压的是 MAGIC 选择字 [0x4c2c54]／[0x4c2c40]） 低字取 +0x34、高字取 +0x38 打包返回；记录不存在返回 0（static-derived）。
- **起点**：Global 状态 1（0x442c09）与 Local 状态 0x14（0x442ef5）都先调 0x4098e0。返回 0：Global 状态 +4 进 5（下一次调用建前导），Local 状态 +4 进 0x18 并当场 0x406d20(施法者, 1, 0x4c42a0) 建前导。返回非 0：写施法者 +0x9c（低字对象号，+0x9e 是 N），状态 +1 返回（static-derived）。
- **镜头到施法者**：状态 0（0x442ad1）对每个魔法先调 0x43bf30(施法者, 0)（0x442ae9），未到位就原样返回（0x442af3），到位的那次才转 Global 状态 1（0x44316f）或 Local 状态 0x14（0x442bf1）；这段滑镜与有没有施法者特效无关。状态 2／0x15（0x442c4f）调的是 0x43bf30(施法者, 0x80000000)：负标志下镜头已在目标上时按帧标志 [0x4c1b1c] 决定（0x43bfd8–0x43bfe7），该字由帧例程 0x42d280 进帧清 0、出帧后置 1，所以镜头自状态 0 起停在施法者身上时首次调用即到位，状态 +1 并经 0x442f18 建前导，没有另一段滑镜。所以 Local 有施法者特效时前导比没有时晚 1 次调用（0x14 → 0x15 返回，0x15 那次才建前导；没有时 0x14 当场建）；Global 的 1 → 2 → 建前导与没有时的 1 → 5 → 建前导调用数相同（static-derived）。
- **施法者对象与等待**：状态 4／0x17（0x442c71／0x442f4d）进入即置 [0x4c1b00] |= 0x1000000；施法者 +0x80 带 0x1000（use_magic 架势）时返回等待。架势结束后的第一次调用 +0x9c 非 0，进 0x442f77：0x409940 取效果号调 0x415ba0，再在施法者 (+4, +8) 调 0x45e307(x, y, 对象号, 0) 建对象，清 +0x9c；建成就返回，建不成把 +0x9e 清 0。此后每次调用 +0x9e 减 1（0x442c9f／0x442fc7）；找到 0 的那次调用：Local 状态 +2 进 0x19；Global 调 0x43bf30(0x4c3860, 0) 滑向效果中心伪对象，到位才状态 +3 进 7（0x442cba）。7／0x19 在下一次调用照没有施法者特效时的流程走（static-derived）。
- **合计**：施法者对象在「架势结束后第一次调用」建成；受者阶段（Global 状态 7／Local 状态 0x19 的首次执行）比没有施法者特效时晚 N + 2 次调用，Global 另加滑向效果中心的时长（static-derived）。
- **0x415ba0**：按效果号取 0x477718 表的一行，逐个形状名 0x45fc01 查句柄并 0x460058(句柄, 1)，是效果形状的预载，不出声、不画；Global 状态 7（0x442d39）对每个 Global 魔法同样调它（static-derived）。尾部调 0x45f4b9(0x3c)，把帧计时重置为 1000/60 ms、基准取当前时刻，即预载后重新对帧。开头调用的 0x42c3d0／0x42c3b0 看上去是对形状缓存做 0x7d00 字节的保存／恢复，未确证。
- **对象的动作**：8 个对象都是 defProcEffectProcess1，effProc* 程序（effProcMindWord、effProcFireBeast2、effProcOtherWord、effProcOtherWord2、effProcEarthStone5）由原生效果对象探针逐 tick 执行，轨迹与声音记在 `content/generated/hsl/skills/effect_motion.json`；它们的 obj_Y1／obj_X2 声音时刻只取原生轨迹，不进静态声音表（static-derived）。基点 +0xaa／+0xa8：0x45e307 只写 +4、+8、+0x54、+0x58、+0x80，模板这两字为 0；defProcEffectProcess1（0x415dc0）首次执行在 0x415e5d–0x415e74 见 +0xa8 为 0 即取对象自身 (+4, +8)，所以 effProcEarthStone5 从基点撒的 300／301／302 子对象（0x41e92e／0x41e9a2／0x41ea16 → 0x415c10）以施法者为基点。探针给根对象写入的原点就是根的创建点，按模板建法重跑的原始轨迹 172 个实例逐帧相同；`effect_motion.json` 里 EarthStone7 记作 mixed 只因位移对照跑仍写固定原点，改按模板建法即为 translates（static-derived）。

## 重制对应

- `special_effect_scripts.json` 的魔法行带 `caster: {object, ticks}`，对象进 `objects`，skill_effects 导入其 SHP 与 WAV；`SkillEffectScriptPlayer.compile_caster` 编成独立时间线。
- `SkillEffectScriptPlayer._present_effect`：有 `caster` 时 Local 先多 1 tick（状态 0x15 那次调用）；架势结束（`lead_in`）时在施法者格画对象，等 N + 2 tick；Global 再 `_effect_centre_glide` 滑向目标格，Local 走原有受者滑镜。没有 `caster` 的魔法时序不变。8 行 effect_caster 都是 Local 魔法，Global 分支（`_effect_centre_glide`）没有数据走到、未经运行核对。
- 状态 0 的镜头滑向施法者重制整体未建模（[施法叠画包](original_cast_overlays.md)「边界」）；`_caster_glide`（0x43bf30 逐 tick 滑行，与受者滑镜同一套，片段时钟从到位起算）是提前替这 8 行补上的状态 0 滑镜，不属于状态 2／0x15。其余魔法仍缺这段，两类魔法的起手在这一点上不对称（provisional，清单 cast-lead-phase）。
- 边界：施法者对象在片段结束时随 `clear()` 清掉；原版对象由自身 effProc 删，若寿命长过施法会多留，重制不留（provisional）。
