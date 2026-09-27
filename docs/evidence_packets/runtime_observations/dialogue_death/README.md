# 对白与阵亡演出：原版三路测量与重制落地（lane R6-P1）

> evidence: runtime-measured: 用户 2026-09-24 原版录屏（605.8 s，可变帧率约 57 fps）按源帧率量的像素轨迹与音轨互相关; static-derived: 死亡入口姿势 0x446c40 状态 6、遗言选句 0x43ef91..0x43efcb 的 r2 读法; resource-derived: SHAPEDEF hit 帧、dead0003.wav; provisional: 说话人／目标／行动者高亮的颜色与脉动只来自这一份录屏 · status: live · functions: 0x43ef91, 0x446c40, 0x458c10 · tools: hsl_video_events.py, run_combat_aftermath_tests.gd · updated: 2026-09-24

起因：R6-V2 录屏对账漏掉了用户确认的"灵魂飞升"与"咻"声（Gemini 把它说成"闪烁后消失"，声音未进流程）。本包对每个效果先量原版三路（像素／声音／资源或静态），再写重制前后。Gemini（agy）本轮不可用（`FAILED_PRECONDITION: User location is not supported`），本包没有任何模型命名，全部是量值。

## 方法

- 录屏：`录屏2026-09-24 中午12.03.22.mov`（用户录屏，私有档案）（本机，不入库），游戏区 `crop=1280:960:112:140`，缩到 640×480 逻辑像素。音轨起始 0.177 s（ffprobe），下文时刻都是视频 PTS 秒。
- 像素：`tools/hsl_video_events.py region`——一个逻辑框按源帧率逐帧量相对参考帧的变化像素（外框、质心、平均亮度差、平均颜色、逐行带计数、亮像素行 `bright_rows`）、相邻帧平均步长 `step_prev`（溶解＝多帧小步，硬切＝一帧大步）与平均亮度的周期。
- 声音：`tools/hsl_video_events.py audio`——10 ms 包络的起点，以及候选 WAV 的归一化互相关（NCC）最佳位置；全片扫描用同一互相关。
- 原始片段、逐帧 JSON 与截图在 lane worktree 的 `ignored/r6p1/`，不入库。

## 1. 阵亡的"灵魂飞升"与"咻"声

| 项 | 原版量值 | 等级 | 来源 |
| --- | --- | --- | --- |
| 声音是哪一个 | `wav/dead0003.wav`（PLAYERS `sound_dead`，021／023／024／026 及己方同声）在全片 15 处命中：108.55、140.99、193.97、206.18、253.25、264.08、275.59、286.86、298.09、311.46、338.02、371.97、449.57、466.47、511.83 s，NCC 0.39–0.51；204 个已导入 WAV 里长音最高分，次高 0.31 | runtime-measured＋resource-derived | `audio` 互相关 |
| 声音与画面时刻 | 298.09 这次：灵魂第一帧 298.027 s，声音起点 298.094 s（晚 4 帧，录屏音画延迟量级） | runtime-measured | 同上＋`region` |
| 顺序 | 遗言框（296.6–297.7 s）→ 框溶解收起（297.71→298.03 s）→ 灵魂＋声音同起 → 消失后 EXP／$ 浮字 | runtime-measured | `region` 对白框与死者框 |
| 时长 | 298.09：298.027→298.30 s（0.27–0.32 s，16–19 帧）；140.99：140.915→141.18 s（0.28 s） | runtime-measured | 亮像素掩码（`--brighter`，阈值 24） |
| 上升 | 亮像素质心从 y≈164 升到 y≈108（≥56 px，顶边被画面上缘截断）；140.99 升 47 px | runtime-measured | 同上 |
| 颜色／亮度 | 第一帧整体变亮（平均 +86 亮度，RGB 约 192,166,149 偏暖白），随后线性变暗到消失 | runtime-measured | 同上 |
| 规则 | 遗言关闭后 16 tick 纵向缩放 +0.25/tick、层级 16→0、加法混合；死亡音与拉伸同起 | static-derived | [原版阵亡处置](../../static_reverse/original_death_disposal.md) |

重制前（R6-V2 补录 1，65.98 s）：同一死亡音、同一加法拉伸，亮像素 0.22 s、质心升 37 px、RGB 205,182,179——拉伸与声音已是原版读法（R5-L2／R5-L7），差在姿势（下节）。16 tick 按 16 ms 为 0.256 s，原版量得 0.27–0.32 s，差值在录屏帧率与 tick 抖动量级内，重制不改静态读出的 16 tick。

## 2. 死亡入口的姿势：hit 帧（NNN-P）

- 静态：死亡入口 `0x43ef36..`／`0x44347e..` 调 `0x446c40(actor, 方向, 6, 2)`。`0x446c40` 按状态查跳表 `0x446d08`：状态 6（`0x446cc4`）取角色 SHAPEDEF 记录偏移 0 的单个 shape、帧数固定 1；解析器 `0x4468b5` 把 `hit` 字段写到偏移 0（`0x4468e2`），`stand` 写 +4、`use_magic` 写 +0x34（`0x446a8c`，状态 7，升级演出 `0x4071e0` 用它）。所以阵亡者在遗言期间与拉伸时都是 `hit` 帧（static-derived）。跳过条件：`+0x80` 有 0x800（已在地图受击态 `0x407230`，收尾每 tick 已画 hit 帧），或 `0x446b60`（live 记录 +0xa0 位 0x20，no_showshape 隐形对象）为真——读法见[地图普攻与受击包](../../static_reverse/original_map_strike.md#1-结论)。
- 像素：511.83 s 那次帝国法师在遗言期间（510.6–511.6 s）从站姿换成宽大白袍铺开的跪姿，随后灵魂升起（runtime-measured，放大截图人工判读）。
- 资源：SHAPEDEF 66 个 `hit` 字段；59 个是独立的 `NNN-P.SHP`（另 068 的 `68-003.SHP`），060／067／100／101 的 hit＝站立帧。导入到 `content/imported/hsl/shared/actor_hit_poses/`（任务 `actor_hit_poses`）。
- 重制落地：`BattleAftermath.show_hit_pose` 在死亡 job 开始（遗言前）用 `ActorRuntime.set_shape_override` 换上 hit 帧，`_dispose` 复原。盘点：全部 61 个走行帧演员键里 59 个有 hit 帧、4 个 hit＝站立帧、2 个（作者关的 102／103，SHAPEDEF 无行）没有——检查 `actor_hit_poses` 守着，新演员不声明就失败。
- 阵亡来源盘点：`ACTION.H` 没有任何"杀死"指令（resource-derived negative-evidence），剧本只有离场删除；所有阵亡都来自战斗回执、都进同一个 `BattleAftermath` 死亡 job（见[原版阵亡处置](../../static_reverse/original_death_disposal.md)的来源表）。

## 3. 遗言选句

- 静态（`0x43ef91..0x43efcb`，玩家过程 `0x4434b2..` 相同）：读 live `+0x14` 整字；整字为 0 → 不弹框；高半字 `+0x16`、低半字 `+0x14` 中为 0 的一半用另一半代替；`0x43efaf` 调 `0x458c10`（原版全局 PRNG，状态初值 0x12345678／0x87654321，与战斗共用），`& 1` 为奇取第二半、为偶取第一半。
- 像素互证：同一种 021 拉爾斯帝國兵，140.99 s 喊「啊---！」（373），193.97 s 喊「拉爾斯帝國萬歲！！」（372）——PLAYERS 021 `dead_message = 372,373` 的两半都出现过（runtime-measured 与 resource-derived 互证）。R6-V2 记的"不弹框"不是 021：它两半都非 0，按上面的读法永远弹框。
- 盘点：66 个 PLAYERS 演员行里 2 句的多数；一半为 0 的真实行 4 个（008 `1825,0`、025、049、064），无遗言 56 个（`content/generated/hsl/combat/aftermath.json` 的 `silent_actors`）。
- 重制落地：`BattleAftermath.choose_dead_message`（结构 static-derived）＋`dead_message_roll`（remake-invented：交锋序号与受害者 id 的字符串散列奇偶；不消耗战斗 RNG、自动对局结果不变、读档同一句）。可替换方案 B：从 PlayLoop 的随机流取一位（更接近原版共用流，但会改变之后全部战斗随机结果）。检查：`run_combat_aftermath_tests.dead_message_choice` 用 021／008／001 三个真实行覆盖三分支。

## 4. 对白框：溶解开合与正文逐行擦出

| 项 | 原版量值 | 等级 | 来源 |
| --- | --- | --- | --- |
| 换说话人 | 旧板溶解收起 21.20→21.52 s（0.32 s），地图露出约 0.08 s，新板溶解展开 21.60→21.89 s（0.29 s）；头像框平均亮度逐帧 2.5–5 的小步（不是一帧硬切） | runtime-measured | `region` 头像框 `step_prev` |
| 收起 | 297.71→298.03 s（0.32 s），同样逐帧小步 | runtime-measured | `region` 对白框 |
| 正文出现 | 名字随板子先出现；第 1 行在板子展开约 0.13 s 后出现，之后每行约 0.1 s，自上而下擦出（亮像素 ≥200 的 4 px 行带依次点亮：第 2 行 24.107→24.207 s 由上到下 4 步；三行消息 22.890／22.973／23.173 s 各行起点） | runtime-measured | `region --bright 200 --band 4` |
| 同一说话人翻页 | 录屏里没有样本 | — | 重制按"新一页重新擦出、板子不溶解"处理（provisional） |

R6-V2 记的"2–6 帧"是块变化 ≥15% 的计数，溶解的每帧变化小，大半帧没过阈值；按逐帧平均步长量是 17–19 帧。

重制前：`BattleDialogue` 一帧出现、一帧消失，正文整段直出（R6-V2 补录 9 个样本全是 1 帧）。
重制后：`BattleDialogue`（战斗对白、开场／剧本、城镇、谢幕共用这一个视图——`BattlePresentation.dialogue_view`、`BattleSceneRuntime` 的 OpeningOverlay、`TownRuntime`、`GameClearScreen` 都实例化它，没有第二个对白视图）新板 0.29 s 溶解展开、换板时旧板留一个无脚本副本 0.32 s 溶解收起后新板才展开、正文用逐行擦出着色器（每行 `LINE_SECONDS` 0.1 s，起点在展开 0.13 s 后）。全部是视觉：消息、页码和 `visible` 立即切换，调用方的输入与逻辑不变。检查：`run_presentation_contract_tests.dialogue_contracts`（消融：擦出高度恒满 → 2 条失败）。

R7-DLG 起节奏改按静态读法（[对白框包](../../static_reverse/original_dialogue_board.md)）：淡入淡出各 16 tick、文字窗裁切 17 px 起每 tick ＋3（本节量到的 0.1 s 一行、0.13 s 起点与 0.29／0.32 s 溶解都是它在 19.4 ms 主机上的样子）、同一说话人翻页是逐行上卷（录屏 399.73–400.53 s 有样本）。本节表格保留为录屏量值。

## 5. 单位高亮：说话人、瞄准目标、当前行动者

| 场景 | 原版量值 | 等级 |
| --- | --- | --- |
| 说话人 | 23.87 s 起说话的一般兵精灵像素从约 (117,111,96) 变到 (153,152,206)（+36,+41,+110 蓝白增色），亮度差 25→49（0.25 s）→20（0.6 s）后保持到消息结束；20.2 s 另一名说话人 20→52（0.57 s）→21（0.9 s）。两次都从消息开始亮起 | runtime-measured（两个样本） |
| 瞄准目标 | 176.7–178.2 s 被瞄准的敌兵约 (183,123,131) 偏粉，亮度差在 28–38 之间约每 0.5 s 起伏一次 | runtime-measured（一个样本，参考帧取不到未瞄准前的原色） |
| 当前行动者 | 139.72–139.77 s 与 140.91 s 雷歐納德约 (138,150,201) 蓝白 | runtime-measured（与灵魂光重叠，provisional） |

重制前：三种都没有（R6-V2 M6–M8）。
重制后：`ActorRuntime.set_highlight(kind, on)` 一个共用接口，色调乘在精灵 `self_modulate` 上（节点 `modulate` 仍归淡出／变暗的主人），同一时刻只显示一种（说话人＞目标＞行动者），亮度在低位与满色之间按周期起伏（说话人／行动者 0.9 s、低位 0.4；目标 0.5 s、低位 0.7）。点亮时机：说话人随 `BattleDialogue.set_speaker_actor` 的消息开始、换人或收起释放；目标＝玩家选目标光标下的合法目标、AI 起手的 target 段受击者；行动者＝玩家选命令期间的当前单位；对白、交锋与结果期间不点。检查：`run_presentation_contract_tests`（周期、优先级、释放）、`run_combat_aftermath_tests`（场景里行动者与目标的点亮；消融：不调 `sync_unit_highlights` → 8 条失败）。**provisional**：颜色与周期都来自一两个样本；原版高亮的绘制过程未读；阵亡者说遗言时是否也亮未量（重制不点）。替换证据：原版对象绘制模式里说话人／选中标志的静态读，或更多录屏样本。

## 6. 仍未做／边界

- 对白框"说话人靠下时放到顶部"保持重制现状（待用户决定）。
- 原版 `hit` 帧在阵亡以外也用：法术通道等 `0x407230` 受击态 60 tick（[地图普攻与受击包](../../static_reverse/original_map_strike.md)），重制由 `MapHitState` 接上。
- 两个跳过条件：no_showshape 由 `ActorRuntime.hide_shape` 常隐精灵满足；已在受击态时重制的 hit 帧已在身上。
- 灵魂时长保留静态读出的 16 tick（0.256 s）；录屏量到 0.27–0.32 s。
