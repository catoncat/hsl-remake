# 地图上的普攻、受击与法术特效原点

> evidence: static-derived: 近战／绝技只在切入层生成刀光与击中闪光（0x4021df、0x40418a → 0x401310），全 EXE 地图受击态只有 0x407230 一个入口（法术通道 0x40aa80、落雷、喷气、地形毒），行动者过程的抖动分支 0x43f288 与收尾换形 0x4420ba..0x442172，死亡入口 0x43ef36／0x44347e 的两个跳过条件，法术演出对象 0x442a90 的两条原点轨道（effect_proc 0／1），`0x40aa80` 效果位 2 是回复 HP、全函数无 MP 伤害分支，受击计数 9 处写入（偷钱／偷物／取消行动只在通道 1 出现，不触发）; runtime-measured: V08 frame_041 受者与 024-P 模板匹配（相关 0.918，锚点 (318, 192)），R7 幻火录屏"原点比脚下高 14 px"换算为比锚点高约 2 px · status: live · functions: 0x401140, 0x401310, 0x4021df, 0x40418a, 0x4043a5, 0x407230, 0x409920, 0x40aa80, 0x423a20, 0x43c7ab, 0x43ca57, 0x43ede0, 0x43ef36, 0x43f288, 0x441ef4, 0x4420ba, 0x442a90, 0x442b58, 0x442d81, 0x443087, 0x44347e, 0x4437b0, 0x4454e7, 0x446b60, 0x446c40 · updated: 2026-09-28

本包回答三条每场可见的差异：原版地图上普攻有没有挥击／受击染色／落空提示；受击（非阵亡）时换不换 hit 帧、哪两个条件下不换；地图法术特效原点在哪。r2 读 `hsl01.exe`（SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`），raw 反汇编只在 `ignored/strikefx/`。

## 1. 结论

| 问题 | 原版读法 |
| --- | --- |
| 地图普攻效果对象 | **没有**。普攻与绝技的打击演出全在切入层：攻方 aniInsertAttackFlash `0x4021df` → `0x401310` 建刀光对象 178（defProcAttackFlash `0x401140`），守方命中时 `0x40418a` → `0x401310` 插 `ANIMAL\ATTACK_FLASH00N.SHP` 击中闪光——两者父对象都是切入对象，不在地图上。`0x401310` 全 EXE 只有这两个调用点。切入路径（`0x401c20`／`0x403860`）不调地图受击态 `0x407230`：地图守方既不染色、不闪白，也不抖动、不换帧 |
| 落空提示 | 切入守方 phase 1 落空分支（`0x4041ea..0x404247`）在同一 tick 起 150 px 闪避并以 `0x409760` 放该角色模板 `+0xc` 的闪避音——**无延迟**；地图上没有落空对象。法术落空只在目标 (x, y−0x34) 生成 kind 5 MISS（`0x40aa80` 尾部），不放声 |
| 受击换 hit 帧 | **换**，且带抖动：`0x407230(actor)` 写 `+0x92 = 60`、`+0x98 = 0x300`、`+0x80` 清 0x1000 置 0x800。行动者过程（敌 `0x43ede0`，玩家 `0x4437b0` 起同构）每 tick：0x800 在时 `+0x92` 减一，到 ≤0 清 0x800、`x = (x & ~31) + 16`；否则相位 +1、大于 3 变 −3，相位 ≥0 画在格心左 1 px（`+15`）、否则右 1 px（`+17`），并把本 tick 的姿势量写成 **6**。过程收尾（`0x4420ba`）：姿势量初值 = `+0x80 & 0x800 ? 6 : 0`，与当前 `+0x90` 不同就 `0x446c40(actor, 方向 +0xa2, 姿势, 6 时 2／0 时 10)`——状态 6 取 SHAPEDEF 偏移 0 的 `hit` 单帧。所以受击者 **60 tick 内是 hit 帧并左右抖 ±1 px**（周期 7：4 tick 左、3 tick 右），第 60 tick 回格心、姿势回站立（状态 0） |
| 谁触发受击态 | `0x407230` 全 EXE 5 个调用点：`0x40b843`（法术结算 `0x40aa80`，见下）、`0x43ca57`（落雷）、`0x43c7ab`（喷气中毒）、`0x441ef4`／`0x4454e7`（敌／玩家站上 0x200000 毒地形）。`0x40aa80(施法者, 目标, 表号, 码, 通道)` 的尾部 `0x40b831`：`通道 == 0`（MAGIC.TXT）且计数非 0 → `0x407230(目标)`；计数（函数体 `[esp+0x14]`）全函数只有 9 处写入，见下行；回复与增益位不写。通道 1（SPECIAL.TXT，切入里 `0x404848` → `0x40b8f0`）不触发 |
| 受击计数逐位 | 置 1：HP 伤害 `0x40ab73`（proc0 值非 0）。加一且都在施加成功之后：麻痹 `0x40acd0`、中毒 `0x40ad97`、禁魔 `0x40aec6`、衰弱 `0x40af7e`；偷钱 `0x40b542`（proc0 命中即加，金额恒 ≥1，加在 `0x40b546` 封顶之前）；偷物 `0x40b691`（八槽里有一件真被偷走才加，遇空槽或全部抽签失败跳 `0x40b695` 不加）；取消行动 `0x40b78d`（`0x407550` 真取消了后续槽才加；ActiveAgain 置位时不访问）；吸血 `0x40b81b`。但尾部只在通道 0 调 `0x407230`，而 MAGIC.TXT 39 行没有一行带偷钱／偷物／取消行动位（这三位只在 SPECIAL.TXT），所以原版实际游戏里三者**从不**让受者进受击态。重制一致：这三种效果只由 `SpecialUtilityRules`（通道 1，回执不带 `magic_key`）结算，`BattlePresentation._present_impact` 不调 `MapHitState` |
| 两个不换姿势的条件 | 死亡入口 `0x43ef36`／`0x44347e` 调 `0x446c40(actor, 方向, 6, 2)` 前跳过：① `+0x80 & 0x800`——**已在受击态**（收尾每 tick 已画 hit 帧，不用再换）；② `0x446b60` = live 记录 `+0xa0 & 0x20`，即 PLAYERS **no_showshape**（[阵营位包](original_player_mode_sides.md)：船壳等隐形对象）——收尾对它每 tick 写形号 `0xffff`，本就不画。收尾本身另有一条：`+0x80 & 0x1000`（`0x4071e0` 升级 use_magic 姿势、`0x4516b8` 脚本姿势持有 40 tick）时不改姿势；`0x407230` 会先清掉 0x1000，所以受击优先 |
| 法术特效原点 | 法术演出对象 `0x442a90` 按 MAGIC 行 `+0x2c`（`effect_proc`，解析器 `0x44dbb6`；`effects.h` Local=0／Global=1，读取 `0x409920`）分两条轨道：**Local（0）**→ 状态 0x14 起，镜头滚到目标对象后 `0x443087` 以目标对象的 `(+4, +8)` 调 `0x423a20` 建效果解释器——行动者初始化 `0x407d1a..0x407d4e` 把两坐标都取 `(c & ~31) + 16`，即**目标格中心，无 y 偏移**；**Global（1）**→ 状态 1 起，`0x442b58` 把 `0x4c2c70／0x4c2c74` 写成光标格 `(列×32+16, 行×32+16)`，镜头滚到同一点后 `0x442d81` 以它为原点建**一份**解释器 |
- `0x40aa80` 的效果位 `param_4 & 2` 是回复 HP（`0x40abb0..0x40ac2c`：`+0xd8` 加到 `+0xdc` 封顶、绿字 kind 2），不碰受击计数；全函数只有 `0x40b474` 一处写 MP（`+0xe0`，`0x8000` HealMP 加 MP），没有 MP 伤害分支，所以不存在「只伤 MP」的法术，受击计数只来自 HP 伤害（`0x40ab73` 置 1）与负面位（static-derived）。重制 `MapHitState.hurt` 同样只看 HP 伤害与施加成功的负面状态，一致。
- 重制对照：`SkillEffectScriptPlayer._present_effect` 对 Global 在 `clip["map_target"]`（`BattlePresentation._show_strike` 取 `cast_center`，无则守方格，格中心投到逻辑屏幕）放一份，Local 在每个受影响单位格中心各一份；Global 原点是光标格中心而非屏幕中心，地图边缘镜头夹住时两者不同，现按格中心（static-derived）。

## 证据

静态读法（static-derived）逐行见上表所列地址，r2 命令见「复现」。

### 2. 录屏对照

- **受击 hit 帧**（runtime-measured）：V08 `14_tactical_map_magic_aoe/frame_041.png`（源帧 10162，幻火命中后受者血条 24/43 时）裁 (255..305, 85..125) 滑动 `024-P.png`（69×99，原点 (41, 81)），灰度相关 **0.918**（次优 0.70），左上 (277, 111) → 锚点 (318, 192)；`frame_046`（源帧 10187，数字 19）同一姿势、正常颜色。两帧都在 60 tick 受击态内，姿势是 SHAPEDEF `hit`，不是站立帧。
- **特效原点**（runtime-measured）：R7 的拟合"落光首帧中心 y≈101–103 → 原点 ≈ y 190，比目标格中心（脚下，y≈204）高约 14 px"（[effect_motion 包](../runtime_observations/effect_motion/README.md)）量的是**脚下**：024 的 hit 帧左脚底在锚点下 12 px（行 93 − 原点 81），frame_041 左脚底 y 204 ＝ 锚点 192 ＋ 12。原点 190 比锚点 192 高约 2 px，在落光换帧 ±3 px 抖动之内——与静态读法"目标格中心"一致，不是 −14 px。镜头按目标居中（`0x43bf30`），两次录屏的受者落在同一屏幕位置。

## 重制接线

- `game/battle/scene/MapHitState.gd` 照 `0x407230`／`0x43f288`／`0x4420ba` 写受击态：60 tick 内 hit 帧、格心左右 ±1 px 抖动，第 60 tick 回格心与站立。
- `BattlePresentation` 对法术通道回执（`_present_impact` → `MapHitState.begin_strike`）与地形毒回执（`_refresh_terrain_poison`）调它；`BattlePoisonGasPresentation` 对喷气与落雷受者调 `MapHitState.begin`。切入路径不调。

## 复现

```text
r2 -q -e scr.color=0 -c 'pd 70 @ 0x4420a0; pd 30 @ 0x43ef36; pd 40 @ 0x43f288; pd 12 @ 0x407230' hsl01.exe
r2 -q -e scr.color=0 -c 'pD 0xdb1 @ 0x40aa80; pD 0x30c @ 0x40b525' hsl01.exe   # 计数 [esp+0x14]，按压栈深度换算
r2 -q -e scr.color=0 -c 'pd 60 @ 0x442a90; pxw 64 @ 0x4432c8; px 32 @ 0x443304; pd 20 @ 0x442d57; pd 20 @ 0x443068' hsl01.exe
```

## 边界

- Local 法术多受者（static-derived，逐受者序列见 [original_magic_damage.md](original_magic_damage.md)「逐受者序列」）：`0x4104d0(1)` 逐个把下一受者放进 `0x4c1cec`，子状态 0x19 在每个受者身上各建一份效果（`0x443087`），前一人的条撤掉后才建下一份，不同时在场。重制的接力伤害法术（风／火／水）照此；状态、回复等其余 Local 法术重制未做，仍在施法时每个受影响单位同时一份。

### 3. 剩余（provisional）

- 计数若日后给 MAGIC 行配偷钱／偷物／取消行动位（续作数据），原版规则会让受者进受击态；重制 `native_magic_*` 不结算这三位，届时要在 `MapHitState.hurt` 补上。
- 切入层击中闪光（`0x40414a..0x4041e5`，static-derived）：只在守方 phase 1 命中分支插入（落空、绝技的 `aniProcessHitMiss` 都不插），受击音三条路径都汇到 `0x404152` 后必插；位置 x = 守方对象命中那一 tick 的 `+0x04`（起站偏移后、击退积分前），y = 镜头 y ＋ `0xb4`（180）；父对象 0（不挡任何人）；镜像 = `0x40ba20(守方) == 0x10000`。插入后 `0x4041a4..0x4041db` 清初始化位并预置 engADDCOLOR_MIX、层级 9、`+0x90 = 6`、`+0x94 = 0x20002`，同一过程 `0x401140`：停 6 次、每 2 次降一级 18 次到 0、再 12 次自删。形状 `+0x86` 只在 kind 0 的 init（`0x40439b`）装：`0x45fc01` 在排序形状名表里二分查 `ANIMAL\ATTACK_FLASH001.SHP` 的序号再加 `[0x4c6f60]`（攻方武器 ITEM `+0xc` 图标类），即图标类 0–7（staff、sword、bow、axe、spear、dagger、claw、sting）→ ATTACK_FLASH001–008。重制 `BattleCombatCutin._show_hit_flash` 照此画（`combat_animation` manifest 的 `hit_flashes`）；武器 code 不在 ITEM 武器行里的不画。设置那次与首个过程调用是否同一 tick 未读（±1 tick）。落雷、喷气与地形毒的受击已接：三处都经同一 `MapHitState.begin` 换 hit 帧并抖 60 tick（见 [落雷包](original_drop_lightning.md)「重制接线」、[喷气包](original_poison_gas.md)）。
