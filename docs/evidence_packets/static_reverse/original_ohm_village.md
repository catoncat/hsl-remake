# 歐姆村：琥、村民、弓與生成生命週期

> evidence: static-derived; resource-derived: 源角色與關卡表; negative-evidence: STORY001／WINFAIL001 無增援與撤離勝利 · status: live · functions: 0x409090, 0x40ba20, 0x40e7a0, 0x40e800, 0x40e870, 0x4100e0, 0x437080, 0x4373f0, 0x437970, 0x437a40, 0x439f80, 0x442720, 0x448840, 0x44cb10, 0x46bd67, 0x46be17 · tools: hsltools/data/ohm_village.py, hsltools/levels/map_objects.py, hsltools/probes/bow_range.py, hsltools/probes/ohm_growth.py · updated: 2026-09-28

## 结论

- 原版琥（003）是 jobBowMan 83，派生走 `0x448840` 的 job83 分支、cap 96/98/70/88，學技讀 `0x478378` 特技表；村民 061／062 是 jobSwordMan 80＋pmNPCPlayer 0x50000，敵方搜尋 mask 0x20000；弓射程為有符號 coverage，近身負值格不可射；地圖組合物件以第一個子物件對齊 EVEF 點（static-derived）。
- 重制 `tools/hsltools/data/ohm_village.py` 生成正式戰役中緊接玩家第 3 场 · 逃出克萊恩城（LEVEL053）之後的歐姆村（LEVEL001）18 名戰鬥角色，出生調級走共同 `ReinforcementGrowthRules`／全局流，村民走 friendly_ai，組合物件落點由 `tools/hsltools/levels/map_objects.py` 統一計算（static-derived）。
- 差異：村民完整逃跑／自救 dispatcher、原物件安裝排程與同種子出生結果未恢復（provisional）；STORY001／WINFAIL001 無增援與撤離勝利（negative-evidence），故正式關不加假增援。

## 证据

**static-derived**（原 EXE 與 PAK 只讀；[original_ohm_growth.json](original_ohm_growth.json)、[original_bow_range.json](original_bow_range.json)）

| 項 | 錨點 | 讀法 |
| --- | --- | --- |
| 覆蓋量 | — | 52 組輸入各兩次 `0x448840` 完整刷新、39 次生成／配額分配、9 次 EXP caller、8 次武器範圍 getter、6 個複製前段、4 次 AI 陣營選擇、53 次學習完整返回；`0x4100e0` 24 次完整返回（9×9／13×13 平坦空圖、中央／邊角、兩種 caller mode，含 shoot5/6 後補 8 次；天劫 69 後補兩次裝備刷新） |
| job83 派生 | `0x449032`，共用後段 `0x4492f3`，cap row `0x4786d4` | 見下式；第二次刷新前污染派生欄，EXP/ST 不變 |
| NPC 複製 | `0x44cb10`；前段 `0x407ef5..0x407f80` | 搜尋 live slot 21..198，保留原模式字；六組前段停在物件安裝前，槽滿不算成功 |
| 陣營選擇 | `0x40ba20` | 0x50000 輸入得敵方搜尋 mask 0x20000，不把同側玩家當敵人 |
| 學技 | `0x4373f0`（弓手不授魔法）；`0x437a40 → 0x437970 → 0x437080` 讀 `0x478378` | 五列 (class-tier, 四維門檻×4, type, bit)：(1,28,24,12,25,5,8)、(1,42,40,16,36,2,1)、(2,52,48,24,50,4,3)、(2,65,52,29,60,2,2)、(2,80,55,32,70,2,3)；零 RNG，preview 不寫、commit 寫 |
| 出生調級 | `0x40e800`、`0x40e7a0`、`0x40e870` | 同 [original_auto_growth.md](original_auto_growth.md)；`0x40e7a0` 只平均登記玩家，不計友方村民 |
| 自動分配配額 | `0x439f80` | job83 為 力1 反2 精1 體1；job80 為 2/1/1/1 |
| EXP caller | `0x442720` | 9 例：NPC 與無升級路徑完整返回；兩個需玩家加點路徑停在 `0x442a45`（UI 之前） |
| opcode 56 | `0x450ba4` | 只把兩字寫入上一有效物件的 packed 參數，不當下升級 |
| 弓範圍 | `0x409090` getter、`0x4100e0` 有符號 coverage | `range3CellShoot` 負值近身格不可射；範圍飾品升到下一個 source mask |
| 組合物件 | `0x46be17` → `0x46bd67`（`0x46bd9b..0x46bdb8`） | 代碼帶 `0x80000000` 的 EVEF 記錄讀 BIN 尾表 `[count,(code,x,y)…]`；`delta = EVEF xy − 第一子物件表內 xy`，每個子物件裝在 `表內 xy + delta` |

job83 職業項（S/D/M/C 基礎四維，L 等級，H = source mode 含 0x10000 時的 L，否則 0；正整數截斷）：

```text
HP = H + floor(165*C/100) + floor(S/7)
MP = floor(40*M/100) + floor(C/8)            （無 magic ownership 時共用尾部置零）
Attack = floor(70*floor(S/2)/100) + floor(40*D/100) + 16 + shared_level_bonus(L)
Defense = floor(28*S/100) + floor(M/4) + floor(D/5) + floor(C/3)
Magic = min(50, floor(5*M/100) + L + 8)
Speed = floor(94*D/100)
抗性加值 = min(36, floor(p*M/100) + floor(C/divisor))，地/水/風/火/心 (p,divisor) = (20,5)/(16,4)/(46,4)/(32,4)/(30,5)
```

源基本偏移、永久取得、出生偏移、當前裝備、臨時攻防各自加入，再經共同尾部夾限。

**resource-derived**

| 角色 | 源資料 |
| --- | --- |
| 003 琥 | jobBowMan 83、pmPlayer、四維 24/16/7/20；弓 61、頭 153、衣 123、鞋 181、兩瓶 241；`special_mind = 毒魔箭`；無初始魔法；SHAPEDEF 綁 source003 |
| 061／062 村民 | jobSwordMan 80、pmNPCPlayer 0x50000；無武器／防具／技能／背包；`level_adjust_range=3, level_adjust_disp_range=0`；源 range0 不產生普通攻擊 |
| 天劫 69 | `double_attack`，jobBowMan 裝備資格，與 shoot5/6 同源 |
| 正式關（戰役 53 `[1,1]`） | 18 名：001/003、六 028、兩 036、三 061、五 062；win0 敵軍全滅、win1 028 剩 ≤3 後敵軍撤退、fail0 主角死亡、fail1 兩種村民全滅 |

**negative-evidence**：逐條核對 STORY001／WINFAIL001 action 列表，無 `actInsertObject`／`actSetPrevInsertObjectAdjustLevel`，也無玩家到達撤離區的勝利條件。

## 重制接线

- `tools/hsltools/data/ohm_village.py`：由 source seed、preview 綁定與 status_timeline 編譯器生成 `ohm_village_battle.json`；preview 保留為獨立回歸。
- `game/sim/ReinforcementGrowthRules.gd`：新實例初始化時讀 opcode 56 參數，PlayLoop 保存 entry_growth 的 input／draws／result；抽樣走全局流 `global_rng`（原生成器 `0x458c10`、`rand` `0x458c80`，狀態對應 `0x4795d4`／`0x4795d8`，不入存檔）。
- `game/sim/loop/BattleLoopInventory.gd`：provenance 頭寫 `rules: static-derived docs/evidence_packets/static_reverse/original_ohm_village.md`。
- `tools/hsltools/levels/map_objects.py`：組合物件落點，作用於帶組合表的關卡 1、2、22、36、37、501–503、558–560、570–572；只改表現層位置，不改 WRD 或站位。
- `double_attack`（系列內追加擊）與 `action_twice`（白光之翼 227，系列與 EXP 完成後一次新行動）分開；第二行動重新檢查裝備、技能、資源與位置。卸弓不再亮 Attack；非自身範圍絕技的空中心不受普通攻擊佔格檢查。
- 村民 friendly_ai、不可下令；登記玩家先於一般 NPC 的建立順序、跨戰 refill／carry 是重制組合（provisional）。
- event901 村民插入是測試夾具（source role／調級 callee 為原證據，事件內容不是原關卡）；天劫 69 只在驗收庫存提供。毒魔箭效果見 [original_poison_arrow.md](original_poison_arrow.md)。

## 复现

`python3 tools/hsl.py check ohm_growth`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [ohm_village](../runtime_observations/ohm_village/receipt.json) | opening、natural、mixed、silence、limited、retreat、defeat、villagers、clear、insert61、insert62、double、ai_current、ai_paralysis、campaign53_to_ohm_to_world | `run_ohm_village_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 村民完整逃跑／自救 dispatcher 未讀；當前用共同 AI 的移動、等待與合法道具查詢，不為村民造攻擊動畫或物品。
- 原完整物件安裝／釋放排程、完整控制狀態機未讀。
- 弓的全高差／障礙傳播未讀（coverage 只在平坦空圖執行）。
- 全局流上其它抽取（AI 決策鏈、動畫延遲）次數與原版不同，同種子出生結果不等於原版那一局。
- 原實時粒子／牆鐘未恢復；跨關承接已照原版註冊表（[注册表与交接写回](original_campaign_actors.md#证据)）。
- 技能與被動已無拒絕項（差異清單 `unimplemented-abilities`）；未知字段與未識別常量仍明確拒絕，只守以後新增的行。
