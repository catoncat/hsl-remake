# 普通交锋尾部：武器附毒、状态字、未来行动取消与防护

> evidence: static-derived · status: live · functions: 0x406fe0, 0x407550, 0x409110, 0x4091b0, 0x409210, 0x409240, 0x4092d0, 0x409310, 0x409460, 0x4095e0, 0x40e240, 0x40e2f0, 0x4423c0, 0x448420, 0x448840 · tools: hsltools/data/weapon_effect_trial.py, hsltools/probes/weapon_effect.py, run_weapon_effect_tests.gd · updated: 2026-09-27

## 结论

- 原版只在普通系列最后一击（或提前击杀结束系列）且该击换算 EXP > 0 时调用 `0x4095e0`：依次取消未来行动槽（10%）、按装备状态字判定衰弱／禁魔／麻痺／中毒（随机位先把整字替换为一位）、MP 打击；免疫先于抽样；武器附带效果不追加技能贡献（static-derived）。
- 重制 `game/sim/WeaponEffectRules.gd` 返回纯提案，`game/sim/loop/BattleLoopCombat.gd` 在两侧输入检查后抽样提交末击 `weapon_effects` 与 `defender_after`；取消用 `game/sim/CoreTurnQueue.gd` 的 `cancel_pending` 改 `slots[].enabled`，不是麻痺跳过（static-derived）。
- 一致：158+15+24+36+12+176+16 组原指令结果与重制零差异（static-derived）。麻痺高字非零（重制拒绝 `unsupported_paralysis_counter`）与 `0x409460` MP 打击位不在本组输入内；复活未开放（未读）。

## 证据

**static-derived**（SHA 锁定 EXE，所有 callee 保持原指令；[original_weapon_effects.json](original_weapon_effects.json) 存入口、停止地址、正常返回标记、原随机 bound／value、队列结果与指令预算；ANCHORS 锁定字段读取、OR 位、helper 与 caller 字节）

| 入口 | 执行 |
| --- | --- |
| `0x4095e0` | 158 组完整返回：取消→状态→未启用 MP 打击；无效果、单独／共同位、免疫、已有毒、上限、死亡后记录、32 组固定种子 |
| `0x407550` | 15 组完整返回：当前索引前后、已禁用槽、无候选、重复目标指针 |
| `0x4423c0` phase4 | 24 组真实 EXP caller，止于后续动画或气力调用前；无贡献已结束分支正常返回 |
| `0x448840` | 18 组 × 2 = 36 次完整返回；刷新前污染效果位，确认先清再 OR，HP／MP／EXP／气力／原状态不重放 |
| ITEM loader 三段 | 12 组有界：`attack_cancel`、`attack_poison`、`keep_status_good` 零／非零与保留其他位 |
| `0x4095e0 → 0x409310` 状态字 | 176 组完整返回：完整 PLAYERS 记录（先跑 `0x448840`）；衰弱／禁魔／麻痺单独位各 34 种子、四位同置、`random_status_error` 16 个分段边界种子、随机位＋全部直接位、七种饰品免疫组合、八种既有状态字、四角色两等级、HP 1000／30／1／0 |
| ITEM loader 状态字四段 | 16 组有界：`attack_weaken`／`random_status_error`／`attack_nomagic`／`attack_paralysis` |

触发时机：`0x4423e7..0x44240b` 先按本击实际伤害换算 EXP；目标存活且有余击时经 `0x4424be` 重入动画，不执行尾部；系列末击且 EXP > 0 经 `0x442489` 调 `0x4095e0`。末击落空不补触发；多击、暴击、多身体格不增加概率次数。顺序：HP 损失→本击 EXP→末击效果→系列气力→整场交锋后最终 EXP 与升级。原 helper 可在 HP0 记录上写毒状态。

状态字 `0x409310`：

| 步骤 | 原读法 |
| --- | --- |
| 字来源 | 攻击者 live `+0x18c`（`0x448420` 对六槽 OR item+0xa0）；ITEM loader `0x4477c0`：`attack_weaken→0x20000`、`random_status_error→0x40000`、`attack_nomagic→0x80000`、`attack_paralysis→0x100000`、`attack_poison→0x200000`；`attack_cancel→0x10000`、`keep_status_good→0x80` |
| 随机位 0x40000 | `r = rand(100)+1`，字替换为一位：`r<25` 衰弱、`r<50` 禁魔、`r<75` 麻痺、否则中毒（`((0x4a < r) - 1 & 0xfff00000) + 0x200000`）；其他位该击不判定 |
| 每位判定 | `0x40e2f0(目标, 免疫位)`＝`+0x18c & (位 | 0x80)` 为 0 才 `rand(100)+1 < 26`；免疫时不抽。免疫位：衰弱 0x2000000、禁魔 0x1000000、麻痺 0x4000000、中毒 0x800000 |
| `0x409240` 衰弱 | flag 8；`+0x38` 低字 += rand(2)+1 封 9；强度 `0x406fe0(3,7)` = 5−rand(3)+rand(3)，既有 p 时 `max(p, trunc((p+new)/2))`；随后 `0x448840`：四属性各减强度（下限 1）、重算上限并夹当前 HP／MP |
| `0x409210` 禁魔／`0x409110` 麻痺 | flag 2／4；`+0x34`／`+0x3c` += rand(2)+1 封 9；禁魔保留高字，麻痺按整 dword 封 9 |
| `0x4091b0` 中毒 | 追加 `rand(2)+1` 次封 9；强度 `24-rand(9)+rand(9)`（16..32），既有 p 时 `max(p, floor((p+sample)/2))` |
| `0x4092d0` 取消 | 每次合格末击抽 1..100，≤10 请求 `0x407550`；只扫描当前索引之后的槽，清第一个同目标指针且启用的资格位，无候选返回 0 |

原生读数（与重制零差异）：随机分段 roll 1／24 → 衰弱，25／49 → 禁魔，50／74 → 麻痺，75／100 → 中毒（种子 15／53／76／99／62／462／239／77／343／743／55／1655／209／20／387／40）；直接位 roll 25 成功、26 失败（种子 62／231）；衰弱强度 0x50003→0x50004、0x30008→0x30009／0x40009、0x70001→0x70002；满血目标衰弱后 39→30；禁魔 0x10008→0x10009；只有衰弱触发时才重夹 HP；HP 0 记录照写状态。无魔法记录另带 `0x4000`（`0x44b7b8`，与免疫无关）。取消后当前反击不终止，行动者的第二行动不消失。

**resource-derived**

| 装备 | 源规则 |
| --- | --- |
| 29 鎮魂之斧 | `attack_cancel`；源职业 mask 含 job94 |
| 35 毒牙／37 針 | `attack_poison`；先查防毒／通用防护，再抽 ≤25 附毒 |
| 144 聖護服 天映 | `keep_status_good`（0x80）；剑士系资格 |
| 229 彩霞的聖石 | 同一通用防护位；`jobAllNoPlayer8` |
| 免疫饰品 | 220（衰弱）、219（禁魔）、211（麻痺）、217（中毒）、229（0x80 全免） |

ITEM 状态字非零行：51（attack_weaken）、66（attack_nomagic）、71／209（random_status_error）、220（avoid_weaken）；`attack_paralysis` 无行，随机位仍可选中麻痺。71 朧月的 `range6CellShoot` 走 `0x40f8b0` 通用传播，可装。`I_STING.SHP` 为 36 字节原空图；RESOURCE.H 无 sting 命中别名。

## 重制接线

- `game/sim/WeaponEffectRules.gd`：六槽 OR 效果（饰品 209 与武器同样进字）、`resolve` 输出 `random_status {roll, selected}`；`Protection.modifiers` 给免疫；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_weapon_effects.md`。
- `game/sim/loop/BattleLoopCombat.gd`：系列末 cancel／protect／poison 尾部与 `0x4075a0`／`0x407550` 队列效果；`struck` 取击后 HP 再夹上限。
- `game/sim/StatusEffectRules.gd` `weapon_status(key, turns 1..2, power)`；衰弱后 `ProgressionRules.refresh_growth_stats`。武器入口单独校验 1..2 回合，不改法术 2..3 合同。
- `tools/hsltools/data/equipment.py` `WEAPON_EFFECTS` 五位。
- 取消：`CoreTurnQueue.cancel_pending` 改 `slots[].enabled` 并保存；被取消者当前轮不进行动入口，不执行毒伤／状态扣次／自动回复／额外行动检查，下次重建队列恢复。0x80 免疫不清既有状态、不防取消。
- 死亡出口清理 HP0 目标的状态与占格，不显示尸体中毒。逐击窗口在对应 impact 后才显示中毒／免疫／行动取消；针武器只播源角色攻击声一次（provisional）。
- 玩家取消目标选择保留已接受移动、撤回移动才恢复原点；取消不触发效果、不扣资源、不推进队列（重制可逆选择，非 `0x407550` 用途）。
- 开发演练 `game/battle/development/WeaponEffectsTrial.tscn`，由 `tools/hsltools/data/weapon_effect_trial.py` 生成；正式编队与初始授予不变。

## 复现

`python3 tools/hsl.py check weapon_effect`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| `weapon_effects/`（目录已删，见 Git 历史） | poison_series、cancel_queue、protected_poison、guard_cure、growth_swap、ai_poison、ai_fallback、ai_silence、ai_wait、ai_cure、phase_cancel、trial、victory、defeat、escape | `hsltools/data/weapon_effect_trial.py`、`run_weapon_effect_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 麻痺高字非零与 `0x409460` MP 打击位未在本组输入内。
- 复活明确拒绝；完整战斗 dispatcher、所有职业、原全局 RNG、精确演出时间未读。
- caller 的气力／动画调用停止点有意保留，前段不等于整个 `0x4423c0` 正常返回。
- ITEM loader 段是有界前段，不是完整文本 parser 返回。
