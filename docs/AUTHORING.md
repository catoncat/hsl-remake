# 作者指南：加一關＋加一名角色（Authoring）

面向要為續集寫內容的人。第一章的每條產線都從 `hsl.pak`／EXE 出發；本頁描述**不靠原作資源**的作者路線，用第 200 關「龍脊隘口」與角色 102「蕾雅」、103「托蘭」（tracer，`content/authored/level200/`、`content/authored/roles/characters.json`、`content/authored/actors/`）示範，每一步標明「只寫數據」「必須改代碼」或「必須有原版資源」。跑通標準：`tests/run_authored_level_tests.gd`（夾具戰役 start_level=200 時 開始新故事 → 第 200 關；標題 戰場記錄 → 第 200 關 → 開場對白 → 機器人打到自然勝負 → 結果頁 → 謝幕；102／103 用自己文件夾的走行幀、切入、臉與稱號）。

## 一、文件在哪裡

```text
content/authored/level200/
  level.json      地圖圖片、配樂、表現 manifest 來源（走行幀／音效／肖像／切入，可選 sprite_aliases）、單位（id／PLAYERS 代號／腳本代號／陣營／起始格）、winfail 會插入的物件代號
  story.txt       開場劇情，原作 STORY 文法
  winfail.txt     勝負與事件，原作 winfail 文法
  messages.json   兩個腳本用到的全部訊息編號 → 文字，以及說話者代號 → 顯示名
  terrain.txt     地形，每行一列、每字一格（# 不可通行，. 平地，1–9 高度）
content/battles/levels/200.json   關卡檔案 battle 分區：id／title／initial_focus_unit_id／initial_objective_phase／result_labels（同第一章，見 architecture/LEVEL_PROFILES.md）
content/authored/roles/characters.json   續集角色表（PLAYERS.TXT 欄位詞彙），code 不與原表重複
content/authored/roles/{job_formulas,learning_tables,roster}.json   新職業的公式與學習表、名冊
content/authored/roles/skills.json       續集招式表（SPECIAL.TXT／MAGIC.TXT 欄位詞彙＋表現腳本），code 以 authored 開頭
content/authored/actors/<外觀>/   一名角色的一套外觀（文件夾名＝外觀 id，預設＝角色代號）：
  art.json        hsl_authored_actor_art.v1：walk.anchor（腳點在每張走行 PNG 內的像素）、walk.fps、
                  cutin（null＝無切入，或 program_of＝沿用哪一 PLAYERS 行的 ANIMAL 打擊程序＋anchor＝每張切入 PNG 內站在切入舞台錨點上的像素）、
                  sounds_of（null 或借哪一行的走／攻／閃／亡音效）
  walk/<stand|down|right|up|left>-<n>.png   走行幀，n 從 1 起、五組張數相同
  cutin/<n>.png   切入幀，n 從 0 起，張數＝program_of 那一行的幀數（程序的 aniSetShape 編號指這些幀）
  portrait.png    臉（characters.json portrait 指向它）
content/battles/campaign.json     註冊一行 "200": {scenario, title}
```

生成：`python3 tools/hsl.py generate authored_level:200`（角色、職業或招式表改了先跑 `hsl generate job_formulas role_data initial_skill_book skill_target_data authored_effect_scripts growth_lifecycle_data ai_profiles entry_growth_data battle_rewards combat_aftermath_data roster_portraits`），產物：

```text
content/generated/hsl/authored/battle200_seed.json            hsl_battle_seed.v1（evidence_tier authored）
content/generated/hsl/authored/level200_terrain.json          hsl_wrd_terrain.v2
content/generated/hsl/authored/battle200/opening_timeline.json  同第一章的 timeline 編譯器
content/generated/hsl/authored/battle200/message_text_evidence.json
content/generated/hsl/authored/battle200/progression.json
content/generated/hsl/authored/battle200/{actor_walk_manifest,actor_audio,portraits,combat_animation}.json
content/battles/battle_200.json                               hsl_level_battle.v1
```

角色表或外觀改了另跑 `hsl generate actor_panels`（身份欄稱號／種族表）。新放的 PNG（走行幀、切入、肖像、地圖）要先跑一次 `tools/godot.sh --headless --import` 才能被遊戲 `load()`（`hsl generate` 看到未導入的資源會印 `HSL_GENERATE_HINT unimported=N`）。檢查：`hsl check authored_level:200 authored_art actor_panels level_profile:200 battle_schema unit_schema campaign_overview autoplay_results`（快門 `tools/verify.sh` 全包）。註冊後 `run_battle_sweep_tests`／`run_autoplay_sweep_tests` 自動覆蓋該關；後者的 `results.json` 需補一行（跑 `HSL_AUTOPLAY_LEVELS=200` 取結果，或跑全量重生成）。

## 二、作者路徑逐步表

| # | 步驟 | 路徑 | 怎麼做／阻塞在哪 |
| --- | --- | --- | --- |
| 1 | 關卡骨架（標題、結果標籤、焦點、目標階段） | 只寫數據 | `content/battles/levels/200.json` battle 分區 |
| 2 | 地形（格、阻擋、高度） | 只寫數據 | `terrain.txt` ASCII；生成器算 stats 與 `hsl_wrd_terrain.v2`。地形沒有 tile id（原作 WRD 的 t 值運行時不讀） |
| 3 | 地圖圖片 | **必須有素材**（美術） | `level.json` `map_texture` 指任一 PNG，尺寸 = 格數 × 32；tracer 借第 2 關的原作圖。新圖只是換路徑，但畫不出來 |
| 4 | 佔位與陣營 | 只寫數據 | `level.json` `units[]`：id、actor（PLAYERS／characters 代號）、token（腳本用 SID_…）、role、cell。同 token 的多個單位依序為 serial 1、2、3… |
| 5 | 開場劇情（音樂、延遲、走位、對白、亡語、狀態上膛） | 只寫數據 | `story.txt`，原文法；`hsltools.sources.scripts.parse_text_metadata` 解析（本輪加了 utf-8 參數），`hsltools.levels.timeline` 編譯；走位終點由 `hsltools.levels.battle.trace_opening` 算成 `coord`。可用的 token 見 `timeline.py ACTION_KIND`／`EXTENDED_TOKENS`（沒有分支的 kind 只記錄不演） |
| 6 | 勝負條件與事件（清場勝、主角死敗、第 N 回合援軍） | 只寫數據 | `winfail.txt`；解釋器 `WinfailScenarioRules`（`WinfailCompiler`／`WinfailConditions`／`WinfailActions`）支援 19 條件／47 動作，詞表與每個 token 的語義見 [WINFAIL_TOKENS](WINFAIL_TOKENS.md)；插入的物件代號在 `level.json` `objects` 給 actor／token |
| 7 | 對白文字與說話者名 | 只寫數據 | `messages.json`；缺編號或缺說話者名生成即失敗。原作用 RESOURCE.TXT 編號做說話者 id，授權關直接用 token 當 id（`opening.speaker_resource_ids`） |
| 8 | 下一關／結局 | 只寫數據 | winfail `actSetNextPlayLevelEvent,200,<下一關 key>`；`998` = 謝幕。第 200 關直接進謝幕（本輪補了 `CampaignProgress` 從**戰鬥**結果頁進 GameClear——第一章只從劇情場景 82 進） |
| 9 | 註冊 | 只寫數據 | `campaign.json` 一行；`campaign_overview`／`autoplay_results` 生成物隨之更新 |
| 10 | 新角色（屬性、裝備、絕技聲明、AI 參數、成長） | 只寫數據 | `characters.json` 一行（PLAYERS 欄位；`name_text`、`portrait`、`allocation` 為授權表專有）＋ `roster.json` 加 code。七張全域表（role／skill book／growth_lifecycle／ai／entry_growth／rewards／aftermath）由合併讀取 `character_rows()` 自動長出該行（`hsl generate role_data …`） |
| 11 | 新職業 | 只寫數據 | `job_formulas.json` `jobs["101"]`＋`"symbol": "jobDragonLord"`：TYPE.H 之外的代號由行內 `symbol` 自己起名（`hsltools.model.jobs.authored_job_symbols`；不得與 TYPE.H 重名／重號），角色行 `job = jobDragonLord`；80–100 仍用 TYPE.H 的名字（100 `jobDarkAngel` 原作有代號無公式）。原表只是第一章職業的來源之一。＋ `learning_tables.json` `jobs["101"]` |
| 12 | 新絕技（角色初始就會） | 只寫數據 | `characters.json` `special_wind = 天雷猛襲劍` 等：SPECIAL.TXT 已有且 `skill_book.REGISTRY` 已支援的招，或授權招式表的招名（寫在該招元素的聲明欄：`special_fire = 龍炎斬`、`magic_fire = 龍息`；寫錯欄生成即失敗）；學習表 `learning_tables.json` 也可引用授權 id |
| 13 | **全新**絕技／魔法（新名字、新數值、新表現腳本） | 只寫數據（效果族限已有公式） | `content/authored/roles/skills.json` 一行（欄位見下表）→ `hsl generate initial_skill_book skill_target_data authored_effect_scripts`：`initial_book.json` 長出該招（id `special:magicFIRE:authoredDragonFlame`），`targeting.json` 長出它點名而原表未用的 RANGE 行，`authored_effect_scripts.json` 長出表現行（`SkillEffectScriptPlayer` 與原表行同路播放）。tracer：102 的 龍炎斬（絕技）與只加數據的第二招 龍息（魔法）。**新效果族**（治療、狀態、增益……）與**新 opcode** 不是數據：生成器拒絕並說明，屬運行時決定 |
| 14 | 角色走行幀／音效／對白肖像 | 只寫數據（新圖需**素材**） | 新圖：`content/authored/actors/<代號>/` 放 `art.json`＋`walk/*.png`＋`portrait.png`（約定見第一節），`characters.json` `portrait` 指該 PNG；`authored_level:N`（`hsltools.assets.authored_art`）產出與導入鏈同形的走行條目（`hsl_actor_walk_manifest.v1`）與音效行（`sounds_of` 借某行的音效）。借用：`presentation.sprite_aliases {"<代號>": "<外觀 id 或 PLAYERS 行>"}`——也用來給一名角色換第二套外觀。作者角色既沒有文件夾也沒有 alias 時生成即失敗（不落到同號導入行）。證明：102 的 30 幀／臉來自 `actors/102/`（佔位：003 換色）；**零代碼**加入的 103（那一提交只動 characters.json／roster.json／level.json／`actors/103/` 與測試斷言，`game/`、`tools/` 零改動）同樣上場 |
| 15 | 角色切入（戰鬥動畫） | 只寫數據（新圖需**素材**） | 切入表由場景 `resources.combat_animation` 給（`BattleCombatCutin.configure`）；作者關的表 `battleNNN/combat_animation.json` 由生成器從 `level.json presentation.combat_animation`（源表：背景、開場球、政策）＋上場各行組成：作者外觀行＝`cutin/<n>.png` 的幀＋`program_of` 行的打擊程序（timeline／dispatch／hurt_frame／flash／朝向），導入行原樣。`cutin: null` 或無導入切入的行走「無美術」片段。s_shape／m_shape 條帶不在約定內（絕技切入顯示站立施法者）。證明：`run_authored_level_tests` 讓 蕾雅／托蘭 的切入片段在開場球後畫自己的 `cutin/` 幀；截圖 `tools/godot.sh --script res://tests/capture_authored_art_review.gd`（需窗口，輸出 `ignored/authored-art-review/`：地圖上兩人的走行幀、各一張切入） |
| 16 | 名冊臉表（狀態面板取臉） | 只寫數據 | `characters.json` `portrait`；本輪把 `ContentPaths.ACTOR_PORTRAITS` 改指生成的合併表 `content/generated/hsl/roles/actor_portraits.json` |
| 17 | 職業稱號顯示、行走特徵（飛行／穿牆／體型） | 只寫數據 | PLAYERS 欄位 `move_fly`／`no_block`／`size_type`；稱號文字由 `job_show_name`（RESOURCE 編號）——授權角色用 `name_text` |
| 18 | 城鎮／大地圖點位（續集世界） | 只寫數據，未驗證 | `world_map.json`／`towndef.json` 是導入表，`town_initial_trees.json` 手寫；本 tracer 未碰 |
| 19 | 從標題直接開始續集 | 只寫數據 | `campaign.json` `start_level` 改成續集第一關的 key：`開始新故事` 不裝交接，運行時 `scenario_path` 為空時解析 `CampaignProgress.first_scenario_path`（直接啟動 `BattleSceneRuntime.tscn`、戰役重新開始同此）；片頭動畫是 `start_movie`（第一章 `"start"`＝start.ani；不寫則直接進首關）。證明：`run_authored_level_tests` 用夾具戰役（start_level 200、無 start_movie）開始新故事 → 無片頭 → 第 200 關；第一章仍 51＋start.ani（`run_title_screen_tests`） |
| 20 | 身份欄稱號／種族（切入、懸停、目標預覽、道具面板） | 只寫數據 | `characters.json` 的 `job`／`class` 經 TYPE.H→RESOURCE 得稱號與種族，`hsl generate actor_panels` 寫進 `content/generated/hsl/roles/actor_panels.json`（導入面板行原樣＋作者行），`UISkin.data()` 的 actors 取它。原本只有 PLAYERS 行，作者角色一上切入身份欄就崩 |

### 授權招式表欄位（`content/authored/roles/skills.json`）

每行一招；欄位名與值都照原表（字串或數字）。`tools/hsltools/data/authored_skills.py` 逐欄校驗，並用與運行時同一道描述符門（`skill_coverage._descriptor_judgment`）核過才寫進技能書。

| 欄位 | 絕技 `special` | 魔法 `magic` | 值 |
| --- | --- | --- | --- |
| `channel` | ✓ | ✓ | `special`（SPECIAL.TXT 形，耗 ST＝`expend`×20）或 `magic`（MAGIC.TXT 形，耗 MP＝`expend`） |
| `code` | ✓ | ✓ | `authored` 開頭的識別字，表內唯一；招式 id＝`channel:type:code` |
| `name_text` | ✓ | ✓ | 顯示名，表內唯一，不得與 mag-spc.h 的招式別名同名；角色聲明欄寫的就是它 |
| `type` | ✓ | ✓ | 元素：`magicEARTH／magicWATER／magicAIR／magicFIRE／magicMIND／magicOTHER`（決定抗性槽與角色聲明欄 `special_*`／`magic_*`；`magicOTHER` 不讀抗性） |
| `range`／`effect_range` | ✓ | ✓ | RANGE.TXT 的形狀名（施放距離／作用範圍），例 `range2Cell`、`range4CellThrust`、`range3CellDir`（直線） |
| `expend` | ✓ | ✓ | 0–999 |
| `damage` | ✓ | ✓ | `"低,高"`，0 ≤ 低 ≤ 高 ≤ 10000，原生三角分佈抽樣 |
| `hit_ratio`／`use_ratio` | ✓ | ✓ | 0–100（命中；AI 使用率） |
| `function` | ✓ | ✓ | 目前只收 `magicFun_Attack`：絕技走原生絕技傷害（0x40a7b0 channel1：＋等級抽樣＋con/8＋mind/4＋dex/3，×`attackpow_ratio`），魔法走原生魔法傷害（channel0：等級＋mind＋抽樣，×魔攻） |
| `attackpow_ratio` | ✓ | — | 0–1000（％） |
| `attack_code`／`defense_code` | ✓ | — | 切入的施法段／受擊段：EFFECTS.TXT 的 specCode（例 `specCode31`）或本表 `scripts` 的 `authored…` 段（只能用 ani* opcode） |
| `effect_proc`／`effect_code` | — | ✓ | `eff_proc_Local`（每個受影響格播一次）或 `eff_proc_Global`（畫面中心一次）；effCode 段或 `scripts` 的 `authored…` 段（只能用 eff* opcode） |

`scripts`：`{"authoredXxx": ["effInsertObject,obj_Effect_FireBomb2,0,0,effWait,50", …]}`，每行即 EFFECTS.TXT 的一條 `action =`；verb 必須在 `SkillEffectScriptPlayer.IMPLEMENTED_OPCODES`，物件／WAV／SHP 必須是 `skill_effects` 已導入的（新美術屬 #14，新 opcode 屬運行時決定）。

## 三、最小文件原文

`content/authored/level200/story.txt`（節錄）：

```ini
[story]
action = actPlayLevelMusic
action = actDelay,20
action = actWalkWait,SID_雷歐納德,1,224,256,4
action = actMessage,SID_雷歐納德,1,1001
action = actMessage,SID_蕾雅,1,1002
action = actSetDeadMessage,SID_雷歐納德,1,1004,0
action = actInsertWinStatus,0
action = actInsertFailStatus,0
action = actInsertEventStatus,0
action = actShowWinFailStatus
```

`winfail.txt`（節錄）：

```ini
[win]
code = 0
message = -1,1101
action = actCheckEnemyTotalNumber,0
action = actMessage,SID_雷歐納德,1,1102
action = actSetNextPlayLevelEvent,200,998

[fail]
code = 0
message = SID_雷歐納德,1103
action = actCheckPlayer,1,SID_雷歐納德

[event]
code = 0
message = -1,1104
action = actCheckRoundNumber,3
action = actInsertObject,obj_Level200_Wolf,608,256
action = actWalkPrevInsertObject,512,288,4
```

`level.json` 的單位行與物件行：

```json
{"id": "reia", "actor": "102", "token": "SID_蕾雅", "role": "player_controlled", "cell": [8, 9]}
"objects": {"obj_Level200_Wolf": {"actor": "036", "token": "SID_ENEMY036"}}
```

`skills.json` 的第二招（只加數據）：

```json
"scripts": {"authoredDragonBreath": ["effPlaySound,WAV\\FIRE0006.WAV", "effInsertObject,obj_Effect_FireRoundFire,0,0,effWait,30", "effInsertRandomObject,obj_Effect_FireFire,0,8,48,16,10,6", "effWait,40", "effInsertObject,obj_Effect_FireBomb2,0,0,effWait,50", "effWait,30"]},
{"channel": "magic", "code": "authoredDragonBreath", "name_text": "龍息", "type": "magicFIRE", "range": "range4CellThrust", "effect_range": "range1Cell", "expend": "10", "damage": "30,48", "hit_ratio": "94", "function": "magicFun_Attack", "use_ratio": "90", "effect_proc": "eff_proc_Local", "effect_code": "authoredDragonBreath"}
```

`job_formulas.json` 的授權職業只多一個 `"symbol": "jobDragonLord"`（其餘欄位同 `jobs["100"]`）；角色行 `"job": "jobDragonLord"`。

`characters.json` 一行的必填：`code name_text job mode str dex mind con move_point`；其餘同 PLAYERS（裝備槽 `*_equip`、`special_*`／`magic_*` 聲明、`find_*`／`ai_*`、`level`／`exp`／`kill_exp`、`item1..8`、`resist_*`），加 `portrait`（res:// PNG）與 `allocation: manual`。

## 四、引擎為此改了什麼（分類）

| 改動 | 分類 | 說明 |
| --- | --- | --- |
| `hsltools/levels/authored.py`（新任務族 `authored_level:N`） | 通用能力 | 作者格式 → 與導入鏈同形的生成物；復用 timeline 編譯器、`trace_opening`、`script_templates`、`status_timelines` |
| `hsltools/sources/tables.py character_rows()`＋七個生成器改讀它；`native/sources.py`；`first_battle_formation.actor_templates` 補授權行 | 本該是數據 | PLAYERS.TXT 之外的角色來源；原表哈希不動 |
| `model/jobs.py source_profile`：授權行自帶 `allocation`、不掛證據包 | 本該是數據 | 「1–9 號＝手動分配」是原表的巧合，不是規則 |
| `data/ai_profiles.py`：授權行 sid＝自身代號 | 本該是數據 | SHAPEDEF 給每個 SID_ENEMYnnn 的數就是 nnn |
| `data/roster_portraits.py`＋`ContentPaths.ACTOR_PORTRAITS` 改指生成表 | 本該是數據 | 名冊臉表原是第一章導入檔的路徑常量 |
| `levels/timeline.py compile_documents`＋接受 `resolved_from_authored_messages` | 通用能力 | 編譯器不再只認磁碟上的 RESOURCE 證據 |
| `hsltools.sources.scripts.parse_text_metadata(encoding=)` | 通用能力 | 授權腳本是 UTF-8 |
| `legacy.py authored_levels()`／`battle.registered_levels()` 排除 | 通用能力 | 兩個任務不能擁有同一個 `battle_NNN.json` |
| `CampaignProgress.start_next_battle` 進 GameClear | 通用能力 | 戰鬥直接結束全章；第一章只有劇情場景這麼做 |
| `model/jobs.py authored_job_symbols`＋`native/sources.py`／`ai_profiles.py`／`job_formulas.py` 合併讀取 | 本該是數據 | 職業代號的名字原只來自 TYPE.H；授權行自帶 `symbol`，TYPE.H 不改 |
| `data/authored_skills.py`（招式表校驗、技能書行、新任務 `authored_effect_scripts`）＋`skill_book.py`／`growth_lifecycle.py` 接授權行 | 通用能力 | 招式 id 不再綁 SPECIAL.TXT／MAGIC.TXT 行；效果仍是既有原生公式與既有 opcode 的組合 |
| `special_effect_scripts.py` 跳過授權行 | 通用能力 | 第一章清單（`skill_effects` 導入以其 sha 為範圍）不因續集招式改變 |
| `SkillEffectScriptPlayer.gd` 並讀 `authored_effect_scripts.json`、`presentation()` 讀行內聲明 | 通用能力 | 導入的 manifest 只有原表行；唯一的運行時改動 |
| `BattleCombatCutin.configure(resources.combat_animation)`；`first_battle.json`＋10 個演練夾具補同一條聲明 | 本該是數據 | 切入表原是寫死的第一章路徑 |
| `hsltools/assets/authored_art.py`（`content/authored/actors/` 約定、檢查任務 `authored_art`）＋ `authored.py` 的 `build_combat_manifest`／外觀查找 | 通用能力 | 新美術＝PNG 文件夾，不寫 manifest |
| `hsltools/data/actor_panels.py`＋`ContentPaths.ACTOR_PANELS`＋`UISkin.data()` | 本該是數據 | 面板稱號表原是第一章導入檔 |
| `BattleSceneRuntime.scenario_path` 缺省為空→戰役 start_level；`TitleScreen` 片頭讀 `start_movie`；`CampaignProgress.campaign_path`（測試指夾具戰役） | 本該是數據 | 首關原是運行時常量 battle_051 |

不動的：規則語義、第一章 137 場生成物（逐字節不變）、既有斷言（`run_authored_level_tests` 的單位數 6→7 因加了 103）。

## 五、邊界

- `authored` 標記：seed／battle JSON `status`／`provenance`／`view`／全部單位（不帶證據台帳，`UnitSchema.evidence_tier` 回 `authored`）。角色 102 的數值由公式表算出，也標 authored（`profiles.json` 該行無 `evidence`）。
- 借用第一章素材（第 2 關地圖、036 的模板）與 102／103 的佔位外觀（003／004 的幀與臉換色，`content/authored/actors/*/art.json` note 註明）是通路驗證，不是續集美術方案；素材側剩下的是「畫出來」本身。
- 作者關的切入表只含上場各行：一名轉職過的第一章角色在作者關的切入仍用基礎行（走行幀走共享的轉職表）；切入 s_shape／m_shape 條帶與新打擊程序（不借 `program_of`）不在約定內。
- 平衡由作者負責：機器人 4 回合勝只說明鏈路通，不是難度證據。
- 授權招式的效果族只有兩個通道的原生傷害（`magicFun_Attack`）：治療、狀態、增益、特殊行動等要等運行時決定哪些原生分支可以由數據驅動（`authored_skills.DAMAGE_POLICIES`），新 opcode 同理。數值與表現標 authored（技能書行 `evidence_tier`）；傷害公式本身仍是第一章的 static-derived 原生公式。
- 102 沒有切入美術（#15），她的絕技走「缺美術」路徑只顯示結果數字；魔法在地圖上播放，不需要切入美術。
- 授權職業的裝備限制沿用 `items.json` 的 `job_mask` 位（位＝代號−80）：101 讀的是原表第 21 位；112 以上沒有位，任何裝備都不能換上。這是原表遮罩的延伸讀法，續集若要自訂職業可裝備表需另加數據。
