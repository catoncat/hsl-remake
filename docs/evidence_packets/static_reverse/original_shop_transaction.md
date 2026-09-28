# 原作商店交易：买入进手持、放下、卖出价与拒收

> evidence: static-derived; runtime-measured: 原版 v1.06 席達鎮 道具店买入后手持与放下两帧（2026-09-28）; negative-evidence · status: live · functions: 0x40e690, 0x414ab0, 0x414c00, 0x42923b, 0x436e30, 0x436e80, 0x436f30, 0x437020 · tools: hsl_original_control.py, hsltools/assets/town_assets.py, hsltools/checks/function_catalog.py, hsltools/checks/static_index.py · updated: 2026-09-29

## 结论

- 原版商店是共用状态窗 `0x414c00` 的商店分支（窗口标志 `*0x4c1cbc & 2`、子模式 `word [win+0xa2] != 6`）。空手点货行：够钱即扣款、物品写进手持槽 `0x4c1ce4`（音 399），不弹消息、不减货表；玩家再点背包格，物品进首空格（满包时与所点格互换）（static-derived；runtime-measured）；持物时右键／Esc 不动作（根态 `0x428dc7` 只在手持为 0 时关窗，见 [original_storage_window](original_storage_window.md)「结论」）（static-derived）。
- 手上有物点货表即卖出：重要物拒收（607），否则半价入账（static-derived）。手上的物品不论来自背包拿起、卸下、买入还是倉庫，都在同一个手持槽里，都能卖。
- 拿起背包物即离包，其后各格前移（`0x436e80`）；裝備页空手点槽卸下进手（`0x437020`），手持点槽装上时旧装备进手（`0x436f30`）（static-derived）。
- 重制照做：`TownShopScreen` 点货行走 `TownRuntime.shop_pick`（只扣款、手持散件），点背包格走 `shop_hand place`，右键 `back`（放回所显示成员首空格，重制读法）；拿起走 `hand_action lift`，卸下走 `unequip`（满包也进手，不占背包），装上后旧件进手；散件点货表走 `shop_sell_hand`。不弹「買下」消息。
- 共用状态窗的持物音效（static-derived）：进手 399（货表／倉庫列表取出 `0x415559`、背包格拿起 `0x4292c3`、空手卸下 `0x429eb5`），放下 400（背包格 `0x42929d`、装上 `0x429e6d`、放入倉庫列表 `0x415452`），卖出 2563 sfxSellItem（`0x415435`）；重制照放，拒绝时不放。
- 差异：持物时右键／Esc 重制放回首空格（原版不动作）；脚本购物 `TownRuntime.shop_buy` 一步入首空格（autoplay 用，不经窗口）（provisional）。

## 证据

| 项 | 原实现（地址） |
| --- | --- |
| 买入 | 空手点行 `0x415498`：`0x44f3f0` 读行；`0x4154d2 call 0x40e690` 重要行不动；商店分支 `0x415519` 读 ITEM `+0x9c` 价（记录步长 0xb0，表基址 `0x4c1b40`）、`0x415526 cmp gold, price`、`0x41552c jl 0x415611` 不足；`0x415532 sub`、`0x415534` 写回金币 `0x4c1bcc`；`0x41553c mov [0x4c1ce4], code`；商店模式跳过 `0x44f430`（不减货表）；`0x415559 push 0x18f` 音 399；无消息调用 |
| 金钱不足 | `0x415611-0x415624`：`fcn.004072b0(win+0x50, -1, 0x25e, 1)` 消息 606「抱歉, 您的金錢不足無法購買。」，不扣款 |
| 放下 | `0x42923b` 背包格点击（手持）：`0x436ed0` 第 8 格有物 → 所点格与手持互换；否则 `0x436e30` 手持物进首空格 |
| 拿起 | `0x436e80(成员, 格)`：`rep movsd` 把 格+1..7 前移一格，`[+0x154]`（第 8 格）清零 |
| 卸下／装上 | `0x437020` 空手点槽卸下进手（音 399）；`0x436f30` 手持点槽装上、旧装备进手，返回 −1 时不能装、手持不变 |
| 卖出价 | `fcn.00414ab0(code) = ITEM[+0x9c] * 0x32 / 100`（`0x414ac9-0x414ae2`，有符号除法；价格非负即 floor(price/2)）；`0x41541a call`、`0x415428 add`、`0x41542f` 写回金币，音 2563 |
| 音效 | 全 EXE `push 0x18f`／`0x190`／`0xa03` 中属状态窗的七处：`0x415559`（列表取出 399）、`0x415452`（放入倉庫 400）、`0x415435`（卖出 2563），`0x4292c3`／`0x42929d`（背包格拿起 399／放下 400），`0x429eb5`／`0x429e6d`（卸下 399／装上 400）；均经 `0x4477b0`→`0x459990`→`0x42c180`；右键放回 `0x44f63a`／`0x44f652` 附近不放音 |
| 拒收 | `0x4153b1 call 0x40e690`：`(ITEM[+0xa0] & 0x08000000) != 0`（`important` 置位）→ `0x4153c2` 消息 607「抱歉, 本店不收購此物品。」，不成交 |
| 货表 | 来自 town_event 的 `item_code` 对应 `[item]` 表（`teCreateShop`，见 [城镇事件语义](town_event_semantics.md)） |

runtime-measured（`level06_pre_battle` 回憶錄只读进 席達鎮 道具店，雷歐納德，存档 sha1 前后一致）：

| 帧 | 画面 | 读数 |
| --- | --- | --- |
| A 买下后 | 卖掉 回復藥（70→120）后空手点货行 回復藥 $100 | 金钱 120→20；物品贴在鼠标上；背包空；无消息板 |
| B 放下后 | 手持点背包第 3 格 | 回復藥 落在第 1 格（首空格）；金钱仍 20；手空 |

帧在仓库外 `ignored/shophand/`（原版帧见私有档案）；同一买入手势的早先记录见 [原版大地图／城镇实录](../runtime_observations/original_world_town/README.md) 帧 11。

## 重制接线

- `game/world/TownShopScreen.gd`：点货行 `buy_requested` → `TownRuntime.shop_pick` → `WorldPartyRules.pay_for_hand`，回 `show_state(…, {loose, code})`；拿起 `hand_requested("lift")`；空手点槽 `hand_requested("unequip")`；散件点货表 `sell_hand_requested` → `TownRuntime.shop_sell_hand` → `WorldPartyRules.sell_hand`（607 时保留手持）。音效：请求时排队（`HAND_SOUNDS`），宿主提交（`show_state`／`show_loop`／无消息的 `show_carry`）时放 `ItemSound`，`refuse` 或出消息板时丢弃；卖出音是 `interface_audio/sell_item.wav`（sfxSellItem）。
- `game/sim/PartyEquipmentRules.hand_action`：`lift`、`unequip`，`equip` 把旧件取到手持（`_lift_last`）；整理裝備（`PartyEquipmentScreen`）同走。
- provenance：`TownShopScreen` 头注释 static-derived 本包与 [original_storage_window](original_storage_window.md)。

## 复现

```sh
EXE="$HSL_ORIGINAL_DIR/hsl01.exe"
r2 -q -e scr.color=0 -c "s 0x415498; pd 60" "$EXE"   # 空手点行：读行／重要／读价／扣款／手持槽／音 399
r2 -q -e scr.color=0 -c "s 0x415611; pd 8" "$EXE"    # 消息 606
r2 -q -e scr.color=0 -c "s 0x436e80; pd 20" "$EXE"   # 拿起：其后格前移、第 8 格清零
r2 -q -e scr.color=0 -c "s 0x414ab0; pd 17" "$EXE"   # 卖出价 price*50/100
r2 -q -e scr.color=0 -c "s 0x4153a2; pd 16" "$EXE"   # 拒收：0x40e690 → 消息 607
```

运行帧：不可再生为逐字节同图（手动单步会话）；步骤见上表，工具 `tools/hsl_original_control.py`。

## 边界

- 静态阅读＋一次两帧实测；未拍拿起后前移与卸下进手（静态读法），未核对满包互换；音效只有静态读法，未录原版声音。
- 消息 606／607 由引擎代码引用而非 TOWNDEF 脚本，`tools/hsltools/assets/town_assets.py` 以 `ENGINE_MESSAGE_IDS` 显式加入城镇消息表。
- `0x414ab0` 用有符号除法；ITEM.TXT 现有价格均非负，负价格行为不建模。
- 手持槽不进存档：重制扣款后物品只在窗口手上，离店／关窗前右键或 Esc 先放回（重制读法；满包时散件留在手上）。
