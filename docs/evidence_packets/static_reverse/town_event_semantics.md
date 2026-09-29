# 城镇事件（TOWNDEF te token）读法表

> evidence: provisional; resource-derived; static-derived: 带地址的读法 · status: live · functions: 0x414280, 0x4264a0, 0x42caa0, 0x434680, 0x434770, 0x4348f0, 0x4545e0, 0x454610, 0x454690, 0x4546c0, 0x454720, 0x454740, 0x454760, 0x4547a0, 0x4547f0, 0x454870, 0x4548b0, 0x454950, 0x4549e0, 0x454a20, 0x454ae0, 0x454cd0, 0x454db0, 0x454e20, 0x456150, 0x4561d0, 0x45e80d, 0x45e882 · tools: hsltools/checks/function_catalog.py, hsltools/data/town_initial_trees.py, run_town_event_rules_tests.gd · updated: 2026-09-29

## 结论

- 原版 TOWNDEF 的 te token 名、参数顺序、事件表与脚本引用可从资源读出；带地址的条目（teCheckMoney、teCheckItemExecEvent、teCheckTEExist、teCheckJobUp 失败链、teAppearSecretMan、teSecretManBuyThing、tePlayerSelectInsertEvent 的选人名单与「離開」行、消息与延时的时钟、初始菜单树）已由 `0x454e20` 等静态阅读确认（resource-derived；static-derived）。
- 重制 `game/sim/TownEventRules.gd`（无状态 te 解释器）与 `content/world/town_initial_trees.json` 按此实现，执行记录的 `provisional` 字段引用本表 `town_event_semantics:<te token>`。
- 执行模型已由静态阅读确认（static-derived，下文「执行模型」）：单指针 VM 的返回码由城镇 BOSS 对象 740（`0x4561d0`）的状态机经跳表 `0x456c84` 分派，子菜单靠一个旗标 `0x4000` 重开与退出，选择行与 teExecEvent 找到事件就跳转、不回来，事件末与条件失败同回最近的子菜单或根菜单，石纹板只在列菜单时在屏上、选择与 teDelay 期间不动。其余不带地址的 token 行为仍是重制读法（provisional，差异清单 `town-event-timing`）。

## 证据

### resource-derived：结构

结构来源见[世界地图数据链](world_map_data.md)：`towndef.json`（`hsl_towndef.v1`，191 条 town_event、62 条 item、
923 条 te 指令、46 个 TOWNDEF.H 定义 token）。解释器读写的世界状态是 `hsl_world_state.v1`（由世界地图运行时创建，
本模块只改 `towns` 与大地图旗标／事件／模式表；`current_point`／`visited_points` 不在此改写）。

### static-derived：消息与延时的时钟（r2ghidra 反编译 `0x454e20`，未执行）

VM 以 `*param_4` 高半字为阶段、每次过程调用进一次（一次主循环＝一 tick，见 `OriginalTick`）：

| token | 原实现 | 重制 |
| --- | --- | --- |
| tePlayerMessage 5／teShapeMessage 7 | 置消息标志为 1、`0x4072b0` 建消息、`0x414220(msg, 位, if_wait, 头像)`（位：player 0／shape 1 → 消息对象 `+0x80` 的 `0x4000`；if_wait → `0x2000`），阶段 5／7；此后每次调用只查标志，**标志清零（消息关掉）才回阶段 0**，下一次调用才执行下一 token。if_wait≠0（`0x2000`）的框末页不收确认、等同一标志被别处清零才收起（`0x41470a`，[原作对白框](original_dialogue_board.md)「if_wait 位」）；VM 也停着等这个标志，能清它的 teDelete*Message 执行不到——TOWNDEF 453 句的 if_wait 全为 0 | 每句等确认（与原版 if_wait 0 同）；if_wait 位不实现（TOWNDEF 不用） |
| teDelay 14 | `0x4c1d54 = N`、阶段 0xe；阶段 0xe 每次调用减一，减到 ≤0 那次只复位阶段，**下一 token 在 teDelay 后第 N+1 次调用执行** | 无对白板停 (N+1)×16 ms（`TownRuntime._hold`）；玩家输入不跳过，脚本化 `confirm()` 可跳过（测试用） |
| teMenuMoveOut 40 | 阶段 0xe、`0x4c1d54 = 0x14`，返回 4 | 同 teDelay 停 20 tick |
| tePlaySound 28 | `0x42c180(wav, 0)`：音效开关 `0x4c1af4` 开且 `0x477c20` 非零时即播，不等待，同一次调用继续 | 照原版：`0x455710` 调用；三个 WAV（WALK0016／OPEN0001／MOVE0001）由 `tools/hsltools/assets/town_assets.py` 导入 `town_sounds/`，`TownRuntime._play_sound` 当场播放 |
| teDeletePlayerMessage 6／teDeleteShapeMessage 8 | 把对应消息标志清零 | 只记录（每句已等确认关板） |

### static-derived：执行模型——城镇 BOSS 对象 740（r2 反汇编 `0x4561d0`，未执行）

城镇画面由对象 740（WINDOW70 石纹板，`0x456150` 建，初始 x −260 在屏外）的过程 `0x4561d0` 驱动：参数 −1 为绘制，`0x4561e8` 只在 `+0x30` 为 −1 时不画——`+0x30` 是通用形状字，只有城外调用者经 `0x45e525`／`0x45e554` 写，城镇代码不写，所以板在每个状态都照画，离开画面只靠滑到屏外。其余调用按 `+0x8c` 状态走（跳表 `0x456be0`／索引 `0x456c24`）。VM `0x454e20` 只有一个 token 指针 `+0x38` 与阶段字，没有调用栈；子菜单只靠 BOSS 的旗标 `0x4000` 与续点 `0x4c27d4`。

| 状态 | 行为 | 地址 |
| --- | --- | --- |
| 0 | 载 TOWNBG → 1 | — |
| 1 | 淡入；完 → 2，`0x454720` 查到进城 exec 事件则 → 80 | — |
| 2 | 板经 `0x45e882`（参数 40）滑到 (60,60)，到位 → 3 | `0x45671d` |
| 3 | `+0x88 = 0`；`0x4000` 未置时 `+0x98 = −1`；→ 4 | — |
| 4 | 菜单：更新悬停行 `+0x9a`（鼠标不在板上为 0xffff）；左键（`0x4c6398 & 0x10000`）→ 音效 398、状态 5。右键／Esc：子菜单模式清 `0x4000`、`+0x38 = [0x4c27d4]`、`+0x98 = 0`、进状态 5 并当场调 VM；根菜单模式 → 6，`0x454760` 查到离城事件则 → 70 | `0x45630f` |
| 5 | 调 VM（`0x4568a1`），返回码经 `0x4568b7` 的跳表 `0x456c84` 分派（下表） | `0x4568a1` |
| 6／90 | 板经 `0x45e80d`（参数 4、20）滑到 x −260，到位 → 状态＋1 | `0x456b2f` |
| 7 → 8 → 9 | 淡出、注销 | — |
| 70 → 71 → 72 | 板滑出（`0x456a17`）；72 调 VM(−2,−2) 跑离城事件 | `0x456a83` |
| 80 → 81 | 81 调 VM(−1,−1) 跑进城事件，只理返回 1（→ 2） | `0x456ad6` |
| 89 | 板滑出，到位 → 5 | `0x456af8` |
| 91／92 | 商店（`0x42a9d0`、`0x42ab40`）开着；关了 → 5 | — |

| VM 返回 | 何时 | BOSS 去向 | 地址 |
| --- | --- | --- | --- |
| 0 | 选择窗开着（阶段 0xf／0x1e）、teDelay／teMenuMoveOut 计数（0xe）、消息等关板（5／0xc／7）、停在阶段 0xd | 留在状态 5，下次再调 | — |
| 1 | 事件末（token 0）；「结束事件」的条件（teCheckTEExist event 0、teCheckJobUp fail −1、选择行事件 −1、teCheckMoney 不足那句关掉后） | 状态 2 | `0x4568cd` |
| 2 | teCreateSubEventMenu（case 10，`0x4c27d4` ← token 后的指针） | 置 `0x4000` → 状态 2 | `0x4568be` |
| 3 | teCreateShop | 状态 90 | `0x4568db` |
| 4 | 建消息（tePlayerMessage／teShapeMessage、teCheckJobUp 失败句、teCheckMoney 不足提示、显示的 teGetGold）、teMenuMoveOut（case 0x28：阶段 0xe、20 tick）；只有 `0x4551ed`（teMenuMoveOut）与 `0x45561a`（消息尾）写 4 | 状态 89 | `0x45691d` |
| 5 | 消息关掉且下一 token 是 0 | 状态 2 | `0x456ae9` |
| 其他 | — | 不理，留在状态 5 | — |

推论：

- 子菜单：返回 2 后状态 2 列出所点根行（`+0x98`）的 children（`0x454610`）；点子项 → 状态 5 从子项事件起跑；子项链结束（返回 1／5）→ 状态 2，`0x4000` 还在，所以子菜单重开；右键／Esc 清 `0x4000`、指针回 `0x4c27d4`，当场接着跑 teCreateSubEventMenu 之后的父事件尾巴，尾巴结束 → 状态 2 列根菜单。
- teMenuMoveOut 不碰 `0x4000`：只让板滑出 20 tick，当前链结束后子菜单照样重开、板滑回。
- 条件失败与事件末同为返回 1：子菜单模式回子菜单，否则回根菜单；没有「回到父链」。
- 跳转不回来：teExecEvent（case 0x11 → `0x4556ea`）目标 0 或查不到越过 token 继续，否则指针换到目标事件；选择（阶段 0xf／0x1e 的 `0x455ef0`）窗口结果 −2 等待、−1 越过 token，所选行事件 −1 返回 1、0 或查不到越过 token、找到则指针换到该事件。
- teSetNextPlayLevelEvent（case 0xd）停在阶段 0xd，VM 没有这一阶段的处理，此后每次返回 0，BOSS 停在状态 5。

石纹板在各阶段：

| 阶段 | 石纹板 | 地址 |
| --- | --- | --- |
| 进城 exec 事件（状态 80／81） | 不在屏上（建时 x −260，还没滑入过） | `0x456150` |
| 列根菜单／子菜单（状态 2 → 4） | 滑入 (60,60)；根行 `0x4545e0`、子菜单行 `0x454610`，每帧照树现画 | `0x45671d` |
| 消息、teCheckMoney 不足、显示的 teGetGold、teMenuMoveOut（返回 4） | 状态 89 滑出，下次列菜单才回来 | `0x456af8` |
| 选择、teDelay（返回 0） | 不动：在屏上就照画，行照画；只在状态 4 收点击；悬停行 `+0x9a` 在任何状态都画绿，所以点过的行在选择期间仍是绿的 | `0x45630f` |
| teCheckJobUp／teCheckJobUp2 成功（返回 0） | 不动。token 成功段（`0x455cd8`）置阶段 0x1f 后不写返回值；阶段 0x1f（`0x455f20` → 表 `0x45613c`）子阶段 1（`0x455f4e`）建 1354 称号句（`0x4072b0`）并经 `0x414220` 挂脸图，子阶段 0／2 等 `[0x4c1d54]` 清零、3 回阶段 0，全程返回 0，BOSS 留在状态 5。TOWNDEF 事件 61–68、79、80 都在 teCheckJobUp 前放一句 tePlayerMessage（返回 4），板在称号句出现前已滑出 | `0x455f4e` |
| 商店（返回 3） | 状态 90 滑出 | `0x456b2f` |
| 离城（状态 6／70） | 滑出 | `0x456b2f`、`0x456a17` |

### static-derived：菜单树 `[0x4c1d74]`

每镇 0x108 字节：8 个 0x20 字节节点槽（dword 0＝节点事件，dword 1–7＝children），`+0x100`／`+0x102`（word）为进城／离城 exec 事件（读 `0x454720`／`0x454760`；`0x454740` 写进城事件）。根菜单行＝各槽节点，子菜单行＝所点节点的 children，只有两层。

| 操作 | 原版 | 地址 |
| --- | --- | --- |
| 查节点 | 只在 8 个槽里找 | `0x454690` |
| AddTE num=0 | 节点不在则放进第一个空槽；8 槽满则不加 | `0x4547a0` |
| AddTE num>0 | 逐个 child：先确保节点（`0x4547a0`），再追加 child，已有不重复，至多 7 个 | `0x454870` → `0x4547f0` |
| DeleteTE num=0 | 删该节点槽，后面的槽前移（`+0x100` 的 exec 事件先存后还） | `0x4548b0` |
| DeleteTE num>0 | 逐个 child 从节点的 children 删去并前移；随后首个 child 槽为 0（没有 child 了）就删掉节点 | `0x454950`、`0x4549e0` |

TOWNDEF 的 teAddSelfTE／teAddTE／teDeleteSelfTE／teDeleteTE 与 PAK 全部 STORY／winfail 的 actAddTE／actDeleteTE 都不触及容量上限、不删空节点、不对非根节点做 AddTE。

### resource-derived 结构与解释器读法：token 表

「结构」列为 TOWNDEF.H 签名注释（resource-derived）；「读法」列为解释器行为（provisional，除非注明为纯记录）：替换证据是各 te handler
的静态分析（`PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query` 定位候选）或原作有界采样；在此之前不能据「读法」列声明原版对金币、物品、旗标或菜单的实际改写。

| token | 结构（TOWNDEF.H） | 读法 | 状态／效果 |
| --- | --- | --- | --- |
| teAddSelfTE／teAddTE | `[parent][num][child…]`／`[town][parent][num][child…]` | num=0：把 parent 节点加到根；num>0：确保 parent 存在（缺则入根），再追加 children | `towns[*].tree`；`tree_change` |
| teDeleteSelfTE／teDeleteTE | 同上 | num=0：整节点连子树删除；num>0：删列出的 children | 同上 |
| tePlayerMessage／teShapeMessage | `[player id][msg][if_wait]`／`[shape][name][msg][if_wait]` | 顺序效果，不阻塞解释 | `player_message`／`shape_message` |
| teDeletePlayerMessage／teDeleteShapeMessage | — | 效果 | `delete_*_message` |
| teDelay／tePlaySound | `[delay]`／`[wav num]`（数据里是 WAV 路径） | 效果 | `delay{ticks}`／`play_sound{sound}` |
| teCreateShop | `[shop' name]` | pending `shop`，货表＝所属 town_event 的 `item_code` 对应 `[item]`；买卖是调用方事务 | `shop{shop_name_id,item_ids}` |
| teGetGold | `[number], if bit 31 = 1, display` | 低 31 位为金额，bit 31 为显示旗 | `party.gold`；`get_gold` |
| teGetItem | `[item id][number]` | 合并到 `party.items` | `get_item` |
| teSetExecEvent／teSetTownExecEvent | `[town id][event]` | 两者同义写 `exec_event` | `set_exec_event` |
| teSetTownExitExecEvent | `[id][event]` | 写 `exit_exec_event` | `set_exit_exec_event` |
| teCheckMoney | `[gold][shape][name][msg id]` | **static-derived（0x4555a5／0x455627）**：足够立即扣除并继续；不足不扣、播 shape_message 后结束本事件（VM 返回 1） | `spend_gold`／`check_failed` |
| teCheckPlayerExist／teCheckItemExist | `[player id]`／`[id]` | **static-derived（0x454e20）**：此版 VM 只前进 opcode、不检查也不读参数——实现为 no-op（TOWNDEF 中 0 次使用） | —（记录 `noop`） |
| teCheckItemExecEvent | `[item id][event][delete]` | **static-derived（0x454cd0）**：查队员八槽，有则 delete≠0 扣 1、event≠0 跳转（event 0 继续）；无：继续 | `remove_item` |
| teCheckTEExist | `[town id][parent][child][event id]` | **static-derived（0x455db7／0x4546c0）**：child 在 parent 下：event≠0 跳转、event 0 结束本事件；不在：继续 | — |
| teCheckJobUp／teCheckJobUp2 | `[player id][fail msg][fail event]` | 失败分支（static-derived）：播 fail 消息，fail event＝-1 结束事件、有效 event 跳转；成功链已重制为 PLAYERS 目标行合并（0x434770／0x4348f0，见下文迁出表与[原作城镇转职](original_town_job_up.md)） | `job_up`／`player_message` |
| teCheckJobUpDeny／teCheckMoney2 | 无签名，0 次使用 | 纯记录 | `recorded_only` |
| teBMSetPointFlag／teBMClearPointFlag／teBMSetTrackFlag／teBMClearTrackFlag | `[id][flag]` | 增删旗标名（`point_flags`／`track_flags`，字符串键） | `bm_flag_change` |
| teBMSetShowTrackPoint | `[id]` | 追加到 `show_track_points` | `bm_show_track_point` |
| teBMSetPointEvent／teBMSetPointEventNotVisit | `[id][event][flag]` | 写 `point_events[id]={event,flag}`；NotVisit 区别只在效果里 | `bm_point_event{not_visit}` |
| teBMSetPointMode／teBMSetTrackMode | `[id][mode]` | 写 `point_modes`／`track_modes`（gameBM* 经 TYPE.H 解析） | `bm_point_mode`／`bm_track_mode` |
| teBMSetPointEncounterRatio（仅 act 版） | `[id][ratio]` | 写 `encounter_ratios` | `bm_encounter_ratio` |
| teSetBMWalkToPoint | `[from][to]` | 写 `state.pending_walk {from,to}`；世界地图运行时在离城／进图时执行：from≠49 先作当前点（`0x45543a`→`0x42cc60`→`0x42f7a4`），再按 `0x427070` 多跳走到 to（与玩家点击同路，薛維斯港 138 送船 11→12、戈黎塔尼港 183 25→26），无路线原地不动 | `bm_walk_to_point` |
| teAddOverScore | `[id][score]` | 累加 `over_score[id]` | `over_score` |
| teAppearSecretMan | `[town id][tavern event][mode]` | 机制 **static-derived（0x454db0）**：缓存 0 未决／-1 失败／正数已选；未决时严格 `rand(100)+1 < ratio` 才把 0x479398 表 `[123,113,114,115,116,117,118,119,120]` 的当前索引事件加为 tavern 子项并缓存，相等失败缓存 -1 不再掷，mode≠0 强制。**provisional**：默认 ratio（本包取数据里唯一出现的 8）、表索引（从 0 起＝123）、缓存何时重置（本包随 teDeleteSecretMan 清除） | `secret_man{appear\|absent\|cached}` |
| teDeleteSecretMan／teSetSecretAppearRatio | —／`[ratio]` | 从 tavern 子项移除已缓存的神秘男子并清 `secret_man`／写当前城镇 `secret_appear_ratio`（0 视为未设） | `secret_man{delete\|ratio}` |
| teSecretManBuyThing | `[shape][name][fail msg][fail event]` | **static-derived**（[原作酒館神秘男子](original_secret_man.md)：0x454e20 case 0x27）：`secret_man_goods[secret_man_index]` 行——金币不足 → 无脸 `[fail msg]` 再跳 `[fail event]`（0 继续）；足够 → 扣价、按位置 `rand(n)` 取该行一件物品（teGetItem 同路入包）、计数器 +1（上限 8） | `shape_message`＋`check_failed`／`spend_gold`＋`get_item`＋`secret_man{purchase}` |
| 未定义 token | — | 记录 `unknown_token`，链继续 | `recorded_only` |

脚本侧 `apply_script_town_actions` 接受 winfail／STORY 的 `act*` 同名 token（`actAddTE`、`actDeleteTE`、`actSetTownExecEvent`、
`actSetTownExitExecEvent`、`actBM*`、`actSetBMWalkToPoint`、`actSetBMWalkerPlayerID`），参数形状与 te 版相同，走同一套状态改写；`actSetBMWalkerPlayerID`（原版唯一写者是剧情 opcode 96 `0x4518d5`）把槽号写进世界状态 `bigmap_walker_player_id`（[行走者是谁](original_world_town.md)）；原版城镇 VM 没有 `teSetBMWalkerPlayerID`（towndef token_ids 只有 1–44、100、101），te 名只是 `apply_script_town_actions` 把 act 换成 te 的内部路由。

### static-derived：初始菜单树

TOWNDEF 没有城镇归属字段；EXE 的初始树由 `0x454a20` 逐项建立（`0x454ae0` 清零树缓冲 `[0x4c1d74]` 后调用它）（[original_world_town](original_world_town.md)），执行结果与本表一致。生成规则保留为推导记录：`content/world/town_initial_trees.json` 按以下规则生成，每条 entry 带 `source`：

1. 段头注释里的城镇名归类（如「歐姆村武器店」）；酒館类子项按注释前缀嵌套（「米蘭多酒館老闆」→ 7）。注释不是引擎数据 → provisional。
2. 排除运行时才出现的节点：TOWNDEF 的 teAddSelfTE／teAddTE 与 PAK 全部 STORY／winfail 的 actAddTE 所加的 children（num=0 时为节点本身）、
   以及只经 teExecEvent／teSetExecEvent／teSetTownExecEvent／select／check 跳转到达的事件（引用本身 resource-derived）。
3. 商店事件（teCreateShop）全部由脚本加入的城镇初始为空（薛維斯港、兩棲族部落、瑪哈亞鎮、沙羅尼亞、斐達克、戈黎塔尼港、亞雷比斯）；
   其中没有任何脚本加入的候选（50、145、150–156 等）记入 `excluded`，不放树（死数据或 EXE 侧默认，未证）。
4. 仅作为 AddTE(num>0) 的 parent 出现且无候选子项的子菜单（命運神殿大廳／港口／神殿中樞、克里夫的家）视为脚本保证节点。

结果：歐姆村 `{0:[1,2,3]}`、米蘭多 `{0:[4,5,6,7], 7:[8,12,13,14]}`、席達鎮 `{0:[16,17,18,20], 20:[21,22,23]}`，其余 9 镇为空树；
`unassigned` 记录无城镇归属的 13 条（酒館神秘男子 113–122、克里夫二 137、152、191）。替换证据：EXE 初始 TE 表或原作各镇首次菜单的有界采样。

## 重制接线

### 重制：执行模型

`TownEventRules` 照上文「执行模型」实现，`TownRuntime` 的石纹板照「石纹板在各阶段」显隐（`_board_in`）；下表只列重制的表示方式与未照做处。

| 项 | 重制 | 与原版 |
| --- | --- | --- |
| run／frame | `begin_event` 建 run，存停放的子菜单帧＋一个运行帧；`resume(run, choice)` 处理 pending | 原版单指针＋`0x4000`／`0x4c27d4`；TOWNDEF 的子菜单都由根行事件自己开、不嵌套，两者走法相同 |
| teExecEvent／选择行 | 找到事件就替换运行帧；0 或找不到越过 token；选择行事件 −1 结束事件 | 同 |
| teCreateSubEventMenu | pending `sub_menu`，子项＝树中该事件的 children；每个子项链结束后重开；`exit` 越过该 token 跑父事件尾巴 | 同 |
| teMenuMoveOut | 只出 `menu_move_out`（停 20 tick、板滑出），子菜单照常重开 | 同 |
| 事件末／条件失败 | 弹到最近的停放子菜单并重开，否则 run 结束、列根菜单 | 同 |
| teSetNextPlayLevelEvent | 记录 `next_level_event` 并结束 run（离开城镇） | 原版停在阶段 0xd；之后由谁带出城未读（边界） |
| 石纹板 | 显隐照上表；滑入滑出没有动画；行是列菜单时的快照；选择期间点过的行不保持绿色 | 差异清单 `town-layout-extras` |
| 菜单树 | `towns[*].tree` 字典：num=0 删除连子树、删 child 连它自己的节点、删空的节点保留、不设 8／7 上限、AddTE 在整棵树里找 parent | 与 `0x4547a0`–`0x4549e0` 不同，数据不触发（上文） |

### 重制：解释器读法字符串

解释器读法原文集中在这里；代码只保留 token 表 `TownEventRules.PACKET_READING_TOKENS`，每条执行记录的 `provisional` 字段存引用 `town_event_semantics:<te token>`（act* 双胞胎按其 te 名查表）。evidence 列取自原句开头的层级词：`static-derived` 只覆盖句中给出地址的部分，句内标 provisional 的部分与不带地址的整句都是重制读法。与上表冲突处（teCheckJobUp／teCheckJobUp2）以本表为准，转职链的地址证据见[原作城镇转职](original_town_job_up.md)。

| te token | evidence | 读法（原文） |
| --- | --- | --- |
| teAddSelfTE | static-derived; provisional | static-derived (0x4547a0, 0x454870 → 0x4547f0): num = 0 adds the parent node to the root; num > 0 ensures the parent node (root if absent) and appends each child not yet listed; provisional: the original's 8-node／7-child capacity is not modelled and the parent is looked up in the whole tree, not only the root slots (no data reaches either) |
| teAddTE | static-derived; provisional | static-derived (0x4547a0, 0x454870 → 0x4547f0): num = 0 adds the parent node to the root; num > 0 ensures the parent node (root if absent) and appends each child not yet listed; provisional: the original's 8-node／7-child capacity is not modelled and the parent is looked up in the whole tree, not only the root slots (no data reaches either) |
| teDeleteSelfTE | static-derived; provisional | static-derived (0x454950): num > 0 removes the listed children; provisional: num = 0 also drops the node's subtree, a removed child's own node goes too and an emptied node stays (the original's 0x4548b0 removes only the root slot and 0x4549e0 drops a node once its children are gone; no data tells them apart) |
| teDeleteTE | static-derived; provisional | static-derived (0x454950): num > 0 removes the listed children; provisional: num = 0 also drops the node's subtree, a removed child's own node goes too and an emptied node stays (the original's 0x4548b0 removes only the root slot and 0x4549e0 drops a node once its children are gone; no data tells them apart) |
| teExecEvent | static-derived | static-derived (case 0x11 → 0x4556ea): a known target replaces the running frame (jump, no return); target 0 or an unknown id continues past the token |
| teSelectInsertEvent | static-derived | static-derived (phase 0xf, 0x455ef0): the chosen row's event replaces the running frame (jump, no return); row event −1 ends the event (VM return 1); 0 or an unknown id continues past the token |
| tePlayerSelectInsertEvent | provisional | options record every candidate with in_party; `listed` keeps the in-party ones whose job_up_flags pass mode 1／2 (0x4557ad), at most nine; the runtime lists those plus the 離開 row (event −1 ends the event) |
| teCreateShop | provisional | shop goods = the owning town_event's item_code list; buying/selling is the caller's transaction |
| teCreateSubEventMenu | static-derived | static-derived (case 10 → VM return 2 → 0x4568be flag 0x4000, BOSS states 2／4): children = tree[this event]; the sub-menu re-opens after each child's chain ends (VM return 1 with 0x4000 still set); exit (right click／Esc) clears 0x4000 and runs on after the token (0x4c27d4) |
| teMenuMoveOut | static-derived | static-derived (case 0x28 → VM return 4 → state 89, 0x456af8): a 20-tick hold that slides the stone board out; the sub-menu stays open and re-opens once the chain ends |
| teCheckMoney | static-derived | static-derived (0x4555a5/0x455627): sufficient gold is deducted at once and the event continues; insufficient gold deducts nothing, shows the shape message and ends the event (VM return 1) |
| teCheckPlayerExist | static-derived | static-derived (0x454e20): this VM only advances past the opcode — no check, no argument read |
| teCheckItemExist | static-derived | static-derived (0x454e20): this VM only advances past the opcode — no check, no argument read |
| teCheckItemExecEvent | static-derived | static-derived (0x454cd0): item found in a party member's slots → delete one when [delete] != 0, then jump when [event] != 0 (event 0 continues); absent: continue |
| teCheckTEExist | static-derived | static-derived (0x455db7/0x4546c0): child present under parent → jump when [event id] != 0, end the event when it is 0; absent: continue |
| teCheckJobUp | static-derived | static-derived (0x454e20 case 0x1f / 0x434770 / 0x4348f0): member in party with a non-zero job-up code and str/dex/mind/con each >= job cap - 50 → merge the target PLAYERS row into the carry member (flag 0x80000000) and show 「<name>的稱號由<old>變成<new>」; otherwise the fail message as the member's face message, then fail event -1 ends the event and a valid event id jumps |
| teCheckJobUp2 | static-derived; provisional | static-derived (0x454e20 case 0x20): same condition and merge with flag 0x40000000; afterwards 0x434680 applies the 兩棲族部落 writes once both 雷歐納德 and 緹娜 have job-up code 0 (provisional: resulting menu not observed natively) |
| teSecretManBuyThing | static-derived | static-derived (0x454e20 case 0x27, original_secret_man.md): row = secret_man_goods[secret_man_index]; gold < price → face message [fail msg] then jump to [fail event] (0 continues); else deduct, grant items[rand(n)] (positional over the non-zero slots) like teGetItem, counter += 1 while < 8 |
| teGetGold | provisional | bit 31 of [number] is the display flag, the low 31 bits the amount |
| teSetNextPlayLevelEvent | static-derived; provisional | static-derived (case 0xd): the VM parks in phase 0xd, which has no handler, so nothing after it runs; provisional: the run ends here (leaving town) and the caller consumes next_level_event — what takes the original out of town was not read |
| teBMSetPointEventNotVisit | provisional | same point_events / type write as teBMSetPointEvent but leaves the Visit bit alone (its handler was not executed; teBMSetPointEvent itself is static-derived 0x426c70) |
| teSetBMWalkToPoint | static-derived | writes state.pending_walk {from, to}; the world-map runtime sets from (unless 49) as the current point, then walks the 0x427070 route to to like a click (0x45543a, 0x42f7a4, 0x427723) |
| teAppearSecretMan | static-derived; provisional | static-derived mechanism (0x454db0): undecided cache → strict rand(100)+1 < ratio adds the table event (`content/generated/hsl/static/hsl01/secret_man_goods.json` rows[index].event, the 0x479398 table) under the tavern event and caches it, a failed roll caches -1 (no re-roll), [mode] != 0 forces; the table index is the purchase counter 0x4c1bd4 (secret_man_index: zeroed by the new-game initialiser 0x42ca70, +1 per teSecretManBuyThing purchase, so 0 → 123 first; original_secret_man.md); provisional: the default ratio (DEFAULT_SECRET_APPEAR_RATIO) is not established |
| teSetSecretAppearRatio | provisional | stored on the town where the running event lives |
| teDeleteSecretMan | provisional | removes the cached secret man from the tavern's children and clears the running town's secret_man |

## 复现

`tools/godot.sh --headless --script res://tests/run_town_event_rules_tests.gd`；初始树 `python3 tools/hsl.py check town_initial_trees`

## 边界

| 项 | 观察 | 替换证据 |
| --- | --- | --- |
| 命運神殿 儀式环 | 71→61…68→（teCheckJobUp 失败）→71 的退出靠 tePlayerSelect 追加的「離開」行（event −1，`0x455831`，[original_world_town 实录](../runtime_observations/original_world_town/README.md)「select 选择窗」）；TOWNDEF 两处用法 mode 为 1 与 2，按 `+0x134` 转职位筛成员，重制已照做 | 原作选人窗实拍 |
| 神秘商人 | 机制、表索引推进与 BuyThing 价格／货物已静态确认（上表、[original_secret_man](original_secret_man.md)）；默认 ratio 与缓存重置点未证 | secret man 设定入口 |
| 商店定价／买卖 | 标价买入、卖价 price×50÷100、重要物品拒收与消息 606／607 已由[原作商店交易](original_shop_transaction.md)静态确认；买入先进手持槽 `0x4c1ce4` 再点背包格放下（`0x42923b`）也已静态确认并照做（同包「结论」） | 手持放置的原版实拍已有两帧，满包互换无样本 |
| teBMSetPointEventNotVisit 与 visited | 与 teBMSetPointEvent 的差别只在名字 | 大地图 handler |
| 子菜单嵌套与跳入的子菜单 | 原版只有一个 `0x4000`／`0x4c27d4`，子菜单行取所点根行 `+0x98` 的 children；子菜单里再开子菜单、跳转到的事件开子菜单、进城 exec 事件里开子菜单（状态 81 不理返回 2）都不在 TOWNDEF 里 | —（数据不触发） |
| 离城接手 | teSetNextPlayLevelEvent 之后 VM 停在阶段 0xd、BOSS 停在状态 5；谁把画面带出城未读 | 读 next level event 全局的读者 |
| 选择窗与石纹板叠放 | 石纹板 238×264 在 (60,60)，选择窗 BOARD02 上缘 y 320，两者在 y 320–324 重叠 4 px；704 与 740 的绘制先后未读 | 引擎绘制链表次序 |
| 消息 if_wait 位 | 已读（见上文消息表与[原作对白框](original_dialogue_board.md)）；if_wait≠0 的城镇消息按静态读法会一直停着，TOWNDEF 453 句全为 0 | —（数据不用） |
