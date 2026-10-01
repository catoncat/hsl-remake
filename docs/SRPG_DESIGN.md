# 战棋设计方法：人物组合、数值与关卡

> 用途：写自制战役时反复查阅的回合制战棋方法库，例子偏向十关上下、队伍从少到多的短篇。最后一节把这些方法对到本作的规则上。
> 写法：每条方法按「是什么／为什么／怎么用」写，合计不超过三句；〔〕里是来源。「怎么用」是把来源落到本作的做法；标【推导】的数字或规则是从所列来源归纳出的经验值，不是来源原话，上图前要在自己的地图上验证。

目录：0 三条总纲 · 1 队伍分工与互补 · 2 数值 · 3 关卡 · 4 十关短篇的节奏 · 5 做一关时逐项过的清单 · 6 落到我们的规则 · 附 来源

---

## 0. 三条总纲

- **威胁要看得见，取舍才成立。** 是什么：把敌人下一步打哪、从哪来尽量提前摊开。为什么：《陷阵之志》把敌方行动全部预告后，每回合像一道解谜，战斗反而更快；而「先行动、后掷骰」的输出随机是玩家最难接受的随机。怎么用：命中以外的变数（增援、Boss 大招、地形事件）一律先告知再发生。〔[Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)；[GMTK「The Two Types of Random」小结（知乎）](https://zhuanlan.zhihu.com/p/106937258)；[Kotaku: Randomness In Video Games Is Not All The Same](https://kotaku.com/randomness-in-video-games-is-not-all-the-same-1841049263)〕
- **先定体验，再定数值。** 是什么：把「一场打多久、一个敌人几刀死」当自变量，属性当因变量。为什么：数值是为体验服务的，先算属性再看体验只能碰运气。怎么用：每关先填第 2 节的「几刀表」和「同时接战人数」，再填 HP／攻／防；《Game Balance》把这种决定胜负的核心量叫作「锚点」，其余数值都相对它来定。〔[indienova：游戏战斗设计基础（十二）数值框架搭建](https://indienova.com/u/yitiaodayu/blogread/30813)；[Schreiber & Romero《Game Balance》第 5 章 Finding an Anchor](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-5/finding-anchor-ian-schreiber-brenda-romero)；[GameRes：战斗数值模型搭建](https://www.gameres.com/669283.html)〕
- **玩家的感觉比数学重要。** 是什么：玩家把 3:1 的优势当成必胜，把 85% 当成 100%。为什么：Sid Meier 在 GDC 2010 讲到，玩家输掉 3:1 的仗会觉得被骗，赢下 1:3 的仗却从不抱怨，他只好把赔率往玩家一边偏。怎么用：凡是玩家会算的数（命中、伤害、回合），宁可略偏向玩家，也别让「明明占优却输」反复出现。〔[Sid Meier GDC 2010 笔记（gamedev.net）](https://www.gamedev.net/blogs/entry/2111213-the-psychology-of-game-design-sid-meier/)；[Ada Chen Rekhi 现场笔记](https://www.adachen.com/gdc10-notes-sid-meier-on-why-everything-you-know-is-wrong/)〕

---

## 1. 队伍：职业分工与互补

- **按「在棋盘上解决什么问题」分岗。** 是什么：把职业归到前排（挡住）、输出（收割）、支援（回复与增益）、控制（推拉、减速、封路）、机动（飞越地形）、工具（开门、偷窃、侦察）几个岗位。为什么：伤害—治疗—坦克铁三角的价值在于互相掩护短板：坦克站前面替治疗挡刀，治疗才腾得出手。怎么用：九名队员每人一个主岗、一个副岗，任意两人的「主＋副」不重复，例如剑士＝前排＋输出、僧侣＝支援＋前排（重甲）、盗贼＝工具＋输出、翼族战士＝机动＋输出。〔[TV Tropes: Damager, Healer, Tank](https://tvtropes.org/pmwiki/pmwiki.php/Main/DamagerHealerTank)；[Wikipedia: Healer](https://en.wikipedia.org/wiki/Healer_(video_games))；[Game Design Skills: Tank in RPG](https://gamedesignskills.com/game-design/tank-in-rpg/)〕
- **每个岗位带一个要队友补的短板。** 是什么：重甲慢且怕魔法、飞行怕弓、法师怕近身。为什么：坦克若和输出一样快就会冲出队形，慢一点才会和队伍待在一起；短板让站位有意义，也让「谁和谁一起上场」成为决定。怎么用：翼族战士被弓箭特攻（《火焰纹章 Engage》里弓对飞行是武器威力 ×3），弓手因此成为对空答案，重甲移动力全队最低。〔[Game Design Skills: Tank in RPG](https://gamedesignskills.com/game-design/tank-in-rpg/)；[18183：Engage 伤害公式](https://m.18183.com/gonglue/202302/4450429.html)〕
- **克制做成循环，不做成排名。** 是什么：兵种克制成环，如《梦幻模拟战》II 以后的步兵＞枪兵＞骑兵＞步兵。为什么：环状克制让没有哪一种永远最优，敌方换编成玩家就得换人对位。怎么用：每关敌人至少覆盖克制环上的两种，逼玩家出场时混编。〔[Langrisser Wiki: Langrisser I & II Gameplay](https://langrisser.fandom.com/wiki/Langrisser_I_%26_II_Gameplay)；[GamerEscape: Langrisser I & II 评测](https://gamerescape.com/2020/03/03/review-langrisser-i-ii/)〕
- **指挥官与部下（《梦幻模拟战》）。** 是什么：指挥官带一队佣兵，佣兵在指挥范围内加攻防并回血，指挥官一死整队消失，佣兵不升级、经验归指挥官。为什么：它把「离队长多远」变成数值，也造出「速杀首领早结束」与「慢慢清兵多拿经验」的取舍。怎么用：敌方小队长可带光环，玩家要么先把兵引出圈外再打，要么冒险直取队长。〔[Wikipedia: Langrisser](https://en.wikipedia.org/wiki/Langrisser)；[RPG Site: Langrisser I & II 评测](https://www.rpgsite.net/review/9504-langrisser-i-ii-review)；[Langrisser Wiki](https://langrisser.fandom.com/wiki/Langrisser_I_%26_II_Gameplay)〕
- **开局的「拐杖」角色（Jagen 原型）。** 是什么：前期给一名已转职、基础高、成长差的老兵。为什么：他把敌人打残让新人补刀拿经验，扛住新人打不过的敌人，抹平前几关的难度曲线；但玩家过度依赖他，其他人就练不起来。怎么用：两人开局时一人是拐杖、一人是成长型；归队老伙伴也按「强但成长慢」做，给新人留出上场空间。〔[Fire Emblem Wiki (Fandom): Jagen](https://fireemblem.fandom.com/wiki/Jagen)；[Set Side B: What is a Jagen?](https://setsideb.com/what-is-a-jagen/)；[TV Tropes: Availability vs Growth](https://tvtropes.org/pmwiki/pmwiki.php/Characters/FireEmblemHeroicArchetypesAvailabilityVsGrowth)〕
- **老伙伴按「离开时的样子」归队。** 是什么：《烈火之剑》琳篇练过的角色，到艾利乌德篇按琳篇结束时的等级归队；新主线却从几个 1 级角色重新开始。为什么：玩家盼着老朋友回来，归队时「还是那么强」本身就是奖励，而新阵容从低处起步让前几关有事做。怎么用：老伙伴以原作终盘的分工归队，但用每关等级上限（见 2.10）压住，避免一来就碾压；本作没有等级上限，替代做法见第 6 节。〔[Digitally Downloaded: Why Fire Emblem (The Blazing Blade) has the greatest tutorial](https://www.digitallydownloaded.net/2023/01/why-fire-emblem-the-blazing-blade-has-the-greatest-tutorial-of-all-time.html)；[Wikipedia: The Blazing Blade](https://en.wikipedia.org/wiki/Fire_Emblem:_The_Blazing_Blade)〕
- **工具岗位要被地图真正用到，也要防它拆关。** 是什么：飞行、开门、偷窃只有在地图给机会时才有价值。为什么：它们也最容易让一关失效，例如《if 暗夜》某关乘风柱直上击败首领，困难和疯狂难度都能用。怎么用：做每关都问一次「翼族／盗贼能不能把这关跳过」，能就要么封住，要么把它定为本关的预设解。〔[Crusader Grant: Conquest Map Design Review Part 3](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-3.html)；[Part 4](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-4.html)〕
- **混编敌人，防一把武器通关。** 是什么：一关只有一两种敌人时，一把特攻武器就能解决全部。为什么：单一敌种让队伍搭配失去意义，《if 暗夜》里全员怕斩兽剑的那关被评为明显偏易。怎么用：每关至少两类需要不同应对的敌人（如重甲＋飞行），逼玩家同时带魔法和对空。〔[Crusader Grant: Conquest Map Design Review](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-3.html)〕

---

## 2. 数值

- **2.1 几刀死（HKO）定基线。** 是什么：《火焰纹章》用「攻−防＝伤害」的减法公式，HP 相对攻击偏低，一个角色三五次交战就会倒下。为什么：每一刀都疼，玩家才会每回合都算；减法公式下刀数 N＝⌈HP÷(攻−防)⌉，而追击（速度差够大时一次交战打两下）和暴击（×3）会让刀数直接跳档。怎么用：【推导】杂兵被主力 2 刀倒（有追击时 1 回合），主力被杂兵 3–5 下倒，Boss 被主力 4–6 下倒；追击和暴击各算一档，别让它们把基线打穿。〔[机核：几个经典战棋游戏分析](https://www.gcores.com/articles/188202)；[知乎：火焰纹章核心战斗公式解析（烈火之剑）](https://zhuanlan.zhihu.com/p/429568333)；[18183：Engage 伤害公式](https://m.18183.com/gonglue/202302/4450429.html)〕
- **2.2 减法公式的「不破防」阈值。** 是什么：伤害＝攻−防时，防御的价值取决于对手攻击，防高到一定程度会出现 0 伤害。为什么：伤害一旦为 0，敌人再多也没威胁，掉一两点时威胁又突然很大，游戏退化成比谁过线。怎么用：最低伤害设为 1 或在临界点附近做修正，重甲的防御别高到让同级杂兵全是 0。〔[GameRes：战斗公式——伤害公式选择](https://www.gameres.com/forum/t/869656)；[GameRes：战斗公式的设计](https://www.gameres.com/457630.html)〕
- **2.3 显示命中与感觉命中。** 是什么：《火焰纹章》6–12 代用两个随机数取平均判定命中，显示 34% 实际约 23%，显示 98% 几乎不会落空。为什么：XCOM 的 Jake Solomon 说不想让玩家连续打空几个 85%，那会让游戏显得在惩罚人，所以低难度暗中给连续落空的士兵加命中，最高难度关掉。怎么用：沿用命中率就二选一——双随机数取平均，或连空补偿；Boss 最后一刀、救人这类关键动作尽量不靠骰子。〔[Serenes Forest: True Hit](https://serenesforest.net/general/true-hit/)；[Game Developer: Jake Solomon explains the careful use of randomness in XCOM 2](https://www.gamedeveloper.com/design/jake-solomon-explains-the-careful-use-of-randomness-in-i-xcom-2-i-)；[XCOM Wiki: Game difficulty (XCOM 2)](https://xcom.fandom.com/wiki/Game_difficulty_(XCOM_2))〕
- **2.4 输入随机优先于输出随机。** 是什么：输入随机在行动前揭晓（地图、敌人配置），输出随机在行动后掷骰（命中）。为什么：输出随机打断计划最招恨，《陷阵之志》几乎只留输入随机，被玩家叫作「没有随机的 XCOM」。怎么用：命中率可以留，但增援、Boss 招式、地形事件做成确定且提前告知的。〔[GMTK 小结（知乎）](https://zhuanlan.zhihu.com/p/106937258)；[Kotaku](https://kotaku.com/randomness-in-video-games-is-not-all-the-same-1841049263)；[ResetEra: Into the Breach looks like X-COM without the randomness](https://www.resetera.com/threads/into-the-breach-looks-like-x-com-without-the-randomness.25973/)〕
- **2.5 伤害与回复的比例。** 是什么：回复也要花掉一个人的一次行动。为什么：如果一次回复能抵消前线一整轮的伤害，最优解就是原地龟缩，XCOM 2 正是为治「慢慢挪、全员警戒」才加了回合限制。怎么用：参照《火焰纹章》GBA 三作——治疗杖回复「魔力＋10」、伤药固定回复 10，伤药因此前期更值、后期不够用；【推导】一次治疗约等于前线一人一轮承伤的 50–100%，持久战关给有限的回复道具，而不是让僧侣无限奶住。〔[Player.One：Jake Solomon 谈任务计时](https://www.player.one/whats-next-xcom-jake-solomon-talks-xcom-5-dlcs-and-mission-timers-589331)；[Fire Emblem Wiki: Heal](https://fireemblemwiki.org/wiki/Heal)；[Fire Emblem Wiki: Vulnerary](https://fireemblemwiki.org/wiki/Vulnerary)〕
- **2.6 威胁范围＝移动力＋射程。** 是什么：每个敌人的威胁区是它能走到的格子再外扩攻击距离。为什么：玩家靠威胁区「诱敌」，只让一个扛得住的人进圈、在敌方回合吃反击，这是战棋最核心的一步决定；接敌前空走的回合只是操作成本，不产生紧张感。怎么用：像《火焰纹章》的「危险区」那样一键显示全体敌人威胁区（《风花雪月》还预告敌人会打谁），注意我方单位挡路会缩小威胁区、挪开就变大；开局与敌人之间留约 1 次行动的缓冲让玩家摆阵，再多就是空走，第一回合结束前就要决定「谁先进圈」。〔[GameRes 论坛：战棋关卡设计思路——一些体验设计的方式](https://bbs.gameres.com/thread_832692_1_1.html)；[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[SuperCheats: Three Houses Danger Radius](https://www.supercheats.com/fire-emblem-three-houses/walkthrough/danger-radius)；[GameFAQs: Awakening danger zone 讨论](https://gamefaqs.gamespot.com/boards/643003-fire-emblem-awakening/66875829)；[FE Heroes Wiki: Baiting Foes](https://feheroes.fandom.com/wiki/Baiting_Foes)〕
- **2.7 行动次数：同时接战不超过我方能处理的量。** 是什么：玩家每回合的行动数决定能同时处理几个威胁，《陷阵之志》只用 3 台机甲、8×8 格就够有深度。为什么：同时打到我方的敌人超过我方行动数，局面就失控，难度来自运气而不是决策。怎么用：【推导】同一回合能打到我方的敌人数 ≤ 我方出场人数；两人起步时，一回合最多 2–3 个敌人能碰到你。〔[Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)；[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)〕
- **2.8 敌我兵力比：总数可以多，同时交手要少。** 是什么：地图上敌人多营造战场感，但用分组仇恨关联和援军（召唤也算）分批，让玩家只盯眼前的小战场。为什么：像武打片的围殴，看着人多，真正和主角交手的只有 1–3 个。怎么用：XCOM 的「小队（pod）」就是这样：外星人成组巡逻，被发现才整组激活，玩家通常一次只打一组，而一口气惊动两三组会被 2–3 倍兵力压住，这正是它最招骂的地方；【推导】总兵力 敌:我 约 1.5–3:1，其余敌人按组待命，靠「我方接近」或「到第 N 回合」触发，且触发前让玩家看得到这组在哪。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[Game Developer: A Deep Dive Into XCOM and XCOM 2](https://www.gamedeveloper.com/design/a-deep-dive-into-xcom-and-xcom-2)；[Wikipedia: XCOM: Enemy Unknown](https://en.wikipedia.org/wiki/XCOM:_Enemy_Unknown)〕
- **2.9 经验：补刀与追赶。** 是什么：《火焰纹章》最后一刀的人拿最多经验，所以「谁来补刀」本身是策略；拐杖角色等级高，打低级敌人几乎不涨经验。为什么：经验随等级差递减，落后的人自然练得快，新人和老兵才能同场。怎么用：照《烈火之剑》的式子——造成伤害得 (31＋敌等级−我等级)÷职业系数，击杀另加一笔，已转职按等级＋20 算，击破首领再加 40，低级角色杀首领常常一次拿满 100 必升级——经验按「击杀＞参战」分配并随等级差递减，让拐杖和老伙伴主动把补刀让给新人，首领的最后一刀成为「给谁」的取舍。本作沿用原作的经验公式，见第 6 节。〔[机核：几个经典战棋游戏分析](https://www.gcores.com/articles/188202)；[Serenes Forest: Blazing Sword Calculations](https://serenesforest.net/blazing-sword/miscellaneous/calculations/)；[Fire Emblem Wiki: Experience](https://fireemblemwiki.org/wiki/Experience)；[Fire Emblem Wiki (Fandom): Jagen](https://fireemblem.fandom.com/wiki/Jagen)〕
- **2.10 等级上限跟剧情走。** 是什么：《皇家骑士团 重生》的联队等级是随剧情推进的全队等级上限，通常比当时的主要 Boss 低两级，满级后的经验分给未满级的人；《if 暗夜》每关经验与金钱有限、不能刷。为什么：上限让设计者知道玩家在第 N 关大约多少级，数值才定得住；开发者说难度是按游戏节奏调的，等级上限、商店、技能都为此改过。怎么用：十关各设等级上限，归队角色到队即等于当前上限，溢出经验均分给未满级者（本作的做法见第 6 节）。〔[RPG Site: Tactics Ogre Reborn 评测](https://www.rpgsite.net/review/13468-tactics-ogre-reborn-review)；[Frontline Gaming Japan：Reborn 开发者访谈](https://www.frontlinejp.net/2022/12/07/tactics-ogre-reborn-developer-interview/)；[Wccftech](https://wccftech.com/tactics-ogre-reborn-gameplay-ui-improvements-detailed-wont-feature-new-content-as-the-developer-deemed-psp-version-already-had-more-than-enough/)；[Wikipedia: Fire Emblem Fates](https://en.wikipedia.org/wiki/Fire_Emblem_Fates)〕
- **2.11 难度曲线跟着玩家技能涨。** 是什么：难度要以合适的速度随玩家变强而上升，《Game Balance》的做法是把「玩家实力曲线」和「敌方实力曲线」画在一起比，二者之差就是难度。为什么：涨得太快玩家受挫，太慢玩家无聊；而且玩家普遍把游戏想得比实际难，靠角色强度的挑战也比靠操作技巧的挑战好用数学调平。怎么用：【推导】每次有人归队后的一关略松，下一关考新组合；整部只放两个尖峰（中段危机、终章），尖峰关可以在前中段造一个「局面像要失控」的危机，但别挑战玩家的心理底线。〔[Ian Schreiber: Game Balance Concepts, Level 7: Advancement, Progression and Pacing](https://gamebalanceconcepts.wordpress.com/2010/08/18/level-7-advancement-progression-and-pacing/)；[Schreiber & Romero《Game Balance》第 11 章 Progression in PvE Games](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-11/progression-pve-games-ian-schreiber-brenda-romero)；[GameRes 论坛：战棋关卡设计思路](https://bbs.gameres.com/thread_832692_1_1.html)〕
- **2.12 难度档优先改「时机」，少改「数值」。** 是什么：《烈火之剑》困难模式的区别之一是增援提前一回合，琳篇困难模式去掉剧本必暴击；XCOM 2 外传允许把回合限制翻倍。为什么：改时机让同一张图出现新的问题，全体加数值只会让每刀更疼、不更有趣。怎么用：难度档调增援时机、回合上限、敌方 AI 激进程度，数值只微调。〔[极特攻略：烈火之剑](https://www.gametoeasy.com/post/370.html?page=all)；[LP Archive: Lyn Hard Mode](https://lparchive.org/Fire-Emblem-Blazing-Sword/Update%2045/)；[GamesBeat: War of the Chosen](https://gamesbeat.com/xcom-2-war-of-the-chosen-upgrades-design-enemies-and-cinematic-story/)〕

---

## 3. 关卡

### 3.1 胜负条件的种类，以及它们各问什么

是什么：胜利条件有全灭、击破首领、压制（占点）、防守 N 回合、生存 N 回合、撤离、抵达，另有可选目标；失败条件有主角阵亡、指定 NPC 阵亡、据点被踩、超过回合、资源耗尽（《陷阵之志》的电网）。为什么：每种条件逼出不同的打法，换条件比换数值更能让关卡不重样。怎么用：按下表选，一部十关里至少用到五种。〔[Fire Emblem Wiki: Objectives](https://fireemblemwiki.org/wiki/Objectives)；[Fandom: Victory Condition](https://fireemblem.fandom.com/wiki/Victory_Condition)；[Fandom: Defend](https://fireemblem.fandom.com/wiki/Defend)；[Fire Emblem Wiki: Unhappy Reunion](https://fireemblemwiki.org/wiki/Unhappy_Reunion)；[Fire Emblem Wiki: Eternal Stairway](https://fireemblemwiki.org/wiki/Eternal_Stairway)；[极特攻略：封印之剑](https://www.gametoeasy.com/post/365.html?page=all)；[极特攻略：烈火之剑](https://www.gametoeasy.com/post/370.html?page=all)；[17173：风花雪月评测](https://newgame.17173.com/content/07302019/114912632.shtml)；[Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)〕

| 条件 | 问玩家的问题 | 先例 |
|---|---|---|
| 全灭 | 能不能在不被消耗的前提下清场 | 系列常规 |
| 击破首领 | 能不能打穿防线直取一点；速杀还是清兵拿经验 | 《梦幻模拟战》指挥官 |
| 压制／占点 | 走哪条路推进 | 《封印之剑》19B、20A |
| 防守 N 回合 | 隘口守得住吗；地形变了怎么办 | 《if 暗夜》第 10 章（11 回合，第 6 回合末放水） |
| 生存 N 回合 | 资源撑得住吗 | 防守／生存图常见 7–15 回合 |
| 撤离 | 能不能避战、靠机动走掉 | 《if 暗夜》第 12、15、21 章 |
| 保护 NPC | 能不能护住会乱跑的弱者 | 《烈火之剑》第 4 章屋内 NPC 存活 7 回合 |
| 可选目标 | 冒多大险换奖励 | 《风花雪月》限时救人、截断逃兵 |

- **3.2 每关都要有「不能龟缩」的理由。** 是什么：回合限制、与 NPC 抢首领、地图中途变化、不给经验的无限增援，都是逼玩家往前走的手段（《陷阵之志》每场固定回合数，就是为了让战斗保持短小）。为什么：没有压力时玩家每关都会「慢慢挪、全员警戒」打成一个样，Solomon 加计时正为此；但他也承认计时太多会招反感，应提供关掉的选项。怎么用：每关从这张单子里挑一个反龟缩手段，开场就让玩家知道，回合给得宽一点。〔[Crusader Grant: Conquest Map Design Review Part 3](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-3.html)；[Fire Emblem Wiki: Unhappy Reunion](https://fireemblemwiki.org/wiki/Unhappy_Reunion)；[Fire Emblem Wiki: Eternal Stairway](https://fireemblemwiki.org/wiki/Eternal_Stairway)；[Player.One](https://www.player.one/whats-next-xcom-jake-solomon-talks-xcom-5-dlcs-and-mission-timers-589331)；[Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)〕
- **3.2b 目标里埋第二条路。** 是什么：目标写「坚持 5 回合」，但敌人其实由某些单位或机关召唤，击破召唤者也能过关。为什么：单纯的「坚持 N 回合」会诱导玩家只带防守型角色龟缩，埋一条进攻解后带进攻型角色也是对的；同一种目标也别反复用，玩家需要新鲜感。怎么用：每个防守／生存关配一个「能提前结束」的进攻解，放在有风险的位置。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)〕
- **3.3 地图大小跟着胜负条件走。** 是什么：防守关用小图，限时或追击关用长图，从一角到另一角至少要移动力最高的角色行动 3 次。为什么：地图尺寸决定接敌要几回合，空走的回合只增加操作、不增加紧张。怎么用：开局到第一次接敌最多空走 1 回合。〔[机核：以人为棋，以天地为盘——SRPG 关卡设计的分析和总结](https://www.gcores.com/articles/154216)；[GameRes 论坛：战棋关卡设计思路](https://bbs.gameres.com/thread_832692_1_1.html)〕
- **3.4 至少两条路。** 是什么：地形只有一条线时只有一种打法，同样的敌人放进 3×5 的棋盘，玩家就能走上路、下路，甚至绕过首领直奔撤离点。为什么：线性棋盘的解法只剩地形加成和数值计算，组合和机动没有用武之地。怎么用：主路（正面、有隘口）＋侧翼（远但能绕后）＋只有特定岗位能走的第三条（翼族飞越、盗贼开门；本作开门要改代码，见第 6 节）。〔[豆瓣：浅谈 SRPG 战棋游戏的历史发展和关卡设计](https://www.douban.com/note/834376093/)；[GameRes：基于关卡设计维度的战棋游戏系统与关卡设计用例](https://www.gameres.com/875718.html)〕
- **3.5 隘口要有失效的时刻。** 是什么：地形分两类，一类值得占（加成、判胜），一类影响移动（墙、泥地）；隘口属于后者里最强的一种。为什么：隘口把「敌多我少」变成「同时只打一两个」，是少打多的前提，但它一直有效就成了龟缩——《if 暗夜》第 10 章先给一格宽的隘口让重甲守，第 6 回合末放水后敌人能绕过所有防线。怎么用：给玩家一个隘口，再安排一个会打破它的事件（侧翼增援、地形变化、飞兵）。〔[战术级战棋设计思考随笔 3：棋盘设计](https://zafara-zd.github.io/blog/%E6%88%98%E6%9C%AF%E7%BA%A7%E6%88%98%E6%A3%8B%E8%AE%BE%E8%AE%A1%E6%80%9D%E8%80%83%E9%9A%8F%E7%AC%943-%E6%A3%8B%E7%9B%98%E8%AE%BE%E8%AE%A1/)；[Fire Emblem Wiki: Unhappy Reunion](https://fireemblemwiki.org/wiki/Unhappy_Reunion)〕
- **3.6 增援：先预告，不当回合行动，别刷在脸上。** 是什么：《火焰纹章》多数作品里增援出现当回合不能行动，能当回合行动的「伏兵刷新」被认为最难规划、最招恨。为什么：玩家无法为看不见的东西做取舍，输了只会觉得被坑；《陷阵之志》提前一回合标出刷新点，站上去就能堵住（受 1 点伤），反而成了一道选择题。怎么用：增援一律提前一回合预告来源（本作没有自动的增援标记，做法见第 6 节），可以派人堵口，刷新点离我方至少一个移动力。〔[Fire Emblem Wiki: Reinforcement](https://fireemblemwiki.org/wiki/Reinforcement)；[GameFAQs: Ambush spawns](https://gamefaqs.gamespot.com/boards/204445-fire-emblem-three-houses/78116754)；[Into the Breach Wiki: Spawn Tile](https://intothebreach.fandom.com/wiki/Spawn_Tile)；[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)〕
- **3.7 增援时机按情绪曲线排。** 是什么：【推导】增援是控制交战场数的开关，前段的仗要简单（热身），最后一场要长（沉浸），难度档可以只把增援提前一回合。为什么：玩家刚「破局」、敌人已无威胁的那段是垃圾时间，这时来新问题最能把紧张感拉回来。怎么用：【推导】10–15 回合的关排两波，第 3–4 回合一波（前线刚清完）、中后段一波打侧后，逼后排临场改站位。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[极特攻略：烈火之剑](https://www.gametoeasy.com/post/370.html?page=all)〕
- **3.8 增援当作「没做好某事」的后果。** 是什么：《封印之剑》外传「疾风之弓」压错蒙古包才出援军；据玩家讨论，《风花雪月》苍月线（青狮子学级）终章会预告增援，并能派人堵住楼梯。为什么：有因果的惩罚让玩家输得服气，并多出一个「要不要去防」的取舍。怎么用：设计「第 N 回合前没关城门 → 城门涌兵」这类可预防的增援。〔[极特攻略：封印之剑](https://www.gametoeasy.com/post/365.html?page=all)；[GameFAQs: Ambush spawns](https://gamefaqs.gamespot.com/boards/204445-fire-emblem-three-houses/78116754)〕
- **3.9 每关至少一个要冒险才拿得到的东西。** 是什么：可选目标（限时救人、截断逃兵）、侧翼宝箱、早结束但少拿经验的首领。为什么：取舍才是决策，《风花雪月》的可选目标正因为高风险高回报才考验对战局的理解；《梦幻模拟战》的「杀指挥官还是多拿经验」是评测最常提的取舍。怎么用：奖励放在偏离主路或威胁区边缘，拿它就要分兵或多冒一回合险。〔[17173：风花雪月评测](https://newgame.17173.com/content/07302019/114912632.shtml)；[RPG Site: Langrisser I & II 评测](https://www.rpgsite.net/review/9504-langrisser-i-ii-review)〕
- **3.10 一关只问一个问题。** 是什么：越靠前的关越考对单个机制的理解，越靠后越考多个机制的组合；关卡由「教学、测试、变化」几个节拍组成。为什么：额外机制在战棋里要挂在敌人或地形上才有意义，一关塞太多机制，玩家分不清自己在学什么。怎么用：开工前写一句「这关问玩家：____？」，地图、敌人、增援、台词都围绕它；后段关卡可以把前面两个问题叠起来问。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[知乎：The Level Design Book「关卡节奏」译文](https://zhuanlan.zhihu.com/p/605974977)；[豆瓣：浅谈 SRPG 关卡设计](https://www.douban.com/note/834376093/)〕
- **3.11 防一招通吃。** 是什么：同一关放两组需要不同打法的敌人，首领给多条命或多个首领，挡住「一人直扑首领」的速通。为什么：一招能过的关只考一次决策，后面全是重复操作。怎么用：做完一关假设玩家只用最强的一招（翼族直取首领、全员龟缩），看能不能过。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[Crusader Grant: Conquest Map Design Review Part 4](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-4.html)〕
- **3.12 单关时长与记忆点。** 是什么：掌机和手机 5–15 分钟一关，PC 和主机 10–30 分钟，前期关更短（XCOM 团队试玩数月后把单场定在平均约 20 分钟、最长不超过 50 分钟）；每关留一个记忆点（场面、阵型、陷阱）。为什么：短篇靠每关都有一件「讲得出来的事」撑住，长而平的关最先被忘掉。怎么用：每关写下一句记忆点，和「这关问的问题」放在一起审。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[Game Developer: Classic Postmortem: XCOM: Enemy Unknown](https://www.gamedeveloper.com/design/classic-postmortem-i-xcom-enemy-unknown-i-which-turns-5-today)〕
- **3.13 教学关不像教学。** 是什么：《烈火之剑》把教学写成琳的十章小故事，序章用固定暴击让主角帅一把，支援等系统几关后才随整备画面开放；困难模式去掉这些剧本，就成了普通关卡。为什么：玩家以为自己在看故事、在帮主角，不觉得在上课，而且每次只多学一件事。怎么用：新机制第一次出现时放在安全、几乎必成功、有剧情理由的情境里，台词只说人物关心的事，系统按关逐个开放。〔[Wikipedia: The Blazing Blade](https://en.wikipedia.org/wiki/Fire_Emblem:_The_Blazing_Blade)；[Fire Emblem Wiki: The Blazing Blade](https://fireemblemwiki.org/wiki/Fire_Emblem:_The_Blazing_Blade)；[Digitally Downloaded](https://www.digitallydownloaded.net/2023/01/why-fire-emblem-the-blazing-blade-has-the-greatest-tutorial-of-all-time.html)；[LP Archive: Lyn Hard Mode](https://lparchive.org/Fire-Emblem-Blazing-Sword/Update%2045/)〕

---

## 4. 十关短篇的节奏

- **4.1 先例：琳篇。** 是什么：《烈火之剑》琳篇是序章加十章的小故事，琳从「草原上孤身一人的少女」成长为一支小部队的首领，新人在剧情里陆续加入（劝降的敌人、路过被卷入战斗的僧侣和法师）。为什么：它同时完成了教学、人物介绍和「队伍从小到大」三件事，被评为系列最好的教学。怎么用：本作十关直接照这个骨架排，每个归队角色有一段「为什么此时回来」的剧情。〔[RPGFan: Fire Emblem 评测](https://www.rpgfan.com/review/fire-emblem-3/)；[Wikipedia: The Blazing Blade](https://en.wikipedia.org/wiki/Fire_Emblem:_The_Blazing_Blade)；[Digitally Downloaded](https://www.digitallydownloaded.net/2023/01/why-fire-emblem-the-blazing-blade-has-the-greatest-tutorial-of-all-time.html)〕
- **4.2 两人起步要用小图和少敌人。** 是什么：两个人每回合只有两次行动，能同时处理的威胁极少。为什么：《陷阵之志》证明 3 个单位、8×8 格已足够有深度，人少时深度来自位置而不是数量。怎么用：【推导】开头两关约 8×8 到 10×10，敌人 3–6 个，同时能碰到我方的不超过 2 个，用地形（隘口、绕路）让两人以少打多。〔[Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)〕
- **4.3 归队关就是那个人的展示关。** 是什么：谁归队，那一关的「问题」就正好是他的岗位能解的（翼族战士对断崖、盗贼对锁门、僧侣对持久战）。为什么：一关只问一个问题（3.10），让新人当答案，玩家第一次见他就记住他能干什么。怎么用：【推导】归队可以写成我方增援从地图边出现，作为「好的意外」（本作战中插入友军要先补生成器，见第 6 节），下一关再把他和已有的人组合起来考。〔[机核：以人为棋，以天地为盘](https://www.gcores.com/articles/154216)；[RPGFan](https://www.rpgfan.com/review/fire-emblem-3/)〕
- **4.4 建议的十关骨架。** 是什么：【推导】按「两人 → 陆续归队 → 中段危机 → 组合 → 全队」排。为什么：前段靠单机制教学，后段靠组合加难，与 3.10 和 2.11 一致。怎么用：

| 关 | 队伍 | 这关的重心 | 难度位置 |
|---|---|---|---|
| 1 | 2 人 | 移动、攻击、反击；两人分工 | 最低，剧本保底 |
| 2 | 2 人 | 隘口以少打多；威胁区诱敌 | 低 |
| 3 | +1～2（第一批归队） | 新人岗位展示（如支援：回复） | 略升 |
| 4 | 4～5 人 | 两种敌人混编；第一次可选目标 | 中 |
| 5 | +1～2 | 新岗位展示（如机动：飞越） | 略降 |
| 6 | 分队或缺人 | 中段危机：增援从侧后来，局面像要失控 | 尖峰一 |
| 7 | 汇合 | 出场上限小于队伍人数，开始取舍 | 中 |
| 8 | +余下的人 | 两个机制叠加 | 中高 |
| 9 | 全队 | 两路同时推进，每个岗位都有活 | 高 |
| 10 | 全队 | 终章：前面问过的问题合在一起问 | 尖峰二 |

- **4.5 出场上限制造取舍。** 是什么：【推导】队伍人数超过出场格数后，「带谁」本身成为决策。为什么：所有人都能上时没有取舍，所有人都上不了时老伙伴等于没回来。怎么用：中后段出场上限比队伍少 2～3 人，终章放开全员（本作没有出场选择，见第 6 节）。
- **4.6 等级随章节锁定。** 是什么：每关一个等级上限（2.10），归队者按上限到队。为什么：十关的短篇没有刷级空间，数值必须能预估。怎么用：【推导】十关等级上限大致线性上升，转职若有，放在第 5～6 关前后，配合中段危机。本作的等级怎么定见第 6 节。〔[RPG Site: Tactics Ogre Reborn 评测](https://www.rpgsite.net/review/13468-tactics-ogre-reborn-review)〕

---

## 5. 做一关时逐项过的清单

**问题与目标**
- [ ] 这关只问一个问题：「____？」写得出一句话。
- [ ] 胜利条件、失败条件、回合数写清，开场就告诉玩家。
- [ ] 有一个「不能龟缩」的理由（回合限制／抢首领／地形变化／无经验增援）。
- [ ] 有一个记忆点。

**队伍**
- [ ] 本关出场几人、谁是必出；若有人归队，这关的问题正好由他解。
- [ ] 每个出场岗位至少有一次「只有他能做好」的机会。
- [ ] 查过翼族、盗贼、最强单体能不能把这关跳过。

**数值**
- [ ] 几刀表：主力打杂兵 __ 刀；杂兵打主力 __ 下；主力打首领 __ 刀；追击、暴击各跳一档后还合理。
- [ ] 没有同级 0 伤害；没有「一回合秒掉满血主力」的组合（剧本除外）。
- [ ] 一次治疗 ≤ 前线一人一轮承伤；回复资源有限。
- [ ] 敌人等级跟随我方还是写死；归队者的四维和对上当时队伍（本作没有等级上限，见第 6 节）。

**地图**
- [ ] 尺寸符合胜负条件（防守小、追击长）；最快单位角到角 ≥ 3 次行动。
- [ ] 开局在所有威胁区外 1–2 格，接敌前空走 ≤ 1 回合。
- [ ] 至少两条路：正面、侧翼，外加一条岗位专用路。
- [ ] 隘口有失效的时刻。
- [ ] 敌人至少两类、需要不同应对；同一回合能打到我方的敌人 ≤ 我方出场人数。

**增援与事件**
- [ ] 每波增援：第几回合、从哪来、提前一回合用对白或剧情交代（第 6 节）、当回合不行动、离我方至少一个移动力、能否堵口。
- [ ] 增援安排在玩家刚「稳了」的时候；至少有一波是「没做好某事」的后果。

**取舍**
- [ ] 至少一个要冒险才拿得到的东西（可选目标、侧翼宝箱、速杀首领 vs 多拿经验）。

**教学与难度**
- [ ] 新机制第一次出现在安全、有剧情理由的情境里；台词不讲系统。
- [ ] 这关在难度曲线上的位置（略松／考组合／尖峰）和上一关对得上。
- [ ] 难度档改的是增援时机、回合上限、AI 激进度，而不是全体加数值。
- [ ] 时长在 10–30 分钟；输了玩家知道为什么输。

---

## 6. 落到我们的规则

前面的方法多来自别的游戏，搬进本作要先对上本作的规则。下面的数字和出处见[规则数值手册](NUMBERS.md)（下称「数值手册」），原作关卡的统计和自制地图能做到哪一步见[原作关卡](ORIGINAL_LEVELS.md)。

- **不设等级上限，难度靠敌人的配置。** 敌人进场时以我方平均等级为中心往上调级，只升不降（数值手册 1.10），2.10、4.6 的「每关等级上限」在本作做不到，也用不着。一关的难度由敌人的种类、装备、人数和出场时机决定；要某个敌人的等级固定，把它的调级范围和离散都写 0。
- **归队者的等级手写。** 队员第一次登场的等级只由四维和决定，不看队伍当时多少级（数值手册第 0 节第 5 条）。归队或新加入的人要按当时队伍的水平写四维和：要 L 级，四维和至少 52＋5×(L−1)。
- **兜底的规则原作已经有了。** 攻不破防也有 3–7 点保底伤害，普通攻击落空后下一次命中会补偿，低等级打高等级的经验最多乘 5（数值手册 1.3、1.2、1.7）。第 0 节说的「宁可偏向玩家」和 2.9 的追赶不必另做，经验公式沿用原作。
- **老伙伴归队，带一道只有他能解的题**（4.3 落到原作队员身上）：
  - 重甲敌人交给雪拉：魔法完全不看防御。
  - 墙、悬崖、水挡住地面单位的地方交给雷特：飞行单位能越过去。
  - 挡得住路、挡不住箭的地形交给琥：远程攻击能隔着障碍打。
  - 隘口交给嚎：他的反击率 42%，一般单位只有 12%。
  - 漢克斯闪避 26，普通攻击打他只有七成左右命中；但魔法不看闪避，遇上法师要让他躲开。
- **胜负条件至少五种。** 原作 49 场剧情战里 31 场以全灭或击败首领为主要胜利条件，有回合上限的只有龍之息（火山）（LEVEL013）一场。十关上下的短篇照 3.1 的表至少用五种，每种问一个不同的问题；原作现成的写法见原作关卡 2.2，原作没有的「敌人走到某处即败」也能只写数据（推断，没实跑）。画面上不显示回合数，有回合上限就把回合数写进看板讯息、开场弹出（原作关卡 2.4 第 6 条）。
- **增援用剧情和对白预告。** 本作没有自动的增援标记，3.6「提前一回合标出来源」要自己做：上一回合的对白、开场的交代、看得见的门口和路口，或用 `actInsertShowPosObject` 在地图上标出格子（原作用它标目标格，拿来标援兵来处没试过）。要增援晚几回合再动，插入后接 `actSetPrevInsertObjectWaitRound`。
- **地图能设计的只有路。** 原作战斗地图玩起来是平面，没有高低地，也没有高地加成。能拿来出题的是这几样：哪里能走，哪里被墙、房子、悬崖、水挡住；路有多远、有几条、卡口在哪；飞行单位能越过障碍，远程攻击能隔着障碍打。3.4「至少两条路」、3.5「隘口要有失效的时刻」都靠这几样做。开门、塌方、宝箱、连飞行和射程都挡的墙，现在要改代码才有（原作关卡 2.2）。
- **战中归队要先补生成器。** 原作让归队的人从图边进场、沿用队伍的成长，重制引擎也支持，但手写关的生成器把战中插入的单位一律建成敌方。不改代码的变通是插入后转成我方，代价是按模板出生、不带之前的成长，还没有实跑（原作关卡 2.4 第 3 条、数值手册 4.4）。4.3「归队写成我方增援从地图边出现」要等生成器补上。
- **没有出场选择。** 原作和重制都没有选人画面，队伍槽最多 9 个；手写关 `units[]` 里写几个我方单位就上几个。4.5「出场上限制造取舍」要改代码，在那之前取舍只能靠剧情分队。
- **短篇的成长靠归队和换装。** 到 L39 以后每升一级要 2000 经验，十关上下升不了几级；中后期强度的主轴是装备（数值手册第 0 节第 8 条）。成长感要从新人归队和换装来，别指望练级。

---

## 附：来源

**设计者访谈与演讲**
- [GDC Vault: 'Into the Breach' Design Postmortem（Matthew Davis，GDC 2019）](https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design)
- [Kotaku: The Creators Of Into The Breach Came Very Close To Giving Up On It](https://kotaku.com/the-creators-of-into-the-breach-came-very-close-to-givi-1833498295)
- [Sid Meier GDC 2010「The Psychology of Game Design」笔记（gamedev.net）](https://www.gamedev.net/blogs/entry/2111213-the-psychology-of-game-design-sid-meier/)；[Ada Chen Rekhi 笔记](https://www.adachen.com/gdc10-notes-sid-meier-on-why-everything-you-know-is-wrong/)
- [Game Developer: Jake Solomon explains the careful use of randomness in XCOM 2](https://www.gamedeveloper.com/design/jake-solomon-explains-the-careful-use-of-randomness-in-i-xcom-2-i-)
- [Player.One: Jake Solomon Talks XCOM, DLCs And Mission Timers](https://www.player.one/whats-next-xcom-jake-solomon-talks-xcom-5-dlcs-and-mission-timers-589331)；[GamesBeat: War of the Chosen](https://gamesbeat.com/xcom-2-war-of-the-chosen-upgrades-design-enemies-and-cinematic-story/)
- [Frontline Gaming Japan: Tactics Ogre Reborn Developers Discuss Changes and Balance](https://www.frontlinejp.net/2022/12/07/tactics-ogre-reborn-developer-interview/)

**书与课程**
- [Ian Schreiber: Game Balance Concepts, Level 7: Advancement, Progression and Pacing](https://gamebalanceconcepts.wordpress.com/2010/08/18/level-7-advancement-progression-and-pacing/)（课程后来扩写为 Schreiber 与 Brenda Romero 合著的《Game Balance》）
- [Schreiber & Romero《Game Balance》（CRC Press，2021）](https://www.routledge.com/Game-Balance/Schreiber-Romero/p/book/9781498799577)：[第 5 章 Finding an Anchor](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-5/finding-anchor-ian-schreiber-brenda-romero)；[第 10 章 Combat](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-10/combat-ian-schreiber-brenda-romero)；[第 11 章 Progression in PvE Games](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-11/progression-pve-games-ian-schreiber-brenda-romero)；[第 18 章 Dependent Randomness](https://www.taylorfrancis.com/chapters/mono/10.1201/9781315156422-18/dependent-randomness-ian-schreiber-brenda-romero)

**游戏分析（英文）**
- [Serenes Forest: True Hit](https://serenesforest.net/general/true-hit/)；[Serenes Forest: Blazing Sword Calculations](https://serenesforest.net/blazing-sword/miscellaneous/calculations/)
- [Fire Emblem Wiki: Heal](https://fireemblemwiki.org/wiki/Heal)；[Vulnerary](https://fireemblemwiki.org/wiki/Vulnerary)；[Experience](https://fireemblemwiki.org/wiki/Experience)
- 危险区：[SuperCheats: Three Houses Danger Radius](https://www.supercheats.com/fire-emblem-three-houses/walkthrough/danger-radius)；[GameFAQs: Awakening danger zone 讨论](https://gamefaqs.gamespot.com/boards/643003-fire-emblem-awakening/66875829)；[FE Heroes Wiki: Baiting Foes](https://feheroes.fandom.com/wiki/Baiting_Foes)
- XCOM：[Game Developer: A Deep Dive Into XCOM and XCOM 2](https://www.gamedeveloper.com/design/a-deep-dive-into-xcom-and-xcom-2)；[Classic Postmortem: XCOM: Enemy Unknown](https://www.gamedeveloper.com/design/classic-postmortem-i-xcom-enemy-unknown-i-which-turns-5-today)；[Wikipedia: XCOM: Enemy Unknown](https://en.wikipedia.org/wiki/XCOM:_Enemy_Unknown)
- [Fire Emblem Wiki: Reinforcement](https://fireemblemwiki.org/wiki/Reinforcement)；[Objectives](https://fireemblemwiki.org/wiki/Objectives)；[Unhappy Reunion](https://fireemblemwiki.org/wiki/Unhappy_Reunion)；[Eternal Stairway](https://fireemblemwiki.org/wiki/Eternal_Stairway)；[The Blazing Blade](https://fireemblemwiki.org/wiki/Fire_Emblem:_The_Blazing_Blade)
- [Fandom: Victory Condition](https://fireemblem.fandom.com/wiki/Victory_Condition)；[Defend](https://fireemblem.fandom.com/wiki/Defend)；[Jagen](https://fireemblem.fandom.com/wiki/Jagen)
- [Crusader Grant: Conquest Map Design Review Part 3](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-3.html)；[Part 4](http://thecrusadergrant.blogspot.com/2017/09/conquest-map-design-review-part-4.html)
- [GameFAQs: Ambush spawns（风花雪月版）](https://gamefaqs.gamespot.com/boards/204445-fire-emblem-three-houses/78116754)
- [Set Side B: What is a Jagen?](https://setsideb.com/what-is-a-jagen/)；[TV Tropes: Availability vs Growth](https://tvtropes.org/pmwiki/pmwiki.php/Characters/FireEmblemHeroicArchetypesAvailabilityVsGrowth)
- [Digitally Downloaded: Blazing Blade 的教学](https://www.digitallydownloaded.net/2023/01/why-fire-emblem-the-blazing-blade-has-the-greatest-tutorial-of-all-time.html)；[RPGFan: Fire Emblem 评测](https://www.rpgfan.com/review/fire-emblem-3/)；[LP Archive: Lyn Hard Mode](https://lparchive.org/Fire-Emblem-Blazing-Sword/Update%2045/)
- [Wikipedia: Langrisser](https://en.wikipedia.org/wiki/Langrisser)；[Langrisser Wiki: I & II Gameplay](https://langrisser.fandom.com/wiki/Langrisser_I_%26_II_Gameplay)；[RPG Site: Langrisser I & II](https://www.rpgsite.net/review/9504-langrisser-i-ii-review)；[GamerEscape](https://gamerescape.com/2020/03/03/review-langrisser-i-ii/)
- [RPG Site: Tactics Ogre Reborn](https://www.rpgsite.net/review/13468-tactics-ogre-reborn-review)；[Wccftech: Reborn Gameplay](https://wccftech.com/tactics-ogre-reborn-gameplay-ui-improvements-detailed-wont-feature-new-content-as-the-developer-deemed-psp-version-already-had-more-than-enough/)
- [Into the Breach - Wikipedia](https://en.wikipedia.org/wiki/Into_the_Breach)；[Into the Breach Wiki: Spawn Tile](https://intothebreach.fandom.com/wiki/Spawn_Tile)；[ResetEra 讨论](https://www.resetera.com/threads/into-the-breach-looks-like-x-com-without-the-randomness.25973/)
- [XCOM Wiki: Game difficulty (XCOM 2)](https://xcom.fandom.com/wiki/Game_difficulty_(XCOM_2))
- [Kotaku: Randomness In Video Games Is Not All The Same](https://kotaku.com/randomness-in-video-games-is-not-all-the-same-1841049263)
- [Wikipedia: Fire Emblem Fates](https://en.wikipedia.org/wiki/Fire_Emblem_Fates)；[Wikipedia: The Blazing Blade](https://en.wikipedia.org/wiki/Fire_Emblem:_The_Blazing_Blade)
- 职业分工通论：[TV Tropes: Damager, Healer, Tank](https://tvtropes.org/pmwiki/pmwiki.php/Main/DamagerHealerTank)；[Wikipedia: Healer](https://en.wikipedia.org/wiki/Healer_(video_games))；[Game Design Skills: Tank in RPG](https://gamedesignskills.com/game-design/tank-in-rpg/)

**中文策划文章**
- [机核：以人为棋，以天地为盘——SRPG 游戏关卡设计的分析和总结](https://www.gcores.com/articles/154216)
- [机核：几个经典战棋游戏分析](https://www.gcores.com/articles/188202)
- [GameRes 论坛：战棋关卡设计思路——一些体验设计的方式](https://bbs.gameres.com/thread_832692_1_1.html)
- [豆瓣：浅谈 SRPG 战棋游戏的历史发展和关卡设计](https://www.douban.com/note/834376093/)
- [GameRes：基于关卡设计维度的战棋游戏系统与关卡设计用例](https://www.gameres.com/875718.html)
- [战术级战棋设计思考随笔 3：棋盘设计](https://zafara-zd.github.io/blog/%E6%88%98%E6%9C%AF%E7%BA%A7%E6%88%98%E6%A3%8B%E8%AE%BE%E8%AE%A1%E6%80%9D%E8%80%83%E9%9A%8F%E7%AC%943-%E6%A3%8B%E7%9B%98%E8%AE%BE%E8%AE%A1/)
- [indienova：游戏战斗设计基础（十二）数值框架搭建及战斗平衡计算实践](https://indienova.com/u/yitiaodayu/blogread/30813)
- [GameRes：战斗公式——伤害公式选择](https://www.gameres.com/forum/t/869656)；[GameRes：战斗公式的设计](https://www.gameres.com/457630.html)；[GameRes：战斗数值模型搭建](https://www.gameres.com/669283.html)
- [知乎：火焰纹章核心战斗公式解析（烈火之剑）](https://zhuanlan.zhihu.com/p/429568333)；[18183：Engage 伤害公式](https://m.18183.com/gonglue/202302/4450429.html)
- [知乎：GMTK「The Two Types of Random」小结](https://zhuanlan.zhihu.com/p/106937258)；[知乎：The Level Design Book「关卡节奏」译文](https://zhuanlan.zhihu.com/p/605974977)
- [17173：风花雪月评测](https://newgame.17173.com/content/07302019/114912632.shtml)
- [极特攻略：封印之剑](https://www.gametoeasy.com/post/365.html?page=all)；[极特攻略：烈火之剑](https://www.gametoeasy.com/post/370.html?page=all)
