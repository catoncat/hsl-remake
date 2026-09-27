# 原作商店交易：买入价、卖出价与拒收

> evidence: static-derived; negative-evidence · status: live · functions: 0x40e690, 0x414ab0, 0x414c00 · tools: hsltools/assets/town_assets.py, hsltools/checks/function_catalog.py, hsltools/checks/static_index.py · updated: 2026-09-19

Checked: 2026-09-19

**static-derived**（r2 反汇编＋ r2ghidra 反编译阅读 `hsl01.exe`，sha256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；无有界执行、无 Wine）。回答 [原作大地图与城镇](original_world_town.md) 中「买入／卖出 handler」的 negative-evidence 项；消息输入时钟、teDelay 墙钟与入包放置流程不在本包范围。

## 结论

背包／商店窗口 handler 是 `0x414c00`（目录角色 ui_menu_input；每帧绘制 5 行物品、以手持槽 `0x4c1ce4` 做拾起／放下）。商店分支只在窗口标志 `(*0x4c1cbc & 2) != 0` 且窗口子模式 `word [win+0xa2] != 6` 时执行；金币全局为 `0x4c1bcc`（与 `teCheckMoney` 同址）。

| 项 | 原实现（地址） | 重制现状 |
| --- | --- | --- |
| 买入价 | ITEM 记录 `+0x9c`（ITEM.TXT price 列，记录步长 0xb0，表基址 `0x4c1b40`）：`0x415519` 读价、`0x415526 cmp gold, price`、`0x41552c jl` → 不足；足够时 `0x415532 sub` 立即扣款，`0x41553c` 把物品 code 放入手持槽 `0x4c1ce4`，随后播放 399 `WAV\TAKEUP01.WAV` | 按 ITEM.TXT price 扣款一致；物品直接入商店窗所显示成员的首空格（重制交互改写，见边界） |
| 金钱不足 | `0x415611-0x415624`：`fcn.004072b0(win+0x50, -1, 0x25e, 1)` 弹出消息 606「抱歉, 您的金錢不足無法購買。」，不扣款 | 原消息 606 文本（`TownRuntime._reason_text`） |
| 卖出价 | `fcn.00414ab0(code) = ITEM[+0x9c] * 0x32 / 100`（`0x414ac9-0x414ae2`，magic 0x51eb851f 有符号除法；价格非负即 floor(price/2)）；`0x41541a call`、`0x415428 add`、`0x41542f` 写回金币，播放 2563 `WAV\GOLD001.WAV` | `WorldPartyRules.sell_price` 同式 `(cost * 50) / 100` |
| 拒收 | `0x4153b1 call 0x40e690`：`fcn.0040e690(code) = (ITEM[+0xa0] & 0x08000000) != 0`，即 ITEM loader 由 `important` 非零置位的标志（见 [原道具行为](original_item_actions.md)）；置位时 `0x4153c2` 弹出消息 607「抱歉, 本店不收購此物品。」，不成交 | 同：拿起重要物品放到货表时拒收，BOARD02 弹原消息 607（`TownShopScreen`，R5-L6b 起） |
| 货表 | 买入不减少货表；货表来自 town_event 的 `item_code` 对应 `[item]` 表（`teCreateShop`，见 [城镇事件语义](town_event_semantics.md)） | 一致 |

非商店模式下同一手势是背包内拾起／放下（声音 399／400 `WAV\PUT00003.WAV`），不涉及金币。

## 边界

- 静态阅读；未执行窗口 handler，不证明排版、滚动、鼠标热区与消息框的关闭输入。
- 原作买入后物品进入手持槽再由玩家放到成员背包格；重制改为「点货行→所显示成员首空格入包」——这是用户允许的交互改写，不声称原流程等价。卖出照原手势：拿起背包物、点货表（[原版大地图／城镇实录](../runtime_observations/original_world_town/README.md) 帧 09／10）。
- 消息 606／607 由引擎代码引用而非 TOWNDEF 脚本，`tools/hsltools/assets/town_assets.py` 以 `ENGINE_MESSAGE_IDS` 显式加入城镇消息表。
- `0x414ab0` 用有符号除法；ITEM.TXT 现有价格均非负，负价格行为不建模。

## 复跑

```sh
EXE="$HSL_ORIGINAL_DIR/hsl01.exe"
r2 -q -e scr.color=0 -c "s 0x414ab0; pd 17" "$EXE"   # 卖出价 price*50/100
r2 -q -e scr.color=0 -c "s 0x40e690; pd 6" "$EXE"    # important 位 0x08000000
r2 -q -e scr.color=0 -c "s 0x415510; pd 14" "$EXE"   # 买入：读价／比较／扣款／手持槽
r2 -q -e scr.color=0 -c "s 0x415611; pd 8" "$EXE"    # 消息 606
r2 -q -e scr.color=0 -c "s 0x4153a2; pd 16" "$EXE"   # 拒收：0x40e690 → 消息 607
r2 -q -e scr.color=0 -c "s 0x41540a; pd 12" "$EXE"   # 卖出：0x414ab0 → 金币加、音 2563
python3 tools/hsl.py check function_catalog
python3 tools/hsl.py check static_index_check
```
