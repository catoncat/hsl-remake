# 并行协作入口

用户于 2026-09-11 17:17:58 UTC 明确授权两条现有对话并行推进，并要求通过仓库文件交流，不再由用户转述。本次授权是 AGENTS.md 默认单线程规则的具体例外，不是自动增加 worker 或 worktree 的授权。

用户于 2026-09-17 16:45 UTC（本地 2026-09-18 00:45）再次授权：presentation 线由 pi 会话 `01a0b032-5d7e-7637-a30d-75cf31793302` 接续，主线为「广度」——第二战／战役推进与演出补全；source-research 线继续「原作机制深度」。接续线获准使用独立工作树 `~/.pi-worktrees/hsl-presentation`（分支 `presentation-line`）；每个 slice 验证通过后由该线在 main 工作区执行 `git merge`，只带自己的文件，git 拒绝覆盖对方未提交改动时该线等待，不 stash／reset／clean。source-research 继续在 main 工作区直接提交。两线仍是仅有的两条授权线，其他 Agent 不得据此再增加工作树。2026-09-18 用户另授权 presentation 线并行多任务：该线可在自己权限下开子工作树（`~/.pi-worktrees/hsl-pl-*`，分支 `pl/*`，见 [P-022](docs/collaboration/presentation.md)），子工作树只合并回 `presentation-line`，不直接接触 main，也不构成新的授权线。

本文件只维护两条已授权对话的写入协议；旧 P-0xx／SR-0xx 的认领与回执分别在 [presentation 留言](docs/collaboration/presentation.md)和 [source-research 留言](docs/collaboration/source-research.md)，**读取各文件末尾最新的 CLAIM／收口，勿把过去的 READY 当现役任务**。当前产品能力与唯一优先级看 [PROJECT](docs/PROJECT.md#next-steps)，提交与验证看 Git。用户另授权负责人按 [lane 协议](AGENTS.md#lane-协议)派独立 worktree；那是已登记任务的执行例外，不等于新增第三条长期对话线。用户既存的 detached Codex worktree 仍为他人改动，禁止代清理。

**2026-09-25 第七轮「照原版补齐演出与走位」**（负责人 pi 会话 `01a0d1a3`；lane 同模型 `PH/claude-opus-5-5`、thinking high；用户定 3–4 路并行，门禁并行度 3）：起因——用户实玩指出第一关走位、章节标题卡动画等多处与原版不同；负责人盘点发现 game/ 170 个模块里 62 个的画面位置或时间标着"自己定的／暂定"，这些只记在代码头与证据包里，从未汇总进待办，此前"剩余量不大"的汇报因此偏乐观。基线 main `032a5470`；任务书与共用协议在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-briefs/R7-*.md`，报告落 `ignored/lane-reports/R7-*.md`。

| lane | 范围（玩家看到的问题） | 状态 |
| --- | --- | --- |
| INV parity-inventory | 原版 vs 重制差异总清单：代码头的"自己定的／暂定"、证据包"未复原／未读"、录屏对账 13 类，逐条写玩家看到什么／原版／重制／原版代码读没读／可见度，登记 check 防腐化 | 已合并 `f5cd953b`（lane 206a7c38）：117 条（合并后归类修正为 116 条／470 来源）；进度页"和原版还差什么"取它的前 20 条 |
| TITLE section-title | 章节标题卡照原版：全屏放大缩回上方横幅、名字随后显现、停留可跳过、横幅放大回全屏淡出，接胜负条件面板（原版逐 tick 读法已在 original_tick_counts §2，重制只做了整体淡入淡出） | 已合并 `589524ea`（lane 6950fc5b）：横幅减色、纵向 8→1、章节名淡入淡出；汇编更正时长 582 tick（改 3 条旧断言，负责人批准）；负责人窗口截 9 个时刻与录屏同刻对比一致（`ignored/lane-recordings/R7-TITLE/compare_sheet.png`）；原版"标题收到上方"实为收成屏幕中间横带 |
| AI51 first-battle-ai | 第一关单位走位逐回合对照用户原版录屏：分歧归类（随机数／规则／顺序／输入），证据足的规则差异修掉 | 已合并 `ddbcc532`（lane f6d3c473→续跑 2c1dcdc1）：够不着目标时按原版 0x4111a0→0x411080 追击（朝目标格、搜索收到移动力、等距抛 rand(2)），录屏 1–3 回合 26 个 AI 行动里重制不可能出现的 11→1（R3-24 攻击站位平局规则未读）；无普攻的施法者保留重制前缀（provisional）；改 2 条旧断言（只放行平局硬币，各补走廊地图零抽样），负责人批准；支线胜 29→25、整章机器人卡第 5 关（此前第 7 关） |
| CAM follow-cursor | AI／脚本走路时镜头按原版 4 px／tick 跟着人走；原版红色短剑游戏光标 | 已合并 `37f2bbc8`（lane 7b1cb0a2）：AI／玩家／剧情带 Wait 的行走镜头逐 tick 跟随；光标是 10 帧红宝石权杖（热点在宝石尖）；负责人窗口截帧目审通过 |
| CUE ai-cue-closeup（第二波） | AI 起手覆盖层照原版（普攻目标段不画射程、施法段在光标处画作用范围）、AI 选格时镜头跟光标；战斗特写中线 y 320→330（负责人预批改断言） | 已合并 `0fac7893`（lane a57b9ccc→续跑 f52f86b1）：起手镜头先到攻击者／施法者（共享 scroll_to_grid）、施法镜头每 tick `center_on_point` 对准光标并按光标格画作用范围（不查射程）、普攻镜头随光标平移、目标段只画光标；特写中线 y 330；负责人截帧目审 |
| CAMX camera-rest（第二波） | 击杀结算前镜头滑到受益者；剧情带速度滚动改原版半程减速；剧情对准人物与首控镜头落点 | 已合并 `f862f57d`（lane 447c034d→续跑 82f7f90f）：所有对准落点改原版 0x43bf30 的 (320,192)（比正中高 48 px，改 3 条"镜头框住某人"旧断言的期望落点，负责人批准）；结算前滑到受益者；速度滚动半程减速；负责人截帧目审（五张中四张被第一战地图下边夹住，结算一张正落） |
| UI panels-dialogue（第二波） | 关面板后地图压暗逐步淡回；对白翻页提示换原版闪烁红光标；升级加点面板按钮切换与收起方式（对白框位置等四件待用户拍板的不动） | 已合并 `f3a4b485`（lane ded9be96→续跑 e3095c51）：压暗开合都逐级（9/16 黑，拟合）；翻页提示实为白字 ▼（还有下一页）／□（最后一页）10 tick 闪烁，去掉「1 / 2」页码；升级面板不可按的按钮不画。旁证：原版对白框旗标 0x4000 放在镜头＋20，即存在顶槽 |
| SPELL effect-motion（第三波） | 法术特效照原版运动（火球从施法者飞向目标再爆开）；施法引导段残影与左右镜像（清单 effect-motion、cast-afterimage） | 已合并 `716537d2`（lane 47bf13e1）：原版 effProc 特效程序在模拟器里逐 tick 执行得出轨迹再回放（131/144 个对象、84 个程序中 73 个完全复原），幻火与录屏逐帧吻合；施法残影与 obj_Data9 换边镜像（battle.py 加 side_swapped，重生成 18 场）；快门 293 s，已发布 |
| POSE map-pose-floaters（第三波） | 地图施法者抬手（use_magic）；升级撒星光与角色升级动作；伤害数字逐位弹跳、原版数字字形（map-cast-pose、levelup-star、damage-digit-bounce） | 已合并 `5187c7b8`（lane 78c3a5c5）：施法／用道具／升级三处抬手 88 tick；升级 36 颗星光；地图普攻伤害数字原版字形高位先逐位＋白闪、不上浮；capture 夹具两轮修正后负责人目审通过；已发布 main `5187c7b8`（快门 324 s） |
| DLG dialogue（第三波） | 先查明原版对白框何时放顶部（旗标 0x4000）再照做；擦出节奏与换行分页照原版（dialogue-top-slot、dialogue-timing、dialogue-line-breaks） | 已合并 `b653db16`（lane 91a6ffa4）：顶槽只给脚本自带人脸的消息（actShapeMessage／城镇 teShapeMessage），其余底部；19 字换行、4 行上卷翻页、擦出与淡入淡出；框位单独提交 `f00f68f7` 可撤回；专名保护与即时确认记为偏离；已发布 main `328b6a26`（快门 1106 s，负载高） |
| NPC level-and-ai（第三波） | 开战 NPC 随机调级（0x40e870 与 phase 条件，解释录屏 023_2 为 3 级 41 HP）；AI 攻击站位 state 7 与 0x40d800 80% 过滤（npc-level-policy、ai-first-battle-moves 剩余） | 已合并 `d7bc17c4`（lane 9fd631fb）：开战调级规则本已正确、录屏 023_2 的 3 级 41 HP 是同规则的随机抽样（测试复现）；同速玩家先于 NPC（0x407660／0x407340）；攻击站位 0x413390；追击候选 80% 跳过 0x40d800；录屏 1–3 回合 26 个原版 AI 行动全部可由重制产生；sweep 胜 25→26、整章机器人推进到第 7 关；未做第 6 关两段式重调级 |
| FONT bitmap-font（第四波） | 界面文字换原版位图字 FONT.24／FONT.15／ASCFONT（bitmap-font） | **暂停**（用户 09-25 要求规则优先）：分支 `paused/R7-FONT-bitmap-font`（`791e334c`）已生成原版 FONT.24／FONT.15 的 Godot 字体、未接界面；报告 `ignored/lane-reports/R7-FONT.md` |
| DIGITS all-numbers（第四波） | 特写与地图法术的伤害／治疗数字换原版字形与逐位出现（damage-digit-bounce 剩余） | **暂停**：分支 `paused/R7-DIGITS-all-numbers`（`05a9e441`）风火水法术数字已换原版字形、寿命对齐；特写数字补丁 `ignored/lane-reports/R7-DIGITS-pending-cutin.patch`（4 条旧断言待批）；报告 `R7-DIGITS.md` |

合并列车一（INV＋TITLE＋CAM）：负责人合并后重新归类差异清单（关闭标题卡、走路跟随、光标三条，新增剧情特殊走法镜头、光标隐藏与持物图标两条）`bb2e03fd`，单测去掉写死的条目 id `b60e9860`；快门 `VERIFY_PASS mode=fast seconds=687`（门禁启动时 b60e9860 的改动已在工作树，门禁日志按同一棵树记给 b60e9860）；已发布 main `b60e9860`，三个 worktree 已清理。

09-25 04:27–07:39 本机电量耗尽休眠，四条 lane 停约 3.2 小时（非卡死）；负责人接电后开防休眠、让第二波先存盘再续跑（各给新 4 小时额度）。列车二（AI51）：合并树深门 `VERIFY_PASS mode=deep seconds=1179`（剧情 22/22、结局 3/3；sweep 胜 25），已发布 main `ddbcc532`，worktree 已清理。列车三（CAMX＋CUE＋UI）：CUE 与 CAMX 在 `center_on_grid` 冲突，按负责人事先定的解法合为 `center_on_grid → center_on_point → focus_centre`（0x43c0f0 光标格与 0x43bf30 人物同落 (320,192)）；差异清单 curation 按条目 id／来源键三方合并（两边关闭的都关），生成物在合并树重生成，清单 116→107。快门 `VERIFY_PASS mode=fast seconds=321`，已发布 main `49ebf571`，三个 worktree 已清理；第三波四路从 `49ebf571` 派出（workflow a22886c1）。

列车四（DLG）快门 1106 s（负载高）发布 `328b6a26`；列车五（POSE）快门 324 s 发布 `5187c7b8`；列车六（SPELL）快门 293 s 发布 `716537d2`；列车七（NPC）合并 `d7bc17c4`（与 lane 深门同树），第七轮收口全门／深门见本段末。**第七轮收尾（2026-09-25）**：用户决定把负责人对话从 Pi 迁到 Claude Code，交接提示词在仓库外 `~/hsl-playtest/HANDOFF-claude-code.md`；用户同日要求按复刻品质影响排序（影响输赢与走位的规则＞演出＞外观），新负责人静态读出（static-derived，未运行验证）：原版 AI／调级用的全局随机数每次启动按时钟播种、不入存档，伤害命中流入存档，故"两次走位相同"不成立；"走位一致"改为三条——同状态同随机数落点与目标一致、同决策点同概率抽取、存读档语义一致；用户 09-25 同意，模拟器整回合试验进行中。

负责人直接修复（已合并）：调试停格——任何画面 P 停住（画面、声音、计时全停，输入不进游戏）、停住时 N 走一帧，方便截图对照原版 `032a5470`（用户 09-24 要求）。

**2026-09-24 第六轮「用户录原版期间的推进」**（负责人 pi 会话 `01a0cf11`，04:25 UTC 起换为 `01a0d1a3`——旧会话读大图撑爆请求体（413）无法继续，编排目标与 lane 原样接管；lane 同模型 `PH/claude-opus-5-5`、thinking high）：用户在本机录制原版视频、稍后补充截图说明；期间推进不依赖该视频的三项。**任何 lane 不开 Wine／原版**；窗口化截图先经负责人确认（避免在用户录屏时弹窗）；最多 3 条并行、每条门禁并行度 2。基线 main `b1fa4b3a`，负责人在 `~/.pi-worktrees/hsl-pipeline` 审阅合并；报告落 `~/.pi-worktrees/hsl-pipeline/ignored/lane-reports/R6-L*.md`。

| lane | 范围（玩家看到的问题） | 状态 |
| --- | --- | --- |
| L8 winnability-audit | 128 场逐场"原则上可赢"体检：脚本引用不存在的单位（如 80 关 Enemy068）、目标不可达、必活单位被脚本送死、59／75 第 1 回合即负等，按类在共享层修并加全量检查 | **已合并** `f9d77892`（HPLow 下限 1：41／59／75–79 可赢、30–37 首领剧情触发；29 关台词；合并树 `--deep` VERIFY_PASS 2070 s）；剩 37 缺守卫、80 缺怨念體 → L10 |
| L9 → L9b script-inventory | 原任务：界面简体换繁体（PROJECT 第 7 行①）。用户 09-24 录屏显示其原版**全部文字为简体**，统一成全繁还是全简待用户拍板。L9 读大图请求体超限（413）死亡、无提交；重派 L9b 只做方向中立部分：盘点烘焙文字素材与玩家可见字串、查明原版运行时如何显示简体、设计单一转换点与检查 | L9 失败；L9b **已合并** `24c186c2`（用户拍板全简体；合并树＝lane 终版树，复用其快门 VERIFY_PASS 797 s） |
| L3c commander-3 | 章节机器人越过第 7 关（中途加入的必活单位护送、两回合开局），每项改动 ≥40 局多交接评估（PROJECT 第 3 行剩余） | **已合并** `334d78a6`（合并树快门 VERIFY_PASS 259 s）：40 局 7→15 胜，第 7 关仍 0/13、memoir_05 仍 1/5；负责人决定机器人线暂停，续做时允许机器人知道剧本援军位置（输过一次的玩家也知道） |
| L9c credits-cells | 通关制作名单简体重画只动仅繁体字（伋 不再成"1及"），逐格检查含消融 | **已合并** `6b459ad1`（合并树快门 VERIFY_PASS 516 s） |
| V1b video-index | 用户 09-24 原版整体录屏的按时间目录（agy 看视频，192 段），只作导航 | 完成（产物在 `ignored/user-video-20260924-1203/index/`，不入库） |
| V2 event-diff | 原版录屏 vs 重制按"画面变化"逐个对账：镜头、面板开合、胜负条件面板、对白框、特殊技页、AI 预告、地图姿势、高亮、飘字等 13 类差异（报告 `ignored/lane-reports/R6-V2.md` 第 6 节） | **已合并**（只加 `tools/hsl_video_events.py` camera 子命令；合并树快门 VERIFY_PASS 436 s）；盲测：人物高亮✓、对白换页过渡部分✓（测到但描述为溶解）、灵魂飞升✗（并排对比因 agy 登录过期未跑） |
| L10 missing-actors | 补剧本用到、重制缺的敌人：37 关守卫 Enemy066／067（主线可赢）、80 关 怨念體 Enemy068；盘点全部 128 场 | **已合并** `6e9aec5c`（37 关宝石／守卫、80 关 怨念體、不死首领被魔法／特技击倒即死的修复；合并树 `--deep` VERIFY_PASS 827 s：sweep 29 胜 99 负 0 死局、章节 stuck_at=7、explorer 22/22 与 3/3 结局、普查 266 项） |
| P1 dialogue-death | 对白与阵亡演出照原版：说话人高亮、对白逐行显现与淡出、遗言规则、闪白与灵魂飞升＋"咻"声（用户截图 user-confirmed）、濒死跪地；先三路量原版（像素／声音／资源） | **已合并** `07e11772`（统一高亮、对白溶解与逐行擦出、遗言按原版选句、濒死跪地、灵魂上移 37→47 px＋dead0003「咻」；负责人抽帧复核与用户截图一致；合并树快门 VERIFY_PASS 281 s，含两处合并修复：生成块重渲染、second_battle_opening 采样窗口） |
| P2 camera-panels | 镜头减速滚动、面板滑入滑出、胜负条件面板真实显示、敌方移动预告、切入白光；先三路量原版 | **已合并** `2eb717c7`（镜头逐 tick 滑动、五面板开合、胜负条件面板、敌方移动预告 16 tick、切入白光；负责人抽帧复核；合并树快门 VERIFY_PASS 538 s） |
| P3 closeup-floaters | 战斗特写人物居中与全宽底栏、特殊技切入半身立绘、KILL／EXP／$／LEVEL UP 原版美术字与节奏、加点面板小剑与倍率；先三路量原版 | **已合并** `15af0a3f`（守方照原版击退 105 px／落空侧滑、所有切入共用 CloseupLayout；KILL／EXP／$／獲得物品／LEVEL UP 原版美术字与顺序、升级音随 LEVEL UP；身份栏抗性行元素宝石；纠正录屏对账三处误读：人物"偏右"实为守方未击退、半身立绘早已有、"小剑与倍率"是抗性宝石＋百分数；合并树快门 VERIFY_PASS 333 s）；特写中线原版 y 330、重制 320 待定 |
| P4 menus-ui | 标题版本号与确认后停留淡出、状态页布局、任務說明与存档「確定／取消」、选目标光标与双卡、敌方回合不显示玩家光标；先三路量原版 | **已合并** `c79af847`（标题 V1.06 与确认后 0.75 s＋0.55 s 淡黑、I_RECT01 黄色目标框含敌方预告、存档確定／取消与 BOARD02 完成板、任務說明用胜负面板；8 处写存档／离开项共用确认框；合并树快门 VERIFY_PASS 697 s）；状态页左栏证据冲突（录屏道具列表 vs 早先 EXE 读法九项属性）待静态复核 |
| L11 script-conditions | 剧本中途 actCheckEventNotExist 按原版求值（37 关 5 号宝石最后打、80 关先倒首领再两宝箱）、30 关 克羅蒂 属性、18 关城门可普攻、37 关槽位洗牌、跳过开场的雕像图残留；盘点全部 128 场 | **已合并** `f4cf06e9`（链中 actCheckEventNotExist 闸门：37 关 5 号宝石最后打、80 关两宝物才赢；30 关 克羅蒂 用 053 属性、21／24／903 关造型改回 009；37 槽位原版洗牌、跳过开场清雕像、宝石／怨念體 加色、范围魔法波及宝石；自动对局 128 场胜负不变；合并树深层套件 PASS 462 s）；18 关城门未建（缺证据，门下墙缝重制可走过）、37 关五宝石机器人探针未赢 |
| T1 audio-exit-leak | 门禁偶发"退出时泄漏"：combat_aftermath 约一半概率在全部检查通过后因退出诊断失败（收轮深门挂在这里），查根因并按类修 | **已合并** `1581d363`（根因：测试结尾按引擎时钟等 0.3 s，长步骤后一帧即到期，已停音乐的播放对象未释放就退出；`TestSuite.stop_audio／settle_audio_before_quit` 按墙钟等到释放，14 个场景套件改用，只改测试、不改断言；aftermath 20 次 0 泄漏，消融去掉等待 6/6 失败） |

**第六轮已于 2026-09-24 收口**：12 条 lane 合并（L9 失败由 L9b 重做，V1b 只产目录不入库）；收口门禁 `1581d363` 深门 VERIFY_PASS 680 s（sweep 128 场 29 胜 99 负 0 死局、章节 stuck_at=7、explorer 22/22 与 3/3 结局），收口文档提交另跑冷启动全门（结果记在交付报告）。

待修（负责人记）：特写中线照原版 y 330（现 320，涉及两条门禁断言，负责人倾向照原版）；18 关城门对象（缺 PLAYERS 解析器对缺省字段的预置读法）；其余约 26 个场景套件结尾统一换 `settle_audio_before_quit`（T1 建议）；状态页存／读按钮也走同一確定／取消（F5／F9 保留即时，负责人定）；状态页左栏道具列表 vs 九项属性待静态复核是否翻页；`run_second_battle_opening_tests` 在 `--fixed-fps 60` 下只看到 2/4 招募兵走动（main 上同样），疑剧情走位混用墙钟与帧时间，查明后可入快钟集；`run_first_battle_playthrough.gd` 不在任何门禁且基线即失败（living unit vanished: Enemy021_script_1_0）——修好入深门或删除；AI 走路时镜头应按原版 4 px／tick 跟随单位（现为出发即滑向终点）；敌方移动预告原版两簇时长成因未明。深门的整章行走用 600 s 墙钟预算，高负载时会在第 7 关前超时并改写 `chapter.json`——结果随负载变，应改成按回合／场次计的确定性预算。

负责人直接修复（已合并）：UI 字体加简体回退，消除缺字方框 `3f27ca45`；shell 脚本变量紧跟全角标点时加花括号（macOS /bin/bash 3.2 把后一个字节读进变量名，门禁 PATH 下 `test_hsl_play_original` 因此失败）`c0c6b5d3`。

**待用户决定**（只列产品行为；派 lane、提速、清理这类流程选择负责人自定）：
- 特殊技页：照原版每次先开技能页（气力不足也能打开、条目灰显）——推荐；或保留重制"只有一个技能直接选目标"。
- 对白框：**暂缓，负责人先查**——此前按录屏判"原版始终在底部"并推荐去掉重制的顶部位置；R7-UI 读到原版对白框旗标 0x4000 会把框放在镜头＋20（原版也有顶槽），何时启用未读，查明后再给建议。
- 敌人出手前的射程与作用范围样式：保留重制红格＋用户定的洋红醒目样式——推荐；或换原版范围格美术。
- 对白页码「1 / 2」：已照原版去掉；用户要的话可恢复（例如放在 ▼ 左侧）。
- 伤害飘字附加词（擊倒／反擊／暴擊／HP）与选目标时头顶「命中 99%」：照原版去掉——推荐；或保留作重制改进。
- 胜负条件面板：照原版一直等按键——推荐（测试与自动对局另开自动跳过）；或保留现在约 1.8 s 自动淡出。

**2026-09-24 第五轮「实玩问题收口」——已收口，终版 main 门禁见本段末**（负责人 pi 会话 `01a0cf11`；lane 与负责人同模型 `PH/claude-opus-5-5`、thinking high，用户指定）：用户授权 6 条并行 lane 接住下表 09-23 的保存点，收口 [PROJECT Next steps](docs/PROJECT.md#next-steps)「先处理用户实玩的现行问题」6 项，不开新功能。lane 在 pi-subagents 管理的 worktree 里工作（基线为登记本段的 main 提交），负责人在 `~/.pi-worktrees/hsl-pipeline`（`pipeline-line`）审阅、合并、跑合并树门禁，再快进 `main`／`presentation-line`；报告落 `~/.pi-worktrees/hsl-pipeline/ignored/lane-reports/R5-L*.md`。**原作（Wine）只归 L6**，其他 lane 的原版取证请求经负责人转给它。

| lane | 范围（玩家看到的问题） | 接住的保存点 | 状态 |
| --- | --- | --- | --- |
| L1 growth-targeting | 升级加点窗按原版时机（全部升级途径）；带格动作光标在任何单位上都显示人物面板；技能选格显示真实作用范围（毒魔箭十字等） | P11（未动工）＋原 P9 的人物面板项 | **已合并** `3d08165d`（合并树 `--deep` VERIFY_PASS 542 s） |
| L2 skill-audio-death | 氣刃斬落点音效与全部技能同类漏音；阵亡演出（低优先、有界取证） | P10（未动工） | **已合并** `abde33fe`（合并树快门 VERIFY_PASS 294 s） |
| L3 commander | 指挥官以合格玩家手段过第 5／6 关，整章重测 | B4b：`rescue-20260923-B4b`＋`refs/rescue/20260923/B4b-wip` | **已合并** `445e8f7f`（合并树 `--deep` VERIFY_PASS 416 s）；剩余交 L3b |
| L4 map-staging | 开场站位、剧情物件（53 绳索）、可走高台、开场镜头、剧情入退场走位（全关同类） | P8：`rescue-20260923-P8`＋`refs/rescue/20260923/P8-wip` | **已合并** `149e77de`（合并树 `--deep` VERIFY_PASS 623 s）；剩余交 L4b |
| L5 ui-classes | 菜单高亮与光标饰物、面板对齐、气力条分格、翻页拆词、默认静音、重制自绘的大地图底栏与城镇界面 | P9：`rescue-20260923-P9`＋`refs/rescue/20260923/P9-wip` | **已合并** `d061b8cb`（合并树快门 VERIFY_PASS 268 s）；标题饰物／大地图黑线／大地图底条与城镇待 L6 实录后跟进 |
| L6 original-evidence | 原版第 6 关存档预设与启动入口、第 5／6 关规则对照、原版大地图／城镇界面实录、其他 lane 的原版取证 | M3：`refs/rescue/20260923/M3-wip`；M4：`rescue-20260923-M4` | **已合并** `4660d59b`（合并树快门 VERIFY_PASS 452 s）；后续原版请求需要时再复活 |
| L7 user-decisions | 用户 09-24 拍板的三项：结束战斗那一击升级在胜利结算前弹加点窗；技能结算范围预览换醒目样式；阵亡音效改到遗言之后 | L1／L2 报告留下的决定 | **已合并** `b4a643fd`（合并树 `--deep` VERIFY_PASS 431 s） |
| L5b ui-reference | 按 L6 原版实录：标题宝珠／书竖直浮动、大地图底条与黑线、城镇构图照原版（重制便利项保留不挡构图）、装备说明框专名换行 | L5 blocked-on-reference 三项 | **已合并** `084190a2`（合并树 `--deep` VERIFY_PASS 464 s） |
| L4b map-staging-tail | 第 6 关村民 061_1 对原版 (25,15)、39 关 Block XRange、单位被前景建筑遮挡是否原版 | L4／L6 报告剩余 | **已合并** `262d312e`（合并树＝lane 终版树，复用其 `--deep` VERIFY_PASS 596 s） |
| L3b commander-2 | 机器人补齐合格玩家手段：攻击位分配、后方掩护、经验分配、药品经济；用户第 6 关存档 memoir_05、第 52 关、遭遇战 509 | L3 报告剩余 | **已合并** `b20d5d52`（合并树＝lane 终版树，复用其 `--deep` VERIFY_PASS 531 s）；memoir_05 0/5、52 关 3/6 未达标，章节新卡点第 7 关 |
| L6b town-shop | 原版商店买卖画面与离开城镇操作实录（当前唯一开 Wine 的 lane，每趟 ≤10 分钟），再照原版收尾重制商店画面 | L5b 剩余 | **已合并** `de8a1ade`（合并树 `--deep` VERIFY_PASS 855 s） |
| L4c terrain-start-cells | 开场站在 0xff 格的单位能否走下（原版移动搜索起点的静态证据，含 552 玩家可控的 咕嚕）；28／80 墙按事件打开 | L4b／L6b 剩余 | **已合并** `30e878e4`（合并树＝lane 终版树，复用其 `--deep` VERIFY_PASS 805 s＋快门 447 s） |

第五轮终版门禁（main `1a163105`，全部 12 条 lane 合并后）：`tools/verify.sh --deep` VERIFY_PASS 594 s（AUTOPLAY_SWEEP_PASS battles=128 win=29 fail=99 dead_end=0；CHAPTER_AUTOPLAY_PASS stuck_at=7 battles=10 won=9；STORY_MODE_EXPLORER_PASS story_scenes=22/22 endings=3/3；0 SCRIPT ERROR）；`tools/verify.sh --full` VERIFY_PASS 840 s（冷导入 222 s，Python 785 项，0 SCRIPT ERROR）。旧 09-23 保存点（7 个旧 lane worktree、9 个已在 main 的 rescue 分支、4 个内容已合并的 WIP 引用）等用户确认后清理；未 push。

**2026-09-23 模型服务中断后的可恢复状态**（已由上方第五轮 lane 接手）：PostHog 的 `claude-opus-5-5` 返回 403 `model_gate`（需付费计划）；随后所有旧子代理退出，当时没有运行中的子代理。不要再用该模型盲目重试。用户允许后续用当前主会话的 `openai-codex/gpt-6-sol`，但要求**先收口，不立即扩功能**。旧会话的模型合同不能靠普通 resume 改写；需要在保存的分支上重新派发、重读 brief、复核差异。以下条目只是恢复位置，**不代表交付或通过门禁**：

| 工作线 | 状态／提交 | 中断时未提交的工作 | 恢复边界 |
| --- | --- | --- | --- |
| R37 事件扫描 | **已合并** `121b99aa`；`--deep` VERIFY_PASS，1221 s、0 SCRIPT ERROR，main／pipeline-line／presentation-line 同步 | 无 | 可直接复用。主线章节自动对局仍卡第 5 关，不声称通关。 |
| P8 地图／走位 | `rescue-20260923-P8` → `8eb1ab4b`（房屋锚点修正）；未合并 | `refs/rescue/20260923/P8-wip`（地图坐标／通行生成链、PROVENANCE）；当时门禁曾报来源汇总 stale | 先审全类关卡与生成物、重跑定向＋快门，不只采纳单关截图。 |
| P9 界面 | `rescue-20260923-P9` → `7a52b211`（含默认静音 `e05052f6` 与菜单图尺寸修复）；未合并 | `refs/rescue/20260923/P9-wip`（气力条组件等） | 标题／大地图／城镇／人物 hover 面板按整类复核，截图人工验收。默认静音尚不是主线能力。 |
| M3 原作第 6 关 | `rescue-20260923-M3` → `6358be38`；**无新提交** | `refs/rescue/20260923/M3-wip`（原版存档预设、启动脚本／解码器／说明） | 原作进程仍可能在运行；先确认窗口与用户操作，再核实能否真正进关；原存档备份在 `~/hsl-playtest/original-save-backups/`。勿擅自覆盖／退出用户窗口。 |
| B4b 指挥官 | `rescue-20260923-B4b` → `a7b4f130`（含上一轮唯一提交 `434e4ee8`）；未合并 | `refs/rescue/20260923/B4b-wip`（逐关交接目录／大脑调整） | 先恢复上轮提交与 WIP、核对 R37 新规则；第 5／6 关和全章重测，报告每关尝试数，不硬编码关卡特例。 |
| M4 大地图／城镇 | `rescue-20260923-M4` → `1f6b51d4`（原版大地图演出资源盘点）；未合并 | 无 | 资源清单尚未变成实际演出／城镇原版画面回执，未过合并树门禁。 |
| P10 落点音效／阵亡 | `rescue-20260923-P10` → `bd5d95d4`；**未动工** | 无 | 氣刃斬命中音效优先；阵亡灵魂演出低优先级，不凭保留帧编造原版动画。 |
| P11 升级窗 | `rescue-20260923-P11` → `bd5d95d4`；**未动工** | 无 | 全队共用提示等级／行动菜单门槛是疑点，须复现并修正，不能把假设当根因。 |

所有 WIP 的原始工作树已 stash 并变干净，且各自提交另有 `rescue-20260923-*` 分支保护；**不要 `stash pop` 或删 worktree**。外部双份备份（manifest、staged／unstaged／working binary patch、untracked 文件、原任务书）在 `~/hsl-playtest/lane-rescue-20260923/`。继续时按 `manifest.json` 的原 HEAD 核对，用 `git show refs/rescue/20260923/<lane>-wip`／备份恢复到**该 lane 的隔离工作树**，再审差异和验证；未验证内容不可合并。原作的 `HSL00.SAV` 曾被替换为第 6 关预设，原备份已另存，仍需核实原作进程／用户是否在玩。


用户 2026-09-12 明确要求：source-research 继续在现有 `main` 和主工作区工作；完成一块、验证一块、更新进度后立即本地提交，不自行增加分支、工作树或额外 checkout（presentation 接续线的独立工作树是 2026-09-18 的明确例外）。下一批开始时重新声明具体文件范围；不因上一批历史留言而无限等待。

## 阅读与回执

每次开始新 slice、发现未知 Git 改动、准备修改公共文件或提交前，先读本文件，再定位各线最新标题并读取最后一条认领及其后的收口。可用 `rg -n '^## ' docs/collaboration/*.md` 找行号，按需读取对应范围；旧消息只在需要核对 REQUEST／ACK 时追读，不把全部历史塞进冷启动上下文。`git status` 只能帮助发现文件，不能证明对方读过；只有对方写出明确的 ACK 才算确认。

本文件记录分工和协议；各方的进展、请求和交付写入自己拥有的 `docs/collaboration/<角色>.md`。读后在自己的文件追加 `ACK <消息编号>`，包含接受的文件范围或具体异议。不得替另一方写确认或完成状态。无需定时轮询或停下独立工作等消息。

## 当前分工

| 角色 | 对话 | 负责范围 | 确认状态 |
| --- | --- | --- | --- |
| presentation | 原 `2026-09-11-3d245c77`；2026-09-18 起由 pi `01a0b032`（独立工作树 `presentation-line`）接续 | 第二战／战役推进（level 52 剧情、编队、开场、胜负、跨关承接的数据与新模块）、战斗演出／音频／镜头补全、presentation 与 second-battle 测试及 PRESENTATION 文档；触及 PlayLoop／Runtime／Checkpoint 等机制线热文件时先 REQUEST | [P-008 接续 CLAIM](docs/collaboration/presentation.md) 起；合并到 main 的提交以 Git 核对 |
| source-research | 原研究线及其接续会话 | 原规则／公共系统研究与接入；新 slice 在本线留言末尾声明文件 | [留言末尾](docs/collaboration/source-research.md) 的最新 CLAIM 和后续收口；实际提交以 Git 核对 |

表中是角色职责，不是永久文件锁。原 ANIMAL／成长／滚动等已完成批次的具体负责文件保留在原留言，不在这里重复维护。

## 写入、验证与提交

1. 跨范围写入先在自己的留言里提出 REQUEST，等所有者 ACK；无冲突的新文件可以先声明并继续。原始 PAK／EXE 只读，raw 输出各用独立 `ignored/` 子目录；成果仍按既有 evidence policy 提升。
2. 公共入口文档仅做小段带上下文 patch，修改前重读；不要重写整份 PROJECT、KNOWLEDGE_INDEX 或本文件。原始研究证据与 live 接入状态分开，不能由工具通过推导游戏已还原。
3. 共享工作区不执行 reset、stash、clean 或批量 add；提交只选择自己的明确路径。提交前检查暂存区，已有别人的暂存内容时不改动它。不要把未知 untracked 文件删除或捎带提交，不自动 push。
4. `verify.sh --full` 在导入前清理 `.godot`／import cache（默认快门保留缓存）。主工作区只由 source-research 运行 verify／GUI；presentation 接续线在自己的工作树导入、验证和录屏，不占用主工作区缓存，也不在主工作区运行 verify。合并前该线核对主工作区 `git status`，仅当合并路径与对方未提交改动无重叠时执行；合并后在留言写明合并提交号。上一批已有的独立副本回执保留其准确基线，不能改称当时验证了另一方的未提交代码。
5. READY 留言必须给出文件、复跑入口、确定结论、未确认边界、验证和提交状态。接入方实际检查后追加 ACK／问题，研究方再更新自己的记录。发现新增指令或证据改变结论时，保留更正说明。
6. 提交完成后更新自己的收口状态，取回所有验证进程结果并同步对话计划；交付中同时写明提交号和剩余改动。研究已完成、已经 live 接入和原版等价是三个独立结论。

通信记录服务于当前协作，正式事实保存在 evidence packet，产品进度仍以 `docs/PROJECT.md` 为准。完成协作后保留成果链接，不把这份留言升级成另一套项目真相。
