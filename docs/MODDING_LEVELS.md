# 加关卡、角色与剧情：逐步表

[MODDING](MODDING.md) 的附篇。MODDING 讲每件事改哪一层；本页讲从零写一关、一名角色、一段剧情时，每一步改哪个文件、跑哪条命令，以及这一步是**只写数据**、**必须有素材**还是**必须改代码**。分层规则（导入层 `content/imported/` 不要直接改、生成物不要手改）只在 [MODDING §1](MODDING.md#1-三分钟看懂结构) 讲一次，这里默认你已经读过。

示范：第 200 关「龍脊隘口」和两名新角色 102「蕾雅」、103「托蘭」，全部在 `content/authored/` 里，不需要原版剧本。跑通标准是 `tests/run_authored_level_tests.gd`：夹具战役（`start_level` 为 200）从「開始新故事」直接进第 200 关；从标题的「戰場記錄」进第 200 关 → 开场对白 → 机器人打到自然胜负 → 结果页 → 谢幕；102／103 用自己文件夹里的走行帧、切入、头像和称号。公开仓库里没有 102／103 的 PNG（占位美术是原版 003／004 的帧换色），`python3 tools/hsl.py bootstrap` 的 `demo_actor_art` 任务在本地生成它们。

## 1. 文件在哪

```text
content/authored/level200/        目录名必须是 level＋三位数字，注册表自动发现
  level.json      地图图片、表现 manifest 来源（走行帧／音效／头像／切入，可选 sprite_aliases）、
                  单位（id／角色代号／剧本代号／阵营／起始格）、winfail 会插入的物件代号
  story.txt       开场剧情，原版 STORY 文法（UTF-8）
  winfail.txt     胜负与事件，原版 winfail 文法
  messages.json   两个剧本用到的全部讯息编号 → 文字，以及说话者代号 → 显示名
  terrain.txt     地形：每行一列、每个字符一格（# 不可通行，. 平地，1–9 高度）
content/battles/levels/200.json   关卡档案，只有 battle 分区：id／title／initial_focus_unit_id／initial_objective_phase／result_labels
content/battles/campaign.json     battles 里注册一行（挂在第一章后面；你自己的战役注册在它自己的 campaign.json，见 #9）
content/authored/roles/characters.json   你的角色（PLAYERS.TXT 的字段，UTF-8），code 不与原表重复
content/authored/roles/roster.json       名册：参与角色链的代号
content/authored/roles/job_formulas.json、learning_tables.json   职业公式与学习表
content/authored/roles/skills.json       你的招式（SPECIAL.TXT／MAGIC.TXT 的字段＋表现脚本），code 以 authored 开头
content/authored/actors/<外观>/   一名角色的一套外观（文件夹名＝外观 id，默认＝角色代号）
  art.json        hsl_authored_actor_art.v1：walk.anchor、walk.fps、cutin（null 或 program_of＋anchor）、sounds_of，可选 sounds
  walk/<stand|down|right|up|left>-<n>.png    走行帧，n 从 1 开始，五组张数相同
  cutin/<n>.png   切入帧，n 从 0 开始，张数＝program_of 那一行打击程序的帧数
  sounds/<名>.wav 自己的走／攻／闪／亡音效（art.json 的 sounds 指向它）
  portrait.png    头像（characters.json 的 portrait 指向它）
```

图片格式、尺寸、锚点的要求见 [MODDING §3](MODDING.md#3-换素材)。`python3 tools/hsl.py generate authored_level:200` 的产物（都是生成物，不要手改）：

```text
content/generated/hsl/authored/battle200_seed.json              hsl_battle_seed.v1（evidence_tier authored）
content/generated/hsl/authored/level200_terrain.json            hsl_wrd_terrain.v2
content/generated/hsl/authored/battle200/opening_timeline.json  与第一章同一个 timeline 编译器
content/generated/hsl/authored/battle200/message_text_evidence.json、progression.json
content/generated/hsl/authored/battle200/actor_walk_manifest.json、actor_audio.json、portraits.json、combat_animation.json
content/battles/battle_200.json                                 hsl_level_battle.v1
```

## 2. 一遍跑通的命令

```sh
# 角色、职业、招式表改了才需要；generate 会按依赖排好先后
python3 tools/hsl.py generate job_formulas role_data initial_skill_book skill_target_data authored_effect_scripts growth_lifecycle_data ai_profiles entry_growth_data battle_rewards combat_aftermath_data roster_portraits actor_panels
python3 tools/hsl.py generate authored_level:200     # 组出关卡
python3 tools/hsl.py generate campaign_overview      # campaign.json 加了行之后更新战役总览
tools/godot.sh --headless --import                   # 新放的 PNG 先让 Godot 导入，才能被 load()
python3 tools/hsl.py check authored_level:200 authored_art actor_panels level_profile:200 battle_schema unit_schema campaign_overview
# 想马上玩：campaign.json 的 start_level 临时改成 "200"，再 tools/play.sh →「開始新故事」
```

`hsl generate` 发现还没导入的资源时会打印 `HSL_GENERATE_HINT unimported=N`。

## 3. 逐步表

### 3.1 关卡与剧情

| # | 步骤 | 类型 | 改哪里、怎么做 |
| --- | --- | --- | --- |
| 1 | 关卡骨架（标题、结果标签、初始焦点、目标阶段） | 只写数据 | `content/battles/levels/200.json` 的 `battle` 分区，字段见 [LEVEL_PROFILES](architecture/LEVEL_PROFILES.md) |
| 2 | 地形（格子、阻挡、高度） | 只写数据 | `terrain.txt`；生成器算出统计和 `hsl_wrd_terrain.v2`。没有 tile id（原版 WRD 的 t 值运行时不读）。每格一个字符，高度只能写 0–9。沿用第一章某关的地形：bootstrap 生成的 `content/generated/hsl/static/hsl01/levelNNN_terrain.json` 可以直接转成 terrain.txt：`python3 -c "import json,sys; g=json.load(open(sys.argv[1]))['grid']; hi=max((c['h'] for r in g for c in r if not c['b']),default=0); assert hi<=9, f'walkable height {hi} > 9: terrain.txt holds 0-9'; print('\n'.join(''.join('#' if c['b'] else '.' if c['h']==0 else str(c['h']) for c in r) for r in g))" content/generated/hsl/static/hsl01/level051_terrain.json > content/authored/level201/terrain.txt`。第一章有 8 关可走格高于 9：012、026 最高 16，019、525、526、527、904 最高 18，013 最高 21。命令遇到它们直接报错，不压成 9：高差 ≥3 不可走（`game/sim/TacticalGridRules.gd`），压平会把悬崖变成可走的坡，这 8 关不能原样搬 |
| 3 | 地图图片 | **必须有素材** | `level.json` 的 `map_texture` 指任一 PNG，尺寸＝格数×32 像素，和 `terrain.txt` 的行列数对上。示范借了第 2 关的原版图；和上一步的地形配套时，借同一关的 `content/imported/hsl/chapter01/battleNNN/levelN.png`（如 `battle051/level51.png`） |
| 4 | 单位与阵营 | 只写数据 | `level.json` 的 `units[]`：`id`、`actor`（PLAYERS 或 characters.json 的代号）、`token`（剧本里用的 `SID_…`）、`role`、`cell`。同一 token 的多个单位依次是 serial 1、2、3…。借原版外观的单位从 `presentation` 指的 manifest 取表现：走行帧先查本关 manifest，再查第一章共用的 `content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json`，两处都没有才生成失败；音效缺行不报错，这名单位只是没声音；头像只查说话的角色，同样退回第一章共用的 `content/imported/hsl/chapter01/portraits/manifest.json`，两处都没有才失败。音效这边会让生成失败的只有新角色 `art.json` 里 `sounds_of` 借的代号不在本关音效 manifest（如 `sounds_of 003 has no row in …actor_audio.json`）。第一章每关的 manifest 只带本关出场的人；示范借的 `battle500`（共用遭遇演员池）的走行帧与音效带 001–009、023、024、027、030–039、041、043–045、048、049、051、065，头像只带 001、008、023、024、041、043、048、049；敌人模板从走行帧那张表里挑最省事。`presentation` 的四个清单路径都可以写成列表（如 `["…/battle018/…", "…/battle017/…"]`），按顺序合并、先写的优先，一关要混用不同原作关才导入过的角色时这样写；`units[]` 一行可带 `initial_state`，键照 battle JSON 的单位字段（如 `no_attack`、`hp`／`max_hp`，或 `evef_instance.overrides` 里的 `find_type`／`find_range`／`wait_round`／`fixed_point`，按 `content/schema/unit.schema.json`），生成时覆盖到该单位上 |
| 5 | 开场剧情（配乐、延迟、走位、对白、亡语、状态） | 只写数据 | `story.txt`。能用的 token 见 `tools/hsltools/levels/timeline.py` 的 `ACTION_KIND`／`EXTENDED_TOKENS`；`game/battle/runtime/BattleOpeningCoordinator.gd` 里没有演出分支的 token 落进 `RECORD_ONLY_KINDS`，只记录不演。走位终点由生成器算成格子坐标。**配乐**：只有 0–99 号关在原版曲目表里有曲子，100 号以上的关写 `actPlayLevelMusic` 不换曲（换关时已经停过乐，所以单独写就是静音；先用 `actPlayMusic` 放过曲的话照旧放着），用 `actPlayMusic,N` 指定曲号；自己的曲子放进 `content/authored/music/N.ogg`（N 从 100 起），剧本写 `actPlayMusic,N`，示范第 200 关用的是 100 |
| 6 | 胜负条件与事件（清场胜、主角倒下败、第 N 回合援军） | 只写数据 | `winfail.txt`：`[win]`／`[fail]`／`[event]` 段，每段是 `code`、`message` 加一串 `action =`；开头的 action 是条件（`actCheckEnemyTotalNumber,0` 清场，`actCheckPlayer,1,SID_雷歐納德` 主角倒下，`actCheckRoundNumber,3` 第 3 回合），后面是动作。19 个条件、47 个动作及参数写法见 [WINFAIL_TOKENS](WINFAIL_TOKENS.md)。剧本插入的物件代号在 `level.json` 的 `objects` 里给出 `actor`／`token` |
| 7 | 对白文字与说话者名 | 只写数据 | `messages.json`；缺讯息编号或缺说话者名，生成即失败。原版用 RESOURCE.TXT 编号当说话者 id，你的关直接用 token 当 id |
| 8 | 下一关／结局 | 只写数据 | 胜利段写 `actSetNextPlayLevelEvent,200,<下一关 key>`；`998` 表示进谢幕（战斗结果页可以直接进谢幕） |
| 9 | 注册 | 只写数据 | 这关所属战役的 `campaign.json` 的 `battles` 加 `"200": {"scenario": "res://content/battles/battle_200.json", "title": "龍脊隘口"}`，再重生成战役总览（§2）。挂在第一章后面就是 `content/battles/campaign.json`；你自己的战役（#19）写进它自己的 `campaign.json`，示范第 200 关两份都登记了。扫关和自动对局只测当前战役登记的关，自己战役里的关要带 `HSL_CAMPAIGN=<id>`（§9）。自动对局结果文件要补一行，见 §9 |

### 3.2 角色、职业与招式

新角色写进 `content/authored/roles/characters.json`，**不要往导入的 `PLAYERS.TXT` 里加段**：那份是导入层，下次导入会被原版覆盖（[MODDING §1](MODDING.md#1-三分钟看懂结构)）。`tools/hsltools/sources/tables.py` 的 `character_rows()` 把你的行接在原表之后，七张全局表（角色、技能书、成长、AI、入场成长、奖励、战后）和名册头像表自动长出该行，原表哈希不动。

| # | 步骤 | 类型 | 改哪里、怎么做 |
| --- | --- | --- | --- |
| 10 | 新角色（属性、装备、初始技能、AI 参数、开场气力、经验） | 只写数据 | `characters.json` 的 `characters` 加一行（值都写成字符串，同原表）。必填 `code name_text job mode str dex mind con move_point`；其余同 PLAYERS：装备槽 `*_equip`、`special_*`／`magic_*`、`find_*`／`ai_*`、`level`／`exp`／`kill_exp`、`stamina`、`item1`…`item8`、`resist_*`；另有你的表专有的 `portrait`（res:// PNG）和 `allocation`（`manual` 手动分配）。再把 code 加进 `roster.json` 的 `actors`。AI 参数和开场气力各字段的含义见 [MODDING §4](MODDING.md#4-改规则) 例二、例三 |
| 11 | 新职业 | 只写数据 | `job_formulas.json` 的 `jobs` 下加 `"101": {…}`：`symbol`（自己起的代号，如 `jobDragonLord`，不得与 `TYPE.H` 重名或重号；角色行 `job` 就写它，`TYPE.H` 不改）、`name_text`（称号，必填）、`caps`（str dex mind con 上限）、`allocation_quota`、`max_hp`／`max_mp`／`attack`／`defense`／`speed` 的项列表（`[mul, var, div]`＝mul×var÷div，`[mul, var, div, pre]`＝mul×(var÷pre)÷div，裸整数＝常数；变量 `str dex mind con level hp_level`）、`magic_attack`（`terms`＋可选 `cap`／`soft_knee`＋`bonus`）、`resist`（`cap`＋五行 `[p, div]`），行内标 `"evidence_tier": "authored"`。80–100 号用 `TYPE.H` 的名字（100 号 `jobDarkAngel` 原版有代号无公式），数值由原版回执钉住。再在 `learning_tables.json` 的 `jobs["101"]` 写它学什么（§5） |
| 12 | 角色一开始就会的绝技／魔法 | 只写数据 | 角色行的 `special_*`／`magic_*` 栏：写 SPECIAL.TXT 已有、且 `tools/hsltools/data/skill_book.py` 的 `REGISTRY` 支持的招名（如 `"special_wind": "天雷猛襲劍"`），或你的招式表里的招名，写在该招元素对应的栏（`"special_fire": "龍炎斬"`、`"magic_fire": "龍息"`），写错栏生成即失败。学习表也可以引用你的招式 id |
| 13 | **全新**绝技／魔法（新名字、新数值、新表现） | 只写数据（效果族限已有公式） | `skills.json` 加一行（字段见 §4），生成后技能书 `content/generated/hsl/skills/initial_book.json` 长出该招（id 如 `special:magicFIRE:authoredDragonFlame`），`targeting.json` 补上它用到而原表没用过的 RANGE 行，`authored_effect_scripts.json` 长出表现行，由 `SkillEffectScriptPlayer` 和原表行同路播放。新的效果族（治疗、状态、增益……）和新 opcode 生成器会拒绝并说明原因，属于改代码（§8） |
| 14 | 走行帧、音效、对白头像 | 只写数据（新图**必须有素材**） | `content/authored/actors/<代号>/` 放 `art.json`＋`walk/*.png`＋`portrait.png`，characters.json 的 `portrait` 指向头像；`sounds_of` 借某个原版角色的走、攻、闪、亡音效，`sounds` 把其中几项换成文件夹里自己的 WAV（示范 103 的 `sounds/attack.wav`）。借现成外观：`level.json` 的 `presentation.sprite_aliases`（`{"<代号>": "<外观 id 或 PLAYERS 行>"}`），也可以给一名角色换第二套外观。你的角色既没有文件夹也没有 alias 时生成即失败（不会落到同号的导入行）。示范 103 是零代码加入的：那次提交只动了 characters.json、roster.json、level.json 和 `actors/103/` |
| 15 | 战斗切入 | 只写数据（新图**必须有素材**） | `cutin/<n>.png`＋`art.json` 的 `cutin.program_of`（借哪一个 PLAYERS 行的打击程序：时间轴、受击帧、闪光、朝向）和 `cutin.anchor`；生成器把上场各行组成该关的 `combat_animation.json`（导入行原样）。`cutin: null` 或没有导入切入的行走"无美术"片段。截图验看：`tools/godot.sh --script res://tests/capture_authored_art_review.gd`（需要窗口，输出到 `ignored/authored-art-review/`）。特写背景：`level.json` 的 `presentation.combat_backdrop` 可写一个 `res://` PNG（640×320，如 `content/imported/hsl/chapter01/combat_animation/backdrops/BG001.png`），不写就用第一战的 BG051；第一章各关的背景由原版每关 obj-NNN.obs 的对象 `BG` 指定，生成器已按它填 `resources.combat_backdrop` |
| 16 | 名册头像（状态面板取脸） | 只写数据 | characters.json 的 `portrait`；`roster_portraits` 生成合并表 `content/generated/hsl/roles/actor_portraits.json` |
| 17 | 行走特征（飞行、穿墙、体型） | 只写数据 | PLAYERS 字段 `move_fly`／`no_block`／`size_type` |
| 18 | 身份栏的称号、种族、姓名（切入、悬停、目标预览、道具面板） | 只写数据 | `actor_panels` 生成 `content/generated/hsl/roles/actor_panels.json`：称号＝角色行 `job` 在 RESOURCE 里的名字（你自己的职业用 job_formulas 那一行的 `name_text`），种族＝`class` 的 RESOURCE 名，姓名＝`name_text`。角色表或外观改了就重跑它，缺行时一上切入身份栏就失败 |

### 3.3 从标题开始与续集世界

| # | 步骤 | 类型 | 改哪里、怎么做 |
| --- | --- | --- | --- |
| 19 | 从标题开始你的战役，和第一章并存 | 只写数据，已验证 | 你的战役写自己的 `campaign.json`：`start_level` 是第一关的 key，片头动画是 `start_movie`（第一章是 `"start"`），不写就不播。再在 `content/authored/campaigns.json`（`hsl_campaign_registry.v1`）登记一行：`id`（存档文件夹名，只用英文字母、数字、`_` 和 `-`）、`title`（选单上的名字）、`campaign`（你的 `campaign.json` 路径）；第一章不用登记，永远排第一。登记了不带 `hidden` 的战役后，「開始新故事」先弹选择板列出第一章和各战役，末行「離開」（或 Esc）回菜单；列得出的只有第一章时照旧直接开始。带 `"hidden": true` 的战役不上选单——示范「續集示範」就这样登记，所以本仓库的标题照原版直接开第一章。实玩或测试直达某个战役：环境变量 `HSL_CAMPAIGN=<id>`，直接启动 `BattleSceneRuntime.tscn` 开它；只列出第一章时，这个进程的「開始新故事」也开它（中途读过别的战役的回憶錄或戰場記錄也一样），列得出多个战役时仍先弹选择板 |
| 20 | 续集自己的大地图 | 只写数据，已验证 | `content/authored/world/world_map.json`（`hsl_world_map.v1`）：点位一行一个，`id`＝`slot`（1–99），可选的 `level` 是没被事件写过时点开的关号（不写就等于 `id`，#22），`x`／`y` 是地图图面上的像素，`flag_names` 定类型（`bmpmTown`／`bmpmBattle`／`bmpmGeneral`），`raw_track_fields` 列它连着的路线，`raw_field0` 是开局的显示阶段（起点写 2，开局藏起来的点写 0）；路线写 `from_point`／`to_point`、折线 `polyline` 和 `sprite.preview`；`towns[]` 把城镇符号对到点位和背景图。同目录的 `world_map_scene.json` 照第一章的场景写，`resources` 指到续集自己的四张表，`new_game.hidden_points`／`hidden_tracks` 定开局藏起来的点和路 |
| 21 | 城镇里的店和人 | 只写数据，已验证 | 同目录 `towndef.json`：`symbols` 里 `town_<名字>` 等于点位 id，`town_events` 一行一个菜单项，te 文法照原版 TOWNDEF（`teShapeMessage` 说话、`teCreateShop` 开店，货表在 `items`）；`town_initial_trees.json` 是开局的根菜单；`town_messages.json` 放文字和队员说话者，606／607 是商店拒绝语的固定编号 |
| 22 | 点位通往哪一关 | 只写数据，已验证 | 点位写 `level` 就开那一关，不写就开和自己 `id` 同号的关（原版点记录 +8 的初始关号，第一章的点都是这样）；身份、路线和存档仍按 `id`，所以续集点位的 `id` 留在 1–99，200 以上的关号直接写进 `level`。中途要改，用城镇事件 `teBMSetPointEvent,<点>,<关>,<类型>`（或剧本的 `actBMSetPointEvent`），事件写过的值优先于 `level`。示范里龍脊隘口写 `"level": 200`，晨風鎮的老獵人只用 `teBMClearPointFlag`／`teBMClearTrackFlag` 去掉龍脊隘口和那条路的 `bmpmHidden`。两处边角：点位写了 `level` 后，事件写 `-1`（保留原值）目前回落到 `id` 而不是 `level`；Town 点仍按 `id` 进城，`level` 只在写 0 时起作用（停住不进） |
| 23 | 战役接起来 | 只写数据，已验证 | 续集自己的 `campaign.json`：`start_level` 写 `"49"`（原版的大地图关号），`battles["49"]` 和 `world_map` 都指到续集的大地图场景；关卡胜利段写 `actSetNextPlayLevelEvent,<点>,49` 回到那个点。示范借用的第 200 关胜利段是 `200,998`，示范战役就把 998 也登记成大地图。登记进 `campaigns.json` 就和第一章并存（#19），存档分开：第一章沿用 `user://` 下原来的进度、戰場記錄和回憶錄文件；登记战役的进度和戰場記錄放 `user://campaigns/<id>/`（`campaign_progress.json`、`<场景 id>.save`）。回憶錄 8 格各战役共用，你的战役存的那格记下 `campaign_id`、行首标出战役名，读取时先切到那个战役；没有战役 id 的记录当第一章。标题的「戰場記錄」接着最近存过档（自动进度或战斗 checkpoint，按文件修改时间）的那个战役。`tests/run_campaign_tests.gd` 的续集世界一条从标题选战役开始，走完 战役 → 大地图 → 城镇 → 大地图 → 龍脊隘口（LEVEL200）→ 大地图，并查存档落在续集自己的文件夹、第一章进度不被覆盖 |

## 4. 招式表字段（`content/authored/roles/skills.json`）

每行一招，字段名和值都照原表写（字符串或数字）。`tools/hsltools/data/authored_skills.py` 逐字段校验，并用和运行时同一道描述符判断（`skill_coverage._descriptor_judgment`）核过才写进技能书。

| 字段 | 绝技 `special` | 魔法 `magic` | 值 |
| --- | --- | --- | --- |
| `channel` | ✓ | ✓ | `special`（SPECIAL.TXT 形，耗 ST＝`expend`×20）或 `magic`（MAGIC.TXT 形，耗 MP＝`expend`） |
| `code` | ✓ | ✓ | `authored` 开头，表内唯一；招式 id＝`channel:type:code` |
| `name_text` | ✓ | ✓ | 显示名，表内唯一，不得与 mag-spc.h 的招式别名同名；角色行声明栏写的就是它 |
| `type` | ✓ | ✓ | 元素 `magicEARTH`／`magicWATER`／`magicAIR`／`magicFIRE`／`magicMIND`／`magicOTHER`，决定抗性槽和角色声明栏；`magicOTHER` 不读抗性 |
| `range`／`effect_range` | ✓ | ✓ | RANGE.TXT 的形状名（施放距离／作用范围），如 `range2Cell`、`range4CellThrust`、`range3CellDir`（直线） |
| `expend` | ✓ | ✓ | 0–999 |
| `damage` | ✓ | ✓ | `"低,高"`，0 ≤ 低 ≤ 高 ≤ 10000，原版三角分布抽样 |
| `hit_ratio`／`use_ratio` | ✓ | ✓ | 0–100（命中率；AI 使用率） |
| `function` | ✓ | ✓ | 目前只收 `magicFun_Attack`：绝技走原版绝技伤害（等级抽样＋con/8＋mind/4＋dex/3，×`attackpow_ratio`），魔法走原版魔法伤害（等级＋mind＋抽样，×魔攻） |
| `attackpow_ratio` | ✓ | — | 0–1000（%） |
| `attack_code`／`defense_code` | ✓ | — | 切入的施法段／受击段：EFFECTS.TXT 的 specCode（如 `specCode31`），或本表 `scripts` 里的 `authored…` 段（只能用 `ani*` opcode） |
| `effect_proc`／`effect_code` | — | ✓ | `eff_proc_Local`（每个受影响格播一次）或 `eff_proc_Global`（画面中心播一次）；effCode 段或 `scripts` 里的 `authored…` 段（只能用 `eff*` opcode） |

`scripts`：`{"authoredXxx": ["effInsertObject,obj_Effect_FireBomb2,0,0,effWait,50", …]}`，每一项就是 EFFECTS.TXT 的一条 `action =`。动词必须在 `SkillEffectScriptPlayer.IMPLEMENTED_OPCODES` 里，物件、WAV、SHP 必须是 `skill_effects` 已经导入的（新美术见 #14，新 opcode 属于改代码）。

## 5. 最小文件原文

`content/authored/level200/story.txt`（节选）：

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

`winfail.txt`（节选）：

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

`level.json` 的单位行和物件行：

```json
{"id": "reia", "actor": "102", "token": "SID_蕾雅", "role": "player_controlled", "cell": [8, 9]}
"objects": {"obj_Level200_Wolf": {"actor": "036", "token": "SID_ENEMY036"}}
```

`learning_tables.json` 的新职业行（魔法、绝技的 id 是 MAGIC.TXT／SPECIAL.TXT 或你的招式表的 `channel:type:code`，名字在生成时解析）：

```json
"101": {"tier": 1, "magic": [{"id": "magic:magicFIRE:authoredDragonBreath", "level": 3}], "special": [{"id": "special:magicFIRE:authoredDragonFlame", "tier": 1, "attributes": {"str": 20, "dex": 22, "mind": 14, "con": 18}}], "evidence_tier": "authored"}
```

`skills.json` 的第二招（只加数据）：

```json
"scripts": {"authoredDragonBreath": ["effPlaySound,WAV\\FIRE0006.WAV", "effInsertObject,obj_Effect_FireRoundFire,0,0,effWait,30", "effInsertRandomObject,obj_Effect_FireFire,0,8,48,16,10,6", "effWait,40", "effInsertObject,obj_Effect_FireBomb2,0,0,effWait,50", "effWait,30"]},
{"channel": "magic", "code": "authoredDragonBreath", "name_text": "龍息", "type": "magicFIRE", "range": "range4CellThrust", "effect_range": "range1Cell", "expend": "10", "damage": "30,48", "hit_ratio": "94", "function": "magicFun_Attack", "use_ratio": "90", "effect_proc": "eff_proc_Local", "effect_code": "authoredDragonBreath"}
```

## 6. 其他内容表（战役流转、城镇、大地图、标题）

| 想改什么 | 文件 | 说明 |
| --- | --- | --- |
| 战役流转（哪一关接哪一关、哪一关是战斗／剧情／谢幕） | `content/battles/campaign.json` | `battles["N"]` 一行一关：`scenario`、`title`、`kind`（省略＝正式战斗；`story`＝剧情场景或开场预览；`game_clear`＝谢幕）。运行时 `CampaignProgress.next_destination` 只看这张表；`campaign_overview` 生成[战役总览](evidence_packets/resource_inventory/campaign_overview.md) |
| 查原版剧本怎么写 | `content/imported/hsl/story_corpus/` | 原版全部 STORY／winfail／STORYOVER／TOWNDEF 的机器可读语料（`story_corpus`），写剧情前在这里查文法和用例 |
| 城镇菜单与事件 | `content/world/town_initial_trees.json`（手写）＋导入的 `content/imported/hsl/global/world_map/towndef.json` | 事件由 `TownEventRules` 解释；剧本对城镇树的改写（actAddTE 等）在交接时由 `WorldScriptActions` 施加。续集用自己的一套，示范在 `content/authored/world/`（§3.3 #21） |
| 转职后哪座城怎么变 | `content/world/town_job_up_writes.json`（`hsl_town_job_up_writes.v1`）；你的战役用自己的一份 | `teCheckJobUp2` 成功后回放这份表。这份是第一章的，改它就是改第一章（改后跑 `python3 tools/hsl.py check town_job_up_writes`，改成别的城要把 `evidence_tier` 标成 `authored`）。你的战役不改它，而是在自己的 `campaign.json` 写 `"town_job_up_writes": "res://…"` 指向同格式的表：`schema` 为 `hsl_town_job_up_writes.v1`，`second_tier.members` 是 towndef 的 `SID_*` 队员符号（全员都走到最后一个称号才改写），`second_tier.town` 是 `town_*` 符号，`second_tier.writes` 按顺序列 te 代号与 TOWNDEF 参数（`teAddTE`／`teDeleteTE`／`teSetTownExecEvent` 城镇在前）；不写这个字段就回放第一章这份。`check town_job_up_writes` 只校第一章这份，你的表缺文件或 schema 不符时，转职成功后记一条 `check_failed`（`missing_town_job_up_writes`） |
| 酒馆神秘男子的价格、货表 | `content/generated/hsl/static/hsl01/secret_man_goods.json` | 生成物（`secret_man_goods`，需要原版 EXE），没有手写层入口 |
| 大地图点位、路线、隐藏 | 导入的 `content/imported/hsl/global/world_map/world_map.json`＋手写的 `content/world/world_map_scene.json`（`new_game` 隐藏集） | 运行时状态随存档。续集的一套示范在 `content/authored/world/`（§3.3 #20） |
| 标题、系统菜单、谢幕的美术与版式 | 导入的 `content/imported/hsl/global/title/manifest.json`（`title_assets`） | 版式常量在 `tools/hsltools/assets/title_assets.py` 里。换图不用改它：同名同尺寸的 PNG 放进 `content/authored/ui/global/title/`，或只给你的战役放进 `campaign.json` 同目录的 `ui/global/title/`（见 [MODDING「界面」](MODDING.md)那一行） |
| 配乐 | 见 [MODDING §3](MODDING.md#3-换素材) 素材表的"配乐"行 | 关卡里自己的曲子：`content/authored/music/N.ogg`（N 从 100 起）＋剧本 `actPlayMusic,N` |

## 7. 手写一场战斗：battle JSON 的合同

加一关**不需要**手写 battle JSON，`authored_level:N` 会组出来；这一节给想绕过作者格式直接喂引擎的人。

- `content/battles/*.json` 里 `rule_adapter` 为 `winfail`／`development_battle` 的文件是战斗，装载时按 `content/schema/battle.schema.json`（`hsl_battle.v1`）校验：`required` 是没有默认值可顶替的输入（`schema`、`id`、`title`、`rule_adapter`、`player_unit_id`、`playable_units`、`resources` 里的 `map_texture`／`terrain`／`attack_ranges`／`consumables`／`progression`、`scenario_rules.initial_objective_phase`），其余键都带 `default`。`BattleScenario.load_file` 先填默认值再交给 `BattlePlayLoop.create`；违规明确失败（`scenario_error = "battle_schema:$.<path>: <reason>"`，Python 侧 `python3 tools/hsl.py check battle_schema` 同一文本）。
- 场景进入 `BattleSceneRuntime` 还需要表现输入 `actor_walk_manifest`／`actor_audio`／`interface_audio`（缺了 push_error）和对白说话者表 `portraits`（缺了该场对白没有脸）。引擎级全局表（技能书、targeting、成长、AI、奖励、装备目录、名册头像表）不在 `resources` 里，登记在 `game/sim/ContentPaths.gd`。
- 单位只需要 `content/schema/unit.schema.json` 的规则键（`tools/hsltools/schema/unit.py` 的 `RULE_KEYS`）；证据台账键（`PROVENANCE_KEYS`）一个都不用写，运行时按 `authored` 处理。
- 最小原文：`tests/support/authored_minimal_battle.json`；`tests/run_authored_level_tests.gd` 证明它能建局、开到首次控制，并让机器人打完几回合。

## 8. 必须改代码的情况

| 想做什么 | 改哪里 |
| --- | --- |
| 新的 winfail 条件或动作 | 先在 `game/sim/WinfailCompiler.gd` 加词表（token 行尾的 `# 语义` 注释就是 WINFAIL_TOKENS 的语义列，缺了 `python3 tools/hsl.py check winfail_token_table` 失败），再在 `WinfailConditions.condition_holds`／`WinfailActions.apply_actions` 加分支，然后 `python3 tools/hsl.py generate winfail_coverage winfail_token_table`（前者需要原版 PAK） |
| 新的开场 opcode 演出 | 在 `tools/hsltools/levels/timeline.py` 的 `ACTION_KIND` 映射 kind，再在 `game/battle/runtime/BattleOpeningCoordinator.gd` 的 `_apply_event` 加分支 |
| 新的技能效果族（治疗、状态、增益、特殊行动） | 规则侧：在 `game/sim/` 写一个模块，按 `SkillResolutionRules.EFFECTS` 表头的签名提供 descriptor_error／prepare／resolve，再在 `EFFECTS` 登记一行新的 `damage_policy`；生成侧：你的招式目前只收两个通道的原版伤害（`authored_skills.py` 的 `DAMAGE_POLICIES`），要让它放行新值 |
| 新的特效 opcode | `SkillEffectScriptPlayer.IMPLEMENTED_OPCODES` 及其播放分支 |
| 新的切入打击程序（不借 `program_of`）、切入 s_shape／m_shape 条带 | 不在作者格式的约定内（绝技切入目前显示站立的施法者） |

改代码时的入口：场景宿主 `game/battle/scene/BattleSceneRuntime.gd` → 开场协调器 `game/battle/runtime/BattleOpeningCoordinator.gd`；战斗规则 `game/sim/`（`TacticalGridRules`、`CoreCombatRules`、`CoreTurnQueue`、`WinfailScenarioRules`…），唯一可变的战斗状态在 `game/sim/loop/BattlePlayLoop.gd`；大地图和城镇 `game/world/`；标题、GAME OVER、谢幕 `game/title/`；战斗内系统菜单 `game/battle/scene/BattleSystemMenu.gd`；设置 `game/settings/GameSettings.gd`；战役存档、交接、回憶錄、戰場記錄只经 `game/common/CampaignProgress.gd`。新加 `game/**/*.gd` 要写 `## provenance:` 头，然后 `python3 tools/hsl.py generate provenance`（格式见 [ARCHITECTURE](ARCHITECTURE.md#provenance-headers)）。模块地图见 [ARCHITECTURE](ARCHITECTURE.md)。

## 9. 验证

```sh
python3 tools/hsl.py check authored_level:200 authored_art actor_panels level_profile:200 battle_schema unit_schema campaign_overview autoplay_results
python3 tools/hsl.py check job_formulas role_data growth_lifecycle_data entry_growth_data     # 改了角色、职业表
tools/godot.sh --headless --script res://tests/run_all.gd -- run_job_stats_tests.gd run_entry_growth_tests.gd
tools/godot.sh --headless --script res://tests/run_authored_level_tests.gd                   # 第 200 关端到端
python3 tools/hsl.py affected --since <基线提交> --check                                      # 只跑改动命中的任务
```

- **注册后自动覆盖**：`tests/run_battle_sweep_tests.gd`（开场 → 首次控制 → 强制胜利 → 交接；胜利条件不是清敌时，在 `levels/NNN.json` 写 `sweep_fixture`）和 `tests/run_autoplay_sweep_tests.gd` 会自动测到新关。窗口化截图：`HOME="$PWD/ignored/lane-home" tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=200`（它会清掉 user:// 里的战役存档，所以只在 ignored/ 下的 HOME 里跑）。
- **自动对局结果文件** `content/generated/hsl/development/autoplay/results.json` 要补一行：跑一次全量 `tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`，它会重写结果文件，并因"新增了一关"报一次不一致，看过重写结果后提交即可。`HSL_AUTOPLAY_LEVELS=200` 只跑这一关，**不写**结果文件，适合调试；`HSL_RNG_SEED=7` 换种子（同样不写）。两个扫关套件读的是当前战役的 `campaign.json`（默认第一章），只登记在你自己战役里的关要加上战役 id 才找得到：`HSL_CAMPAIGN=sequel_demo HSL_AUTOPLAY_LEVELS=200 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`，输出 `AUTOPLAY level=200 outcome=win …` 即自动打到了胜利。
- **改了剧情流转、大地图或城镇**：`tests/run_story_scene_tests.gd`（全部注册剧情场景：启动 → 跑完 → 交接）、`run_town_scene_tests.gd`，用法同上；大地图与流转改动按需跑 `run_story_mode_explorer_tests.gd`（约 20 分钟，自动走全图）。
- **原版链的关**（有原版时）：`python3 tools/hsl.py list '*:37'` 列出第 37 关的全部任务，`python3 tools/hsl.py check '*:37'` 只跑它们。
- 本仓库的"原版裁判"对你有意改动的规则报不一致是正常的，见 [MODDING §4](MODDING.md#4-改规则) 末段；完整门禁口径见 [CONTRIBUTING §2](../CONTRIBUTING.md#2-门禁口径)。

## 10. 边界

- **authored 标记**：你的关的 seed、battle JSON 和全部单位都不带证据台账，`UnitSchema.evidence_tier` 返回 `authored`；角色 102 的数值由公式表算出，也标 authored。伤害公式本身仍是第一章的原版公式（static-derived）。
- **借用的素材只是通路验证**：第 200 关借第 2 关的地图和 036 的模板，102／103 的外观是原版 003／004 的帧和脸换色（各自 `art.json` 的 note 写明），不是续集美术方案；剩下的是"画出来"本身。
- **切入**：作者关的切入表只含上场各行；转职过的第一章角色在作者关里切入仍用基础行（走行帧走共享的转职表）。
- **平衡**由作者负责：自动对局（贪心、不躲的机器人）在种子 1–5 里 4 胜 1 负、3–5 回合结束；`results.json` 记的是默认种子 1，那一局雷歐納德第 3 回合阵亡判负（winfail 的 fail 段）。胜负只说明链路通，不是难度证据。
- **职业可装备表**：你的职业沿用 `items.json` 的 `job_mask` 位（位＝代号−80），101 读原表第 21 位；112 以上没有位，任何装备都换不上。要自定义可装备表得另加数据。
- 给本仓库提交内容时，改剧情属于重制决定，在场景 `unresolved_semantics` 里写明"重制读法／原创"，证据用语见 [METHOD「证据分级」](METHOD.md#证据分级)。
