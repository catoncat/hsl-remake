# 技能function、目标覆盖与共享范围

> evidence: static-derived · status: live · functions: 0x407800, 0x409850, 0x409870, 0x40ba80, 0x40fc90, 0x4100e0, 0x4104d0, 0x446b30 · tools: hsltools/data/skill_targeting.py, hsltools/probes/skill_target.py, run_skill_resolution_tests.gd · updated: 2026-09-25

Checked: 2026-09-13。接续 [技能资源费用](original_skill_resources.md)。机器证据为 `original_skill_targets.json`；生成数据为 `content/generated/hsl/skills/targeting.json`。本包恢复函数标记到目标模式、当前单格覆盖／枚举及来源范围的公共合同，未实现全部辅助效果或原AI决策。

## 来源与调用链

原EXE SHA-256：`f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。原PAK中MAGIC/SPECIAL/ITEM复用前包的原始哈希校验；本包又直接核对TYPE.H/RANGE.TXT，原始及导入哈希分别记录。TYPE.H导入除了CRLF→LF和末尾空行，还删掉一条职业注释末尾空格；校验仅允许行尾ASCII空白规范化，不更改符号、数值或内部文本。首次直接比较因此失败，查明实际差异后补限定校验，没有覆盖原表。

Magic函数getter `0x409850` 从类型表`0x4c2ca0`、记录+0x24取function；Special `0x409870`从`0x4c3920`、记录+0x28取function。当前氣刃斬、风刃、幻火均为TYPE.H明确的 `magicFun_Attack=1`。getter在本包只核对指令，不冒称已单独执行。

玩家Magic路径 `0x444e8e` 调getter，function=0拒绝，随后 `0x444e9e..0x444eb2` 将 `(function & 0xf62)!=0` 转成mode3，否则mode2。Special路径 `0x44503a` 调getter，`0x44504a` 使用不同掩码 **0x18f62**，`0x445053/0x44507f` 分别写mode3/2。ActiveAgain另进入`0x40ba80`相关调用，未在这里推成完整再动规则。

| function示例 | Magic目标模式 | Special目标模式 |
| --- | --- | --- |
| Attack、Poison等不在支持掩码中的位 | 2 | 2 |
| Heal、DefUp、AttUp、AllUp、CureParalysis/Poison/NoMagic | 3 | 3 |
| HealMP、ActiveAgain | **2** | **3** |

这张表是原玩家选择分支的静态结果；不能用“辅助技能”一词把两个mask统一，也不能仅凭mode决定实际效果。完整TYPE符号逐项结果保存在机器包，GDScript逐项对照。未知function和function=0明确拒绝。

## 覆盖、标志与目标枚举

Magic `0x444f08`、Special `0x4450e0` 将角色、目标XY、effect_range和mode传给同一个 `0x4100e0`。该函数清理覆盖缓冲区，读取RANGE结构，再选择目标模式。分发表 `0x410498` 中mode2到`0x410155`，使用排除位0x10000；mode3到`0x410161`，使用排除位0x20000。TYPE.H定义它们为pmPlayer、pmEnemy，pmNPC=0x40000；组合标志不能被当成角色控制权的完整解释。

所追单格center支路 `0x4103cc` 检查排除位，但0x70000组合标志例外。之后调用 `0x40fc90`：正常角色指针非零时会清临时地图位，再在 `0x410410` 检查特殊0x850000标记；因此“地图位”和“有无可返回角色”共同影响覆盖。`0x446b30`查询的是actor+0xa0的0x10位，不能未经来源写入追踪就把它命名为死亡或禁魔状态。大体型和全部标志生命周期另列未证；多格区域的障碍传播见 [原武器射程](original_weapon_ranges.md#地形传播)。

`0x4104d0(0)` 重建目标列表：只遍历非零覆盖格，经 `0x407800` 查角色，`0x410579` 做指针去重，`0x410585`追加。后续非零参数继续取缓存，`0x4105da`在耗尽后返回0。去重分支有静态锚点；本批单格夹具未执行“同一大角色跨多格”的重复指针情况，不声称该变体运行验收。

## 本次原函数执行

32个1×1地图／range0Cell夹具：mode2/3 × 八种地图位（0、Player、Enemy、NPC及组合）× 有无角色。每例真实执行一次完整 `0x4100e0`、两次完整 `0x4104d0`，均正常返回；后继枚举为0，角色与地图真值完全不变。实际调用的 `0x40fc90`／`0x407800`／`0x446b30` 等使用原指令，无stub，每次8192指令上限，陌生callee拒绝。

夹具有明确合成地图、200槽原角色注册表、可见角色和effect_range0Cell，不运行完整技能、战场UI或伤害效果。公式模型独立比较覆盖/指针/耗尽输出；原函数的返回EAX在builder本身不被误当成语义返回值，验证的是它写的覆盖缓冲。机器包同时记录20段静态字节锚点，证据等级与原函数执行标记分开。

## 当前产品接入

纯 `SkillTargetRules` 解析明确TYPE符号，严格验证来源range矩阵及单目标effect_range；当前只接受精确Attack bit1。治疗、再动、Attack|Poison等尚无效果实现的组合明确报错，不能继续走扣费后物理/元素伤害路径。场景初始化及AI入口的 `_skill_input_error` 联合验证费用和目标定义，失败前不移动、不耗资源、不切队列。

`hsltools/data/skill_targeting.py` 只从已有原表生成function位和当前三种来源矩阵，不重新导入图片。`range2Cell`是两格十字，`range3CellCircle`是三格菱形，`range0Cell`是单格效果；矩阵非零值用于范围，不能把名字当半径自行生成。方向型范围见 [直线范围](original_line_ranges.md)；地形阻挡与传播算法（`0x40f8b0`／`0x40fdc0`）见 [原武器射程](original_weapon_ranges.md#地形传播)——玩家施放范围已接，效果区域已实现、结算与预览尚未接。

PlayLoop玩家特殊技选择/确认/效果提交、AI法术可达性和战斗预告统一调用这份范围。法师先对实际候选位置、真实角色状态和每个法术分别筛选，才从能够命中该目标的法术中抽选；删除旧固定三格判断与另一份预告几何。候选目标只使用id查当前PlayLoop真值，不能用旧目标快照欺骗存活／阵营校验。没有合法目标时不消耗RNG或资源。

当前目标存活、自己不可攻击、player_controlled/friendly_ai对enemy_ai的敌我关系沿已明确的产品role适配；未知role拒绝。它不冒充原全部pm组合、所有状态资格或AI目标mode选择。最少位移／来源顺序、施法倾向、同候选随机抽选仍是已有重制AI策略；新代码先检查是否有合法计划再抽倾向，以避免失败查询消耗随机数，这个顺序不宣称原AI等价。

811项新Godot检查逐格核对来源范围和地图边界、Magic/Special不同mode、当前/已死/失效/友军/未知角色、非法矩阵、未实现function不误伤，以及两种不同来源范围时AI仅选择真正够得到的法术。费用212项、行动508项、core和第一战运行时回归通过。首次新增GDScript的String/Vector2i类型推断编译失败已修正，并完成编译检查、终止该失败测试进程后重跑；没有把脚本输出0误当编译成功。

```sh
python3 tools/hsl.py check skill_target_data
uv run --with unicorn==2.1.4 python3 tools/hsl.py generate skill_target --exe $HSL_ORIGINAL_DIR/hsl01.exe
godot --headless --path . --script res://tests/run_skill_resolution_tests.gd
```

无EXE/PAK参数只核对保存证据；不用runtime原函数仿真。完整门禁最终结果保存于本批提交说明，Control验收见 [skill_targets](../runtime_observations/skill_targets/README.md)。下一项仍是能力拥有权、原不可行动／目标状态位与各效果应用。
