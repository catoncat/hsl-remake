# 整理裝備（Title051 世界卷轴第 1 项＝原版共用状态窗模式 0）——接入回执（runtime-measured）

> evidence: runtime-measured · status: live · tools: capture_party_equipment_review.gd, run_party_equipment_tests.gd, run_system_menu_tests.gd · updated: 2026-09-27

2026-09-27，lane PARTYEQUIP 把 2026-09-19 的重制整理画面换成原版窗体（原版读法见[原作仓库窗](../../static_reverse/original_storage_window.md)「模式 0 全貌」）。帧来自 `tests/capture_party_equipment_review.gd`（窗口化，隔离 HOME）；夹具＝level 2 戈爾山道 交接的 carry，另在 雷歐納德 背包放入 銀劍（3）／長弓（61）／回復藥（241）作演示物品（不是默认授予）。

## 玩家结果

- 大地图按 Esc 卷出 Title051 世界卷轴，选「整理裝備」：卷轴收回，打开共用状态窗的模式 0（关窗后卷轴卷回，同原版）——与商店窗同一套板（上方 Vitals 条、左板 (12,168)、右 WINDOW30 装备板 (252,168)、`$:` 框 (20,442)），不压暗大地图。剧情 57／81 与 winfail 045／078 的 `actEnterStorageWindow` 打开的是同一个窗（同一个 `PartyEquipmentScreen.open`）。
- 底部按钮按原版 `0x42ab40` 模式 0 的位置与按页显隐：初始页 狀態 显示 上一位 272／下一位 320／倉庫 389（暗：重制没有队伍仓库）／狀態 457／裝備 505／魔法 553／特殊技 601（y 429）；丟棄／使用 只在倉庫页出现，所以重制里不出现。
- 左板随页换：狀態＝WINDOW21 九行属性；裝備＝背包 8 格（32 px 行）；魔法／特殊技＝该成员的列表（28 px 行）。右板六个装备槽（两列三行、50 px 行距）在每页都显示，悬停出 WINDOW50 说明 (252,390)。
- 换装只在裝備页：点背包物拿到手上（光标换成物品图标）→ 点装备板，按物品类别装上（旧装备回背包）；不能装的（如 長弓 給劍士）留在手上、无提示；空手点有物槽＝卸下（进背包）。右键／Esc 依次：放回手上物 → 关窗；关窗把新队伍写回 hand-off carry 与已保存的战役位置（`user://campaign_progress.json`），金币、`pending_rewards`、`initialization_rng` 等其余顶层字段原样保留。

## 帧

1. `01-status-page-hu.png`：打开时的狀態页（琥；左 WINDOW21 属性、右 長弓／鐵護輪／皮鎧／皮靴、七个按钮、倉庫 暗）。
2. `02-leonard-equip-page.png`：下一位 雷歐納德、裝備页——左板换成背包（回復藥×3、解毒草、銀劍、長弓、回復藥）。
3. `03-holding-silver-sword.png`：拿起 銀劍，背包该格空出。
4. `04-after-equip.png`：点装备板后 武 槽为 銀劍，闊刃劍 回到背包。

## 自动验证

- `tests/run_party_equipment_tests.gd` → `PARTY_EQUIPMENT_TESTS_PASS`：初始页 4 与七个按钮及其中心（272／320／389／457／505／553／601 @ 429）、成员顺序、dry-run 标记（銀劍 ok／長弓 wrong_job／药品不是装备）、被拒物留在手上且无消息板、第一次 Esc 放回手上物不关窗、换装后 weapon_code 与属性刷新、卸下、`project` 只替换同 id 的 units 且其余顶层字段逐字节相等、from_scenario_id 找不到时 `unknown_source_scenario` 只可关闭、无 carry 时 `no_party`；大地图挂接与剧情 storage window 段同前。
- `tests/run_system_menu_tests.gd`：世界卷轴「整理裝備」返回 `party_equipment`。
- 窗口化 `PARTY_EQUIPMENT_REVIEW_PASS`（6 帧，输出 `ignored/partyequip/`）。

## 证据等级与边界

- 窗体、按钮位置与按页显隐、初始页、裝備页的手持规则为 static-derived（`0x42ab40`／`0x42a330`／`0x428410`／`0x4289e0`），并与原版帧 15–17（[原版实录](../original_world_town/README.md)）对过：七个按钮图标、WINDOW21／WINDOW30 左上角、`$:` 框逐像素最佳偏移都是 (0,0)。当前页按钮画暗、右键关窗回到卷轴两处照原版帧做了。
- 重制读法：倉庫 暗（无队伍仓库，规则层不改），丟棄／使用 因而不出现；空手卸下进背包（`PartyEquipmentRules` 的卸下）而不是原版的进手；魔法／特殊技页用普通 WINDOW20 板、无悬停说明与九行以上滚动条；裝備页手持移入装备板时原版左板暂显狀態（根页 0x40a），重制未做；来源场景缺失时的提示字为重制；原版狀態页 力量 的黄字、裝備页背包非装备物的红字（帧 15／16）未做——着色条件未读。
- 规则：`game/sim/PartyEquipmentRules.change` 与 `BattlePlayLoop.change_equipment` 同序，仅去掉战斗阶段门与行动结算。
- 队员来源＝carry.units（正式战斗承接的可控成员）；城镇内没有系统卷轴入口（城镇 Esc＝离开城镇）。
