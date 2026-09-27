# 阵亡：遗言后 16 tick 拉伸淡出、尸格释放时序、当前行动者阵亡的队列两步

> evidence: static-derived: the dead branches of the battle-actor processes read from hsl01.exe, including when a corpse's map-cell bits are cleared relative to the next actor after attack and counter kills, and the double queue step when the current actor dies, and the 0x2c000000 draw mode as kind 9 of the pixel-kind table (map_pose_floaters §4); runtime-measured: 505 s1 queue trace · status: live · functions: 0x4072b0, 0x407340, 0x4074a0, 0x407510, 0x407540, 0x407720, 0x407800, 0x409700, 0x40ba20, 0x411b90, 0x43bf30, 0x43ede0, 0x441594, 0x442720, 0x442a90, 0x446c40 · tools: run_actor_traversal_tests.gd, run_combat_aftermath_tests.gd · updated: 2026-09-27

## 结论

- 原版：遗言关闭后死者纵向缩放每 tick +0.25、层级 16→0，16 tick（0.256 s）拉到 5.0 并淡出，同时放 `sound_dead`；玩家、敌方、友军同一读法（static-derived）。
- 普通攻击与反击击杀时，下一名行动者要等死者清格并删除后才开始，所以它寻路时尸格已空；当前行动者在自己行动里阵亡时队列连走两步，紧随其后的活单位失去当轮行动（static-derived；505 关种子 1 实测印证）。
- 重制：`game/battle/scene/BattleAftermath.gd` 按 16 tick、+0.25／tick 拉伸与层级 16→0 的加色淡出，死亡音在进入拉伸时响；`ActorTraversalRules` 一死即放格；`BattlePlayLoop._step_past_dead_actor` 复现两步（static-derived 规则）。
- `0x2c000000` 是 `0x46b6b1[6]` 种类 9（`0x462e8b`，缩放饱和加法，层级分支先按层级表取 `⌊c×L/16⌋`），重制用共用 `AdditiveLevelBlend` 画（static-derived，[map_pose_floaters §4](../runtime_observations/map_pose_floaters/README.md#4-加色层级混合0x46b6b1--像素种类表-0x46211c)）。
- 差异：法术击杀的清格时序无定论，重制按已放格处理（provisional）。

## 证据

**static-derived：死亡分支**（原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；敌方过程 `0x43ede0` 与玩家过程逐条相同，演员都由 `0x407ec0` 装成过程 3／5）

| 地址（敌方／玩家） | 读法 |
| --- | --- |
| `0x43ef36..0x43ef89`／`0x44347e..0x4434aa` | `+0x80 \|= 0x4000000`、`+0x8c = 0`、`0x4c6d80[id] = 1`；未置 0x800 且 `0x446b60` 为假时 `0x446c40(actor, 方向, 6, 2)` 换姿态；此时不清格、不移出对象表 |
| `0x43ef91..0x43efda`／`0x4434b2..0x4434ef` | 取 live +0x14 死亡台词字（两 id 以 `0x458c10 & 1` 选一），`0x4072b0` 显示；有台词时 `+0x9c = 1` |
| 子状态 0 `0x43eff9`／`0x443510` | 等 `+0x9c == 0` 且 `0x43bf30(actor,0)`；子状态 1，击杀计数 +1，绘制模式 `\|= 0x2c000000`，`+0x20 = +0x24 = 0x10000`，层级 `+0x28 = 16`；`0x409700` 放模板 +0xa 死亡音；有击杀者时 `0x408390` 浮字 |
| 子状态 1 `0x43f0cd`／`0x4435e9` | 每 tick `+0x24 += 0x4000`、`+0x28 -= 1`；层级 ≤0 → 子状态 2 |
| 子状态 2 `0x43f0f2` | 等掉落（`0x4c2970`／`0x4c2978`），`+0x30 = −1` 隐藏，`0x4423b0` |
| 子状态 3 `0x43f13f` | `0x442720` 奖励浮字（[tick 计数](original_tick_counts.md)） |
| `0x43f160..0x43f181`／`0x443670..0x443687` | 击杀者 +0xac 非零时 `inc word [killer+0x8c]`（`0x43f16a`）放行击杀者；同 tick `0x40ba20`＋`0x411b90`（`0x43f179`）清脚下格侧位 |
| 子状态 4 `0x43f190..0x43f1b6`／`0x44369e..` | `0x407720` 清 `0x4c34c0` 槽与队列项；死者是当前行动者时再 `0x407510`；`0x45e3ed` 删除 |

**static-derived：尸格与下一名行动者**

| 地址 | 读法 |
| --- | --- |
| 格字 `*0x4c0928`（宽 `0x4c0934`、高 `0x4c0938`） | 侧位 `0x10000`／`0x20000`／`0x40000`；寻路 `0x4111a0`→`0x411080`→`0x40f350`／`0x40f440`／`0x410a50`、站位 `0x413390`、候选 `0x40d800`→`0x411c40` 只读格字，不扫对象表 |
| `0x43f45f..0x43f4b0` | 非当前行动者每 tick 把侧位 OR 回脚下格；死亡分支在此前返回，尸体不补写 |
| `0x407800` | 查格上对象时不查死亡位，删除前仍能找到尸体 |
| 普通攻击 minor 0xb `0x441594..0x441611` | 目标致死：`+0x80 \|= 0x8000000`，`[target+0xac] = attacker`（`0x44160b`），攻击者 `+0x8c` 进 0xc 等待，直到 `0x43f16a` 推到 0xd，再经 0xd／0xf／0x10／0x11 在 `0x4420b5` 调 `0x407510`；同形写法另见 `0x441dd8`、`0x44471e`、`0x44539c` |
| 反击致死 minor 0xe `0x4414c4` | 死者是攻击者本人，轮转在它的子状态 4（`0x43f1b0`），清格之后 |
| `0x40bb80` | 跳过 `+0x80 & 0x8000000` 的对象 |
| 施法 `0x442a90`（调用 `0x4419c7`、`0x4419f9`、`0x444ff1`） | case 12（`0x4431a0..0x4431d4`）置 `0x8000000`、`+0xa8 = 施法者`，但 `+0xac = 0`（`0x442aa5`），施法者不被扣住；清 `0x4c2970`／`0x4c2978`（`0x442b87`／`0x442b8d`）；对 `0x4c1b00` 只切 `0x1000000`／`0x200000` |

**static-derived：当前行动者阵亡**

| 地址 | 读法 |
| --- | --- |
| `0x43f190..0x43f1b0`（玩家 `0x44369e..0x4436c8`） | 先 `0x407540` 存当前行动者，调 `0x407720(死者)`，若当前者即死者再调 `0x407510` |
| `0x407720` | 清槽与队列项；当前项指针已为 0（`0x4077c4`），调 `0x4074a0(1)` 走到下一个活着的未用项并标已用（`0x407504`） |
| `0x407510`→`0x4074a0([0x4c1ba0])` | 完成扫描 `0x408370` 后再走一步；到表尾则 `0x407340` 重排并 `inc [0x4c1bbc]` |

**runtime-measured**（`_enemy_level` 观察器挂 `0x407720`／`0x4074a0`／`0x407510`／`0x407340`，505 关种子 1）：`UNREG actor036_4` → `STEP arg=1 caller=0x4077cf`（idx 12→13，036_5）→ `HANDOFF caller=0x43f1b5` → `STEP arg=1` 到队尾重排进第 2 轮；036_5 当轮未行动，也未跑中毒与状态计时。第一战录屏 R2-20 的 024_2 停点差异不来自尸体占格（原版该格同样已空），归停点随机（[battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)）。

**user-hypothesis**：阵亡时人物被拉高、上下拉伸后透明消失的记忆，与上面的读法一致；缩放锚点是 SHP 脚点（[演员绘制原点](actor_shp_draw_origin.md)），画面上是从脚下往上拉高。

## 重制接线

- `game/battle/scene/BattleAftermath.gd`：`DEATH_TICKS = 16`、`DEATH_STRETCH_PER_TICK = 0.25`、`FADE_SECONDS = 16 × 16 ms`；`scale.y = 1 + 0.25 × tick`、`modulate.a = 1 − tick／16`、加法混合；`_dispose` 复原缩放与材质。`_begin_disposal` 是进入 `fade` 的唯一入口，发 `disposal_started(unit)`，`BattlePresentation._play_sound(unit, "dead")` 放死亡音；开发快进 `finish` 不补放。provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_death_disposal.md`。
- 死亡演出只从回执 `CombatSequence.outcomes` 中 `defender_hp_before > 0 且 defender_hp_after ≤ 0` 的目标建立：普通攻击、绝技、反击、地图法术、多目标逐个都播；中毒不致死（`StatusEffectRules`）；undead 复活回执非 lethal；脚本删除不产生回执、不播。
- `game/sim/ActorTraversalRules.gd`：`prepare` 只把 `BattlePresence.living` 写进占格（一死即放）。
- `game/sim/loop/BattlePlayLoop.gd`：`_step_past_dead_actor` 对应 `0x407720` 这一步（换轮时先加回合数再跑完成扫描），之后 `CoreTurnQueue.end_turn` 对应第二步；重制保留死者队列槽，故连续跳过已死槽。

## 复现

`tools/godot.sh --headless --script res://tests/run_combat_aftermath_tests.gd`（`lethal_case` 攻击／绝技 × 30／144 fps、`map_magic`、`multi_target`、`counter_defeat`；尸格释放见 `run_actor_traversal_tests.gd` 的 `pursuit_cases`）。

## 边界

- 原版脚本删除路径未读（未证明原版也不播）
- 法术击杀后下一名行动者寻路时受害者格位是否已清，取决于遗言、镜头 `0x43bf30` 与浮字各自的 tick 数，静态读无定论；替换证据为从法术击杀那一 tick 起逐 tick 读受害者 +0x8c、脚下格字与施法者调 `0x407510` 的时刻。
- 脚本离场的当前行动者两步语义见 [initial_battle_initiative.md](initial_battle_initiative.md)，未实测。
