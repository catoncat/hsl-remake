# 第二轮：第一章真实可玩（决策记录）

起点：收口冲刺收口 `0c88ad6d`（[收口冲刺](CONSOLIDATION.md)）。本文件是第二轮的决策记录与 oracle；当前能力与唯一 Next steps 仍在 [PROJECT](PROJECT.md)，lane 协议见 [AGENTS「Lane 协议」](../AGENTS.md#lane-协议) 与 [任务书模板](templates/lane_brief.md)。

## 1. 为什么是"真实可玩"

量得的现状（`0c88ad6d`）：

- `content/battles/campaign.json` 注册 127 场正式战斗（主线／支线 49 ＋ 遭遇战 78）、22 个剧情场景、结局分派；41 个主线关的 `status` 全部是 `product-opening-source-adapted`，胜负／增援／事件由 `WinfailScenarioRules` 从 seed 实时解释（`scenario_rules.events` 数据层为空是设计，不是缺口）。
- **没有一场战斗被真实打过**：sweep（127 场）与 explorer（全程 57 场景）都用 `tests/support/BattleForceWin.gd` 秒杀全部敌军过关。tests/README 自己写明：通用夹具"清掉 fail status、护住受控队伍，因此它证明不了开场武装的胜负条件是否会立刻成立"。规则死路（软锁、无人可动、AI 永不结束、胜负条件永不成立）目前只能靠人玩到才发现。
- 唯一的端到端剧情测试 `run_story_mode_explorer_tests`（约 20 分钟，不在门禁）在 P3c lane 的基线 `376a688d` 上观察到 `STORY_MODE_EXPLORER_FAIL outcome=exhausted`，而 tests/README 记录 2026-09-20 早些时候 PASS（57 场景、GameClear）——要么冲刺期间回归，要么该测试对负载敏感；两种都不能接受。
- 用户已实机打通第一战（user-confirmed 2026-09-20）；第一章其余关卡没有任何实机或自动的真实对局证据。

第一性原理：这个项目的产品是"能玩的第一章"，不是"能通过夹具的第一章"。冲刺把门禁做到 2 分钟，正是为了现在能承受得起**真实对局**这种重验证。

## 2. 目标与 oracle

| # | 目标 | oracle（可当下核实） |
| --- | --- | --- |
| R0 | explorer 回绿并进"深门" | `tools/verify.sh --deep`（新档：快门 ＋ explorer ＋ 自动对局 sweep，波末与阶段收口跑）`STORY_MODE_EXPLORER_PASS game_clear=true`；README 里的到达场景数≥57；失败原因定位到提交或负载并修掉 |
| R1 | **自动对局**：无夹具、用现有 AI 驱动玩家侧，把每场注册战斗打到自然胜负 | 新套件 `run_autoplay_sweep_tests.gd`：127 场每场输出 `level outcome=win|fail rounds=N seconds=S`；oracle 是"**没有一场以 dead_end 结束**"（超回合上限、无合法行动、异常、胜负条件永不成立都算 dead_end）；胜负结果本身不作断言（AI 打 AI 输赢皆可），但按关记录成 evidence packet |
| R2 | 死路归零 | R1 发现的每个 dead_end：定位到规则／数据／脚本解释，修复进 play loop，或以 negative-evidence／provisional 记入对应证据包并在 autoplay 里标 `known`（数量必须在报告里给出并趋零） |
| R3 | 功能缺口接续 | PROJECT Next steps 1（技能侧边界）、2（转职收尾）按项做完或标 provisional；每项独立 lane |
| R4 | 管线遗留 | CONSOLIDATION §10 的 1（删 156 个垫片）、2（run_all 按耗时分片）、4（schema inputs／story_corpus 散文） |
| R5 | 用户判断项 | D1 精灵朝向审核表、D2 兩棲族部落 原生观察（Wine）——进决策清单，不阻塞 |

完成标志：R0–R2 全部 oracle 成立、R3 每项有回执、R4 做完、全门 VERIFY_PASS；PROJECT Next steps 只剩 R5 与"仍独立未接"的机制。

## 3. 不动的东西

- 沿用冲刺 §3：game/sim 细粒度规则语义与测试断言内容不因"让 autoplay 过"而改；autoplay 发现的问题按证据修，修不了标 provisional。
- `BattlePlayLoop` 仍是唯一可变战斗状态所有者；autoplay 只通过它已有的命令入口（`IMPLEMENTED_COMMANDS`）驱动玩家单位，不新增第二套控制通道。
- 不 push。

## 4. 工作协议

冲刺 §5 原样，外加：

- 长测试（explorer、autoplay sweep）只进 `--deep`，快门保持 ≈2 分钟；deep 跑在负责人工作树、结果行进回执。
- autoplay 的每关结果写成生成数据（`content/generated/hsl/development/autoplay/` 或 evidence packet），由 `hsl check` 守着，不是日志。
- lane 并发按**量得的资源**准入，不设固定条数：本机 10 核（4P＋6E）／16 GB。派新 lane 前看 `uptime`、`memory_pressure`、`df`：1 分钟 load < 8 且系统空闲内存 > 40% 且磁盘 ≥ 20 GB 才派；每条 lane `HSL_VERIFY_JOBS=3`（一次门禁峰值约 3 核／1.5 GB，持续 1–3 分钟，占 lane 生命周期 <10%）；负责人自己的门禁在有 lane 时用 `HSL_VERIFY_JOBS=4`。冲刺时的"≤3"是 load 109 事故后的保守常数，不是测量。

## 5. 决策清单（需用户）

| # | 事项 | 建议 |
| --- | --- | --- |
| D1 | 42 名演员／上位行 `sprite_facing` 人眼判定（继承） | **关闭（消融）**：该字段是无消费者的元数据（运行时不读，玩家不可见），审核不产生任何玩家结果；保持 provisional 标记，等有消费者（如按朝向镜像切入）时再由 lane 用解码帧对照判定，不占用用户时间 |
| D2 | 兩棲族部落 第二次转职后菜单的原生观察 | **关闭**（R9 用生成的存档载入原版两分钟看完：根菜单 154/155/156/145、事件 153、集會場 三位说话人、雷歐納德 終焉劍使 Lv24——runtime-measured；`teCheckJobUp2` 触发本身仍 provisional，因为转职写入由生成器预置。见 [原版存档格式](evidence_packets/static_reverse/original_save_format.md)） |
| D4 | autoplay 发现的"原版也如此"的死路：**未出现**——唯一一类死路（遭遇战 fail 段未解析）是重制缺陷，已修 | 关闭 |
| D5 | 原生 30–34 段遭遇战全灭观察 | **关闭**（R8 有界原生执行代替：见下「负责人已决」两行；[check_player 探针](evidence_packets/static_reverse/original_check_targets.md)） |
| D6 | 53 关 winfail 台词的脸 | **关闭**（static-derived：对白框 `0x414280` 取说话对象自身记录 `+0x5c` picture → FACE0001；029 是过场公主，旧手表有误） |
| D7 | 闇瑩蝶舞 SP08 仅 3 帧（PAK 内缺 40 个成员）与 obj_Special51_05 无定义 | 资源事实（negative-evidence）；若要看原作怎么播，用 R9 的存档生成器造「持有该绝技」的局面即可，不再需要用户通关。低优先 |

### 负责人已决（本轮，不需用户）

| 决策 | 依据 | 记录处 |
| --- | --- | --- |
| 37 关战斗内转职目标 052 → **017 邪獸** | 原函数链 0x4348f0→0x45dbe1→obj_Data7→PLAYERS 816（static-derived） | [37 关 token](evidence_packets/static_reverse/original_level37_tokens.md)、机制矩阵 |
| `actCheckPlayer 1 <已绑定但本战未上场>` → 不成立（未上场 ≠ 阵亡） | R8 有界执行：原版 -1 路径**成立**（找不到即算阵亡，不读 HP），但原版遭遇战按注册表 `0x4c4360` 装人、注册只由 `actDeletePlayerCode` 清除、029–034 从不调用 → 被囚的 雷歐納德 在原版仍被装进 5NN，「已注册未上场」在原版不可达 | **remake rule**（补偿 carry 模型），[目标计数包 §R8](evidence_packets/static_reverse/original_check_targets.md) |
| 重制显式规则 `party_wiped`：上场玩家单位非空且全部阵亡、无 win 状态 → 判负（最低优先级） | R8 negative-evidence：`0x4c1b90` 六处读者无一判负，判负只经 fail 扫描；无武装 fail＋无玩家时 80 条指令正常返回——原版也会敌军无限行动。用户授权的重制改善 | 同上 ＋ 机制矩阵 |
| 30–34 段遭遇战**不**照搬原版「被囚的 雷歐納德 仍上场」 | 原版是注册表未清的疏漏（剧情上他被关押）；重制按 carry 只装在队成员，配合上一行规则 | 本文件；[目标计数包 §R8](evidence_packets/static_reverse/original_check_targets.md) |
| 阵亡结算／绝技帧／台词头像缺失 → 数据层显式声明（`silent_actors`／`special_frames: []`／派生 portraits），运行时报错但不软锁 | AGENTS「必要输入缺失应明确失败，不静默 fallback」 | [表现层软锁包](evidence_packets/runtime_observations/presentation_soft_locks/README.md)、PRESENTATION.md |
| Jev（TypeSafe）不进自动对局／运行时决策；留给开发流水线的文本判断 | 深门要确定性与离线；0.7–1.5 s/次×数万决策不可行；候选带数字后代码打分已足够 | 本文件 |

## 6. 进度记录

| 阶段 | 收口提交 | 门禁 | 备注 |
| --- | --- | --- | --- |
| R0 explorer ＋ R4-1 垫片 | `1a648e1c`（R0）／见本提交（R4） | 深门 **135 s** VERIFY_PASS（explorer 22 s，scenes=57 game_clear=true）；快门 126 s | explorer 失败根因＝harness 竞态（遭遇骰覆盖已武装战斗，~35%），非回归；`--deep` 档落地；152 个垫片删除（tools/hsl_*.py 185 → 33） |
| R4 全部 | 见本提交（R4-rest 合并） | 快门 228 s VERIFY_PASS（3 lane 并行，jobs=4） | §10 的 1／2／4 全部落地：垫片删除、run_all 按耗时装箱（四片 39/37/24/38 s）、schema inputs 308 条、story_corpus 散文入包。**R4 收口** |
| R1 自动对局 | `ad15c0c4` | 快门 259 s | 127 场无夹具首跑：win 46／fail 48／dead_end 33（一类）；SCRIPT ERROR 17,982 行全部是产品表现层缺陷（三处） |
| R3 技能侧＋转职收尾 | `4bc1e17b`／`3861f6af` | 快门 203／176 s | 技能侧 3/4 static-derived（特效素材量成范围）；转职六项含 37→017 的重大更正 |
| R2 死路归零 | `77239a3a`（表现）／`6b8d0307`（规则） | 快门 244／171 s；lane 深门 **1260 s** VERIFY_PASS | SCRIPT ERROR → 0；dead_end 33 → **0**；四次全量 sweep 逐字相同（`HSL_RNG_SEED` 缝）；遭遇战 win 45→21（雷歐納德 先死的局按脚本改判负） |
| R6 更聪明的驾驭器 | `02427732` | 快门 310 s | greedy 0/60 → scored 3/60（全在 1 关）；保留为探索工具，不据此声称主线可通；Jev 分支撤销 |
| R7 绝技专属特效 | `d37011bd` | 快门 180 s | 24/24 opcode、495 帧＋59 WAV、借用行 0；SP08 缺帧为原 PAK 事实 |
| **第二轮收口** | 见本提交 | 深门 **VERIFY_PASS mode=deep 711 s**（explorer 37 s；sweep 552 s：battles=127 win=22 fail=105 dead_end=0，results.json 逐字不变）；全门 **VERIFY_PASS mode=full seconds=312**（jobs=8）；0 SCRIPT ERROR | R0–R4 oracle 全部当下可核实：explorer 绿、127 场 dead_end=0、Next steps 1／2 逐项 done 或 provisional、§10 1／2／4 落地 |
| 第三轮起步 R8 probe | `15d93977` | 快门 288 s | 有界原生执行：-1 路径在原版成立但「已注册未上场」在原版不可达（被囚的 雷歐納德 仍被装进 5NN）→ 重制规则保留为 remake rule；全灭 negative-evidence；53 关脸 FACE0001。D5／D6 关闭 |
| 第三轮起步 R9 save | 见本提交 | 深门 **VERIFY_PASS mode=deep seconds=1140**（AUTOPLAY_SWEEP_PASS battles=127 win=22 fail=105 dead_end=0 seconds=900.6，results.json 逐字不变）；0 SCRIPT ERROR | 原版存档编解码器（LZW 变体＋校验和，样本 round-trip 逐字节相同）＋「二次转职站在 兩棲族部落 门口」预设存档，Wine 载入验证；D2 关闭。其他成员 live 记录合成留作下一 lane |

## 7. 第三轮：第一章机器通关（2026-09-21 起）

第二轮证明了 127 场战斗"不会卡死"；第三轮要证明"主线能打通"——由机器人而不是人。主线 49 场 greedy 0／60、scored 3／60 的根因是驾驭器不会魔法／绝技，不是规则。

| 项 | 内容 | oracle |
| --- | --- | --- |
| R10 驾驭器接魔法／绝技 → 整章机器人通关 | `AutoplayBrain` 候选加 `magic:<spell>@<target>`／`special:<skill>@<target>`（只经 PlayLoop 已实现命令；数字用现有 preview／forecast，不重写公式）；然后把 explorer 的选路与真打战斗、carry 成长接成一条链，每场允许换种子重试 ≤K 次（K 记入报告） | `AUTOPLAY_BRAIN_COMPARE` scored 胜场显著高于 3／60；`CHAPTER_AUTOPLAY` 报告 game_clear，或逐关列出不可赢关及原因分类（规则缺陷／平衡／驾驭器）；进 `--deep` |
| R11 存档生成器补其他成员 | 运行时 dump 一次 live 记录（`*0x4c1bc8`）→ 合成任意成员；预设 ≥3；Wine 载入验证；原生触发 `teCheckJobUp2` | `ORIGINAL_SAVE_PRESET_PASS` ×3 且 slots>0；`original_town_job_up.md` 的触发行升 runtime-measured |
| R12 规则小项 | `0x40c770` MAGIC 桶 5／7「有用」时无条件接受；`0x40dd80` 进攻绝技桶回放；支援绝技结果文字 | 各自 static-derived 落地（规则套件断言随证据改）或 negative-evidence；机制矩阵更新 |
| R13 用户项与协议 | D1 按消融关闭（无消费者的元数据不审核）；lane 模板加「验证过就提交」（已做） | 本文件 §5／模板 |

约束不变（§3／§4）。收口：`--full` ＋ `--deep` 绿，§6 记回执，main 快进。深门耗时 711 s／1140 s 的波动来自机器争用（深层只有两个进程，`--jobs` 不影响它），不是代码变慢。

### 7.1 收口回执（2026-09-21）

| 项 | 结果 | 提交 |
| --- | --- | --- |
| R10 | scored 3／60 → 6／60（未达显著）；`CHAPTER_AUTOPLAY game_clear=false`，战役起点卡 52、歐姆村起点卡 2；逐关分类交 R14 核实——"平衡"分类被用户否决（不买装备、不换装、只护主角的玩家在任何策略游戏都打不过），改派 R15 前瞻＋经济循环 | `53725bc8` |
| R11 | 四个预设 Wine 载入；原生触发 `teCheckJobUp2`，town-14 写入与重制写入表（当时 `TownEventRules.SECOND_TIER_TOWN_WRITES`，S6f 起为 `content/world/town_job_up_writes.json`）逐字节相同 → runtime-measured | `98df448c` |
| R12 | 三项 static-derived 落地（AI 有用行无条件接受、进攻绝技桶回放、「+N HP」） | `8035f740` |
| R13 | D1 按消融关闭；模板改 | `c6c07b46` |
| R14（追加） | 用生成存档在原版观察 17 关：敌军一致，**友军 NPC 行为是规则缺陷** | `5fd08366` |
| R16（追加） | EVEF 逐单位实例字（wait_round 535／fixed_point 12／物品 20，70 关 569 单位）接入运行时；52 关皇帝 wait 7 与用户实玩一致（user-confirmed）；sweep win 23→27 | `805d9721` |
| R17（追加） | 149 模块 provenance 头进门禁；remake-invented 141→140 格（[PROVENANCE](PROVENANCE.md)） | `5918a50a` |
| R18（追加） | 升級／獲得物品面板按原版窗体代码重做；用户验收路线两份；待用户拍板：逐件丟棄命令 | `f33369ce` |
| R15 | 前瞻机器人＋进城买装备＋两个诊断开关：属性 1.0 两种机器人 5 场全输、1.5 倍打分 4 胜／前瞻 3 胜——机器人≈"需要 1.5 倍属性才能赢"的玩家，前瞻没带来质变；整章卡 53（52 已过） | `b2309cda` |
| R21 | 字段覆盖审计：原版 742 字段，读 500／记录 80／未读 42，P1 疑点两项（逐单位阵营位、HP 加值） | `13bda1bb` |
| R22 | 逐单位 `player_mode`／`object_hit_point` 接入；侧别位计数（0x407660／0x407720）；未读 42→40；玩家可见后果 provisional（替换路线：Wine 6 关观察士兵是否攻击村民）；深门于 `d50dd40f` 补跑：`AUTOPLAY_SWEEP_PASS battles=128 win=28 dead_end=0`、`CHAPTER_AUTOPLAY stuck_at=53` | `d562b6cb` |
| R24 | 原版逻辑 tick：设计 16 ms（0x45f4b9，1000/60），本机 Wine 实测 19.4 ms（GetTickCount 步进粗）；36 格时序映射 A21／B12／C15；负责人决定重制以 16 ms 为目标（R26 执行） | `d50dd40f` |

未收口、转入 [第四轮](SEQUEL_READINESS.md) 与其余 lane：R23（12 关 AI 异常＋17 关护送对照，跑中）、R25（provisional 行静态烧减，跑中）、R26（tick 时序换算，跑中）；"主线能打通"仍未证明——第三轮的结论是**阻碍它的每一项都已定位并有 lane**，而不是通关。
