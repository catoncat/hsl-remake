# 给予、交换与物品行动消耗

> evidence: static-derived · status: live · functions: 0x407800, 0x40f560, 0x411c40, 0x436e30, 0x436e80, 0x436ed0, 0x43b4e0 · tools: capture_give_review.gd, hsltools/evidence/give.py, run_give_exchange_tests.gd · updated: 2026-09-26

Checked: 2026-09-13。接续 [物品命令和窗口关闭](original_item_actions.md) 及 [八槽库存／装备](original_inventory_equipment.md)。机器证据为 [original_give_exchange.json](original_give_exchange.json)，复跑工具为 `tools/hsltools/evidence/give.py`。

## 来源及验证边界

原 EXE SHA-256：`f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。原 PAK 成员 `@:\data\obj-051.obs` SHA-256：`f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8`。该成员的 `obj_Data8` 将 Give 对象115连接到玩家 state6；它进入 state110 的物品选择，不能从菜单排列推断编号。

本包新增15段人工审阅的原指令字节和8个玩家状态分派核对；原 EXE 全文件哈希、这些字节、分派和原 PAK 均已实际检查。证据等级为 **static-derived**。没有新增原函数执行：前次库存 probe 创建曾被工具阻止，本次也有一条后续反汇编调用被阻止，未通过另一入口重试那条被拒绝操作。`native_execution=false`。机器包中的6组输入输出是独立 Python 模型的合成例子，Godot 与其比较不构成原函数执行或原版实玩证明。

已证八槽、首空插入 `0x436e30`、删除左移 `0x436e80` 与最后一格读取 `0x436ed0` 直接复用前包。角色对象 `+0xa4` 索引 `0x4c1bc8` 指向的 roster，stride 为 `0x1fc`；库存位于 actor `+0x138..+0x154`。0为空，每个重复 code 独占一格。本包不重新从 PLAYERS 的 item 字段数猜容量。

## 完整给予事务

| 阶段 | 入口／字段 | 已读行为 |
| --- | --- | --- |
| 打开给出方背包 | state110 `0x444b8a` → `0x43b4e0(mode7)` | mode7 根设置 `0x40005000`（`0x43ba0b`）；库存子对象设置 `0x5000`（`0x43ba97`） |
| 选取给出物品 | `0x438c53`、`0x438d63`、`0x438d8d` | 索引必须0..7；空源格无操作；选中 code 保存到暂持全局 `0x4c1ce4`，对所选源槽调用删除／压紧，关闭该选择窗口 |
| 选目标 | state113 `0x444c27`，`0x444c4e..0x444c99` | 需要 `0x40f560` 可达、格子 `0x411c40` 结果含 `0x10000`，以及 `0x407800` 返回非空对象 |
| 打开目标背包 | state114 `0x444d9c` | 将给出 code 保存到 `0x4c2c88`，使用 `0x4c1cec` 的目标对象打开同一 mode7；父对象仍为本次行动的给出方 |
| 选择接收槽 | `0x438c92` → `0x438cbf..0x438d0c` | Give 的 `0x1000` 位跳过普通库存的尾格判断。目标所选格非空时先取出该 code 作为新暂持物，删除／压紧，再把给出的物品插入目标首空格。选择空格则直接首空插入 |
| 关闭目标背包 | `0x438d0c..0x438d29` | mode7 一次选择完成后请求根窗口关闭；既有根对象关闭流程通知父对象继续 |
| 归还及继续给予 | state116 `0x444def..0x444e36` | 比较返回暂持 code 与 `0x4c2c88` 的给出 code；不同时将 `0x10000` 并入给出方 object+0x80。非零返回物通过首空插入归还给出方，清暂持，返回 state110，再次打开给出方背包 |
| 结束给予会话 | `0x444bff..0x444c22` | 若曾设置 `0x10000`，清位后进入 `0x4454a5` 公共行动结束；否则回 state3 物品子菜单。EBX=`0x10000` 的来源为 `0x443955` |

因此，目标背包满时可以选择一件物品交换，不应把整个目标禁用。目标有空位时也允许主动选择已占用格交换。取出目标物会压紧后续槽位，再把输入物放到首空位；不是直接覆盖所点槽。两边原来都满也能完成：先从给出方取物留下一个空位，接收方先取出交换物也留下一个空位，最后各自首空插入。

选择目标空槽时，真正插入的是**第一个空槽**，不是必须落在点击的那一个空槽。产品提供自动找空位参数 `target_index=-1, expected_return=0` 时，满包明确失败；它不会自动挑一件装备换走，只有显式选择交换格才交换。

## 重复物品、同 code 与取消

上述接收代码没有合并重复 code，也没有同 code 免写分支。因此同一种物品互换仍可能改变双方顺序。例如双方均为 `[241,246,0,0,0,0,0,0]`，互换各自第0格，结果均为 `[246,241,0,0,0,0,0,0]`。

行动判断只比较本次给出和返回的 code。正常给予返回0，不等于给出物，所以记为已使用；交换不同 code 也记为已使用；交换相同 code 不新增使用标记。原代码使用 OR，所以一次有效给予后再同 code 交换，不能清掉已有的使用标记。

目标选择取消 `0x444d3b..0x444d73` 会把暂持物首空归还给出方，清暂持，回 state110，不新增行动标记。mode7 根含 `0x1000`，由前包 `0x438835` 的关闭门禁可知它绕过普通 Equip/Drop 的“先放回本窗口所属角色背包”；留下的暂持物由父 Give 流程归还给出方。这避免把取消的输入物错误放进目标背包。

原版取消后的首空归还可能调整源槽顺序。当前重制采用确认前不取出物品：取消预览完整保留双方原顺序、当前角色、移动和行动状态。这是明确的重制交互。**取消下一次预览不撤销此前已经确认的给予／交换**；结束已有成功交易的会话仍消耗行动。请求版本号会增加以拒绝旧请求，它不是可消费行动或第二份库存。

## 统一物品行动矩阵

| 操作／结果 | 原版证据 | 当前规则／测试 |
| --- | --- | --- |
| Use 正常完成 | 前包 `0x444e3b`：state118→state4；本包核对 state4→`0x4454a5` | 正常成功使用结束角色行动。满值目标也能用并消耗一件；目标资格与消耗见 [物品命令包](original_item_actions.md)，不由这个完成分支证明 |
| Give 到空格 | receiver 返回0；`0x444def` 设置使用标记并回110 | 库存当次提交，仍可继续给予；明确结束会话时消费一次行动 |
| Give 交换不同 code | 同一比较置位／归还分支 | 目标满包或有空位均可交换，双方守恒；退出时消费一次行动 |
| Give 仅交换同 code | 比较相等不置位 | 顺序可改变；没有之前成功交易则退出后仍能行动 |
| Give 满包但未选交换、错误或失效选择 | 原 helper 无空位插入失败；产品额外校验准确请求 | 整笔拒绝，不改双方库存、会话使用标记和队列 |
| Give 取消未确认选择／退出空会话 | `0x444d3b` 回110，不置位；`0x444bff` 无使用标记回3 | 取消预览不改状态；退出空会话不消费行动 |
| Give 成功后取消下一次预览 | 使用标记为 OR，不被取消分支清除 | 保留已确认交易；最终退出仍结束角色行动 |
| Drop 正常成功、Equip 正常替换 | 前包根关闭→父76→77→3 | 免费，保留当前行动；已证保护与失败原子性保持 |
| 任一确认前取消或校验失败 | 原取消分支与各 helper gate；原子确认由重制实现 | 不扣物、不刷新一半属性、不耗行动；旧 signal／重复请求被视图身份及版本检查拒绝 |

后续公共行动 slice 已把原 `ItemActionRules` 合入 `ActionBudgetRules`，PlayLoop `_settle_action` 统一消费结果。Give 的 sticky code 比较、Use结束、免费Drop/Equip语义保持；新的攻击与移动撤销合同见 [公共矩阵](original_action_state_machine.md)。

## 目标与移动边界

给予目标：`0x444bc7` 以 `0x40f440(user, 1, 4)` 标记相邻一格，`0x40f520(0)` 清掉本人格；点击 `0x444c27` 要求格带标记且格字含 `0x10000`（pmPlayer），不查 no_attack。模式4 不进入 `0x24000` 格，所以敌方、pmNPC 与 pmPlayerEnemy 都不能接收（见 [物品命令包](original_item_actions.md)）。死亡／隐藏对象的格字映射没有读到。

打开给予期间暂停其他战斗命令和移动撤销，防止已成功交易后绕过会话结束。未确认任何交易时结束给予仍保留 pending move，之后可以撤销移动。成功交易结束会话会提交所在位置并推进一次行动。交换同 code 且未有其他交易时仍保留撤销能力。完整原版移动 flag／rollback、攻击后再操作与所有脚本组合继续归入后续公共行动研究。

## 产品结构与验证

`InventoryRules.exchange` 根据双方真实八格库存计算结果；`BattlePlayLoop.begin_give/confirm_give/finish_give` 持有会话、双方库存和行动标记并原子提交。每次开始、成功确认和结束增加 `item_revision`；旧请求不能再次消费压紧后同位置的同类物品，也不能进入重新打开的会话。不存在 UI-owned 暂持库存。

`BattleItemPanel` 只管理目标与选择，`BattleGiveView` 展示双方槽位，确认前用同一纯规则做只读预览。确认按钮捕获本次请求和自身视图身份，取消过的旧按钮不能批准后来内容相同的新预览。正常路线为 Item→Give→目标→双方道具／槽位→确认／取消→继续给予→结束；保持原资源样式，采用九宫格边框避免原图被拉长。

```sh
PYTHONPATH=tools python3 -m hsltools.evidence.give --exe $HSL_ORIGINAL_DIR/hsl01.exe --pak $HSL_ORIGINAL_DIR/hsl.pak
python3 -m unittest tools.test_hsl_give_evidence -v
godot --headless --path . --script res://tests/run_give_exchange_tests.gd
godot --path . --position 1700,350 --resolution 640x480 --script res://tests/capture_give_review.gd
tools/verify.sh
```

运行窗口坐标只适用于本次已检查的显示器布局，其他布局先定位内建屏。`run_give_exchange_tests.gd` 包含独立合成例子、各容量组合的逐 code 守恒、顺序、满包、同 code、连续给予、拒绝、移动与实际 UI 信号回归。首次比较失败是 JSON float 数组与整数槽位的测试 oracle 类型不一致，已规范化期望数组后通过，没有修改产品来迎合错误断言。

内建屏短 Control 鼠标验收与准确数据见 [give_exchange/README.md](../runtime_observations/give_exchange/README.md)。完整门禁最终退出结果记录在本次本地提交说明中。仍未恢复自动整理、完整原目标过滤、所有动作状态／角色控制和跨关存档；不由这一批扩成全物品系统原版等价声明。
