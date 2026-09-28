# 城镇事件（TOWNDEF te token）读法表

> evidence: provisional; resource-derived; static-derived: 带地址的读法 · status: live · functions: 0x434680, 0x434770, 0x4348f0, 0x4546c0, 0x454a20, 0x454ae0, 0x454cd0, 0x454db0, 0x454e20 · tools: hsltools/checks/function_catalog.py, hsltools/data/town_initial_trees.py, run_town_event_rules_tests.gd · updated: 2026-09-28

## 结论

- 原版 TOWNDEF 的 te token 名、参数顺序、事件表与脚本引用可从资源读出；带地址的条目（teCheckMoney、teCheckItemExecEvent、teCheckTEExist、teCheckJobUp 失败链、teAppearSecretMan、teSecretManBuyThing、消息与延时的时钟、初始菜单树）已由 `0x454e20` 等静态阅读确认（resource-derived；static-derived）。
- 重制 `game/sim/TownEventRules.gd`（无状态 te 解释器）与 `content/world/town_initial_trees.json` 按此实现，执行记录的 `provisional` 字段引用本表 `town_event_semantics:<te token>`。
- 其余 token 的行为、帧栈与子菜单重开是重制读法（provisional，差异清单 `town-event-timing`）。

## 证据

### resource-derived：结构

结构来源见[世界地图数据链](world_map_data.md)：`towndef.json`（`hsl_towndef.v1`，191 条 town_event、62 条 item、
923 条 te 指令、46 个 TOWNDEF.H 定义 token）。解释器读写的世界状态是 `hsl_world_state.v1`（由世界地图运行时创建，
本模块只改 `towns` 与大地图旗标／事件／模式表；`current_point`／`visited_points` 不在此改写）。

### static-derived：消息与延时的时钟（r2ghidra 反编译 `0x454e20`，未执行）

VM 以 `*param_4` 高半字为阶段、每次过程调用进一次（一次主循环＝一 tick，见 `OriginalTick`）：

| token | 原实现 | 重制 |
| --- | --- | --- |
| tePlayerMessage 5／teShapeMessage 7 | 置消息标志为 1、`0x4072b0` 建消息、`0x414220(msg, 位, if_wait, 头像)`（位：player 0／shape 1 → 消息对象 `+0x80` 的 `0x4000`；if_wait → `0x2000`），阶段 5／7；此后每次调用只查标志，**标志清零（消息关掉）才回阶段 0**，下一次调用才执行下一 token | 每句等确认（与 if_wait 无关，与原版同）；`0x2000` 位在消息对象里的作用未读 |
| teDelay 14 | `0x4c1d54 = N`、阶段 0xe；阶段 0xe 每次调用减一，减到 ≤0 那次只复位阶段，**下一 token 在 teDelay 后第 N+1 次调用执行** | 无对白板停 (N+1)×16 ms（`TownRuntime._hold`）；玩家输入不跳过，脚本化 `confirm()` 可跳过（测试用） |
| teMenuMoveOut 40 | 阶段 0xe、`0x4c1d54 = 0x14`，返回 4 | 同 teDelay 停 20 tick |
| tePlaySound 28 | `0x42c180(wav, 0)`：音效开关 `0x4c1af4` 开且 `0x477c20` 非零时即播，不等待，同一次调用继续 | 照原版：`0x455710` 调用；三个 WAV（WALK0016／OPEN0001／MOVE0001）由 `tools/hsltools/assets/town_assets.py` 导入 `town_sounds/`，`TownRuntime._play_sound` 当场播放 |
| teDeletePlayerMessage 6／teDeleteShapeMessage 8 | 把对应消息标志清零 | 只记录（每句已等确认关板） |

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
`actSetTownExitExecEvent`、`actBM*`、`actSetBMWalkToPoint`），参数形状与 te 版相同，走同一套状态改写；`actSetBMWalkerPlayerID` 只记录。

### static-derived：初始菜单树

TOWNDEF 没有城镇归属字段；EXE 的初始树由 `0x454a20` 逐项建立（[original_world_town](original_world_town.md)），执行结果与本表一致。生成规则保留为推导记录：`content/world/town_initial_trees.json` 按以下规则生成，每条 entry 带 `source`：

1. 段头注释里的城镇名归类（如「歐姆村武器店」）；酒館类子项按注释前缀嵌套（「米蘭多酒館老闆」→ 7）。注释不是引擎数据 → provisional。
2. 排除运行时才出现的节点：TOWNDEF 的 teAddSelfTE／teAddTE 与 PAK 全部 STORY／winfail 的 actAddTE 所加的 children（num=0 时为节点本身）、
   以及只经 teExecEvent／teSetExecEvent／teSetTownExecEvent／select／check 跳转到达的事件（引用本身 resource-derived）。
3. 商店事件（teCreateShop）全部由脚本加入的城镇初始为空（薛維斯港、兩棲族部落、瑪哈亞鎮、沙羅尼亞、斐達克、戈黎塔尼港、亞雷比斯）；
   其中没有任何脚本加入的候选（50、145、150–156 等）记入 `excluded`，不放树（死数据或 EXE 侧默认，未证）。
4. 仅作为 AddTE(num>0) 的 parent 出现且无候选子项的子菜单（命運神殿大廳／港口／神殿中樞、克里夫的家）视为脚本保证节点。

结果：歐姆村 `{0:[1,2,3]}`、米蘭多 `{0:[4,5,6,7], 7:[8,12,13,14]}`、席達鎮 `{0:[16,17,18,20], 20:[21,22,23]}`，其余 9 镇为空树；
`unassigned` 记录无城镇归属的 13 条（酒館神秘男子 113–122、克里夫二 137、152、191）。替换证据：EXE 初始 TE 表或原作各镇首次菜单的有界采样。

## 重制接线

### 重制：执行模型（provisional）

替换证据：hsl01.exe 城镇脚本 VM（te dispatcher）的静态分析，或原作单镇菜单的有界单步采样。不支持的结论：原版是否有帧栈、
菜单是否在子项后重开、条件失败是否退回菜单、离开城镇的时机——以下每行只描述解释器当前行为。

| 项 | 读法 | 依据／替换证据 |
| --- | --- | --- |
| run／frame | `begin_event` 建立帧栈逐 token 执行；`resume(run, choice)` 处理 pending | 重制模型；替换证据为 EXE 城镇脚本 VM |
| teExecEvent | 跳转：替换当前帧 | TOWNDEF 19 处全部为事件末 token，跳转与调用不可区分 |
| teSelectInsertEvent／tePlayerSelectInsertEvent | pending `select`／`player_select`；选项事件作为插入帧运行，结束后回到父链 | 20 处全部为末 token；两种都开对象 704 选择窗（`0x4264a0`），tePlayerSelect 只列 `0x42caa0` 判为在队、且 `[mode]` 1／2 按成员 `+0x134` 转职位通过的成员（至多 9 行），再追加「離開」行（event −1 结束事件）（static-derived，[original_world_town 实录](../runtime_observations/original_world_town/README.md)「select 选择窗」「tePlayerSelect 名单过滤」）；重制照做 |
| teCreateSubEventMenu | pending `sub_menu`，子项＝树中该事件的 children；每个子项结束后重开菜单，`exit` 或 teMenuMoveOut 后越过该 token | 13 处；重开行为为重制读法 |
| teMenuMoveOut | 标记最近的打开菜单在当前链结束时关闭 | 仅事件 96 使用 |
| 条件失败 | 只中止当前帧（回到父菜单） | 重制读法 |
| teSetNextPlayLevelEvent | 记录 `next_level_event` 并结束 run（离开城镇） | 6 处全部为末 token |
| 尾帧消除 | 插入帧前弹出已执行完且非菜单的帧 | 使 命運神殿 儀式 71→61→71 数据环不增长栈 |

### 重制：解释器读法字符串

解释器读法原文集中在这里；代码只保留 token 表 `TownEventRules.PACKET_READING_TOKENS`，每条执行记录的 `provisional` 字段存引用 `town_event_semantics:<te token>`（act* 双胞胎按其 te 名查表）。evidence 列取自原句开头的层级词：`static-derived` 只覆盖句中给出地址的部分，句内标 provisional 的部分与不带地址的整句都是重制读法。与上表冲突处（teCheckJobUp／teCheckJobUp2）以本表为准，转职链的地址证据见[原作城镇转职](original_town_job_up.md)。

| te token | evidence | 读法（原文） |
| --- | --- | --- |
| teAddSelfTE | provisional | AddTE `[parent][num][children]`: num = 0 appends the parent node itself to the root; num > 0 ensures the parent node (root if absent) and appends the children |
| teAddTE | provisional | AddTE `[parent][num][children]`: num = 0 appends the parent node itself to the root; num > 0 ensures the parent node (root if absent) and appends the children |
| teDeleteSelfTE | provisional | DeleteTE `[parent][num][children]`: num = 0 removes the parent node and its subtree; num > 0 removes the listed children |
| teDeleteTE | provisional | DeleteTE `[parent][num][children]`: num = 0 removes the parent node and its subtree; num > 0 removes the listed children |
| teExecEvent | provisional | jump: the current frame is replaced (every TOWNDEF use is the last token) |
| teSelectInsertEvent | provisional | the chosen event runs as an inserted frame; the parent continues afterwards (every TOWNDEF use is the last token) |
| tePlayerSelectInsertEvent | provisional | options record every candidate with in_party; `listed` keeps the in-party ones whose job_up_flags pass mode 1／2 (0x4557ad), at most nine; the runtime lists those plus the 離開 row (event −1 ends the event) |
| teCreateShop | provisional | shop goods = the owning town_event's item_code list; buying/selling is the caller's transaction |
| teCreateSubEventMenu | provisional | children = tree[this event]; the menu re-opens after each child until exit or teMenuMoveOut |
| teMenuMoveOut | provisional | closes the enclosing sub-menu once the current chain ends |
| teCheckMoney | static-derived | static-derived (0x4555a5/0x455627): sufficient gold is deducted at once and the event continues; insufficient gold deducts nothing, shows the shape message and ends the event (VM return 1) |
| teCheckPlayerExist | static-derived | static-derived (0x454e20): this VM only advances past the opcode — no check, no argument read |
| teCheckItemExist | static-derived | static-derived (0x454e20): this VM only advances past the opcode — no check, no argument read |
| teCheckItemExecEvent | static-derived | static-derived (0x454cd0): item found in a party member's slots → delete one when [delete] != 0, then jump when [event] != 0 (event 0 continues); absent: continue |
| teCheckTEExist | static-derived | static-derived (0x455db7/0x4546c0): child present under parent → jump when [event id] != 0, end the event when it is 0; absent: continue |
| teCheckJobUp | static-derived | static-derived (0x454e20 case 0x1f / 0x434770 / 0x4348f0): member in party with a non-zero job-up code and str/dex/mind/con each >= job cap - 50 → merge the target PLAYERS row into the carry member (flag 0x80000000) and show 「<name>的稱號由<old>變成<new>」; otherwise the fail message as the member's face message, then fail event -1 ends the event and a valid event id jumps |
| teCheckJobUp2 | static-derived; provisional | static-derived (0x454e20 case 0x20): same condition and merge with flag 0x40000000; afterwards 0x434680 applies the 兩棲族部落 writes once both 雷歐納德 and 緹娜 have job-up code 0 (provisional: resulting menu not observed natively) |
| teSecretManBuyThing | static-derived | static-derived (0x454e20 case 0x27, original_secret_man.md): row = secret_man_goods[secret_man_index]; gold < price → face message [fail msg] then jump to [fail event] (0 continues); else deduct, grant items[rand(n)] (positional over the non-zero slots) like teGetItem, counter += 1 while < 8 |
| teGetGold | provisional | bit 31 of [number] is the display flag, the low 31 bits the amount |
| teSetNextPlayLevelEvent | provisional | ends the run (leaving town); the caller consumes next_level_event |
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
| 子菜单重开／退出 | 每个子项后是否回到菜单、如何退出 | 菜单 handler 或原作单步采样 |
| 消息 if_wait 位 | 消息都等关板、teDelay N＝N+1 tick 已读；if_wait 位 `0x2000` 在消息对象里的作用未读 | 消息对象过程读 `+0x80 & 0x2000` 的分支 |
