# 原作关卡模式与自制地图能力

> 依据：本仓库的数据与代码。文中的「文件:行号」只帮助定位，代码一改行号就会漂，按同处写的函数名或常量名查，不按行号。数字由一次性脚本从下列文件算出：`content/battles/campaign.json` 登记的正式战斗、各场 battle JSON（`playable_units` 的 `battle_actor_role`、`resources.terrain`、`resources.map_texture`）、`content/imported/hsl/story_corpus/scripts/` 的 `WINFAILnnn.json` 与 `STORYnnn.json`。标"推断"的是读代码得出、没有实跑过的结论。

逐场的设计拆解（每场的决定、棋盘、节奏、打法、手法）见 [原作关卡的设计](ORIGINAL_LEVEL_DESIGN.md)；这份只记统计和能力核对。

## 速览

- 127 场＝49 场剧情战（LEVEL001–080 里 44 场＋LEVEL900–904）＋78 场遭遇战（LEVEL501–578）。遭遇战全是"全灭／雷歐納德死亡"，借剧情战地图，没有事件；关卡设计的花样都在 49 场剧情战里。
- 49 场剧情战按主要胜利条件分：全灭 18、击败首领 13、全员撤离 7、到达 4、坚持 N 回合 3、取物／寻物 3、剧情抉择 1；8 场同时开着两条胜利路线。
- 31 场开局时胜利条件还没开：要等某个回合、某一波增援或某个阶段的事件才武装，开局只有失败条件生效。
- 失败：45 场是雷歐納德死亡；19 场另有指定队员死亡即败；6 场要保护友军（村民、商人、市民、船）；只有 1 场有回合上限（龍之息（火山）（LEVEL013））。
- 地图宽 20–60、高 17–60 格，中位约 1100 格，最常见 30×22；一屏是 20×15 格。开局敌人中位 13 名；34 场有增援，46 场有触发事件，11 场开局带友军。
- 自制地图：任意 PNG（尺寸必须正好是格数×32 像素）＋ `terrain.txt`（`#` 不能走，`.` 和 `1`–`9` 能走），上限 256×256 格。玩起来只分能走和不能走：`terrain.txt` 里的高度只是记法，记的是走过去费几步、哪两格之间走不通，画面上没有高低，也没有高地加成和地形防御；`#` 只挡地面单位，挡不住飞行单位和远程攻击。
- 19 个条件、47 个动作都只写数据就能用；战中开门／塌方／毒气、宝箱、连飞行和射程都挡的墙要改生成器。
- 唯一的手写关龍脊隘口（LEVEL200）没有自制底图：借原版戈爾山道（LEVEL002）的图，地形是在第 2 关地形上改写的。
- 六项能力（2.4）：待命、靠近才动、守点都只写数据；回合、进区域、死亡、HP 阈值都能触发对白、增援和改胜负。战中归队原作有 9 场先例，手写关要改生成器，或用 `actSetPlayerMode` 变通。原作和重制都没有出场选择。高度只是记移动的办法，玩家感觉到的只有能走和不能走，命中和伤害不看它。回合上限可以写进开场看板，画面上的倒数要改代码。

---

## 一、原作的关卡怎么设计的

### 1.1 样本与读法

- 127 场正式战斗＝`campaign.json` 里 kind 为战斗的 128 关去掉龍脊隘口（LEVEL200）。
- 胜负：每个 win／fail／event status 开头连续的 `actCheck…`／`actTRUE` 是条件。开局武装哪几个 status 看 STORY 的 `actInsertWinStatus`／`actInsertFailStatus`／`actInsertEventStatus`；条件是 `actTRUE` 的胜利，往回追到武装它的事件，取那个事件的条件。看板文字是该 status 的 `message`（说话者名＋讯息文字）。
- 人数：battle JSON 的 `playable_units`，即开局在场的单位，不含之后由 winfail 插入的。"受控 9"是全队 9 格名单，实际上场人数取决于当时的队伍。
- 地图：`resources.terrain` 的格数，以及 `resources.map_texture` 的像素尺寸。

### 1.2 遭遇战（78 场）

- 遭遇战没有自己的地图：26 张剧情战地图各配 3 场，三连号同图（如戈爾山道 · 遭遇戰（LEVEL501–503）都用戈爾山道（LEVEL002）的图）。
- 胜负全部相同：全灭胜（75 场用 `actCheckEnemyTotalNumber,0`，3 场用 `actCheckEnemy` 列出全部敌种），雷歐納德死亡败。
- 敌人 1–29 名，中位 9；全队上场；没有友军，没有增援。只有帕尼西雅城 廢墟 · 遭遇戰（LEVEL513–515）有一个事件：第 4 回合插入下雨的演出物件。
- 怎么进入：剧情战胜利段用 `actBMSetPointEvent,<点>,<5xx>,bmpmVisit` 和 `actBMSetPointEncounterRatio,<点>,<几率>` 把大地图点位改成遭遇点。

### 1.3 胜利条件分类（49 场剧情战，按主要胜利条件互斥计数）

| 主类 | 判定写法 | 场数 |
| --- | --- | ---: |
| 全灭 | `actCheckEnemyTotalNumber,0`，或 `actCheckEnemy` 列出全部敌种；少数为"剩 N 名以下" | 18 |
| 击败首领 | `actCheckEnemy,1,首领`／`actCheckPlayer,1,首领`／`actCheckPlayerHPLow,首领,1,阈值%`；首领常先设不死，打到阈值才判 | 13 |
| 全员撤离 | 每名队员一条 `actCheckPlayerArrivePos` 事件 → `actDeleteObject` 离场；`actCheckPlayerTotalNumber,0` → 武装胜利 | 7 |
| 到达（指定一人） | `actCheckPlayerArrivePos,token,serial,x1,y1,x2,y2`（像素矩形） | 4 |
| 坚持 N 回合 | 事件 `actCheckRoundNumber,N` → 武装胜利或直接进下一关 | 3 |
| 取物／寻物 | 走到祭坛格、踩中随机藏点、倒计时搜刮 | 3 |
| 剧情抉择（无战斗） | `actSelectInsertEvent` 二选一 | 1 |

各类包含的关卡：

- 全灭：歐姆村（LEVEL001）、戈爾山道（LEVEL002）、呼嘯平原（LEVEL005）、寧靜之森（LEVEL007）、帕尼西亞城　廢墟（LEVEL010）、深淵之沼（LEVEL015）、艾瓦台地（LEVEL017）、利魯瑪山地（LEVEL019）、哈莫特沙漠（LEVEL024）、日沒灣（LEVEL026）、約瑟河（LEVEL029）、沙羅尼亞近郊（LEVEL034）、黃昏之丘　陽（LEVEL039）、大地的裂縫（LEVEL043）、曼多力亞　對峙（LEVEL900）、菲納斯河畔　伏擊（LEVEL901）、哈莫特沙漠・魔騎士團（LEVEL903）、利魯瑪山地・再訪（LEVEL904）。
- 击败首领：盜賊洞窟（LEVEL003）、席達鎮（LEVEL006）、尼布魯瀑布（LEVEL022）、薩魯司海岸（LEVEL036）、古代神殿遺跡（LEVEL037）、聖靈之森（LEVEL040）、悲嘆之湖（LEVEL041）、惡夢的終曲（LEVEL052）、劫數・地劫神（LEVEL059）、自覺與宿命・塔克斯（LEVEL075）、最終的序曲・妖精王（LEVEL076）、破滅的命運・席德爾（LEVEL077）、終焉・咕嚕最終型態（LEVEL079）。
- 全员撤离：絕望之谷（LEVEL030）、漆黑之森（LEVEL031）、拉格納沼地（LEVEL032）、黃昏之丘　陰（LEVEL033）、幽闇墳場（LEVEL038）、亞修頓大橋（LEVEL044）、克萊恩城（LEVEL045）。
- 到达（指定一人）：龍之息（火山）（LEVEL013）、那可那魯邊境（LEVEL018）、回音之谷（LEVEL021）、逃出克萊恩城（LEVEL053）。
- 坚持 N 回合：巴瀚納海峽（LEVEL012）（23 回合）、棄卒（LEVEL051）（6 回合后援军到）、接觸・妖精王（LEVEL078）（10 回合）。
- 取物／寻物：眾神的宮殿遺址（LEVEL028）、禁忌之魂・墳場地下（LEVEL080）、艾瓦台地・尋（LEVEL902）。
- 剧情抉择：悲嘆之湖・兄弟的抉擇（LEVEL073）。

不互斥的计数：含"全灭"路线的 23 场，含"击败首领"路线的 14 场，含"单人到达"路线的 7 场（主类之外另有席達鎮（LEVEL006）、棄卒（LEVEL051）、艾瓦台地・尋（LEVEL902））。两条胜利路线同时开着的 8 场：歐姆村（LEVEL001，全灭或獸族 028 号剩不到 3 名就撤退）、席達鎮（LEVEL006，打倒隊長或逃出城鎮）、那可那魯邊境（LEVEL018，离开战场或全灭）、回音之谷（LEVEL021，离开战场或把克羅蒂打到 HP 40%）、拉格納沼地（LEVEL032）／亞修頓大橋（LEVEL044）／克萊恩城（LEVEL045）（全灭或全员撤离）、棄卒（LEVEL051，全灭或到达城门）。

胜利条件晚开：只有 16 场在开局剧本（STORY）里就武装了胜利；31 场的胜利要等事件武装。常见的触发："第 N 回合"（寧靜之森（LEVEL007）第 6 回合、帕尼西亞城　廢墟（LEVEL010）第 5 回合、艾瓦台地（LEVEL017）第 8 回合、棄卒（LEVEL051）第 6 回合、巴瀚納海峽（LEVEL012）第 23 回合），"前一波打完或撑满若干回合"（戈爾山道（LEVEL002）、尼布魯瀑布（LEVEL022）、哈莫特沙漠（LEVEL024）、沙羅尼亞近郊（LEVEL034）、黃昏之丘　陽（LEVEL039）、亞修頓大橋（LEVEL044）），"首领倒下"（破滅的命運・席德爾（LEVEL077）变身后），以及全员撤离的"我方在场 0 人"。另 2 场没有胜利段，由事件直接进下一关（悲嘆之湖・兄弟的抉擇（LEVEL073）、接觸・妖精王（LEVEL078））。开局就武装胜利的 16 场：歐姆村（LEVEL001）、呼嘯平原（LEVEL005）、席達鎮（LEVEL006）、龍之息（火山）（LEVEL013）、那可那魯邊境（LEVEL018）、日沒灣（LEVEL026）、約瑟河（LEVEL029）、聖靈之森（LEVEL040）、悲嘆之湖（LEVEL041）、大地的裂縫（LEVEL043）、惡夢的終曲（LEVEL052）、逃出克萊恩城（LEVEL053）、劫數・地劫神（LEVEL059）、自覺與宿命・塔克斯（LEVEL075）、最終的序曲・妖精王（LEVEL076）、終焉・咕嚕最終型態（LEVEL079）。这样做的效果是不能在最后一波到来前提前结束。

看板上的字不一定是真实条件：巴瀚納海峽（LEVEL012）的看板写"消滅所有敵人"，实际胜利由第 23 回合的事件武装。原版常用一条永不触发的事件（`actCheckRoundNumber,20000`／`30000` 或 `actFALSE`）只为在看板上多显示一行目标（巴瀚納海峽（LEVEL012）、艾瓦台地（LEVEL017）、利魯瑪山地（LEVEL019）、絕望之谷（LEVEL030）、古代神殿遺跡（LEVEL037）、艾瓦台地・尋（LEVEL902））。

### 1.4 失败条件（49 场剧情战）

- 雷歐納德死亡：45 场。例外 4 场：黃昏之丘　陰（LEVEL033）和沙羅尼亞近郊（LEVEL034）由緹娜领队，逃出克萊恩城（LEVEL053）只有"緹娜被捕"，悲嘆之湖・兄弟的抉擇（LEVEL073）没有胜负。
- 另有指定队员死亡即败：19 场。緹娜 8（含逃出克萊恩城（LEVEL053）的"被捕"）、雷特 3、克羅蒂 3、琥 2、雪拉 2、嚎 2、咕嚕 1。嚎（艾瓦台地（LEVEL017）、艾瓦台地・尋（LEVEL902））、克羅蒂（薩魯司海岸（LEVEL036））、咕嚕（深淵之沼（LEVEL015））的这条失败是在他们中途加入时才用 `actInsertFailStatus` 武装的。
- 保护对象：6 场。村民（歐姆村（LEVEL001）、沙羅尼亞近郊（LEVEL034））、商人克里夫（艾瓦台地（LEVEL017））、市民死 3 人以上（曼多力亞　對峙（LEVEL900））、船（巴瀚納海峽（LEVEL012）62 段、日沒灣（LEVEL026）26 段）。船由不会动的 101 号友军单位拼成，`actCheckEnemyNumber,SID_ENEMY101,62` 表示少一段就败。
- 回合上限：1 场，龍之息（火山）（LEVEL013）第 30 回合"火山爆發"。
- 原作没有"敌人走到某处就败"的关：全部 fail 的条件只用了 `actCheckPlayer`、`actCheckEnemyNumber`、`actCheckRoundNumber` 三种。

### 1.5 地图

- 尺寸（49 张剧情战地图）：宽 20–60、高 17–60 格；面积 480–2700 格，中位 1100。最常见 30×22（10 场，960×704 像素）和 40×30（7 场）。
- 一屏是 640×480 像素＝20×15 格，原作没有比一屏小的图。
- 最小：戈爾山道（LEVEL002）24×20、哈莫特沙漠（LEVEL024／903）20×30、絕望之谷（LEVEL030）40×17。最大：巴瀚納海峽（LEVEL012）45×60、亞修頓大橋（LEVEL044）和克萊恩城（LEVEL045）60×37、薩魯司海岸（LEVEL036）37×60、眾神的宮殿遺址（LEVEL028）30×60。
- 长条图：竖长的有漆黑之森（LEVEL031）22×50、拉格納沼地（LEVEL032）22×37、眾神的宮殿遺址（LEVEL028）30×60、薩魯司海岸（LEVEL036）37×60；横长的有絕望之谷（LEVEL030）40×17。
- 高度（只记移动，画面上看不出高低，见 2.1）：14 张全平；多数最高 2–5；有 8 关可走格高于 9：巴瀚納海峽（LEVEL012）、日沒灣（LEVEL026）最高 16，利魯瑪山地（LEVEL019）、利魯瑪山地・再訪（LEVEL904）和利魯瑪山地 · 遭遇戰（LEVEL525–527）最高 18，龍之息（火山）（LEVEL013）最高 21。高度在原作里主要用来隔区（日沒灣的海和船）和做减速区（漆黑之森、拉格納沼地的 0／2 交错），不用来造盘山路：龍之息（火山）9–21 级的高地是每级差 3 的阶梯断崖，走不上去，輝煌之器在高度 7 的主区里。
- 不可走格占 3%–75%，中位 21%。
- 图片尺寸都是格数×32 像素，只有最終的序曲・妖精王（LEVEL076）到終焉・咕嚕最終型態（LEVEL079）这四场的图是 960×720，比 30×22 格（960×704）高 16 像素。

### 1.6 人数（开局在场）

- 剧情战我方受控：全队 9 格 19 场，8 名 9 场，4–6 名 12 场，1–3 名 9 场。只有 1 名受控的：利魯瑪山地（LEVEL019／904，雷特）、棄卒（LEVEL051）、惡夢的終曲（LEVEL052）、逃出克萊恩城（LEVEL053）。从两人起步的有歐姆村（LEVEL001，雷歐納德＋琥）、戈爾山道（LEVEL002，雷歐納德＋琥）、帕尼西亞城　廢墟（LEVEL010，雷歐納德＋緹娜，敌 4 名，按敌数反复补兵，第 5 回合起才能赢）。黃昏之丘　陰（LEVEL033）和沙羅尼亞近郊（LEVEL034）是緹娜、琥、漢克斯、雪拉四人，没有雷歐納德。
- 敌方开局 1–75 名，中位 13。只有 1 名敌人的 3 场是单挑首领或无战斗（劫數・地劫神（LEVEL059）、悲嘆之湖・兄弟的抉擇（LEVEL073）、終焉・咕嚕最終型態（LEVEL079））；最多的是亞修頓大橋（LEVEL044），75 名。
- 遭遇战：全队上场，敌人 1–29 名，中位 9。

### 1.7 增援、事件、友军

- 增援（事件里插入敌人）：49 场剧情战里 34 场有，遭遇战 0 场；每场的插入动作 2–32 次。
- 增援怎么触发：
  - 按回合：31 场用 `actCheckRoundNumber` 起事件。
  - 按剩余敌数补兵：`actCheckEnemyNumber`／`actCheckEnemyTotalNumber` 起头。只补一次的如利魯瑪山地（LEVEL019）、漆黑之森（LEVEL031）、黃昏之丘　陰（LEVEL033）、悲嘆之湖（LEVEL041）、惡夢的終曲（LEVEL052）；链尾再用 `actInsertEventStatus` 武装自己，就成了打不完的兵：帕尼西亞城　廢墟（LEVEL010）、巴瀚納海峽（LEVEL012）、棄卒（LEVEL051）、逃出克萊恩城（LEVEL053）、艾瓦台地・尋（LEVEL902）。
  - 按首领 HP：絕望之谷（LEVEL030）在克羅蒂 HP 50% 时来一波。
  - "清场或撑满 N 回合"先到先得：回音之谷（LEVEL021）、尼布魯瀑布（LEVEL022）、黃昏之丘　陽（LEVEL039）、亞修頓大橋（LEVEL044）。
- 触发事件：46 场剧情战有（没有的是歐姆村（LEVEL001）、龍之息（火山）（LEVEL013）、終焉・咕嚕最終型態（LEVEL079））。每场 1–50 个，中位 4。事件起头最常用的条件（按场数）：回合 31、链式 `actTRUE` 15、敌人总数 13、HP 低于阈值 9、某人攻击某人 9、某类敌人数 9、`actCheckEnemy` 7、到达 7、我方在场总数 5。
- 友军：11 场开局带友军（1–62 名；巴瀚納海峽（LEVEL012）、日沒灣（LEVEL026）的友军是船的段）。还有中途入队的：
  - 漢克斯：盜賊洞窟（LEVEL003）由敌转我。
  - 咕嚕：深淵之沼（LEVEL015）选"救"后加入。
  - 嚎：艾瓦台地（LEVEL017）、艾瓦台地・尋（LEVEL902）以 AI 控制加入（`actSetPlayerExecMode`）。
  - 克羅蒂：薩魯司海岸（LEVEL036）先是敌，再停手，最后入队。
- 战中归队：9 场在战斗中途从图边或图外插入队员（`actInsertStoryObject,obj_Story_PlayerN`）。最典型的是帕尼西亞城　廢墟（LEVEL010）：两人开局，第 5 回合三名队友从下方进场。逐场见 2.4 第 3 条。
- 开局待命：开局放在图上的敌人大多带等待回合。70 关 569 个开局实例里 535 个写了 `wait_round`（1–30）；亞修頓大橋（LEVEL044）的 61 名敌人分 2–30 回合陆续出动。见 2.4 第 1 条。
- 其他机制（括号里是出现的场）：
  - 不死首领或追兵：16 场在 STORY 或 winfail 里写了 `actSetPlayerUndead`（盜賊洞窟（LEVEL003）、回音之谷（LEVEL021）、絕望之谷（LEVEL030）、漆黑之森（LEVEL031）、拉格納沼地（LEVEL032）、黃昏之丘　陰（LEVEL033）、沙羅尼亞近郊（LEVEL034）、薩魯司海岸（LEVEL036）、古代神殿遺跡（LEVEL037）、悲嘆之湖（LEVEL041）、劫數・地劫神（LEVEL059）、自覺與宿命・塔克斯（LEVEL075）、最終的序曲・妖精王（LEVEL076）、破滅的命運・席德爾（LEVEL077）、接觸・妖精王（LEVEL078）、終焉・咕嚕最終型態（LEVEL079）），通常配 `actCheckPlayerHPLow` 判"打到阈值"；HP 归零时用 252 号道具复活并停 2 回合的有絕望之谷（LEVEL030）、漆黑之森（LEVEL031）、拉格納沼地（LEVEL032）、黃昏之丘　陰（LEVEL033）、薩魯司海岸（LEVEL036）、接觸・妖精王（LEVEL078）。
  - 阵营切换 `actSetPlayerMode`：盜賊洞窟（LEVEL003）、沙羅尼亞近郊（LEVEL034）、薩魯司海岸（LEVEL036）、古代神殿遺跡（LEVEL037）。
  - 地形改变：眾神的宮殿遺址（LEVEL028）、禁忌之魂・墳場地下（LEVEL080）开墙，黃昏之丘　陽（LEVEL039）塌方。
  - 随机：艾瓦台地・尋（LEVEL902）随机藏点，拉格納沼地（LEVEL032）随机毒气。
  - 二选一：深淵之沼（LEVEL015）、悲嘆之湖・兄弟的抉擇（LEVEL073）、曼多力亞　對峙（LEVEL900）。
  - 战中得道具：龍之息（火山）（LEVEL013）、尼布魯瀑布（LEVEL022）、大地的裂縫（LEVEL043）、禁忌之魂・墳場地下（LEVEL080）、艾瓦台地・尋（LEVEL902）。
  - 结局分数：`actAddOverScore` 用于艾瓦台地（LEVEL017）、回音之谷（LEVEL021）、曼多力亞　對峙（LEVEL900）、艾瓦台地・尋（LEVEL902）；`actSetOverFlag` 用于古代神殿遺跡（LEVEL037）、悲嘆之湖・兄弟的抉擇（LEVEL073）。

### 1.8 设计得有意思的 8 场

1. **棄卒（LEVEL051）——死守，等援军，再选打还是走。**
   - 前 6 回合，城门（像素 267,209）每当 021 号敌兵少于 3 名、026 号少于 2 名就补一名，杀不完。
   - 第 6 回合援军到场，补兵停止，同时开放两条胜利路线：全灭，或雷歐納德走到城门。
   - 靠的是按敌数补兵，加上按回合切换目标。地图 24×24，我方 1 名＋友军 4 名，对敌 7 名。
2. **席達鎮（LEVEL006）——限时斩首。**
   - 第 5 回合前打倒兵隊長（024 号）立即胜利；第 5 回合起这条胜利被 `actDeleteWinStatus` 删掉。
   - 之后再打倒隊長，会冒出第二名隊長和 6 名士兵，并开放两条路：再打倒隊長，或雷歐納德逃出城鎮。
   - 题目是"冲得够不够快"。地图 35×28，带 12 名友军。
3. **龍之息（火山）（LEVEL013）——30 回合内登顶。**
   - 雷歐納德到达輝煌之器处即胜，第 30 回合火山爆發即败。
   - 没有事件和增援，敌 9 名；地图 30×40 竖长，可走的格 961 个里 873 个连成一片，輝煌之器在高度 7 的 (13–14,9)；9–21 级的高地是每级差 3 的阶梯断崖（相邻两格高差 ≥3 走不通），走不上去，只隔开路线。
   - 题目是赛跑：一个人穿过敌阵到祭坛，其他人挡龙，靠的是路程和回合上限。
4. **絕望之谷（LEVEL030）——分两路撤退，追兵打不死。**
   - 40×17 的狭长谷地：雷歐納德一组往南、琥一组往东南，每人走进自己那组的出口就离场，全员离场才算胜利。
   - 克羅蒂、傲等首领设为不死，HP 归零就用 252 号道具复活并停 2 回合；克羅蒂 HP 50% 时来一波援军，再过 5 回合（`actCheckRoundDisp,5`：第一次求值时记下“当前回合＋5”，到点成立；本关没有倒计时物件，画面上不显示剩余回合）又来一波。
   - 题目是"打不赢，只能拖住追兵把人送走"。
5. **眾神的宮殿遺址（LEVEL028）——限时搜刮。**
   - 第 4 回合起出现倒计时，到点直接判胜（看板写"時間內盡情搜刮""獲得所有寶箱"），宝箱拿到多少算多少。
   - 30×60 的地图上有 4 个封印物件（5000–5003），打掉一个就开一处墙（ClearWall），露出后面的宝库。
   - 题目是"回合有限，怎么分兵拿最多"。
6. **古代神殿遺跡（LEVEL037）——让对的人补最后一刀。**
   - 先过 5 尊守護者（067 号）的机关：受击的那尊换阵营，同组 5 尊都打过后（`actCheckEventNotExist` 作闸门）全体复位；只有第 5 尊是最后一个被打的才进下一组（第 5 尊的事件要求 1–4 号事件都已撤掉才武装下一组，第 4 尊最后被打走的是复位那条链）；脚本里这样的轮换有 6 组，全关 50 个事件。
   - 之后出现謎之生命體（052 号），HP 归零前不死。归零后，如果最后一击来自咕嚕，咕嚕当场转职（`actPlayerJobUpProcess`）并写结局旗标；换别人补刀，它只是消失。
   - 靠的是两条互斥分支：`actCheckPlayerAttacked`（攻击者＋受击者）和 `actCheckNotPlayerAttacker`。
7. **艾瓦台地・尋（LEVEL902）——找随机藏起来的通行證。**
   - 第 3 回合从 5 个候选点里随机抽 1 个藏起通行證（`actRandomSetSysArrivePos`），5 名队员谁先踩中谁得到它（道具 281），之后雷歐納德走到东边才胜利。
   - 4 种敌人各少于 2 名时各补 2 名。
   - 也是第 3 回合，嚎以 AI 控制加入，自己行动，他死了也算失败。
   - 题目是边搜、边打、边护人。
8. **盜賊洞窟（LEVEL003）——打服而不是打死。**
   - 胜利条件有两个，任一成立漢克斯就转为我方入队（`actSetPlayerMode … pmPlayer`）：把漢克斯打到 HP 30% 以下；或緹娜与漢克斯之间发生两次攻击（谁打谁都算）。
   - 题目是"派指定角色去接触敌将"，靠攻击者／受击者条件链加阵营切换。

另外几场可借鉴的做法：

- 深淵之沼（LEVEL015）：第 27 回合前清场就直接胜利，拖到第 27 回合才会遇到咕嚕，再救／不救二选一。
- 巴瀚納海峽（LEVEL012）：守船 23 回合，敌方有飞行单位。
- 薩魯司海岸（LEVEL036）：克羅蒂第 8 回合以不死敌人登场，第 10 回合停手，第 12 回合入队。
- 拉格納沼地（LEVEL032）：每 3 次行动（`actCheckNextSerialNumber,3`）从 9 个点里随机挑一处喷毒气。
- 黃昏之丘　陽（LEVEL039）：第 3、5、7 回合地震、烟雾扩散，第三次地震后第 20–29 排共 89 格塌成悬崖（10 次 `actInsertStoryObjectXRange,obj_Story_Block`，每排一段），站在上面的敌我单位都被删掉（`actDeletePosPlayerXRange` 两边各 10 次）；塌方前两回合先用烟雾圈出范围。
- 破滅的命運・席德爾（LEVEL077）：首领 HP 归零后原地变身第二形态毀滅天使（059 号）。

---

## 二、我们能自己做什么样的地图和关卡

### 2.1 做一张新战斗地图要什么

要哪些文件、跑什么命令、在哪登记，见 [MODDING_LEVELS §3.1](MODDING_LEVELS.md#31-关卡与剧情)，格式照龍脊隘口（LEVEL200）。下面只记做图时会碰到的限制。

**底图**

- 任意 PNG，写在 `level.json` 的 `map_texture`（res:// 路径）。
- 尺寸必须正好是格数×32 像素。生成器拿它和 `terrain.txt` 的行列数比对，不符就报错（`tools/hsltools/levels/authored.py` 的 `terrain_packet`）。原版最終的序曲・妖精王（LEVEL076）到終焉・咕嚕最終型態（LEVEL079）那种多出 16 像素的图，手写关不收。
- 新 PNG 要先跑一次 `tools/godot.sh --headless --import`，才能被 `load()`。
- 图上画的房子、树、水对规则没有作用，规则只读 `terrain.txt`。

**地形格 `terrain.txt`**

- 一行是一排（y），一个字符是一格（x），各行等长；`;` 开头的行是注释。
- `#`＝高度 255，不能走（悬崖、墙、房子、水都写成它）；`.`＝高度 0，`1`–`9`＝可走的高度；没有别的字符。
- 生成物是 `content/generated/hsl/authored/levelNNN_terrain.json`（`hsl_wrd_terrain.v2`，tile id 全为 0）。

**地形种类与效果（规则读到的只有下表这些）**

玩家感觉到的只有哪里能走、哪里不能走、要绕多远。高度是记移动的办法：画面上没有高低，命中和伤害也不看它。下表是做图时要照着写的规则。

| 格子 | 地面单位 | 飞行单位 | 武器射程、法术范围 |
| --- | --- | --- | --- |
| 高度 0–9 | 进一格耗 1 点移动，上坡另加高差（下坡不加）；相邻两格高差 ≥3 不能走 | 无视高度，每格 1 点 | 不读高度，不挡 |
| `#`（高度 255） | 不能进入 | 能越过，也能停在上面（按 `ActorTraversalRules.gd` 的 `transition_error`／`stop_error` 读，未实测） | 不挡 |

- 没有森林、沼泽之类的地形种类（画上的水、房子要在 `terrain.txt` 里写成 `#` 才挡路），也没有地形防御或回避修正。移动消耗固定为 1（`game/sim/WrdTerrainTiles.gd`：`move_cost: 1`）；高度只进移动规则（`game/sim/ActorTraversalRules.gd`：`arrival_cost`、`height_delta`、高差 ≥3 即 `target_blocked_by_height`），不影响命中和伤害。原版也是这样：原版 WRD 的 tile id 在运行时只取其中的格标记位。
- 原版 WRD 还有两种格标记：0x4000（房屋底下的硬阻挡，连飞行单位也挡，并截断武器射程和法术范围，见 `game/sim/RangePropagationRules.gd`）和 0x100000（能经过、不能停）。`terrain.txt` 写不出这两种，所以手写图上的 `#` 挡不住飞行单位，也挡不住远程攻击。
- 高度只能写 0–9。原版有 8 关的可走格高于 9（见 1.5），这几关的地形不能原样搬。

**尺寸**

- 上限：运行时的地形加载器拒绝任一边超过 256 格（`WrdTerrainTiles.gd`：`invalid_terrain_size`），即最大 256×256 格（8192×8192 像素）。
- 下限：没有显式检查。但射程传播代码的注释写明"每个战场都 ≥20×15，所以不做边界钳制"（`RangePropagationRules.gd` 文件头）。比一屏（20×15 格）小的图超出了已核对过的范围。
- 原作实际用的是 20–60 × 17–60 格。

**单位与 AI**

- `level.json` 的 `units[]`：`id`、`actor`（PLAYERS 或 `content/authored/roles/characters.json` 的代号）、`token`（剧本里的 `SID_…`，同一 token 依次是 serial 1、2…）、`role`（`player_controlled`／`friendly_ai`／`enemy_ai`）、`cell` [x, y]。
- 单位可带 `initial_state` 覆盖字段：`no_attack`、`hp`／`max_hp`，以及 AI 实例参数 `find_type`、`find_range`、`find_flag`、`wait_round`（等几回合再动）、`fixed_point`（守点）、`ai_fixed`、`gold`、`stamina`、`level_adjust_range`／`level_adjust_disp_range`（`content/schema/unit.schema.json` 的 `evef_instance.overrides`）。
- winfail 插入的增援先在 `level.json` 的 `objects` 里声明 `{"obj_…": {"actor": …, "token": …}}`，没声明就生成失败。生成器把这些物件一律建成敌方单位（`script_objects` 的 `object_process` 写死为 `defProcEnemy`）。

### 2.2 新关卡能用的胜负条件和事件

**只写数据就能做到的。** [WINFAIL_TOKENS](WINFAIL_TOKENS.md) 列出的 19 个条件、47 个动作、17 个世界旗标、36 个演出都由运行时解释，手写关和原版关走同一个解释器（`WinfailScenarioRules`）。

| 想做的关 | 写法 | 原作先例 |
| --- | --- | --- |
| 全灭 | `actCheckEnemyTotalNumber,0` | 遭遇战、多数剧情战 |
| 剩 N 名就收兵 | `actCheckEnemyTotalNumber,N`，或 `actCheckEnemyNumber,token,N` | 歐姆村（LEVEL001） |
| 击败首领 | `actCheckEnemy,1,token`／`actCheckPlayer,1,token`，或 `actCheckPlayerHPLow,token,serial,%` | 聖靈之森（LEVEL040）、惡夢的終曲（LEVEL052） |
| 首领打到阈值才算（之前不死） | `actSetPlayerUndead` ＋ `actCheckPlayerHPLow` | 劫數・地劫神（LEVEL059）、自覺與宿命・塔克斯（LEVEL075） |
| 胜利晚开（最后一波到了才能赢） | 胜利段不在开场武装，由事件 `actInsertWinStatus` | 31 场剧情战 |
| 从某一刻起再过 N 回合 | `actCheckRoundDisp,N`：第一次求值时记下“当前回合＋N”，到点成立。画面倒数另需倒计时物件，见 2.4 第 6 条 | 絕望之谷（LEVEL030） |
| 单人到达 | `actCheckPlayerArrivePos,token,serial,x1,y1,x2,y2`（像素矩形）；任一我方到达用 `actCheckAnyPlayerArrivePos` | 龍之息（火山）（LEVEL013）、逃出克萊恩城（LEVEL053） |
| 全员撤离 | 每人一条到达事件 → `actDeleteObject`；`actCheckPlayerTotalNumber,0` → `actInsertWinStatus` | 絕望之谷（LEVEL030）、幽闇墳場（LEVEL038） |
| 坚持 N 回合 | 事件 `actCheckRoundNumber,N` → `actInsertWinStatus` | 巴瀚納海峽（LEVEL012）、接觸・妖精王（LEVEL078） |
| 回合上限 | fail 段写 `actCheckRoundNumber,N` | 龍之息（火山）（LEVEL013） |
| 限时窗口 | 事件按回合 `actDeleteWinStatus` | 席達鎮（LEVEL006） |
| 保护友军 | 友军用 `friendly_ai`；fail 段写 `actCheckPlayer,1,友军 token` | 艾瓦台地（LEVEL017）、沙羅尼亞近郊（LEVEL034） |
| 增援 | `actInsertObject,obj,x,y` ＋ `actWalkPrevInsertObject` ＋ `actSetPrevInsertObjectWaitRound` | 34 场剧情战 |
| 敌人待命、靠近才动、守点 | 单位 `initial_state` 的 `wait_round`／`find_range`／`ai_fixed`／`fixed_point`；战中用 `actSetWaitRound`、`actSetPlayerFixPos`（2.4 第 1 条） | 亞修頓大橋（LEVEL044）、惡夢的終曲（LEVEL052）、克萊恩城（LEVEL045） |
| 敌人走到某处即败 | fail 段写 `actCheckPlayerArrivePos,SID_ENEMYnnn,0,x1,y1,x2,y2`：serial 0 表示这一类全部，增援也算。几类敌人就写几段（推断，未实跑） | 原作没有 |
| 打不完的兵 | `actCheckEnemyNumber` 起头，链尾 `actInsertEventStatus` 重新武装自己 | 棄卒（LEVEL051）、艾瓦台地・尋（LEVEL902） |
| 敌人转为我方、AI 控制的同伴 | `actSetPlayerMode,token,serial,pmPlayer,1`；`actSetPlayerExecMode` | 盜賊洞窟（LEVEL003）、薩魯司海岸（LEVEL036）、艾瓦台地（LEVEL017） |
| 回合上限让玩家开场就看到 | 把回合数写进该段看板讯息，开场 `actShowWinFailStatus` 弹出（2.4 第 6 条） | 龍之息（火山）（LEVEL013）只写了“超過時間，火山爆發” |
| 交手触发对白 | `actCheckPlayerAttacked`／`actCheckSerialPlayerAttacked` → `actMessage` | 悲嘆之湖（LEVEL041）、最終的序曲・妖精王（LEVEL076） |
| 二选一 | `actSelectInsertEvent`（开场或事件里都可以） | 深淵之沼（LEVEL015）、悲嘆之湖・兄弟的抉擇（LEVEL073）、曼多力亞　對峙（LEVEL900） |
| 随机地点 | `actRandomSetSysArrivePos` ＋ `actCheckPlayerArriveSysPos` | 艾瓦台地・尋（LEVEL902） |
| 拿道具、结局分数、改大地图、下一关 | `actGetItem`、`actAddOverScore`、`actBM…`、`actSetNextPlayLevelEvent` | 多数剧情战 |
| 看板上的目标文字 | status 的 `message = -1,讯息号`；只为显示一行，可写一条永不触发的事件 | 艾瓦台地（LEVEL017）、艾瓦台地・尋（LEVEL902） |

龍脊隘口（LEVEL200）实际只用到全灭、主角死亡、第 3 回合增援三样，有端到端测试（`tests/run_authored_level_tests.gd`）。表里其余写法没有在手写关里跑过；生成器用同一个语法解析器读剧本，所以判断可用（推断）。

**要改代码或生成器的。**

| 想做的 | 卡在哪 | 改哪里 |
| --- | --- | --- |
| 战中开门、塌方、毒气、落雷 | 这些靠带 obj_Data9 种类的剧情物件（mapobjClearWall、mapobjBlock、defProcPoisonGas、defProcDropLightn）；手写关的 `objects` 只能声明 actor＋token 的单位（推断） | `tools/hsltools/levels/authored.py` 的 `script_objects` |
| 宝箱和其他地图物件 | 宝箱：手写关 `level.json` 列 `treasures`（格、道具代号、是否暗箱）即产出箱子，走原版的开箱链（`docs/MODDING_LEVELS.md`）；其他地图物件生成器仍不产 | 同上 |
| 挡飞行和射程的墙、能过不能停的格 | `terrain.txt` 只能写可走的高度和 `#` | `authored.py` 的 `terrain_packet`（把新字符映射到 0x4000／0x100000） |
| 高度 >9 | 一格一个字符 | 同上 |
| 战中归队并沿用队伍成长（原作的队伍槽插入） | `objects` 一律建成 `defProcEnemy`，生成器不产 `obj_Story_PlayerN`；变通办法是插入后接 `actSetPlayerMode`，按模板出生（数据可做，未实跑，2.4 第 3 条） | `authored.py` 的 `build_seed` |
| 画面上的「剩餘回合」倒数 | 要有 `mapobjRoundNumberCounter` 物件，手写关写不出 `obj_Data9`／`obj_HitPoint`；表现层也没画数字（推断） | `authored.py` 的 `build_seed` ＋ `game/battle/` 表现层 |
| 出场选择 | 原作和重制都没有这个界面 | 新界面＋按选择生成开场名单 |
| 新条件／动作、新开场演出、新招式效果族、新特效 opcode | 不在词表里 | [MODDING_LEVELS §8](MODDING_LEVELS.md#8-必须改代码的情况) |

### 2.3 现有的手写示范关

- `content/authored/` 下只有一关：龍脊隘口（LEVEL200）。
  - 底图不是自制的：`map_texture` 指向原版戈爾山道（LEVEL002）的 `content/imported/hsl/chapter01/battle002/level2.png`（768×640）。`level.json` 的说明写着"新地圖只需換這一條路徑"。
  - 地形是手写的 `terrain.txt`，24×20，文件注释写明"以第 2 關的地形為底稿改寫"。
  - 走行帧、音效、头像清单借 battle500（遭遇战共用的演员池），敌人是原版 036 号（翼狼）3 名，第 3 回合再增援 1 名。
  - 上场角色：雷歐納德、緹娜、新角色 102 蕾雅（受控）、103 托蘭（友军）。102／103 的美术是原版 003／004 换色，由 bootstrap 在本地生成。
  - 配乐自制：`content/authored/music/100.ogg`，剧本写 `actPlayMusic,100`（100 号起读这个目录）。
  - 胜负：全灭胜，雷歐納德死亡败；胜利后 `actSetNextPlayLevelEvent,200,998` 进谢幕。
- 其他手写战斗（`content/battles/*_trial.json`、`first_battle.json`、`tests/support/authored_minimal_battle.json`）都直接用原版棄卒（LEVEL051）或戈爾山道（LEVEL002）的图和地形。
- 所以，仓库里还没有一张自制的战斗底图。"自制 PNG＋`terrain.txt`"这条路生成器已经支持，也会校验尺寸，但还没有用非原版的图跑过。

### 2.4 六项关卡能力核对

每条先给结论（只写数据，还是要改代码），再给写法和出处。

**1. 敌人分组待命：靠近才动、第 N 回合才动。只写数据。**

- 第 N 回合才动用 `wait_round`，有三种写法：
  - 开局单位：写在 `level.json` 的 `units[].initial_state.evef_instance.overrides.wait_round`。
  - 增援：插入后接 `actSetPrevInsertObjectWaitRound,N`。
  - 战中改某个单位：`actSetWaitRound,token,serial,N`。
  - 出处：`docs/WINFAIL_TOKENS.md`、`docs/evidence_packets/static_reverse/original_script_wait.md`。
- 等待不是死等：
  - 每次轮到它行动就减一。等待期间只在 8 格内找目标。
  - 8 格内出现敌人、自己 HP 不满、或身上带任何状态，就立刻结束等待（`game/sim/AINavigationRules.gd:116` 的 `acquire`；`docs/evidence_packets/static_reverse/original_ai_navigation.md` 第 7 行）。
  - 所以"第 N 回合才动"实际是"N 回合内不主动出击，被惹到就动"。
- 靠近才动用 `find_range`：找目标的半径，单位是格，按圆距离算。
  - 圈里没有目标，这一手就原地结束（`game/sim/loop/BattleLoopAI.gd:386` 的 `_ai_no_target_action`）。
  - 原版缺省值大多是 80，等于全图都在圈里，所以要写小值。`content/generated/hsl/ai/profiles.json` 里 38 个角色是 80，另有 11 个是 12–20。
- 守点：
  - `ai_fixed` 是以出生格为圆心的半径。只打进了圈的目标；圈里没人就走回原位（`BattleLoopAI.gd:358` 的 `_ai_fixed_guard`）。
  - `fixed_point` [x, y]：先走到指定格，到了就不再受限（`AINavigationRules.gd:54` 的 `initialize`）。
  - 战中改锚点用 `actSetPlayerFixPos,token,serial,x,y,半径`。锚点可以放在图外，当撤退点用，巴瀚納海峽（LEVEL012）就这么做。
- 战中放闸：开局给一个大的 `wait_round`，到某个事件里写 `actSetWaitRound,token,serial,0`，让它立刻动。这是推断：`ScriptWaitRules.valid_count` 接受 0–10000。
- 原作用得多的是等待回合，另外三项很少（`content/generated/hsl/development/evef_instances.json`）：
  - `wait_round`：70 关 569 个开局实例里 535 个写了，取值 1–30。例如亞修頓大橋（LEVEL044）的 61 名敌人分 2–30 回合陆续出动，哈莫特沙漠（LEVEL024）的 28 名分 2–18 回合。
  - `find_range`：只有惡夢的終曲（LEVEL052）和逃出克萊恩城（LEVEL053）用。前一场的帝國皇帝是等 8 回合、半径 10，两名帝國法師是等 2 回合、半径 12；后一场有一名 023 号是等 8 回合、半径 8。
  - `ai_fixed`：只有克萊恩城（LEVEL045）用，四名 044／045 号守卫半径 6，另配 15／18 回合的等待。
  - `fixed_point`：歐姆村（LEVEL001）、沙羅尼亞近郊（LEVEL034）用它给村民设去处，艾瓦台地（LEVEL017）用在克里夫身上。
- 注意两点：
  - `content/schema/unit.schema.json` 的 `evef_instance` 必须带 `record_index`。
  - 手写关里还没有人用 `initial_state` 写过 AI 参数；`docs/MODDING_LEVELS.md` §3.1 第 4 步写明可以这样写。

**2. 事件触发。只写数据。**

- 能用来触发的条件：
  - 第 N 回合：`actCheckRoundNumber,N`。
  - 单位进入区域：`actCheckPlayerArrivePos,token,serial,x1,y1,x2,y2`，区域是像素矩形。这个条件不分敌我；`SID_ENEMYnnn` 配 serial 0 表示这一类的全部单位，增援也算（`game/sim/WinfailConditions.gd` 的 `units_for_token`）。
  - 任一我方单位（含友军）进入区域：`actCheckAnyPlayerArrivePos`。
  - 单位死亡或离场：`actCheckPlayer`／`actCheckEnemy,num,token…`。
  - 某类敌人的剩余数：`actCheckEnemyNumber`。
  - 敌方或我方总数：`actCheckEnemyTotalNumber`／`actCheckPlayerTotalNumber`。
  - HP 低于比例：`actCheckPlayerHPLow,token,serial,百分比`。
  - 某人攻击了某人：`actCheckPlayerAttacked`。
  - 每隔 N 次行动：`actCheckNextSerialNumber`。
  - 一段里写几条条件，就是要它们全部成立（`docs/WINFAIL_TOKENS.md` 第 5、15 行）。
- 触发后能做什么：win、fail、event 三种段结构相同，条件成立后按顺序执行动作链。所以下面这些，任何一种条件都能触发：
  - 对白：`actMessage`。
  - 增援：`actInsertObject`＋`actWalkPrevInsertObject`。
  - 改胜负：`actInsertWinStatus`／`actDeleteWinStatus`／`actInsertFailStatus`／`actDeleteFailStatus`。
  - 开关其他事件：`actInsertEventStatus`／`actDeleteEventStatus`。
  - 弹出看板：`actShowWinFailStatus`。
  - 换阵营：`actSetPlayerMode`。
  - 改 AI：`actSetWaitRound`、`actSetPlayerFixPos`。
  - 让单位离场：`actDeleteObject`。
  - 给道具：`actGetItem`。
  - 在地图上标出目标格：`actInsertShowPosObject`。
- 什么时候检查：每完成一个行动检查一次，一次检查最多启动一个事件；链里写 `actExecWinFailProcess` 可以再查一轮。所以"第 N 回合"的事件要等第 N 回合的第一个行动完成后才触发，不是回合一开始就触发（`docs/evidence_packets/static_reverse/original_round_display.md`「结论」）。
- 一段触发一次就从武装列表里移除；要重复触发，就在链尾重新武装自己。
- 同时武装的上限：胜利 10 段、失败 10 段、事件 20 段，超出的插入不生效（`game/sim/WinfailCompiler.gd:592` 的 `STATUS_SLOT_COUNTS`）。
- 原作先例：按回合触发的有 31 场；HP 阈值有盜賊洞窟（LEVEL003）的 30% 和絕望之谷（LEVEL030）的 50%；进入区域有龍之息（火山）（LEVEL013）；交手有古代神殿遺跡（LEVEL037）（见 1.7、1.8）。
- 原作没有"敌人走到某处即败"。照上面的读法，fail 段写 `actCheckPlayerArrivePos,SID_ENEMYnnn,0,…` 就能做到，有几类敌人就写几段。这是推断，没有实跑。

**3. 战中我方增援：归队角色从地图边进场，并且可以操作。原作有，引擎也支持；手写关要改生成器，只写数据有变通办法。**

- 原作的写法：`actInsertStoryObject,obj_Story_PlayerN,x,y`。N 是 1–9，对应九个队伍槽，物件过程是 `defProcPlayerInstall`。坐标放在图边或图外，再用 `actWalk…` 走进场。先例 9 场：
  - 帕尼西亞城　廢墟（LEVEL010）：两人开局。第 5 回合琥、漢克斯、雪拉从下方 (672–800, 768) 进场，同时开放胜利条件。
  - 戈爾山道（LEVEL002）：敌人剩 1 名时，緹娜从左边 (0, 672) 进场，追兵沿同一条路跟进。
  - 寧靜之森（LEVEL007）：第 6 回合雪拉从右边 (1024, 288) 进场。
  - 艾瓦台地（LEVEL017）、艾瓦台地・尋（LEVEL902）：嚎从图外上方 (256, −64) 走进来，再用 `actSetPlayerExecMode,SID_嚎,1,1` 交给 AI 操作。
  - 薩魯司海岸（LEVEL036）：第 8 回合克羅蒂从图外上方进场，先设为敌方。
  - 利魯瑪山地（LEVEL019）、利魯瑪山地・再訪（LEVEL904）：雷特单人开局。041 剩不到 3 名时，其余六人从左下 (64/128, 1248) 进场。
  - 深淵之沼（LEVEL015）：第 27 回合咕嚕出现。
  - 古代神殿遺跡（LEVEL037）：咕嚕打中謎之生命體后，在随机点出现。
- 重制的引擎：`game/sim/ScriptActorCreationRules.gd` 的 `registered_player` 分支照原版插入队伍槽，沿用队伍的成长记录（跨关承接的 carry 和 reserve）。
- 手写关的现状：生成器不产队伍槽物件。`level.json` 的 `objects` 一律建成 `defProcEnemy`；winfail 里插入没声明过的 `obj_`，生成直接报错（`tools/hsltools/levels/authored.py:239` 的 `build_seed`）。要像原作那样归队并沿用成长，得改生成器，让 `objects` 能声明成队伍槽、对上角色代号。
- 只写数据的变通办法（推断，没有实跑）：
  - 写法：在 `objects` 里声明归队角色，`actor` 写他的代号，`token` 写他的 `SID_…`。用 `actInsertObject` 插在图边，`actWalkPrevInsertObject` 走进场，同一条链接 `actSetPlayerMode,token,1,pmPlayer,1`。
  - 这条动作把单位改成 `player_controlled` 并可以操作（`game/sim/WinfailActions.gd:668` 的 `apply_player_mode`）。原作盜賊洞窟（LEVEL003）的漢克斯、薩魯司海岸（LEVEL036）的克羅蒂，转为我方用的都是它。
  - 代价：角色按 PLAYERS 模板出生，不带之前的成长。可以用 `actSetPrevInsertObjectAdjustLevel`、`actSetPrevInsertObjectEquip` 调等级、配装备。
  - 战后它按角色代号进入跨关承接（`game/sim/CampaignCarryRules.gd` 的 `DEFAULT_POLICY` 只收 `player_controlled`）。
  - 想让归队角色先由 AI 操作，再接 `actSetPlayerExecMode,token,1,1`，和嚎一样。

**4. 出场选择、出场人数上限。原作和重制都没有选择画面；要做选择得改代码。**

- 原作没有出场选择：
  - 每关由 STORY 或 WINFAIL 逐个插入队伍槽 `obj_Story_Player1–9`，只有已经入队的成员才出场；遭遇战把九个槽都写成"有才產生"。
  - 没上场的成员照样跟着队伍走，每关开始时回满。
  - 出处：`tools/hsltools/levels/battle.py` 的 `PARTY_SLOTS` 和遭遇战注释；`docs/evidence_packets/static_reverse/original_campaign_actors.md`「跨关承接」。
  - 人数上限就是九个槽。剧情战开局最多 9 名受控单位，有 19 场是 9 名。
- 重制同样没有出场选择界面，`game/` 下只有大地图上的整备界面 `PartyEquipmentScreen`。
  - 手写关的出场名单，就是 `level.json` 的 `units[]` 里写成 `player_controlled` 的那些单位。
  - 生成器和运行时都没找到人数上限的常量（推断：没有上限检查）。
- 要做出场选择得改代码：开战前加一个选人界面，再按选择结果生成开场名单。

**5. 地形：玩家感觉到的只有能走和不能走。高度只是记移动的办法，不影响命中和伤害；`#` 挡不住飞行单位和远程攻击。**

原作战斗地图玩起来是平面：高度决定哪里能走、走过去费几步，画面上没有高低，也没有高地加成。下面是做图时要知道的规则和出处。

- 移动：
  - 进一格耗 1 点；上坡另加高差（1 或 2），下坡不加；相邻两格高差 ≥3 不能走。
  - 地面单位进不了 `#`（高度 255）；飞行单位（模式 6）不看高度。
  - 出处：`game/sim/ActorTraversalRules.gd` 的 `transition_error`、`height_delta`；`docs/evidence_packets/static_reverse/original_actor_traversal.md` 第 7、26 行；`original_movement.md`「模式 mask 与高差」表。
- 命中和伤害不看高度：
  - 物理、法术、特技的公式模块都不引用地形或高度，即 `game/sim/CoreCombatRules.gd`、`SkillResolutionRules.gd`、`SpecialDamageRules.gd`、`MultiHitSpecialRules.gd`、`CombatSequenceRules.gd`。
  - 原版物理战斗的指令执行回执（`docs/evidence_packets/static_reverse/original_physical_combat.json`）里也没有地形输入。
- 射程和法术范围不看高度，只有 0x4000 格标记能截断。出处是 `game/sim/RangePropagationRules.gd` 文件头：第 20 行写"Heights are not read"，第 65–66 行写高度 255 也不算在内。
- `#` 挡不住飞行和远程，依据是下面这串代码：
  - 手写地形里，`#` 只写成 `{t: 0, b: 1, h: 255}`，不带格标记（`tools/hsltools/levels/authored.py:186–187`）。
  - 加载时格标记取 `t & 0x974000`，所以是 0（`game/sim/WrdTerrainTiles.gd:63`）。
  - 飞行的阻挡掩码只有 0x4000（`ActorTraversalRules.gd:15` 的 `MASKS`）。
  - 越格判断对飞行单位跳过高度（第 168–177 行）；能不能停在某格，`stop_error`（第 188–197 行）只看 0x100000 和 0x4000。
  - 射程传播只看 0x4000 和格上的单位（见上一条）。
- 要挡飞行和射程，就得能写出 0x4000 格，这要改 `terrain_packet`（见 2.2 的要改代码表）。

**6. 回合上限能不能开场就让玩家看到：写进看板文字就行；画面上的倒数要改代码。**

- 原版：
  - 回合数本身不显示。只有倒计时物件 `mapobjRoundNumberCounter` 会在画面上显示「剩餘回合」（`docs/evidence_packets/static_reverse/original_round_display.md` 文件头，以及证据表里的 `0x43d610` 一行）。
  - 第一章只有眾神的宮殿遺址（LEVEL028）用了它：第 4 回合插入 `obj_Story_Level_Counter`（obj_HitPoint 12），倒数 12 回合。第 14 回合由 `actDetectRoundDispDisp,-2` 触发一个事件，第 16 回合 `actCheckRoundDisp,0` 到点。
  - 龍之息（火山）（LEVEL013）的 30 回合上限，只在看板上写了"超過時間，火山爆發"，没有写数字。
  - 絕望之谷（LEVEL030）的 `actCheckRoundDisp,5` 只用来计时，这一关没有倒计时物件。
- 重制：
  - 倒计时只做了规则层：插入倒计时物件时设基线（`game/sim/WinfailActions.gd:350` 起的 `_act_insert_story_object`），物件由 `WinfailCompiler.gd:442` 的 `_round_counter_objects` 登记。
  - `game/battle/` 下没找到画「剩餘回合」的代码（推断：现在不显示）。
  - "第 N 回合 · 目标"这行状态只在调试 HUD 下出现（`game/battle/scene/BattlePresentation.gd:273`、`:366`）。
- 只写数据就能做到：
  - 把回合数写进该段看板讯息里，例如"第 30 回合結束前未到達即失敗"。段的 `message = -1,讯息号` 指向 `messages.json` 里的一条。
  - 开场 STORY 里写 `actShowWinFailStatus` 会弹出看板，龍脊隘口（LEVEL200）的 `story.txt` 第 20 行就用了。
  - 战斗中，系统卷轴的「任務說明」随时能打开同一块看板（`game/battle/scene/BattleWinFailBoard.gd` 文件头）。
  - 开场对白里也可以直接说。
- 要改代码的是画面上的回合倒数：手写关的 `objects` 写不出 `obj_Data9`／`obj_HitPoint`（`authored.py` 的 `build_seed` 只写 `obj_Data6`／`obj_Data7`），表现层也要补上画数字。

---

## 三、没查清的

- 增援人数没有区分敌我：事件里插入的单位按 `actInsertObject` 一类动作计数，个别是友方（如巴瀚納海峽（LEVEL012）第 23 回合那批）。
- 古代神殿遺跡（LEVEL037）守護者机关：每组要第 5 尊最后被打才进下一组这一条已追清；打完几组、由哪个事件放出謎之生命體还没追清。
- 曼多力亞　對峙（LEVEL900）开场二选一里，"全员走出画面"那一支之后怎么收场，没有追。
- 原版各关 0x4000／0x100000 格标记的分布没有统计。
- 手写关里还没跑过的三条写法：用 `initial_state` 写 AI 参数；插入后用 `actSetPlayerMode` 转为我方；用 `actCheckPlayerArrivePos` 判敌人到达。转为我方的插入单位在成长面板、道具和结算里是否和队员完全一样，也没核对。
- 重制是否在别处画了「剩餘回合」：按关键字在 `game/` 下没找到，没有实跑眾神的宮殿遺址（LEVEL028）确认。
- 手写关能否用 `actInsertStoryObject` 插入非单位的演出物件（光、烟），只读了生成器的声明检查，没有实跑。
- 续集战役能否像原作那样在大地图点位上随机触发遭遇战，没有核对。

---

## 附录：49 场剧情战逐场表

开局我／友／敌是 battle JSON `playable_units` 里 `player_controlled`／`friendly_ai`／`enemy_ai` 的人数（受控 9＝全队名单）；增援是 event 段里 `actInsertObject` 一类动作的次数；事件是 event 段数；失败一栏只列雷歐納德死亡之外的条件。

| 场景（文件号） | 地图 | 开局 我／友／敌 | 胜利 | 雷歐納德之外的失败 | 增援 | 事件 |
| --- | --- | --- | --- | --- | ---: | ---: |
| 歐姆村（LEVEL001） | 40×35 | 2／8／8 | 全灭；或獸族 028 号剩不到 3 名（撤退） | 村民（061／062 号）全滅 | 0 | 0 |
| 戈爾山道（LEVEL002） | 24×20 | 2／0／5 | 敌剩 1 名以下；第一次剩 1 名时緹娜登场并来 4 名士兵，再打到剩 1 名 | 琥；緹娜被捕（第二波时武装） | 4 | 1 |
| 盜賊洞窟（LEVEL003） | 36×21 | 3／0／14 | 漢克斯 HP ≤30%，或緹娜与漢克斯之间发生两次攻击 → 漢克斯入队 | 緹娜 | 0 | 5 |
| 呼嘯平原（LEVEL005） | 30×22 | 4／0／9 | 全灭 | — | 8 | 1 |
| 席達鎮（LEVEL006） | 35×28 | 4／12／11 | 第 5 回合前打倒兵隊長；之后打倒隊長会再出隊長＋6 兵，可再打倒或雷歐納德逃出城鎮 | — | 7 | 3 |
| 寧靜之森（LEVEL007） | 30×26 | 4／0／21 | 第 6 回合起全灭（列出 5 种敌） | 雪拉 | 8 | 3 |
| 帕尼西亞城　廢墟（LEVEL010） | 30×22 | 2／0／4 | 第 5 回合起全灭 | 緹娜 | 14 | 8 |
| 巴瀚納海峽（LEVEL012） | 45×60 | 9／62／32 | 第 23 回合由事件武装胜利（看板写消滅所有敵人） | 船（62 个 101 号单位）少一个 | 25 | 7 |
| 龍之息（火山）（LEVEL013） | 30×40 | 9／0／9 | 雷歐納德到達輝煌之器處 | 第 30 回合火山爆發 | 0 | 0 |
| 深淵之沼（LEVEL015） | 30×22 | 8／0／11 | 第 27 回合前清场即胜；拖到第 27 回合咕嚕出现，救则再清场，不救则全员离开即胜 | 咕嚕（选救后） | 10 | 6 |
| 艾瓦台地（LEVEL017） | 40×30 | 5／4／15 | 第 8 回合嚎加入后全灭（看板：拯救商人克里夫） | 克里夫（064 号）；嚎（第 8 回合 AI 控制加入后） | 8 | 3 |
| 那可那魯邊境（LEVEL018） | 40×30 | 6／1／15 | 雷歐納德離開戰場（上边），或全灭 | — | 0 | 1 |
| 利魯瑪山地（LEVEL019） | 50×37 | 1／0／4 | 041 号敌兵少于 3 名时来援军，之后全灭 | 雷特 | 32 | 3 |
| 回音之谷（LEVEL021） | 40×22 | 8／0／13 | 雷歐納德離開戰場（左边），或克羅蒂 HP ≤40% | — | 19 | 6 |
| 尼布魯瀑布（LEVEL022） | 40×40 | 9／0／8 | 打倒龍（051 号）（两波各"清场或 8 回合"后龍才现身） | — | 10 | 6 |
| 哈莫特沙漠（LEVEL024） | 20×30 | 8／0／31 | 最后一波到场后全灭（列出 6 种敌） | — | 21 | 6 |
| 日沒灣（LEVEL026） | 50×31 | 9／26／12 | 全灭 | 船（26 个 101 号单位）少一个 | 7 | 1 |
| 眾神的宮殿遺址（LEVEL028） | 30×60 | 9／0／9 | 第 4 回合起倒计时，到点判胜；打掉 4 个封印物件开墙 | 雪拉（倒计时开始时撤掉） | 0 | 7 |
| 約瑟河（LEVEL029） | 30×22 | 8／0／18 | 全灭 | — | 0 | 2 |
| 絕望之谷（LEVEL030） | 40×17 | 8／0／7 | 全员撤离：雷歐納德組往南、琥組往东南 | 雷特、琥 | 15 | 18 |
| 漆黑之森（LEVEL031） | 22×50 | 4／0／6 | 全员往上撤离 | — | 5 | 7 |
| 拉格納沼地（LEVEL032） | 22×37 | 4／0／19 | 全灭，或全员往下撤离 | — | 12 | 10 |
| 黃昏之丘　陰（LEVEL033） | 30×30 | 4／0／11 | 全员往下撤离 | 緹娜（本关无雷歐納德） | 7 | 7 |
| 沙羅尼亞近郊（LEVEL034） | 40×30 | 4／3／16 | 第一次清场后来第二批，消灭其中的 044 号、023 号两种 | 緹娜；村民（062 号） | 9 | 2 |
| 薩魯司海岸（LEVEL036） | 37×60 | 8／0／9 | 第 12 回合后把傲打到 HP ≤20% | 克羅蒂（第 12 回合入队后） | 7 | 6 |
| 古代神殿遺跡（LEVEL037） | 30×37 | 9／5／16 | 守護者机关后打倒謎之生命體（052 号）；咕嚕补刀则咕嚕转职 | 克羅蒂 | 4 | 50 |
| 幽闇墳場（LEVEL038） | 30×22 | 9／0／35 | 全员到達禁忌之墓 | — | 0 | 10 |
| 黃昏之丘　陽（LEVEL039） | 30×37 | 9／0／12 | 清场或撑满 12 回合后来最后一波，再全灭 | — | 4 | 6 |
| 聖靈之森（LEVEL040） | 40×22 | 9／0／9 | 打倒傲（055 号） | — | 6 | 2 |
| 悲嘆之湖（LEVEL041） | 40×30 | 9／0／16 | 打倒席德爾（056 号）（HP 归零） | — | 16 | 3 |
| 大地的裂縫（LEVEL043） | 40×22 | 9／0／18 | 全灭 | — | 0 | 1 |
| 亞修頓大橋（LEVEL044） | 60×37 | 9／0／75 | 清场或撑满 8 回合后来大波增援；之后全灭或全员到达右上方 | 緹娜 | 16 | 14 |
| 克萊恩城（LEVEL045） | 60×37 | 9／0／35 | 全灭，或全员到达出口 | — | 13 | 13 |
| 棄卒（LEVEL051） | 24×24 | 1／4／7 | 第 6 回合援军到后：全灭或雷歐納德到達城門 | — | 3 | 4 |
| 惡夢的終曲（LEVEL052） | 20×40 | 1／4／13 | 打倒法蘭克（025 号） | — | 4 | 2 |
| 逃出克萊恩城（LEVEL053） | 32×43 | 1／0／3 | 緹娜逃出克萊恩城 | 只有"緹娜被捕" | 3 | 3 |
| 劫數・地劫神（LEVEL059） | 51×40 | 9／0／1 | 地劫神（060 号） HP 归零（之前不死）；接结局影片 | — | 0 | 2 |
| 悲嘆之湖・兄弟的抉擇（LEVEL073） | 40×30 | 9／0／1 | 无战斗：雷特二选一，写结局旗标 | — | 0 | 3 |
| 自覺與宿命・塔克斯（LEVEL075） | 30×22 | 9／0／20 | 塔克斯（054 号） HP 归零 | 克羅蒂 | 0 | 6 |
| 最終的序曲・妖精王（LEVEL076） | 30×22 | 9／0／13 | 妖精王（058 号） HP 归零 | — | 4 | 13 |
| 破滅的命運・席德爾（LEVEL077） | 30×22 | 9／0／18 | 席德爾 HP 归零后原地变身毀滅天使（059 号），再打到归零 | — | 2 | 1 |
| 接觸・妖精王（LEVEL078） | 30×22 | 8／0／16 | 撑到第 10 回合（妖精王归零即用 252 号道具复活） | — | 0 | 3 |
| 終焉・咕嚕最終型態（LEVEL079） | 30×22 | 8／0／1 | 咕嚕最終型態（057 号） HP 归零 | — | 0 | 0 |
| 禁忌之魂・墳場地下（LEVEL080） | 40×30 | 9／0／24 | 两处祭坛都有人踩到（血祭、忌魂）；打倒 068 号开墙 | — | 0 | 4 |
| 曼多力亞　對峙（LEVEL900） | 50×37 | 5／6／23 | 开场二选一；开战后全灭 | 緹娜；市民（062 号） 死 3 人以上 | 0 | 2 |
| 菲納斯河畔　伏擊（LEVEL901） | 47×25 | 5／0／17 | 伏兵出现后全灭 | — | 12 | 6 |
| 艾瓦台地・尋（LEVEL902） | 40×30 | 5／0／14 | 踩中随机藏点得通行證，再由雷歐納德到达东边 | 嚎（第 3 回合 AI 控制加入后） | 8 | 12 |
| 哈莫特沙漠・魔騎士團（LEVEL903） | 20×30 | 8／0／31 | 同哈莫特沙漠（LEVEL024） | — | 21 | 6 |
| 利魯瑪山地・再訪（LEVEL904） | 50×37 | 1／0／4 | 同利魯瑪山地（LEVEL019） | 雷特 | 32 | 3 |
