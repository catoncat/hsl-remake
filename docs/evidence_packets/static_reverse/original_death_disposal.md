# 阵亡演出：遗言之后 16 tick 向上拉伸并淡出

> evidence: static-derived: the dead branches of the battle-actor processes read from hsl01.exe, including when a corpse's map-cell bits are cleared relative to the next actor after attack and counter kills, and the double queue step when the current actor dies; runtime-measured: 505 s1 queue trace; provisional: the 0x2c000000 draw mode's blend · status: live · functions: 0x4072b0, 0x407340, 0x4074a0, 0x407510, 0x407540, 0x407720, 0x407800, 0x409700, 0x40ba20, 0x411b90, 0x43bf30, 0x43ede0, 0x441594, 0x442720, 0x442a90, 0x446c40 · tools: run_actor_traversal_tests.gd, run_combat_aftermath_tests.gd · updated: 2026-09-27

lane R5-L2（2026-09-27）。起因：用户记忆"原版角色死了之后有一个类似灵魂飞出、飞起的演出……把人物拉高，向上下拉伸，然后透明化消失"（user-hypothesis，用户也说"影响不大"）。本包是一次有界静态读（r2 反汇编 `hsl01.exe`，SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，未执行原程序），从 `BattleAftermath` 已注明的死亡分支（遗言读取点 `0x43ef91`／`0x4434b2`）往下读。录像侧：[原版画面参考](../runtime_observations/original_gameplay_reference/README.md) `12_leonard_normal_attack` 的击杀→遗言→KILL 帧未截到该段（用户确认），本包不依赖录像。

## 读法（static-derived）

敌方过程 `0x43ede0`（defProcEnemy）的死亡分支与玩家过程（defProcPlayer）的 `0x4434b2` 分支逐条相同；战场演员都由 `0x407ec0` 装成这两种过程之一（模板 +0x64 过程 3／5，[字段覆盖](original_field_coverage.md)），所以玩家、敌方、友军同一读法。

| 地址（敌方／玩家） | 读法 |
| --- | --- |
| `0x43ef36..0x43ef89`／`0x44347e..0x4434aa` | 进入死亡：`+0x80 \|= 0x4000000`、子状态 `+0x8c = 0`、`0x4c6d80[id] = 1`；未置 0x800 位且 `0x446b60` 为假时 `0x446c40(actor, 方向, 6, 2)` 换姿态 |
| `0x43ef91..0x43efda`／`0x4434b2..0x4434ef` | 取 live `+0x14` 死亡台词字（两个 id 以 `0x458c10 & 1` 选一），`0x4072b0` 显示；有台词时 `+0x9c = 1` |
| 子状态 0 `0x43eff9`／`0x443510` 跳表 [0] | 等 `+0x9c == 0`（遗言关闭）且 `0x43bf30(actor, 0)` 为真；然后子状态 1、击杀计数（记录 `+0xa4`）加一，**绘制模式 `\|= 0x2c000000`、`+0x20 = +0x24 = 0x10000`（横／纵缩放 1.0）、层级 `+0x28 = 16`**，`0x409700` 放该角色模板 `+0xa` 的死亡音（PLAYERS `sound_dead`），有击杀者时 `0x408390` 起浮字 |
| 子状态 1 `0x43f0cd`／`0x4435e9` | **每 tick `+0x24 += 0x4000`（纵向缩放 +0.25）、`+0x28 -= 1`**；层级 ≤ 0 → 子状态 2 |
| 子状态 2 `0x43f0f2` | 等掉落（`0x4c2970`／`0x4c2978`），`+0x30 = −1` 隐藏，`0x4423b0` |
| 子状态 3 `0x43f13f` | `0x442720` 奖励浮字（EXP／KILL／$，见 [tick 计数](original_tick_counts.md)） |
| 子状态 4 `0x43f190` | 移出队列、`0x45e3ed` 删除对象 |

结论：遗言关闭后，死者以 16 tick（0.256 s，62.5 tick/s）从缩放 1.0 纵向拉到 5.0，同时层级 16→0 淡出，然后隐去——与用户记忆的"向上下拉伸、透明化消失"一致。缩放锚点是对象坐标，即 SHP 脚点（[演员绘制原点](actor_shp_draw_origin.md)），所以画面上是从脚下往上拉高。

## 重制落地

`game/battle/scene/BattleAftermath.gd` 的 `fade` 阶段：`DEATH_TICKS = 16`、`DEATH_STRETCH_PER_TICK = 0.25`，`FADE_SECONDS = 16 × 16 ms`（替换原 provisional 的 0.45 s 淡出）；演员节点（原点＝脚点）`scale.y = 1 + 0.25 × tick`、`modulate.a = 1 − tick／16`、加法混合；隐去时 `_dispose` 复原缩放与材质（开发快进 `finish` 同一出口）。

**provisional**：`0x2c000000` 含 `0x04000000`／`0x08000000`（`0x46b6b1` 表的饱和加法种类）与层级位，重制读作"加法混合、alpha＝层级／16"；该组合的像素例程未读。替换证据：`0x46b6b1` 对 `0x2c000000` 的像素种类静态读，或原作单帧对照。

**死亡音时刻（lane R5-L7，2026-09-24 用户决定"照原版：遗言之后响"）**：`BattleAftermath._begin_disposal` 是进入 `fade` 阶段的唯一入口，遗言关闭（`advance_dialogue`）或没有遗言时死亡 job 一开始就进入，在那一刻发 `disposal_started(unit)`，`BattlePresentation._play_sound(unit, "dead")` 放该角色的死亡音——对应子状态 0 的 `0x409700`。所有死亡来源都走这一处；开发快进 `finish` 不补放。检查：`run_combat_aftermath_tests` 在 `lethal_case`（攻击／绝技 × 30／144 fps）、`map_magic`（fire／wind）、`multi_target`（逐个受害者）断言遗言期间零个死亡音播放器、确认后恰一个，`counter_defeat` 断言无遗言的 雷歐納德 在拉伸开始时即响。消融：把发信号挪回 job 开始 → 10 条失败。

## 阵亡来源盘点

重制的死亡演出只有一个入口：`BattleAftermath.prepare` 从回执 `CombatSequence.outcomes`（主击与反击的全部参与结果）取 `defender_hp_before > 0 且 defender_hp_after ≤ 0` 的目标。

| 来源 | 播／不播 | 依据 | 检查 |
| --- | --- | --- | --- |
| 普通攻击（玩家打敌） | 播 | 回执 lethal → death job → 拉伸 | `run_combat_aftermath_tests.lethal_case("attack")` 30／144 fps |
| 绝技 | 播 | 同一回执路径 | `lethal_case("special")` |
| 反击（敌打死玩家） | 播 | 反击结果在 `outcomes` 里；玩家过程同一读法 | `counter_defeat`（雷歐納德） |
| 魔法（地图法术，敌方 AI 施放） | 播 | `affected` 各目标结果 | `map_magic`（fire／wind） |
| 多目标 | 播（逐个） | 每个 lethal 目标一个 job | `multi_target` |
| 玩家／敌方／友军 | 播 | 三者都是 defProcPlayer／defProcEnemy，两处死亡分支相同；重制不分阵营 | 上列用例覆盖玩家与敌方；友军同一路径 |
| 中毒回合末 | 不适用 | 毒伤 `min(hp − 1, …)`（`StatusEffectRules`），不致死 | — |
| 脚本删除（actDeleteObject／WalkAndDelete 等离场） | 不播 | 不产生战斗回执、不进 aftermath；原版脚本删除路径未读（未证明原版也不播） | — |
| undead 复活 | 不播 | 复活单位 HP 回 1，回执非 lethal | — |

消融：`DEATH_STRETCH_PER_TICK = 0` → `run_combat_aftermath_tests` 7 条失败（4 个 lethal_case、反击、两种法术）。

## 阵亡后占格

lane R7-CORPSE（2026-09-25）。起因：TURNDUMP 的第一战录屏（[battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)）中，R2-19 023_1 普通攻击击杀 021_4(15,14)。紧接着的 R2-20，原版 024_2 从 (15,18) 走到 (14,15)，而重制有种子让它停在 (15,14)。问题：原版刚死的单位，在遗言和拉伸期间以及之后，是否仍占着脚下格、挡住寻路。读法同上：r2 `aaa` 后用 `pdf`／`pdg`／`pdr` 静态读同一 exe，不执行原程序。

| 地址（敌方／玩家过程） | 读法（static-derived） |
| --- | --- |
| 地图格字 `*0x4c0928`（宽 `0x4c0934`、高 `0x4c0938`） | 占位侧位 `0x10000`／`0x20000`／`0x40000`。寻路 `0x4111a0` → `0x411080` → `0x40f350`／`0x40f440`／`0x410a50`，攻击站位 `0x413390`，追击候选 `0x40d800` → `0x411c40`：这几处只读格字和由格字算出的 `*0x4c1b44`，`pdr` 引用盘点里都没有扫对象表 `0x4c34c0` |
| `0x43f45f..0x43f4b0` | 非当前行动者且 `+0x8c == 0` 时，每 tick 用 `0x40ba20`＋`0x411a30` 把自己的侧位 OR 回脚下格。死亡分支（`+0x80 & 0x4000000`）在这之前就返回，所以尸体不会再补写 |
| `0x43ef36`／`0x44347e` | 进入死亡：只置 `+0x80 \|= 0x4000000` 和子状态 0；此时不清格，也不移出对象表 |
| 子状态 0–3（`0x43eff9`／`0x43f0cd`／`0x43f0f2`／`0x43f13f`） | 遗言、16 tick 拉伸、隐去、奖励浮字期间，格位都还在 |
| `0x43f160..0x43f181`／`0x443670..0x443687` | 击杀者 `+0xac` 非零时执行 `inc word [killer+0x8c]`（`0x43f16a`），放行击杀者。同一 tick 由 `0x40ba20`＋`0x411b90`（`0x43f179`；玩家 `0x443687` 为 `0x411b90(obj, 0x10000)`）清掉脚下格侧位，子状态改为 4 |
| 子状态 4 `0x43f190..0x43f1b6`／`0x44369e..` | `0x407720` 清 `0x4c34c0` 槽和行动队列项；死者若是当前行动者，调 `0x407510` 轮转；最后 `0x45e3ed` 删除对象。`0x407800`（查格上对象）扫 `0x4c34c0` 时不查死亡位，所以在删除前仍能找到尸体 |
| 普通攻击 minor 0xb `0x441594..0x441611` | 目标致死时：目标 `+0x80 \|= 0x8000000`，`[target+0xac] = attacker`（`0x44160b`），攻击者 `+0x8c` 进到 0xc（`0x441611`）。0xc 没有处理分支，攻击者原地等待，直到死者在 `0x43f16a` 把它推到 0xd；之后经 0xd／0xf／0x10／0x11，在 `0x4420b5` 调 `0x407510` 轮转。同形写法（`+0x8000000`、`+0xac = 出手者`、出手者 `+0x8c` 递进）另有 `0x441dd8`（敌方）、`0x44471e`、`0x44539c`（玩家过程），没有逐一标注各是哪种出手 |
| 反击致死 minor 0xe `0x4414c4` | 死的是攻击者本人，轮转发生在它自己的子状态 4（`0x43f1b0`），在清格之后 |
| AI 目标扫描 `0x40bb80` | 跳过 `+0x80 & 0x8000000` 的对象 |

**结论（static-derived）**：原版尸体在遗言和拉伸期间（子状态 0–3）仍占格。但在普通攻击和反击击杀下，下一名行动者要等 `0x43f179` 清格（以及随后 `0x45e3ed` 删除）之后才开始：攻击者被 `+0xac` 扣在 0xc；反击击杀时死者就是当前行动者，它删除时才轮转。所以下一名行动者寻路时尸格已经空了，可以穿过，也可以停下。

重制 `ActorTraversalRules.prepare` 只把 `BattlePresence.living` 的单位（hp>0、未 defeated、未 departed）写进占格，也就是一死就放格。对这两类击杀，重制与原版一致，本 lane 不改规则。已有检查 `run_actor_traversal_tests.pursuit_cases` 的 "a defeated blocker releases both transit and landing on the next decision" 钉住了这条规则。

TURNDUMP R2-20 正是 023_1 普通攻击击杀后的下一名敌人，原版里 (15,14) 同样是空的。重制停在 (15,14)（×10）与原版停在 (14,15) 的差别不来自尸体占格，仍按那份 README 归为分类 a（停点／目标随机）。

**provisional（未验证）：法术击杀的清格时序。** 两边施法都走 `0x442a90`（调用点 `0x4419c7`、`0x4419f9`、`0x444ff1`）。其 case 12（`0x4431a0..0x4431d4`）给受害者置 `0x8000000` 并写 `+0xa8 = 施法者`，但 `+0xac = ebp = 0`（`0x442aa5` 把 ebp 清零），所以施法者不被扣住。同一过程还把 `0x4c2970`／`0x4c2978` 清零（`0x442b87`／`0x442b8d`），受害者拉伸完直接进入清格。施法者随后自行走完浮字（`0x442720`）并轮转。两条链之间没有找到显式同步：`0x442a90` 对 `0x4c1b00` 只切换 `0x1000000`／`0x200000`，不碰当前行动者的开局门 `0x94000000`（`0x43f4ee` 起的 case 0）。

因此，法术击杀后下一名行动者寻路时受害者格位是否已清，取决于遗言关闭、镜头 `0x43bf30` 和浮字各自的 tick 数，静态读没有定论。重制在这里按"已放格"处理，不改。替换证据有两条路：一是从法术击杀那一 tick 起，逐 tick 读受害者 `+0x8c`、脚下格字，以及施法者调 `0x407510` 的时刻（runtime-measured）；二是静态读完施法者法术后的状态链，以及遗言对象（`0x4072b0` 建的过程 5）的等待条件。

## 当前行动者阵亡：队列连走两步

lane AI-PRIO-2（2026-09-26）。起因：原版裁判批量对照 505 关三个种子里，036_4 攻击 howl 被反击打死，同轮排在它后面的 036_5 一次都没行动，重制却让 036_5 接着行动（3 行差异）。

| 地址 | 读法 |
| --- | --- |
| 子状态 4 `0x43f190..0x43f1b0`（玩家 `0x44369e..0x4436c8`） | 先 `0x407540` 取当前行动者存进 esi，再调 `0x407720(死者)`；返回后若 esi 就是死者，再调 `0x407510` |
| `0x407720` | 清 `0x4c34c0` 槽，把死者的队列项（指针、+4、+8）全写 0。随后 `0x407540` 读到的当前项指针已是 0（`0x4077c4`），于是调 `0x4074a0(1)`：走到下一个活着且本轮未用的队列项，并把该项标成已用（`0x407504`） |
| `0x407510` → `0x4074a0(esi = [0x4c1ba0])` | 先做完成扫描 `0x408370`，再从刚才那一项之后再走一步。末尾找不到可用项时，`0x407340` 重排并 `inc [0x4c1bbc]` |

runtime-measured（`_enemy_level` 观察器挂 `0x407720`／`0x4074a0`／`0x407510`／`0x407340`，505 关种子 1）：`UNREG actor036_4` → `STEP arg=1 caller=0x4077cf`（idx 12 → 13，036_5）→ `HANDOFF caller=0x43f1b5` → `STEP arg=1`，从 036_5 走到队尾，`0x407340` 重排，进入第 2 轮。036_5 这一轮没有行动。

**结论（static-derived，runtime-measured 印证）**：当前行动者在自己的行动里死亡（反击击杀）时，队列里排在它后面的下一名活着的单位会失去本轮行动；这名单位不跑行动尾（中毒、状态计时都不走）。如果死者是本轮最后一名，第一步就会换轮，新一轮最快的那名单位失去第一次行动。敌我双方用的是同一种写法。只有当前行动者自己死亡时才会这样；防守方被打死时当前行动者还在，`0x407720` 不走这一步。

**玩家可见后果**：己方或敌方单位攻击时被反击打死，速度队列里紧跟其后的单位（可能是己方，也可能是敌方）本轮不能行动。

**重制落地**：`BattlePlayLoop._step_past_dead_actor` 对应 `0x407720` 这一步：推进到下一名活着的单位，换轮时先加回合数，再跑完成扫描。之后照旧 `CoreTurnQueue.end_turn`，对应 `0x407510` 的第二步。重制保留死者的队列槽，所以第一步要连续跳过已死的槽；原版里这些槽已经是空项。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleAftermath.gd` timing：a fallen actor's disposal after its last words: 16 ticks, the vertical zoom +0.25 and the draw level −1 a tick — enemy process 0x43eff9..0x43f0e6, player process 0x443501..0x443602
