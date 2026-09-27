# 原版敌人回合裁判：在模拟器里跑原帧体，输出 enemy_turn_v1

> evidence: runtime-measured: 整个 hsl01.exe 映像在 unicorn 中执行——载入 51 关样本存档后的敌人回合（落点、动作、目标、每次抽取）、0x407340 四种速度下的队列、帧桩消融、0x4c1bbc 回合计数从 1 走到 2、0x40e870 出生调级只抽全局流、任意关卡经 0x42da60 进关并在首个 0x407340 前注入局面后原版跑整回合（§11）; static-derived: 0x460a06 转场步进与 [0x4bbb5a]、0x458c10／0x458c80 与伤害流换入 0x42c780／0x42c720、0x407340 插入排序; provisional: 全局流的样本起点（来自模拟器时钟桩）、玩家回合结束从 +0x8c=0x10000 起跑（不经待機菜单输入）、call／other 两类动作从不产出、抽取点对照表 SITE_MAP（逐站点反汇编对照，未逐值对拍） · status: record-only · functions: 0x407340, 0x407510, 0x407cc0, 0x409e40, 0x40a7b0, 0x40c9a0, 0x40e870, 0x42c720, 0x42c780, 0x42ce10, 0x42d280, 0x42d600, 0x42da60, 0x42e640, 0x43e110, 0x43e1c0, 0x4423c0, 0x458c10, 0x458c80, 0x460799, 0x4607f9, 0x460884, 0x460a06, 0x461479 · tools: hsl_original_probe_units.py, hsltools/probes/_enemy_level.py, hsltools/probes/enemy_turn.py, test_hsl_enemy_level.py, test_hsl_enemy_turn.py · updated: 2026-09-25

lane ORACLE，2026-09-25。要回答的问题：给定一个战斗局面和随机数起点，原版的敌人回合里每个 NPC 走到哪、打谁、用什么，每次抽随机数时抽了什么。做法是把原程序本身当裁判：整个 `hsl01.exe`（SHA-256 `f0b5f835…`）映像装进 unicorn，用原版的存档读取器载入样本，然后逐帧调原帧体。全程没有启动 Wine，也没有截屏。回执是 [original_enemy_turn.json](original_enemy_turn.json)，由注册任务 `enemy_turn` 生成和校验。

## 1. 结论

- **出手动画的等待已解开，攻击回合能跑完。** 用样本自带的随机数，雷歐納德交接之后原版依次跑了 11 个 NPC 行动：第 1 回合剩下的 6 个友军、第 2 回合的 5 个敌人。第 1472 帧时队列回到玩家进程（雷歐納德），这是 `player_control`。其中 021_2 和 021_4 各打了 023_2 一次（−10、−9），伤害流的抽取逐次记录在案。另外 4 个全局种子也都跑到 `player_control`：5 个回合共 55 个行动，其中 10 个攻击，共 2739 次抽取。
- **等待的根因（模拟器实测）：** 早先 spike 的手排帧从来没调转场步进 `0x460a06`。守方特写进入 phase 101 时，调 `0x46098f(1)` 把转场挂起字 `[0x4bbb5a]` 置为 1，而只有 `0x460a06` 会把它清零，所以 `0x4423c0` 的交手永远等下去。改成每帧调完整帧体 `0x42d600`（只桩掉呈现 `0x42d280`）后就解开了。反过来把 `0x460a06` 桩掉，等待原样复现：6000 帧后当前行动者仍是 021_2，`[0x4bbb5a]` 仍为 1（§6）。
- **回归一致：** 026_1 (13,6)→(11,7)、026_2 (4,9)→(7,9)、024_1 (17,21)→(17,17)、024_2 (15,22)→(15,18)，与录屏 R1-09..R1-12 相同。`check` 会校验这四条。
- **队列顺序（模拟器实测）：** `0x407340` 先按注册槽 0..199 收集，再做插入排序。只有当前一项的速度 `+0xb8` 严格小于当前项时才上移，所以速度降序、同速保持槽序。样本里 023_2 速度 14，与槽 0 的雷歐納德同速，雷歐納德先动。把 023_2 的速度改成录屏值 16（L3），它就排到雷歐納德之前。所以录屏里"023_2 先于雷歐納德"来自它的速度：它 3 级、速度 16，说明开场随机调级 `0x40e870` 给它升了级。调级本身是随机的，这一点是 static-derived，录屏那一局的抽样过程没有复现（§7）。
- **全局随机流的"样本起点"不在存档里。** 存档只带伤害流的两个字 `0x4c3044`／`0x4c3040`。全局流 `0x458c10` 在种子标志 `0x4c1e8c` 为 0 时按时钟播种（`0x457830` = GetTickCount − `[0x4c2310]`）。所以样本回合的全局起点是模拟器伪影：时钟桩的值，再加上载入过程中 `0x407b70` 内调用点 `0x407c06` 的 12 次抽取。回执里写在 `meta.rng_source`。

## 2. 用法

```sh
# 离线校验回执（verify 会跑；不需要 unicorn 和 exe）
python3 tools/hsl.py check enemy_turn
# 重跑原程序并重写回执（缓存命中实测 23 s；缓存缺失时先重建载入态，首次共实测 65–95 s）
uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsl.py generate enemy_turn
# 单回合：默认用样本自带的随机数，stdout 输出 enemy_turn_v1 JSON（含 meta），--brief 时 stderr 每个行动一行
uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/enemy_turn.py --brief
#   --seed S1 S2          全局流起点 0x4795d4 0x4795d8（同时置种子标志 0x4c1e8c=1）
#   --damage-seed D1 D2   伤害流起点 0x4c3044 0x4c3040
#   --set ACTOR.FIELD=V   载入后写原版内存：hp / max_hp / level / speed，cell=X/Y，target=ID|none，dead=1（可重复，§8）
#   --save FILE           换一份 51 关 HSLBAT 存档
#   --lines FILE          另写每回合一行的 enemy_turn_v1，draws 按 SITE_MAP 改名保留（_enemy_level.py compare 的输入，§11）
#   --bare-lines FILE     同上但 draws 置空（重制导出器 --expect／--search 的输入）
#   --ablate NAME         消融开关（§6）；--no-cache 重建载入态；--frames N 帧上限（默认 6000）
```

只有回到玩家控制时退出码才是 0。载入态缓存在 `ignored/native_cache/battle_machine/v1_<exe12>_<save12>_L51.pkl`，不提交；缺失时工具自己重建，重建后的输出与用缓存时逐字相同（已实测）。

与重制导出器 [export_enemy_turns.gd](../runtime_observations/battle_051_ai_moves/README.md) 的约定对齐如下：

- actor 名用重制单位 id：按 `battle_051.json` 的 `playable_units` 顺序，对同一 actor code 按注册槽顺序配对。
- 坐标是格坐标，等于像素 >> 5。
- Wait 的 `target` 是持有的追击目标，即对象 `+0x88`（u16，值为注册槽 + 1）。
- `--lines`／`--bare-lines` 每回合写一行。
- draws 的 `site` 两边天然不同：这里是调用者地址，重制是 `Script.function`。`--lines` 按抽取点对照表 `SITE_MAP`（§11.3）把全局流站点改成重制的 `Script.function`，raw & 1 的站点记成 n=2、值取低位，没有对应的站点保留地址，伤害流不写（导出器不记）。导出器 `--expect` 把非空 draws 整段按 JSON 比较，所以给它用 `--bare-lines`（draws 置空）。

## 3. 机器与垫片

整映像机器在 `tools/hsltools/native/battle_machine.py`。以下是所有非原版代码，回执的 `shims` 字段逐条列出：

1. **Win32 导入白名单：**
   - GetTickCount／timeGetTime 每调一次加 1。
   - FindFirstFileA 返回 INVALID_HANDLE_VALUE。
   - PeekMessageA 和按键状态返回 0。
   - 其他导入一律停机。
2. **CRT 堆：** malloc `0x457b70` 换成 bump 分配，free 为空操作。
3. **游戏自己的文件层**（`0x46c830`…`0x46c970`）换成内存文件：`SAVES\HSLBAT.SAV` 是给定的存档，其余文件从 exe 旁的 hsl.pak 读。
4. **图形：** 形状加载器 `0x4601a2`／`0x460058` 返回 0，资源名转 id `0x45fc01` 发顺序号；帧内跳过行走者绘制段 `0x45f724→0x45f75e`，桩掉形状绘制 `0x4607f9`／`0x460799`、文字 `0x460884` 和呈现 `0x42d280`。
   - `0x460799` 是 `0x4607f9` 的兄弟：写 blit 参数 `0x4bbb9a..`，形状表 `[0x4abf28+id·4]` 为 0 时报 `0x46e100(3,id)` "Shape not loaded"。形状从不解码，所以它只会致命。7 个调用者 `0x424ecd` `0x430346` `0x436ae8` `0x436de2` `0x43da5c` `0x4458aa` `0x4458cd` 都是对象绘制；第 3 关第一个 NPC 攻击走到 `0x436ae8`，未桩时第 280 帧 `fatal 'Shape not loaded: 4b0'`。另一处 "Shape not loaded" `0x45f78f` 在已跳过的行走者绘制段里（字节模式全扫，模拟器实测）。加桩后本回执只有 `shims` 这一行变。
   - 呈现桩返回前把"本帧已画出"标志 `[0x4c1b1c]` 置 1。原版 `0x42d280` 进门先清零（`0x42d282`），出帧时置 1（`0x42d2b3`／`0x42d359`），正常出帧时它就是 1。桩成恒 0 会卡规则路径：镜头等待 `0x43bf30` 在 mode 带 `0x80000000` 时，到位后还要 `[0x4c1b1c]≠0` 才返回 1（`0x43bfe0`），这种调用点有 `0x442c55` 和施法流程里的 `0x44301e`；震屏 `0x4176af`／`0x41d528`／`0x421766` 也只在它为 1 时对 `[obj+0x94]` 取反、累加 `0x4c1b98`。
   - 改前改后重跑回执，只有 `shims` 这一行变了，5 个回合、2739 次抽取、消融逐字相同（模拟器实测）。
5. **致命框 `0x45b29e` 停机。**

钩子须知（模拟器实测）：unicorn 2 在翻译代码块时才决定这个块调不调代码钩子，块翻译之后再加的钩子不触发。`BattleMachine.hook` 因此每加一个钩子就 `ctl_remove_cache(at, at+1)` 丢掉该地址已翻译的块。修前，冷路径（没有关卡缓存、同一台机器跑完开场直接接回合）上 rand 的入口钩子漏掉、返回钩子照发，`TurnRun._rand_out` 空栈 IndexError（第 3、52 关）；修后第 3、52 关冷路径与缓存路径逐字相同，本回执不变。

载入顺序照 WinMain `0x42f1ad`：

1. 引擎初始化 `0x46d14c`，以及 WinMain 的工作缓冲。
2. 12 个文本表加载器。
3. GLOBAL.OBS（`0x45dc5c`）。
4. 关卡开始复位 `0x42c640`／`0x407260`／`0x45fb5c`。
5. 关卡加载 `0x42ce10(51)`，接着 `0x45e224`。
6. 存档读取 `0x42e640(0,0,1)`。

回合的跑法：

1. 雷歐納德是样本的当前行动者。把他的对象 `+0x8c` 写成 `0x10000`，即玩家进程 `0x443330` 的回合结束模式：高字 1 进 `0x443a67`，低字按跳表 `0x4457fc` 逐步走 `0x4454a5` 地形检查 → `0x443a86` 的 `0x40e2b0` 检查与中毒扣血（经 `0x4084e0` 可达 rand `0x408d7d`／`0x408db1`）→ 回复检查 `0x40e3b0`，满足时 `0x40e430` 在 `0x40e480`／`0x40e508` 抽伤害流 → `0x40b910` 状态倒计时（写 live 记录 `+0x24`、`+0x30..+0x48`）→ 交接 `0x407510`。这样整段由原版自己跑，它的抽取与 HP 变化记在 `meta.handoff`。
   - 早先直接调 `0x407510`，会漏掉这段。样本上这些都为 0：改后 5 个回合的 55 个行动与全部抽取逐字相同，只多 3 帧（交接 3 帧、0 次抽取，模拟器实测）。玩家中毒或会回复的局面，旧做法会漏抽取和 HP 变化。
2. 然后每帧调 `0x42d600`，直到队列当前对象（`0x4c3940 + 12·[0x4c6e48]`）的 `+0x64` 等于 3（玩家进程）。
3. 当前对象一变，就结束上一个行动、开始下一个：记录 `from`/`to`、回合 `0x4c1bbc`、HP 差和持有目标。

## 4. 动作分类与抽取记录

**动作分类**（在原程序运行时测得）：

| action | 判定 | target |
| --- | --- | --- |
| attack | `0x4423c0` 交手起手（phase 字 `0x4c432c` 为 0），且攻方是当前行动者；攻方不是当前行动者时算反击，记进 `meta.counters` | 守方 |
| magic | AI 名牌 `0x43e110`（MAGIC 组 `[0x4c2c54]`、序号 `[0x4c2c40]`）为当前行动者绘制 | AI 目标 `[0x4c1cec]` |
| skill | 名牌 `0x43e1c0`（SPECIAL 组 `[0x4c2c44]`、序号 `[0x4c2c94]`） | 同上 |
| item | `0x409e40(target, item, user)` 且 user 是当前行动者 | target |
| wait | 以上都没有 | 持有追击目标 `+0x88`，没有时为 null |

- magic 和 skill 的 `skill` 写作 `magic|special:<TYPE.H 元素名>:magicCodeNN`，item 写作 `item:<code>`。
- magic／skill 的 target 不是施放中心的单位：施放态在 `0x4417a6` 用中心 `[0x4c2c70]／[0x4c2c74]` 调 `0x4100e0` 铺效果区域，随即 `0x4417b5` 写 `[0x4c1cec] = 0x4104d0(0)`——区域里按行（y 外层、x 内层，`0x410548..0x410553`）遇到的第一个对象（static-derived）。重制导出 `export_enemy_turns.gd` 按同一口径报 target：足迹格按行排序后第一个被命中的单位（lane AI-PRIO-2；此前报中心单位，59 s1、575 s2 因此误记成规则差异）。
- `call`（`0x40bee0` 呼叫广播）是找目标时的副作用，这里从不作为动作产出；`other` 同样不产出。
- 51 关这一回合实际只出现 attack 和 wait。魔法见 §11.5。

**抽取记录** `{"site","n","value","stream"}`：

- `site` 是抽取函数调用者的 call 地址（返回地址 − 5）。
- `global` 流：rand(n) `0x458c80` 在 n ≤ 0xffff 时返回 (raw & 0xffff) % n，更大的 n 返回 raw % n。rand(0) 不抽、返回 0，照样记一条 n = 0。raw `0x458c10` 由其他调用点直接调用时 n 为 null。
- `damage` 流：`0x42c780`（rand(n)）和 `0x42c720`（raw，唯一调用者 `0x409d06`）先把 `0x4c3044`／`0x4c3040` 换入全局生成器，抽一次再换回。这类抽取记在包装函数的调用者名下。

**样本 021_2 攻击 023_2 的伤害流**（site, n, value）：`0x442669` 100→32，`0x409cc3` 3→2，`0x409ce6` 0→0，`0x409cf5` 0→0，`0x403efa` 100→14，`0x403f51` 100→86，`0x40a660` 5→0，`0x40a6d7` 1→0。

样本回合全局流共 515 次抽取，伤害流 17 次。全局流最多的调用点是 `0x41385d`（268 次，走法精化），其次 `0x40c061`、`0x40c138`、`0x440db5`、`0x40d500`。

## 5. 样本与种子结果

样本自带的随机数：全局 [956367880, 2292745173]（伪影，见 §1），伤害 [212957692, 4082009603]（取自存档）。

```
actor023_1 [17, 18]->[15, 15] wait actor021_4        actor021_2 [13, 10]->[14, 13] attack actor023_2 (−10)
actor023_2 [14, 19]->[14, 14] wait actor021_2        actor021_3 [10, 8]->[12, 11] wait leonard
actor026_1 [13, 6]->[11, 7] wait actor023_1          actor021_5 [6, 9]->[10, 8] wait leonard
actor026_2 [4, 9]->[7, 9] wait actor023_1            actor021_1 [13, 7]->[12, 9] wait actor023_2
actor024_1 [17, 21]->[17, 17] wait actor021_4        actor021_4 [13, 11]->[15, 14] attack actor023_2 (−9)
actor024_2 [15, 22]->[15, 18] wait actor021_4        stop=player_control next=leonard frames=1472
```

4 个全局种子，伤害流保持样本值：(1,2)、(0x12345678,0x9abcdef0)、(7,7)、(0xdeadbeef,0x13579bdf)。

- 全部在 1469–1478 帧回到雷歐納德。
- 021_2 与 021_4 每次都攻击。021_4 的目标在两个种子下换成 023_1。
- 落点随种子变化，例如 026_2 在 (7,9) 与 (6,8) 之间。
- 4 条回归落点在种子 (0xdeadbeef,…) 下同样成立。其他种子下 026_1、026_2 可能不同，校验只对样本回合要求。

## 6. 消融（`--ablate`，回执 `ablations` 段）

| 开关 | 结果（模拟器实测） | 说明 |
| --- | --- | --- |
| 去掉 blit `0x461479` 的桩 | 5 个回合、终局 HP、帧数逐字相同，耗时 3.41 s 对 3.70 s | **已从垫片中删除**，现在跑原指令 |
| keep-present（不桩 `0x42d280`） | 第 1 帧 `unmapped access 0x0 at eip 0x457d67` | 没有 DirectDraw 表面，必须保留 |
| keep-shape（不桩 `0x4607f9`） | 第 464 帧 `fatal 'Shape not loaded: 364'`（021_2 出手特写） | 形状加载器被桩成 0，必须保留 |
| keep-text（不桩 `0x460884`） | 第 489 帧 `unmapped access 0x4 at eip 0x4608d6`（021_2 出手） | 必须保留 |
| keep-draw-pass（跑 `0x45f724..0x45f75e`） | 第 1 帧 `fatal 'Shape not loaded: 2'` | 必须保留 |
| stub-transition（桩 `0x460a06`） | 6000 帧 `frame_limit`，current=actor021_2，`[0x4bbb5a]`=1 | 复现旧的出手等待 |

四个必须保留的桩都只做"画出来"这件事。要去掉它们，得先让形状真正解码、并提供一个表面，这属于更大的垫片工程，本 lane 没做。

## 7. 队列排序 `0x407340`（回执 `queue_sort` 段）

在载入的样本上改 live 速度后直接调原函数，读它写出的 `[对象, 槽, 1]` 表：

```
loaded        021_2/s22/v16 021_3/s23/v16 021_5/s26/v16 021_1/s20/v15 021_4/s24/v15 leonard/s0/v14 023_1/s27/v14 023_2/s28/v14 026_1/s21/v13 026_2/s25/v12 024_1/s29/v12 024_2/s30/v12
023_2 速度16  … 021_5/s26/v16 023_2/s28/v16 021_1/s20/v15 021_4/s24/v15 leonard/s0/v14 023_1/s27/v14 …
全员速度10     leonard/s0 021_1/s20 026_1/s21 021_2/s22 021_3/s23 021_4/s24 026_2/s25 021_5/s26 023_1/s27 023_2/s28 024_1/s29 024_2/s30
速度=槽号      024_2/s30 … 021_1/s20 leonard/s0
```

- 四种情形都等于按 (−速度, 槽) 排序。
- 样本 11 个行动的顺序，等于这个队列里雷歐納德之后的部分，再接下一轮雷歐納德之前的部分。
- 录屏第 1 回合其余单位的先后，取决于它们各自的开场调级速度。录屏读不出所有单位的速度，这部分没有逐个核对（未验证）。

## 8. 状态注入

注入只写原版自己读的内存字段，或调用原版自己的函数去改占位与死亡状态，不改原版逻辑。`enemy_turn.py --set` 与 `_enemy_level.py --board／--set` 共用 `apply_board`，每个字段写什么、依据是什么都列在 `INJECTION` 表里，`meta.board` 记录实际写入：

| 字段 | 写入 | 依据 |
| --- | --- | --- |
| speed | live 记录 `[0x4c1bc8] + (对象 +0xa4)·0x1fc` 的 `+0xb8` | `0x407340` 排序键（`0x4073de`，§7） |
| hp／max_hp／level | live `+0xd8`／`+0xdc`／`+0x9c`；board 的 hp 按 max_hp 截断（与重制导出器一致），`--set ID.hp` 原值写入 | live 记录布局 |
| cell（board 的 `units`） | 对象 `+4/+8` 像素 x/y（格 = 值 >> 5，低 5 位保留）。占位随之移动：先对所有移动者调 `0x411b90(obj, 0x40ba20(obj))` 清旧格（`0x407940` 查到同格另有对象时不清，照脚本离场 `0x453c9a..0x453caf` 的次序），再全部写坐标，最后 `0x411a30(obj, 同一掩码)` 标新格 | 原版清格／标格函数 |
| target | 对象 `+0x88` u16 = 持有目标的注册槽 + 1（0 为无） | AI 目标扫描读它 |
| dead | 死亡入口 `0x43ef36..0x43ef5b` 的写入（`+0x80 \|= 0x4000000`、`+0x8c = 0`、`[0x4c6d80 + u16 +0xa2] = 1`）、live hp 0；再跑死亡子状态会跑的：`0x411b90` 清格（NPC `0x43f179`；玩家进程用 side 0x10000，`0x443687`），尸体不占格；然后 `0x407720`（注册槽、队列项、阵营计数 `0x4c1b90/0x4c1b94`）、`0x44cb90(live 索引)`、`0x45e3ed(obj)`（`0x43f190..0x43f1b6`） | 原版死亡流程 |
| turn | u16 回合计数 `[0x4c1bbc]` | §10 |

- 当前行动者不能注入死亡（会拆掉正在跑的进程）。
- 死亡注入不跑死亡字幕／事件 `0x446b60/0x446c40`，也不给击杀者经验与金钱。
- 局中阵亡的单位会被 `0x45e3ed` 摘链，事后再读它的 `+0xa4` 会越界。所以 `TurnRun` 开局就缓存各单位的活表索引。
- 51 关样本上 `--set` 仍只能改那一份存档里的棋盘；换关卡与整盘局面走 §11 的新关卡路径。

## 9. 边界与未验证

- 玩家回合是从回合结束模式 `+0x8c=0x10000` 起跑的（§3），没有模拟待機菜单的输入。菜单本身有没有抽随机数，未验证。玩家计划只支持"全员待机"。
- 全局流的样本起点是伪影（§1）。要复现录屏那一局，需要当时的时钟，拿不到。
- 动作分类建立在§4 的入口上。魔法经注入实测过一次（§11.5）；绝技与道具在原版一侧还没有出现过（未验证）。
- 存档路径（本回执）没有对话点击驱动，只能从存档那一刻跑敌人回合。任意关卡、任意局面走 `_enemy_level.py`（§11）。
- 抽取点对照表只按反汇编对照了站点（static-derived）。两端逐值对拍要求两边抽取次序一致，目前重制跳过优先级链，次序不一致（§11.3）。

## 10. 同批更正

- [original_auto_growth](original_auto_growth.md) 与 [battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md) 剩余表都写过"`0x40e870` 用 `0x4c3040`／`0x4c3044`"。实际上 `0x40e870` 的目标等级抽取 `0x40e92c`／`0x40e938` 以及其后逐级属性抽取，都是 `call 0x458c80`，走全局 `0x458c10`；函数内没有伤害流换入。模拟器实测（回执 `growth` 段）：对载入样本的 023_2 按调用点 `0x43ef26` 的参数（18, 2）原生调用 `0x40e870`，L1 29 HP 速 14 → L2 36 HP 速 15；rand(n) 调用点依次为 `0x40e92c`、`0x40e938`、`0x40e956`、`0x40e9a2`、`0x40ea0b`、`0x40ea38`、`0x40ea62`、`0x40ea90`、`0x40eabe`、`0x40eaf9`，没有进入 `0x42c780`／`0x42c720`，全局状态变了，伤害流状态 `0x4c3044`／`0x4c3040` 没变。
- `tools/hsl_original_probe_units.py` 把 `0x4c1e8c` 标成 ROUND_COUNTER。它其实是全局流的种子标志：`0x458c10` 在它为 0 时按时钟播种，`0x458bc3` 把它置 1。真正的回合计数是 `0x4c1bbc`：u16，`0x42c6b9` 置 1，`0x4074f1` 每轮 `inc word`。本回执里它从 1 走到 2，是模拟器实测。
  - 工具现在分别输出 `round_0x4c1bbc` 和 `rng_seeded_0x4c1e8c`。
  - 旧回执（battle_005、battle_006、level17 护送）里的 `round_counter_0x4c1e8c` 保持原样没改，它的值 1 表示"已播种"，不是"第 1 回合"。

## 11. 任意关卡回合裁判 `_enemy_level.py`

lane ORACLE2，2026-09-25。要回答的问题：给一份重制导出的回合开始局面和随机数起点，原版在任意关卡的第 1 回合里每个 NPC 落点、动作、目标和逐次抽取是什么，与重制差在哪。诊断工具，不注册生成任务，也不进回执。

### 11.1 进关、输入与注入点

- **进关：** 整映像机器照 WinMain 启动，然后以载入标志清零调 `0x42da60(level)` 走新关卡分支（复位、关卡加载、EVEF 实例、开场脚本），进入原版帧循环 `0x42dbf0`。原版逻辑一处不换。
- **输入只有玩家会给的两种，写在窗口过程写的地方：**
  - 对话：上一帧跑过等待点（脚本等待 `0x453052`、消息框 `0x414743`／`0x414152`），下一轮循环头把左键 `[0x4c2344]` 置 1 一帧再清 0。
  - 玩家回合：待機菜单输入检测 `0x4082c4` 在玩家进程当前时跑过，就把该单位 `+0x8c` 写成 `0x10000`（同 §3，全员待机；不支持其他计划）。
- **growth false**：开场调级读成长字 live `+0x1f8／+0x1fa` 之前把它们清零。NPC 在 `0x43eefb`，玩家在 `0x44345d`。出生 `0x40e870` 照跑，只是没有等级散布：NPC 升到实例等级，玩家按推断等级。重制导出 `{"growth": false}` 对应跑 adjust_level [0, 0] 的出生（同开局快照 g0），不是模板阵容；带 `speed` 覆盖的记录局面仍用模板阵容。`--align` 只写格位。LETHALITY 2026-09-27 改正：此前重制停在模板阵容、裁判又被写进模板 hp／速度，帕尼西亞城 · 廢墟中的雷雨（LEVEL010）034 原版 L10 攻击 68、重制 L1 攻击 59，两边每下伤害差约 9。
- **局面注入：** 停在第一次进入 `0x407340` 时、排序之前，写入 §8 的字段，让原版用它排第 1 回合的队列。`resume_after` 用原版的 `0x4074a0(1)` 把队列推到该单位之后（相当于交接 `0x407510`，但不跑其中的 `0x408370／0x44f4e0`）。
- **随机数：** 在同一停点，`--seed` 写全局流 `0x4795d4／0x4795d8` 并置种子标志 `0x4c1e8c=1`，`--damage-seed` 写伤害流 `0x4c3044／0x4c3040`。
- **缓存：** 停点的机器（含寄存器与活栈）按关卡和成长模式缓存为 `ignored/native_cache/battle_machine/level_v1_*.pkl`，启动态缓存为 `boot_v1_*.pkl`。
  - 实测单跑（机器空闲）：缓存命中时第 3 关 1.5 s、第 52 关 0.5 s；无缓存冷跑时第 3 关 34.7 s、第 52 关 21.1 s。
  - 冷跑与缓存命中的输出逐字相同（§3 钩子须知）。
- **单位命名：** 按开场格、再按注册槽顺序，对照 `content/battles/battle_<关>.json`。

### 11.2 用法

```sh
U="uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3"
B=docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json
# 原版：注入 r1 局面，全局流 (1,1)，写 SITE_MAP 改名后的对照行
$U tools/hsltools/probes/_enemy_level.py --level 51 --board $B --board-key r1 --seed 1 1 --lines ignored/oracle2/r1_orig_s1.jsonl --brief
#   --set ID.FIELD=V 叠加在 board 上（字段同 §8）；--turns N；--bare-lines 给导出器 --expect；--no-cache 冷跑
# 重制：同一局面、--seed 1
tools/godot.sh --headless --script res://tests/diagnostics/export_enemy_turns.gd -- --battle 051 --turns 1 --seed 1 --state $B --state-key r1 --out ignored/oracle2/r1_remake_s1.jsonl
# 两端逐行动、逐抽取对照
python3 tools/hsltools/probes/_enemy_level.py compare ignored/oracle2/r1_orig_s1.jsonl ignored/oracle2/r1_remake_s1.jsonl
# 批量：关卡 × 种子，原版进程池与重制导出都按 --jobs 并行（重制单次 600 s 超时），表格与 batch.json 写到 --out
$U tools/hsltools/probes/_enemy_level.py batch --levels 3,6,10,51,52 --seeds 1,2,3 --jobs 3 --out ignored/oracle2/batch2
```

`compare` 按 actor 配对，比较 from／to／action／target 和先后顺序（顺序计数跳过重制没有的原版行动者）。然后把两边抽取按 (site, n) 逐个对照，报第一个分歧；值另报。最后一行是 `ORACLE_MATCH total …`。`ORACLE_DRAWS` 行给每个站点两边的次数。

### 11.3 抽取点对照表

`enemy_turn.SITE_MAP`（static-derived：逐个调用点反汇编回所在函数，再对照重制在该处抽取的那一行）覆盖首战样本里全局流的全部站点：

| 原版调用点 | 重制 `Script.function` |
| --- | --- |
| `0x40bd4f`（raw & 1） | `AIDecisionRules.select_target` |
| `0x40c061` | `AIPriorityRules.low_hp_target` |
| `0x40c138` | `AIPriorityRules.self_recovery` |
| `0x40c58d` `0x40c5b3` `0x40c5f8` | `AIDecisionRules.select_action` |
| `0x40c7f8` `0x40c842` `0x40de0c` `0x40de56` | `AISkillDecisionRules.select_index` |
| `0x40d500` | `AISkillDecisionRules.area_order` |
| `0x4136ba`（raw & 1） | `AINavigationRules.station_order`（`0x413390` 站位排序等距交换） |
| `0x440bf5` | `AINavigationRules.attack_station` |
| `0x41385d`（raw & 1） `0x413890` | `AINavigationRules._nearest_stoppable` |
| `0x440db5` `0x440ddf` `0x440e1b` | `AIPriorityRules.choose_check` |
| `0x440e57` `0x440e93` `0x440ecf` | `AISupportRules.next_check` |
| `0x43ff32` | `AIDecisionRules.side_walk_roll`（`0x43ff1f..0x44003c` 法术落空后 rand(100) ≤ 10 侧移） |
| `0x40cb54` `0x40cb99`（raw & 1） | `AISkillPlanning.centre_scan`（`0x40c9a0` 施法中心同覆盖时的取舍） |
| `0x40d1c8` | `AISkillPlanning._cast_search`（`0x40cca0` 留下的移动施法格、无威胁时 rand(count)） |
| `0x40d273`（raw & 1） | `AISkillDecisionRules.farthest_index`（`0x40d200..0x40d2b0` 离威胁等距） |

- raw & 1 的站点在 `--lines` 里记 n=2、值取低位：同一生成器状态下，原版 raw & 1 与重制 rand(2) 是同一位。
- 伤害流站点另表 `DAMAGE_SITE_MAP`（导出器不记伤害流，对照行不写）。本次新加魔法的三处：`0x40a7f0`／`0x40a884`／`0x40a893` → `NativeMagicRollRules.roll`（`0x40a7b0` 命中 rand(100)+1，两次 rand(half+1)）。
- 魔法行动窗口里出现、重制没有对应的全局流站点登记在 `UNMAPPED_ACTION_SITES`：`0x401390`、`0x415c10` 与 `0x415d90..0x4239xx` 效果进程区；还有 `0x407cc0` 入场与 `0x40e870` 升级（§11.5）。每个站点各自的含义没有逐一证明。
- **两端逐值对拍目前对不上。** 原版每个 NPC 行动都先抽优先级链：`choose_check`、`low_hp_target`、`self_recovery`、`area_order`、`next_check`、`select_action`、`select_index`。重制在这些局面里大多只抽 `select_target` 和 `_nearest_stoppable`，所以第一个分歧落在第 1–6 次抽取。各关的"抽取站点相同"全是两边都 0 次抽取的行动（`draws_both_empty`）；非空抽取序列没有一条逐站点一致。

### 11.4 结果

本节的重制列与「归类」是 ORACLE2 当时的重制（2026-09-25）；之后的重制现状见差异清单 `ai-first-battle-moves`。

**第 51 关 r1，种子 1**（原版 (1,1)，重制 `--seed 1`）：

```
ORACLE_MATCH total agree=2/11 order=11/11 draw_sites_same=0/11 draw_values_same=0/11 extra=0 draws_both_empty=0
ORACLE_DRAWS site=AIPriorityRules.choose_check original=53 remake=0
ORACLE_DRAWS site=AINavigationRules._nearest_stoppable original=353 remake=320
```

落点 8/11 一致。9 处分歧按两边各 32 个种子的分布归类（原版 (s,s)、重制 `--seed s`，s=1..32）：

| actor | 分歧 | 归类 | 依据 |
| --- | --- | --- | --- |
| 023_2 | to＋target 021_1 对 021_2 | 规则 | 持有目标集合不相交：原版 {026_1, 021_1}，重制 {021_2, 021_4} |
| 021_2 | target leonard 对 023_2（to 随机） | 规则 | 原版 14/32 持有雷歐納德，重制 0/32；原版从不持有 023_1，重制 19/32 |
| 021_4 | target leonard 对 023_1 | 规则 | 同上：原版雷歐納德 19/32、023_1 0/32；重制雷歐納德 0/32 |
| 021_5 | target leonard 对 023_2 | 规则 | 原版雷歐納德 13/32，重制 0/32 |
| 023_1 | target 021_1 对 021_2 | 规则 | 原版持有 021_1 7/32，重制 0/32 |
| 024_2 | target 021_4 对 021_1 | 随机 | 两边都出现 021_4／021_2／021_1 |
| 024_1 | target 021_4 对 021_1 | 随机 | 同上 |
| 026_1 | target 023_1 对 023_2 | 随机 | 两边都出现（但原版另有雷歐納德 13/32，重制 0/32） |
| 026_2 | to [7,9] 对 [6,8] | 随机 | 两格两边都出现 |

注入缺口 0 处。规则类集中在持有目标：原版友军（021_x、026_x）常持有雷歐納德，重制除 021_3 外从不。

**第 3 关，种子 1**（board `{"growth": false}`，重制导出 14 个行动）：

```
ORACLE_MATCH total agree=12/14 order=14/14 draw_sites_same=7/14 draw_values_same=7/14 extra=0 draws_both_empty=7
```

| actor | 分歧 | 归类 | 依据（两边各 16 个种子） |
| --- | --- | --- | --- |
| 028_2 | target hu 对 leonard | 规则 | 原版 [5,9] 攻击 hu 16/16；重制从不打 hu |
| 028_5 | to [14,16] 对 [16,14] | 随机 | [14,16] 原版 12、重制 11；[16,14] 4 对 5 |

另外 028_1 种子 1 时一致，但站位规则不同：原版 16/16 走 [6,10]，没有 `attack_station` 抽取；重制在 [6,10]／[5,9] 间 7/9 分，抽 `attack_station` rand(2)。归为规则。

**第 52 关，种子 1**（重制导出 15 个行动）：

```
ORACLE_MATCH total agree=11/15 order=15/15 draw_sites_same=7/15 draw_values_same=7/15 extra=2 draws_both_empty=7
```

- 4 处分歧都是随机，16 个种子的分布两边共有：021_5 的 to，023_2 的 to，024_1 与 024_2 的 to＋target。
- 多出的 2 个是 `slot27/28_code069`（SID_ENEMY069），当时在重制导出器的 `excluded_source_actors` 里。原版里 024_1、024_2 各有一次以它们为目标。归为注入缺口（重制阵容排除）。原版两名 069 装入时 EVEF obj_Data9 1 把 pmPlayer 换成 pmEnemy（`0x407ec0`），站为敌方：(15,14)／(6,13)，48 个种子第 1 回合都 wait 不动（runtime-measured）。

**批量 5 关 × 3 种子**（board `{"growth": false}`，`--jobs 3`，与其他 lane 并行、机器有负载）：

| level | seed | 原版行动 | 重制行动 | 一致 | 顺序 | 抽取站点相同（两边皆空） | 原版 s | 重制 s |
|---|---|---|---|---|---|---|---|---|
| 003 | 1 | 14 | 14 | 12 | 14 | 7 (7) | 1.7 | 3.9 |
| 003 | 2 | 14 | 14 | 11 | 14 | 7 (7) | 1.9 | 3.9 |
| 003 | 3 | 14 | 14 | 11 | 14 | 7 (7) | 2.0 | 3.4 |
| 006 | 1 | 23 | 9 | 4 | 9 | 2 (2) | 3.5 | 4.0 |
| 006 | 2 | 23 | 23 | 19 | 23 | 2 (2) | 3.4 | 4.1 |
| 006 | 3 | 23 | 23 | 19 | 23 | 2 (2) | 3.3 | 3.9 |
| 010 | 1 | 4 | 4 | 1 | 4 | 0 (0) | 8.8 | 3.6 |
| 010 | 2 | 4 | 4 | 3 | 4 | 0 (0) | 10.3 | 2.8 |
| 010 | 3 | 4 | 4 | 2 | 4 | 0 (0) | 10.8 | 2.8 |
| 051 | 1 | 11 | 11 | 0 | 11 | 0 (0) | 1.0 | 4.0 |
| 051 | 2 | 11 | 11 | 3 | 11 | 0 (0) | 0.9 | 3.8 |
| 051 | 3 | 11 | 11 | 4 | 11 | 0 (0) | 1.0 | 4.0 |
| 052 | 1 | 17 | 15 | 11 | 15 | 7 (7) | 1.6 | 4.7 |
| 052 | 2 | 17 | 15 | 11 | 15 | 7 (7) | 1.8 | 6.5 |
| 052 | 3 | 17 | 15 | 12 | 15 | 7 (7) | 1.9 | 9.8 |

`BATCH levels=5 seeds=3 jobs=3 original_wall=23.3s total_wall=49.5s`

并入 pipeline-line（WRANGE 射程传播、RNG-A）后重跑，各格计数逐一相同。耗时随机器负载变化，那一次是 `original_wall=56.7s total_wall=101.3s`。

- 第 6 关种子 1 的重制只导出 9 个行动：导出器日志无错，是重制这一局在回合中途判定胜负（雷歐納德本回合被打 3 次）。这是重制一侧的结局，不是工具问题。
- 第 51 关这里用 `{"growth": false}`，不是 r1，所以与上面 r1 的数字不同。

### 11.5 魔法（经注入实测）

把 026_1、026_2 挪到敌群旁（r1 局面加 `--set 026_1.cell=17/15 --set 026_2.cell=16/16`，全局流 (1,2)）：

```
actor026_2 [16, 16]->[16, 16] magic actor024_2 skill=magic:magicFIRE:magicCode01 draws=521
stop=round_end frames=2355 rounds=[1, 1] opening_frame=852 clicks=10 handoffs=1 cache=hit unnamed=[] unattributed={}
```

- 动作分类走名牌 `0x43e110`（§4），024_2 的 HP −20。026_1 在自己行动之前就被 023_1、024_1 打倒（hp_end 0）。
- 这次施法的伤害流 (site, n, value)：`0x40a7f0` 100→23，`0x40a884` 8→0，`0x40a893` 8→2（`0x40a7b0` 命中与散布），`0x40a660` 10→1，`0x40a6d7` 3→2（经验）。
- 这个窗口共 521 次抽取：伤害流 5 次；全局流 516 次，其中 AI 决策站点 28 次（含 `0x40cb99` 4 次），效果进程区 472 次（`0x401390` 144、`0x415c10` 99、`0x415d90..0x4239xx` 229），一次单位入场 16 次。
- **入场（模拟器实测）：** 026_2 成为当前行动者的那一帧（停点后第 1844 帧），`0x43eedd` 路径对一个开局时不在盘上的对象调了 `0x407cc0`（经 `0x43eef6`）和 `0x40e870`（经 `0x43ef26`）。对象 `0x212cd4c0`，`+0x64` 进程类型 5，格 [8,6]，恰是本关 `escape_zone`；`+0x80 = 0x90100000`；入场后拿到注册槽 31。r1 原局面和批量各局里都没有这次入场，只在挪了 026_1、026_2 的这一局出现。`0x407cc0` 发事件 `0x446c40`，`+0x7c` 加 rand(0x18)，经 `0x40ba20／0x411a30` 占格，再调 `0x407660`。这些抽取（`0x407dba`、`0x407c86`×5、`0x40e92c..0x40eaf9`）记在当时行动者名下，但不是施法者抽的；其中 `0x407dba` 是出生的张延迟 `rand(24)`、`0x407c86` 是 pmEnemy 的携带 `rand(101)`（本表 5 项都未中，lane RNGC 实测，[奖励输入](battle_reward_inputs.md)）。它是什么对象没有查（未验证）。
- **两边 8 个种子的分布**（原版 (s,s)，重制 `--seed s`，board = r1 加同样两格）：

  | | 原版 | 重制 |
  | --- | --- | --- |
  | 023_1 攻击谁 | 026_1 8/8 | 026_1 3/8，026_2 5/8 |
  | 谁活到自己行动 | 026_2 8/8（026_1 全被打倒） | 026_2 2/8，026_1 5/8，都没活 1/8 |
  | 026_2 的动作 | 魔法 024_2 5 次、024_1 2 次，攻击雷歐納德 1 次（原因未查） | 魔法 023_2、023_1 各 1 次 |
  | 026_1 的动作 | — | 魔法 024_1 2 次、023_1 2 次，自用道具 1 次 |

  归类：魔法目标是规则（两边目标集合不相交）；023_1 的攻击目标、以及因此谁活下来，也是规则。样本小。重制里 026_1 的道具是本 lane 唯一见到的 item 动作，原版一侧没有。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/loop/BattleLoopInit.gd` rules：global stream `global_rng` 0x4795d4／0x4795d8: not per battle — the scene hands in the process's live words, GlobalRandomStream.session; a caller without them seeds it from reward_seed as the clock would, 0x458c10 [t, t ^ 0xe54a231c]
- `game/sim/GlobalRandomStream.gd` rules：global words 0x4795d4／0x4795d8 outside the save, clock seed behind flag 0x4c1e8c: the lazy seed 0x458c19..0x458c28 stores [t, t ^ 0xe54a231c] over the static data words 0x12345678／0x87654321, 0x40e870 draws only here
