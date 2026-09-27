# level 901 菲納斯河畔伏擊 开场预览（runtime-measured）

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd · updated: 2026-09-19

2026-09-19，presentation 线。数据链由子代理线 ambush901 建成（`1247486`，P-044 协议），本线注册 campaign、接通胜利写入并验证。
窗口化 `tests/capture_story_scene_review.gd -- --level=901`（640×480，正常重制节奏）与 headless 套件的实际运行回执。

## 玩家结果

- 大地图：level 10 廢墟的胜利写入（`actBMSetPointEvent 8,901,bmpmGeneral`）之后到达 菲納斯河畔（点 8）进入 `story_901.json`：
  五人队在河畔桥头被 14 名 023 与 3 名 024 包围，三句对白（1139 隊長／1140 重裝兵／1141 雷歐納德），WORD901 标题，止于首次控制的卡片。
- 卡片两行：「略過戰鬥（視為勝利）→ 回到大地圖」（WINFAIL901 胜利段 `8,gameBigMapLevel`）／「回到大地圖（不施加戰果）」。
- 视为胜利的写入：点 8 → event 516／Visit、遭遇率 20；席達鎮：删 酒館 20 与 護甲店 17、加 護甲店二 45、重建 酒館 20 → [26, 27]、exec event 25。
  由此 席達鎮 酒馆链 25 → 27（女客人）→ 28（妖精）→ 30（女客人二）可走通：揭示 薛維斯港（点 11）与路线 10、曼多力亞 改 event 900、
  薛維斯港 菜单树 [33, 34, 35, 36, 41]＋exec 32——第一章后半（港口→命運神殿）的入口。

## 帧

1. `01-riverside-framed.png`：level 8 地图（`obj-901.obs` 地圖管理員 命名 `SHAPE01\LEVEL08.SHP`；`level901.wrd` 与 `level008.wrd` 同字节）上的伏击阵形。
2. `02-captain-1140.png`：重裝兵（SID_ENEMY024，remake 标签）「叛賊雷歐納德，你逃不了的！」。
3. `03-victory-card.png`：两行选择卡片。

## 自动验证

- `WORLD_MAP_TESTS_PASS`：点 8 event 901（bmpmGeneral）到达 → 交接 `story_901.json`，站点 8。
- `STORY_SCENE_TESTS_PASS`：22 名 cast、三句顺序与说话人、stand-in 配乐、胜利行文案、胜利写入（点 8 event 516／遭遇率 20、席達鎮 exec 25、tree["20"]=[26,27]、45 替 17）。
- `TOWN_SCENE_TESTS_PASS`：以 story_901 的 skip_battle 写入为起点，席達鎮 exec 25 → 酒館 [26,27] → 27 加 28 → 28 改写为 [29,30,31] → 30 揭示 薛維斯港／路线 10／曼多力亞 900、港口菜单树与 exec 32。
- 窗口化 `STORY_SCENE_REVIEW_PASS shots=8`。

## 证据等级与边界

- 地图别名 901→8：地圖管理員 记录＋.wrd 同字节（resource-derived；loader 未定位，仍标 provisional 尾注）。
- 配乐《席達鎮對峙》为 stand-in：原解析器对 level ≥ 100 返回 -1（static-derived），无 901 专属 track。
- 卡片标题「菲納斯河畔　伏擊」为重制标签；WORD901.SHP 实为「狙兵／SNIPER」（resource-derived，已记 unresolved）。
- 战斗本体（第 8 回合增援 031／027／030、琥 与 031 交锋事件 3–5）未重制；「視為勝利」只施加胜利段的城镇／大地图写入。
- 说话人：SID_ENEMY023 一般兵／024 重裝兵 沿用惯例标签（provisional）；031 名字段 306「???」。
