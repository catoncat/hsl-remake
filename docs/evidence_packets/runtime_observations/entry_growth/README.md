# 脚本增援入场成长：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_entry_growth_review.gd, run_entry_growth_tests.gd · updated: 2026-09-18

SR-071从`4014828b8874965eba14901b6d3829a138818f58`接续，过程中保留presentation合并至`47f35d9`的内容。原函数／VM证据见[入场调级与自动分配](../../static_reverse/original_auto_growth.md)，本页记录Godot正常时钟、内建屏0、640×480的可玩链。[机器回执](receipt.json)包含14条完成路线、六次进程的真实退出边界、出生收据／随机流、AI／交锋／尾部／恢复记录及14张人工查看图片的哈希。

## 走通的路线

| 路线 | 实际操作和结果 |
| --- | --- |
| mage、thief、wing、large、zero | 实际攻击或移动施法触发event901，分别生成原026法师、028盗贼、036翼战士、039大型角色；显示实际出生等级和当前数值，进入后续AI队列，F5/F9不重新调级。zero显式`[0,0]`保持基础推算等级并不抽样 |
| repeat、blocked | 第二次独立行动再次触发事件，生成新的同类实例并延续出生随机流；大型角色整块落点受阻时保留请求而不花随机数，真实控制阻挡者移开后才生成一次 |
| support、states、paralysis | 实际换装／移动治疗触发增援；禁魔与无MP阻止法术，普通攻击仍合法，清醒剂解除禁魔而保留毒伤；带毒／禁魔／麻痺的新援按正常行动入口跳过与尾部处理，不再次出生或重复叠加成长 |
| victory、defeat、escape | 先击杀旧末敌后，事件新援先于胜负判断落地；击杀新援按该实例金币和经验结算，再显示清敌结果。修正夹具后由新援实际攻击造成主角败北；移动到指定格再待机完成撤离。三种结果均实际F5/F9及按钮重开 |
| carry | 撤离后用一次性队伍承接进入实际的新MobileJobsTrial场景，保留匹配队员的成长／装备等字段；旧敌人、出生收据和随机流不带入，新场景再次F5/F9通过 |

全部为明确开发夹具，沿源051地图与原职业／角色资源，起始受控等级12及耐久、资源、装备、状态、AI概率在`EntryGrowthFixture.gd`中声明。support为完成持续观察另加祭司源HP并在开局填满；defeat给新援声明足够攻击并让原种子敌人经真实`actDeleteObject`离场，验证记录确认实际致命决策来自新援。没有把这些装备、法术或数值额外授予正式关卡。

事件之前完成一次真实保存；之后的移动、选格、攻击、施法、治疗、使用道具、取消、成长、等待、保存、恢复与重开都使用现有控件。初次出生数值由正式事务执行原规则提案和独立随机流，不在演出后修改结果。每次安静边界还核对所有出生收据不变、历史顺序和当前派生状态一致。

## 画面与顺序

[入场状态页](birth-status.png)显示基础Lv.1与实际Lv.11，当前攻击、防御、MP等来自正式重算；新文字置于右侧信息区，不再被底框裁切。[大型角色恢复](large-restored.png)和[释放占地的实际路径](unblock-path.png)分别记录生成后与被阻挡后的流程。[第二次事件](repeated-reinforcements.png)保留两个不同的新实例，没有重用旧编号或再次成长旧角色。

[移动風刃](moved-wind.png)、[移动治疗](moved-healing.png)展示真实范围和目标。[解除禁魔](silence-cured.png)之后仍有[中毒尾部](poison-preserved.png)；[新援麻痺](paralysis-entry.png)进入已有跳过流程。对应期间出生记录和随机流不变。[实例EXP](instance-experience.png)先于[清敌结果](victory.png)；[败北](defeat.png)、[撤离](escape.png)和[新场景恢复](new-battle-restored.png)保留各自终态及场景边界。

## 本轮发现及修正

实玩发现攻击触发的增援原本要等整次行动交接才创建，带白光之翼时第二行动能先看到旧阵容。现将生成放入事件事务，先提交完整新阵容再交回第二行动／判断清敌。进一步的定向红例确认“旧末敌死亡＋新援整块占地受阻”也会误判清空；现只延后依赖敌人数的胜利，撤离与败北仍独立成立。该组合已取得失败到通过的回归结果，不把仅有正常出生路线当成此边界的证明。

手工查看状态页还发现出生文字贴住左下框，已移到右侧信息区并核对实际新截图。原始裁切图保留在ignored，未作为当前完成图证归档。

早期夹具检查依次纠正了：状态字典用英文`attack`键；support低血量祭司在预定循环前被正常伤害击倒；states密集位置的鼠标点击选中了相邻旧角色；败北断言误用`defeat_player`而项目共享键为`defeat_leonard`；夹具删除token改为真正支持的`actDeleteObject`。这些修正没有放宽产品伤害、命中、范围或原作初始化规则。

## 回执范围

`render-roles-close.log`五条、`render-states-close.log`两条和`render-outcomes-close.log`三条整次退出0。`render-interactions.log`在repeat／blocked两条完成后遇到后续support夹具问题退出1；`render-support-states.log`在support完成后遇到states选中错误退出1；`render-outcomes.log`在victory及按钮重开完成后遇到败北旧断言退出1。只提升此前具名已完成结果，未宣称这些失败进程整次通过。

原指令调用、定向检查和本页实玩各自证明不同边界。完整门禁还要核对所有Godot套件、冷缓存资源导入、Python／源数据／文档／JSON／UID／diff；最终真实退出结果记录在本批提交正文。整个初始对象构造、NPC战后自动成长、学技、原全局随机流和完整dispatcher不在当前等价声明中。现有初始阵容策略不因本批新援成长而改写。

```sh
tools/godot.sh --headless --script res://tests/run_entry_growth_tests.gd
tools/godot.sh --screen 0 --script res://tests/capture_entry_growth_review.gd
tools/verify.sh
```

实玩入口只写`ignored/entry-growth-review/`的隔离存档与画面；跨场景使用独立一次性carry，不改用户持久战役文件。

## 指定兵种数量胜利的补充收口

`e299115299e23c6bec660dd988cb16e162d19a52`提交后，定向红例发现待入场保护仅检查`actCheckEnemyTotalNumber`，遗漏`actCheckEnemyNumber SID_ENEMY026,0`：旧026已死且新026落点被占用时会提前锁定胜利，后续腾位也无法再生成。修复沿既有token→class映射，只延后依赖同一待生成兵种的胜利；其他兵种、绑定到旧实例的目标、撤离与败北仍独立。定向覆盖增至2807项，保留真实红／绿日志哈希，不把未设置`supported`的第一版测试数据当作产品失败证据。

新增`class_blocked`实际输入路线在已合并presentation的`8bad191`上运行，正常时钟、内建屏1、640×480，完整退出0。它击杀旧敌、保留第二行动，在待入场阶段F5/F9，然后用真实移动腾出格子，生成并查看唯一的新援，再移动攻击、结算该实例EXP／金币、终态F9及按钮重开。四次保存恢复均核对完整状态相等；[独立回执](class-boundary.json)保留命令、进程、出生与随机链、实际交锋以及四张已查看图片的哈希。原14条路线保留各自原始边界，未重新执行或冒充同一新进程。

图证为[等待同类新援](class-victory-pending.png)、[腾位后单次入场](class-birth.png)、[目标胜利](class-victory.png)和[终态恢复](class-final-restored.png)。图片复核暴露了类计数条件落入无默认标题的`victory_script`；规则适配现将其归入既有目标胜利类型`victory_boss`，按现有表现合同显示“目标已击破”，不把只消灭指定兵种说成全敌清除。该内部类型不表示角色被认定为原作boss；脚本有结果标签时仍使用原标签。

第一次新增窗口进程在目标仍存活时被验收驱动错误地等待终态，退出1；驱动改为最多八次按当前合法路径和实际命中结果继续操作。第二次进程虽然逻辑检查退出0，图片的空标题使其不作为最终视觉验收；补齐目标结果映射及标题非空检查后第三次完整通过。三次范围分别记录，当前图证来自最后一次。此补充是当前生成／终态事务修复，没有增加完整原dispatcher的等价声明。

```sh
tools/godot.sh --screen 1 --script res://tests/capture_entry_growth_review.gd -- class_blocked
```
