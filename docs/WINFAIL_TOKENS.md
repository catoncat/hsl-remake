# winfail 脚本 token 表

_由 `python3 tools/hsl.py generate winfail_token_table` 从 `game/sim/WinfailCompiler.gd` 的词表常量生成；`hsl check winfail_token_table` 在门禁内逐字节核对。不要手改本文件——改 token 行尾的 `# 语义` 注释后重生成。_

每场战斗 seed 的 `scripts.winfail` 由 win／fail／event 三类 status 组成，每个 status 是**前导条件链**（全部成立才触发，触发后从武装列表移除）接**结果动作链**。本表列出解释器认识的全部 token：

- **参数**：原版 `ACTION.H` 的形状注释（resource-derived；`[code][serial]` 指 `SID_*` actor token 与其序号）。
- **语义**：重制解释器当前的读法（测试合同 `tests/run_winfail_rules_tests.gd`，不是原版等价声明；边界见 [winfail_claim_limits](evidence_packets/static_reverse/winfail_claim_limits.md)）。
- **出现**：原版 PAK 全部 130 个 winfail 脚本中的出现次数（[winfail_token_coverage.json](../content/generated/hsl/static/hsl01/winfail_token_coverage.json)）。

不在本表的 token 会被编译为 `unsupported`：以它开头的 status 永不触发，结果链里遇到它记入 `unsupported_encountered` 后继续。模块分工见 [BATTLE_SYSTEMS](architecture/BATTLE_SYSTEMS.md#winfailscenariorulesgd)。

## 条件（`SUPPORTED_CONDITIONS`，19 个）

status 的前导条件链；全部成立才触发（WinfailConditions.condition_holds）。

| token | 参数（ACTION.H） | 语义（重制读法） | 出现 |
| --- | --- | --- | ---: |
| `actCheckPlayer` | `[num][id1][id2][...]` | 所列 id 中至少 num 个不再在场；已绑定但本战未上场的不计，无法解析的 token 永不计 | 153 |
| `actCheckRoundNumber` | `[num]` | 当前回合 ≥ num | 68 |
| `actCheckEnemyTotalNumber` | `[num]` | 在场敌军总数 ≤ num | 109 |
| `actCheckEnemyNumber` | `[code][num]` | code 的在场数（含场景声明的静态敌物件）< num；token 无法解析则不成立 | 20 |
| `actCheckPlayerArrivePos` | `[player code][serial][x1][y1][x2][y2]` | code／serial 指定的在场单位站在像素矩形 (x1,y1)-(x2,y2) 覆盖的任一格 | 54 |
| `actCheckPlayerAttacked` | `[attack player id][attacked player id]` | 仅攻击行动的完成扫描：本行动攻击者属 attack id（-1＝任意）、受击者之一属 attacked id | 34 |
| `actCheckSerialPlayerAttacked` | `[attacked player id][serial]` | 仅攻击行动的完成扫描：受击者之一是 id／serial 指定的单位 | 30 |
| `actCheckNotPlayerAttacker` | `[player id]` | 完成扫描：本行动攻击者不属于 id（未攻击的行动也成立） | 1 |
| `actFALSE` | — | 永不成立；以它开头的 status 永不触发 | 1 |
| `actCheckEnemy` | `[num][id1][id2][...]` | 与 actCheckPlayer 同一计数：所列 id 至少 num 个不再在场 | 25 |
| `actCheckPlayerHPLow` | `[code][serial][ratio(%)]` | code／serial 指定单位 hp ≤ max(1, max_hp×ratio÷100)（截断）；已倒下按 hp 0；ratio 0 即 hp ≤ 1（不死身复活后的 1 HP 成立） | 23 |
| `actCheckEventNotExist` | `[num][event1][event2][...]` | 所列 event 编号目前都未武装；在结果链中间（WINFAIL037／080 的全部 32 处）作闸门：有一个仍武装即中止该链余下动作 | 32 |
| `actTRUE` | — | 恒成立；无条件结果链，status 一武装即触发 | 50 |
| `actCheckPlayerTotalNumber` | `[num]` | 在场我方（受控＋友军）总数 ≤ num | 5 |
| `actCheckAnyPlayerArrivePos` | `[x1][y1][x2][y2]` | 任一在场我方单位站在像素矩形覆盖的格 | 3 |
| `actCheckNextSerialNumber` | `[num]` | 行动计数 0x4c1ad4 的定时器：截止字 0x4c1ad6 为 0 时置为计数＋num，计数到截止成立并清零 | 1 |
| `actCheckPlayerArriveSysPos` | `[player code][serial]` | code／serial 指定单位站在 actRandomSetSysArrivePos 抽中的系统到达点 | 5 |
| `actCheckRoundDisp` | `[number]` | 基线字 0x4c1bbe 为 0 时首次求值置为回合＋num；回合 ≥ 基线成立并清零 | 2 |
| `actDetectRoundDispDisp` | `[num]` | 回合 ≥ 基线字＋num（不写基线；基线未设即绝对回合） | 1 |

## 动作（`APPLIED_ACTIONS`，47 个）

结果链里改 loop 或写 PlayLoop 消费记录的 token（WinfailActions.apply_actions）。

| token | 参数（ACTION.H） | 语义（重制读法） | 出现 |
| --- | --- | --- | ---: |
| `actMessage` | `[player code][serial][message code]` | 推入一句对白（actor token、message id），同 status 内按 id 去重 | 580 |
| `actMessageIfExist` | `[player code][serial][(true)message id][(false)message id 2][check number][ check player code list ...]` | 前 check number 个 code 有一个还有在场单位就推 true id，否则（含 check number 为 0）推 false id；选中的是 0 或空不推 | 21 |
| `actGetItem` | `[item id][number]` | 向受控角色的队伍背包放入 number 个 item id；无效或背包满则 scenario_error | 10 |
| `actInsertObject` | `[code][x][y]` | 请求在像素 (x,y) 插入 code 对应的增援；class 由 script_objects obj_Data7 决定 | 372 |
| `actInsertObjectRandomPos` | `[code][disp x][disp y][pos id]` | 随机槽 pos id 的锚点加位移所在格插入增援，不抽随机数（0x450f2c） | 1 |
| `actInsertStoryObjectRandomPos` | `[code][disp x][disp y][pos id]` | 同 actInsertObjectRandomPos，剧情物件版 | 4 |
| `actInsertRandomObject` | `same as effInsertRandomObject` | 参数 code／slot／w／h／delay／count：每个对象在全局流抽 w、h、delay 三次（0x450f99），只记 presentation 请求 | 10 |
| `actDeleteRandomPosObject` | `[id][range][proc code]` | 站在随机槽 id 锚点格上的单位离场（object_delete_requests） | 1 |
| `actSetPlayerPosToRandom0` | `[player id][serial]` | 以 player id／serial 单位的当前位置作为随机槽 0 的锚点 | 13 |
| `actWalkPrevInsertObject` | `[x][y][speed]` | 编译期折进上一条 insert：落点 (x,y) 整除 cell_size 为 walk_cell，附速度 | 154 |
| `actWalkPrevInsertObjectWait` | `[x][y][speed]` | 同 actWalkPrevInsertObject，等待版 | 148 |
| `actSetPrevInsertObjectWaitRound` | `[num]` | 上一名增援的等待回合数，按动作顺序覆盖编译期折叠值 | 55 |
| `actSetPrevInsertObjectAdjustLevel` | `[range][disp range]` | 编译期折进 insert：增援等级调整（range／disp range） | 10 |
| `actSetPrevInsertObjectFly` | `[mode]` | 编译期折进 insert：增援飞行模式 | 20 |
| `actSetPrevInsertObjectST` | `[st]` | 编译期折进 insert：增援体力 | 3 |
| `actSetPrevInsertObjectEquip` | `[id][part, 0=weapon, 1=armor, 2=head, 3=foot, 4=other1, 5=other2]` | 编译期折进 insert：增援装备（id／part） | 0 |
| `actInsertEventStatus` | `[code]` | 武装 event 编号 code | 211 |
| `actDeleteEventStatus` | `[code]` | 撤下 event 编号 code | 141 |
| `actInsertWinStatus` | `[code]` | 武装 win 编号 code | 44 |
| `actInsertFailStatus` | `[code]` | 武装 fail 编号 code | 12 |
| `actDeleteFailStatus` | `[code]` | 撤下 fail 编号 code | 15 |
| `actDeleteWinStatus` | `[code]` | 撤下 win 编号 code | 1 |
| `actExecWinFailProcess` | — | 链结束后同一扫描再扫一轮（仍只启动一个 event），上限 MAX_PASSES | 180 |
| `actSetNextPlayLevelEvent` | `[level][event]` | 写 next_level_event=[level, event]（gameBigMapLevel=49）并记触发 status | 133 |
| `actDeletePlayerCode` | `[id][mode]` | 记 deleted_player_codes（id、mode、解析到的单位）供 carry 注销 | 2 |
| `actKeepPlayerST` | — | 记 carry_requests keep_stamina：下一次进关保留余气（CampaignCarryRules） | 5 |
| `actSetPlayerMode` | `[code][serial][mode][flag], mode = pmPlayer, ....` | code／serial 单位阵营改为 mode：pmPlayer／pmEnemy／pmNPCPlayer／pmNPCEnemy | 69 |
| `actSetPlayerExecMode` | `[code][serial][mode], = 0 player` | 写单位 player_exec_mode；0 对应原生状态 3，其余 5 | 4 |
| `actPlayerJobUpProcess` | `[player id][serial]` | 按 job_up_targets／templates 对 player id／serial 单位执行原生转职并刷新成长 | 1 |
| `actRandomSetSysArrivePos` | `[num][x1][y1][x2][y2][...]` | 从 num 对 (x,y) 中以全局流 rand(num) 抽一个系统到达点，对齐 32 像素 | 1 |
| `actSetPlayerUndead` | `[code][serial][mode]` | 写单位 undead 标记，mode≠0 为开 | 21 |
| `actSetPlayerFixPos` | `[code][serial][x][y][distance]` | 写 code／serial 单位的守备锚点 ai_home_coord＝(x,y)/32，distance≠0 时写 ai_fixed_radius；单位不瞬移，由固定点行走自己走去（锚点可在图外＝撤退点） | 34 |
| `actSetPlayerFly` | `[code][serial][mode]` | 写单位 traversal.flying，mode≠0 为开 | 8 |
| `actChangePrevInsertObjectID` | `[id]` | 改上一条 insert 的 object_id；尚无 insert 时记 previous_insert_object_id | 7 |
| `actWaitPlayer` | `[player id][serial]` | 记 wait_requests wait_player：player id／serial 单位（含离场中的） | 22 |
| `actSetWaitRound` | `[code][serial][num]` | 记 wait_requests wait_round：code／serial 单位或同 class 未落地 insert 等 num 回合 | 12 |
| `actDeleteObject` | `[code][serial]` | code／serial 解析为单位 id，记 departure_requests／departed_unit_ids；离场由 PlayLoop 执行 | 91 |
| `actDeletePosObject` | `[x][y][range][proc code]` | 按绝对像素 (x,y)、range、proc code 记 object_delete_requests；表现镜像，不改名册 | 12 |
| `actWalkAndDelete` | `[player code][serial][x][y][speed]` | 同 actDeleteObject，另记 presentation 走位请求 | 68 |
| `actWalkAndDeleteWait` | `[player code][serial][x][y][speed]` | 同 actWalkAndDelete，等待版 | 27 |
| `actSetDeadMessage` | `[code][serial][msg1][msg2]` | 写目标单位的死亡台词字 dead_message（code／serial，msg1<<16|msg2；同链插入的目标由 ScriptActorCreationRules 回放时写）并记 dead_messages[code]=msg1（记录，结果页不再复述：原版两个读者都在死亡时由死者说出） | 21 |
| `actUseItem` | `[code][serial][item id]` | code／serial 单位对自身使用背包内的 item id（ItemResolutionRules） | 11 |
| `actInsertStoryObjectWaitPos` | `[code][pos number][x1][y1][x2][y2]...` | pos number 组 (x,y) 中以全局流 rand(number) 抽一点（0x451ecf），记 story_object_wait_requests；defProcPoisonGas 对象当场喷毒（PoisonGasRules） | 1 |
| `actInsertStoryObjectXRange` | `[code][x][y][x number]` | 自 (x,y) 起横向 x number 格，记 story_object_x_range_requests | 10 |
| `actDeletePosPlayerXRange` | `[x][y][x number][proc code]` | 自 (x,y) 起横向 x number 格上、属 proc code 阵营的在场单位离场 | 20 |
| `actSetPlayerNoAttack` | `[player id][serial][mode]` | 写单位 no_attack，mode≠0 为开 | 2 |
| `actSetPlayerWalkShape` | `[player id][serial]` | 写单位 walk_shape_serial 并记 walk_shape_changes／presentation 请求 | 30 |

## 世界旗标（`WORLD_FLAG_ACTIONS`，17 个）

只记 winfail_runtime.pending_world_flags，交接时 WorldScriptActions 按 TownEventRules 读法执行。

| token | 参数（ACTION.H） | 语义（重制读法） | 出现 |
| --- | --- | --- | ---: |
| `actAddTE` | `[town id][parent][num][child1][...]` | 城镇 town id 的事件树在 parent 下加 child 节点 | 39 |
| `actDeleteTE` | `[town id][parent][num][child1][...]` | 城镇 town id 的事件树删除 child 节点 | 15 |
| `actSetTownExecEvent` | `[id][event]` | 城镇 id 进城即执行 event | 10 |
| `actSetTownExitExecEvent` | `[id][event]` | 城镇 id 出城执行 event | 1 |
| `actBMSetPointMode` | `[id][mode], mode = gameBMShowHidden, gameBMShowSlow, gameBMShow` | 大地图点 id 的显示模式（gameBMShowHidden／Slow／Show） | 0 |
| `actBMSetTrackMode` | `[id][mode]` | 大地图路线 id 的显示模式 | 0 |
| `actBMSetPointFlag` | `[id][flag]` | 大地图点 id 置 flag | 6 |
| `actBMSetTrackFlag` | `[id][flag]` | 大地图路线 id 置 flag | 4 |
| `actBMClearPointFlag` | `[id][flag]` | 大地图点 id 清 flag | 9 |
| `actBMClearTrackFlag` | `[id][flag]` | 大地图路线 id 清 flag | 8 |
| `actBMSetPointEvent` | `[id][event][flag], flag = bmpmVisit, bmpmTown, bmpmGeneral, bmpmBattle` | 大地图点 id 绑定 event 与类型 flag（visit／town／general／battle） | 43 |
| `actBMSetPointEncounterRatio` | `[id][ratio]` | 大地图点 id 的遭遇率 | 37 |
| `actBMSetShowTrackPoint` | `[id]` | 显示路线端点 id | 1 |
| `actSetBMWalkToPoint` | `[from point id][point id]` | 大地图队伍从 from point 走到 point | 4 |
| `actSetBMWalkerPlayerID` | `[player id]` | 大地图行走者改用 player id 的形象 | 1 |
| `actAddOverScore` | `[id][score]` | 结局分派：id 的 over score 加 score | 10 |
| `actSetOverFlag` | `[flag], flag = gameoverflagFreeEnemy, gameoverflagEnemyJobUp` | 结局分派：置 over flag（gameoverflagFreeEnemy／EnemyJobUp） | 2 |

## 演出（`PRESENTATION_ACTIONS`，36 个）

只记 winfail_runtime.presentation_requests，由演出协调器消费；规则不等待、不走位、不播放。

| token | 参数（ACTION.H） | 语义（重制读法） | 出现 |
| --- | --- | --- | ---: |
| `actDelay` | `[delay counter]` | 演出停顿 delay counter | 1191 |
| `actWalk` | `[player code][serial][x][y][speed] speed = 0(default), 1, 2, 4(default), 8, 16` | code／serial 走到像素 (x,y) | 35 |
| `actWalkWait` | `[player code][serial][x][y][speed]` | 同 actWalk，等待走完 | 13 |
| `actWalkDisp` | `[player code][serial][x disp][y disp][speed]` | code／serial 相对位移走位 | 26 |
| `actWalkDispWait` | `[player code][serial][x disp][y disp][speed]` | 同 actWalkDisp，等待走完 | 24 |
| `actMoveDispWait` | `[code][serial][disp x][disp y][speed]` | code／serial 相对位移瞬移，等待 | 1 |
| `actShowSectionName` | `[section level code]` | 显示章节名 section level code | 1 |
| `actSelectInsertEvent` | `[id][serial][num, max = 8][msg id 1][event 1][msg id 2][event 2][....]` | 二至八选一提示；所选 event 由 select_event_status 插入同一循环 | 1 |
| `actWalkToPlayerDisp` | `[code][serial][code][serial][xdisp][ydisp][speed]` | code／serial 走到另一单位旁的相对位移 | 0 |
| `actWalkToPlayerDispWait` | `[code][serial][code][serial][xdisp][ydisp][speed]` | 同 actWalkToPlayerDisp，等待走完 | 3 |
| `actScrollBGToPos` | `[x][y]` | 镜头滚到像素 (x,y) | 59 |
| `actScrollBGToObject` | `[code][serial]` | 镜头滚到 code／serial 单位 | 40 |
| `actScrollBGToPosSpeed` | `[x][y][speed]` | 镜头按 speed 滚到像素 (x,y) | 3 |
| `actSetBGToObject` | `[code][serial]` | 镜头直接对准 code／serial 单位 | 0 |
| `actSetBGToPos` | `[x][y]` | 镜头直接对准像素 (x,y) | 0 |
| `actPlaySound` | `[sound code]` | 播放音效 sound code | 57 |
| `actPlayMusic` | `[track id]` | 播放乐曲 track id | 0 |
| `actPlayLevelMusic` | — | 恢复本关配乐 | 1 |
| `actChangeShape` | `[player code][serial][shape delay][shape name][shape number]` | code／serial 换形象 shape name／number | 2 |
| `actChangeShapeWait` | `[player code][serial][shape delay][shape name][shape number]` | 同 actChangeShape，等待 | 0 |
| `actRestoreShape` | `[player code][serial]` | code／serial 恢复原形象 | 42 |
| `actSetUseShapeWait` | `[code][serial]` | code／serial 播放使用形象并等待 | 1 |
| `actShowWinFailStatus` | — | 显示胜负条件看板 | 25 |
| `actInsertStoryObject` | `[code][x][y]` | 在像素 (x,y) 插入剧情物件 code（演员由 ScriptActorCreationRules 建） | 127 |
| `actInsertStoryObjectWait` | `[code][x][y]` | 同 actInsertStoryObject，等待；defProcDropLightn 对象当场落雷（DropLightningRules） | 1 |
| `actInsertShowPosObject` | `[x][y]` | 在像素 (x,y) 显示位置标记 | 76 |
| `actDeleteShowPosObject` | — | 删除位置标记 | 8 |
| `actDarkScreen` | — | 画面变暗 | 3 |
| `actDeleteDarkScreen` | — | 撤销变暗 | 0 |
| `actEarthQuake` | `[delay]` | 地震抖屏 delay | 6 |
| `actSetWalkSoundMode` | `[mode]` | 走位脚步声模式 | 4 |
| `actWaitPrevInsertPlayer` | — | 等待上一名插入的剧情角色就位 | 8 |
| `actEnterStorageWindow` | — | 进入仓库窗口 | 2 |
| `actSetDoublePageMode` | `[mode]` | 双页对话模式 mode | 2 |
| `actInsertLevelUpStar` | `[sound id]` | 升级星光特效与音效 sound id（记 level_up_star_requests） | 9 |
| `actPlayMovie` | `[over delay]` | 播放影片；140 为结局影片（记 movie_requests） | 1 |
