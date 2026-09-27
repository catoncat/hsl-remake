# 歐姆村：琥、村民、弓與生成生命週期

> evidence: static-derived · status: live · functions: 0x409090, 0x40ba20, 0x40e7a0, 0x40e800, 0x40e870, 0x4100e0, 0x437080, 0x4373f0, 0x437970, 0x437a40, 0x439f80, 0x442720, 0x448840, 0x44cb10, 0x46bd67, 0x46be17 · tools: hsltools/data/ohm_village.py, hsltools/levels/map_objects.py, hsltools/probes/bow_range.py, hsltools/probes/ohm_growth.py · updated: 2026-09-19

## 範圍與可復跑輸入

本包是 **resource-derived + static-derived**，不是原作整場 runtime 觀測。源角色、ITEM、TYPE、RANGE、SPECIAL、SHAPEDEF 與原 EXE 的 SHA 留在同名 JSON；原 EXE 與 PAK 只讀。`tools/hsltools/probes/ohm_growth.py`、`tools/hsltools/probes/bow_range.py` 無參數時驗證已保存輸出；`--execute <hsl01.exe> --write` 才實際執行有界原指令。數值 Python 模型與 Godot 實現分開，前者不替代原執行。

- [角色／成長與控制分支 JSON](original_ohm_growth.json)：52 組輸入各兩次 `0x448840` 完整刷新、39 次生成／配額分配、9 次 EXP caller、8 次武器範圍 getter、6 個複製前段、4 次 AI 陣營選擇、53 次學習完整返回。
- [射擊範圍 JSON](original_bow_range.json)：24 次 `0x4100e0` 完整 coverage-builder 返回，包含 9×9 與 13×13 平坦空圖、中央／邊角與兩種 caller mode。後補 shoot5/6 的 8 次返回保留先前 16 個原輸出；天劫 69 後補兩次裝備刷新，未重算或替換舊 51 組證據。
- [毒魔箭](original_poison_arrow.md)獨立保存傷害、毒判定與應用邊界，不由職業或初始聲明推出完整效果。

## 角色身分與分層

PLAYERS 的 **003** 是 `jobBowMan` 83，`pmPlayer`，原四維 24/16/7/20，弓 61、頭 153、衣 123、鞋 181、兩瓶 241，`special_mind = 毒魔箭`。並無初始魔法；ST 絕技不使其取得 MP 法術。SHAPEDEF／玩家安裝綁定保持 source003，不能用 026 法師借殼。

**061／062 是 `jobSwordMan` 80 + `pmNPCPlayer` 0x50000，並非另一個 jobNPC。** 源表未聲明武器、防具、技能或背包物；各自原四維／HP 額外量與 `level_adjust_range=3, level_adjust_disp_range=0` 獨立。`0x44cb10` 的 NPC 複製分支搜尋 live slot 21..198，保留原模式字。`0x407ef5..0x407f80` 的六組有界前段以明示 general-object-kind 5、源記錄 61/62 和空／部分佔用／槽滿輸入執行完整複製 callee；停在後續物件安裝前，不是整個生成函數返回。槽滿不冒稱成功複製。

`0x40ba20` 在 0x50000 輸入取得敵方搜尋 mask 0x20000，四個完整選擇返回驗證不把同側玩家當敵人。控制、陣營與職業不是同一欄位：本重制村民走 friendly_ai、不可發玩家命令；無武器的源 range0 不產生普通攻擊。這不證明原完整村民逃跑／自救 dispatcher；當前移動、等待、已有合法道具／能力查詢使用共同 AI。沒有為村民製造攻擊動畫或物品。

## 弓手派生與學習

`0x448840` 的 job83 分派在 `0x449032`，共用數值後段 `0x4492f3`，cap row `0x4786d4` 為 **96/98/70/88**。以正整數域逐項截斷，令 S/D/M/C 為基礎力量／反應／精神／體質，L 為等級，H 為 source mode 含 0x10000 時的 L（否則 0）：

```text
HP = H + floor(165*C/100) + floor(S/7)
MP = floor(40*M/100) + floor(C/8)   // 無 magic ownership 時共用尾部置零
Attack = floor(70*floor(S/2)/100) + floor(40*D/100) + 16 + shared_level_bonus(L)
Defense = floor(28*S/100) + floor(M/4) + floor(D/5) + floor(C/3)
Magic = min(50, floor(5*M/100) + L + 8)
Speed = floor(94*D/100)
Resistance bonuses = min(36, floor(p*M/100)+floor(C/divisor))
  earth/water/air/fire/mind: (20,5)/(16,4)/(46,4)/(32,4)/(30,5)
```

上述是職業項；源基本偏移、永久取得、出生調級偏移、當前裝備、臨時攻防增益各自加入，並按既有共同尾部夾限。52 組／104 次完整刷新測試初始、逐級邊界、四維、cap、source-mode、卸裝及天劫；第二次刻意污染派生欄再刷新，EXP/ST 不因重算改變。

`0x4373f0` 的弓手分支不授魔法；`0x437a40 → 0x437970 → 0x437080` 讀 `0x478378` 特技表。五列 class-tier／四維門檻／type／bit 分別為 `(1,28,24,12,25,5,8)`、`(1,42,40,16,36,2,1)`、`(2,52,48,24,50,4,3)`、`(2,65,52,29,60,2,2)`、`(2,80,55,32,70,2,3)`。53 完整返回覆蓋未達／剛達、已擁有、preview 不寫與 commit 寫入，零 RNG；初始毒魔箭聲明不替代這份後天學習表。尚無效果實現的其他新學技仍明示不可施放。

## 出生、EXP、自動分配與保存

復用 [SR-071 的獨立原調級證據](original_auto_growth.md)及 [SR-072 caller／學習](original_growth_lifecycle.md)，而非另建 progression owner。

`0x40e800` 由基礎四維推級；`0x40e7a0` 只平均登記玩家，不因村民友方就計入。`0x40e870` 接收來源或腳本的兩個調級參數：可能消耗原 RNG 並提高實例獎勵與獨立出生偏移，最後自動分配／派生刷新；不把已完成出生當一般裝備刷新再次執行。39 組新角色輸入完整返回核對這條組合。`0x439f80` 的 job83 配額是 1/2/1/1；061/062 的 job80 配額是 2/1/1/1。9 個 `0x442720` EXP caller 中 NPC 與無升級路徑完整返回，兩個需玩家加點路徑停在 **0x442a45、UI 之前**；不把 prefix 寫作 full return。

`actSetPrevInsertObjectAdjustLevel` 原 opcode56（`0x450ba4`）只將兩字寫入上一有效物件的 packed 參數，**不是當下再次升級**；原數值入口及兩次 VM 的既有 SR-071 證據可復用。本重制 `ReinforcementGrowthRules` 在新實例初始化時讀它，於單一 PlayLoop 保存 entry_growth 的 input／draws／result；後續 NPC EXP 自動分配與這個出生記錄互不覆盖。還原、第二行动與裝備變更只驗證／重算，不抽取第二份出生。

lane RNG-A（2026-09-25）起，出生調級改抽 loop 的全局流 `global_rng`（`GlobalRandomStream`：原生成器 `0x458c10`／`rand` `0x458c80`，狀態對應原版 `0x4795d4`／`0x4795d8`，不入存檔、不隨跨戰承接），獨立的 `initialization_rng` 退役；登記玩家先於一般 NPC 的建立順序、跨戰 refill／carry 仍是明示重制組合。全局流上其它抽取（AI 決策鏈、動畫延遲）的次數尚未與原版一致，所以同一時鐘種子下的出生結果不等於原版那一局。

## 有符號弓範圍與兩種追加機制

原 `range3CellShoot` 的負值近身格不許射擊；不是填滿的三格菱形。弓61正常射程取原 index，範圍飾品提升到下一個 source mask。`0x409090` 的 source getter、`0x4100e0` 有符號 coverage 均有返回證據。天劫69的原 `double_attack`、jobBowMan 裝備資格與 shoot5/6 使用同一來源；只在明示驗收庫存中提供，不加入正式 003 的初始物品。

`double_attack` 在一次普通攻擊／反擊系列內追加擊，`action_twice`（白光之翼227）在系列和全部 EXP／演出完成後給一次新行動。第二行動的毒魔箭不因此變成兩次施放；當前裝備、技能、資源與位置重新檢查。實玩暴露並修正：卸弓仍亮 Attack；以及非自身範圍絕技的空中心已通過 prepare，卻被玩家舊普通攻擊占格檢查拒絕。普通攻擊仍要求實體目標，單體技能限制仍由各自 prepare 驗證。

## 正式關卡與明確負證據

`tools/hsltools/data/ohm_village.py` 只讀 source seed、已有 preview 的綁定和既有 status_timeline 編譯器，生成 18 名實際戰鬥角色：001/003、六028、兩036、三061、五062。正式戰役53的 `[1,1]` 進入 `ohm_village_battle.json`；preview 保留為獨立回歸，但不再替代戰鬥。

**negative-evidence（限定查證範圍）**：已逐條核對保存的 STORY001/WINFAIL001 action 列表；其中沒有 actInsertObject／actSetPrevInsertObjectAdjustLevel，也沒有玩家到達撤離區的胜利條件。因此不往正式001加假增援或逃跑門。新增的 event901 村民插入是明示測試 fixture；其 source role／調級 callee 是原證據，事件內容不是原關卡。原 win1 是028剩≤3後敵軍撤退；win0是敵軍全滅；fail0主角死亡；fail1兩種村民均全滅。實玩、範圍與來源邊界見[當前驗收](../runtime_observations/ohm_village/README.md)。

## 地圖組合物件落點（房屋／樹＋影）

**static-derived**：EVEF 物件循環 `0x46be17` 遇到代碼帶 `0x80000000` 的記錄，以記錄 x/y 與組合槽號呼叫 `0x46bd67`；後者讀關卡 BIN 尾表該槽的 `[count, (code,x,y)…]`，先算 `delta = EVEF xy − 第一個子物件的表內 xy`，再把每個子物件安裝在 `表內 xy + delta`（`0x46bd9b..0x46bdb8`）。所以第一個子物件站在 EVEF 點，其餘保持相對位置。舊讀法「EVEF 點＋表內 xy」把歐姆村三棟房屋整體推向右下約 300×220 像素，壓住水井（WRD 阻擋格 (18..19,17)）並蓋在開場站位上；修正後雷歐納德／琥站在水井西南、房屋圍繞村中空地。同一規則由 `hsltools/levels/map_objects.py` 對所有帶組合表的關卡（1、2、22、36、37、501–503、558–560、570–572）生效；只改變表現層物件位置，不改 WRD 地形或站位。

未確認：原完整物件安裝／釋放排程、完整控制狀態機、弓的全高差／障礙傳播、原實時粒子／牆鐘、原跨關持久化。替換證據需相应完整 caller／原运行观测，不能由這些正常返回或 Godot PASS 推廣。
