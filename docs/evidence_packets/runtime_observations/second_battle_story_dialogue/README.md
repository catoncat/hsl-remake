# 第二战交锋／胜负对白表现（runtime-measured，重制布局）

> evidence: runtime-measured · status: live · tools: run_second_battle_runtime_tests.gd · updated: 2026-09-18

来源：level 52 以 `dev_first_control` 进入后向 PlayLoop 注入 `event_log = ["boss_engaged"]`，由 `BattlePresentation._queue_story_dialogue` 经 `BattleScenarioRuleAdapter.story_dialogue_messages` → 当时的 `SecondBattleScenarioRules.story_dialogue_messages` 取得 WINFAIL052 event0 的两句资源消息并分页显示（640x480 窗口）。2026-09-18 起 level 52 改由 `WinfailScenarioRules` 现场解释（`rule_adapter: winfail`，事件键 `event_0`，由 Leonard 攻击皇帝的那个行动的完成扫描触发——R37 起不再在打击后单独扫描），同一对白 id 经同一表现路径显示，headless 回归见 `tests/run_second_battle_runtime_tests.gd`。

| 截图 | 内容 |
| --- | --- |
| [boss-engaged-392](boss-engaged-392.png) | 法蘭克（speaker 382 → 头像 025）：消息 392 |
| [boss-engaged-393](boss-engaged-393.png) | 雷歐納德：消息 393 |

胜利 `victory_boss` → 消息 378、败北 `defeat_leonard` → 已注册 dead message 394 由 `tests/run_second_battle_runtime_tests.gd` 以同一路径断言（文本来自 `battle052/message_text_evidence.json`，即 RESOURCE.TXT）。

## 结论与边界

- runtime-measured：event0 两句、胜利一句、败北一句按 `key:message_id` 去重后进入共享对白视图；第一战继续使用其表现侧事件表，未受影响（presentation_contract／battle_scene_runtime 套件通过）。
- provisional：原作 event0 的触发极性（`actCheckPlayerAttacked(SID_PLAYER0, SID_ENEMY025)`）、对白出现在攻击演出前后的确切时机、结果消息 122「死亡」的展示位置与胜负结果页文案未证实；本包只证明表现路径接通。
- 不证明原版等价。
