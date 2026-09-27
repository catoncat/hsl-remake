# 对白与阵亡演出：原版录屏三路测量（灵魂飞升与死亡音、hit 帧、遗言选句、对白框开合、单位高亮）

> evidence: runtime-measured: 2026-09-24 原版录屏（605.8 s，可变帧率约 57 fps）按源帧率量的像素轨迹与音轨互相关; static-derived: 死亡入口姿势 0x446c40 状态 6、遗言选句 0x43ef91..0x43efcb 的 r2 读法; resource-derived: SHAPEDEF hit 帧、dead0003.wav; provisional: 说话人／目标／行动者高亮的颜色与脉动只来自这一份录屏 · status: live · functions: 0x43ef91, 0x446c40, 0x458c10 · tools: hsl_video_events.py, run_combat_aftermath_tests.gd · updated: 2026-09-27

## 结论

- 原版阵亡：阵亡者遗言期间换成 SHAPEDEF `hit` 帧，遗言框溶解收起后灵魂加法拉伸上升与 `dead0003.wav` 同起；遗言按 live `+0x14` 两半与全局 PRNG 一位选句；对白框逐帧溶解开合、正文逐行擦出（runtime-measured＋static-derived＋resource-derived）。
- 重制 `BattleAftermath`（`show_hit_pose`、`choose_dead_message`）、共用对白视图 `BattleDialogue` 与 `ActorRuntime.set_highlight` 按这些量值与读法实现（runtime-measured 对照）。
- 差异：遗言选句的奇偶来源是重制散列（remake-invented）；高亮颜色与周期只来自一两个样本（provisional，差异清单 `highlight-colours`）。

## 证据

### 方法

- 录屏：`录屏2026-09-24 中午12.03.22.mov`（原版录屏，私有档案，不入库），游戏区 `crop=1280:960:112:140`，缩到 640×480 逻辑像素；音轨起始 0.177 s（ffprobe），下文时刻为视频 PTS 秒。
- 像素：`tools/hsl_video_events.py region`——逻辑框按源帧率逐帧量相对参考帧的变化像素（外框、质心、平均亮度差、平均颜色、逐行带计数、亮像素行 `bright_rows`）、相邻帧平均步长 `step_prev`（溶解＝多帧小步，硬切＝一帧大步）与亮度周期。
- 声音：`tools/hsl_video_events.py audio`——10 ms 包络起点与候选 WAV 的归一化互相关（NCC）最佳位置。

### 1. 阵亡的灵魂飞升与死亡音

| 项 | 原版量值 | 等级 |
| --- | --- | --- |
| 声音 | `wav/dead0003.wav`（PLAYERS `sound_dead`，021／023／024／026 及己方同声）全片 15 处命中：108.55、140.99、193.97、206.18、253.25、264.08、275.59、286.86、298.09、311.46、338.02、371.97、449.57、466.47、511.83 s，NCC 0.39–0.51；204 个已导入 WAV 里长音最高分，次高 0.31 | runtime-measured＋resource-derived |
| 声画时刻 | 298.09：灵魂第一帧 298.027 s，声音起点 298.094 s（晚 4 帧，录屏音画延迟量级） | runtime-measured |
| 顺序 | 遗言框（296.6–297.7 s）→ 框溶解收起（297.71→298.03 s）→ 灵魂＋声音同起 → 消失后 EXP／$ 浮字 | runtime-measured |
| 时长 | 298.09：298.027→298.30 s（0.27–0.32 s，16–19 帧）；140.99：140.915→141.18 s（0.28 s） | runtime-measured（亮像素掩码 `--brighter`，阈值 24） |
| 上升 | 亮像素质心 y≈164 → y≈108（≥56 px，顶边被画面上缘截断）；140.99 升 47 px | runtime-measured |
| 颜色 | 第一帧平均 +86 亮度（RGB 约 192,166,149 偏暖白），随后线性变暗到消失 | runtime-measured |
| 规则 | 遗言关闭后 16 tick 纵向缩放 +0.25/tick、层级 16→0、加法混合，死亡音与拉伸同起 | static-derived（[original_death_disposal](../../static_reverse/original_death_disposal.md)） |

### 2. 死亡入口的姿势：hit 帧（NNN-P）

- static-derived：死亡入口 `0x43ef36..`／`0x44347e..` 调 `0x446c40(actor, 方向, 6, 2)`；`0x446c40` 按状态查跳表 `0x446d08`，状态 6（`0x446cc4`）取 SHAPEDEF 记录偏移 0 的单个 shape、帧数 1；解析器 `0x4468b5` 把 `hit` 写到偏移 0（`0x4468e2`）、`stand` 写 +4、`use_magic` 写 +0x34（`0x446a8c`，状态 7，升级演出 `0x4071e0` 用它）。跳过条件：`+0x80` 有 0x800（已在受击态 `0x407230`），或 `0x446b60`（live `+0xa0` 位 0x20，no_showshape）为真（[original_map_strike](../../static_reverse/original_map_strike.md#1-结论)）。
- runtime-measured：511.83 s 帝国法师在遗言期间（510.6–511.6 s）从站姿换成白袍铺开的跪姿，随后灵魂升起（放大截图人工判读）。
- resource-derived：SHAPEDEF 66 个 `hit` 字段，59 个是独立 `NNN-P.SHP`（另 068 的 `68-003.SHP`），060／067／100／101 的 hit＝站立帧；`ACTION.H` 没有「杀死」指令（negative-evidence），剧本只有离场删除，所有阵亡都来自战斗回执。

### 3. 遗言选句

- static-derived（`0x43ef91..0x43efcb`，玩家过程 `0x4434b2..` 相同）：读 live `+0x14` 整字，为 0 不弹框；高半字 `+0x16`、低半字 `+0x14` 中为 0 的一半用另一半代替；`0x43efaf` 调 `0x458c10`（全局 PRNG，状态初值 0x12345678／0x87654321，与战斗共用），`& 1` 为奇取第二半、偶取第一半。
- runtime-measured 与 resource-derived 互证：同一种 021 拉爾斯帝國兵 140.99 s 喊「啊---！」（373），193.97 s 喊「拉爾斯帝國萬歲！！」（372）——PLAYERS 021 `dead_message = 372,373` 两半都出现。
- 盘点：66 个 PLAYERS 演员行里两句的占多数；一半为 0 的 4 个（008 `1825,0`、025、049、064），无遗言 56 个（`content/generated/hsl/combat/aftermath.json` 的 `silent_actors`）。

### 4. 对白框溶解开合与正文擦出

| 项 | 原版量值 | 等级 |
| --- | --- | --- |
| 换说话人 | 旧板溶解收起 21.20→21.52 s（0.32 s），地图露出约 0.08 s，新板溶解展开 21.60→21.89 s（0.29 s）；头像框平均亮度逐帧 2.5–5 小步 | runtime-measured（`step_prev`） |
| 收起 | 297.71→298.03 s（0.32 s），逐帧小步 | runtime-measured |
| 正文出现 | 名字随板子先出现；第 1 行在展开约 0.13 s 后出现，之后每行约 0.1 s，自上而下擦出（第 2 行 24.107→24.207 s 4 步；三行消息 22.890／22.973／23.173 s 各行起点） | runtime-measured（`--bright 200 --band 4`） |

块变化 ≥15% 的帧计数只得 2–6 帧，因为溶解每帧变化小；按逐帧平均步长是 17–19 帧。静态读法（淡入淡出各 16 tick、擦出 3 px/tick、同一说话人逐行上卷）见 [original_dialogue_board](../../static_reverse/original_dialogue_board.md)，上表是它在 19.4 ms tick 主机上的样子。

### 5. 单位高亮

| 场景 | 原版量值 | 等级 |
| --- | --- | --- |
| 说话人 | 23.87 s 起说话的一般兵像素从约 (117,111,96) 变到 (153,152,206)（蓝白增色），亮度差 25→49（0.25 s）→20（0.6 s）后保持到消息结束；20.2 s 另一名说话人 20→52（0.57 s）→21（0.9 s）；两次都从消息开始亮起 | runtime-measured（两个样本） |
| 瞄准目标 | 176.7–178.2 s 被瞄准的敌兵约 (183,123,131) 偏粉，亮度差 28–38 间约每 0.5 s 起伏一次 | runtime-measured（一个样本） |
| 当前行动者 | 139.72–139.77 s 与 140.91 s 雷歐納德约 (138,150,201) 蓝白 | runtime-measured（与灵魂光重叠） |

## 重制接线

- `BattleAftermath.show_hit_pose`：死亡 job 开始（遗言前）用 `ActorRuntime.set_shape_override` 换 hit 帧，`_dispose` 复原；hit 帧导入 `content/imported/hsl/shared/actor_hit_poses/`（任务 `actor_hit_poses`：61 个走行帧演员键里 59 个有 hit 帧、4 个 hit＝站立帧、作者关的 102／103 无行）。拉伸按 16 tick（0.256 s）。
- `BattleAftermath.choose_dead_message`（结构 static-derived）＋`dead_message_roll`（remake-invented：交锋序号与受害者 id 的字符串散列奇偶；不消耗战斗 RNG，读档同一句）。替换方案：从 PlayLoop 随机流取一位（更接近原版共用流，但改变之后全部战斗随机结果）。
- `BattleDialogue`（战斗对白、开场／剧本、城镇、谢幕共用；`BattlePresentation.dialogue_view`、OpeningOverlay、`TownRuntime`、`GameClearScreen` 都实例化它）：溶解开合与逐行擦出为纯视觉，消息、页码与 `visible` 立即切换。
- `ActorRuntime.set_highlight(kind, on)`：色调乘在精灵 `self_modulate`，同一时刻只显示一种（说话人＞目标＞行动者），亮度按周期起伏（说话人／行动者 0.9 s、低位 0.4；目标 0.5 s、低位 0.7）；说话人随 `BattleDialogue.set_speaker_actor`，目标＝选目标光标下的合法目标与 AI 起手受击者，行动者＝选命令期间的当前单位；对白、交锋与结果期间不点。
- 阵亡以外的 hit 帧（`0x407230` 受击态 60 tick）由 `MapHitState` 接上。

## 复现

不可再生：原版侧唯一记录。重制侧 `tools/godot.sh --headless --script res://tests/run_combat_aftermath_tests.gd`（`dead_message_choice` 等）。

## 边界

- 高亮颜色与周期来自一两个样本；原版高亮的绘制过程未读；阵亡者说遗言时是否也亮未量（重制不点）。替换证据：原版对象绘制模式里说话人／选中标志的静态读，或更多录屏样本。
- 灵魂时长保留静态读出的 16 tick（0.256 s）；录屏量到 0.27–0.32 s，差值在帧率与 tick 抖动量级内。
- 同一说话人翻页在本段录屏的阵亡片段外才有样本（见 original_dialogue_board）。
