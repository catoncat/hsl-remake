# 月花圓舞：十三条实际输入与完整收尾

> evidence: runtime-measured · status: live · tools: capture_moon_dance_review.gd, run_moon_dance_tests.gd · updated: 2026-09-18

SR-063在`ecd96ea`祭司来源批次上接入月花圓舞。这里记录Godot正常时钟、640×480内建屏0中的鼠标／键盘操作；原EXE应用与顺序证据另见[原指令研究](../../static_reverse/original_moon_dance.md)。[机器回执](receipt.json)保存每条路线的初始覆盖、末态、逐段伤害／经验收据、实际音频、F5/F9次数和终态重开结果。

## 四个最终进程

| 最终运行 | 采用路线 | 实际退出 |
| --- | --- | --- |
| `render-player-final.log`，session84106，PID19814 | manual、multi_kill、misses | 0，无Godot错误／警告 |
| `render-interactions.log`，session68721，PID28531 | phase_extra、ordinary_then_moon、aid_after_moon、large_target | 0，无Godot错误／警告 |
| `render-ai.log`，session51162，PID35445 | ai_multi、ai_empty、ai_paralysis | 0，无Godot错误／警告 |
| `render-terminals.log`，session29439，PID39399 | victory、defeat、escape | 0，无Godot错误／警告 |

原始日志和按次冻结的JSON位于`ignored/moon-dance/`；哈希与真实终端结果写入回执。四次运行分别覆盖3／4／3／3条，总共十三条，不用旧失败进程的PASS文本替代零退出证据。每条至少完成一次F5保存／F9恢复；三个指定终态均操作真实重开按钮。

## 走通的完整链

| 路线 | 已完成的实际行为 |
| --- | --- |
| manual | 启动发布的`MoonDanceTrial.tscn`，选择自身并对三名源士兵施放；十五次月花命中及后继两次普通打击后回到可操作状态，满包采用“稍後領取”，保存待领物品及战斗 |
| multi_kill、misses | 实际装备幸運緞帶228，三目标十五段、两个死者一次奖励、经验加倍和完整成长后交接；另一条以明确hit0覆盖验证落空后的后续抽样与保存 |
| phase_extra | 白光之翼下移动、取消绝技选择、撤回移动、重新移动施放；MP0与禁魔不阻止绝技，第二行动保存后卸翼再施放，分别支付两次20气力，最后只执行一次毒／状态尾部 |
| ordinary_then_moon、aid_after_moon | 主攻双击和反击双击四个impact后，第二行动施放五段月花；另一条月花后使用移动施法环，移动并治疗真实残血同伴，经验与资源仍按各次行动独立结算 |
| large_target | 原039海輝魔的多个身体格被覆盖，只生成一个目标、五段回调及一份最终贡献；原大型资源、边缘目标与保存共同工作 |
| ai_multi | AI移动到自身范围的有效站位，第一行动五段×两目标；其中一人死亡后第二行动重新选剩余目标，再五段并单独付款，共十五次impact |
| ai_empty、ai_paralysis | 无攻击资格、无MP、气力不足及禁魔时两次合法等待；麻痺则只走一次入口跳过，不再授予白光之翼第二行动 |
| victory、defeat、escape | 三人致死月花十五段后胜利；普通攻击被致命反击后败北；月花后第二行动移动到撤离区并待机。三种终态保存／恢复、冻结后续结算及按钮重开均通过 |

所有战斗状态覆盖仅发生在各路线setup之前，之后由实际控件触发；伤害／经验随机数没有替换。AI路线把选择概率显式设为100以保证命中待验分支，生成的源技能概率仍为90。普通双击／反击组合中的固有双击、初始HP、经验99和队列速度属于明确夹具，源拥有权／支付／伤害公式与当前角色事务没有被伪造为默认授予。

## 图证

十六张图均来自上述通过进程的frames列表，已经查看，并在回执内保存SHA256。未引用的旧失败截图不进入本证据包。

选择、出招与真实交接：[自身与周围范围](manual-self-center.png)、[原施放画](manual-moon-1-0.png)、[满包等待选择](manual-full-bag.png)、[恢复后可操作菜单](manual-restored-1.png)。

逐段结果与成长：[第三目标第五段](multi_kill-moon-1-15.png)、[最后经验后的成长](multi_kill-growth.png)、[落空反馈](misses-moon-1-1.png)、[最后行动的毒伤](phase_extra-tail-1.png)。

组合与AI：[普通双击后接月花](ordinary_then_moon-moon-2-5.png)、[后继援助及恢复](aid_after_moon-restored-2.png)、[大型目标只一次覆盖](large_target-moon-1-1.png)、[AI第二行动末段](ai_multi-moon-2-5.png)、[麻痺跳过](ai_paralysis-skip.png)。

终态：[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)。终态图中的“祭司·援護演練”来自明确使用PriestTrial状态的控制夹具；manual才是发布的月花演练原样路线，不混同为正式第三战。

## 失败修正与范围

早期演练的包围布阵既可能落在原地形不可行走格，也可能因源速度让角色在首次操作前倒下；已移到原地图真实空地，并将演练用120HP／20speed加值明确写入生成器与说明。一次经验装备路线误用了未开放的冰心石220编号，已改为原幸運緞帶228。正式第一战与PriestTrial的初始气力、角色来源均未修改。

起初被怀疑为演出阻塞的等待，诊断后确认为背包已满、领取界面正在正确等待交换或“稍後領取”；验证脚本此前反复点击禁用按钮，现改为实际操作稍后领取。该次诊断在查明原因后终止退出143。另一次诊断访问开发场景为空的剧情控制器，严格运行器将其判为退出1；修正空值检查后将整组三条路线重新验证，最后进程退出0。这里没有把正确的满包事务描述成产品死锁，也没有接受含脚本异常的PASS文本。

收尾定向检查还发现组合夹具给麻痺／禁魔传入了只属于毒的强度参数，现按状态合同只给毒传强度；修正后3031项月花检查零诊断通过。AI技能2149项、祭司908项及表现合同的受影响定向检查也通过；最终全仓门禁由独立`tools/verify.sh`执行，实际日志及退出码记录在本批提交说明。

## 体验与复跑

```sh
tools/play.sh --screen 0 res://game/battle/development/MoonDanceTrial.tscn
tools/godot.sh --screen 0 --script res://tests/capture_moon_dance_review.gd
tools/godot.sh --headless --script res://tests/run_moon_dance_tests.gd
tools/verify.sh
```

发布演练使用源051地图、002职业／装备／技能和原士兵；提供原PriestTrial的开发库存、40初始气力及120HP／20speed训练加值。这是独立体验入口，不属于正式原关卡或自然入队授予。花瓣／光球轨迹、选点颜色、混色与演出时钟是明示重制取舍；315次原指令应用和14组边界只证明各自执行范围，不证明完整原对象调度、现场随机流或逐帧表现等价。
