# 基于本仓库做你自己的游戏（Modding）

写给想拿这套代码改出自己游戏的人：换美术和音乐、改数值与规则、写新关卡和剧情，最后不再依赖原版。怎么跑、怎么协作见 [README](../README.md)／[CONTRIBUTING](../CONTRIBUTING.md)；从零加关卡、角色、剧情的逐步表见[加关卡与角色逐步表](MODDING_LEVELS.md)。本页只讲每件事改哪一层、跑什么命令，以及现在哪些做不到。

先把现状说清楚：代码（`game/`、`tools/`、`tests/`）是 MIT，可以随便改；但目前几乎所有画面、声音和数据表都是从你本机的正版《幻世錄》导入的。所以一般的路线是：先带着原版素材做一个自己玩的改版，再一块块换成自己的东西（§7 列了要换哪些）。

## 1. 三分钟看懂结构

| 层 | 目录 | 谁产生 | 公开仓库里有没有 | 改它会怎样 |
| --- | --- | --- | --- | --- |
| 素材（imported） | `content/imported/hsl/` | 导入器从你的正版 `GAME-PAK/`（`hsl.pak`、`music/`）解出：图片、声音、原版文本表（`global/tables/PLAYERS.TXT` 等）、剧本源文本 | 没有，本地导入 | 直接改的话，下次跑那个导入任务会被原版覆盖回去，`hsl check` 也会报和原版不一致 |
| 手写数据（authored） | `content/authored/`、`content/battles/levels/NNN.json`、`content/battles/campaign.json`、`content/world/`、`content/schema/` | 人手写 | 有（只有示范角色 102／103 的 PNG 不在：那是原版帧换色，bootstrap 的 `demo_actor_art` 任务在本地生成） | 重跑用到它的生成任务，下游跟着变。**你的改动主要放这一层** |
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

需要 Godot 4.7+、Python 3.10+，以及你自己的 Steam《幻世錄 重製版》里的 `GAME-PAK/` 目录。Python 依赖装进虚拟环境：`python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt`（Homebrew、Debian 等的系统 Python 不允许全局安装；`tools/doctor.sh` 会用激活的虚拟环境）。从压缩包解出、没有 `.git` 的目录也能玩和改，`doctor` 对此只报 WARN；`hsl affected` 和 `tools/lane_verify.sh` 要先 `git init` 并提交一次。

```sh
export HSL_ORIGINAL_DIR=/path/to/GAME-PAK     # Windows/Linux 装了 Steam 版的话可以不设，工具会自己找
python3 tools/hsl.py doctor                   # 检查 Godot、Python 和原版目录，并打印选中了哪个目录、为什么
python3 tools/hsl.py bootstrap                # 生成全部原版派生文件：缺什么补什么，已有的不动，中断了重跑接着做
python3 tools/hsl.py check original_derived_manifest          # 逐文件比对导入结果和清单里记的哈希
tools/play.sh                                 # 没导入过会先跑 bootstrap，再导入 Godot 资源、开游戏；Windows 用 powershell -ExecutionPolicy Bypass -File tools\play.ps1
```

`bootstrap` 以原版派生文件清单（`content/generated/hsl/original_derived_manifest.json`，每个文件记着由哪个任务生成）为准：有文件缺席的任务按先上游后下游的顺序生成，文件齐全的任务跳过；`--dry-run` 只数不写。最后一行是 `HSL_BOOTSTRAP_PASS|FAIL generated=… skipped=… original_missing=… no_generator=… failed=… differ=…`。`original_missing` 是要用到 Steam 版不带的东西（原版程序 `hsl01.exe`、原版录像或存档）的任务，`no_generator` 是只有检查器、或输入来自仓库外工具的证据文件，这两类只列出、不算失败；`differ` 是生成出来但和清单哈希不一致的任务（原版字库 `original_bitmap_font` 按导入后内容里实际用到的字排版：改过文字就会不同，公开检出里少了几份没有生成途径的证据文本，字集也会差几个字；不影响游戏）；`failed` 非零时 `tools/play.sh` 下次启动会再补一次。末尾的 `missing_files` 是 `original_missing`／`no_generator` 那些任务仍缺的文件数，`unowned` 是清单里不归任何任务、只随维护者导入刷新的文件数，`rounds`／`seconds` 是轮数和耗时；这几项和上面每个没生成的任务那一行 `[bootstrap no_generator|original_missing] 任务名: 原因`（比如 `title_assets` 那一行写着等 `gameplay_reference`：它的检查要求一张原版录像帧存在，公开仓库不带、也没有生成途径；图本身已经生成——`content/imported/hsl/global/title/` 下清单记的 40 个文件齐全、哈希一致）都只说明缺了什么证据，不影响游戏；只有 `failed` 的任务附输出末几行。之后 `doctor` 会对第一章机制夹具 `first_battle.json` 引用的 `chapter01/message_text_evidence.json` 报 WARN，同样不影响游戏。只想重做某一族，照旧 `python3 tools/hsl.py generate <任务或族>`。

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
| 界面 | `content/imported/hsl/shared/panels/`（面板，`panel_assets`）、`shared/shape_previews/battle_ui/`（面板底板、按钮、目标框）、`shared/command_menu/`（命令环）、`shared/range_cells/`（范围格）、`shared/game_cursor/`（光标）、`global/title/`（标题、系统菜单、谢幕，`title_assets`）；位图字体表 `content/generated/hsl/fonts/`（`original_bitmap_font`） | `content/authored/ui/` 下照 `content/imported/hsl/` 的相对路径放同名 PNG（如 `content/authored/ui/shared/panels/WINDOW21.png`），所有战役都换；只给某个战役换，放在它 `campaign.json` 同目录的 `ui/` 下，同一张图战役的优先；这只对 `content/authored/` 下的战役有效，第一章的 `campaign.json` 在 `content/battles/`，只读 `content/authored/ui/`。标题画面在进入战役之前就建好了，所以标题画面的图要放 `content/authored/ui/global/title/`，战役 `ui/` 里的 `global/title/` 只换进入该战役之后才出现的系统菜单和谢幕。没放的照旧读原版，第一章不放就和原版一样。示范：续集示范的 `content/authored/world/ui/shared/range_cells/range_border_move.png` 换了移动范围边框。位图字体没有手写层入口 | 保持原文件名和尺寸（版式、点击范围、帧切片都照原版 manifest）；版式常量写在对应的导入工具里。这两处目录会随仓库公开，只放自己画的图，和原版图同哈希的同步时会被拦下 |
| 音效 | `content/imported/hsl/shared/interface_audio/manifest.json`（确认、取消等符号对应的 WAV，`interface_audio`）、各关 `sounds/manifest.json` 和 `actor_audio.json` | 新角色的音效写在 `art.json`：`sounds_of` 借某个原版角色的走、攻、闪、亡音效；`sounds`（如 `{"attack": "sounds/attack.wav"}`）给其中几项换成外观文件夹里自己的文件，没写的照旧借 `sounds_of`。`sounds/` 和 `content/authored/music/` 里只放自己做的声音，这两个目录会随仓库一起公开。示范 103 的攻击音效是 `content/authored/actors/103/sounds/attack.wav` | PCM WAV（原版多为 11025／22050 Hz 单声道） |
| 配乐 | `content/imported/hsl/music/NN.ogg`＋`manifest.json`（`music_import`，NN 是原曲号 02–19） | 大地图和城镇用 `content/world/world_map_scene.json` 的 `map_music`／`town_music`，标题和谢幕用 `global/title/manifest.json` 的 `music`，都是 `res://` 路径，指到你的 OGG 就行；关卡里剧本 `actPlayMusic,N`：N 为 0–99 播原曲 `content/imported/hsl/music/NN.ogg`（原曲只有 02–19，写别的号不会播新曲），N 为 100 起播 `content/authored/music/N.ogg`（文件缺失时生成失败）。示范第 200 关开场写 `actPlayMusic,100`，播 `content/authored/music/100.ogg` | OGG Vorbis；`project.godot` 的 `[importer_defaults]` 默认整首循环 |

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

`global/tables/` 下的原版表只要重跑 `original_tables` 导入就会被覆盖。新角色、新职业、新招式请写进 `content/authored/roles/`（[逐步表 §3.2](MODDING_LEVELS.md#32-角色职业与招式) #10–18）；要改原版已有的行，写覆盖层，别动导入的副本。

**覆盖层**：`content/authored/overrides/PLAYERS.json` 改 PLAYERS.TXT 的行，`content/authored/overrides/ITEM.json` 改 ITEM.TXT 的行。只写要改的字段，行键是那一行的 `code`，字段名和取值照原表（整数可以写成 JSON 数字）：

```json
{
  "schema": "hsl_table_override.v1",
  "rows": {
    "1": {"attack_damage": 40, "cost": 500},
    "241": {"add_hp": 80}
  }
}
```

生成器读这两张表时都经过同一个入口 `tools/hsltools/sources/tables.py` 的 `table_rows()`，覆盖层在那里叠到导入的行上，导入副本本身不改、哈希不变。同一行会流进好几份生成物，上表「重跑」一列不够用：上例 1 号的 `cost` 是商店价，经 `town_assets` 进游戏；241 号的 `add_hp` 是回复量，经 `consumables` 进游戏；装备数值还会进角色模板和各关的战斗文件。所以改完先跑 `python3 tools/hsl.py check --profile=modder`，报不一致的就是要重跑的任务，再对它们跑 `python3 tools/hsl.py generate <任务名…>`。写了不支持的表、表里没有的 `code`、表里没有的列名，或者想改 `code` 本身，生成直接失败，报错里写着文件、行键和字段。目前只支持这两张表：MAGIC.TXT、SPECIAL.TXT、RANGE.TXT、TYPE.H 等其余原版表还不能覆盖；PLAYERS.TXT 在 PAK 里的原件（城镇对话按名字找说话人头像）、各角色 `source_record` 记下的原表行号，也都照旧读原版。原版对拍探针（`probe` 族）有意不叠覆盖层，照旧拿导入副本和原版回执对拍；拿生成物去比原版的检查（`role_profiles_proof` 这类 parity 检查、生成物哈希清单 `original_derived_manifest`）在有覆盖层时会报不一致，`--profile=modder` 本来就跳过它们；拿原版回执对拍的 Godot 套件不归 `hsl check` 管，由 Godot 测试运行器另跑。

**覆盖层的已知限制**：

- 025（法蘭克）的模板 `emperor_data` 会拿刷新出的数值去比原版探针包：改 PLAYERS 025，或它身上 ITEM 5／126／182 的数值，生成和检查都会失败。
- 039 的模板 `large_actor_data` 的血量、攻防等战斗数值直接取自原版探针包，覆盖层对它不生效。
- PLAYERS 1 的 `special_other`、PLAYERS 26 的 `magic_wind`／`magic_fire` 在读表处被断言成原版招式名（`initial_skill_book` 和 `special_damage`／`magic_damage` 探针都经过这里），改了生成失败。
- PLAYERS 的 `carry_item` 用到的掉落表号必须正好是原版用到的那一组：换成原版没用过的号，或让某张表不再有人用，`battle_rewards` 报错。
- ITEM 241／246 的 `icon` 被 `item_art` 断言成原版值；武器的 `icon` 还决定 `interface_audio` 记下的命中音，改了它的检查不过，重新生成要原版 PAK。
- 生成物里记的 `source_sha256` 和 `evidence_tier` 在有覆盖层时仍写导入原表的值。

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
   - `content/authored/world/`：续集世界示范。点位、路线、城镇事件和文字是新写的；地图图面 bigmap、点位标记 m_pnt001–003、路线图 m_trk001 和原版第 1 条路线的折线、城镇背景 townbg_01、状态栏 status_bar、头像 FACE0073／0062（队员说话者用 0000／0001）、城镇音效、商品目录、大地图上的行走帧和角色音效表（battle001）、界面音效和配乐 06／05 都借用原版导入件，货架上的 1／81／101 是原版物品。
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
- **命名**：代码里一个概念只用一个词（切入 `cutin`、飘字 `*Floater`、金钱 `gold`、关卡号 `level_no`……），preload 常量用被引文件名，原版字段名不翻译；对照表见 [ARCHITECTURE「术语」](ARCHITECTURE.md#terms)。
- **SKIP 不是 PASS**：原版不在场时，读原版的检查一律显式跳过；看到 `SKIP original-absent` 说明这部分根本没验证。

## 现在做不到的（需要先改代码或工具）

- 规则类选项：存档与锁定的底座（[OPTIONS §9](OPTIONS.md#9-实施计划) B2）还没建，现有卡都是演出／外观类。
