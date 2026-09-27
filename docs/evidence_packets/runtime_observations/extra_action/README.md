# 连续两次行动：实际操作验收

> evidence: runtime-measured · status: live · tools: capture_extra_action_review.gd, run_extra_attack_tests.gd, run_first_battle_playthrough.gd · updated: 2026-09-17

本包验证 Godot 的白光之翼 `action_twice` 完整操作链，不是原作运行截图。原规律和有界执行范围见 [原额外行动](../../static_reverse/original_extra_action.md)。

## 场景与输入

`tests/capture_extra_action_review.gd` 在 640×480 内建屏窗口、正常时钟下，通过真实 Control／鼠标／键盘事件完成 13 条具名路线。源 WRD、人物美术、菜单、动画和音效保留。装备227／193／12、交战坐标／速度／HP、部分技能授予及必现分支条件是明确夹具；没有替换 RNG、写入伤害／经验结果或直接指定结局，正式首战默认授予不变。

| 路线 | 检验的实际流程 |
| --- | --- |
| wait_status、equip_restore | 实际换装预览／取消，两次待机只结算一次毒伤；第二次卸装、F5/F9、再装备仍不能第三次行动 |
| move_attack_cast、double_series、growth_kill | 第一段移动攻击，第二段从现位置重新移动施法；每段独立双击／反击；首段击杀后领取／升级／分点／保存，再进行第二段施法 |
| support_cure | 先治疗同伴，再范围驱毒，费用分别扣除；解毒先于最终毒伤 |
| ai_cast、ai_support、ai_no_mp、ai_silence | 两条新AI行动收据与中间提示，真实施法／支援或物理回退；第二次不是重放第一条意图 |
| victory、defeat、escape | 第二次行动清敌／反击败北／移动待机撤离；F5/F9及实际重开清空次数并恢复默认装备 |

第二次耗尽MP后的回退、第一次治疗已恢复健康后的重新决策、两位连续行动角色、队尾wrap、两次击杀连续数和经验倍率、首／次行动终态等边界另由 `tests/run_extra_attack_tests.gd`（与追加攻击同套件）覆盖，不能混称全部都是GUI路线。

## 证据保存与失败范围

精简的 [receipt.json](receipt.json) 保存具名路线、原始进程退出范围、费用／交锋／经验／装备／终态和图像哈希。早期三个进程在之后的路线失败，只保留此前无断言失败的具名路线，不把失败进程标成整次PASS。修复后成功路线分别补齐；详见回执 `attempts`。

实玩修正了装备预览遗漏连续行动行、持续提示压住菜单两项可见回归。成长后恢复的自动点击需要等待菜单展开完成；AI治疗夹具需仍满足原伤势门槛。这两项只修正验收输入／预期，未放宽产品输入或AI规则。收口还补了伪造存档中已死亡owner持有第二次行动的拒绝回归，实际死亡路径原已清除该标记。

默认整场使用 `tests/run_first_battle_playthrough.gd`，不改战斗值。早期hold在第12回合败北（318.014秒、重开成功），保留为失败尝试；它不是撤离通过，也不是已经定位的产品规则回归。该路线使用真实随机战斗和贪心撤离规划，结果不构成所有自主打法必胜保证。最终实际结果和所用脚本版本以回执为准，不引用不存在的验证日志。

## 图像检查

装备页 [连续行动预览](wait_status-equipment-preview.png) 与 [中毒第二行动](wait_status-second-status.png)，[恢复后控制](equip_restore-restored.png)，[成长后再次行动](growth_kill-ready-0.png) 与 [独立第二次法术](growth_kill-impact-1.png)，[范围驱毒](support_cure-impact-1.png)，[AI再次行动](ai_support-again.png)，以及 [清敌](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png) 已检查。标签与0.55秒停顿为重制可读性选择，不声称原作逐帧相同。

## 复跑

```sh
tools/godot.sh --headless --import
tools/godot.sh --headless --script res://tests/run_all.gd -- run_extra_attack_tests.gd
# 先查询当前内建屏索引；以下1只是这次验收的实际索引。
tools/godot.sh --screen 1 --script res://tests/capture_extra_action_review.gd
tools/verify.sh
```

默认没有白光之翼；单战保存不等于跨关或原作存档兼容。原高位dispatcher其余分支、其他职业、未支持装备效果和全局RNG仍是独立边界。
