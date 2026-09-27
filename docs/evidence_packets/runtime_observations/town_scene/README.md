# 菜单式城镇画面 — runtime-measured

> evidence: runtime-measured; provisional · status: live · tools: capture_town_review.gd, hsltools/assets/town_assets.py, run_town_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_town_review.gd --resolution 640x480 --screen 0`（`TOWN_REVIEW_PASS shots=11`，正常重制节奏，三次连跑无重按；headless 回归为 `tests/run_town_scene_tests.gd`）。城镇由 `game/world/TownRuntime.gd` 在大地图到达 bmpmTown 点时挂在 `UI` 下，菜单树与 te 事件来自 `content/imported/hsl/global/world_map/towndef.json`（解释器 `game/sim/TownEventRules.gd`，[读法表](../../static_reverse/town_event_semantics.md)），文字／头像／货表来自 `town_messages.json`／`town_portraits.json`／`town_shop_items.json`（`tools/hsltools/assets/town_assets.py`），初始根菜单来自 provisional 的 `content/world/town_initial_trees.json`。

## 看到什么

1. `01-ohm-village-root-menu.png`：TownBG01.SHP（325×185）配点名「歐姆村」、队伍条（金錢 275、同伴：雷歐納德）与右侧菜单——武器店／護甲店／道具店（初始树 [1,2,3]）＋「離開城鎮」。（此截图为 2026-09-18 旧构图；R5-L5b 起构图改按原版，见下「构图」。）
2. `02-weapon-shop-greeting.png`：点武器店先播 teShapeMessage（FACE0073 武器店老闆、消息 869「歡迎光臨…」）；对白板复用 `BattleDialogue`（BOARD02）。
3. `03-shop-buy-panel.png`：确认后 teCreateShop 开商店：货表＝TOWNDEF item 1（長劍 200／木杖 180／匕首 210，ITEM.TXT 标价），右侧金錢与收货成员（雷歐納德，空格 7）；先选商品再选人。
4. `05-shop-sell-panel.png`：賣出页列出成员背包内可卖物品与半价（長劍 100），重要物品拒卖；标注为重制暂定。
5. `08-exec-event-villager.png`：预置 `towns["1"].exec_event = 10`（原作 level 1 胜利后由 `actSetTownExecEvent` 预置事件 9；10→11→0 为完成链）后再进城，入城即播 FACE0062 村民「盜賊解決了嗎?」。
6. `10-exec-event-gold-grant.png`：链中 teGetGold 2000 以旁白「獲得 2000 金錢」呈现，队伍条即时显示解释器中的金錢；链末 teSetExecEvent 11 落盘，再进城跑 11 后解除。

## 构图（R5-L5b，按原版帧）

原版实录 [original_world_town](../original_world_town/README.md) 帧 03／04（runtime-measured）：进城不压暗大地图（状态栏与网格线仍可见）；TownBG 模板匹配在 (158,148)；菜单是 WINDOW70.SHP 石纹板，匹配在 (60,60)、叠在 TownBG 左上；菜单项为白色平排字，自 x 72、字行中心 y 79.5＋32·n。对白：teShapeMessage（NPC）用上方对白板（重制 y 20，原版文字板 y 22），tePlayerMessage（队伍成员）用下方（`BattleDialogue` 底槽 y 320）；上下分工由 7 句样本归纳（provisional），转职结果与重制旁白（获得金钱／物品）放下方。放消息时石纹板隐藏（原版帧 05–07 同）。lane TOWNMAP 起照原版帧 03／04 去掉重制补的点名、金錢／同伴条与「離開城鎮／返回／取消」按钮，右键／Esc 离城、退子菜单、取消选人；select／player_select 的选项作为石纹板里的文字行（重制读法）。商店画面无原版实录，保持重制构图（provisional）。窗口复核 `tools/godot.sh --script res://tests/capture_ui_reference_review.gd`：大地图底条与 席達鎮／兩棲族部落 根画面按原版帧 01／03／04 的镜头截图，另截 NPC 上方与队伍下方对白（输出在 `ignored/ui-reference-review/`，只作目视对照）。

## 断言（headless）

`WorldPartyRules`：carry→party（金币、按背包码计数、SID 成员）、`apply_party` 差额首空格入包／移除／无空格 dropped 回执、`buy` 扣标价入首空格与三种拒绝、`sell` 半价与重要物品／格位变化拒卖。场景：歐姆村根菜单与 TownBG（构图：无全屏压暗、TownBG (158,148)、WINDOW70 (60,60) 在 TownBG 之上、各项在原版行位、重制多出的点名／队伍条／離開城鎮不与原版元素及状态栏字行相交、状态栏仍在城镇下方可见）、武器店老闆招呼用上方对白板且石纹板隐藏、席達鎮 雷歐納德（tePlayerMessage）用下方、米蘭多酒館子菜单行在石纹板里、招呼→商店货表、买長劍后 hand-off carry 背包 [1,1,0…]／金 75 并写入 `user://campaign_progress.json`、匕首金钱不足、非货表拒买、卖出回 175、关店回根菜单、Escape 离城后 carry 保留且地图图层重绘；10→11→0 链与落盘；米蘭多酒館子菜单→14 长对白→树改写 [8,12,13,15]→回菜单→退出；席達鎮事件 23 的 teSetNextPlayLevelEvent 6 关城并弹未重制关卡卡。

## 边界

- 城镇根画面构图按原版帧（见上「构图」）；商店买卖画面、离开城镇的原版操作未采到，商店面板与「離開城鎮」按钮为重制；TOWNDEF 每条消息 if_wait 均为 0，重制改为每句等待确认，teDelay 与 tePlaySound 只记录不播放。
- 买卖为重制政策：按 ITEM.TXT 标价购买、放入所选成员首个空格；卖价＝标价÷2 向下取整；原买卖处理函数未定位（P-027 追加）。
- 各城初始根菜单为 provisional（按 TOWNDEF 行尾注释归类），原静态表未定位（P-027）；teCheck* 失败语义按读法表 provisional。
- 城镇交易只改 hand-off 的 carry（金币与各成员 8 格背包）；进入下一战时由既有 `CampaignCarryRules.apply` 生效，战斗内物品规则不变。
