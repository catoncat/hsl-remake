# 追加攻击：实际输入与可见交锋

> evidence: runtime-measured · status: live · tools: capture_extra_attack_review.gd, run_extra_attack_tests.gd, run_first_battle_playthrough.gd · updated: 2026-09-17

2026-09-17。实现依据与系统对照见[原追加攻击](../../static_reverse/original_extra_attack.md)。本包记录Godot真实Control／地图输入和正常时钟，不是原作运行录像；图片和检查通过不等于全原作还原。

## 验证范围

[receipt.json](receipt.json)保留十条具名路线、逐击收据、release／impact次序、实际EXP通知、HP/ST画面读数、声音资源及三种终态重开结果。原动作、当前WRD、选格和真实窗口一直启用，`Engine.time_scale=1`，不替换战斗RNG、不直接赋值伤害／命中／结果。

本机先用NSScreen与CGDisplayIsBuiltin查询：外接EV2736W为0，内建Retina为1；本批用`--screen 1`，640×480窗口位于内建屏。屏幕布局改变后应重新查询，不能把索引1当固定常量。

| 路线 | 实际操作／观察 | 结果 |
| --- | --- | --- |
| equip_move | 道具→装备極光之劍→滚动预览→取消→再次确认→移动→选敌取消→攻击 | 预览1擊→2擊；移动后实际两击，总EXP130，只升级一次并进入下一角色 |
| double_counter | 实际攻击，双方各拥有测试用追加位和100%暴击／反击概率 | 主1→主2→反1→反2；四次release与四次impact，HP/ST只显示当前击 |
| early_kill | 1HP目标，仍有追加和反击资格 | 第一击致死后没有第二击或反击；遗言→EXP33→领取→成长→后继 |
| late_kill | 23HP目标，非暴击普通系列 | 两击实际19+4，最后一击才致死；EXP37、一次击杀和领取、五点成长 |
| counter_defeat | 主角21HP，目标拥有两击反击 | 第二反击致死；死者不作死后成长，正常败北、F5/F9不重发、鼠标重开 |
| ai_move | 玩家实际Wait，AI走到攻击格再发动普通系列，玩家反击也有追加 | 行走结束后才播放四击，只记一个AI行动；玩家反击EXP15一次显示，交给下一角色 |
| miss | 基础命中0、目标回避20，按原最低命中和落空补偿正常抽样 | 本次第一击有效17HP、第二击闪避；只发有效贡献EXP10，末击落空不补中间积气 |
| special | 禁魔状态下选择氣刃斬、取消、再次确认，仍有追加位 | 只有一次绝技，扣20ST一次；追加攻击不复制费用或绝技 |
| final_kill | 第6回合报告后，最后敌人23HP，两击击杀 | EXP54、一次战利品领取后才清敌胜利；终态F5/F9和鼠标重开成立 |
| escape | 报告后在撤离格实际Wait，已有EXP23 | 撤离成功，无打击、无额外EXP或行动；终态F5/F9和鼠标重开成立 |

数值均为本次具名夹具的实际样本，不是固定伤害或奖励。默认第一战不增加極光之劍或天赋。装备路线从真实ITEM12刷新属性／概率；其他数值路线明确设置三人位置／速度、HP500、attack20、STR/DEX20及0/100概率，并在001／021源声明的测试副本上设置追加位。击杀路线起始99EXP、连续数1、目标持药241与奖励seed17；终态夹具推进到已有报告事件，不冒称自然到达这些状态。低命中仍至少10%，不是“0命中必定失败”。

## 截图检查

十三张精选画面的SHA-256记录在receipt中，均已人工查看。装备预览末项没有压住按钮；选敌的2擊与实际提交一致；第二次反击、最后一击击倒、逐击HP/ST、地图EXP和五点成长均清晰。结果页的胜利／失败／撤离与已提交状态一致。

| 画面 | 入口 |
| --- | --- |
| 换装与移动后选敌 | [滚动到追加次数](equip_move-equip-12.png)、[当前命中与2擊](equip_move-target.png) |
| 四击交锋与逐击数值 | [第一击原始ST](double_counter-main1-windup.png)、[第二次反击暴击](double_counter-counter2-impact.png) |
| 晚一击死亡及完整经验 | [第二击只扣剩余4HP](late_kill-main2-impact.png)、[最终EXP37](late_kill-experience.png)、[五点成长](late_kill-growth.png) |
| AI接近与落空 | [先行走再攻击](ai_move-movement.png)、[第二击闪避](miss-main2-impact.png) |
| 终态 | [追加反击败北](counter_defeat-result.png)、[最后一击清敌](final_kill-result.png)、[实际Wait撤离](escape-result.png) |

默认数据另跑一次完整坚守：第8回合、192.148秒`victory_escape`，鼠标重开通过、退出0。其开场／对白、自然NPC普通攻击和风火、地图浏览／移动、撤离与结果沿正式流程运行；[默认结果帧](default-hold-result.png)已检查。主角本次保持一级、0EXP；不能把独立夹具的升级／極光之劍说成该默认路线自然获取。默认路线回执压缩保存在同一receipt的default_playthrough中。

声音验证是源AudioStreamPlayer在真实混音时钟上开始推进、触发次序与逐击收据一致；未新增原音轨时刻／音量或审美等价声明。

## 失败回执与修正

产品回归：新增系列测试先复现两个ST错误，第一击无积气记录时错误借用了后续反击的before。现在特写入口按每击快照投影；中间击、末击和反击前后各自独立，既有气力套件也保持通过。

验收脚本也修了两处错误。最初鼠标重开已成功，但脚本仍引用旧场景，随后报freed-instance；该次记录未用于本包。后续完整尝试的前六条全部断言通过，之后低命中路线因错误要求“两击必定全落空”而退出1。本包明确保留该进程失败事实，只接受其前六条具名路线。修正后只重跑低命中／绝技／清敌／撤离四条，`EXTRA_ATTACK_RENDER_PASS routes=4`、退出0。没有把失败进程包装成十条整体PASS。

## 复跑

先确认内建屏索引。本次机器布局对应：

```sh
tools/play.sh --screen 1 --script res://tests/capture_extra_attack_review.gd
# 也可选定路线，避免重复已成立的部分。
tools/play.sh --screen 1 --script res://tests/capture_extra_attack_review.gd -- ai_move final_kill
tools/godot.sh --headless --script res://tests/run_all.gd -- run_extra_attack_tests.gd
```

原始输出在`ignored/extra-attack-review`，每条完成后保存progress，最终receipt另记录整体错误。保存使用同目录专用`.save`，不覆盖玩家存档。默认数据完整流程沿`tests/run_first_battle_playthrough.gd`，本批完整门禁与默认路线的最终结果记录在提交说明；没有新增第二套战斗状态、额外回合或原作文件依赖。
