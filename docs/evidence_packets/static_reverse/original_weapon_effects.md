# 普通交锋尾部：武器附毒、未来行动取消与防护

> evidence: static-derived · status: live · functions: 0x406fe0, 0x407550, 0x409110, 0x4091b0, 0x409210, 0x409240, 0x4092d0, 0x409310, 0x409460, 0x4095e0, 0x40e240, 0x40e2f0, 0x4423c0, 0x448420, 0x448840 · tools: capture_weapon_effect_review.gd, hsltools/data/weapon_effect_trial.py, hsltools/probes/weapon_effect.py, run_weapon_effect_tests.gd, test_hsl_weapon_effects.py · updated: 2026-09-22

本批沿已有extra_attack／EXP caller的确定性符号继续，未调用Jev。`hsl01.exe`身份由共用PE映像校验固定；完整回执为[original_weapon_effects.json](original_weapon_effects.json)，复跑工具为[原指令探针](../../../tools/hsltools/probes/weapon_effect.py)。原始EXE／PAK只读。原公式与Godot整合分别验证，表字段／名字不单独构成行为证据。

## 系统对照与选择

| 差距 | 现有基础与本次选择 |
| --- | --- |
| 武器附带状态及取消行动 | 普通／反击系列、三状态、唯一队列与最终EXP均已有证据；原caller明确调用同一尾部，能形成完整装备→交锋→后续回合链，优先实现 |
| 伙伴自动成长、jobWise与动态学技 | 当前三职业及039固定模板可复用，但需要新增职业分支和进入／学技调用证据；另列下一工作，不借用现有职业公式 |
| 弱化、随机多状态、MP打击、复活 | MP打击（108）与 0x409310 状态字（衰弱／禁魔／麻痺／随机位，R27）已接入，见下「状态字与随机异常」；复活仍明确拒绝 |
| 脚本计时与原步行速度 | presentation已登记非阻塞请求；精确原timer源／每tick步长仍需新证据，不把当前演出时间重标为原版 |

## 原指令执行边界

| 入口 | 实际执行 |
| --- | --- |
| `0x4095e0` | 158组完整helper返回，执行取消→状态→未启用MP打击检查；覆盖无效果、单独／共同位、免疫、已有毒、上限、死亡后记录和32组固定RNG种子 |
| `0x407550` | 15组完整队列取消返回；当前索引前后、已禁用槽、无候选和重复目标指针分别验证 |
| `0x4423c0` phase4 | 24组真实EXP caller；实际执行每击EXP换算后，根据剩余击数／HP／贡献进入原效果链，止于后续动画或气力调用前；无贡献的已结束分支正常返回 |
| `0x448840` | 18组装备／既有状态输入，各刷新两次，共36次完整返回；刷新前故意污染效果位，确认清除再OR，HP／MP／EXP／气力／原状态不被重放 |
| ITEM loader返回后的三段 | 12组有界原指令，分别检查`attack_cancel`、`attack_poison`、`keep_status_good`的零／非零值和保留其他位；止于下一字段读取前，不宣称完整文本parser返回 |
| `0x4095e0` → `0x409310` 状态字（R32） | 176组完整返回：目标为完整 PLAYERS 记录（先跑一次 `0x448840`，衰弱 helper 内的 `0x448840` 真实执行并夹 HP／MP），攻击者字为 衰弱／禁魔／麻痺 单独位各 34 种子、四位同置、`random_status_error` 16 个分段边界种子、随机位＋全部直接位、七种饰品免疫组合、八种既有状态字、四角色两等级、HP 1000／30／1／0 |
| ITEM loader 状态字四段 | 16组有界原指令：`attack_weaken`／`random_status_error`／`attack_nomagic`／`attack_paralysis` 零／非零值与保留其他位 |

所有原callee保持原指令，不跳过／替换函数。各组入口、停止地址、正常返回标记、原随机bound／value、actor未变范围、队列结果与指令预算均在JSON。ANCHORS将源字段读取、OR位、helper及caller锁到实际字节；离线checker还拒绝结果、原字节、RNG、停止边界和装备刷新被篡改的回执。

## 触发时机与经验顺序

原`0x4423e7..0x44240b`先以本击实际伤害换算EXP。目标仍活且剩余追加击时，经`0x4424be`重新进入攻击动画，**不执行武器尾部**。只有系列最后一击或提前击杀结束系列，并且该击换算EXP大于0，才经`0x442489`调用`0x4095e0`。因此最后一击落空不会补触发先前一击的效果；多击、暴击或覆盖多个身体格也不增添概率次数。

主攻与反击系列各自使用自己的末击、当前装备和原随机链。顺序是实际HP损失→本击EXP换算→末击附带效果→系列气力；整场交锋全部结束后才沿既有规则发放各行动者的最终EXP并升级。武器附毒和取消行动**没有追加技能贡献**，不能套用法术中毒的持续时间贡献公式。原helper可在HP0记录上写入毒状态；Godot保留接受的抽样顺序，然后由共用死亡出口清理状态、释放占格，不显示尸体仍中毒。

## 当前装备来源

| 装备 | 源规则与当前接入 |
| --- | --- |
| 29 鎮魂之斧 | `attack_cancel → 0x10000`；每次合格系列末击抽1..100，≤10请求取消一个未来行动槽；当前job94及其源职业mask |
| 35 毒牙／37 針 | `attack_poison → 0x200000`；先查目标防毒／通用防护，再抽1..100，≤25附毒；当前job94 |
| 144 聖護服 天映 | `keep_status_good → 0x80`；源剑士系资格，当前job80可装；不授予法师或兽战士 |
| 229 彩霞的聖石 | 同一通用防护位；源`jobAllNoPlayer8`资格，当前角色按实际mask判定 |

所有效果由当前六槽求OR；换装、升级与读档不缓存另一份能力值。0x80使已有三种状态应用入口免疫中毒／禁魔／麻痺；不清除已存在的状态，也不保护行动槽免于取消。两个防护来源不会重复应用。其余状态分支仍未开放。

附毒成功后追加`rand(2)+1`次剩余持续时间，上限9；强度为`24-rand(9)+rand(9)`，范围16..32。已有毒强度为p时取`max(p, floor((p+sample)/2))`，保留其他状态计时。它与魔法的2..3次采样域不同，状态合并共用，而新增武器入口单独校验1..2；没有放宽旧法术合同。

## 状态字与随机异常（2026-09-22 lane R27 读法；2026-09-22 lane R32 有界原生执行，static-derived＋native receipt）

`0x4095e0` 依次调 `0x4092d0`（取消，位 0x10000）、`0x409310`（状态字）、`0x409460`（MP 打击，位 0x400000）。`0x409310` 的读法（下表每行都已由 [original_weapon_effects.json](original_weapon_effects.json) `status`／`status_mapping` 回执逐字节核对）：

| 步骤 | 原指令 | 重制 |
| --- | --- | --- |
| 状态字 = 攻击者 live `+0x18c`（0x448420 对六槽 OR item+0xa0；ITEM loader `0x4477c0`：`attack_weaken→0x20000`、`random_status_error→0x40000`、`attack_nomagic→0x80000`、`attack_paralysis→0x100000`、`attack_poison→0x200000`） | 反编译 `0x409310` 首行 | `equipment.py WEAPON_EFFECTS` 五位；`WeaponEffectRules.effects` 对六槽 OR（饰品 209 詛咒戒指 与武器同样进字） |
| 位 0x40000 时 `r = rand(100)+1`，字**替换**为一位：`r<25` 衰弱 0x20000、`r<50` 禁魔 0x80000、`r<75` 麻痺 0x100000、否则中毒 0x200000 | `((0x4a < r) - 1 & 0xfff00000) + 0x200000` 即 50..74 → 0x100000、75..100 → 0x200000 | `resolve`：`random_status` 收据 `{roll, selected}`；原装备字的其它位在该击不再判定 |
| 每位：`0x40e2f0(目标, 免疫位)`（＝目标 `+0x18c & (位 | 0x80)`）为 0 才 `rand(100)+1 < 26` | 衰弱免疫 0x2000000（`avoid_weaken`）、禁魔 0x1000000、麻痺 0x4000000、中毒 0x800000 | `Protection.modifiers` 的 effects；免疫时不抽 |
| 应用 helper：`0x409240` 衰弱（flag 8，`+0x38` 低字 += rand(2)+1 封 9，`+0x3a` 强度 `0x406fe0(3,7)`＝5−rand(3)+rand(3) 与旧值取 max(old,(old+new)/2)，然后 `0x448840`）；`0x409210` 禁魔（flag 2，`+0x34` += rand(2)+1 封 9）；`0x409110` 麻痺（flag 4，`+0x3c` += rand(2)+1 封 9）；`0x4091b0` 中毒（既有 16..32） | 四个 helper 反编译 | `StatusEffectRules.weapon_status(key, turns 1..2, power)`；衰弱后 `ProgressionRules.refresh_growth_stats`（`resolve` 的 `struck` 参数取击后 HP 再夹上限，PlayLoop 传当前守方） |

数据：ITEM 只有 51（attack_weaken）、66（attack_nomagic）、71／209（random_status_error）、220（avoid_weaken）非零；`attack_paralysis` 无行，随机位仍可选中麻痺分支。R21 字段审计曾把 attack_weaken／attack_nomagic／avoid_weaken 记为 dead——各有 1 行，本波更正。71 朧月 仍因 `range6CellShoot` 未支持而不可装。

### R32 原生回执（`hsltools/probes/weapon_effect.py` `status`，176 组；`status_mapping` 16 组）

探针在 `0x4095e0(owner, target)` 上执行，目标是用 PLAYERS 行与 ITEM 行铺出的完整记录（`stat_magic.put_actor`），先真实跑一次 `0x448840` 得到装备派生的免疫字与 HP／MP 夹值，再进入效果链；所有 callee（`0x40e2f0`／`0x40e240`、`0x42c780`、`0x406fe0`、四个 helper、`0x448840` 全段）保持原指令。独立模型 `status_expected` 只吃回执里的原随机 bound／value 序列、PLAYERS／ITEM 源表与 `model/jobs.calculate`，不复算 RNG。离线 `hsl check weapon_effect` 还强制覆盖：四个随机分段各至少一次且 roll 恰为 1／24／25／49／50／74／75／100（种子 15／53／76／99／62／462／239／77／343／743／55／1655／209／20／387／40）、直接位 roll 恰为 25（成功）与 26（失败）（种子 62／231）、四个 helper 各有被调与被跳过。

| 探过的组合 | 原生结果（与重制 `WeaponEffectRules.resolve`／`StatusEffectRules.weapon_status` 零差异） |
| --- | --- |
| 随机位分段 | roll 1／24 → 衰弱，25／49 → 禁魔，50／74 → 麻痺，75／100 → 中毒；整字被替换（随机位＋全部直接位时只判定被选中的一位） |
| 每位判定 | `rand(100)+1` 25 成功、26 失败；免疫先于抽样（免疫时不消耗随机数） |
| 衰弱 helper `0x409240` | flag 8；`+0x38` 低字 += rand(2)+1 封 9；强度 `5−rand(3)+rand(3)`，既有强度 p 时 `max(p, trunc((p+new)/2))`（0x50003→0x50004、0x30008→0x30009／0x40009、0x70001→0x70002）；随后 `0x448840`：live 四属性各减强度（下限 1）、攻防速／HP／MP 上限重算、当前 HP／MP 夹到新上限（满血目标 39→30） |
| 禁魔 `0x409210`／麻痺 `0x409110` | 低字 += rand(2)+1 封 9；禁魔保留高字（0x10008→0x10009），麻痺按整 dword 封 9（域内 ≤9 与重制一致） |
| 中毒 `0x4091b0` | 与既有 158 组同一模型（16..32 强度、1..2 回合、封 9） |
| 免疫来源 | 饰品 220（0x2000000）／219（0x1000000）／211（0x4000000）／217（0x800000）／229（0x80 全免）由 `0x448420` 从 item+0xa0 OR 进 `+0x18c`；无魔法记录另带 `0x4000`（`0x44b7b8`，与免疫无关） |
| HP | 目标 HP 1000／30／1／0：只有衰弱触发时 `0x448840` 才重夹；HP 0 记录照样写入状态（重制沿死亡出口清理） |

差异清单：以上组合零差异；重制 `struck` 参数（击后 HP 再夹上限）与原生记录 HP 即击后 HP 同义。边界：麻痺高字非零（重制 `unsupported_paralysis_counter` 拒绝）与 `0x409460` MP 打击位未在本组输入内；`run_weapon_effect_tests.status_word` 仍以固定 draw 序列复核同一分段与存档往返。

## 行动取消不是麻痺跳过

`0x407550`只扫描当前队列索引之后的槽，清除第一个目标指针相同且仍启用的资格位；当前／过去槽不动，无候选时返回0。10%成功抽样不保证实际取消：没有未来资格就不显示取消提示。原附带链没有在取消后终止当前反击；当前行动者的白光之翼第二行动也不会因反击请求取消而消失。

Godot以`CoreTurnQueue.cancel_pending`更新现有`slots[].enabled`，保存该结果；不改unit身份／HP／占格，不把它换成麻痺flag或另造跳过动作。被取消者这轮不会进入行动入口，因此不执行自己的毒伤、状态扣次、自动回复或额外行动检查。下一次正常重建队列恢复其资格。原麻痺入口仍是选中后消耗一次尾部，两者有不同回合节奏。

玩家主动取消是另一个已存在的阶段合同：取消目标选择保留已接受的移动，撤回移动才恢复原点和移动资格；已经确认的装备和既有状态不回滚。取消不触发武器效果、不扣资源、不推进队列，第二行动重新选择也不重发第一行动收据。提交交锋后则必须等演出完成，不能取消已发生的命中；这些交互组合复用原阶段证据与现行可逆选择，不将它们冒充`0x407550`的用途。

## 游戏整合与反馈

`WeaponEffectRules`只返回当前装备、目标状态与队列的纯提案。PlayLoop在两侧完整输入检查之后抽样并提交，末击保存不可变`weapon_effects`与`defender_after`；后续AI基于新状态重新选择解毒、攻击或资源退路。法术／支援／物品不调用普通武器尾部。装备预览显示能力获得／移除，防护注明不治旧状态；逐击窗口在对应impact之后才显示中毒／免疫或本回合行动取消，前一击和升级前数值不泄漏未来结果。

`I_STING.SHP`与已确认的I_CLAW同为原36字节空图，清单保留真实空资源和武器名称；RESOURCE.H没有同名sting命中别名，目前仅播放源角色攻击声一次，不挪用刀剑图或捏造第二个音效。正式第一／第二战库存、技能和编队没有额外赠送。

本批回归入口：`tests/run_weapon_effect_tests.gd`、`tests/capture_weapon_effect_review.gd`、`tools/test_hsl_weapon_effects.py`。原概率不为实玩调成100%，实际控件路线记录有限重试次数；完整门禁的终端退出码写入提交说明。`WeaponEffectsTrial.tscn`为可手动操作的独立演练，由`hsltools/data/weapon_effect_trial.py`生成：原地图与039三职业刷新，额外HP及供换装的库存明确标为开发设置，正式编队和初始授予不变。

[十五条实际控件与十六张图证](../runtime_observations/weapon_effects/README.md)分别记录主攻／反击末击、取消未来槽、防护与驱毒、阶段取消重选、第二行动／换装／成长、AI耗魔／禁魔／无有效动作、手动开发入口和三终态。每个进程只采用已完成的具名范围，失败夹具、缺失旧终端退出码与最终退出0均单独说明。替换装备后的效果位还在同一库存提交前验证，避免错误来源进入可恢复状态。

## 明确边界

仅恢复上述普通尾部子链（含 R27 读出、R32 原生执行的 0x409310 状态字与随机异常）、通用防护在四状态中的效果和现有队列适配，不宣称完整战斗dispatcher、复活、所有角色职业、原全局RNG或精确原演出时间已恢复。caller的气力／动画调用停止点有意保留；其已有独立证据可复用，不能将本包前段写成整个原函数正常返回。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleLoopCombat.gd` rules：series-end cancel／protect／poison tail, 0x4075a0／0x407550 queue effects
