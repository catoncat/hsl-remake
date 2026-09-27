# 歐姆村正式战斗：角色、弓、毒魔箭与跨关

> evidence: runtime-measured · status: live · tools: capture_ohm_campaign_review.gd, capture_ohm_village_review.gd, run_ohm_village_tests.gd · updated: 2026-09-19

本包记录 **Godot 实际窗口与真实控件输入**，不是原作 runtime。原指令结论分别见[角色／职业／控制／生成／射程](../../static_reverse/original_ohm_village.md)及[毒魔箭](../../static_reverse/original_poison_arrow.md)。[结构化回执](receipt.json)保存每条采用路线、输入边界、人物与出生记录、实际交锋／AI动作、进程退出码、日志及截图 SHA256。

## 玩家入口

正式战役在53逃出后通过「下一戰」进入 `content/battles/ohm_village_battle.json`，不再以预览卡代替战斗。直接游玩同一正式配置：

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 0 res://game/battle/development/OhmVillage.tscn
```

本次本机枚举内建屏为0；换机先核对显示器。该入口使用原18人编队、原装备／物品／初始能力和ST0，经共同初始成长再入场。开场结束可控制雷欧纳德与琥，村民是不可控友方NPC。原001无玩家到达撤离区条件，胜利是敌军全灭或强盗剩≤3后的敌军撤退；两种败北分别为主角死亡、两类村民全灭。原001没有插入／调级token，因此未往正式关卡添加假增援。

## 已完成的窗口路线

共 **15条命名路线（含一条四阶段跨关链）**，17张逐张按原尺寸审查的图片。所有路线实时运行（time_scale=1），效果、伤害、经验、队列与随机调用均由实际PlayLoop执行，输入之后不注入结果。只有下表明确注明的初始fixture例外。

| 路线 | 初始条件与实际操作 | 完成结果 |
| --- | --- | --- |
| opening／natural | 未修改的正式18人源编队；完整开场、状态、移动、攻击、治疗物品、成长确认、F5/F9 | 开场进入实际控制；自然战斗第五回合敌军撤退、结果页／重开。两条分别978／8978检查 |
| mixed／silence／limited | 明示40ST、快速琥、敌方耐久与站位；分别1HP受击者、禁魔、19ST | 多目标致命／非致命分开，移动且禁魔不阻止ST绝技；不足20ST不可选；真实卸弓／再装备、无虚构近身攻击、取消／F9无重复付款 |
| retreat／defeat／villagers／clear | 明示终局前提：少量存活强盗、主角1HP、最后村民1HP或仅两个敌人1HP；最后动作实际输入 | 原win1撤退、fail0、fail1与win0全灭分别出现；结果F9不重放，真实重开。clear完整进程875检查、12.589秒 |
| insert61／insert62 | 原地图上额外测试event901；队伍Lv12、临界EXP、毒与白光之翼；未改正式STORY001 | 实际普通攻击触发插入／脚本20,3调级；第二独立行动施放毒魔箭，再武装事件生成新身份／新游标。两次出生都无假装备，旧出生不重抽，F9保留 |
| double | 测试库存提供原天劫69／白光之翼227，实际装备确认 | 两次非致命普通射击属于一次行动；随后一整次毒魔箭只扣20ST，不按双击重复毒回调；两行动间F9保持阶段 |
| ai_current／ai_paralysis | 明示将原003交给友方AI并给定策略、20ST、白光之翼；分别禁魔与最后一回合麻痺。不声称003有源默认AI策略 | 实际玩家Wait交出队列；AI用自己持有的毒魔箭，ST耗尽后第二行动改选合法弓／移动动作。麻痺只跳过一次并执行一次尾部，不再获白光行动；解除反馈后才交回控制，F9不重播 |
| campaign53_to_ohm_to_world | 初始carry是已分配属性的Leonard Lv7／永久防御3／345金；Tina053放于源逃出区外一格并加速，仅为setup | 真正移动→Wait逃出→下一战按钮→完整001开场与自然实战→回大地图按钮；四阶段9661检查、184.022秒、进程退出0。新村民沿53结束的生成游标出生，双玩家carry保留而不混入Tina，永久来源与学习／升级不被覆盖 |

村民正常源编队已在自然实战中移动／等待、被攻击并参与两类胜负判定，没有凭空获得弓、法术或物品。原无装备range0是空普通攻击范围；状态面板仍展示派生攻击数值，这不代表可以执行普通攻击。

## 进程、失败与采用范围

原始日志位于 `ignored/ohm-village/`，不作为产品运行依赖。结构化回执列出精确完整命令、时间、baseline HEAD、差异指纹、退出与SHA。`render-opening`、`render-natural2`、`render-repaired`、`render-extended`、`render-campaign-reachable`、`render-ai-paralysis`、`render-clear` 均实际退出0。

`render-ai-current` 的 **ai_current已完成**，但该进程后来在ai_paralysis验收器计数失败，真实退出1；这里只采用其已写入的完整命名前缀，不称整进程通过。原因是旧通用逐帧采集按回合给无combat sequence的跳过记录换了标识，跨回合重复采集同一条记录；改读该玩家Wait之后唯一PlayLoop的AI区间账本后，单独重跑ai_paralysis退出0（1811检查、29.229秒）。规则层同样验证一次跳过／尾部及无额外行动，不删除断言。

此前失败还包括：跨关fixture只改等级未分配属性而实际战败、自然选技候选中心未过滤可选范围、空中心范围绝技在玩家旧普通目标检查处被拒绝、卸弓后菜单仍亮普通攻击，以及脚本编辑缩进／类型错误。源规则和资格未为fixture放宽：跨关用共同成长／分配准备有效carry，选点器过滤当前可选格；实际产品修复只统一空中心skill入口与空手普通攻击资格。第三战三条目的地断言被本线误移进等待循环也已恢复至循环外，并重跑整个第三战套件。

部分较早进程记录 `unchanged_during_verification=false`（开发中修改或presentation合并）；不把这些窗口记录称为最终稳定差异门禁。最后完整仓库结果以该slice提交正文及 `ignored/ohm-village/verify-close.json` 的实际退出为准，不用此处的单条检查数替代。

门禁兼容修正保留全部旧语义：扩容后的演练库存／成长表由各自生成器重新派生；无需重复的全局003/061/062行走帧注册被移除，正式001继续使用既有局部原帧。独立story001预览回归只注入测试局部的预览注册项，仍检查原对白、卡片与普通返图；正式campaign[1]保持真实战斗。全量story扫描以实际kind=story注册集合精确对照，不用硬编码数量，也没有减少遍历。

## 图像审查

![正式003状态与原装备](opening-stats-hu.png)

![原毒魔箭肖像／拉弓小窗合成](double-clip-2.png)

![移动与禁魔下的双目标ST绝技](silence-arrow-impact-1.png)

![实际脚本插入的061独立出生记录](insert61-villager-stats-19.png)

![原自然战斗的敌军撤退](natural-result.png)

![实际跨关链回大地图](campaign_world-returned-from-victory.png)

其余11张图的语义、原路径与SHA见回执frames：包括原移动范围、源发射、天劫装备、第二个062、成长确认、全灭、主角／村民败北及AI施放／麻痺／解除。文件名不是语义证据，例如早期 `*-arrow-source-panels.png` 抓在预备移动阶段，未拿它当肖像合成图；实际采用的是完整clip中的 `double-clip-2.png`。

## 复跑与证据边界

```sh
python3 -m unittest tools.test_hsl_ohm_village
tools/godot.sh --headless --script res://tests/run_ohm_village_tests.gd
tools/godot.sh --screen 0 --script res://tests/capture_ohm_village_review.gd -- opening natural
tools/godot.sh --screen 0 --script res://tests/capture_ohm_village_review.gd -- mixed silence limited retreat defeat villagers clear
tools/godot.sh --screen 0 --script res://tests/capture_ohm_village_review.gd -- insert61 insert62 double ai_current ai_paralysis
tools/godot.sh --screen 0 --script res://tests/capture_ohm_campaign_review.gd
tools/verify.sh
```

两个窗口脚本现在在Runtime创建前选择按进程隔离的user目录，F5/F9存档只写ignored，不覆盖玩家战役／设置。完整verify会清理Godot缓存；在其后再跑窗口或资源套件须重新import，且不要与同一工作树GUI并发。

原全局RNG、物件完整安装／释放调度、全地形射击传播、原实时粒子与时钟没有由这些窗口PASS证明。源数据、bounded native返回、Godot合成策略与真实输入验收是不同证据层；没有新增默认人物授予或另一份可变战斗状态。
