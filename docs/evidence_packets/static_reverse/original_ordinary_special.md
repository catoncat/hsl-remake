# 普通交锋、武器附加与氣刃斬

> evidence: static-derived · status: live · functions: 0x409a60, 0x409af0, 0x409be0, 0x40a7b0, 0x40aa80 · tools: hsltools/data/equipment.py, hsltools/data/first_battle_formation.py, hsltools/probes/physical.py, hsltools/probes/special_damage.py, run_ordinary_special_tests.gd · updated: 2026-09-17

2026-09-17。基线为已提交的原风火／最终EXP及移动友军援助。该批将普通伤害、武器附加、暴击／反击概率和氣刃斬接入同一可玩战斗链；不以数值 helper 的正常返回宣称原游戏全局状态机或演出完全等价。

## 系统对照与本批选择

对照输入为 [当前项目](../../PROJECT.md)、[机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md)、[原录像V01–V10](../runtime_observations/original_gameplay_reference/README.md)、源PLAYERS／ITEM／SPECIAL，以及下方锁定EXE的原指令结果。上一批[友军援助](original_ai_support.md)已完成治疗、范围驱毒和真实药品的移动支援，十条真实控件路线及默认撤离通过；这些结果直接复用。

| 体验维度 | 本批前的实际差距 | 连贯实现 |
| --- | --- | --- |
| 核心循环、战斗节奏 | 普通攻击缺暴击；默认角色反击为0；氣刃斬仍是表值减防御 | 接入原数值／基础概率，攻击与反击各自命中、暴击、扣HP，氣刃斬采用独立能力公式 |
| 敌人、交互与站位 | 已有武器范围、敌我判断、可达规划和一次交接；新反击会使近身选择有实际代价 | 复用已有合法目标及路径，存活且可反击者至多响应一次；技能和远距离资格保持原有校验 |
| 操作手感 | 新装备被动仍显示未开放；长效果预览可能超出固定区域 | 原子换装、取消保留、武器附加与暴击／反击变化提示；长预览可滚动，确认按钮保持可见 |
| 数值反馈 | 已结算原EXP，但普通暴击前伤害、实际扣血和气力输入尚未区分 | 收据分别保存queued_damage、damage和actual_damage；气力用前者，经验及可见数字用实际扣血 |
| 角色成长 | 升级／换装会刷新基础数值，但没有完整刷新当前暴击／反击和武器附加 | 从源基础值和当前六槽重新计算；替换武器清除旧附加，升级不会恢复旧装备概率 |
| 镜头、动画、音效 | 原尺寸单人镜头、源动作／氣刃斬素材、出招和命中事件已经接通 | 复用既有镜头和音效时序，在impact后才显示暴击与实际伤害；整次反击演出后再发奖／交接 |
| 胜利、撤离与保存 | 原经验按动作发放，终态和存档已有公共链 | 原普通／绝技贡献沿同一经验换算，最后击杀先收尾再结果；存档校验新增物理字段，恢复不重放 |

选择依据是这些差异直接改变每次普通交锋和绝技的收益、击杀数、气力与经验，覆盖默认第一战。没有重复修复已成立的水系特效、风火落点或友军扫描；下轮地图搜索／目标持有仍需独立证据。

## 原指令证据与边界

原EXE仍由公共加载器锁定SHA-256；未修改原文件，也未给未知callee提供stub。正常checker读取已保存结果，只有`--execute`重新运行原指令。

| 原入口／停止点 | 覆盖 | 可以支持的结论 |
| --- | --- | --- |
| 0x409be0、0x409af0、0x409a60正常返回 | 148组普通伤害、武器附加和命中 | 正／负力量差、弱伤害分段、元素0..5、等值／逆序范围和抗性；随机参数和调用顺序与独立模型一致 |
| 0x403f39→0x403ff6／0x403ff1／0x4041ea | 24组命中、落空、暴击前段 | 先检查已抽取的命中值；命中后才抽暴击，暴击有低伤害补足和32767上限；停在回调前 |
| 0x409d06→0x409d49 | 6组低伤害修正后缀 | 原raw随机值低四位及折算规则，不伪装完整普通函数触发该分支 |
| 0x4489bd→0x448a1e | 4组概率刷新后缀 | 源0反击改12，源0暴击改8，非零原值保留；不是全角色初始化 |
| 0x40a7b0，channel1/proc0正常返回 | 20组氣刃斬 | 命中先后、等级上限、反应／精神／体质、倍率；防御／抗性和魔法命中装备不进入magicOTHER数值 |
| 0x40aa80→0x40ab87／0x40abb0 | 24组绝技HP应用前段 | 剩余1／20／1000HP、落空／命中、禁攻击资格旁路与原贡献；停在显示与EXP回调前 |

机器结果：[普通交锋](original_physical_combat.json)、[氣刃斬](original_special_damage.json)。工具：[physical probe](../../../tools/hsltools/probes/physical.py)、[special probe](../../../tools/hsltools/probes/special_damage.py)。原物理入口明确为`0x409be0`；旧`0x409bca`是前一个函数后的填充，已修正当前compact入口。武器三字段也更正为`+0xc4=元素类型`、`+0xc8=low`、`+0xcc=high`。

## 普通伤害、暴击和气力

以下除法均为整数截断。令`base=攻击−防御`、`d=clamp((力量差)/2,−20,30)`。base≤0时基础量为rand(5)+3；base1..9时为rand(base+4)加7／8／9（边界2和6）。这两支把负d置0；其余基础量等于base，并将d的下限提高至`−base/2`。

其后伤害为`基础量+d−rand(基础量×30/100)−rand(abs(d)/2)+rand(abs(d)/2)`。`rand(0)`依然调用原生成器（返回0，不推进伤害流，见[伤害随机流](original_damage_random.md)）；它不是rand(1)，也不能从原顺序删除。极低结果使用原raw随机值的低四位折回正值。Godot测试用每次原bound/value回放，而非只比较最终平均伤害。

武器元素类型−1关闭附加。启用时抽`low+rand(abs(high−low))`，因此high通常为不含端点，而等值范围仍调用rand(0)。零取值改1，再加rand(取值/2)，处理低于3的原折算。元素0..4按目标对应抗性（最高80）乘算；类型5不乘元素抗性。此附加进入普通原伤害，随后才判断命中、暴击。

命中沿现有0..99原抽样；命中后以rand(100)+1与当前暴击率比较。暴击时若伤害不足6，重复加2+rand(5)，然后使用`floor(1.5D)+rand(abs(2D−floor(1.5D)))+1`，最高32767。反击先对普通抽样量取80%，再独立判断命中与暴击，不能把最终暴击量简单乘80%。不会反击再反击。

`0x44248e`把全局queued伤害传给气力helper，而实际HP扣除已经可能因暴击变大。因此收据中`queued_damage`用于[原积气](original_stamina.md)，`damage`保存impact值，`actual_damage`／`native_contribution`为剩余HP封顶后的扣血，进入[最终EXP](original_experience.md)。例如queued20、暴击31、目标60HP：气力仍按20判轻击，经验贡献31；目标只剩1HP时贡献和显示都为1。

## 角色数据、装备与成长

源PLAYERS零反击不等于最终概率0；原刷新把它置12，零暴击置8，然后应用装备增量。Leonard的源暴击本身为14，必须保留14，不能统一覆盖成8。`hsltools/data/first_battle_formation.py`和第二战生成器共享这些字段；源no_attack也显式生成。初始气力0和已有技能授予保持其已批准政策；NPC 等级按原出生调级（[original_auto_growth](original_auto_growth.md)）。

`hsltools/data/equipment.py`恢复原magic_attack_type三字段并开放已实现的add_weapon_dmgx2，其他未支持非零被动仍拒绝。实际换装6（名劍 狂嵐）增加风属性附加；替换为7（死靈血刃）移除旧风附加、给暴击加10；216（墨鏡）再加16。Leonard对应14→24→40。来源字段、换装事务和成长刷新使用同一catalog，不在UI缓存第二套效果。

`ProgressionRules`在升级及换装时从source/current equipment重算反击、暴击和武器附加；原子预检拒绝缺失或非法字段。单战存档校验也包含这些必需字段。其他职业完整refresh、额外攻击被动和原完整初始化仍未由本批恢复。

## 氣刃斬与公共事务

源能力是magicOTHER/code01，伤害区间36..54、命中98、attackpow_ratio100和已验证的20ST费用。channel1先按`rand(100)+1 <= 原命中+累计补偿`判断；目标no_attack沿原旁路。落空只增加该次one-based roll/10补偿，命中清零。

命中后的三角取值为`max(low,low+half−rand(half+1)+rand(half+1))`，`half=abs(high−low)/2`。等级夹到1..120；加入rand(等级×180/100)、rand(等级×150/100)、体质/8、精神/4、反应/3，再乘来源倍率并做原低值处理。物理防御、元素抗性、魔擊力和魔法命中装备均不进入本能力的magicOTHER公式。

`SpecialDamageRules`只准备及提案，`SkillResolutionRules`共同拥有费用、资格、各目标结果与贡献换算，PlayLoop仍是唯一提交者。一次扣费、取消无损、落空付费、禁魔不禁止绝技、无普通积气返还、无物理反击均沿现有合同。当前氣刃斬源效果为单体；已有风火／状态／驱毒多目标事务继续复用，不把该单体能力改成未证实的范围攻击。

## 表现与验证解释

原录像V06中的5／22等数字只证明同次过程的实际扣血显示，不能作为固定公式。普通与绝技特写现在显示actual_damage；暴击标识在impact之后出现，反击使用自身收据。原动作帧、武器命中声和绝技attack.wav沿既有事件播放一次。原暴击回调仅确认派发事件0x302，未进一步恢复其完整画面／音效含义；新增“暴擊”文字是明确的重制反馈，不冒称原字体或专属原声。

装备详情与确认页显示当前概率／元素变化；内容在原面板区域内滚动，固定按钮不随内容离屏。界面保持只读；不能由刷新画面重抽伤害或发经验。真实Control演出、两种装备、终态和默认第一战的回执见[普通／绝技可玩验收](../runtime_observations/ordinary_special/README.md)。

```sh
python3 tools/hsl.py check physical
python3 tools/hsl.py check special_damage
python3 -m unittest tools.test_hsl_physical_special
tools/godot.sh --headless --script res://tests/run_ordinary_special_tests.gd
# 有原EXE时定向重新执行，不启动Wine
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate physical --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate special_damage --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
```

全局PRNG身份、任意有符号／超界输入、原完整初始化、所有额外攻击被动、其它职业、完整地图搜索／目标持有和精确演出时钟仍有独立边界。下一项只在PROJECT维护；本包的正常返回数、应用前段数、Godot断言数和自然游玩次数必须分别报告。
