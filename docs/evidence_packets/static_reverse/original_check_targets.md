# 脚本条件 actCheckEnemy／actCheckPlayer／actCheckEnemyNumber 的目标计数、全灭判负与 winfail 台词的脸

> evidence: static-derived; negative-evidence: 非脚本全灭判负; provisional: 重制 carry 模型 · status: live · functions: 0x407299, 0x4072b0, 0x407720, 0x4080b0, 0x4145b4, 0x42c700, 0x42caf0, 0x42cbd0, 0x44ecb0, 0x44ee20, 0x44fa80, 0x44fad0, 0x44fb90, 0x450840, 0x453a80, 0x453ac0 · tools: hsltools/levels/battle.py, hsltools/probes/check_player.py, run_autoplay_sweep_tests.gd, run_battle_sweep_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-27

## 结论

- 原版 `actCheckEnemy`／`actCheckPlayer`（case 0x23／0x26）在所列 id 全部经 `0x44fad0(code,1)` 找不到时成立——已删除、已阵亡出表与从未插入不可区分；`actCheckEnemyNumber` 是登记数严格小于 num；原版没有非脚本的全灭判负（static-derived，含有界原生执行；negative-evidence）。
- 重制 `game/sim/WinfailConditions.gd` `condition_holds` 照此计数，遭遇战组装器把 `SID_雷歐納德` 等名字 token 绑定到上场单位；另有两条重制规则：绑定存在而本战无该单位时不计入、全队阵亡判负（`PARTY_WIPE_POLICY = remake_party_wipe_defeat_v1`）。
- 差异：两条重制规则补偿的是 carry 模型与原版注册表的差异，不是原版等价（provisional，差异清单 `carry-model`）。

## 证据

原 EXE `hsl01.exe` sha256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。

### resource-derived：触发案例

WINFAIL533（bigmap 点 24 的随机遭遇战）win 0 为 `actCheckEnemy 6 SID_ENEMY024 SID_ENEMY030 SID_ENEMY031 SID_ENEMY027 SID_ENEMY044 SID_ENEMY049`，而 level 533 的 EVEF 只放置 030／031／044／049，STORY533 也不插入任何敌人。重制解释器此前把“所列单位已阵亡”读成“每个 token 至少解析到一个单位且全部阵亡”，解析为空的 token 直接跳过不计，于是 533 永远凑不满 6 个，强制胜利扫描报 `force-win reaches a victory result page (outcome )`。需要确认原作对**从未存在**的 id 如何计数。

### static-derived：`actCheckEnemy`／`actCheckPlayer`（case 0x23／0x26）

`ACTION.H`：`actCheckEnemy 35 // [num][id1][id2][...]`、`actCheckPlayer 38 // [num][id1][id2][...]`。story／winfail 解释器 `0x450840`（已登记 `script_interpreter_bridge`）的 switch 把 35 与 38 合并处理（反编译 `case 0x23: case 0x26:`）：

```c
uVar13 = *puVar16;              // [num]
puVar17 = puVar16 + 1;          // [id1]...
count = 0;
if (0 < uVar13) {
    do {
        iVar11 = fcn.0044fad0(*puVar17, 1);   // lookup_registered_actor_by_code_and_serial(code, 1)
        if (iVar11 != -1) count++;            // 仍能找到 → 该 id 在场
        puVar17++; uVar13--;
    } while (uVar13 != 0);
    if (count != 0) {
        *(obj + 0x90) = puVar16 - 1;          // 任一 id 在场：pc 退回本 opcode，下轮再判
        return 0;
    }
}
goto code_r0x004527a0;                        // 无一在场：条件成立，继续本 status 后续动作
```

`fcn.0044fad0(code, serial)`（已登记 `lookup_registered_actor_by_code_and_serial`）遍历对象槽表 `0x4c34c0..0x4c37df`，只看非空槽；对每个 code 相同的登记对象递减 serial，命中则返回槽号；扫完没有任何同 code 对象时返回 `-1`。因此：

- 条件成立的判据是**所列 id 全部找不到**，与 `[num]` 是否等于 id 数无关（`[num]` 只决定消费几个参数）。
- 已被删除、已阵亡出表或**从未插入**的 code 都返回 `-1`，三者在这个 opcode 下无法区分，都计为“不在场”。
- 每个 id 只查 serial 1 的存在性；但同 code 的任一实例都会让 serial-1 查找命中（递减计数只在有同 code 对象时发生），所以等价于“该 code 无任一在场实例”。

所列 id 无一仍在场即成立；从未放置的 class 视为已阵亡。原作靠 `actInsertWinStatus` 的时机而不是靠“存在计数”阻止提前胜利——例如 WINFAIL007 win 0 列出 023／024／036／037／038，其中 023／024 在 event 1（第 5 回合）才插入，而 win 0 到 event 2（第 6 回合）才 `actInsertWinStatus 0`。

### static-derived：actCheckEnemyNumber／actCheckEnemyTotalNumber 的比较方向

同一 `0x450840` 反编译。`ACTION.H`：`actCheckEnemyNumber 36 // [code][num]`、`actCheckEnemyTotalNumber 37 // [num]`。条件 case 共用两个出口：`code_r0x004527a0` 置返回值 1 并把指令指针推过参数（条件成立、继续本 status 后续动作），`code_r0x004527c3` 保持返回值 0 并把指针退回本指令（条件不成立、下次再评估）。

- `case 0x24`（actCheckEnemyNumber）：`iVar11 = fcn.0044fb90(code)`；`if (num <= iVar11) goto code_r0x004527c3`。即 **registered_count(code) < num 才成立**（严格小于）。`0x44fb90` 遍历已登记对象表 `0x4c34c0..0x4c37e0`，对每个非空槽位以 `0x44fa80` 取对象 code 并与参数比较计数——计的是仍登记在表中的对象，与 HP 无关，被消灭而注销的对象不再计入。
- `case 0x25`（actCheckEnemyTotalNumber）：`if (num < *0x4c1b94) goto code_r0x004527c3`，即 **敌方总数 <= num 成立**（与既有重制读法一致）。

含义核对：WINFAIL010 event 7／8 为 `actCheckEnemyNumber SID_ENEMY034,1`／`SID_ENEMY035,1`（该兵种归零才触发）；WINFAIL026 fail 2 `SID_ENEMY101,26` 与 WINFAIL012 fail 2 `SID_ENEMY101,62` 对应 EVEF 恰好放置 26／62 枚 船殼（Enemy101，`defProcEnemy` 静态敌方对象）——"少于全部即失败"读作"任一船殼被破坏即失败"，而旧的 `<=` 读法会让这两关在武装后立即失败。

### resource-derived：遭遇战 fail 段的玩家名 token（SID_雷歐納德）

78 场遭遇战 501–578 的 fail 段全部是 `actCheckPlayer 1 SID_雷歐納德`（`content/generated/hsl/chapter01/battle5NN_seed.json` `scripts.winfail.sections[fail]`），而 `content/battles/battle_5NN.json` 的 `opening.actor_bindings` 为空，`WinfailScenarioRules.token_source` 对该 token 报 `unresolved` → 按上节读法不计 → 全队阵亡后 fail 永不成立，敌军无限行动（重制全量自动对局 `party_wiped_no_defeat`，runtime-measured）。

token 数值来源（resource-derived）：`DATA\EXTRAS.H`（导入为 `content/imported/hsl/global/tables/EXTRAS.H`，摘要 `content/imported/hsl/story_corpus/index.json extras_sid_defines`）定义九个受控槽 `SID_雷歐納德 0、SID_緹娜 1、SID_琥 2、SID_漢克斯 3、SID_雪拉 4、SID_雷特 5、SID_嚎 6、SID_咕嚕 7、SID_克羅蒂 8`；`SHAPEDEF.H` 的 `SID_PLAYER0..8` 同为 0..8。两组 define 对 `0x450840 case 0x26` 传给 `fcn.0044fad0(code, 1)` 的是同一个 code，原作里 `SID_雷歐納德` 与 `SID_PLAYER0` 没有区别；脚本文本用哪个拼写只是作者习惯（主线 WINFAIL0NN 同样写 `SID_雷歐納德`）。

### static-derived（有界原生执行）：-1 路径、全灭与 53 关对白脸

回执 [original_check_player_native.json](original_check_player_native.json)；任务 `python3 tools/hsl.py check check_player`（离线校验 tracked 回执，快门内）；复跑 `uv run --no-project --with 'unicorn>=2,<3' --python /opt/homebrew/bin/python3 python3 tools/hsl.py generate check_player --exe $HSL_ORIGINAL_DIR/hsl01.exe`（同一 EXE SHA 下重执行后回执逐字节相同）。执行方式：Unicorn x86-32、原字节、合成的对象槽表 `0x4c34c0`／角色记录 `*0x4c1bc8`／VM 对象，无 stub；越出白名单的 callee 直接报错。

#### 1. `actCheckPlayer 1 <找不到的 id>`：成立（-1 即不计入），且原作根本不会出现「已注册未上场」

**static-derived（有界执行 11 次 `0x44fad0`、7 次 `0x450840` case 0x26，全部正常返回）**：

| 布局 | `0x44fad0(code,1)` | case 0x26 返回／pc |
| --- | --- | --- |
| 槽表无该 code（从未上场／已注销） | -1 | **1，pc 越过 2＋num 个参数——条件成立** |
| 有该 code 的 kind-3 对象、HP=50 | 槽号 | 0，pc 退回本 opcode |
| 有该 code、HP=0 但未打死亡标 | 槽号 | 0——opcode **不读 HP** |
| 有该 code、对象 `+0x80` 带 `0x8000000` | -1 | 1——`0x44fa80` 先拒绝死亡标再取 code |
| 两个 id，其一在场 | — | 0（任一在场即不成立） |
| 两个 id 都不在 | — | 1，pc 越过 4 个参数 |
| 不在场但 `0x4c1b00` 带剧情阶段位 `0x4000000` | -1 | 0，pc 退回（剧情 VM 内的条件不当场消费） |

`0x8000000` 死亡标由三条伤害结算路径在目标 HP<=0 时立即写入（anchors `0x4415d4`／`0x441da5`／`0x44448d`），之后对象注销 `0x407720` 清槽并按阵营递减 `0x4c1b90`／`0x4c1b94`。所以「HP 归零」到「不在场」之间没有可观察的中间态；`0x44fad0` 的负 code：-1（`defAnyPlayer`）＝槽 0–19 中第一个非空、-2（`defAnyEnemy`）＝槽 20–199 中第一个非空、-3（`defNoOne`）恒 -4（永远「在场」）；serial 超过实例数返回最后一个同 code 槽而非 -1。

对 30–34 段的 5NN 遭遇这意味着什么（static-derived，anchors `0x4080b0`／`0x42caf0`／`0x42c700`）：`有才產生` 条件安装只问注册表 `0x4c4360[slot]` 是否非零且无 `0x80000000`（[原安装分支](original_player_install.md)）；注册表只被三处写——新游戏初始化 `0x42c869`（槽 0＝雷歐納德 写 800）、安装启用 `0x42cb47`、转职 `0x43493d`——**没有任何调用者写 `0x80000000` 禁用位**，清零只有 `actDeletePlayerCode`（opcode 71，`0x42caf0`）。全部剧本里它只出现两次：WINFAIL053 win 0（`SID_PLAYER1, 0`，序章 緹娜 离队）与 WINFAIL015 event 4（`SID_咕嚕, 1`）；STORY／WINFAIL 029–034 一次都没有（resource-derived，`content/imported/hsl/story_corpus/scripts/`）。因此原作在 31–32（雷歐納德 组）与 33–34（緹娜 组）的分队期间，八名已注册成员**全部**会被 5NN 的九个 `有才產生` 槽装进战场，`actCheckPlayer 1 SID_雷歐納德` 检查的是一个在场的 雷歐納德——「已注册但未上场」这个状态在原作的遭遇战里不可达，-1 路径只会在真正阵亡／注销后出现。

重制的落点：`WinfailConditions.condition_holds` 对 `binding` 且无单位的 token 跳过不计，是 remake rule：它补偿的是重制 carry 模型（carry 曾只含上一战上场的受控单位，[BATTLE_SYSTEMS](../../architecture/BATTLE_SYSTEMS.md#conditional-party-installs-random-encounters) 已声明「carry 代替注册且启用槽表，registered-but-disabled 未建模」）与原作注册表的差异，不是对 opcode 语义的另一种读法。若照 opcode 语义把未上场计为阵亡，重制会在原作不会败北的局面（原作此时 雷歐納德 在场）首回合判负，比原作更严。carry 现已照注册表传下未上场的已加入成员（[注册表与交接写回](original_campaign_actors.md#证据)），30–34 段的遭遇战因此装入 雷歐納德；这条规则只对 carry 之外的缺席者起作用。

#### 2. 全灭：原作没有非脚本判负（negative-evidence，有界执行 6 次 `0x44ecb0` 佐证）

判负入口的全部静态链（anchors）：每次评估 `0x44ee20` 依次跑 win 扫描 `0x44ebf0`、fail 扫描 `0x44ecb0`、event 扫描 `0x44ed70`（`*0x4c1d44` 脏标为 1 才评估，由 `0x407ec0` 关卡对象与 `0x453b30` 状态对象两处调用）；fail 扫描对每个已武装条目（code ≠ -1）调 `0x450840`，返回非零才 `code:=-1` 并调状态动作执行器 `0x453ac0(pc, 2, 0)`，其返回 0 时进 `0x453a80(2)` → `jmp 0x42cbd0`（`0x4c1b00 |= 0x88000000`，下一关／事件 999，转场 2）。`0x453a80(2)` 的调用者只有 fail 扫描 `0x44ed60` 与状态对象回调 `0x453b61`；`0x42cbd0` 的另一个同形函数 `0x42cb90` 只被系统菜单／读档失败路径调用。玩家计数 `0x4c1b90` 的读者共六处：清零 `0x407299`、注册递增 `0x4076fe`／`0x4079b6`、注销递减 `0x4077ea`、光标循环 `0x43a9ec`／`0x43aa17`（只判是否还有第二名玩家）、脚本 opcode `actCheckPlayerTotalNumber`（`0x4524de`，剧本里只在 WINFAIL030–033／038 的 event 段用作「全员撤离 → 判胜」）。回合调度 `0x407340`／`0x4074a0` 不看阵营，槽表少于两个对象只重置索引。

有界执行（fail 表 10 条 × 0xb4，`*0x4c1b50 = 0`，停在 `0x453ac0` 入口记录参数）：

| 布局 | 结果 |
| --- | --- |
| 无武装 fail、槽表无任何玩家 | 正常返回，**未调用任何函数**（80 条指令） |
| fail 0 = `actCheckPlayer 1 0`，雷歐納德 在场 | 正常返回，条目 code 保持 0，pc 退回 |
| 同上，雷歐納德 在场、其余两名玩家带死亡标 | 正常返回——只看所列 id |
| fail 0 武装，雷歐納德 不在场 | 停在 `0x453ac0(pc+3, 2, 0)`，条目 code := -1 |
| fail 0 武装，雷歐納德 不在、其余两名在场 | 同上判负——「在场人数」无关 |
| fail 1 武装、全部玩家带死亡标 | 停在 `0x453ac0`，entry=1 |

结论：原作在「上场玩家全部阵亡但脚本 fail 条件不成立」时**没有任何判负路径**，敌方会在回合调度中无限行动；原作靠剧本不变量避免这个局面（每关 fail 段检查的 id 都是该关上场的领队；5NN 检查 雷歐納德 而 雷歐納德 总在场）。重制 `party_wiped`／`PARTY_WIPE_POLICY` 因此不是原版等价，也不是 provisional 等待替换，而是**项目采纳的重制改善规则**，其触发条件（领队因 carry 缺席）本身就是重制独有的状态。

#### 3. 53 关 winfail 台词的脸

`actMessage`（case 0xa）把 code／serial 存到 VM `+0x98`／`+0x94`，phase 10 case 0 用 `0x44fad0(code, serial)` 取**对象槽号**后调 `0x4072b0(&vm+0x9c, slot, msg, 0)`；构造器把 `0x4c34c0[slot]`（说话对象本体）写进对白框 `+0xa8`、消息 id 写 `+0xac`（anchor `0x4072b0`）。对白框处理器（proc 表第 13 项 `0x414280`）初始化时 `面部字 +0xae := *0x4c1bc8[speaker+0xa4].+0x5c`（anchor `0x4145b4`），`+0x5c` 正是 PLAYERS.TXT `picture` 字段的落点（`0x44bdeb` 读 "picture" 写 `+0x5c`，转职 `0x4349dc` 只在新模板非零时覆盖）。WINFAIL053 的 `SID_PLAYER1,695／696` 于是取**说话对象自身记录**的 picture：53 关受控单位由 `obj_Story_Player2` 安装为槽 1＝源 002（`FACE0001.SHP`，[原安装分支](original_player_install.md)），029（jobWise、`FACE0029`）是 STORY053 走完即删除的过场公主，不是这个对象。重制「按说话对象自身 face」与原路径一致。未追：对白框旗标 `0x1000` 时改用预置面部字 `+0xaa` 的调用方（`actShapeMessage` 一类），与本问题无关。

## 重制接线

### 重制：目标计数

`game/sim/WinfailConditions.gd` `condition_holds`：token 的 `token_source` 为 `unresolved`（既非 `SID_ENEMYnnn` class、也无绑定或受控单位回落）时仍跳过不计，避免绑定缺口误判胜负；其余 token 只要没有存活单位即计入。已注册正式战斗中仅 533 的条件含从未放置的 class（024／027），level 7 的 023／024 因 win 0 延后武装而不受影响。

### 重制：比较方向

`WinfailConditions.condition_holds` 的 `actCheckEnemyNumber` 为 `registered < num`，其中 registered ＝ 该 token 的存活单位数（＋运行时 `winfail_runtime.static_enemy_counts[token]`，组装器已不再产生）。12／26 关 Enemy101 船殼、18 关 Enemy100 門、80 关 068 都是 PlayLoop 单位（读法见 [阵营位包](original_player_mode_sides.md#证据)），船殼被敌方普通攻击打倒即注销、计数下降——WINFAIL012／026 的「任一船殼被破坏即失败」由此可以发生（船殼共用一份 live 记录，HP 由 `SharedRecordRules` 并池）。歐姆村（level 1）由手写 `FirstBattleScenarioRules` 承接其 `actCheckEnemyNumber SID_ENEMY028,3`。

`0x44fa80` 取的 code 是角色记录字 `+0x84`，`actChangePrevInsertObjectID` 写同一字（[original_story_object_terrain](original_story_object_terrain.md)）；扫描时机见 [original_round_display](original_round_display.md)。

### 重制：名字 token 绑定

不在规则里再建第二条别名解析路径，而是让遭遇战组装器与主线走同一条数据路——`tools/hsltools/levels/battle.py build_encounter` 把每个已上场的 EVEF 有才產生 安装位（`obj_Data9` 槽 → `PARTY_SLOTS` 的 token／unit）写成 `opening.actor_bindings["SID_<名>/1"] = {unit_id, actor_id, placement_xy}`，与主线 `trace_opening` 对有才產生 安装的绑定形状一致；`token_source` 随即报 `binding`，`actCheckPlayer 1 SID_雷歐納德` 在 leonard 阵亡时成立（`defeat_leonard`），其余队员全灭不结束战斗（与脚本只列 slot 0 一致）。未上场的 `conditional_party.unavailable_slots` 不绑定（当前为空集）。单测 `run_winfail_rules_tests.gd _encounter_fail_resolves_player_name_token`（真实 `battle_571.json`），定向自动对局 571／558／525 由 `dead_end` 变 `outcome=fail battle_outcome=defeat_leonard`。

不在本读法内：原作对已登记但 disabled 槽位（未随队成员）的 `0x44fad0` 查找结果由 `conditional_party` 的 carry 读法代表，仍是那里标注的 provisional 边界。

### 重制：未上场成员与全队阵亡

剧情模式探索在 34 沙羅尼亞近郊（队伍 hu／tina／hanks／shera，雷歐納德 被囚不在 carry）后于地图点 33 掷中遭遇战 550：`SID_雷歐納德/1` 已绑定，但 `ConditionalPartyRules` 按 carry 未上场 leonard，若按上节读法「找不到即阵亡」则首次控制时立即 `defeat_leonard`。原 `big_map_flow.json` 显示 30–34 点遭遇比例 20／10／10／10／10 非零，原作确实会在雷歐納德缺席段触发 5NN 遭遇。静态读法本身没有歧义——`0x450840 case 0x26` 对 `fcn.0044fad0(code,1) == -1` 直接不计入 count，count==0 即成立；歧义在**原作是否把 registered-but-absent 的槽装进遭遇战**（`conditional_party.claim_limit` 已写明未建模）。两条接入：

1. **未上场 ≠ 阵亡**：`WinfailConditions.condition_holds` 的 `actCheckPlayer`／`actCheckEnemy` 对 `token_source == "binding"` 且 `units_for_token` 为空的 token（绑定存在、本战没有该单位）不计入 dead，与 unresolved 同样跳过；`SID_ENEMYnnn` class token 从未放置仍计入（WINFAIL533 读法不变）。下文有界执行确认原版此时 雷歐納德 在场，这条是补偿 carry 模型的重制规则。
2. **全队阵亡判负（重制显式规则）** `WinfailScenarioRules.party_wiped`／`PARTY_WIPE_POLICY = remake_party_wipe_defeat_v1`：脚本 fail 段、win 段都不成立时，本战上场且仍在场的 `player_controlled` 单位（不含 `departed`、`departed_unit_ids`，不含 friendly_ai）非空且全部 `defeated` → `DEFEAT_OUTCOME`；`commit_outcome` 记 `resolved = {key: party_wiped, kind: fail, code: -1, policy}`，不跑任何脚本 fail 链，`_terminal_status` 对该 resolution 返回空 status（不说缺席成员的死亡台词、无脚本看板标签），结果页走同一败北路径（`BattlePresentation` 主角未上场时标签「隊伍全滅」）。这是项目采纳的重制改善，不声称原版等价；效果是 autoplay 的 `party_wiped_no_defeat` 死路在任何战斗都结构性不可达。

覆盖：`run_winfail_rules_tests.gd _encounter_fail_resolves_player_name_token`（真实 571 ＋ 四人 carry：未上场不判负、全灭判负、脚本撤退不计、win 成立优先、无死亡台词／看板标签）；定向自动对局 `HSL_AUTOPLAY_PARTY=hu,tina,hanks,shera HSL_AUTOPLAY_LEVELS=543,546,549,550,552,555,556,557` 八场全部 `outcome=fail battle_outcome=defeat_leonard result_page=true`（4–7 回合被全灭，非首回合瞬败）。

## 复现

`python3 tools/hsl.py check check_player`（离线校验有界执行回执）；重制侧 `tools/godot.sh --headless --script res://tests/run_all.gd -- run_winfail_rules_tests.gd`

## 边界

- opcode 的执行时机见 original_round_display；`0x44fad0` 负 code 分支（-1／-2／-3）的调用方未逐一追。
- 已登记但禁用槽位在原版不可达（注册表没有写禁用位的调用者，见[原安装分支](original_player_install.md)）；`conditional_party` 的 carry 读法不需要代表它。
- 未上场不计入与全队阵亡判负是重制规则，不声称原版等价。
