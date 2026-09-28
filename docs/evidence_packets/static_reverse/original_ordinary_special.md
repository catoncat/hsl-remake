# 普通交锋与氣刃斬：物理伤害、武器附加、暴击／反击与绝技公式

> evidence: static-derived · status: live · functions: 0x409a60, 0x409af0, 0x409be0, 0x40a7b0, 0x40aa80 · tools: hsltools/data/equipment.py, hsltools/data/first_battle_formation.py, hsltools/probes/physical.py, hsltools/probes/special_damage.py, run_ordinary_special_tests.gd · updated: 2026-09-28

## 结论

- 原版普通伤害由攻防差与力量差分段取基础量，加随机扰动，再加武器元素附加，然后判命中、暴击（1.5–2 倍，≤32767）；反击取普通抽样量 80% 后独立判命中与暴击，不会反击再反击；源 0 反击刷新为 12、源 0 暴击为 8（static-derived）。
- 氣刃斬（magicOTHER）走 `0x40a7b0` channel1：命中含累计补偿，三角取值加等级、体质、精神、反应随机项再乘倍率；物理防御、元素抗性、魔击力与魔法命中装备都不进入（static-derived）。
- 重制：`SpecialDamageRules` 与普通伤害规则只出提案，`SkillResolutionRules`／PlayLoop 唯一提交；收据分存 `queued_damage`（积气用）、`damage`（impact 值）、`actual_damage`（封顶后扣血，进经验与显示）（static-derived）。
- 差异：暴击回调仅确认派发事件 0x302；原版飘字只有数字，「暴擊」说明字是重制反馈，只在 OPT-INFO＝公開 下显示（remake-invented，`BattlePresentation.strike_words`）。

## 证据

**static-derived**（EXE 由公共加载器锁定 SHA-256；结果见 [original_physical_combat.json](original_physical_combat.json)、[original_special_damage.json](original_special_damage.json)）

| 原入口／停止点 | 覆盖 | 支持的结论 |
| --- | --- | --- |
| `0x409be0`、`0x409af0`、`0x409a60` 正常返回 | 148 组普通伤害、武器附加、命中 | 正／负力量差、弱伤害分段、元素 0..5、等值／逆序范围与抗性；随机参数与调用顺序 |
| `0x403f39` → `0x403ff6`／`0x403ff1`／`0x4041ea` | 24 组命中、落空、暴击前段 | 命中后才抽暴击；低伤害补足与 32767 上限 |
| `0x409d06` → `0x409d49` | 6 组低伤害修正后缀 | raw 随机值低四位折算 |
| `0x4489bd` → `0x448a1e` | 4 组概率刷新后缀 | 源 0 反击改 12、源 0 暴击改 8，非零保留 |
| `0x40a7b0` channel1／proc0 正常返回 | 20 组氣刃斬 | 命中先后、等级上限、反应／精神／体质、倍率；防御／抗性／魔法命中装备不进入 |
| `0x40aa80` → `0x40ab87`／`0x40abb0` | 24 组绝技 HP 应用前段 | 剩余 1／20／1000HP、落空／命中、禁攻击旁路与原贡献 |

物理入口是 `0x409be0`（旧 `0x409bca` 为前一函数后的填充）；武器字段 +0xc4 元素类型、+0xc8 low、+0xcc high。

普通伤害（整数截断）：

| 步骤 | 规则 |
| --- | --- |
| 基础 | `base=攻击−防御`，`d=clamp(力量差/2, −20, 30)`；base≤0：rand(5)+3；base 1..9：rand(base+4) 加 7／8／9（边界 2、6），两支把负 d 置 0；其余基础量＝base，d 下限提到 `−base/2` |
| 扰动 | `基础量+d−rand(基础量×30/100)−rand(abs(d)/2)+rand(abs(d)/2)`；`rand(0)` 照常调用（返回 0，见 [original_damage_random.md](original_damage_random.md)）；极低结果按 raw 低四位折回正值 |
| 武器附加 | 类型 −1 关闭；启用时 `low+rand(abs(high−low))`，零改 1，再加 rand(取值/2)；元素 0..4 按对应抗性（≤80）乘算，类型 5 不乘；进入普通伤害后才判命中与暴击 |
| 暴击 | 命中（0..99）后 `rand(100)+1` 与暴击率比较；伤害 <6 时重复加 2+rand(5)；`floor(1.5D)+rand(abs(2D−floor(1.5D)))+1`，≤32767 |
| 反击 | 普通抽样量 ×80% 后独立判命中与暴击 |
| 积气输入 | `0x44248e` 传 queued 伤害给气力 helper（见 [original_stamina.md](original_stamina.md)）；例：queued 20、暴击 31、目标 60HP → 气力按 20，经验贡献 31；目标剩 1HP 时贡献与显示都为 1 |

氣刃斬：源 damage 36..54、命中 98、attackpow_ratio 100、20ST；命中 `rand(100)+1 <= 命中+累计补偿`，目标 no_attack 走原旁路，落空补偿加该次 roll/10，命中清零；取值 `max(low, low+half−rand(half+1)+rand(half+1))`，`half=abs(high−low)/2`；等级夹 1..120，加 rand(等级×180/100)、rand(等级×150/100)、体质/8、精神/4、反应/3，乘倍率后做原低值处理。

**resource-derived**：Leonard 源暴击 14（保留，不覆盖为 8）；装备 6 名劍 狂嵐 加风属性附加，7 死靈血刃 暴击 +10，216 墨鏡 +16，Leonard 14→24→40。

**runtime-measured**：原版录像 V06 的 5／22 等数字只证明实际扣血显示，不是固定公式。

## 重制接线

- 普通伤害与氣刃斬规则由 `SpecialDamageRules` 等纯规则准备提案，`SkillResolutionRules` 管费用、资格、各目标结果与贡献，PlayLoop 唯一提交；一次扣费、取消无损、落空付费、禁魔不禁绝技、绝技无反击。
- `ProgressionRules` 在升级与换装时从源值与当前六槽重算反击、暴击与武器附加；`hsltools/data/equipment.py` 恢复 magic_attack_type 三字段并开放 add_weapon_dmgx2；`hsltools/data/first_battle_formation.py` 与第二战生成器共享概率字段与 no_attack。
- 表现：特写显示 actual_damage，反击用自身收据；暴击说明字只在 OPT-INFO＝公開 下于 impact 后出现；装备详情页内容可滚动、按钮固定（provisional）。

## 复现

`python3 tools/hsl.py check physical`；`python3 tools/hsl.py check special_damage`；重制侧 `tools/godot.sh --headless --script tests/run_ordinary_special_tests.gd`。九条 Control 路线与两次默认第一战路线回执（`runtime_observations/ordinary_special/receipt.json`、`default_routes.json`）驱动已退役，回执为历史记录。

## 边界

- 全局 PRNG 身份、任意有符号／超界输入、原完整初始化不在本包。
- 各职业的属性刷新见 [original_job_stats.md](original_job_stats.md)（全部职业按公式表），追加攻击见 [original_extra_attack.md](original_extra_attack.md)；技能与被动已无拒绝项（差异清单 `unimplemented-abilities`）。
- 暴击事件 0x302 的完整画面／音效含义未读。
- 风火公式见 [original_magic_damage.md](original_magic_damage.md)。
