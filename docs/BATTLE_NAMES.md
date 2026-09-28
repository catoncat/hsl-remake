# 战斗命名口径与对照表

命名规定：提到任何一场战斗，一律写**「玩家第 N 场 · 场景名（LEVEL0xx）」＋在做什么**，不说裸文件号。文件号 LEVEL0xx 是原版数据文件编号，不是玩家玩的顺序。

## 开局顺序（玩家口径）

| 玩家第几场 | 场景名 | 文件号 | 说明 |
|---|---|---|---|
| 第 1 场 | 棄卒 · 死守與撤離 | LEVEL051 | 雷歐納德＋两名骑士 024、两名士兵 023；战役 start_level |
| 第 2 场 | 惡夢的終曲 | LEVEL052 | 妖精王与 069 铠甲战士；骑士各带两瓶回復藥 |
| 第 3 场 | 逃出克萊恩城 | LEVEL053 | 緹娜加入 |
| 第 4 场 | 歐姆村 · 獸族的襲擊 | LEVEL001 | 回村后 STORY001 開場接战斗：雷歐納德、琥（003）对獸族 028×6、036×2，村民 061／062 为友军 |
| 第 5 场 | 戈爾山道 | LEVEL002 | 首个野外战 |
| 第 6 场 | 盜賊洞窟 · 影牙隊長 | LEVEL003 | 漢克斯第一回合为敌方 |

歐姆村（LEVEL001）是一场战斗，不是无敌人的回村过场：WINFAIL053 胜利段 `actSetNextPlayLevelEvent,1,1` 直接进 LEVEL001；WINFAIL001 胜利条件为 `actCheckEnemyTotalNumber,0`（全灭）或 `actCheckEnemyNumber,SID_ENEMY028,3`（028 剩 3 名时獸族撤退），失败条件为雷歐納德阵亡或村民 061／062 全灭，胜利后 `actSetTownExecEvent,town_歐姆村,9`、无下一关号，回大地图点 1 再去戈爾山道（资源：`content/imported/hsl/chapter01/battle053/source_texts/winfail053.txt`、`content/imported/hsl/chapter01/battle001/source_texts/winfail001.txt`；重制数据 `content/battles/campaign.json` battles["1"] → `content/battles/ohm_village_battle.json`）。

此后按剧情流程走，分支关卡（5xx 遭遇战、73／75／76／78 等）以剧本 next 为准；写汇报时若拿不准是第几场，写「场景名（LEVEL0xx）」并说明它在哪一场之后。

## 全部场景名（取自 content/battles/*.json 的 title）

| 文件号 | 场景名 | 类型 |
|---|---|---|
| LEVEL001 | 歐姆村（開場預覽） | story |
| LEVEL002 | 戈爾山道（開場預覽） | story |
| LEVEL003 | 盜賊洞窟（開場預覽） | story |
| LEVEL005 | 呼嘯平原（開場預覽） | story |
| LEVEL006 | 席達鎮（開場預覽） | story |
| LEVEL007 | 寧靜之森（開場預覽） | story |
| LEVEL008 | 菲納斯河畔 | story |
| LEVEL009 | 廢都　曼多利亞 | story |
| LEVEL010 | 帕尼西亞城　廢墟（開場預覽） | story |
| LEVEL012 | 巴瀚納海峽（開場預覽） | story |
| LEVEL013 | 龍之息（火山）（開場預覽） | story |
| LEVEL015 | 深淵之沼（開場預覽） | story |
| LEVEL017 | 艾瓦台地（開場預覽） | story |
| LEVEL018 | 那可那魯邊境（開場預覽） | story |
| LEVEL019 | 利魯瑪山地（開場預覽） | story |
| LEVEL021 | 回音之谷（開場預覽） | story |
| LEVEL022 | 尼布魯瀑布（開場預覽） | story |
| LEVEL024 | 哈莫特沙漠（開場預覽） | story |
| LEVEL026 | 日沒灣（開場預覽） | story |
| LEVEL028 | 眾神的宮殿遺址（開場預覽） | story |
| LEVEL029 | 約瑟河（開場預覽） | story |
| LEVEL030 | 絕望之谷（開場預覽） | story |
| LEVEL031 | 漆黑之森（開場預覽） | story |
| LEVEL032 | 拉格納沼地（開場預覽） | story |
| LEVEL033 | 黃昏之丘　陰（開場預覽） | story |
| LEVEL034 | 沙羅尼亞近郊（開場預覽） | story |
| LEVEL036 | 薩魯司海岸（開場預覽） | story |
| LEVEL037 | 古代神殿遺跡（開場預覽） | story |
| LEVEL038 | 幽闇墳場（開場預覽） | story |
| LEVEL039 | 黃昏之丘　陽（開場預覽） | story |
| LEVEL040 | 聖靈之森（開場預覽） | story |
| LEVEL041 | 悲嘆之湖（開場預覽） | story |
| LEVEL043 | 大地的裂縫（開場預覽） | story |
| LEVEL044 | 亞修頓大橋（開場預覽） | story |
| LEVEL045 | 克萊恩城（開場預覽） | story |
| LEVEL051 | 棄卒（開場預覽） | story |
| LEVEL052 | 惡夢的終曲（開場預覽） | story |
| LEVEL053 | 逃出克萊恩城（開場預覽） | story |
| LEVEL055 | 營地・黃昏 | story |
| LEVEL056 | 營地・清晨 | story |
| LEVEL057 | 自覺與宿命・塔克斯之死 | story |
| LEVEL058 | 沃斯菲塔王座廳 | story |
| LEVEL059 | 劫數・地劫神（開場預覽） | story |
| LEVEL060 | 王座廳・俘虜 | story |
| LEVEL061 | 營地・漢克斯的報告 | story |
| LEVEL062 | 營地・漢克斯的警告 | story |
| LEVEL063 | 王座廳・密報 | story |
| LEVEL064 | 營地・雪拉入隊 | story |
| LEVEL065 | 廢都　曼多利亞　村民 | story |
| LEVEL066 | 營地・廢都之後 | story |
| LEVEL067 | 營地・通行證 | story |
| LEVEL068 | 營地・嚎的問題 | story |
| LEVEL069 | 營地・大陸的真相 | story |
| LEVEL070 | 營地・克萊恩城之前 | story |
| LEVEL071 | 王座廳・克羅蒂的疑問 | story |
| LEVEL072 | 沙羅尼亞・海濱步道 | story |
| LEVEL073 | 悲嘆之湖・兄弟的抉擇（劇情預覽） | story |
| LEVEL074 | 斐達克旅館・出發前夜 | story |
| LEVEL075 | 自覺與宿命・塔克斯（開場預覽） | story |
| LEVEL076 | 最終的序曲・妖精王（開場預覽） | story |
| LEVEL077 | 破滅的命運・席德爾（開場預覽） | story |
| LEVEL078 | 接觸・妖精王（開場預覽） | story |
| LEVEL079 | 終焉・咕嚕最終型態（開場預覽） | story |
| LEVEL080 | 禁忌之魂・墳場地下（開場預覽） | story |
| LEVEL081 | 妖精王的告白 | story |
| LEVEL082 | 破滅的命運・終幕 | story |
| LEVEL200 | 龍脊隘口 | battle |
| LEVEL501 | 戈爾山道 · 遭遇戰 | battle |
| LEVEL502 | 戈爾山道 · 遭遇戰 | battle |
| LEVEL503 | 戈爾山道 · 遭遇戰 | battle |
| LEVEL504 | 盜賊洞窟 · 遭遇戰 | battle |
| LEVEL505 | 盜賊洞窟 · 遭遇戰 | battle |
| LEVEL506 | 盜賊洞窟 · 遭遇戰 | battle |
| LEVEL507 | 呼嘯平原 · 遭遇戰 | battle |
| LEVEL508 | 呼嘯平原 · 遭遇戰 | battle |
| LEVEL509 | 呼嘯平原 · 遭遇戰 | battle |
| LEVEL510 | 寧靜之森 · 遭遇戰 | battle |
| LEVEL511 | 寧靜之森 · 遭遇戰 | battle |
| LEVEL512 | 寧靜之森 · 遭遇戰 | battle |
| LEVEL513 | 帕尼西雅城  廢墟 · 遭遇戰 | battle |
| LEVEL514 | 帕尼西雅城  廢墟 · 遭遇戰 | battle |
| LEVEL515 | 帕尼西雅城  廢墟 · 遭遇戰 | battle |
| LEVEL516 | 菲納斯河畔 · 遭遇戰 | battle |
| LEVEL517 | 菲納斯河畔 · 遭遇戰 | battle |
| LEVEL518 | 菲納斯河畔 · 遭遇戰 | battle |
| LEVEL519 | 艾瓦台地 · 遭遇戰 | battle |
| LEVEL520 | 艾瓦台地 · 遭遇戰 | battle |
| LEVEL521 | 艾瓦台地 · 遭遇戰 | battle |
| LEVEL522 | 那可那魯邊境 · 遭遇戰 | battle |
| LEVEL523 | 那可那魯邊境 · 遭遇戰 | battle |
| LEVEL524 | 那可那魯邊境 · 遭遇戰 | battle |
| LEVEL525 | 利魯瑪山地 · 遭遇戰 | battle |
| LEVEL526 | 利魯瑪山地 · 遭遇戰 | battle |
| LEVEL527 | 利魯瑪山地 · 遭遇戰 | battle |
| LEVEL528 | 回音之谷 · 遭遇戰 | battle |
| LEVEL529 | 回音之谷 · 遭遇戰 | battle |
| LEVEL530 | 回音之谷 · 遭遇戰 | battle |
| LEVEL531 | 哈莫特沙漠 · 遭遇戰 | battle |
| LEVEL532 | 哈莫特沙漠 · 遭遇戰 | battle |
| LEVEL533 | 哈莫特沙漠 · 遭遇戰 | battle |
| LEVEL534 | 約瑟河 · 遭遇戰 | battle |
| LEVEL535 | 約瑟河 · 遭遇戰 | battle |
| LEVEL536 | 約瑟河 · 遭遇戰 | battle |
| LEVEL537 | 巴瀚納海峽 · 遭遇戰 | battle |
| LEVEL538 | 巴瀚納海峽 · 遭遇戰 | battle |
| LEVEL539 | 巴瀚納海峽 · 遭遇戰 | battle |
| LEVEL540 | 深淵之沼 · 遭遇戰 | battle |
| LEVEL541 | 深淵之沼 · 遭遇戰 | battle |
| LEVEL542 | 深淵之沼 · 遭遇戰 | battle |
| LEVEL543 | 絕望之谷 · 遭遇戰 | battle |
| LEVEL544 | 絕望之谷 · 遭遇戰 | battle |
| LEVEL545 | 絕望之谷 · 遭遇戰 | battle |
| LEVEL546 | 漆黑之森 · 遭遇戰 | battle |
| LEVEL547 | 漆黑之森 · 遭遇戰 | battle |
| LEVEL548 | 漆黑之森 · 遭遇戰 | battle |
| LEVEL549 | 黃昏之丘  陰 · 遭遇戰 | battle |
| LEVEL550 | 黃昏之丘  陰 · 遭遇戰 | battle |
| LEVEL551 | 黃昏之丘  陰 · 遭遇戰 | battle |
| LEVEL552 | 拉格納沼地 · 遭遇戰 | battle |
| LEVEL553 | 拉格納沼地 · 遭遇戰 | battle |
| LEVEL554 | 拉格納沼地 · 遭遇戰 | battle |
| LEVEL555 | 沙羅尼亞近郊 · 遭遇戰 | battle |
| LEVEL556 | 沙羅尼亞近郊 · 遭遇戰 | battle |
| LEVEL557 | 沙羅尼亞近郊 · 遭遇戰 | battle |
| LEVEL558 | 薩魯司海岸 · 遭遇戰 | battle |
| LEVEL559 | 薩魯司海岸 · 遭遇戰 | battle |
| LEVEL560 | 薩魯司海岸 · 遭遇戰 | battle |
| LEVEL561 | 黃昏之丘  陽 · 遭遇戰 | battle |
| LEVEL562 | 黃昏之丘  陽 · 遭遇戰 | battle |
| LEVEL563 | 黃昏之丘  陽 · 遭遇戰 | battle |
| LEVEL564 | 聖靈之森 · 遭遇戰 | battle |
| LEVEL565 | 聖靈之森 · 遭遇戰 | battle |
| LEVEL566 | 聖靈之森 · 遭遇戰 | battle |
| LEVEL567 | 悲嘆之湖 · 遭遇戰 | battle |
| LEVEL568 | 悲嘆之湖 · 遭遇戰 | battle |
| LEVEL569 | 悲嘆之湖 · 遭遇戰 | battle |
| LEVEL570 | 尼布魯瀑布 · 遭遇戰 | battle |
| LEVEL571 | 尼布魯瀑布 · 遭遇戰 | battle |
| LEVEL572 | 尼布魯瀑布 · 遭遇戰 | battle |
| LEVEL573 | 亞修頓大橋 · 遭遇戰 | battle |
| LEVEL574 | 亞修頓大橋 · 遭遇戰 | battle |
| LEVEL575 | 亞修頓大橋 · 遭遇戰 | battle |
| LEVEL576 | 幽闇墳場 · 遭遇戰 | battle |
| LEVEL577 | 幽闇墳場 · 遭遇戰 | battle |
| LEVEL578 | 幽闇墳場 · 遭遇戰 | battle |
| LEVEL900 | 曼多力亞　對峙（開場預覽） | story |
| LEVEL901 | 菲納斯河畔　伏擊（開場預覽） | story |
| LEVEL902 | 艾瓦台地・尋（開場預覽） | story |
| LEVEL903 | 哈莫特沙漠・魔騎士團（開場預覽） | story |
| LEVEL904 | 利魯瑪山地・再訪（開場預覽） | story |
