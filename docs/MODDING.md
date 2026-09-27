# 基于本仓库做你自己的游戏（Modding）

写给想拿这套代码改出自己游戏的人：换美术和音乐、改数值与规则、写新关卡和剧情，最后不再依赖原版。怎么跑、怎么协作见 [README](../README.md)／[CONTRIBUTING](../CONTRIBUTING.md)；从零加关卡、角色、剧情的逐步表见[加关卡与角色逐步表](MODDING_LEVELS.md)。本页只讲每件事改哪一层、跑什么命令，以及现在哪些做不到。

先把现状说清楚：代码（`game/`、`tools/`、`tests/`）是 MIT，可以随便改；但目前几乎所有画面、声音和数据表都是从你本机的正版《幻世錄》导入的。所以一般的路线是：先带着原版素材做一个自己玩的改版，再一块块换成自己的东西（§7 列了要换哪些）。

## 1. 三分钟看懂结构

| 层 | 目录 | 谁产生 | 公开仓库里有没有 | 改它会怎样 |
| --- | --- | --- | --- | --- |
| 素材（imported） | `content/imported/hsl/` | 导入器从你的正版 `GAME-PAK/`（`hsl.pak`、`music/`）解出：图片、声音、原版文本表（`global/tables/PLAYERS.TXT` 等）、剧本源文本 | 没有，本地导入 | 直接改的话，下次跑那个导入任务会被原版覆盖回去，`hsl check` 也会报和原版不一致 |
| 手写数据（authored） | `content/authored/`、`content/battles/levels/NNN.json`、`content/battles/campaign.json`、`content/world/`、`content/schema/` | 人手写 | 有（只有 `content/authored/actors/` 下的占位 PNG 不在，那是原版帧换色） | 重跑用到它的生成任务，下游跟着变。**你的改动主要放这一层** |
| 生成物（generated） | `content/generated/hsl/`、`content/battles/battle_NNN.json`、`story_NNN.json` | `python3 tools/hsl.py generate …` 从上面两层算出来 | 没有（只保留重制配乐 `remake_music/`、自动对局结果和清单 `original_derived_manifest.json`） | 不要手改：下次生成就覆盖了，`hsl check` 会报出来 |
| 代码（game） | `game/` | 人写 | 有 | 规则只在 `game/sim/`；全游戏共用的 tick 与界面皮肤在 `game/common/`；战斗画面在 `game/battle/`；大地图和城镇在 `game/world/`；标题在 `game/title/`；设置和选项在 `game/settings/` |

```text
你的正版 GAME-PAK/（hsl.pak、music/NN.wav）     手写数据：content/authored/、content/battles/levels/、
            │                                    campaign.json、content/world/
            │  python3 tools/hsl.py generate …              │
            ▼                                               │
  content/imported/hsl/（素材＋原版文本表）                  │
            │  python3 tools/hsl.py generate …  ◄───────────┘
            ▼
  content/generated/hsl/ ＋ content/battles/battle_NNN.json、story_NNN.json（运行时读的表和关卡）
            │  Godot 按 res:// 路径加载
            ▼
  game/sim（规则；战斗里唯一可变的状态在 game/sim/loop/BattlePlayLoop.gd）
  → game/battle（画面与演出）、game/world、game/title、game/settings
```

所有生成和检查任务都登记在一张注册表里：`python3 tools/hsl.py list` 列出全部（任务名、族、输出路径），`python3 tools/hsl.py list '*:51'` 只列第 51 号关卡相关的任务。`generate` 会先跑上游再跑下游。关卡文件号和"玩家第几场"的对照见 [BATTLE_NAMES](BATTLE_NAMES.md)。

## 2. 跑起来

需要 Godot 4.7、Python 3.10+（`python -m pip install -r requirements-dev.txt`），以及你自己的 Steam《幻世錄 重製版》里的 `GAME-PAK/` 目录。

```sh
export HSL_ORIGINAL_DIR=/path/to/GAME-PAK     # Windows/Linux 装了 Steam 版的话可以不设，工具会自己找
python3 tools/hsl.py doctor                   # 检查 Godot、Python 和原版目录，并打印选中了哪个目录、为什么
python3 tools/hsl.py generate original_tables music_import   # 按任务或族导入（示例：原版文本表、配乐）
python3 tools/hsl.py check original_derived_manifest          # 逐文件比对导入结果和清单里记的哈希
tools/play.sh                                 # 先导入 Godot 资源再开游戏；Windows 用 powershell -ExecutionPolicy Bypass -File tools\play.ps1
```

从空仓库一条命令导入全部原版资源的工具还在做（README 也这么写）。现在只能按族分批 `generate`，再用 `check original_derived_manifest` 查还缺哪些文件；进度见 [PROJECT](PROJECT.md)「排队」。

**没有原版的时候**：凡是读写原版派生文件的任务都会报 `SKIP original-absent`，只有文档和纯代码的检查会真正跑出 PASS；`tools/verify.sh` 会跳过 Godot 导入和场景套件。游戏本身开不起来，因为关卡 JSON 和素材都是生成物。注意 SKIP 只是跳过，不等于通过。

## 3. 换素材

有两条路：

- **新建素材（推荐）**：新角色的外观、新地图、新关卡的配乐都放在手写层，导入任务不会碰它们。
- **就地替换导入素材**：把 `content/imported/hsl/` 里的文件原名替换掉。能用，但下次跑对应的导入任务会被覆盖回原版，那个任务的 `hsl check` 也会报不一致。替换之后跑 `python3 tools/hsl.py generate original_derived_manifest`，把清单里的哈希改成你的文件，`check original_derived_manifest` 才不会报错；导入任务本身的检查会继续报"和原版不同"，你的分支得决定是不再跑它还是从门禁里去掉。

画面基准：逻辑分辨率 640×480（`project.godot` 里 viewport 640×480，窗口 1280×960 按 viewport 拉伸）；图片一律用 PNG（RGBA）。原版的 SHP 帧由导入器解成 PNG，每帧附带脚点坐标（manifest 里的 `draw_origin`），**你自己不用写 SHP**。

| 素材 | 原版导入在哪（生成任务） | 自己新建放哪 | 格式要求 |
| --- | --- | --- | --- |
| 人物走行帧 | `content/imported/hsl/chapter01/battleNNN/actor_walk_frames/actor_walk_manifest.json`（每帧的 `png_path` 和脚点 `draw_origin`；`level_actors:N`）、转职／共用的在 `shared/actor_walk_frames/`（`actor_walk_manifest:shared`） | `content/authored/actors/<外观>/walk/<stand\|down\|right\|up\|left>-<n>.png`，外加 `art.json`（`walk.anchor`＝脚点在 PNG 里的像素坐标，`walk.fps`） | 五组帧数必须相同，n 从 1 开始；示范角色 102 是每组 6 张、每张 72×77 |
| 战斗切入（特写） | `content/imported/hsl/chapter01/combat_animation/manifest.json`（`combat_animation`） | `content/authored/actors/<外观>/cutin/<n>.png`；`art.json` 的 `cutin.program_of` 写借用哪个原版角色的打击程序，`cutin.anchor` 写锚点 | n 从 0 开始，张数必须等于被借程序的帧数；`cutin: null` 表示没有特写 |
| 头像 | `content/imported/hsl/chapter01/portraits/NNN.png`＋各关 `portraits/manifest.json`；名册脸表是生成物 `content/generated/hsl/roles/actor_portraits.json`（`roster_portraits`） | `content/authored/actors/<外观>/portrait.png`，由 `content/authored/roles/characters.json` 那一行的 `portrait` 指过去 | 示范图 120×144 |
| 地图 | `content/imported/hsl/chapter01/battleNNN/levelNN.png`（第 51 关 768×768＝24×24 格） | 任意 PNG，写进 `content/authored/levelNNN/level.json` 的 `map_texture` | 尺寸＝格数×32 像素，必须和 `terrain.txt` 的行列数对上 |
| 界面 | `content/imported/hsl/shared/panels/`（面板，`panel_assets`）、`shared/command_menu/`（命令环）、`shared/range_cells/`（范围格）、`shared/game_cursor/`（光标）、`global/title/`（标题、系统菜单、谢幕，`title_assets`）；位图字体表 `content/generated/hsl/fonts/`（`original_bitmap_font`） | 没有手写层入口，只能就地替换 | 保持原文件名和尺寸；版式常量写在对应的导入工具里 |
| 音效 | `content/imported/hsl/shared/interface_audio/manifest.json`（确认、取消等符号对应的 WAV，`interface_audio`）、各关 `sounds/manifest.json` 和 `actor_audio.json` | 新角色用 `art.json` 的 `sounds_of` 借某个原版角色的走、攻、闪、亡音效；自带新音效目前没有入口 | WAV |
| 配乐 | `content/imported/hsl/music/NN.ogg`＋`manifest.json`（`music_import`，NN 是原曲号 02–19） | 大地图和城镇用 `content/world/world_map_scene.json` 的 `map_music`／`town_music`，标题和谢幕用 `global/title/manifest.json` 的 `music`，都是 `res://` 路径，指到你的 OGG 就行；关卡里剧本 `actPlayMusic,N` 固定播 `res://content/imported/hsl/music/NN.ogg` | OGG Vorbis；`project.godot` 的 `[importer_defaults]` 默认整首循环 |

仓库自带 14 首重制配乐 `content/generated/hsl/remake_music/`（CC BY 4.0，由 `tools/compose_*.py` 合成），游戏代码目前没有读它；想用就把上面那些 `res://` 路径指过去。

新放进去的 PNG、OGG 要先让 Godot 导入一次才能被 `load()`：`tools/godot.sh --headless --import`。`tools/play.sh` 会自动做这步；Windows 上生成了新图或新声音后，先设 `$env:HSL_FORCE_IMPORT=1` 再跑一次 `play.ps1`。`hsl generate` 如果发现还没导入的资源，会打印 `HSL_GENERATE_HINT unimported=N`。外观放好之后跑 `python3 tools/hsl.py check authored_art` 检查。截图验看：`tools/godot.sh --script res://tests/capture_authored_art_review.gd`（需要窗口，输出到 `ignored/authored-art-review/`）。

## 4. 改规则

战斗规则全部在 `game/sim/`，可变状态只有 `game/sim/loop/BattlePlayLoop.gd` 一份（同目录 6 个 `BattleLoop*.gd` 是操作它的静态模块）。画面层只负责显示，不算任何规则。规则分两类：一类由数据表驱动，改表就等于改规则；另一类写死在代码里，得改 GDScript。

**表驱动的规则**（改完重跑右边的生成任务）：

| 表 | 管什么 | 重跑 |
| --- | --- | --- |
| `content/imported/hsl/global/tables/PLAYERS.TXT`（原版角色表，**cp950 编码**）／`content/authored/roles/characters.json`（你的角色，同一套字段，UTF-8） | 角色属性、装备、初始技能、AI 参数、开场气力、经验、携带物 | `python3 tools/hsl.py generate role_data ai_profiles entry_growth_data growth_lifecycle_data battle_rewards` |
| `content/authored/roles/job_formulas.json`、`learning_tables.json` | 职业属性公式、各职业学什么 | `python3 tools/hsl.py generate job_formulas growth_lifecycle_data` |
| `global/tables/ITEM.TXT` | 道具与装备数值 | `python3 tools/hsl.py generate equipment_data` |
| `global/tables/MAGIC.TXT`、`SPECIAL.TXT`、`RANGE.TXT`／`content/authored/roles/skills.json`（新招） | 魔法、绝技、施放范围 | `python3 tools/hsl.py generate initial_skill_book skill_target_data authored_effect_scripts` |
| 各关 `winfail` 剧本 | 胜负条件、援军、事件 | 该关的生成链（§5） |

`global/tables/` 下的原版表只要重跑 `original_tables` 导入就会被覆盖。新角色、新职业、新招式请写进 `content/authored/roles/`（[逐步表 §3.2](MODDING_LEVELS.md#32-角色职业与招式) #10–18）；要改原版已有的行，目前只能直接改导入的副本（见本页末"现在做不到的"）。

**例一：改普攻伤害公式。** 位置是 `game/sim/CoreCombatRules.gd` 的 `preview_damage()`：先算攻击力减防御力，加上力量差项（限制在 −20～30），再做三次随机抽取，结果不大于 0 时走保底。命中是同一文件的 `hit_chance()`，暴击是 `critical_impact()`；绝技和魔法的伤害抽取在 `game/sim/NativeMagicRollRules.gd`。随机抽取的次数和顺序变了，同一个种子打出来的结果就会变，旧存档读回来后面的发展也会跟着变。

**例二：改 AI 参数。** 每个角色的 AI 参数写在 PLAYERS 行（或 characters.json 行）里：`find_type`／`find_range`（找谁、多远）、`ai_help_otherhp`（给别人补血的概率，单位 %）、`ai_help_status`、`ai_help_attack`、`ai_lock`、`ai_att_special`、`ai_att_magic`、`ai_call_range`、`ai_fixed`，等等。改完跑 `python3 tools/hsl.py generate ai_profiles`，结果写进 `content/generated/hsl/ai/profiles.json`，运行时由 `AINavigationRules.gd`、`AISupportRules.gd` 等读取（比如 `AISupportRules` 就是拿随机数和 `ai_help_otherhp` 比，决定要不要去治疗队友）。某一关里单个敌人的覆写值在那一关的 seed 里（原版 EVEF 实例）。

**例三：改开场气力。** 角色第一次登场时的气力就是 PLAYERS／characters.json 行里的 `stamina`（取值 0–60，超出范围建局直接失败）。它先进入进度表（第一章是 `content/imported/hsl/chapter01/progression.json`，由 `progression_data` 从 PLAYERS.TXT 抽出；你自己的关由 `authored_level:N` 写进该关的 `progression.json`），再由 `ActorInitializationRules.prepare()` 读取。改数值：改那一行，然后跑 `python3 tools/hsl.py generate progression_data`（原版角色）或 `python3 tools/hsl.py generate authored_level:200`（你的关）。队伍带进下一关时气力清零，除非上一段剧本执行过 `actKeepPlayerST`；这条承接规则写在 `game/sim/CampaignCarryRules.gd` 里，要改只能改代码。

**验证**：

```sh
python3 tools/hsl.py check ai_profiles role_data job_formulas     # 表和生成物一致
HSL_AUTOPLAY_LEVELS=51,200 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd
#   每场打印一行 AUTOPLAY level=… outcome=win|fail|dead_end rounds=N fallen=N；HSL_RNG_SEED=7 换种子
tools/godot.sh --headless --script res://tests/run_all.gd -- run_job_stats_tests.gd   # 只跑指定的 Godot 套件
```

本仓库的门禁里有一批"原版裁判"：`enemy_turn` 等 `probe` 族任务、自动对局结果 `autoplay_results`，以及拿原版回执对拍的 Godot 套件。它们检查的是"和原版一样"，你有意改了规则，它们报不一致是正常的。在你的分支里，可以把这些报告当成"我和原版差在哪"的清单，也可以直接从门禁里移除。

## 5. 加关卡与剧情

**原版关卡是怎么来的**：原版每一关有三份剧本——`STORYNNN.TXT`（开场演出）、`winfailNNN.txt`（胜负与事件）和 PAK 里的 EVEF（出场单位），它们被导入到 `content/imported/hsl/chapter01/battleNNN/source_texts/` 和该关的 seed。之后依次经过 `battle_seed:N`、`opening_timeline_compile:N`、`story_scene:N`、`level_battle:N`，编译成 `content/battles/story_NNN.json` 和 `battle_NNN.json`。关卡档案 `content/battles/levels/NNN.json` 是手写的（标题、结果标签、初始焦点等，见 [LEVEL_PROFILES](architecture/LEVEL_PROFILES.md)）。这条链只能在有原版的情况下跑；原版全部剧本文本可以在 `content/imported/hsl/story_corpus/` 里查。

**你自己的关**：不需要原版剧本，也不用改代码。在 `content/authored/levelNNN/` 写五个文件（`level.json` 地图与单位、`story.txt` 开场、`winfail.txt` 胜负、`messages.json` 对白、`terrain.txt` 地形，剧本沿用原版文法），在 `content/battles/levels/NNN.json` 写关卡档案，再往 `campaign.json` 注册一行；`python3 tools/hsl.py generate authored_level:200` 一条命令组出和原版链同形的 `battle_200.json`。新角色、新职业、新招式也都只写数据。第 200 关「龍脊隘口」和角色 102／103 是完整示范。每一步改哪个文件、跑什么命令、哪些步骤必须有素材或必须改代码（新的 winfail 条件或动作、新的开场演出、新的技能效果族、新的切入打击程序），都在[加关卡与角色逐步表](MODDING_LEVELS.md)里。

## 6. 选项系统

「重製選項」页（任何画面按 Tab 打开）的内容来自注册表 `content/authored/options/remake_options.json`（`hsl_remake_options.v1`）：`options` 是选项卡列表，`page` 是页面版式。

加一张卡的步骤：

1. 在 `options` 里加一个对象。游戏加载时会校验下面这些键（`GameOptions._card_problem`）：`id`（不能重复）、`tier`（`experience` 会出现在设置页，`development` 不会）、`layer`（`rules`／`presentation`／`appearance`）、`values`（`[{id, label, text}]`）、`original_value`、`comfort_value`（这两个必须是 `values` 里某个 id）。其余字段 `name`、`why`、`save_effect`、`changeable`、`read_points`、`evidence` 是给人看的说明，照现有的卡写就行。
2. 在代码里读它：`GameOptions.value("OPT-XXX")` 返回当前取值的 id，`GameOptions.is_original("OPT-XXX")` 在走原版路径时返回 true。例如 `game/battle/scene/BattleGrowthPanel.gd` 里的 `postpone_allowed = not GameOptions.is_original("OPT-GROWTH")`。
3. 如果某个界面只在建好时读一次选项，要让它加入 `remake_options_listeners` 组。选项页关闭且有值被改动时，会调用组内节点的 `remake_options_changed()`。

口径：`original_value` 就是走原版的那条分支（关掉选项时代码必须和原来一字不差），`comfort_value` 是「舒適」预设的取值。取值优先级：卡片的 `original_value` < `campaign.json` 的 `option_defaults` < 玩家的选择；`option_hidden` 可以把某张卡藏起来。续集里没有"原版"可言，「原版」预设按钮会显示成 `page` 里写的「作者默認」。无窗口运行（门禁、自动对局）一律用原版预设，只有设了 `HSL_OPTIONS_PRESET=comfort` 才换。设计原则（一个选项对应一个玩家意图、不做平衡滑杆）见 [OPTIONS](OPTIONS.md)。

## 7. 完全去掉原版依赖

目前没有现成的"空白模板"。要彻底脱离原版，下面几类都得换成你自己的，并且保持相同的路径和 schema（或者去改代码里的路径常量）：

1. **所有导入素材** `content/imported/hsl/`：`shared/`（面板、命令环、范围格、光标、界面音效、技能特效与魔法、走行帧与受击／施法姿势、战利品飘字、物件预览）；`global/title/`（标题、系统菜单、谢幕）；`global/world_map/`（大地图、城镇定义 towndef）；`global/tables/`（原版文本表）；`music/`、`movie/`、`story_corpus/`、`chapter01/`。引擎用写死的路径读 `shared/` 和部分生成表，这些路径集中在 `game/sim/ContentPaths.gd`；面板路径在 `game/common/BattleUISkin.gd`。
2. **由原版表算出的生成物** `content/generated/hsl/`：`skills/`、`roles/`、`ai/`、`combat/`、`equipment/`、`text/`、`fonts/`，以及只能从原版 EXE 导出的 `static/hsl01/`。你换掉源表后重新生成，或者按同样的 schema 自己写。
3. **看起来是手写、其实源自原版的文件**：
   - `content/authored/roles/job_formulas.json`、`learning_tables.json`：80–100 号是第一章的职业，数值由原版回执钉住（`static-derived`）。你自己的行标 `"evidence_tier": "authored"`。
   - `content/authored/roles/roster.json`：里面列的是 PLAYERS.TXT 的角色代号。
   - `content/authored/roles/characters.json`、`skills.json`：数据是新写的，但沿用 PLAYERS／SPECIAL 的字段，并且借用了原版的职业代号、特效物件和 WAV。
   - `content/authored/battles/first_battle_base.json`：原版第一战的手写底稿（含 `resource-derived` 字段）。
   - `content/authored/level200/`：地图借用第 2 关的原版图，表现 manifest 借用 battle500，敌人用的是原版 036。
   - `content/authored/actors/102`、`103` 的 PNG：原版 003／004 号角色的帧换色而来。
   - `content/world/town_initial_trees.json`、`town_job_up_writes.json`（`static-derived`）、`world_map_scene.json`（指向导入的大地图和原曲）。
   - `content/battles/campaign.json`、`content/battles/levels/*.json`：虽然是手写的，但记录的是原版的关卡顺序和标题。
4. **派生物清单与分类**：`content/generated/hsl/original_derived_manifest.json` 记录每个原版派生文件的路径、哈希和生成任务；`tools/hsltools/original_content.py` 的 `classify()` 按目录判定 A 类（原版派生），并用 `PLAYERS.TXT` 是否存在来判断"原版在不在场"。你自己的素材放在 `content/imported|generated|battles/` 下，同样会被当作原版派生，原版不在场时一律 SKIP。所以要么把清单换成你的文件（`python3 tools/hsl.py generate original_derived_manifest`），要么改 `classify()`／`A_DIRECTORIES`，要么去掉这套机制。
5. **原版裁判与证据**：`docs/evidence_packets/`、`probe` 族任务，以及拿原版回执对拍的测试，对一款新游戏都没有意义，可以删掉或者不跑。
6. **NOTICE 与名字**：重写 [NOTICE](../NOTICE.md) 里"不含原版、需自备正版"和权利归属两段，改成你自己游戏的素材来源与许可。保留本项目代码的 MIT 版权声明（MIT 要求保留），用到本仓库文档或重制配乐的话，按 CC BY 4.0 署名。游戏里显示的《幻世錄》名称来自标题 manifest 和 `campaign.json` 的 `title`，要一并换掉。以上不是法律意见。

## 8. 常见坑

- **Windows**：`python tools\hsl.py doctor|check|generate` 不需要 bash；开游戏用 `tools\play.ps1`；PowerShell 会吞掉裸 `--`，传给 Godot 的参数要写在 `++` 后面；直接跑其他 `tools\*.py` 前先设 `$env:PYTHONUTF8=1`。`tools/verify.sh`、`tools/lane_verify.sh` 需要 Git Bash 或 WSL。仓库统一用 LF 换行（`.gitattributes`），不要打开 `core.autocrlf`。详见 [CONTRIBUTING §6](../CONTRIBUTING.md#6-windows-与-linux)。
- **大小写**：原版成员名大小写混用（例如 `Attack01.WAV`）；`res://` 路径在导出包和 Linux 上区分大小写。不要新建只靠大小写区分的文件名，`python3 tools/hsl.py check case_collisions` 会拦下来。
- **编码**：原版表是 cp950（Big5），你写的剧本、JSON 用 UTF-8。
- **Godot 导入缓存**：新图、新声音要先 `tools/godot.sh --headless --import`。缓存在 `.godot/`（已被 Git 忽略），`.import` 文件不要提交（`doctor` 会检查）。
- **别手改生成物**：`content/generated/`、`battle_NNN.json` 都会被下次生成覆盖，要改就改它的源头。
- **引擎代码不写章节路径**：`game/` 里一出现 `chapter01` 这样的目录名，`python3 tools/hsl.py check engine:chapter_paths` 就失败；逐关素材路径要通过场景 JSON 的 `resources` 传进来。
- **新加 `game/**/*.gd` 文件**：文件头要写 `## provenance:` 块，然后跑 `python3 tools/hsl.py generate provenance`，否则门禁失败（格式见 [ARCHITECTURE](ARCHITECTURE.md#provenance-headers)）。
- **只跑相关检查**：`python3 tools/hsl.py affected --since <基线提交>` 列出改动命中的任务，加 `--check` 直接跑；`tools/lane_verify.sh affected <基线提交>` 还会带上命中的 Python 测试和 Godot 套件；也可以只跑一关，例如 `python3 tools/hsl.py check '*:200'`；只改了文档就跑 `python3 tools/hsl.py check docs`。改自己的游戏时用 `python3 tools/hsl.py check --profile=modder` 跑全部"我改的数据能生成、能读"的检查；它跳过原版等价层（parity：探针包、出场顺序、配乐、繁体文案）和我们的证据流程层（maintainer：来源头、差异清单等），并打印一行 `SOURCE_CHECKS_SKIP profile=modder parity=N maintainer=N`——通过不代表仍和原版等价。
- **SKIP 不是 PASS**：原版不在场时，读原版的检查一律显式跳过；看到 `SKIP original-absent` 说明这部分根本没验证。

## 现在做不到的（需要先改代码或工具）

- 从空仓库一条命令导入全部原版资源。
- 用覆盖层改原版已有的行（ITEM.TXT 某件装备、PLAYERS.TXT 某个原版角色）：目前只能直接改导入副本，而这份副本会被 `original_tables` 覆盖，检查也会报不一致。
- 手写层的新音效、新界面美术：两者都没有 authored 入口。
- 关卡配乐用任意路径：剧本 `actPlayMusic` 的路径模板写死在 `tools/hsltools/levels/timeline.py` 的 `MUSIC_STREAM`。
- 规则类选项：存档与锁定的底座（[OPTIONS §9](OPTIONS.md#9-实施计划) B2）还没建，现有卡都是演出／外观类。
- 续集自己的大地图和城镇：数据入口存在，但没有验证过（[逐步表](MODDING_LEVELS.md#33-从标题开始与续集世界) #20）。
