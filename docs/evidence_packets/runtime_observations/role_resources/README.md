# 三职业、资源装备与最终行动的可玩验收

> evidence: runtime-measured · status: live · tools: capture_role_resources_review.gd, run_job_stats_tests.gd, run_resource_recovery_tests.gd · updated: 2026-09-17

本包记录当前Godot实际控件与正常时钟验收。源公式／调用边界分别见[职业原指令](../../static_reverse/original_job_stats.md)与[资源尾部](../../static_reverse/original_resource_recovery.md)，本包不作为原作runtime证据。机器回执与图片哈希见[receipt.json](receipt.json)。

## 操作与结果

13条具名路线由两个完整成功的渲染进程组成：`ignored/role-resources/render-player2.log`为5条，`render-other2.log`为8条；对应`player-final.json`和`other-final.json`均没有失败。两个进程都使用内建屏index1、640×480窗口和Engine.time_scale=1，输入走真实菜单、鼠标选择和F5/F9。初始化时提供的角色、装备、当前资源与控制权在机器回执中逐项声明；不会把受控法师／重装兵或额外装备说成正式第一战新授予。

| 路线 | 实际走通的链路 |
| --- | --- |
| mage_growth／heavy_growth | 查看源职业属性→合法换装→移动击杀→原最终EXP升级与四属性分配→白光之翼第二行动→保存恢复→再次移动攻击／施法→末次回复与交接 |
| sword_double | 極光之劍、白光之翼及回复装备；两次行动各含两击和一次反击，全部结束后仅一次自动回复 |
| poison_recovery | 中毒、禁魔、HP及MP回复同时存在；画面依次显示毒伤、HP回复、MP回复，后继菜单在三段结束后开放 |
| second_remove_restore | 第一行动无回复，第二行动读档后移除MP回复装备；不补回MP、不产生第三次行动 |
| support_recovery | 减耗饰品→移动治疗友军→支援贡献与EXP→自身毒伤及HP回复→安静边界保存 |
| detour | 换移动装备，在实际WRD障碍上选择比直线距离长的合法路径，按同一预算到达并待机回复 |
| ai_half_cast／ai_mp_return／ai_item_restore | 4MP减耗施法；0MP不能施法、最终回复后下一轮重新选法术；真实库存用药反馈先于MP回复 |
| victory／defeat／escape | 第二行动分别清敌、被反击击败或移动后待机撤离；冻结未执行的回复，终态保存恢复，真实重开恢复默认角色／资源状态 |

默认第一战另外实际跑通：hold第8回合236.278秒撤离、advance第4回合116.904秒败北，两条都鼠标重开。日志末行和对应完整receipt一致，哈希保存在本包；中断接续后未保留原终端退出码，因此这里只声明已核对的PASS标记与回执，不编造退出码。

## 人工检图

![法师源属性](mage_growth-initial-stats.png)
![职业成长末项](mage_growth-growth-resists.png)
![毒伤反馈](poison_recovery-tail-1-0.png)
![生命回复](poison_recovery-tail-1-1.png)
![魔力回复](poison_recovery-tail-1-2.png)
![真实绕路](detour-range.png)
![回复后的AI新施法](ai_mp_return-impact-2.png)

其余选帧包括[重装兵属性](heavy_growth-initial-stats.png)、[成长后法术](mage_growth-impact-1.png)、[双击后回复](sword_double-tail-1-0.png)、[清敵](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)和默认[撤离](default-hold-result.png)／[败北](default-advance-result.png)。原技能／行走／普通攻击声音沿现有动作，自动回复没有被附会新的原作音效。

## 复跑与修正

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 1 --script res://tests/capture_role_resources_review.gd
tools/godot.sh --headless --script res://tests/run_job_stats_tests.gd
tools/godot.sh --headless --script res://tests/run_resource_recovery_tests.gd
tools/verify.sh
```

运行前确认内建屏索引；夹具存档只在ignored目录，不覆盖玩家存档。早期渲染选择了职业不允许的193靴子，以及不在武器范围的斜格；修正的是夹具装备／站位，没有放宽源资格或攻击范围。实际出现的移动后用药与回复提示相互阻塞由表现层前置顺序修复；规则仍只提交一次。最终门禁发现旧状态测试在初始化前设置速度／MP，新共享刷新按源值重算后选不到预定施法者；将合成值改为初始化后设置，状态600项及支援／AI支援／奖励定向全部退出0。旧AI范围夹具还只设置MP100而未设置对应上限，新增资源一致性检查据此拒绝；补齐合成上限后AI技能／导航／收尾／第二战定向全部退出0。verify在退出时清理导入缓存，后续定向先重新import，缺缓存诊断不冒充产品回归。数值取整、固定NPC模板策略、手动成长与原完整初始化的区别见源包。最终完整门禁结果由本批提交说明记录。
