# 盜賊洞窟（level 3）：正式戰鬥回執

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py, run_battle_sweep_tests.gd, run_campaign_tests.gd, run_story_mode_walkthrough_tests.gd, run_story_scene_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-20

本包記錄 Godot 重製版正式 level 3 的一次實際窗口化運行，不是原版 EXE 現場。原 STORY003／WINFAIL003 的演員、寶箱與 token 順序為 resource-derived；本次開場節奏、強制勝利夾具、鏡頭與結果頁為 runtime-measured 的重製運行，不能據此聲稱原版等價。

## 入口

戰役表的 level 3 現在直接進 content/battles/battle_003.json。場景由 python3 tools/hsl.py generate level_battle:3 從 STORY003 預覽、level 3 seed、審核過的演員模板與一個 EVEF 寶箱組裝；戰後 WINFAIL003 的模式切換把漢克斯由 enemy_ai 轉為 player_controlled 並清除 undead 標記，再由戰役 carry 進入後續 STORY061。

- 17 名初始單位：3 名受控角色、漢克斯與 13 名敵方單位。
- 漢克斯 開場為 pmEnemy／undead；勝利段為 pmPlayer／非 undead。這是 static-derived 的 player mode／PLAYER_TABLE bit 讀法在唯一 PlayLoop 狀態上的重製接入。
- level 3 seed 的 EVEF record 27 提供一個寶箱；content/generated/hsl/treasures/battle_003.json 使用 PAK 重建取得的 treasure_words。

## 本次回執

| 帧 | 內容 |
| --- | --- |
| [opening.png](opening.png) | STORY003 開場地圖與演員 |
| [first-control.png](first-control.png) | 首次控制：17 名單位、3 名受控角色 |
| [result.png](result.png) | 強制勝利結果頁，顯示「漢克斯加入隊伍」 |

[review_manifest.json](review_manifest.json) 是同次運行的 20 張截圖 manifest；原始完整截圖仍在 ignored capture output。復跑命令：tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=3。

自動驗證：tests/run_winfail_rules_tests.gd、tests/run_battle_sweep_tests.gd（全部 13 個正式戰鬥）、tests/run_story_mode_walkthrough_tests.gd、tests/run_campaign_tests.gd 與 tests/run_story_scene_tests.gd。

## 邊界

- 強制勝利只證明正式場景能開場、結算並交接；不證明 AI、平衡、原版節奏或自然打法。
- static-derived 的 undead getter 只確認 PLAYER_TABLE bit 與已檢查的裝備處理分支；HP 歸零免死、受擊不扣 HP 與傷害免疫為 negative-evidence，仍 provisional。替換證據是有界原生傷害／死亡 probe。
- mode refresh 時機、全域標記、原始 turn queue 調度與完整入隊 handler 尚未定位，均為 provisional；carry 是目前重製的跨關策略。
