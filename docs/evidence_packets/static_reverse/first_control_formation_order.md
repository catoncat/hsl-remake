# First-control formation and queue input order

> evidence: resource-derived; static-derived: 0x407660 注册槽与 0x407340 收集顺序; runtime-measured: 2026-09-24 第一战录屏行动顺序 · status: live · functions: 0x407287, 0x407340, 0x407660 · tools: hsltools/checks/registration_order.py, hsltools/data/first_battle_formation.py, run_tests.gd · updated: 2026-09-25

2026-09-05；2026-09-25 lane R7-NPC 取代同速次序一节；同日 lane SLOTORDER 把首版与更正矛盾的段落标为作废。

**2026-09-25 更正（取代下文"保留 EVEF 顺序"的重制选择）。** 同速平局现按原版注册顺序：`0x407660` 把登记玩家（对象字 `+0xa2 < 20`）放进注册数组 `0x4c34c0` 的保留槽 `+0xa0`（PLAYERS 编号 −1），其余对象从槽 20 起按创建顺序取下一个空槽（游标在 `0x407287` 复位为 20）；`0x407340` 从槽 0 收集再做稳定降速排序，所以同速时登记玩家先于 NPC、NPC 之间按创建顺序（static-derived）。用户录屏实测：023_1 的速度下限就是 14，与雷歐納德相同，原版雷歐納德先动、023_1 在他之后（runtime-measured，[battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)）。`CoreTurnQueue.rebuild` 按 `registration_slot` 先排玩家；`run_tests.gd` 的首战夹具（全 1 级）改为 021×5 之后交给雷歐納德、023_1／023_2 紧随其后，另有一条"调级到 L2（速 15）的 023 在雷歐納德之前"的断言。下文的参考帧（首控时两名 023 在雷歐納德前方）由开战随机调级解释：每名 023 有 2/3 概率升到 L2 以上、速度 ≥15（[原入场调级](original_auto_growth.md)，重制 `InitialRosterGrowthRules` 已接入），不再需要改排序来还原。

**仍有效的事实（2026-09-05 首版，2026-09-25 lane SLOTORDER 复核）。**

- 资源：第一战 EVEF 记录 17／18 是两名普通友军（023），20 是雷歐納德（`defProcPlayerInstall`，保留槽 0），21／22 是两名重装友军（024）。`hsltools/data/first_battle_formation.py` 不再把 001 排到最前，场景保持资源记录顺序；这个顺序对 NPC 就是原版创建顺序，对玩家不起作用（玩家按保留槽排）。
- 稳定排序：`0x4073e5`／`0x4073ec` 遇到速度大于等于时停止插入，`0x407433`／`0x40743a` 只上移速度更低的前项，所以同速保持输入（注册槽）顺序（static-derived，本地 EXE 反汇编核对；lane ORACLE 在模拟器里实跑 `0x407340` 复现，见[原版敌人回合裁判](original_enemy_turn.md) §7）。
- NPC 槽号按创建顺序：同一模拟器读出第一战槽号 021_1 s20、026_1 s21、021_2 s22、021_3 s23、021_4 s24、026_2 s25、021_5 s26、023_1 s27、023_2 s28、024_1 s29、024_2 s30，正是 EVEF 记录 4／5／7／9／10／11／12／17／18／21／22 的顺序。全部战场的对照在 [initial_battle_initiative](initial_battle_initiative.md)「Registration order is not simply EVEF order」，由 `python3 tools/hsl.py check registration_order` 在门禁里重算。
- 参考帧：精选原版截图 `first_control_action_menu.png` 首控时两名普通友军在雷歐納德前方、两名重装在后。它们的出生格正确，是已经先行动过（开战调级把速度升到 15 以上，见第 7 行），不是排序差。

**已作废（2026-09-05 首版原文，勿再引用）。** 首版有三处与第 7 行的更正矛盾，现全部作废：

1. "保留 EVEF 顺序是重制有意的队形／节奏选择，原版同速次序不能由 EVEF 顺序确定"。现行规则是原版注册槽顺序：同速时登记玩家（槽 0..19）先于 NPC，NPC 之间按创建顺序。
2. "五名速 15 士兵和两名速 14 普通友军都先于速 14 的雷歐納德行动"。现行队列（模板速度）是 021×5 之后下标 5 雷歐納德、6 023_1、7 023_2（`run_tests.gd` `_test_real_equal_speed_pairs_follow_registration_slots` 钉住）。
3. "核心检查断言普通友军在前"，以及"同距目标按最少横移打破平局"的重制走法。前者随第 2 条作废；后者已不在现行代码里，现行追击走法见 [battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)「修了什么」。

首版的截图回执在 `ignored/formation-review/`（不入库），只当历史记录。
