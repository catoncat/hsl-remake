# 毒魔箭：source003 的 ST 範圍絕技

> evidence: static-derived · status: live · functions: 0x40a7b0, 0x40aa80 · tools: hsltools/data/poison_arrow.py, hsltools/probes/poison_arrow.py · updated: 2026-09-19

## 證據與邊界

[JSON](original_poison_arrow.json)與 `tools/hsltools/probes/poison_arrow.py` 保存 exact source SPECIAL／TYPE／EXE 身分。無參數離線檢查；`--execute <hsl01.exe> --write` 才執行原指令。44 個 `0x40a7b0` 數值完整返回（special channel1），49 個 `0x40aa80` 應用前段停止於 **0x40b831**，顯示與 EXP 回調之前。全部標 **static-derived**；沒有聲稱原整次施放、整場戰鬥或原牆鐘已執行。

Source `SPECIAL.TXT` 的 magicMIND／magicCode03＝毒魔箭：`damage=30,45`，`hit_ratio=98`，`expend=1`（共同 ST 規則換成20），可選 `range3CellThrust`，`effect_range=range1Cell`，`magicFun_Attack,magicFun_Poison`。初始取得來自 PLAYERS003 的 special_mind 聲明；不是弓武器給的能力，也不是可用 MP 法術。詳見[琥與村民](original_ohm_village.md)。

## 一個目標內的源順序

1. 先用 special channel1/proc0 傷害公式與主命中，套來源精神系抗性和實際 HP 上限。
2. 目標已死亡則不再毒判定、不製造殘留狀態。免疫保留無貢獻原因。
3. 存活／不免疫者做獨立 proc6 毒命中；此絕技分支使用來源主 hit_ratio 與命中補償，不借魔法裝備命中修正或別的 status_hit_ratio。
4. 毒時間 `2+rand(2)`；另一次 proc0 數值的30%供強度。毒合併保留其他旗標，貢獻為實際傷害與新增加毒時間×10；反覆毒不能把未增加的時間當額外貢獻。

原 RNG bounds/value 序列、主命中／毒命中分離、精神抗性、HP1、現有毒與其他狀態、免疫／失敗分支分別在 JSON。prepare 在任何支付或 RNG 前驗證全部將受影響目標；純 `PoisonArrowRules` 回傳變更，PlayLoop 統一提交。

## 一次施放與當前能力

共用 SkillResolution prepare/resolve 支援合法空中心；只對不同 actor 結算一次，不能因大體型有多個格重複中招。每個目標的原數值／狀態後接其 EXP 轉換，全部目標完成才一次20ST扣款和一次最終EXP／成長；過程不以中途升級重算後續目標。穩定 roster 遍歷是重制調度，不由單目標原前段推論原全區物件順序。

禁魔不封鎖 ST 絕技，麻痺／氣力不足／失效目標則完整拒絕。移動後仍按絕技自身範圍，可取消無費用；普通武器射程、雙擊與反擊獨立。白光之翼只給新的整次行動，天劫双击不加倍絕技支付或毒回調。F9、cross-battle learned records、原初始聲明和不可變回執使用既有 owner，不建立第二份技能清單。

## 原圖音與重制演出

`tools/hsltools/data/poison_arrow.py` 從原 spec37/spec38 效果序列及 OBJ-ALL/PAK 解出 SP00_003、SP19（發射、投射、毒球）與 source ATTACK09／SPECIAL6；PNG／WAV 和來源 sha 由 `--check` 逐項重建檢查。`P003_201` 是肖像條、202是臉部小窗、203..206是手／拉弓小窗，不能誤當六個全身施法姿勢。

當前 PoisonArrowPresentation 將未改動的原圖分窗合成，再在地圖對真正的受影響位置播放投射／毒效果和實際傷害／状态文字；只有一個 release／impact。版面、粒子軌跡、scale、混色與以既有0.4播放速率換算的時間是 **provisional 重制演出**，沒有原時鐘或像素逐幀等價主張。消息與後續選單等待不可變交锋回執完成。原素材來源與當前窗口結果見[實玩包](../runtime_observations/ohm_village/README.md)。
