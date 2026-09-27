# 原作酒館神秘男子（teSecretManBuyThing）

> evidence: static-derived; provisional · status: live · functions: 0x4072b0, 0x40e690, 0x42c7e0, 0x42e070, 0x42e640, 0x44e0e0, 0x44ef70, 0x44f100, 0x454db0, 0x454e20, 0x458c80, 0x460058 · tools: hsltools/data/secret_man_goods.py, run_town_event_rules_tests.gd · updated: 2026-09-19

Checked: 2026-09-19

**static-derived**（r2ghidra 反编译＋ r2 反汇编阅读 `hsl01.exe`，sha256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；无有界执行、无 Wine）。回答 [城镇事件读法表](town_event_semantics.md) 未解语义里「神秘商人：表索引推进与 BuyThing 买卖价格」两项；默认出现率仍 provisional。

## 数据链

- 城镇 VM `0x454e20` case 0x27 = te token 39 `teSecretManBuyThing [shape][name][fail msg][fail event]`（TOWNDEF 只在 121「酒館神秘男子選一」使用：`-1,1607,1282,122`）。
- 货表 `.data 0x4793b0`：9 行 × 0x22 字节，每行 int32 价格 + 15 个 int16 物品 code；`tools/hsltools/data/secret_man_goods.py` 从 SHA 锁定的 EXE 读出并写入 [`secret_man_goods.json`](../../../content/generated/hsl/static/hsl01/secret_man_goods.json)（`--check` 在无 EXE 时做离线交叉核对：价格严格递增且等于宣传词 1608–1616 的 `$N`，全部 code 在 ITEM.TXT）。
- 计数器 `0x4c1bd4`（重制 `secret_man_index`）同时选中 `0x479398` 表的宣传事件（123,113,…,120，见 `teAppearSecretMan` 的 `0x454db0`）与本表的行；新游戏初始化 `0x42c7e0` 在 `0x42ca70` 清零，战斗记录 `0x42e070`／`0x42e640` 存取。

| 行 | 价格 | 宣传 | 物品（15 槽，按位置） |
| --- | ---: | --- | --- |
| 0 | 5000 | 123→1608 | 8 炎魔劍、145 怨念血衣、172 兔耳朵、196 高跟鞋、204–209 五色戒指与詛咒戒指、163 女神之冠、209（再一次）、239／240／234 水晶 |
| 1 | 7500 | 113→1609 | 9、136、135、134、133、164、172、195、222、221、218、220、214、213、212 |
| 2 | 10000 | 114→1610 | 10 聖紋之劍、11 妖刀 鬼哭、46、65、87、106、137 法王聖衣、165、188、226、225、219、211、234、237 |
| 3 | 15000 | 115→1611 | 146 奧汀特製Ｔ恤、26、47、66、89、107、138、166、189、230、224、223、216、215、238 |
| 4 | 20000 | 116→1612 | 12、27、48、67、90、108、139、167、190、228、234、237、238、239、240 |
| 5 | 30000 | 117→1613 | 13、28、49、68、91、109、140、168、191、229、296–300 结晶 |
| 6 | 40000 | 118→1614 | 14、29、299、69、92、110、141、171、192、231、291–295 结晶 |
| 7 | 60000 | 119→1615 | 300、298、297、296、91、295、142、170、193、232、291–294、301 |
| 8 | 99999 | 120→1616 | 16、30、50、70、93、111、144、143、146、169、194、233、227、236、301 透明天晶 |

## handler 行为（case 0x27）

1. `price = table[counter].price`；`gold (0x4c1bcc) < price` → 若 `[shape] != -1` 载入脸图（`0x460058`），弹出 `[fail msg]` 消息框（`0x4072b0`），并把脚本指针改到 `[fail event]`（`0x44e0e0`，为 0 时留在原链继续）。TOWNDEF 121 的失败消息是 1282「抱歉, 您的金錢不足！」，失败事件 122（1623「OH NO！…」＋ teDeleteSecretMan）。
2. 否则 `gold -= price`；统计该行非零槽数 n（现有数据全部 15），`k = rand(n)`（`0x458c80`，越界钳到 n-1／0），取 `items[k]`——按**位置**取值，因此第 0 行的 209 詛咒戒指占 2/15。
3. 物品入账走与 `teGetItem` 相同的分叉：`0x40e690`（important 位）置位 → `0x44ef70(item, 1)` 重要物品表 `0x4c1d10`，否则 `0x44f100(item, 1)` 普通物品表 `0x4c1d1c`（两者都是「已有则计数 +1，否则追加 {code,count}」）。
4. 计数器 `< 8` 时 +1（因此 99999 行可重复购买）。
5. 以缓冲串 1354 组合 1621「獲得」＋ 物品名（ITEM 记录 +4 的名字资源）弹出消息框，随后脚本继续（121 接着播 1622「哈哈！下次有緣再相見啦！」并 teDeleteSecretMan）。

## 重制接线

- `TownEventRules.teSecretManBuyThing`：从 `secret_man_goods.json` 取 `secret_man_index` 行；金币不足 → 无脸（`-1`）的 `shape_message` 1282 ＋ `check_failed`，再跳失败事件；足够 → `spend_gold`、`get_item`（与 teGetItem 相同的 party 入包）、`secret_man{purchase}` 回执，`secret_man_index` +1（上限 8）。抽样用重制自己的 RNG（`state.secret_pick` 可钉住供测试）。
- `WorldMapRules.initial_state` 起始 `secret_man_index = 0`，随世界状态存档。
- `TownRuntime` 的 `get_item` 叙述行已是「獲得 <名> × 1」，与原 1621 一致；无脸消息按叙述行显示、不再记 `portrait_missing`。

## 边界

- 静态阅读；未执行 VM，不证明消息框排版与关闭输入。
- 原 `rand(n)` 是全局 RNG，重制抽样分布相同但序列不同。
- `teAppearSecretMan` 的默认出现率（`DEFAULT_SECRET_APPEAR_RATIO`）仍 provisional，不在本包范围。

## 复跑

```sh
python3 tools/hsl.py check secret_man_goods            # 有 EXE 时逐字节比对，否则离线交叉核对
PYTHONPATH=tools python3 -m hsltools.data.secret_man_goods --exe "$HSL_ORIGINAL_DIR/hsl01.exe"   # 重建
tools/godot.sh --headless --script res://tests/run_town_event_rules_tests.gd
r2 -q -e scr.color=0 -c "s 0x4552a0; pd 60" "$HSL_ORIGINAL_DIR/hsl01.exe"   # case 0x27 区段
```
