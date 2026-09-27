# 地图死亡、遗言与经验收尾

> evidence: runtime-measured · status: live · tools: capture_combat_aftermath_review.gd, hsltools/data/combat_aftermath.py, run_first_battle_playthrough.gd · updated: 2026-09-15

2026-09-15，接续 `main@d61905a`。本包记录已经进入游戏的共同收尾流程；原录像仍是 [V06–V10 局部观察](../original_gameplay_reference/README.md)，不等于全规则或逐帧规格。图片、输入回执和实现哈希见 [manifest.json](manifest.json)。

## 原帧、差异与当前结果

原版 [普通致死接触表](../original_gameplay_reference/12_leonard_normal_attack/contact_sheet.jpg) 显示受击、回到地图及遗言；[地图 EXP 原帧](../original_gameplay_reference/15_post_attack_settlement_floats/frame_006.png) 确认经验提示位于地图上。旧实现直接在近景伤害文字后拼 EXP，致死淡出发生在近景或法术 impact，缺少独立的遗言／地图经验等待段；次要范围目标也没有完整保留。

| 阶段 | 当前图证及合同 |
| --- | --- |
| 整次交锋 | [普通受击](attack-hurt.png)、[气刃斩受击](special-hurt.png)：保留受击姿势，尚不显示地图 EXP，反击也必须先播放完 |
| 地图遗言 | [来源台词](attack-last-words.png)：死者保留在地图，共用 BOARD02／肖像／完整分页；确认只推进这条遗言 |
| 死亡淡出 | [中间帧](attack-fade.png)：遗言确认后逐渐隐藏，回执同时记录可见性与 alpha；其他待呈现死者仍保留 |
| 地图经验 | [EXP 与升级](attack-experience.png)：显示已经提交的经验收据和等级，升级声只触发一次，提示位于角色上方 |
| 成长与后继 | [成长面板](attack-growth.png) 等待提示结束；[下一角色](attack-successor.png) 在面板关闭后获得自己的完整行动，不能重复推进 |
| 正常路线 | [第七回合撤离结果](hold-result.png)：七段开场、正常行动、多次敌我遗言、中途剧情、撤离与鼠标重开通过 |

原表文字、称号及音效绑定属于 `resource-derived`；本包重制运行属于 `runtime-measured`。新模块只持有不可变收据和表现游标，HP、EXP、击败、库存、队列与结果仍由 `BattlePlayLoop` 持有。零经验／落空没有虚构奖励；多个同模板死者按单位与收据分别展示。终局台词和结果页等待这段结束。主角无模板遗言，既有脚本台词 304 仍归剧情模块。

`tools/hsltools/data/combat_aftermath.py` 从 tracked PLAYERS 的 `dead_message`／`job_show_name` 联接 tracked RESOURCE，保留非零变体，缺少引用或模板明确失败。它不重新声明原 PAK 与 tracked PLAYERS 相等；既有原包差异仍保留。当前选择第一条非零遗言，不消费战斗 RNG；淡出 0.45 秒、经验 1 秒、紫色文字、上浮和字体均为明确的 `provisional` 重制编排。近景显示的攻击伤害可能大于剩余 HP，经验继续按既有“实际扣血＋kill_exp”规则；本批没有恢复或更改原完整 EXP award。

## 实际输入与回归

`tests/capture_combat_aftermath_review.gd` 在真实渲染窗口、`Engine.time_scale=1` 下通过鼠标选命令／目标，普通遗言用鼠标确认，特殊技遗言用空格确认，Esc 关闭成长后检查下一队友。没有直接调用攻击结算、手工推进动画、暂停时钟或覆盖随机结果。夹具明确设为邻接1HP敌人、Leonard 99EXP／100ST／速度100、下一队友速度99且受玩家控制；这证明交互与收尾，不是自然获取经验或全队友能力的证据。

夹具最初授予 ST 后未刷新菜单，实际点击验证因此失败；改为通过既有选择入口刷新后通过。图片人工审查发现升级第二行压住角色头部，提示上移28逻辑像素后重跑普通／特殊技输入并通过。最终回执无失败，日志无脚本错误或资源泄漏。

无战斗数值／坐标／结果／RNG覆盖的 `run_first_battle_playthrough.gd -- hold` 另取得 `FIRST_BATTLE_PLAYTHROUGH_PASS`／exit 0：178.172秒、第7回合 `victory_escape`、鼠标重开成功。实际经过多次 372／374 遗言、396／397、368／369 和371；此路线未获得玩家经验或触发成长，不能替代专用夹具。路线运行早于最后仅改变 EXP 文字垂直位置的调整，其余交接逻辑相同；最终显示以专用夹具及实现哈希为准。

本机先查询显示器，专用夹具实际窗口位于内建 Retina 屏。Godot 的 `--position` 是本机物理像素坐标；正常路线初次按逻辑坐标传入后发现窗口在外接，随即仅移动该游戏窗口到内建，后续已用原生窗口观察核对。不得将历史屏幕编号或坐标直接用于另一显示器布局。

```sh
# 先确认本机屏幕编号与实际窗口位置；本次内建屏为1。
tools/play.sh --screen 1 --position 3520,660 --resolution 640x480 \
  --script res://tests/capture_combat_aftermath_review.gd

tools/play.sh --screen 1 --position 3520,660 --resolution 640x480 \
  --script res://tests/run_first_battle_playthrough.gd -- hold
```

`run_combat_aftermath_tests.gd` 覆盖30／144fps、普通／特殊技、非致死／落空、实际风刃／幻火收据、致命反击、末敌胜利、同模板多目标、重复刷新、输入阻挡、音效一次、成长及后继；其中范围双死者是明确的表现收据夹具，不声称原技能范围。旧 runtime／presentation／action_handoff 回归同步等待完整收尾。真实终态还覆盖并修复了空菜单 offsets 数组类型错误。来源生成器、这些套件及 UID／JSON／差异检查均由 `tools/verify.sh` 覆盖；完整门禁最终状态记录在本次提交正文。

## 接续边界

金币、掉落资格／数量、取物暂持、满包、取消／放弃及重复领取尚未实现；原录像单次 `$100` 或取物页面不构成完整合同。下一批按 [PROJECT](../../../PROJECT.md#next-steps) 先查来源／静态证据，必要时按 [CAPTURE_SPEC](../original_gameplay_reference/CAPTURE_SPEC.md) 补窄分支。原遗言随机选择、完整死亡 handler、特殊声效内部时序、字体和逐帧混合模式也未因此恢复。当前可玩流程、原规则等价和用户最终手感验收保持分别陈述。
