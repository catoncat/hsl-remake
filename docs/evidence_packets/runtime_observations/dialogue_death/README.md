# 对白与阵亡演出：原版录屏三路测量（灵魂飞升与死亡音、hit 帧、遗言选句、对白框开合、单位高亮）

> evidence: runtime-measured: 2026-09-24 原版录屏（605.8 s，可变帧率约 57 fps）按源帧率量的像素轨迹与音轨互相关，2026-09-28 Wine 原版（v1.06，cnc-ddraw 游戏窗截图）第 1 场开场对白与行动菜单、选攻击目标各帧; static-derived: 死亡入口姿势 0x446c40 状态 6、遗言选句 0x43ef91..0x43efcb 的 r2 读法、单位高亮 0x43db70／0x43dcb9 与阵营色 0x407cc0、玩家状态表 0x445758／0x445694 里两处 0x200000 写入各属哪个选格态; resource-derived: SHAPEDEF hit 帧、dead0003.wav · status: live · functions: 0x407cc0, 0x407ec0, 0x40ba20, 0x4145e7, 0x43db70, 0x43dcb9, 0x43ef91, 0x443a00, 0x4442ef, 0x444be4, 0x444bf0, 0x446c40, 0x458c10 · tools: hsl_original_control.py, hsl_video_events.py, run_combat_aftermath_tests.gd, run_original_hsl.sh · updated: 2026-09-28

## 结论

- 原版阵亡：阵亡者遗言期间换成 SHAPEDEF `hit` 帧，遗言框溶解收起后灵魂加法拉伸上升与 `dead0003.wav` 同起；遗言按 live `+0x14` 两半与全局 PRNG 一位选句；对白框逐帧溶解开合、正文逐行擦出（runtime-measured＋static-derived＋resource-derived）。
- 重制 `BattleAftermath`（`show_hit_pose`、`choose_dead_message`）、共用对白视图 `BattleDialogue` 与 `ActorRuntime.set_highlight` 按这些量值与读法实现（runtime-measured 对照）。
- 原版单位高亮：说话人、行动菜单里的当前行动者、以及选攻击目标与选用药／交付格期间（选格里左键误点一次即熄到选格结束）**全场所有单位**按阵营色亮起脉动（我方蓝 80,80,255、敌方粉 255,100,160、其余黄 255,255,80；颜色每 tick 减 5·|p|，p 在 −30..30 循环）；画法是先以该色 engGLASS 半混合、再叠 10/16 加色的原精灵（static-derived＋runtime-measured，§5）。选魔法／绝技目标与选移动格不全场亮；AI 回合没有高亮来源。
- 差异：遗言选句的奇偶来源是重制散列（remake-invented）；高亮已照原版（差异清单 `highlight-colours`），剩重制选魔法／绝技目标时仍全场亮（与攻击共用 attack_select）。

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

**static-derived**（r2／objdump 阅读 `hsl01.exe` sha256 `f0b5f835…`）

| 项 | 原版读法 | 地址 |
| --- | --- | --- |
| 绘制 | 敌我单位每 tick 的空闲尾（敌 `0x442173`、我 `0x445628`）调 `0x43db70(obj)`；它走到 `0x43dcb9`：`+0x80 & 0x100` 或全局 `0x4c1b00 & 0x200000` 时亮，并清 `+0x80` 的 0x100（每帧一次） | `0x43dcb9–0x43dcd7` |
| 说话人 | 对白框过程每 tick 给说话对象（`+0xa8`，无人脸台词）置 `+0x80 \|= 0x100`，所以亮到对白框注销为止 | `0x4145d3–0x4145f0` |
| 全场亮 | `0x4c1b00 \|= 0x200000` 只有玩家状态机两处，敌方过程与剧本不写。玩家状态经 `0x443a00` 字节表 `0x445758` → 指针表 `0x445694` 分派：state 0x50（普通攻击选目标）→ 第 16 项 `0x4442e4`，在 `0x4442ef` 置位；state 104（用药标范围）→ 第 27 项 `0x4448f4`（`0x444915`／`0x444925` 跳 `0x444be4`），state 112（交付标范围）→ 第 32 项 `0x444bc7` 直落 `0x444be4`，两者在 `0x444bf0` 置位并进 105／113。魔法选目标 0x79 → 第 38 项 `0x444ec1`、绝技 0x98 → 第 42 项 `0x445099`、选移动格都不置位。清位 `0x4444e5`、`0x444a67`（用药取消）、`0x444d46`（交付取消）等；105／113 每次左键都在查格之前先清（`0x444947`／`0x444c40`），格子没标记、不是可用对象或 no_attack 时跳 `0x4449bb`／`0x444c9e` 仍停在原态、不再置位，所以误点一次后这次选格剩下的时间只亮行动者与悬停单位 | `0x443a00`、`0x4442ef`、`0x444bf0`、`0x4444e5`、`0x444947`、`0x444c40`、`0x4449bb`、`0x444c9e` |
| 颜色 | 出生 `0x407cc0` 按 `0x40ba20` 侧字（live `+0x28 & 0x870000`）写 `+0x3a..+0x3c`：恰为 0x10000 → (80,80,255)；恰为 0x20000 → (255,100,160)；其余 → (255,255,80) | `0x407de6–0x407e4e` |
| 脉动 | 字 `+0x38` 每次亮时 +1，>30 回 −30（61 tick 一周）；三通道各减 `5·\|p\|`、下限 0，按 RGB565 打包 | `0x43dcdd–0x43dd34` |
| 画法 | 同形状在单位上方（z＋1）画两次：模式 `0x40000000`（engGLASS）带上述颜色，再以 `0x24000000`（engADDCOLOR_MIX）层级 10 | `0x43dd29–0x43dda6` |

**runtime-measured**（2026-09-28 Wine 原版，第 1 场开场对白→行动菜单→攻擊，`hsl_original_control.py` 游戏窗截图，存档 sha 前后不变）

| 场景 | 原版帧 | 等级 |
| --- | --- | --- |
| 说话人 | 雷歐納德说话时整身蓝白、连拍 5 帧亮度起伏；换成一般兵说话后雷歐納德恢复原色、一般兵变蓝 | runtime-measured |
| 画法拟合 | 同一动画帧的亮／不亮像素对：`(o + C)/2 + o·10/16`（C＝蓝色减 5·\|p\|）每像素三通道平均误差 11.4–12.7（RGB565 量化级），层级扫 6／8／10／12／16 以 10 最优；纯色替换与加法两种画法误差都更大 | runtime-measured |
| 行动菜单 | 只有当前行动者（雷歐納德）亮，其余我方与敌方原色 | runtime-measured |
| 选攻击目标 | 点攻擊后全场单位都亮：我方蓝、敌方粉，光标下的单位没有额外标记 | runtime-measured |

录屏旧样本（说话一般兵 (117,111,96)→(153,152,206)、被瞄准敌兵偏粉、行动者蓝白）与上述读法相容。

## 重制接线

- `BattleAftermath.show_hit_pose`：死亡 job 开始（遗言前）用 `ActorRuntime.set_shape_override` 换 hit 帧，`_dispose` 复原；hit 帧导入 `content/imported/hsl/shared/actor_hit_poses/`（任务 `actor_hit_poses`：61 个走行帧演员键里 59 个有 hit 帧、4 个 hit＝站立帧、作者关的 102／103 无行）。拉伸按 16 tick（0.256 s）。
- `BattleAftermath.choose_dead_message`（结构 static-derived）＋`dead_message_roll`（remake-invented：交锋序号与受害者 id 的字符串散列奇偶；不消耗战斗 RNG，读档同一句）。替换方案：从 PlayLoop 随机流取一位（更接近原版共用流，但改变之后全部战斗随机结果）。
- `BattleDialogue`（战斗对白、开场／剧本、城镇、谢幕共用；`BattlePresentation.dialogue_view`、OpeningOverlay、`TownRuntime`、`GameClearScreen` 都实例化它）：溶解开合与逐行擦出为纯视觉，消息、页码与 `visible` 立即切换。
- `ActorRuntime.set_highlight(kind, on)`：三种来源画法相同——精灵换着色器 `(src + C)/2 + src·10/16`，C 取 `highlight_side`（`BattleSceneStage.highlight_side`＝`side_mask | player_mode & 0x800000`）的阵营色减 5·|p|，脉动字每原版 tick +1 在 −30..30 循环、跨高亮保留。说话人随 `BattleDialogue.set_speaker_actor`；`BattleSceneOverlays.sync_unit_highlights`：`attack_select`（攻击／魔法／绝技选目标）与道具用药／交付选格期间全场可见单位都亮（选格用 `BattleSceneMenus.item_pick_lit`：进选格置位，每次左键在查格前清、误点后不再置），行动者＝选命令期间的当前单位；对白、交锋、结果与 AI 回合不点。没有 PlayLoop 单位的剧情演员（剧情场景的 EVEF 敌方过程对象与脚本插入对象）按原版取色：`0x40ba20` 读的是对象记录 `+0x28`，剧情演员同样由构造器 `0x407ec0` 写（PLAYERS 模式 → obj_Data9 换边 → obj_X1 覆盖，见 [阵营位](../../static_reverse/original_player_mode_sides.md)），`story_scene.py` 把它写进条目 `player_mode`，`BattleSceneStage.story_cast_player_mode` 带进视图；`obj_Story_PlayerN` 槽位安装的主角不带此字、按我方色（static-derived）。
- 阵亡以外的 hit 帧（`0x407230` 受击态 60 tick）由 `MapHitState` 接上。

## 复现

录屏不可再生。高亮 Wine 帧：`tools/run_original_hsl.sh` 启动（不换存档） → 開始新故事 → 空格跳片头 → 对白中截图 → 空格到行动菜单 → 点攻擊 (308,210)；帧与拟合脚本在 `ignored/highlight/`（不入库）。重制侧 `tools/godot.sh --headless --script res://tests/run_combat_aftermath_tests.gd`（`dead_message_choice` 等）。

## 边界

- 高亮：engGLASS 的像素内核未逐条读，画法 `(dst + C)/2` 由 Wine 帧拟合；重制选魔法／绝技目标时仍全场亮（原版 0x79／0x98 不置位；重制与攻击共用 `attack_select`，改动要动现有演出测试）；剧情场景里 `actSetPlayerMode`（`0x450710`）中途改阵营时剧情演员的高亮色不跟（重制视图只取构造时的字）；阵亡者说遗言时说话人高亮不亮（遗言走构造器、`+0xa8` 是阵亡者本身，是否亮未量，重制不点）。替换证据：engGLASS 内核的静态读。
- 灵魂时长保留静态读出的 16 tick（0.256 s）；录屏量到 0.27–0.32 s，差值在帧率与 tick 抖动量级内。
- 同一说话人翻页在本段录屏的阵亡片段外才有样本（见 original_dialogue_board）。
