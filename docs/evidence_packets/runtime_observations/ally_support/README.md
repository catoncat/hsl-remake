# 友军移动援助：实际输入与默认第一战

> evidence: runtime-measured · status: live · tools: capture_ally_support_review.gd, hsltools/probes/ai_support.py, run_ai_support_tests.gd, run_first_battle_playthrough.gd · updated: 2026-09-17

2026-09-17。基线`d1ffa8d`，本批SR-049工作区。这里记录Godot实际可见验收；原函数、来源字段、完整系统对照与明确的重制组合见[友军规则证据](../../static_reverse/original_ai_support.md)。截图不是原游戏画面，不能据此认定原AI、全部职业或精确时钟等价。

## 十条完整输入路线

运行`tests/capture_ally_support_review.gd`。通过实际Viewport鼠标／按键／滚轮选择Wait、魔法、目标、状态与成长；正常Runtime移动、施法、声音、经验和行动交接。没有用信号代替点击，没有覆盖战斗RNG、直接指定命中／结果或加速时钟。最终进程退出0，日志`ALLY_SUPPORT_RENDER_PASS routes=10`，回执无失败。

| 路线 | 本次观察 | 通过的链路 |
| --- | --- | --- |
| heal_move | 移动3格，治癒之水实际回复37HP，施援者获EXP9并到2级 | 下一名角色实际再施放治疗，独立获得EXP／五点成长，前一人的经验不重发；最终第三位角色菜单出现 |
| greater_move | 生命之水回复68HP，EXP14 | 使用自身射程、一次16MP、完整特效和经验后交接 |
| life_move | 女神之淚实际回复96HP封顶，EXP25 | 长射程选择不同合法位置，28MP，聚集／扩散和全部声音后交接 |
| cure_move | 范围内两名友军驱毒，施援者获最终EXP51 | 一次4MP，两个毒字清除，主要受援者禁魔2回合仍保留 |
| next_patient | 首位残血队友超出当前移动＋治疗射程；后续患者获41HP，EXP14 | 扫描续查没有被首个不可达目标卡住，选定后移动／施放正常完成 |
| enemy_heal | 敌方侧施援者回复同侧目标37HP，EXP13 | 对侧伤员未被治疗，明确测试的成长资料归施援者 |
| no_mp | 未施法，继续合法移动行动 | 原MP0和EXP99保留，无支援特效／经验提示，下一角色可操作 |
| silence | 未施法，继续合法移动行动 | 未错误扣MP或记录法术贡献，行动后禁魔按原生命周期递减 |
| item_move | 移到相邻格使用实际携带的药品241，回复40HP | 库存减少一次，到达后才显示绿色+40HP／播放用药声，无魔法EXP |
| item_no_mp | 拥有治疗术但MP0，改用携带的药品援助 | 同一物品事务／移动／反馈／交接，MP和原EXP保持 |

完整的精简技能／物品收据、每目标贡献与最终经验、两个参与者的经验事件、移动路径、源音效路径和观察项见[receipt.json](receipt.json)。数字是本次正常随机运行的结果，不是固定治疗值或固定EXP。影像SHA-256随回执保存。

夹具明确使用原可渲染角色、固定站位／速度、`move_point=move_range=3`、100MP和残血患者；001水系技能与药品是测试授予。为了观察两名参与者升级，夹具提供明确的受支持成长资料和99EXP；不是对一般兵等职业原成长的恢复声明。实际WRD和正常演出时钟保持。原027的未修改WATER06拥有权另由纯规则规划检查，未冒充该角色已有完整正式场景。

本次屏幕查询确认AppKit索引0为外接、1为内建。最终Godot窗口回执为screen1、640×480；高分屏的原生窗口坐标与AppKit逻辑frame不直接比较。截图只取游戏Viewport，不截桌面。

## 人工图像核对

已查看并保留[移动中](heal_move-moving.png)、[治疗命中](heal_move-impact.png)、[最终经验](heal_move-experience.png)、[下一名参与者的成长页](heal_move-growth.png)与[第二次施援后的菜单](heal_move-second-handoff.png)。移动阶段没有提前施放或开放命令；经验提示位于源角色附近，成长页显示本人的等级／经验／未用点数。

[两目标驱毒](cure_move-impact.png)的两段文字位于光效之上、彼此分离；[结果状态页](cure_move-status.png)保留禁魔。另保留[高级治疗](life_move-impact.png)、[续查后的患者](next_patient-impact.png)和[缺MP后的药品援助](item_no_mp-item.png)。这些位置与画面使用统一地图坐标，未另造展示战斗状态。

音效确认来自实际播放流前进与路径采样：cast_magic、MHEAL006／007／008、LASERUP003、SHOOT005／MHEAL003和use_item；释放／命中与每次经验事件数量也有断言。声音已接入并实际播放，不把这项检查称为与原录影音轨逐帧／逐耳等价。

## 默认整场与结果

两条路线直接运行未改战斗数值／技能／库存的`run_first_battle_playthrough.gd`，都从正式开场进入并实际鼠标重开成功。详见[default_routes.json](default_routes.json)。

| 默认策略 | 本次结果 | 边界 |
| --- | --- | --- |
| advance | 第6回合战败，172.164秒；等级1，EXP66；自然使用氣刃斬 | 正常交锋、伤害／经验、死亡对白、[失败结果页](default-advance-result.png)和重开成立；没有为获得胜利重抽或修改数值 |
| hold | 第8回合撤离成功，182.354秒；等级1，EXP0 | 剧情目标切换、两次正常移动、[撤离结果页](default-hold-result.png)与重开成立；等待／撤离没有凭空发EXP |

这是两个单次策略运行，不是稳定难度或长期平衡统计；两条默认录像没有额外授予水系术，也没有由患者夹具反推默认战斗中自然发生了所有辅助技能。范围风火、击杀／非击杀、等级差／连续数／装备、支援升级和终态存档另复用上一批[魔法／最终EXP实际验收](../magic_experience/README.md)，本批没有重开已充分证明的伤害公式。

## 发现、修复与验证边界

真实集成回归是移动后范围施法仍使用起点枚举施法者：进入范围时会漏掉自身，离开范围时会错误保留自身效果。现在公共技能准备阶段使用只读目的地提案，提交仍归PlayLoop；两方向的范围、取消／失败不变更和一次MP扣费都有回归。

首次单路线进程在两人施援完成后的检查点，把原地图角色位置上的命令图标当作角色点击，因而进入攻击而不是状态。修正夹具使用受援角色的实际状态按钮后继续。第一次十路线虽退出0，但夹具只设置move_point3、实际move_range仍继承5；统一两字段并增加真正的路径预算／短法术不能借长法术射程断言后，重新完成全部十条，最终回执取后一次。以上经过在receipt中明确保留，未把较早失败进程改写成PASS。

`run_ai_support_tests.gd`覆盖原扫描／概率、阻挡／不可达续查、阵营／存活／坏数据、独立技能射程、多人贡献、药品类别退路和过时意图拒绝。新增正常时钟场景检查还验证移动完成前无用药反馈、到达后一次声音／反馈、重复tick不变更战斗状态、反馈结束后准确开放下一角色和音频释放。最终完整门禁结果见SR-049提交说明，不把定向PASS替代全仓验证。

## 复跑

先查询当前屏幕；布局变化后不能假定内建屏永远是1。下面1是本次实际查询所得索引。GUI逐条顺序运行；完整门禁会清理导入缓存，不与渲染并行。

```sh
tools/play.sh --screen 1 --script res://tests/capture_ally_support_review.gd
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- advance
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- hold
tools/godot.sh --headless --script res://tests/run_ai_support_tests.gd
python3 tools/hsl.py check ai_support
```

单场景支持通过`-- heal_move cure_move item_no_mp`选择部分路线；实际默认十条和两条整场已在本包记录。规则等价范围、原函数入口和未恢复的完整辅助／地图搜索语义只由[原证据包](../../static_reverse/original_ai_support.md)定义。
