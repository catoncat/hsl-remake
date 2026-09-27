# HSL Tools

本目录只保留可复跑、有明确输入/输出/验证的工具。临时探索脚本必须留在 `ignored/`，确认有长期价值后再进入 `tools/`。

按读者分三段：[一、改游戏的人](#一改游戏的人)（运行、导入素材、生成关卡、检查数据）→ [二、贡献者](#二贡献者)（lane、文档检查、公开导出）→ [三、维护者研究](#三维护者研究)（EXE 静态分析、原作运行时观测、原指令探针）。每段先一张总表，再是细节；文件都还在 `tools/` 顶层原位。

## 一、改游戏的人

| 脚本／任务 | 用途 | 入口命令 |
| --- | --- | --- |
| `play.sh`／`play.ps1` | 先导入并检查资源，再运行正式游戏 | `tools/play.sh` |
| `doctor.sh` | 只读环境与仓库检查；`--original` 加查 Wine 与原作 | `tools/doctor.sh` |
| `godot.sh`／`godot.ps1` | Godot 共用入口：导入资源、跑定向测试 | `tools/godot.sh --headless --import` |
| `playtest.sh`／`hsl_playtest_kit.py` | 人工验收：独立存档，标题「戰場記錄」直进验收关 | `tools/playtest.sh [N]` |
| `hsl.py` | 生成器／检查器注册表的唯一 CLI（`list`／`check`／`generate`／`affected`） | `python3 tools/hsl.py list` |
| `verify.sh`／`verify_runner.py`／`verify_slot.sh` | 完整非 GUI 验证 | `tools/verify.sh` |
| 任务 `level_battle:N` | 原版关卡组装成正式战斗 `content/battles/battle_NNN.json` | `python3 tools/hsl.py generate level_battle:N` |
| 任务 `authored_level` | 为重制版写的新关一次组出全部产物 | `python3 tools/hsl.py generate authored_level` |
| 任务族 `assets` | PAK／SHP／WAV 素材导入 | `python3 tools/hsl.py generate assets` |
| 任务 `music_import` | Steam 經典版原曲转成游戏配乐 | `python3 tools/hsl.py generate music_import` |
| 全部任务 | 检查 tracked 数据正是当前源与代码所产生的 | `python3 tools/hsl.py check --all -j 8` |
| `hsl_resource_scanner.py` | 扫描原作目录，原始提取只写 `ignored/` | `python3 tools/hsl_resource_scanner.py --help` |
| `hsl_payload_inspector.py` | chapter01 payload 导入报告 | `python3 tools/hsl_payload_inspector.py --manifest MANIFEST --no-previews` |
| `hsl_chapter_dialogue.py` | RESOURCE.TXT 对白证据导入 | `python3 tools/hsl_chapter_dialogue.py --pak PAK --level N` |
| `hsl_actor_walk_manifest.py`／`hsl_actor_walk_contact_sheet.py` | 解码演员走路帧与 manifest；生成 5×6 contact sheet | `python3 tools/hsl_actor_walk_manifest.py --help` |
| `hsl_map_object_origins.py` | 站立物件 SHP 原点导入与复核 | `python3 tools/hsl_map_object_origins.py --check` |
| `hsl_wrd_decode.py` | `.wrd` → compact terrain JSON | `python3 tools/hsl_wrd_decode.py WRD` |
| `hsl_steam_classic.py` | Steam 經典版目录：下载命令、逐文件校验、PAK 比较、原曲清单 | `python3 tools/hsl_steam_classic.py verify` |

### 标准入口

```sh
tools/doctor.sh             # 只读环境与仓库检查
tools/doctor.sh --original  # 加查 Wine、原作和采样 helper
tools/verify.sh             # 完整非 GUI 验证：快门（默认，热缓存并行）／--full（另证冷克隆导入）／--deep（快门＋长端到端套件）
tools/verify_slot.sh        # verify.sh 开头 source：全机最多 2 个 verify 同跑（/private/tmp/hsl-verify-slots 两个 mkdir 槽）；HSL_VERIFY_PRIORITY=1（lane_merge.sh gate）用负责人专用槽，其余共用另一槽，排队时每 30 s 打 VERIFY_WAIT
tools/verify_runner.py      # 门禁背后的并行 runner：python-tests / checks（＝ hsl check --all）/ godot / deep / affected（lane 定向，见下行）/ promote-timings（run_all 分片耗时 → tests/support/suite_timings.json）
python3 tools/hsl.py list|check|generate|affected   # 生成器／检查器注册表的唯一 CLI（见下节）
tools/play.sh               # 先导入并检查资源，再运行正式游戏
tools/playtest.sh [N]       # 人工验收：独立存档、标题「戰場記錄」直进验收关 N、日志留 ~/hsl-playtest/logs（docs/PLAYTEST.md）
tools/godot.sh --headless --import # 共用诊断入口；先导入一次再做命中的定向测试；上次成功导入以来没有可导入变动时约 1 s 跳过（HSL_FORCE_IMPORT=1 强制）
```

项目标准运行时：

- `/opt/homebrew/bin/python3`（3.10+）
- `/opt/homebrew/bin/godot`
- `/opt/homebrew/bin/wine` 仅用于原作验证

定向套件及命令见 [测试路由](../tests/README.md)。godot.sh 被 play 的资源导入和完整 verify 共用，集中处理 Godot 退出码／日志诊断以及 ignored/.gdignore 的首次创建；已有标记和原始捕获文件保持原状。直接运行定向套件不会清理资源缓存。docs checker 扫描 Git tracked 与未忽略的新 Markdown，检查显式 Markdown 链接／图片、引用式链接和标题锚点；代码示例、裸路径及外链内容不属于其验证范围。

### hsltools 包与 `hsl` 注册表

生成器、探针、导入器与检查器的实现全部收在包 [`tools/hsltools/`](hsltools/)（`tools/hsl_*.py` 只剩下节表中有自己实现的独立工具，没有任何再导出或转发垫片）：`paths`（仓库根／content／原作目录 `~/.wine-hsl-original`，可用 `WINEPREFIX` 覆盖；Steam 經典版目录 `~/hsl-steam/fancy-realm/GAME-PAK`，可用 `HSL_STEAM_CLASSIC` 覆盖；唯一出处）、`sources/tables`（PLAYERS／ITEM／MAGIC／SPECIAL 段解析 `blocks`、RESOURCE.TXT `parse_table`、`digest`）、`sources/pak`（PAKS 容器：LZW 目录解码、按 `@:\\path` 查记录、读字节、XOR-A8 WAVE）、`sources/shp`（TLHS/SHP 解码与 PNG 预览）、`native/image`（SHA 锁定的 hsl01.exe 段映射 `image`／`EXE_SHA`）、`native/machine`（unicorn 机器工厂）、`native/sources`（探针输入表）、`model/jobs`（职业属性模型）。生成器、探针、导入器与检查器的函数体都住在下表的任务包里；PAK／SHP／RESOURCE.TXT／EXE 映像这些共享读法只 import `hsltools.sources.*`／`hsltools.native.image`，不经任何 `tools/hsl_*.py` 转手（2026-09-24 起 `hsl_resource_scanner`／`hsl_payload_inspector`／`hsl_chapter_dialogue`／`hsl_native_animal_probe` 不再再导出 hsltools 的名字）。

#### 独立工具 `tools/hsl_*.py`（全部有自己的实现）

这些脚本不是注册表任务的入口（那些走 `hsl check|generate`），而是有自己 CLI／函数体的独立工具。被包复用的库体全部住在包里（`sources/scripts`＝EVEF／文本元数据、`sources/wrd`、`sources/actor_walk_frames`、`sources/pak.ensure_safe_extract_output`、`levels/message_text`＝说话者表与对白导入、`native/animal_dispatcher`、`assets/_mobile_animation`、`typesafe`），脚本只 import 包、包不 import 脚本（`test_hsl_registry` 断言；`hsl affected` 对 `tools/hsl_*.py` 改动不再命中任何任务）。任务的 `scripts` 字段只列包内文件；`hsl affected` 仍沿 `tools/*.py` 静态 import 图传播独立工具之间的依赖。新增独立工具要在所属读者段的独立工具表加一行并带 `test_hsl_*.py`／`--check`／`--dry-run` 验证；共享读法进 `hsltools.sources.*`，不在这里再导出。

| 脚本 | 用途 | 验证 |
| --- | --- | --- |
| `hsl_actor_walk_contact_sheet.py` | 由走路帧 manifest 生成 5×6 contact sheet（检查器在 `hsltools/evidence/actor_walk_contact_sheet.py`） | — |
| `hsl_actor_walk_manifest.py` | 从原 PAK 解码演员走路帧 PNG 与 manifest 的命令行（解码器与 manifest 构建在 `hsltools/sources/actor_walk_frames.py`，`levels/actors`、`story_scene`、`map_objects`、`assets/job_casts` 复用） | — |
| `hsl_chapter_dialogue.py` | RESOURCE.TXT 对白证据导入命令行：`--pak PAK --chapter`／`--level N`（导入器、说话者表 `SPEAKER_IDS` 与检查器同住 `hsltools/levels/message_text.py`） | `test_hsl_levels.py` |
| `hsl_map_object_origins.py` | 第一战站立物件 SHP 原点导入，`--check` 复核 | `--check`（[放置初始化包](../docs/evidence_packets/static_reverse/actor_placement_initialization.md)） |
| `hsl_playtest_kit.py` | 人工验收存档：`generate` 在隔离 HOME 跑章节 autoplay、留下产品每次写的战役进度，取每个验收关的首次进入做成 8 个回憶錄；`select` 只重选；`install` 装进 `~/hsl-playtest/home` 并让标题「戰場記錄」指向某一格（`tools/playtest.sh` 调用；见 [PLAYTEST](../docs/PLAYTEST.md)） | — |
| `hsl_payload_inspector.py` | chapter01 payload 导入报告（EVEF／脚本文本元数据解析在 `hsltools/sources/scripts.py`，WORL／WAV／SHP 报告与 chapter01 写出仍在此；SHP 预览写到同级 `shared/shape_previews/`） | `test_hsl_payload_inspector.py` |
| `hsl_resource_scanner.py` | 原作目录扫描器：类型猜测、嵌入签名、XOR-A8 WAVE 候选、`ignored/` 安全提取 | `test_hsl_resource_scanner.py` |
| `hsl_steam_classic.py` | 仓库外 Steam 經典版目录（`paths.STEAM_CLASSIC_ROOT`，`HSL_STEAM_CLASSIC`）：`fetch` 打印 DepotDownloader 命令（用户本人登录），`verify` 按固定清单 `steam_classic_files.json` 逐文件 sha1，`pakdiff [--text]` 本机 hsl.pak 对 Steam hsl.pak／hsl-cn.pak 逐成员比较，`music` 列原曲格式与时长（[证据包](../docs/evidence_packets/resource_inventory/steam_classic_edition.md)） | `verify`（需 Steam 目录，不入门禁）、`fetch` 只打印 |
| `hsl_wrd_decode.py` | 显式 `.wrd` → compact terrain JSON 命令行（解码器 `hsltools/sources/wrd.py`，`levels/seed`、`data/terrain_heights` 复用） | `test_hsl_wrd_decode.py` |

[`hsltools/registry.py`](hsltools/registry.py) 是任务注册表。每个 Task 声明 `inputs`／`outputs`（仓库相对路径）、`replaces`（它取代的旧检查命令）、`scripts`（改动会影响它的 `tools/*.py`），`check` 证明 tracked 输出正是当前源与代码所产生的，`generate` 重写输出；`generate` 需要的原作输入（`hsltools.paths` 解析：`WINEPREFIX`，缺省 `~/.wine-hsl-original`；或 `--exe`）不在场时报 `NotGeneratable`，`hsl generate` 计 FAIL 并打印缺的路径与设法（lane 的独立 `HOME` 下须显式 `export WINEPREFIX=/Users/<用户>/.wine-hsl-original`）；只有纯检查任务（`NoRegenerationPath`）计 skipped 不失败。`tools/hsl_*.py` 探针／导入器的 `--exe`／`--pak` 缺省值同样取自 `hsltools.paths`，不再各自从 `$HOME` 猜。任务模块由 `registry.TASK_PACKAGES`（`probes`／`levels`／`data`／`checks`／`assets`／`evidence`／`schema`）自动发现：包内每个定义 `tasks()` 的模块都参与，没有登记清单。`all_tasks()` 的不变量是 [`hsltools/legacy.py`](hsltools/legacy.py) 的命令台账（按仓库数据枚举的逐关命令＋字面清单，即门禁在注册表之前逐条运行的检查命令）：台账每条命令恰好被一个任务 `replaces`、每条 `replaces` 都在台账内、任务名唯一，否则 `ValueError` 逐条点名——PASS 行集合因此由台账固定，任务不会静默掉队。`tools/verify_runner.py checks` ＝ `hsl check --all`。

任务形状：

| 形状 | 定义处 | `check` | `generate` |
| --- | --- | --- | --- |
| `Task` | `registry` | 基类；逐关纯检查器（`battle_seed`／`level_*`／`*_check`）直接继承并自定 | 自定；无原包时 skipped |
| `GeneratedFilesTask` | `registry` | `render()` → `{path: bytes}` 与 tracked 文件**逐字节**比对 | 写出 `render()` |
| `PacketTask` | `registry` | `validate()` 校验 tracked 证据包（独立模型） | `execute()` 在原 EXE 上跑有界原指令（需 unicorn）后重写包 |
| `ProbeTask` | [`probes/_base.py`](hsltools/probes/_base.py) | `PacketTask` 的探针绑定：`execute_packet(exe)`＋`summary_line(packet, executed_now)` | 同上 |
| `ScriptCheckTask` | `registry` | `verify()` 自己打印 PASS 行，`printed_pass_line` 捕获末行（assert／ValueError／`SystemExit(msg)` → `CheckFailed`） | `build(ctx)` 可选，经 `original_archive` 在 `ctx.original_exe` 旁找 `hsl.pak`／`movie.pak` |
| `OriginalArchiveTask` | [`data/__init__.py`](hsltools/data/__init__.py) | 旧 `--check` 对 tracked 资源／报告的校验 | 从原作 archive 重导入 |
| `CheckTask` | [`checks/__init__.py`](hsltools/checks/__init__.py) | 纯检查，只声明 `inputs` | 无（`NotGeneratable`） |

家族（`hsl list` 第二列；逐关家族的任务名为 `家族:N`）：

| 家族 | 包 | 任务数 | 内容 |
| --- | --- | --- | --- |
| `battle_seed` | [`levels/seed.py`](hsltools/levels/seed.py) | 149 | 原关卡 seed／地形／地图 PNG（读原 `hsl.pak`；含第一战 51 的 `battle051/`） |
| `opening_timeline_compile` | [`levels/timeline.py`](hsltools/levels/timeline.py) | 150 | 每关开场时间线编译（逐字节；149 关＋ `:chapter01`＝章级共享 `chapter01/opening_timeline.json`，开发试炼场景加载） |
| `opening_timeline_check` | [`levels/timeline.py`](hsltools/levels/timeline.py) | 150 | 时间线与源脚本对照（149 关＋ `:chapter01`） |
| `message_text_evidence_check` | [`levels/message_text.py`](hsltools/levels/message_text.py) | 150 | 逐关对白证据（149 关＋ `:chapter01`＝章级共享 `chapter01/message_text_evidence.json`，`hsl_chapter_dialogue.py --chapter` 重建） |
| `level_map_objects` | [`levels/map_objects.py`](hsltools/levels/map_objects.py) | 149 | 逐关地图对象 |
| `level_sounds`／`level_source_texts` | [`levels/sounds.py`](hsltools/levels/sounds.py)／[`levels/source_texts.py`](hsltools/levels/source_texts.py) | 71＋71 | 非遭遇战关的音效与源文本 |
| `level_actors` | [`levels/actors.py`](hsltools/levels/actors.py) | 72 | 逐关演员（71 关＋共享遭遇战池 500）：共享章表已有的演员（walk／portraits／actor_audio 三表）逐字镜像共享条目，`check` 逐字比对共享条目（共享表长出新演员后旧关的本地副本条目即报 drifted，`hsl generate level_actors` 重生成）；只有关卡独有的演员才解码进 `battleNNN/`，其肖像 `name` 按 PLAYERS `name` 字段（`PORTRAIT_NAME_POLICY`）。关卡肖像表的 `name` 运行时不读（对白名来自脚本 name id，面板／给予／队伍画面读名册表 `roles/actor_portraits.json`，由共享表喂） |
| `story_scene` | [`levels/story_scene.py`](hsltools/levels/story_scene.py) | 71 | 逐关剧情场景（逐字节；正式战斗关的开场预览含 051／052／053） |
| `level_battle` | [`levels/battle.py`](hsltools/levels/battle.py) | 125 | 正式战斗装配，`content/battles/battle_NNN.json`（含第一章三战 `battle_051`／`052`／`053.json`），逐单位过 unit schema；共用的 winfail 读法在 [`levels/scenario.py`](hsltools/levels/scenario.py)（无任务） |
| `authored_level` | [`levels/authored.py`](hsltools/levels/authored.py) | 1 | 为重制版写的关（`content/authored/levelNNN/`：原文法 STORY／winfail、对白、ASCII 地形、单位表）一次组出 seed／地形／timeline／对白证据／progression／表现 manifest／`battle_NNN.json`，逐单位过 unit schema；作者路线见[加关卡与角色逐步表](../docs/MODDING_LEVELS.md) |
| `roles` | [`data/roster_portraits.py`](hsltools/data/roster_portraits.py) | 1 | 名册脸表 `content/generated/hsl/roles/actor_portraits.json`（导入的第一章脸表＋授权角色的 `portrait`），`ContentPaths.ACTOR_PORTRAITS` 读它 |
| `probe` | [`probes/`](hsltools/probes/) | 58 | 有界原生探针的证据包；`check` 不需 EXE，`hsl check probe` 进程内约 8 s |
| `assets` | [`assets/`](hsltools/assets/) | 18 | PAK／SHP／WAV 导入器：`check` 只核对 tracked manifest 与哈希；`generate` 重解码 SHP 时像素与 tracked PNG 相同则保留原字节（`sources/shp.write_shp_preview`，所有 SHP→PNG 导入器共用；Pillow／zlib 版本不同只会改压缩字节），追加演员用模块命令行 `PYTHONPATH=tools python3 -m hsltools.assets.combat_animation --pak PAK --actors …`（其余导入器只经 `hsl generate`）；`skill_effects` 按 `special_effect_scripts.json` 清单导入 60 行绝技＋39 行魔法特效的 800 帧＋111 WAV 并声明每行的切入 presentation（`script`／`dedicated_module`＋模块文件名）|
| `evidence` | [`evidence/`](hsltools/evidence/) | 16 | 离线证据包／manifest 检查器；`index` 逐字节渲染 KNOWLEDGE_INDEX.md 生成段 |
| `actors` | [`data/`](hsltools/data/) | 12 | 角色表派生 JSON（progression／role／ai／growth／aftermath／rewards…）；角色链只以表为输入：`job_formulas`（[`data/job_formulas.py`](hsltools/data/job_formulas.py)，作者可编辑的 [`content/authored/roles/job_formulas.json`](../content/authored/roles/job_formulas.json) → 运行时读的 `roles/job_formulas.json`，`JobStatsRules`／`jobs.py` 两侧同一张表、无 per-job 分支）、`role_data`（[`roster.json`](../content/authored/roles/roster.json) 点名哪些 PLAYERS 行成为 live profile，`initial` 由模型算出）、`growth_lifecycle_data`（[`learning_tables.json`](../content/authored/roles/learning_tables.json) 的每 job 魔法等级／绝技行）；原生回执由 `checks` 族的 `role_profiles_proof`／`learning_tables_proof` 逐字段核对，不再是生成输入；加职业／角色的步骤见 [逐步表 §3.2](../docs/MODDING_LEVELS.md#32-角色职业与招式) |
| `skills` | [`data/`](hsltools/data/) | 11 | 技能与魔法表（含 first_skill／mage_magic 等原作档案导入；`special_effect_scripts` 为绝技 specCode＋魔法 effCode 特效脚本／素材范围清单，只列原表行；`authored_effect_scripts`（[`data/authored_skills.py`](hsltools/data/authored_skills.py)）把授权招式表 [`content/authored/roles/skills.json`](../content/authored/roles/skills.json) 的表现行写成 `skills/authored_effect_scripts.json`，同一模块给 `initial_skill_book` 长出授权招式行，见 [逐步表](../docs/MODDING_LEVELS.md#32-角色职业与招式) #13） |
| `items` | [`data/`](hsltools/data/) | 4 | 攻击距离／消耗品／装备／宝箱 |
| `trials` | [`data/`](hsltools/data/) | 5 | 可独立游玩的演练配置 |
| `scenarios` | [`data/`](hsltools/data/) | 4 | 第一战编队、第二战、欧姆村、戈尔山道 |
| `world` | [`data/`](hsltools/data/) | 3 | 地形高度、大地图、城镇初始树 |
| `static` | [`data/`](hsltools/data/) | 7 | EXE／脚本静态产物：big_map_flow／scope_inventory／secret_man_goods／winfail／story token／语料／战役总览 |
| `skill_book` | [`data/skill_book.py`](hsltools/data/skill_book.py) | 1 | 初始技能书 |
| `original_save` | [`data/original_save.py`](hsltools/data/original_save.py)、[`data/original_save_members.py`](hsltools/data/original_save_members.py) | 7 | 原版存档：tracked 样本逐字节 round-trip（`sample`）、运行时 PLAYERS 模板 dump 与成员合成回归（`members`）、原生二次转职 回憶錄 与生成器逐表对照（`native_second_tier`）＋九个可载入的 回憶錄 预设（`second_tier_at_amphibian_gate`／`before_second_tier_at_temple`／`after_second_tier_at_temple`／`level37_pre_jobup`；关卡入口 `level02_pre_battle`／`level17_pre_battle`／`level05_pre_battle`（大地图点；最后一个站在米蘭多、点呼嘯平原即原生进 5 关，STORY005 只有 3 句对白，lane M1）、`level06_pre_battle`（站在席達鎮，酒館 → 沃斯菲塔士兵 原生进 6 关，队伍取自重制 playtest kit 的 memoir_05，含已学技能位，lane M3）与 `level53_pre_battle`（`entry_level` 经 58 → 60 剧情链进关；**战斗关不能用 `entry_level` 直进**：原版载入后敌军记录全未安装、首次 待機 即判胜，见存档格式包）） |
| `checks` | [`checks/`](hsltools/checks/) | 15 | 纯结构检查：source_map_binding／function_catalog／core_logic／generated_metadata／static_index／imported_script_ir／imported_content；`level_music`（[`checks/level_music.py`](hsltools/checks/level_music.py)）：每个场景开场／胜败／选择事件解析出的配乐与影片序列（曲号、流路径）与[原版配乐证据包](../docs/evidence_packets/static_reverse/original_music.md) §4 逐条一致，场景 `level_table_music`（读戰場記錄时从头放的曲，≥100 关为空）与 §2 表一致；`PYTHONPATH=tools python3 -m hsltools.checks.level_music --table` 打印逐关对照表；`engine:chapter_paths`（[`checks/engine_chapter_paths.py`](hsltools/checks/engine_chapter_paths.py)）：`game/` 下除 `## provenance:` 头的证据路径外不得出现 `chapter01`——共享素材经 `ContentPaths` 取 `content/imported/hsl/shared/`，逐关素材经场景 `resources`；`role_profiles_proof`／`learning_tables_proof`（[`checks/role_chain_proof.py`](hsltools/checks/role_chain_proof.py)）把五个原生属性探针包与四个学习探针包降为**检查**：生成的 `roles/profiles.json` 每个 `initial` 与原回执逐字段相等、授权学习表每 job 与原表相等，未标 `authored` 的 job 行必须有回执；`field_coverage`（[`checks/field_coverage.py`](hsltools/checks/field_coverage.py)）逐字节生成 [原版数据字段覆盖](../docs/evidence_packets/static_reverse/original_field_coverage.md) 与 `content/generated/hsl/development/field_coverage.json`：17 张原表／记录（PLAYERS／ITEM／MAGIC／SPECIAL／RANGE／SHAPEDEF 列、EVEF 演员实例字与非演员记录、OBJ `[Object]` 字段、WRD、0x1fc 演员记录、EXTRAS／ANIMAL／TYPE define 组、STORY／WINFAIL／te／ANIMAL／EFFECTS opcode）每个字段的非默认量、状态（consumed／passthrough／recorded／unconsumed／dead）与消费点 `file:function`（生成时核对文件与符号存在，interpreter 支持集直接读 GDScript 常量），外加前十嫌疑；`--census` 模块命令行从原 PAK 重新量 OBJ 字段与 EVEF 字直方图；`provenance`（[`checks/provenance.py`](hsltools/checks/provenance.py)）是这一族里唯一的 `GeneratedFilesTask`：核对每个 `game/**/*.gd` 的 `## provenance:` 头（五维度、[ARCHITECTURE「Provenance headers」](../docs/ARCHITECTURE.md#provenance-headers)词汇、引用文件存在），并渲染 [docs/PROVENANCE.md](../docs/PROVENANCE.md) 的生成块（模块矩阵、remake-invented 清单、provisional 疑点、计数）——头格式错即失败，文档过期只警告（`stale_document=1`，负责人 `tools/lane_merge.sh merge` 时重生成）；`hsl generate provenance` 重写它；`parity_inventory`（[`checks/parity_inventory.py`](hsltools/checks/parity_inventory.py)）把原版与重制的全部已知差异汇成一张单（[原版与重制差异总清单](../docs/evidence_packets/static_reverse/parity_gap_inventory.md)＋同名 `.json`）：每次检查从 provenance 头的 remake-invented／provisional 片段、证据包的「未读／未复原／未复刻／未重制」句与头部 provisional／negative-evidence 范围、机制矩阵每行、R6-V2 录屏 13 类重新量出来源，与人工归类 `parity_gap_inventory.curation.json` 对齐——除句子外新来源没归类（归进一条、`no_visible_effect` 理由或 `resolved` 出处）即失败；句子只警告（清单按归类文件里的句子渲染，改写／删句只打 `PARITY_INVENTORY_WARN`，`generate` 即 merge 时自动删掉已不存在的句子归类）；声明输入是 `game/` 而非 docs/PROVENANCE.md；`PYTHONPATH=tools python3 -m hsltools.checks.parity_inventory --stubs` 打印待填条目 |
| `autoplay` | [`checks/autoplay_results.py`](hsltools/checks/autoplay_results.py)、[`checks/autoplay_brain.py`](hsltools/checks/autoplay_brain.py)、[`checks/autoplay_chapter.py`](hsltools/checks/autoplay_chapter.py) | 3 | 自动对局 sweep 的 `results.json`／`known_dead_ends.json`（每个注册战斗一行、有 `loop_seed` 无墙钟、dead_end 类别须 known；regen-and-compare 由 sweep 套件自己做——重写后与 tracked 逐字比较；见 [tests/README](../tests/README.md#godot-suites)）；驾驭器对照 `brain_comparison.json`（关卡选取规则、每关每模式一行、次数与汇总相加）；整章机器人 `chapter.json`（行名注册战斗、种子递增、首胜即止、败局为末行且等于 `stuck_at`、计数相加）。`autoplay_results` 是注册表里第一个没有旧脚本可 `replaces` 的任务，台账条目是它自己的 CLI 形式 `python3 tools/hsl.py check autoplay_results`；后两个按下文「新增任务」规则 `replaces = ()` |
| `schema` | [`schema/unit.py`](hsltools/schema/unit.py) | 1 | `content/schema/unit.schema.json` |
| `content` | [`checks/player_copy_traditional.py`](hsltools/checks/player_copy_traditional.py) | 1 | 玩家可见文案全繁体：`game/**/*.gd` 代码行字串（注释与 assert／push_error／print 不算）、`game/**/*.tscn` 字串、`content/battles`、`content/authored` 与原文语料 JSON 的 title／name／name_text／display_name／label／message_text／speaker_name／text 及 result_labels／messages／speakers 下的值，按明确的简繁差异字表（1236 字，不含 后／云／里／系／伙 等繁体自有字）＋ 6 个词（游玩→遊玩）判定，原语料自身零命中是字表的校验 |

用法：

```sh
python3 tools/hsl.py list [PATTERN...]                     # 任务：名字、家族、输出（stderr 末行 HSL_TASKS total=N）
python3 tools/hsl.py check --all -j 8                      # ＝ verify_runner.py checks（1,287 项，8 worker 约 20–30 s）
python3 tools/hsl.py check level_battle:37 skills 'level_battle:9*'   # 名字／家族／fnmatch 通配
python3 tools/hsl.py generate unit_schema level_battle:37  # 重生成，生产者先于消费者（按 inputs∩outputs 排序）；--exe 指定原 EXE；写出的 PNG／WAV 若还没有 Godot `.import` 旁车，结尾打印 `HSL_GENERATE_HINT unimported=N first=…`——跑 `tools/godot.sh --headless --import` 后才能 `load()`
python3 tools/hsl.py affected --since HEAD~3 [--check]     # 改动路径→受影响任务：hsltools／runner／CLI／全局源表改动＝全部；tools/*.py 沿静态 import 图传播；数据路径按声明 inputs／outputs 匹配
```

新增任务：在对应任务包里新建模块（或在既有模块的 `tasks()` 里追加），`replaces = ()`——台账 `legacy.LITERAL_CHECKS` 只记迁移前真实存在过的命令（每条须恰好被一个任务 replaces，这是 `check_ledger` 的不变量），**不要为新任务编造台账条目**；不再写 `tools/hsl_*.py` 垫片（2026-09-21 已全部删除，模块命令行只保留注册表没有动词的模式，用 `PYTHONPATH=tools python3 -m hsltools.<family>.<module>` 运行）；单测照 [`test_hsl_registry.py`](test_hsl_registry.py) 的 parity 模式（任务 PASS 行 == `hsl check` 子进程末行、`render` 与 tracked 文件逐字节相同）。各家族的 parity 单测：`test_hsl_levels.py`／`test_hsl_data_tasks.py`／`test_hsl_assets_tasks.py`／`test_hsl_unit_schema.py`。

`unit_schema`（`hsl check|generate unit_schema`，模块 `tools/hsltools/schema/unit.py`）推导 `content/schema/unit.schema.json`——Python 生成器与 GDScript 运行时共用的**唯一** unit 字典合同：从 122 关进程内渲染的 `playable_units`／`script_actor_templates[*].actor`、手工 `content/battles/*.json` 名册与 `content/generated/hsl/actors/*.json` 模板推导现状（必需键＝全部单位都有的键；`combat_profile`／`growth_profile`／`status_counters`／`equipment[]` 分层 `additionalProperties=false`；角色／装备槽／evidence tier 枚举），运行时增补键登记在 `RUNTIME_PROPERTIES`（可选）。`level_battle:N` 的 `render` 用 [`hsltools/schema/validate.py`](hsltools/schema/validate.py)（零依赖，type／required／properties／additionalProperties／enum／items／minItems／maxItems）逐单位校验，违规 `CheckFailed`；运行时对应 `game/sim/UnitSchema.gd`。改了生成器写出的 unit 键：`hsl generate unit_schema level_battle`（生成顺序已按 inputs∩outputs 排好）；单测 `tools/test_hsl_unit_schema.py`。

### 产品数据与资源

- `hsl_resource_scanner.py`：扫描 `$HSL_ORIGINAL_DIR` 下的原版包；raw 输出只允许写入 `ignored/`。
- `hsl_payload_inspector.py`：解析 payload 和章节数据；必须显式传入仓库外或 `ignored/` 中的 resource-scan manifest，默认报告与 preview 只写入 `ignored/payload-inspector/`。

```sh
python3 tools/hsl_payload_inspector.py \
  --manifest /path/to/resource-scan-manifest.json \
  --no-previews
```
- `hsl_actor_walk_manifest.py` / `_check.py`：提取、验证 actor 走路帧 manifest。
- `hsl_actor_walk_contact_sheet.py` / `_check.py`：生成、验证 5×6 contact sheet。
- `hsltools/levels/timeline.py` / `_check.py`：从 STORY IR 或 tracked battle seed 生成 opening timeline（`--message-evidence` 附带对白正文，`--check` 复编译比对）；检查器按 `source_script` profile（story001／051／052／053／058／060）校验。`EXTENDED_TOKENS` 为 ACTION.H 全部非条件 token 给出明确 kind，并按 ACTION.H 注释把参数写入事件 `params`（token 名大小写不敏感，原拼写记入 `script_action_spelling`）；actCheck* 留给 winfail 解释器。
- `hsltools/assets/movie_import.py [--pak movie.pak] [--check]`：解码原 `movie.pak` 的开场／结尾动画——`.ani` 为 Autodesk FLI（0xAF11，320×240 8-bit，COLOR256／BRUN／LC／COPY 块；742／501 帧，环帧剔除，纯 Python 解码与 ffmpeg flic 解码逐字节一致）、`.snd` 为前 38 字节 XOR 0xA8 的 RIFF WAVE（原加载器 0x45a6d0 同样只异或 38 字节）；写 `content/imported/hsl/movie/`（`start.wav`／`end.wav`、每部 ≤ 12 MB 的 320×240 行优先 WebP 精灵表 3840×4080、`manifest.json` `hsl_movie_import.v1`：帧数／15 fps（原播放器 0x45c5f0 以 .data 浮点 15.0 定步，FLI speed=4 未用，static-derived）／时长／来源 sha256／表格帧范围）与证据包缩略图，完整 PNG 帧序列只写 `ignored/movie/<name>/`；`--check` 不读原包，核对哈希、表格尺寸与 WAV 头；单测 `test_hsl_movie_import.py`；结论与边界见[原动画证据](../docs/evidence_packets/resource_inventory/original_movies.md)。
- `hsltools/assets/music_import.py`（任务 `music_import`）：把用户所购 Steam 經典版的原版 18 首配乐 `music\02–19.wav` 转成 `content/imported/hsl/music/NN.ogg`（NN＝原曲号）与 `manifest.json`（`hsl_music_import.v1`）。源文件夹在仓库外、只读（`HSL_STEAM_CLASSIC`，缺省 `~/hsl-steam/fancy-realm/GAME-PAK`），大小与 sha1 须与固定清单 `steam_classic_files.json` 一致。libsndfile Vorbis，compression 0.4（约 q6），保持 22050 Hz 立体声，不重采样、不改增益、不裁头尾；OGG 帧数＝WAV 帧数。流序号固定为 0x48534C00＋曲号，重编码逐字节相同。`null.wav` 是音频初始化时的预热，记为排除项。原版整首循环、无循环点（流播放器 0x45a0b0 播到末尾回到数据开头）；`project.godot` 的 `[importer_defaults]` `oggvorbisstr` 让首次导入的 OGG 取 loop=true、loop_offset=0，调用方不必再设（旁车不入库）。生成需要 Steam 文件夹，编码要 soundfile：`uv run --no-project --with soundfile --with pillow python3 tools/hsl.py generate music_import`，未变的曲目原样保留。`python3 tools/hsl.py check music_import` 不读 Steam 文件夹，核对清单固定值、OGG 哈希、逐页 CRC／序号，以及末 granule＝源帧数。
- `hsltools/assets/title_assets.py [--check]`：解码原标题画面 shape `@:\shape\Title001／002／021–028` 到 `content/imported/hsl/global/title/previews/`，写 `manifest.json`（`hsl_title_assets.v1`：贴图、SHP 原点、参考帧测得的屏幕布局、圆环内亮起项偏移、三项菜单标签与重制语义、未解语义）；`--check` 在 `verify.sh` 运行。布局常量由 `hsl_title_layout_probe.py [--check]` 复测（需 numpy：`uv run --with numpy --with pillow python3 tools/hsl_title_layout_probe.py --check`，对 `01_title_and_opening/frame_001.png` 与 Title021 做模板匹配，不入门禁）。Title011／012（GAME OVER）供 `GameOverScreen`，Title041–047（系统卷轴＋亮起项，卷轴位置 (190,67) 量自录像 05 帧 003）、Title051–057（战间卷轴＋亮起项）、Title031–033（回憶錄 列表与 讀取／儲存 抬头，槽带几何 `memoir_list`）、Title039（設定選項，行几何 `options_rows`／`options_groove`）与 Title061–063（確定／取消）供 `BattleSystemMenu`；标题家族至此全部导入。
- `python3 tools/hsl.py generate|check story_scene:1|2|3|5|6|7|8|9|10|12|53|58|60|65`：无 SHAPEDEF 步行帧的 EVEF 敌方物件（shape 非 `NNN-00001` 或无 `[define]`，如 level 12 的 Enemy101 船殼）不生成 story actor，交由 `map_objects.json` 的 `static_enemy_object` 站立物件绘出；物件名含「(有才產生)」的玩家安装是条件安装，不安装并写入 unresolved_semantics；story_objects 条目带 `frames`／`frame_draw_origins`／`shape_number`／`shape_delay`／`plane`／`object_fields`／`definition_source`，供 `StoryEffectObjects` 数据驱动地读出效果（level 10）；由 tracked seed／manifest 生成 story-only 场景 `content/battles/story_058.json`／`story_060.json`／`story_008.json`／`story_009.json`（level 8／9 五个命名玩家槽，`actSetNextPlayLevelEvent N,gameBigMapLevel` 解析为 `[N,49]` 回大地图；完整过场的下一关未注册时 spec 可给 `end_card`＋`end_exit` 以卡片回大地图而非重开战役），以及战斗关 53／1／2／3 的开场预览 `story_053.json`／`story_001.json`／`story_002.json`／`story_003.json`（level 2／3 的 `end_exit` 回大地图；有 `leonard` 时以他为 `player_unit_id`；level 3 四个命名玩家槽）（止于首次控制点的「尚未重製」卡片；level 1 用 `player_installs` 把命名玩家 token `SID_雷歐納德`／`SID_琥` 绑到 EVEF 的两个 player_install）（`hsl_story_scene.v1`：EVEF cast 绑定、编译 timeline、对白证据、逐关 actor／肖像／音效／脚本物件、`next_level_event`）；`--check` 在 `verify.sh` 运行。
- 战后剧情段 55／56／61／62／63／64（winfail002 `2,55`→STORY055 `2,56`→回图；winfail003 `61,61`；winfail006 `6,62`→STORY062 `6,63`→回图；winfail007 `7,64`）以独立 story level 走 58／60 的同一数据链：`python3 tools/hsl.py generate battle_seed:N`（55／56 有自有 640×480 `shape41\levelNN.SHP` 营地图；`MAP_ALIASES` 现为 `{level: {map_level, evidence}}`，61／62／64→55（同一份 20×15 WRD、EVEF 同样放置 火01 与 夜晚聲；黄昏／清晨营地的选择为 provisional，另一候选 56）、63→58（WRD 与 58／60 逐字节相同，克里歐司 说话））、`hsltools/levels/sounds.py`（`script_wav_refs` 现也收 EVEF 放置物件字段里的 WAV：夜晚聲 NIGHT001／鳥聲 YELL010）、`hsltools/levels/source_texts.py`、`hsltools/levels/timeline.py … --check` 与 `PYTHONPATH=tools python3 -m hsltools.levels.timeline TIMELINE --source-script story0NN`、`hsl_chapter_dialogue.py --level N`／`python3 tools/hsl.py generate message_text_evidence_check:N`、`hsltools/levels/map_objects.py`（`mapobjPlayBGSound` 的 EVEF 放置物件导出为 `background_sound` role，运行时不绘其 I_RECT01 标记）、`hsltools/levels/actors.py`、`python3 tools/hsl.py generate story_scene:N` → `content/battles/story_0NN.json`（`next_level_event` 原样保留脚本参数；63 的 actShapeMessage 五句为 coordinator 记录型 token）。campaign 注册与「略過戰鬥→續播」路径由 presentation 线接线。
- level 901（菲納斯河畔伏擊：winfail010 胜利段 `actBMSetPointEvent 8,901,bmpmGeneral` 把大地图点 8 改为进 901，所以战斗关 901 是廢墟战后再到 菲納斯河畔 的伏击）以 battle_opening_preview 走同一数据链（`--level 901` 逐工具）：`hsltools/levels/seed.py` 的 `MAP_ALIASES[901]` → level 8 地图（PAK 无任何 level901 shape；`level901.wrd` 与 `level008.wrd` 逐字节相同，且 `obj-901.obs` 的 `地圖管理員`（`defProcIconBG`）记录直接命名 `SHAPE01\LEVEL08.SHP`——该记录在有自有地图的关卡都命名自己的地图、在 60／61–64／66 分别命名 LEVEL58／LEVEL55，是 resource-derived 的关卡→地图表；引擎读取该记录的 loader 未定位，别名仍标 provisional；build 现按此记录校验 `MAP_ALIASES`，不一致即报错）、`level901.png` 与 `level8.png` 像素相同按工具惯例保留同一字节；`hsltools/levels/timeline.py` 加 `story901` profile（首事件 `opening_music`，对白 1139／1140／1141）；`hsl_chapter_dialogue.py` SPEAKER_IDS[901]（五个 EXTRAS.H 槽位＋023／024 沿用 376／377 惯例、031 保留 306「???」；obs 的 `obj_Data5 = 977 兵隊長` 记为未解释的候选标签）；`hsltools/levels/actors.py` cast 001–005·023·024＋winfail 插入的 027·030·031；`python3 tools/hsl.py generate story_scene:901` → `content/battles/story_901.json`（结束卡回大地图点 8；`skip_battle` 自动写出胜利段 `[8,49]` 与 7 条城镇／大地图写入；配乐表解析器对 level ≥ 100 返回 -1，槽位以《席達鎮對峙》provisional 填补；WORD901 实为「狙兵／SNIPER」）。campaign 注册与运行时接线由 presentation 线负责。
- 特别关 902／903／904（支线替代战斗：TOWNDEF 命運神殿 event 53 `teBMSetPointEventNotVisit 17,902` 在 艾瓦台地 未访问时把点 17 改为进 902；winfail021 胜利段 `actBMSetPointEvent 24,903,0` 把 哈莫特沙漠 点 24 改为进 903；winfail902 胜利段 `actBMSetPointEvent 19,904,0` 把 利魯瑪山地 点 19 改为进 904）以 battle_opening_preview 走 901 的同一数据链（`--level 90N` 逐工具）：三关都无自有 shape，`hsltools/levels/seed.py` 按 `obj-90N.obs` 地圖管理員 记录解码 LEVEL17／Level24／LEVEL19（SR-075 绑定表已含三关，resource-derived；`level903.wrd` 与 `level024.wrd` 同字节、`level902.wrd` 与 `level017.wrd` 同字节、`level904.wrd` 比 `level019.wrd` 多 12 个阻挡格，`obj-904.obs` 与 `obj-019.obs` 同字节）；`hsl_chapter_dialogue.py` 的 section title 成员改为读 `actShowSectionName` 实参（903／904 复用 WORD024／WORD019，PAK 无 WORD903／904；902 有自有 WORD902「尋／SEEK」；既有关卡重建逐字节相同），SPEAKER_IDS［902］五槽＋嚎、［903］八槽＋024／053 克羅蒂→8／054 塔克斯→650、［904］七槽＋041→306；`hsltools/levels/timeline.py` 加 `story902`（38 事件，对白 1422–1426）／`story903`（43 事件，1628–1632）／`story904`（39 事件，与 story019 同链）；`hsltools/levels/actors.py` cast 902＝001–005·007＋035–038、903＝level 24 阵容（winfail 到场的 049／053／054 不入 cast，同 24）、904＝001–007＋038／041／043；`python3 tools/hsl.py generate story_scene:902|903|904` → `content/battles/story_90N.json`（结束卡回大地图点 17／24／19；`skip_battle` 自动写出胜利段：902 `[17,68]`＋3 条大地图写入（19→event 904、17→519、ratio 40；`actAddOverScore`／嚎 入队／通行證 281 不施加）、903 `[24,49]`＋2 条、904 `[19,69]`＋6 条（薛維斯港 event 41 子项 133 而非 19 的 130）；配乐表解析器对 level ≥ 100 返回 -1，槽位以各自基底关的重制曲《戈爾山道》《弃卒・守望》《巴瀚納海峽→席達鎮對峙》provisional 填补；咕嚕(有才產生) 按既有政策不安装）。campaign 注册、运行时接线与 story_corpus 重建由 presentation 线负责。
- 随机遭遇战 501–578（大地图已访 General 点按 ratio 掷中进 `点事件 + 0..2`）：`python3 tools/hsl.py generate battle_seed:5NN`（`ENCOUNTER_RANGE`：obj-5NN.obs 地圖管理員 命名基底关地图；level5NN.wrd 与基底 WRD 同 sha256 时 seed 直接引用基底的 `level0NN_terrain.json`，解码地图与基底 PNG 像素相同时引用基底 PNG——`shared_packet_of_level`／`shared_png_of_level`，525–527 的 WRD 与 19 不同则各自落文件；OBJ-ALL.H 作头的关只保留脚本插入的 `script_objects`，seed 约 40 KB）→ `hsl_chapter_dialogue.py --level 5NN`（共用 `ENCOUNTER_SPEAKERS`：只有 雷歐納德 死亡讯息 741 与胜负 121／122）→ `python3 tools/hsl.py generate opening_timeline_compile:5NN`＋`python3 tools/hsl.py check opening_timeline_check:5NN`（`ENCOUNTER_PROFILE`：default_level_music→delay→dead message→win／fail status→board）→ `python3 tools/hsl.py generate level_map_objects:5NN`（云／柱等站立物件，共享 sprite 池）→ `python3 tools/hsl.py generate level_actors:500`（一次性演员池 `battle500/`：001–009 全队＋78 关全部怪物码，遭遇战场景都引用它）→ `python3 tools/hsl.py generate level_battle:5NN`（`ENCOUNTERS` profile；`build_encounter`：EVEF 装位 obj_Data9 槽位→受控槽（`install_if_carried`，并按 EXTRAS.H 名 token 写入 `opening.actor_bindings["SID_<名>/1"]`，否则 WINFAIL5NN 的 `actCheckPlayer 1 SID_雷歐納德` 无法解析、遭遇战永不失败——见 [original_check_targets.md](../docs/evidence_packets/static_reverse/original_check_targets.md)），obj_Data7→怪物模板；`ENCOUNTER_PARTY_SLOTS` 列可上场的槽，其余记 `conditional_party.unavailable_slots`）→ `content/battles/battle_5NN.json`；campaign.json 每关一行（无 kind）。501–578 全部已组装注册（seed 共享逻辑按 `MAP_ALIASES` 解析贴图归属：549–551 名 Level32.SHP 而该图跟踪在 battle033/，故与 033 共享；标题由大地图点 `name_text`＋「遭遇戰」派生；基底关为正式战斗时 `base_scenario` 取其 `battle_00N.json`，故基底关转正式后要重建对应遭遇关）；`ENCOUNTER_PARTY_SLOTS` 为 001–007／009（需模板＋共享肖像＋面板标题三者齐备），008 因源武器 range 3CellCircle 初始化拒绝而 unavailable；面板标题表 `shared/panels/manifest.json`（`hsltools/assets/panel_assets.py`）与共享肖像 `portraits/manifest.json`（`hsltools/assets/portraits.py`，`hsl generate actor_portraits`）均已覆盖 39 名演员。
- 第二章战斗关开场预览 13／15／17／18／19／21／22／24（龍之息 火山／深淵之沼／艾瓦台地／那可那魯邊境／利魯瑪山地／回音之谷／尼布魯瀑布／哈莫特沙漠，自有 `shape11|shape21\LEVELnn.SHP`；`obj-NNN.obs` 的 `地圖管理員`（defProcIconBG）记录直接命名各关地图）与营地 story-only 关 66／67／68／69（STORY065 `9,66`；winfail017 `17,67`；winfail902 `17,68`——TOWNDEF 命運神殿 event 53 `teBMSetPointEventNotVisit 17,902` 装配的 level 17 变体；winfail019／904 `19,69`）走同一数据链 → `content/battles/story_0NN.json`：66–69 的 `MAP_ALIASES` →55 以 `地圖管理員` 命名 `SHAPE41\LEVEL55.SHP` 为主证据（resource-derived，20×15 WRD 仅 (9,3) 一格与 055 不同，EVEF 同置 火01／夜晚聲；loader 未定位仍留 provisional 尾注）；配乐按原表 `0x477b44`（13→15 廢都雨夜、15／17→12 戈爾山道、18→18 逃出克萊恩城、19／22→17 席達鎮對峙、21→14 盜賊洞窟、24→19 弃卒・守望，`actPlayMusic 9`→巴瀚納海峽、`8`→王座廳）复用既有重制曲；19 唯一玩家槽为 雷特（`player_unit_id: rett`）；18 的 門1（Enemy100，静态 shape）与 `obj_Story_Level_Door` 插入只记录不绘；13 的 `actWalkDispWait,-1` 指向前一插入物件；「(有才產生)」槽（咕嚕／克羅蒂）不安装，脚本对其的走位／对白记入 unresolved。
- 第二幕战斗关 26／28／29／30／31／32／33／34（开场预览，`battle_opening_preview`＋`end_exit` 回图，`opening.skip_battle` 由 winfail 胜利段编出：26→`26,gameBigMapLevel`＋6 写入、28→`28,gameBigMapLevel`＋4、29→`29,70`＋2、31→`31,71`＋2，30／32／33／34 无 next level 只 `actSetBMWalkToPoint` 等 5／6／5／14 写入）与 story-only 段 70（winfail029→70，营地）、71（winfail031→71，王座廳，STORY071 无 `actSetNextPlayLevelEvent`，以 `end_card`＋`end_exit` 回图）、72（沙羅尼亞酒館 te 167 `35,72`，自有 `shape31\level72.SHP`）走同一数据链：`MAP_ALIASES` 以 obj-NNN.obs 地圖管理員（defProcIconBG）记录为主证据——32→33、33→32（各自有 shape 但 WRD 网格只与对方 shape 相符）、70→55、71→58（resource-derived，loader 未定位仍注 provisional）；`hsltools/levels/story_scene.py` 新增 spec 键 `unresolved_notes`（逐关边界句）、`lead_unit_id`（34 由 緹娜 领队），EVEF 敌物件 shape 前缀与 obj_Data7 不同时按 shape 绑定走路帧并记 `source_actor_code`（Enemy053(克羅蒂) 穿 009）；配乐按 EXE 表 0x477b44 复用既有 track 曲（26 8→12、28 13、29 16＝level 52 曲、30 14、31 9→13、32 19、33 8→18、34 9→17、70 9、71 8），72 的 track 10 无重制曲以王座廳曲 stand-in。
- <!-- lane ch2c --> 第二章战斗关 36／37／38／39／40／41／43／44／45（薩魯司海岸／古代神殿遺跡／幽闇墳場／黃昏之丘 陽／聖靈之森／悲嘆之湖／大地的裂縫／亞修頓大橋／克萊恩城）开场预览与 story-only 过场 74（斐達克旅館：TOWNDEF 事件 178 `teSetNextPlayLevelEvent 42,74`，末尾 `42,gameBigMapLevel` 回图）走同一条数据链 → `content/battles/story_0NN.json`：全部自有 `shape31\levelNN.shp`／`shape41\levelNN.shp`（obj-0NN.obs 地圖管理員 记录命名同一 shape，resource-derived，无 MAP_ALIASES）；九槽队伍按 EXTRAS.H → obj_Data9 → PLAYERS name_N 解析，「(有才產生)」咕嚕／克羅蒂不安装并记 unresolved（story-only 关也记）；LEVELS spec 现可自带 `unresolved` 句子；`INSERT_ACTIONS` 增加 actInsertObjectRandomPos／actInsertStoryObjectRandomPos／actInsertStoryObjectXRange（STORY037 五个随机槽的 白光／守护者、winfail039 的 obj_Story_Block），随机槽本身只作记录型 token；配乐按 0x477b44 表复用既有原创曲（36·45→13 村落警報、37→14 盜賊洞窟、38→15 廢都雨夜、40·43→16 惡夢的終曲、41→17 席達鎮對峙、44→18 逃出克萊恩城，36／37／41／74 的 actPlayMusic 9→巴瀚納海峽），39 的 track 11 尚无重制曲、以 戈爾山道 stand-in（provisional）；`opening.skip_battle` 由 winfail 首个 win 段写出（38→`80,80`、41→`41,73`、45→`75,75`，其余回图同号点）。campaign 注册与运行时接线由 presentation 线负责。 <!-- end lane ch2c -->
- <!-- lane ch3 --> 终章链：战斗关开场预览 73（悲嘆之湖・兄弟的抉擇，winfail041 胜利 `41,73`）／75（自覺與宿命：塔克斯，winfail045 → `75,75`）／76／77／78（最終的序曲／破滅的命運／接觸：三场终战，由 STORY057 的 `actSetNextPlayLevelGetOverEvent 0` 按 over-score 选择）／79（終焉：咕嚕最終型態，winfail078 event 2 → `79,79`）／80（禁忌之魂：墳場地下，winfail038 → `80,80`）／59（劫數：地劫神，STORY081 → `59,59`）与 story-only 过场 57（塔克斯之死，winfail075 → `57,57`）／81（妖精王的告白，winfail076 → `81,81` → 59）／82（終幕，winfail077 → `82,82` → `90,998`）走同一数据链 → `content/battles/story_0NN.json`：`MAP_ALIASES` 以 obj-0NN.obs 地圖管理員 记录为主证据——73→41（WRD 逐字节相同）、75→57（同 30×22 网格，250 字节差）、76／77／78／79／81／82→58（六关共享一份 30×22 变体，与 058 差 34 字节；resource-derived，loader 未定位留 provisional 尾注），57／59／80 自有 `shape41\level57／59.SHP`／`shape31\Level80.SHP`；`hsl_story_scene._select_event_timelines` 把分支尾部 `actInsertEventStatus N`＋`actExecWinFailProcess` 命名的无条件（actTRUE）event N 追加进该分支（`chained_event_codes`；73 两支都接 event 2 的 斐達克 写入与 `41,gameBigMapLevel`；900 字节不变）；`_skip_battle` 无 win 段时改用带 `actSetNextPlayLevelEvent` 的战斗时 event 段（78 → `79,79`；actTRUE 尾段不算，73 无 skip_battle）；STORY `actInsertObject` 的非步行 shape（59 魔神 `SHAPE\60-10001`）不绑演员、由 map_objects 静态 script object 绘出；`LEVEL_CASTS[73]` 的 `shape_sets.fallen` 解码 056-P 倒地帧，80 的 068 怨念（`SHAPE\68-001`）为 `static_enemy_object`；配乐按 0x477b44 表复用既有原创曲（75→17 席達鎮對峙、76→13 村落警報、77→18 逃出克萊恩城、78→16 惡夢的終曲、79／80／59→14 盜賊洞窟、73 actPlayMusic 9→巴瀚納海峽），57／81 的 actPlayMusic 10 与 82 的 actPlayMusic 4 无重制曲、以 王座廳 stand-in（provisional）；`90,998` 的 998 为 PAK level998 GameClear 谢幕画面（obj-998.h `obj_gameclear*`，resource-derived，未重制），82 以无 end_exit 的 end_card 结束，79／59 的 skip 目标未注册；57／81 的 actEnterStorageWindow／actKeepPlayerST／actSetNextPlayLevelGetOverEvent 只记录。campaign 注册与运行时接线由 presentation 线负责。 <!-- end lane ch3 -->
- `python3 tools/hsl.py generate|check level_actors:1|2|3|53|58|60`（53 另解码 actChangeShape 攀绳帧集到 `actor_shape_sets/`）／`python3 tools/hsl.py generate|check level_map_objects:1|2|3|53|58|60`：逐关 actor 走路帧／肖像／音频 manifest 与脚本物件（徽章 `AIR06_04.SHP`）预览，只引用共享资源、不改共享 manifest；脚本物件只导出本关脚本实际插入的符号（共享头 OBJ-007.H 定义的数百个 UI／未用物件不再导出），角色 `other`／`map_object` 皆可，`obj_Shape_Number>1` 的按数字后缀导出整段帧（`FIR03_01..03`、`10_RAIN001..003`），PAK 缺帧处截断、缺主 shape 的列入 `skipped_script_objects`；EVEF 敌方进程物件若 shape 无 SHAPEDEF 步行组则作 `static_enemy_object` placement 导出（`tools/hsl_actor_walk_manifest.is_walking_shape`）；EVEF `寶藏`（`defProcTreasureBox`，`SHAPE\BOX0001.SHP`）作 `treasure_box` placement 导出为关闭宝箱（level 1／2／3／5／6／7／10／12；开箱／拾取未重制）；带组合物件表的关卡（level 1 的「树／房＋影」）另输出 `combined_placements`（EVEF 锚点＋子偏移候选），运行时 `BattleSceneRuntime._map_object_stand_records` 与普通站立物件一并放置；`presentation_hint.blend` 为 add／glass／mix（`engGLASS` 云影在运行时读为半透明）；`runtime_layer_hint` 含 `backdrop`（`mapobjMoveBG` 移動背景，画在地图底图之下）。
- `hsltools/data/scope_inventory.py [--check [--rescan]]`：扫描原 PAK 统计主线／500 段／900 段关卡、STORY／WINFAIL 脚本、actMessage 与全局表记录数，并对照 `campaign.json` 注册的重制覆盖，写 `content/generated/hsl/static/hsl01/scope_inventory.json`；`--check` 离线核对重制侧与内部总数（`verify.sh` 运行），`--rescan` 才重读 PAK。口径见[范围盘点](../docs/evidence_packets/resource_inventory/original_scope_inventory.md)。
- `hsltools/data/world_map.py [--check]`：读原 PAK 的 `bigmap.dat`（45 点／44 线记录）、`TRACK.TXT`＋`TRACK.H` 折线、`RESOURCE.TXT` 点名、`extras.h` 12 个 `town_*`、`TownBG*.SHP`／`BigMap.SHP`／`m_pnt00N.SHP`／`m_trk0NN.SHP`／`Status_Bar.SHP` 预览（含 draw_origin），写 `content/imported/hsl/global/world_map/world_map.json`（`hsl_world_map.v1`）；同目录 `towndef.json`（`hsl_towndef.v1`）为 `TOWNDEF.TXT` 的 `[item]`／`[town_event]` 记录、te token 对照 `TOWNDEF.H` 与消息 id 清单。`--check` 有 PAK 时重生成比对，无 PAK 时只做离线一致性（`verify.sh` 运行）；单测 `test_hsl_world_map.py`；结构与未解语义见[世界地图数据](../docs/evidence_packets/static_reverse/world_map_data.md)。
- `hsltools/data/big_map_flow.py [--check]`：扫描原 PAK 全部 `story*.txt`／`winfail*.txt`，只抽取关卡／大地图／城镇流转指令（`actSetNextPlayLevelEvent`、`actBMSetPointEvent*`、`actBMSetPointEncounterRatio`、`actBM*Flag`／Mode、`actSetTownExecEvent`、`actAddTE` 等 17 个）按脚本与段落输出到 `content/generated/hsl/static/hsl01/big_map_flow.json`（symbol 取 `towndef.json`／`world_map.json` 的 extras.h／TYPE.H 读法：`gameBigMapLevel=49`、`town_*`、`bmpm*`），并推导 `level_return_points`（`N,gameBigMapLevel` 的回图点）、`battle_return_point_equals_level`（主线战斗 17/17 回到同号点）、`encounter_return_matches_assigned_point`（5xx 遭遇关 28/28 回到脚本指派的点）与 `post_clear_visit_writes`；`--check` 离线复推导。resource-derived 脚本惯例，不是 EXE 到点／进关 handler 的证明。
- `hsltools/assets/town_assets.py [--check]`：从 tracked `towndef.json` 收集 te 对白／名字／菜单标签引用的 RESOURCE.TXT 文本（`town_messages.json`，含 SID_* 玩家说话者→PLAYERS 肖像的 provisional 映射）与 teShapeMessage 等指名的 FACE*.SHP 肖像（`town_portraits.json`，`hsl_actor_portraits.v1` 兼容，PNG 在 `previews/faces/`）；`--check` 有 PAK 时重生成比对，无 PAK 时离线一致性。
- `hsltools/data/secret_man_goods.py [--check] [--exe hsl01.exe]`：从 SHA 锁定的原 EXE 读出酒館神秘男子的 9 行价格／15 槽货表（`.data 0x4793b0`）与宣传事件表（`0x479398`）写入 `content/generated/hsl/static/hsl01/secret_man_goods.json`；`--check` 有 EXE 时逐字节比对，无 EXE 时做离线交叉核对（价格递增且等于宣传词 1608–1616 的 `$N`、code 全在 ITEM.TXT）。读法见[原作酒館神秘男子](../docs/evidence_packets/static_reverse/original_secret_man.md)
- `python3 tools/hsl.py check content:player_copy_traditional`（`hsltools/checks/player_copy_traditional.py`，family content，纯校验）：玩家看得见的字串里不得有简体字——`game/**/*.gd` 非注释代码行的字串字面量（`assert`／`push_error`／`push_warning`／`print*` 行是开发者文案，不算）、`game/**/*.tscn` 全部字串、`content/battles/**/*.json`、`content/authored/**/*.json` 与原文语料（`message_text_evidence.json`、`story_corpus/scripts`、`town_messages.json`、面板／标题 manifest）中 `title`／`name`／`name_text`／`display_name`／`label`／`message_text`／`speaker_name`／`text` 及 `result_labels`／`messages`／`speakers` 下的值；判据是模块内明确列出的简→繁差异字表（`SIMPLIFIED_TO_TRADITIONAL`，只收「是另一繁体字的简化、自身不在繁体通用」的字，后／云／里／干／系／采／症／伙／痴 等有意不收）加 `SIMPLIFIED_WORDS`（游玩→遊玩 这类字面全为繁体自有字的词），不做任何猜测；原作语料同在扫描范围，命中即字表缺陷。失败行给出 `简→繁` 修法。
- `python3 tools/hsl.py check town_job_up_writes`（`hsltools/checks/town_job_up_writes.py`，纯校验）：`content/world/town_job_up_writes.json`（`hsl_town_job_up_writes.v1`，`teCheckJobUp2` 成功后 `0x434680` 的城镇写入：members／town／writes）的 SID_／town_ 符号、te 写入 token 形状与事件号都要在 `towndef.json` 里；回憶錄 预设生成器 `hsltools/data/original_save.py` 直接读同一文件，`original_save:native_second_tier` 把结果钉在原生 `HSL_second_tier_native.SAV` 上（不再有 Python 副本）。消费者 `game/sim/TownEventRules.gd`。
- `hsltools/data/town_initial_trees.py [--check]`：从 tracked `towndef.json` 与原 PAK 全部 STORY／winfail 脚本的 `actAddTE`／`actDeleteTE`／`actSetTown*ExecEvent` 引用生成 `content/world/town_initial_trees.json`（`hsl_town_initial_trees.v1`，evidence_tier provisional）：按 TOWNDEF 段头注释归镇、按前缀嵌套酒館子项，排除运行时才加入或只经跳转到达的事件、商店全由脚本加入的城镇与脚本保证的子菜单，每条 entry／excluded 带来源。`--check` 有 PAK 时重生成比对，无 PAK 时离线一致性（`verify.sh` 运行）；消费者 `game/sim/TownEventRules.gd`，读法见[城镇事件读法表](../docs/evidence_packets/static_reverse/town_event_semantics.md)。
- 52／53 关（`battle_052.json`／`battle_053.json`）自 S11 起由 `level_battle:N` 组装：`content/battles/levels/052.json`／`053.json` 的 `battle` 分区用 `unit_ids`（emperor025／ally023_n／enemy021_n…）与 `result_labels`；起始格、增援（`script_actor_templates`）与其他关同一条通用路径（R35 删除了迁移期的 `reinforcements` 落点策略与 052 的四条 `initial_unit_state.coord` 钉格）；052 的两名 069 翼战士（PLAYERS pmPlayer、穿 `SHAPE\022`）按装入读法出场为敌方（EVEF obj_Data9 1 把 pmPlayer 换成 pmEnemy，0x407ec0；原版 (15,14)／(6,13) 站为敌方，runtime-measured）；`hsltools/data/emperor.py`（`emperor_data`）从 PLAYERS 025 经共享 0x448840 刷新写 `content/generated/hsl/actors/025.json`（对照 `second_battle_template_stats.json`）。`hsltools/levels/scenario.py` 只剩装配器共用的 winfail 读法（`SHARED_RESOURCES`／`status_timelines`），不再有逐关 profile 或任务。
- `python3 tools/hsl.py generate|check level_battle:N`：通用正式战斗组装器（首个关卡 6 席達鎮 → `content/battles/battle_006.json`）。输入全部是 tracked 数据：预览 `story_NNN.json`（开场、绑定、资源、EVEF cast）、seed（STORY 开场的插入／走位终点由 `trace_opening` 追踪——`obj_Story_PlayerN` 安装、`actInsertObject`＋`actWalkPrevInsertObject`、绝对／相对走位、删除；winfail 插入符号→`script_actor_templates`；寶藏的 8 个 override words→`content/generated/hsl/treasures/battle_NNN.json`）、来源模板（`first_battle.json` 的 playable_units 与 `content/generated/hsl/actors/*.json`）。角色：`obj_Story_PlayerN` 安装＝player_controlled，PLAYERS `pmNPCPlayer`＝friendly_ai，其余 enemy-process 物件＝enemy_ai（`content/battles/levels/NNN.json` 的 `battle.role_overrides` 可覆盖；逐关知识的分区见 [关卡档案](../docs/architecture/LEVEL_PROFILES.md)，`hsl check level_profile:N` 查结构）。源位置落在重制地形阻挡格时移到最近可用格并记 provisional。`--check` 比对场景与寶藏两份输出。任务按 `content/battles/levels/NNN.json` 的 `battle` 分区（或遭遇战分配）注册，不要求 `battle_NNN.json` 已存在：新关写好 profile 后一条 `python3 tools/hsl.py generate level_battle:N` 即首建场景（未生成前 `check` 报 `not yet written`）。
- `hsltools/levels/source_texts.py`：把某关的 STORY/winfail/obj 头文件原始文本提升到 `battle<code>/source_texts/`；`--check` 用 seed 摘要核对。
- `hsl_chapter_dialogue.py --level 52`：从原包 RESOURCE.TXT 生成 level 52 的 message evidence 与 WORD052 标题图；message id 来自 seed 脚本。
- `hsltools/levels/source_texts.py`：把某关的 STORY/winfail/obj 头文件（以及存在时的 LEVEL<code>.H）原始文本提升到 `battle<code>/source_texts/`；`--check` 用 seed 摘要核对。
- `python3 tools/hsl.py generate battle_seed:N`：脚本 `actInsert*Object` 引用而本关 `obj-NNN.h` 未定义的符号（`obj_Effect_FireBomb`、`obj_Story_Block`、`obj_Story_PlayerN`）另按 `OBJ-ALL.H`／`global.obs` join 并标 `definition_source`（未用到全局表的关卡 seed 字节不变）；joined 脚本物件记录 `shape_number`／`plane`／`shape_delay`；地图 PNG 像素未变时保留 tracked 文件（避免编码器差异搅动多 MB 文件）；地图 shape 按两位关卡号在章节目录 `shape01`／`shape11`／`shape21`／`shape31`／`shape41` 中定位（level 12／13／15 在 `shape11`）；EVEF 放置坐标按有符号 32 位读取（level 3 的玩家槽在地图西缘外 x = -64／-96／-128）；EVEF 全表不截断；BIN 尾部组合物件表（level 1／2／22 等）解码为 `combined_objects`，带 `0x80000000` 旗标的 placement 按槽位 join 为 `combined_map_object`。
- `hsltools/data/original_save.py --state <preset> --out DIR`／`--dump FILE.SAV`：原版 戰場記錄／回憶錄 文件的逐字节编解码器（`_original_save_codec.py`：0x45b016 LZW 变体＋0x42e040 校验和）与 回憶錄 生成器——从 tracked 样本 `docs/evidence_packets/static_reverse/original_save_format/HSLBAT_first_control.SAV` 出发，按剧情顺序重放脚本对存档表的写入、用运行时 dump 的 PLAYERS 模板（`original_save_members.py`：模板复制→`0x4348f0` 转职交换→`0x448840` 刷新，队员用 carry 词汇 `actor_id`／`level`／`attributes`／`inventory`／`job_up_history` 描述）合成任意成员的 live 记录、写大地图头部，产出 `content/generated/hsl/development/original_saves/<preset>.SAV`＋回执 JSON；装到 `<hsl>/SAVES/HSL00.SAV` 后用 讀取回憶錄 载入。注册任务 `original_save:sample`（样本 round-trip 与摘要 JSON）、`original_save:members`（模板 dump 对 PLAYERS.TXT／职业模型／资源句柄规则逐字段核对，合成 001 与样本 live 记录逐字节相同；重建需 `HSL_ORIGINAL_MEMORY_DUMP=<memread JSON>` 与原作 PAK）、`original_save:native_second_tier`（原版从 `before_second_tier_at_temple` 原生跑完两次 teCheckJobUp2 后写出的 回憶錄 `HSL_second_tier_native.SAV`，与 `after_second_tier_at_temple` 预设除站位头字外逐表逐字节相同）、`original_save:<preset>`。字段表、句柄规则与 Wine 载入回执见[原版存档格式](../docs/evidence_packets/static_reverse/original_save_format.md)
- `hsltools/data/story_corpus.py [--check]`：把 PAK 全部剧情脚本一次压成 tracked 语料 `content/imported/hsl/story_corpus/`（`index.json` `hsl_story_corpus.v1` 逐脚本一行：family story／winfail／storyover／towndef、编号、member／sha256、行数、action_counts、消息 id／已解析／缺文本计数、SID 令牌、`actSetNextPlayLevelEvent` 边（含 `gameBigMapLevel`）、未被 `hsl_opening_timeline_compile.ACTION_KIND` 覆盖的 opcode；`scripts/<FAMILY><nnn>.json` 存 `_compact_script` 形状的 actions 与逐条消息 `{id, sid_token, speaker_name?, text}`，speaker_name 只在 `hsl_chapter_dialogue.SPEAKER_IDS` 有该关表时给出）。解析全部复用 `hsl_payload_inspector.parse_text_metadata`／`hsl_battle_seed._compact_script`／`hsl_chapter_dialogue`／`hsl_world_map.parse_towndef`，不含第二套脚本解析器；`--check` 有 PAK 时内存重建逐字节比对、无 PAK 时离线一致性，并始终与全部 tracked `message_text_evidence.json` 逐字比对（`verify.sh` 运行）；单测 `test_hsl_story_corpus.py`；计数与边界见[全剧本语料](../docs/evidence_packets/resource_inventory/original_story_corpus.md)。只恢复文本与动作顺序，不含时序／分支条件／镜头。
- `hsltools/data/campaign_overview.py [--check]`：从 `campaign.json` 与场景文件生成 `docs/evidence_packets/resource_inventory/campaign_overview.md`（每个注册关卡一行：类型／地图／结束去向／視為勝利去向／状态），改剧情或注册关卡后重跑；`--check` 在 `verify.sh` 运行。
- `hsltools/data/story_token_coverage.py [--check]`：扫描 PAK 全部 `STORY*.TXT` 与 `DATA\ACTION.H`，写 `content/generated/hsl/static/hsl01/story_token_coverage.json`（每 token 使用关卡数／编译器 kind、每关未映射列表、总计）并把 `ACTION.H`／`EXTRAS.H` 提升到 `global/tables/`；`--check` 不读 PAK，核对报告与当前 `ACTION_KIND` 一致。 `tools/test_hsl_story_token_coverage.py` 另核对每个编译器 kind 在 `BattleOpeningCoordinator.gd` 中有分支或列入 `RECORD_ONLY_KINDS`；协调器合同见 [表现合同](../docs/architecture/PRESENTATION.md#extended-story-tokens)。
- `hsl_chapter_dialogue.py --level 52`：从原包 RESOURCE.TXT 生成 level 52 的 message evidence 与 WORD052 标题图；message id 来自 seed 脚本（含 `actMessageIfExist` 的备用 id 与 `actShapeMessage`）。`--level 1` 使用 `SID_雷歐納德`／`SID_琥` 等 EXTRAS.H 别名 profile。
- `hsltools/checks/generated_metadata.py`、`hsltools/checks/imported_content.py`、`hsltools/checks/imported_script_ir.py`：检查 tracked importer 结果。
- `hsltools/assets/item_art.py`：从原包导入共用药包类别与物品格；`--check` 离线核对 ITEM 类别、图片尺寸与哈希。
- `hsltools/assets/combat_animation.py`：ANIMAL 原始动作帧、延迟与锚点；独立记录原始 k_action 和 sprite_facing，不混用两者。程序源 `combat_animation/ANIMAL.TXT` 归 `animal_programs` 任务导入（`generate` 先从 PAK 复制成员再编译 `animal_programs.json`；`check` 只读 tracked 文件，源经 JSON 的 sha256 钉住），`combat_animation` 读这份 tracked 副本与编译后的 JSON、只写 manifest／background／逐演员目录（PAK 成员与 tracked 不同即拒绝）；三条追加导入任务 `ohm_assets`／`priest_assets`／`mobile_jobs_assets` 声明的输入只有这两份，读写自己的输出（manifest 追加）不算另一任务的产物——文件级依赖因此无环，`hsl generate '*'` 按 inputs∩outputs 排全库。共享 manifest（全关共用一份，不逐关复制）现含 47 名来源演员＋上位形态行 010–017／019／020（`UP_TITLE_ACTORS`，SID_PLAYER9–19 → P0xx；018 有块与 PAK 帧但 SHAPEDEF 走行行被注释，故不导入）；`--actors` 只追加选定演员并保留已审核素材；时间线／hurt_frame 由绑定的 ANIMAL 程序推导；`SPECIAL_FRAME_ACTORS`（001／003 与有 s_shape 的上位行 010／012／013／016／017／019／020）导入 `special_frames`——上位行为 3 帧三面板条，构图与 001／003 面板不同，运行时绝技表现仍取基础行（`BattleCombatCutin.special_frames`）；`MAGIC_FRAME_ACTORS`（有 m_action 且有战斗行的 16 行：002／005／006／009／053 基础行、010／011／014／015／019／020 上位行、025／056／058／059／060 魔物）导入 m_shape 条 `magic_frames`（69 张）并绑 `magic_cast_program`，地图法术 presenter 以 `AnimalCastLead` 播放；018／068 无战斗行、其余行无 m_action，`magic_frames: []`（`magic_frames_policy`／`magic_cast_program_policy`）。新增 32 名与上位行的 sprite_facing 为 provisional（未经视觉审核，运行时不消费）。
- `hsltools/data/skill_coverage.py`：全部源技能的可施放覆盖表 `content/generated/hsl/skills/coverage.json`（每个技能：学习者与等级、`SkillResolutionRules` 判定 ok／unknown_skill、原表字段），`--check` 入门禁；接新技能后重跑以更新 supported 计数。
- `hsl_wrd_decode.py`：WRD 地形解析。
- `hsltools/data/winfail_coverage.py`：扫描本机原版 PAK 全部 `winfail*.txt`，按关卡输出 token 集合与 `game/sim/WinfailCompiler.gd` 常量支持集的差集到 `content/generated/hsl/static/hsl01/winfail_token_coverage.json`（`fully_supported`／`fully_applied`、主编号 <100 战斗关计数、阻塞 token 排名）；`--check` 只用 tracked 报告与当前 GDScript 常量复核，不读 PAK，已进 `verify.sh`；单测在 `test_hsl_data_tasks.py` 的 winfail_coverage 段。 同文件的任务 `winfail_token_table`（`hsl generate|check winfail_token_table`）把词表常量的 token 行注释、`ACTION.H` 参数形状与 tracked 出现次数渲染成作者可读的 [docs/WINFAIL_TOKENS.md](../docs/WINFAIL_TOKENS.md)；token 缺语义注释即 check 失败。
- `hsltools/levels/seed.py`：从本机原版 PAK 按关卡号读取 STORY/WINFAIL/EVEF/WRD/OBJ/map SHP，提升为 compact battle seed、terrain packet 与 map PNG；raw PAK record 不进仓库。`--check` 只核对 tracked 输出，不依赖 Wine/原版安装。

### 输出规则

- raw 提取、静态导出、trace、截图：`ignored/`
- 可复用导入资产：`content/imported/`
- compact 机器事实：`content/generated/`
- curated 原作证据：`docs/evidence_packets/`
- 新工具必须有 `test_hsl_*.py`、checker 或可执行 `--help`/`--dry-run` 验证。

## 二、贡献者

| 脚本／任务 | 用途 | 入口命令 |
| --- | --- | --- |
| `lane_verify.sh` | lane 工作期间的定向验证（命中的检查、Python 测试与 Godot 套件） | `tools/lane_verify.sh affected BASE` |
| `lane_merge.sh`／`merge_curation_json.py` | 负责人合并 lane：合并、合并树门禁、快进、清理；curation JSON 三方合并 | `tools/lane_merge.sh merge`（再 `gate`、`publish`、`cleanup`） |
| `godot_cache_seed.sh` | 从另一份 checkout 克隆 Godot 导入缓存 | `tools/godot_cache_seed.sh --auto` |
| `hsl_docs_check.py` | 文档显式链接、图片、标题锚点 | `python3 tools/hsl_docs_check.py` |
| 任务 `docs:tool_references` | 文档代码里的工具路径、模块、任务名都存在 | `python3 tools/hsl.py check docs:tool_references` |
| `oss_export.sh` | 组装公开仓库树（不推送） | `tools/oss_export.sh OUT_DIR [REF]` |
| `oss_sync.sh` | 公开仓库跟随 main：导出→复扫（个人路径、公开截图外的媒体）→提交→推送；`lane_merge.sh publish` 推 main 后自动调用 | `tools/oss_sync.sh [REF]`（`HSL_OSS_PUBLIC_DIR` 指公开仓库检出） |
| `oss_screenshots.py` | 公开导出的截图计划与链接改写 | `python3 tools/oss_screenshots.py summary` |
| `oss_audit_stats.py` | 开源审计：逐文件分类统计 | `python3 tools/oss_audit_stats.py [REF] [--migration]` |

### 流程入口

```sh
tools/godot_cache_seed.sh SRC|--auto [DST]  # 从另一份 checkout 克隆 .godot 与 *.import；godot.sh 缺 .godot/imported 时自动 --auto（取最近成功导入的工作树），手动很少需要
tools/lane_verify.sh affected BASE [SUITE...]  # lane 工作期间：hsl affected --since BASE --check ＋ 改动命中的 test_hsl_*.py ＋ 命中的 Godot 套件（套件自身改了，或经 res:// 路径／class_name 直接或经 tests/support 引用了改动的 game/、tests/support 脚本；改了战斗场景只扫那几关；一次一个 Godot 进程；命中场景套件超过 12 个时改提示跑 fast）＋ 改动 .sh 的 bash -n；环境内置（PYTHONDONTWRITEBYTECODE、HSL_VERIFY_JOBS=3；不设 HOME：Godot 套件本就各自独立 HOME），全日志 ignored/lane-verify/，终端只出结果行与失败块，末行 LANE_VERIFY_PASS|FAIL
tools/lane_verify.sh fast  # lane 报告前那一次快门（同一环境，排 verify 共享槽）
tools/lane_merge.sh merge|gate|publish [--dry-run]|cleanup  # 负责人合并 lane：合进 pipeline-line（只有生成物冲突时自动重生成）→ 合并树门禁 → 门禁过了才快进 main／presentation-line → 删已合并 worktree；连续几次 merge 只跑一次 gate＝合并火车。publish 先对全部目标预检，任一目标工作树有与将落地文件同名的未跟踪文件（LANE_PUBLISH_FAIL untracked=）、改过这些文件（dirty=）或不能快进（not-ff）就一个都不快进、非零退出；--dry-run 只跑预检；merge 的 git merge／generate／commit 失败各打 LANE_MERGE_FAIL merge|generate|commit
python3 tools/hsl_docs_check.py    # 文档显式链接、图片、标题锚点；不联网
python3 tools/hsl.py check docs:tool_references   # 文档代码里的 tools/ 路径、python3 -m hsltools 模块、hsl check|generate 任务名都存在
```

#### 独立工具

| 脚本 | 用途 | 验证 |
| --- | --- | --- |
| `hsl_docs_check.py` | 文档显式链接／图片／标题锚点检查（`verify.sh` 调用） | — |

- `python3 tools/hsl.py check docs:tool_references`（`hsltools/checks/doc_tool_references.py`，family docs，纯校验）：根目录 `*.md`、`docs/`（不含 `external/`）、`tests/`、`tools/` 的 fenced code block 与行内代码里，每个 `tools/….{py,sh,swift,c,json}` 路径与裸写的 `hsl_*.py` 独立工具名须存在，每个 `python3 -m hsltools.…` 模块须存在，每个 `hsl check|generate|list` 参数须选中至少一个注册任务（`family:N`／`family:5NN`／`family:<preset>` 只要求家族存在，`family:a|b` 逐项检查；选项值、占位符、`#`／`)`／非 ASCII 之后不算参数）。`hsl_docs_check.py` 只查链接，这项补上 T1 消融暴露的盲区（删一个只被文档引用的脚本无人发现）；`content/` 下生成的 README 不在范围（其字串随生成器重生成才变）。

## 三、维护者研究

| 脚本／任务 | 用途 | 入口命令 |
| --- | --- | --- |
| 任务族 `probe` | 有界原生探针证据包：默认离线核对回执，`--execute` 才重跑原指令 | `python3 tools/hsl.py check probe` |
| `hsl_exe_static_export.py`／`hsl_exe_decompile.py` | EXE 静态导出到 `ignored/static/hsl01/`；按地址窄反编译 | `python3 tools/hsl_exe_static_export.py --help` |
| `hsl_script_vm_semantics.py` | 脚本 VM dry-run 语义生成／核对 | `python3 tools/hsl_script_vm_semantics.py --check` |
| `hsl_combat_resolution_probe.py` | 用 r2 复核战斗 instruction anchors | `python3 tools/hsl_combat_resolution_probe.py --exe EXE` |
| `hsl_native_animal_probe.py`／`hsl_native_growth_probe.py`／`hsl_native_growth_refresh_probe.py`／`hsl_native_level_probe.py`／`hsl_native_map_scroll_probe.py`／`hsl_native_presentation_probe.py`／`hsl_native_stats_probe.py` | 旧式原指令有界仿真（需 unicorn） | `uv run --with unicorn==2.1.4 python tools/hsl_native_growth_refresh_probe.py --check` |
| `hsl_opening_choreography_packet.py` | 生成开场 choreography 证据包 | `python3 tools/hsl_opening_choreography_packet.py --help` |
| `hsl_original_control.py`／`hsl_win32_control.c` | Wine 内部单步输入＋cnc-ddraw 截图 | `python3 tools/hsl_original_control.py inspect` |
| `hsl_original_probe_units.py` | 只读 dump 原作战斗内 live 单位 | `python3 tools/hsl_original_probe_units.py PID [label]` |
| `hsl_runtime_probe.py`／`hsl_runtime_probe_schema.json`／`hsl_win32_memread.c` | 只读 scalar trace | `python3 tools/hsl_runtime_probe.py --help` |
| `hsl_capture.sh`／`hsl_window.swift`／`hsl_input.swift`／`routes/*.txt` | 旧 macOS window-only 采样路线 | `tools/hsl_capture.sh --dry-run tools/routes/p1_title_to_player_control.txt` |
| `hsl_record_window.swift` | Wine／Godot 窗口录像 | `ignored/bin/hsl_record_window --list`（先 `swiftc tools/hsl_record_window.swift -o ignored/bin/hsl_record_window`） |
| `build_runtime_helpers.sh` | 构建 macOS window/input helper 与 Wine helper | `tools/build_runtime_helpers.sh --win32-control` |
| `run_original_hsl.sh`／`play_original.sh` | 启动原作；原版对照装回憶錄预设 | `tools/play_original.sh` |
| `hsl_video_events.py` | 录像画面变化的像素盘点 | `python3 tools/hsl_video_events.py --help` |
| `hsl_title_layout_probe.py` | 标题布局模板匹配复测（需 numpy） | `python3 tools/hsl_title_layout_probe.py --check` |
| `hsl_sprite_facing_audit.py` | 切入美术人工审核表 | `python3 tools/hsl_sprite_facing_audit.py --output-root ignored/g` |
| `hsl_typesafe_client.py`／`typesafe/evidence_lint_rules.json` | TypeSafe 请求命令行；`jevgrep lint` 仓内规则 | `python3 tools/hsl_typesafe_client.py ask request.json --dry-run` |

### 原指令探针与诊断

P-027原作世界／城镇证据：`hsltools/probes/world_town.py`离线校验三个初始非空菜单树、地图模式／到达、te扣费／失败分支、表现helper及其具名停止边界；`--execute EXE --write`才实际执行原指令并更新回执。见[完整答复](../docs/evidence_packets/static_reverse/original_world_town.md)。此工具只读原包；产品world／town路径由presentation线维护。

盗贼／翼战士与MP打击：`hsltools/probes/mobile_jobs.py`／`hsltools/probes/mana_strike.py`分别核对完整职业刷新与末击资格／目标削魔；`hsltools/probes/mobile_source.py`核对玩家槽与缺字段读法，`hsltools/probes/mobile_motion.py`核对动作位移。默认只核对回执，显式`--execute`才执行原指令。`python3 tools/hsl.py check mobile_jobs_data`和`python3 tools/hsl.py check mobile_jobs_assets`覆盖四模板、演练库存及资源。见[来源合同](../docs/evidence_packets/static_reverse/original_mobile_jobs.md)。

永久能力：`hsltools/probes/permanent_items.py`离线核对82组来源、164道具前段和328完整刷新；`--execute`才重取原指令。`python3 tools/hsl.py check permanent_items_data`验证公开演练及实际角色库存。原始抗性80和最终抗性80分开，详见[来源合同](../docs/evidence_packets/static_reverse/original_permanent_items.md)。

战役JSON的永久字段经`run_permanent_items_tests.gd`（`carry_cases`）验收（完整门禁已注册）；原作存档／跨关handler等价不在这组范围。

战斗道具入口：`hsltools/probes/tactical_items.py`（97前段——含 R32 解衰弱 28、18采样／72扫描返回）、`hsltools/probes/item_cure_route.py`（24AI路由前段）、`hsltools/probes/item_magic.py`（6低强度混合前段／4到期返回）、`python3 tools/hsl.py check tactical_items_data`（公开演练／库存）。前三项默认离线校验，显式`--execute`才重新执行原EXE；[来源与完整体验](../docs/evidence_packets/static_reverse/original_tactical_items.md)。

原宝箱使用`hsltools/probes/treasure.py`（默认离线，`--execute <原EXE> --write`才执行）与`python3 tools/hsl.py check treasure_data`：14次实例复制、14领取调用及14重复守卫、6初始化、7接触前段各保留真实停止边界；源EVEF三箱内容加入正式1／2的可选资源，不改地图／剧情。`run_treasure_tests.gd`覆盖实际领取、满包交换、独立行动、F9与保留物品跨营地，见[源合同](../docs/evidence_packets/static_reverse/original_treasure.md)和[完整控件路线](../docs/evidence_packets/runtime_observations/treasure/README.md)。
原宝箱整段生命周期使用`hsltools/probes/_treasure_reentry.py`（诊断，不注册任务；`… python3 tools/hsltools/probes/_treasure_reentry.py --level N [--out FILE]`）：借`_enemy_level.round_sort_machine`经`0x42da60`进关停在首个`0x407340`，列出全部 process 41 对象（隐藏／已开位／八字内容），整段执行`0x4156d0`并在`0x458c10`计抽取、列映像改动，再同进程进同一关重读箱表，打印`TREASURE_REENTRY`；每只箱另列对象码、按像素连回的 EVEF 记录与模板 `+0x80`（obj_Attribute）。`--census 1,2,28,…` 只读各关首回合箱表，每关一行`TREASURE_HIDDEN`（隐藏／可见记录、模板 bit `0x10000` 是否决定可见性）。结果见[源合同「进关、再进关与读档」「隐藏宝物」](../docs/evidence_packets/static_reverse/original_treasure.md)。
地图物件云漂移／移動背景视差使用`hsltools/probes/_map_object_drift.py`（诊断，不注册任务；`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_map_object_drift.py --level N [--ticks 250] [--out FILE]`）：借`_enemy_level.round_sort_machine`进关停在首个`0x407340`，列出 process 2 且 obj_Data9 为 mapobjCloud（3）／mapobjMoveBG（6）的对象；云按原帧循环再跑 N 帧逐帧取坐标（`MAP_OBJECT_DRIFT`），再放到出界边缘直接调 `0x43ccf0` 看回绕（`MAP_OBJECT_WRAP`；机器的形状装载是桩，先按 SHP 头装入帧描述）；移動背景把镜头 `0x4c091c／0x4c0920` 放到四角与中点各调一次过程（`MAP_OBJECT_PARALLAX`）。读法见[地图物件漂移](../docs/evidence_packets/static_reverse/original_map_object_drift.md)。
噴人沼氣（defProcPoisonGas）追踪使用`hsltools/probes/_poison_gas.py`（诊断，不注册任务；`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_poison_gas.py --level 32 --seed S1 S2 [--damage-seed D1 D2] --turns N --out FILE`）：借`_enemy_level.run_level`进关、玩家待机，记每次喷气的剧本位置／中心像素／交接计数`0x4c1ad4`与截止字`0x4c1ad6`、每次`0x409140`的调用者与状态字前后及抽前随机字。[读法与结果](../docs/evidence_packets/static_reverse/original_poison_gas.md)。

打人閃電（defProcDropLightn）追踪使用`hsltools/probes/_drop_lightning.py`（诊断，不注册任务；`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_drop_lightning.py --level 10 --seed S1 S2 [--set ID.FIELD=V] --turns N --out FILE`）：借`_enemy_level.run_level`进关、玩家待机，记每道雷创建时的镜头字`0x4c091c／0x4c0920`与抽前全局字、落点像素、九格取到的单位与抽伤害前全局字、伤害与写回 HP、每次交接的计数与镜头。[读法与结果](../docs/evidence_packets/static_reverse/original_drop_lightning.md)。

关卡地图来源使用`python3 tools/hsl.py check source_map_binding`与`hsltools/probes/map_binding.py`（默认离线；`--execute <原hsl01.exe> --write`才重跑有界原指令）。`hsl_battle_seed.build/check`已先解析OBS、读取完整源path并核对原哈希，不再用MAP_ALIASES选择资源；旧别名只作兼容注记。源绑定153关卡图／49控制器例外、27装载前段和18回调边界见[原包](../docs/evidence_packets/static_reverse/original_map_binding.md)，实际营地／王座厅及隔离验收入口见[回执](../docs/evidence_packets/runtime_observations/map_binding/README.md)。

戈爾山道使用`python3 tools/hsl.py check gol_road_data`生成／核对正式七人编队、两个待安装源模板和原WINFAIL002两阶段；`hsltools/probes/player_install.py`默认离线校验30安装分派前段、15启用槽完整返回、4坐标前段及缺省字段读取，显式`--execute <原EXE> --write`才执行原指令。源002／023复用原职业／装备／能力，不改变原数据；见[安装证据](../docs/evidence_packets/static_reverse/original_player_install.md)。`GolRoad.tscn`或大地图点2进入正式战斗；[实玩回执](../docs/evidence_packets/runtime_observations/gol_road/README.md)给出自然战斗、专项输入、胜利存档跨进程到55／56／地图的复跑入口。旧story_002只保留独立预览回归，不再是产品点2的入口。

脚本离场使用`hsltools/probes/departure.py`：56状态样例、12删除请求与16行走请求；当前角色清理止于renderer/reset之前，正常返回样例核对栈平衡及历史字段未变。[地址和范围](../docs/evidence_packets/static_reverse/original_script_departure.md)独立记录。默认离线检查，重执行须显式`--execute`，不调用Jev或覆盖原EXE。

原版敌人回合裁判使用`hsltools/probes/enemy_turn.py`（整映像机器 `hsltools/native/battle_machine.py`；`python3 tools/hsl.py check enemy_turn` 离线校验；复跑 `uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsl.py generate enemy_turn`；单回合 `… python3 tools/hsltools/probes/enemy_turn.py --brief [--seed S1 S2] [--damage-seed D1 D2] [--set ACTOR.FIELD=V] [--lines FILE] [--ablate NAME]`）：原存档读取器载入 51 关样本后，把雷歐納德置入玩家进程的回合结束模式（`+0x8c=0x10000`，原版自己走完结束序列与交接 `0x407510`）起逐帧调原帧体 `0x42d600` 直到回到玩家控制，输出 enemy_turn_v1（落点、attack／magic／skill／item／wait、目标、每次抽取的 site／n／value／stream）；回执另含 `0x407340` 队列排序四种情形、`0x40e870` 出生调级的抽取流（`growth`）与帧桩消融。载入态缓存在 `ignored/native_cache/battle_machine/`（缺失自动重建），`hsl check enemy_turn` 离线校验、有 unicorn 与原 exe 时复跑。[读法与结论](../docs/evidence_packets/static_reverse/original_enemy_turn.md)；`replaces=()`。
任意关卡回合裁判使用`hsltools/probes/_enemy_level.py`（诊断，不注册任务；`… python3 tools/hsltools/probes/_enemy_level.py --level N [--board FILE --board-key KEY] [--set ID.FIELD=V] [--seed S1 S2] [--lines FILE] --brief`，`compare ORIGINAL REMAKE`，`batch --levels … --seeds … --jobs N --out DIR`）：原版从新关卡分支 `0x42da60` 进关，输入只有对话点击和玩家待机，停在首个 `0x407340` 前按 `enemy_turn.INJECTION` 把局面写进原版内存（速度、血量、坐标连同占格、持有目标、阵亡），跑 N 回合输出 enemy_turn_v1；`--lines` 按 `enemy_turn.SITE_MAP` 把原版抽取调用点改名为重制 `Script.function`，`compare` 与 `tests/diagnostics/export_enemy_turns.gd` 的输出逐行动、逐抽取对照。停点缓存在 `ignored/native_cache/battle_machine/level_v1_*.pkl`；`test_hsl_enemy_level.py` 离线测对照与改名、有 unicorn 与原 exe 时跑第 51 关 r1。[读法与结果](../docs/evidence_packets/static_reverse/original_enemy_turn.md#复现)。
原版行动队列追踪使用`hsltools/probes/_turn_queue_trace.py`（诊断，不注册任务；`… python3 tools/hsltools/probes/_turn_queue_trace.py --level N [--board FILE --board-key KEY] [--seed S] [--set ID.FIELD=V] [--poke N:ID:V] [--kill N:ID] --turns T --out FILE`）：借`_enemy_level.run_level`的观察者钩子逐事件记`0x4074a0`选取、`0x407340`重建表（对象／标志／速度／注册槽）、`0x4c1bbc`加一、`0x407510`交接、`0x407720`注销、`0x407660`注册与回合结束序列；`--poke`在第 N 次`0x4074a0`入口改某单位速度，`--kill`在第 N 次选取后注入阵亡。结果见[轮次语义](../docs/evidence_packets/static_reverse/initial_battle_initiative.md)。

原版掉落与出生携带抽样追踪使用`hsltools/probes/_reward_rng_trace.py`（诊断，不注册任务；`… python3 tools/hsltools/probes/_reward_rng_trace.py birth|drop|carry|kill --level N [--unit ID --bag CODES --seeds 1..32] --out FILE`）：借`_enemy_level`的整镜像模拟器逐次记`0x458c80`／`0x458c10`调用点与抽前全局字，事件含`0x407cc0`出生、`0x407c40`携带、`0x40e870`调级与`0x44f580`掉落；`drop`／`carry`按种子`[s, s^0xe54a231c]`写全局字后嵌套调用。结果见[奖励输入](../docs/evidence_packets/static_reverse/battle_reward_inputs.md)。

脚本条件目标计数与全灭使用`hsltools/probes/check_player.py`（`python3 tools/hsl.py check check_player`；复跑 `uv run --no-project --with 'unicorn>=2,<3' --python /opt/homebrew/bin/python3 python3 tools/hsl.py generate check_player --exe $HSL_ORIGINAL_DIR/hsl01.exe`）：11 次 `0x44fad0` 查找、7 次 `0x450840` case 0x26（actCheckPlayer）完整返回、6 次 winfail fail 扫描 `0x44ecb0`（止于状态执行器 `0x453ac0` 入口）、20 个 anchor 字节段；回执 `original_check_player_native.json`，结论见[目标计数读法 §R8](../docs/evidence_packets/static_reverse/original_check_targets.md)。它替代不了任何台账命令（`replaces=()`）。

脚本等待使用`hsltools/probes/script_wait.py`：opcode33／34／88共120组，含busy→idle重入的129次完整单步返回，另有28段AI等待入口。默认离线固定指令和来源哈希检查；[源合同](../docs/evidence_packets/static_reverse/original_script_wait.md)区分赋值、AI倒数、指定对象演出同步。`tests/run_script_wait_tests.gd`覆盖事务，不修改世界／城镇数据或其协调器。

入场成长使用`hsltools/probes/auto_growth.py`：128次完整数值函数与16段真实VM序列，包括原RNG／refresh／职业分配；opcode56继续运行到下一条缺失对象wait88才正常让出。`hsltools/data/entry_growth.py`连接已验证角色的源参数（缺失保持null），[源合同](../docs/evidence_packets/static_reverse/original_auto_growth.md)与[窗口验收](../docs/evidence_packets/runtime_observations/entry_growth/README.md)区分原函数、当前新援入口和未覆盖的初始／NPC升级分派。没有模型路由或被替换的原callee。

成长生命周期使用`hsltools/probes/growth_lifecycle.py`：78经验升级caller、278魔法／绝技完整返回、16初始调级caller和opcode73两次VM返回；默认离线校验，`--execute`才执行原EXE；`hsltools/probes/job_up_learning.py`同样方式补上位职业81／82／84／86／87／89／91／97／99的714组学习返回（`uv run --no-project --with 'unicorn>=2,<3' --python /opt/homebrew/bin/python3 tools/hsl.py generate job_up_learning --exe $HSL_ORIGINAL_DIR/hsl01.exe`，在仓库根运行）。`python3 tools/hsl.py check growth_lifecycle_data`核对原job／等级／基础属性／初始mask（20个职业）；`python3 tools/hsl.py check growth_lifecycle_trial`核对可独立游玩的治疗升级→驱毒与剑士学技演练。初始毒／经验／耐久为明确配置，不修改正式授予。[原证据](../docs/evidence_packets/static_reverse/original_growth_lifecycle.md)和[实际回执](../docs/evidence_packets/runtime_observations/growth_lifecycle/README.md)区分原全局RNG与独立保存生成流。

歐姆村使用`hsltools/probes/ohm_growth.py`（104派生刷新、39成长、9EXP caller、53学习及控制／复制）、`hsltools/probes/bow_range.py`（24范围正常返回）、`hsltools/probes/poison_arrow.py`（44正常数值／49应用前段）；默认离线检查，只有显式`--execute`才执行原EXE。`python3 tools/hsl.py check ohm_village_data`核对正式18人编队及原STORY终点，`python3 tools/hsl.py check ohm_assets`／`python3 tools/hsl.py check poison_arrow_data`核对原图音；不猜jobNPC，不为无装备村民造武器。直接游玩`game/battle/development/OhmVillage.tscn`或从53结果页进入；[源合同](../docs/evidence_packets/static_reverse/original_ohm_village.md)与[实玩／跨关](../docs/evidence_packets/runtime_observations/ohm_village/README.md)分别记录自然流程与明示插入、AI策略、装备夹具。

攻防增益／退魔：`hsltools/probes/stat_magic.py`默认离线核对61原应用前段、128完整refresh和16完整tick；`hsltools/probes/ai_stat.py`核对160优先级／正向状态扫描样例。`python3 tools/hsl.py check stat_magic_data`核对源图音与明确开发赠予，`test_hsl_data_native.py` 的 stat_magic 段验证篡改边界。[规则和实玩入口](../docs/evidence_packets/static_reverse/original_stat_magic.md)；只有显式`--execute`重新执行本机原EXE。

月花圓舞由`hsltools/probes/moon_dance.py`核对315次原应用和14组扣费／目标切换／死亡扫描；正常返回和表现前段边界分列。`python3 tools/hsl.py check moon_dance_data`核对完整源程序、11图2声音、显式演练配置；[研究合同](../docs/evidence_packets/static_reverse/original_moon_dance.md)说明目标五段、HP0尾段、最后经验和原时钟边界。

002祭司的`hsltools/probes/priest.py`、`hsltools/probes/priest_motion.py`和`hsltools/probes/mana_item.py`分别核对槽绑定／完整job85刷新、原垂直动作前段与回魔物品入口；默认离线检查，显式execute才执行原指令。`python3 tools/hsl.py check priest_data`和`python3 tools/hsl.py check priest_assets`校验生成模板／场景和资源，见[源依据](../docs/evidence_packets/static_reverse/original_priest.md)及[实玩](../docs/evidence_packets/runtime_observations/priest/README.md)。

施法装备使用`hsltools/probes/casting_equipment.py`核对243转化样例和80完整装备刷新；有效转化止于首个数字renderer前，无效果分支正常返回。源字段、装卸／成长和玩家／AI整链见[施法装备](../docs/evidence_packets/static_reverse/original_casting_equipment.md)，脚本默认离线检查，显式`--execute`才重新执行原指令。

白光之翼连续行动的有界原指令核对用 `python3 tools/hsl.py check extra_action`；其5个getter完整返回与20个玩家／AI收尾前段分别记录。Godot实际接入及验收范围见[源额外行动](../docs/evidence_packets/static_reverse/original_extra_action.md)。

当前三职业／资源装备使用 `hsltools/probes/job_stats.py`、`hsltools/probes/recovery.py` 离线核对固定源字节、原返回及字段；显式`--execute`才调用原指令。源包通过后依次生成 `hsltools/data/equipment.py`、`hsltools/data/role_profiles.py`、`hsltools/data/first_battle_formation.py`、`hsltools/data/emperor.py`（025 皇帝模板 `actors/025.json`），所有`--check`进入完整门禁。216职业完整返回与582资源前段／6无效果完整返回的范围见[三职业](../docs/evidence_packets/static_reverse/original_job_stats.md)、[资源尾部](../docs/evidence_packets/static_reverse/original_resource_recovery.md)，不能互称完整原引擎执行。

大型角色用`hsltools/probes/large_actor.py`离线核对命中、整块四邻flood、占格与去重、039刷新和缺失AI字段前段；`--execute <hsl01.exe> --write`才执行固定原字节。`python3 tools/hsl.py check large_actor_data`对照039源模板及独立开发场景，普通第一／第二战编队保持。可玩入口`tools/godot.sh --screen <内建屏索引> res://game/battle/development/LargeActorTrial.tscn`，详情见[大型角色合同](../docs/evidence_packets/static_reverse/original_large_actor.md)。

武器尾部由`hsltools/probes/weapon_effect.py`离线核对158完整效果、15完整队列取消、24真实EXP caller分支、36完整装备刷新、12＋16字段OR前段和176组`0x409310`状态字（衰弱／禁魔／麻痺／随机异常，完整PLAYERS目标上真实`0x448840`刷新）；偷窃加成字与金之手槽循环由`hsltools/probes/steal_ratio.py`核对（21次`0x448840`刷新、5次`0x4348f0`转职、67次`0x40b8f0→0x40aa80`完整返回；`hsl check steal_ratio`）；默认不运行原EXE，只有`--execute <hsl01.exe> --write`才重新执行并写回。`python3 tools/hsl.py check weapon_effect_trial`校验独立可玩演练的数据：`tools/godot.sh --screen <内建屏索引> res://game/battle/development/WeaponEffectsTrial.tscn`。原10%／25%概率不为截图调高，有限合法轮次的重试次数进入回执；[证据和边界](../docs/evidence_packets/static_reverse/original_weapon_effects.md)。

麻痺链用`hsltools/probes/paralysis.py`默认离线校验、显式`--execute`核对原指令，区分入口／施加／解除前段与计时／道具扫描／装备刷新正常返回。`hsltools/assets/paralysis_assets.py`通过既有PAK importer导出地靈縛8帧2声音，`--check`核对原成员、SHP解码和声音哈希；不替代实玩或完整高位dispatcher证据。入口见[麻痺规则](../docs/evidence_packets/static_reverse/original_paralysis.md)。

`hsltools/probes/position_equipment.py`默认离线核对源移动施法资格和范围索引，显式`--execute`才执行原getter／菜单和AI前段／装备refresh。`hsltools/data/attack_ranges.py`保留RANGE.H索引，当前普通武器1／2可由装备扩至3；`hsltools/data/skill_book.py`保留固有移动施法字段。来源与可玩范围见[位置能力](../docs/evidence_packets/static_reverse/original_position_equipment.md)。

`hsltools/probes/movement.py`普通运行检查58份完整四邻扩展和80份邻格代价返回；`--execute <EXE>`才重新执行原字节，`--write`必须同时执行。[移动证据](../docs/evidence_packets/static_reverse/original_movement.md)区分0xff地形墙和低位对象flags，实际预算／路径／失效重选进入`run_ai_navigation_tests.gd`及完整门禁。

原风火／最终经验使用`hsltools/probes/magic_damage.py`与`hsltools/probes/experience.py`；默认只核保存的原输出，`--execute <原EXE>`才实际隔离执行，完整返回和应用／发放后缀分别标注。实际输入回执（驱动已退役）见[魔法经验包](../docs/evidence_packets/runtime_observations/magic_experience/README.md)，测试存档只写ignored，不覆盖玩家存档。

伤害／命中随机流使用`hsltools/evidence/damage_random.py`（任务`damage_random`，族`evidence`）：`python3 tools/hsl.py check damage_random`不需EXE，用独立模型逐值复算4组状态×1000次原生返回；`generate`在unicorn里重跑原`0x458c10`／`0x458c80`／`0x42c720`／`0x42c780`并按字节钉住播种与存档读写。Godot侧`run_tests.gd`拿同一机器包逐值对拍`DamageRandomStream`，见[伤害随机流](../docs/evidence_packets/static_reverse/original_damage_random.md)。

整段交锋对拍使用`hsltools/probes/_exchange_check.py`（诊断，不注册任务）：`record --level N [--board FILE --board-key KEY] [--set ID.FIELD=V] --damage-seeds 1-200 --turns T --out FILE`借`_enemy_level.run_level`的观察者钩子在原版交锋`0x4423c0`、冲击`0x403860`、发放`0x442720`上逐次记下开场伤害字、双方活记录、每次伤害流抽取、每下的命中／暴击／伤害与发放；`tests/export_exchanges.gd --cases FILE --out FILE`从同一开场状态走重制`BattleLoopCombat._resolve_exchange`；`compare CASES REMAKE [...]`逐列（命中／伤害／暴击／反击／反击伤害／经验、每次抽取、交锋末活记录与伤害字）对照，打印`EXCHANGE_COMPARE`。结果见[伤害随机流](../docs/evidence_packets/static_reverse/original_damage_random.md)。

水剎使用`hsltools/probes/water_strike.py`追加实际水元素输入：22次原数值正常返回、44段HP／贡献前段，不把它们当完整施法。`python3 tools/hsl.py check water_strike_data`核对真实源十字、费用、命中、11帧WAT和WATER005；非check需合法原PAK。`python3 tools/hsl.py check water_strike_trial`核对002治疗学习→独立第二行动施放的公开演练。全部注册进完整门禁；[原证据](../docs/evidence_packets/static_reverse/original_water_strike.md)／[真实输入](../docs/evidence_packets/runtime_observations/water_strike/README.md)明确保留对象访问顺序、独立随机流和演出时钟边界，不改原风火单体定义。

#### 独立工具

| 脚本 | 用途 | 验证 |
| --- | --- | --- |
| `hsl_combat_resolution_probe.py` | 用 r2 复核 `core_logic.json` 的战斗 instruction anchors | `--exe` 手动复跑（[core_logic 证据](../docs/first_battle_core_logic_evidence.md)） |
| `hsl_exe_decompile.py` | 按地址窄反编译到 `ignored/static/hsl01/decompiled/` | — |
| `hsl_exe_static_export.py` | EXE 静态导出到 `ignored/static/hsl01/` | `test_hsl_static_export.py` |
| `hsl_native_animal_probe.py` | ANIMAL 派发器前缀有界仿真（入口／停点常量在 `hsltools/native/animal_dispatcher.py`） | `hsl check animal_programs` |
| `hsl_native_growth_probe.py` | 四属性加点上限 helper 有界仿真 | `test_hsl_native_growth_probe.py` |
| `hsl_native_growth_refresh_probe.py` | Leonard 成长上限与属性刷新有界仿真，`--check` | `test_hsl_native_growth_refresh_probe.py` |
| `hsl_native_level_probe.py` | NPC 等级选择有界仿真（探索工具） | 手动复跑（[等级选择包](../docs/evidence_packets/static_reverse/first_battle_level_selection.md)） |
| `hsl_native_map_scroll_probe.py` | 鼠标边缘滚屏请求函数有界仿真 | `test_hsl_native_map_scroll_probe.py` |
| `hsl_native_presentation_probe.py` | 三个表现 helper 有界仿真（探索工具） | 手动复跑（[表现 helper 包](../docs/evidence_packets/static_reverse/native_presentation_helpers.md)） |
| `hsl_native_stats_probe.py` | 原属性刷新有界仿真（需 unicorn） | `test_hsl_data_native.py` |
| `hsl_opening_choreography_packet.py` | 生成开场 choreography 证据包（检查器在 `hsltools/evidence/opening_choreography_packet.py`） | — |
| `hsl_original_control.py` | Wine 内部单步输入＋cnc-ddraw 截图（见「原作 runtime 验证」） | `--dry-run` |
| `hsl_original_probe_units.py` | 只读 dump 原作战斗内 live 单位（见「原作 runtime 验证」） | 手动（[17 关护送包](../docs/evidence_packets/runtime_observations/original_level17_escort/README.md)） |
| `hsl_runtime_probe.py` | 只读 scalar trace 写出 | `test_hsl_runtime_probe.py` |
| `hsl_script_vm_semantics.py` | 脚本 VM dry-run 语义生成／`--check` | `test_hsl_script_vm_semantics.py` |
| `hsl_sprite_facing_audit.py` | 切入美术人工审核表（见「产品数据与资源」） | 手动，输出到 `ignored/` |
| `hsl_title_layout_probe.py` | 标题布局模板匹配复测（需 numpy，不入门禁） | `--check` |
| `hsl_video_events.py` | 录像画面变化的像素盘点：`scan` 解码（保留 PTS、裁出游戏区、降到 320×240 灰度、80×60 块的逐帧变化计数与相位相关镜头平移，需 numpy：`uv run --with numpy`），`events` 切出整屏／镜头平移／局部事件与局部变化轨迹（起止 PTS、640×480 逻辑坐标外框、面积、首末中心），`camera` 数镜头移动段（多帧小步＝平滑滚动，单帧大步＝跳切），`region` 按原帧率量一个逻辑框（相对参考帧的外框／质心／亮度变化／颜色、逐行带计数与亮像素行、逐帧平均步长切出的过渡段——硬切 1 帧、溶解多帧——与平均亮度的周期），`audio` 找音轨起点并用归一化互相关认出是哪一个原版 WAV（需 numpy）；`sprite` 在一个逻辑框里逐帧匹配已知精灵（hsl.pak 解出的 RGBA 图，掩膜 RGB 差最小的位置与分数），给出可见段的起止 PTS、首末中心与漂移（需 numpy；长录像先按窗口切成 `-copyts` 的 ffv1 片段再跑）；只回答“何时何处变了”，不命名、不判等价，输出放 `ignored/` | — |
| `hsl_typesafe_client.py` | TypeSafe 请求命令行 `models`／`ask [--dry-run]`（客户端本体 `hsltools/typesafe.py`，`checks/function_catalog` 调用） | `python3 tools/hsl_typesafe_client.py ask request.json --dry-run` |

- `hsl_sprite_facing_audit.py [--output-root ignored/g]`：人工审核材料——上位行切入／flash／s_shape contact sheet，第六波 32 名 provisional 演员的审核表（每演员一行：五向站立帧 pose 1＋切入首帧＋受击帧，取共享→逐关走行 manifest 首个命中）与 `sprite_facing_audit.json`（现值／k_action／素材来源／review_status）；只产出审核材料，不改 manifest，人工判定后再改 `SPRITE_FACING` 与 provisional 集。

### TypeSafe 判断分担与全 EXE 函数目录

Jev 只判断不生成、不执行、不看图；用它分担"读很多、判一点"的语义判断（函数职责候选、长文档段落筛选、证据用语自检、多入口文档漂移），精确事实仍由代码做。用法、实测准确率与模板在私有仓库的 TypeSafe 用法文档（第三方镜像，公开导出不带）。key 只经 `TYPESAFE_API_KEY` 环境变量注入，不进 verify 门禁。

```sh
python3 tools/hsl.py check function_catalog                       # 离线核对 tracked 函数目录
PYTHONPATH=tools python3 -m hsltools.checks.function_catalog judge --dry-run               # 登记新函数名后：数多少函数需要重判（无网）
PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query --role pathfinding_terrain --unknown --min-confidence 0.5
PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query --prop 'tests_capability_bits>=0.7' --unknown
TYPESAFE_API_KEY=<你的 key> python3 tools/hsl_typesafe_client.py ask request.json   # 任意 state/questions 请求
jevgrep rank "机制问题" --files docs/KNOWLEDGE_INDEX.md --split rows --top 8   # 全局 CLI（维护者自建）：冷启动路由
jevgrep lint --rules tools/typesafe/evidence_lint_rules.json --diff HEAD      # 全局 CLI：改文档后的证据用语自检
```

- `typesafe/evidence_lint_rules.json`：`jevgrep lint` 的仓内规则（等价声明无证据等级、测试绿推等价、文件名当语义、provisional 无替换证据、入口文档日报）；命中只是提示，按 hint 复核，不进门禁。
- `PYTHONPATH=tools python3 -m hsltools.checks.function_catalog decompile|judge|build`：r2ghidra（崩溃回退 r2dec）反编译全部函数到 `ignored/static/hsl01/catalog/`，按 `content/generated/hsl/static/hsl01/known_functions.json` 与 core_logic 字段表符号化后逐函数判定，生成 tracked `function_catalog.json`（tier static_export_candidate，无反编译文本与私有路径）。接完一个机制把新函数追加到 known_functions.json 再重跑。
- 目录是路由候选，不是证据；写进证据包前仍需有界原指令探针。

### 录像证据

录像资料校验使用 `python3 tools/hsl.py check gameplay_reference`：验证正式 packet 的媒体哈希、尺寸、源帧范围和分类引用，已纳入 verify。`PYTHONPATH=tools /opt/homebrew/bin/python3 -m hsltools.evidence.gameplay_reference --video <record.mp4>` 重解码并比较源像素；默认不需要原视频或 FFmpeg。该工具不认证文字解释或原版等价；原始交付审查与恢复位置见 [录像参考](../docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md)。

### EXE 静态分析

`hsltools/probes/extra_attack.py`检查43组追加攻击查询／初始化／续击／收尾结果和九段源字节，13正常返回与30有界分支分别标注；`--execute <hsl01.exe>`才重新运行原指令。天赋019／057和ITEM12／55／69来自原表，只有全部字段受支持的12开放；与额外行动action_twice分开。详见[追加攻击证据](../docs/evidence_packets/static_reverse/original_extra_attack.md)。

- `hsl_exe_static_export.py`：可重复导出，默认写 `ignored/static/hsl01/`。
- `hsl_exe_decompile.py`：按地址生成窄反编译输出。
- `hsltools/checks/static_index.py`、`hsltools/checks/core_logic.py`：检查 tracked compact packet。
- `hsl_script_vm_semantics.py`：脚本 VM。
- `hsltools/probes/ai_skill.py`：普通运行检查202组技能／施法格原结果，162正常返回与40距离后缀分别记录；只有 `--execute <hsl01.exe>` 重新执行锁定SHA的原字节，`--write`必须同时执行。对应 [技能／站位合同](../docs/evidence_packets/static_reverse/original_ai_skills.md)，不需要启动Wine。
- `hsltools/probes/ai_support.py`：原友军回复／状态扫描连续正常返回、两项支援概率后缀及源loader／药品caller字节；普通运行只核对已保存结果，`--execute <hsl01.exe>`实际运行、`--write`必须同时执行。见 [支援证据](../docs/evidence_packets/static_reverse/original_ai_support.md)，不运行Wine或原完整AI。
- `hsltools/probes/stamina.py`：168组完整原气力函数执行，核对双方资源写入、上限、等级差、装备加倍／停止和零RNG；`--execute <hsl01.exe>`重放，`--write`必须同时执行。普通门禁读取已核对的[气力证据](../docs/evidence_packets/static_reverse/original_stamina.md)，无需原作进程。
- `hsltools/probes/physical.py`／`hsltools/probes/special_damage.py`：普通／武器／命中148正常返回、暴击／下限／概率34后缀；氣刃斬20返回／24HP应用，RNG0和raw值独立核对。普通checker不执行EXE，`--execute`才重放锁定SHA字节；原始输出边界和命令见[普通／绝技证据](../docs/evidence_packets/static_reverse/original_ordinary_special.md)。

### 原作 runtime 验证

```sh
tools/play_original.sh      # 原版对照：把第 6 关回憶錄预设装进原版第 1 行再启动；--restore 还原第 1 行与原版退出时写的 HSL.CFG（docs/PLAYTEST.md；测试 test_hsl_play_original.py）
tools/build_runtime_helpers.sh             # 只构建 macOS window/input helper
tools/build_runtime_helpers.sh --win32-rpm # 按需加构建 Wine scalar-memory helper
tools/build_runtime_helpers.sh --win32-control # 仅构建 Wine 内部输入 helper
```

优先使用本机已实测的 **Wine 内部 SendInput + cnc-ddraw 原生游戏画面截图**，
不依赖 macOS Accessibility 控件或 `screencapture` 能否读取 Wine 窗口：

```sh
tools/build_runtime_helpers.sh --win32-control
python3 tools/hsl_original_control.py inspect
python3 tools/hsl_original_control.py screenshot --label before
python3 tools/hsl_original_control.py click 367 175 --dry-run
# 仅当截图确认行动菜单的“移动”在此处时执行：
python3 tools/hsl_original_control.py click 367 175 --label move
# 看返回的 game.png，确认进入选格后再取消：
python3 tools/hsl_original_control.py rclick 320 240 --label cancel
```

新入口不自动启动原作，不修改 EXE/存档/内存。一次只执行一个有界动作；
非 `inspect` 动作附带游戏截图与 JSON receipt，写入 `ignored/original-control/`。
截图使用已安装 cnc-ddraw 的 `keyscreenshot=0x2C` 和 `screenshotdir=.\Screenshots\`；
窗口非 Wine 前台、身份不唯一、截图陈旧/歧义/尺寸错误时失败，不自动重复游戏输入。
`focus` 是显式操作；这不是隔离桌面，仍可能移动真实指针，不能承诺后台无干扰。
**窗口落在已断开的显示器上**（Wine 记住上次会话的位置；表现为截图正常、点击全部落空，`inspect` 的 `window` 左上角在主屏之外，如 2026-09-23 lane M1 的 x=1972）：先 `python3 tools/hsl_original_control.py place 100 60` 把游戏窗口左上角移回桌面坐标 (100,60)（`SetWindowPos`，不改尺寸、不发输入、不截图），再 `inspect` 核对 `origin`，否则每趟会白丢几分钟。
实测范围与图证见 `docs/evidence_packets/runtime_observations/original_control/README.md`。

旧的 macOS HID/window capture 路线保留用于兼容与人工探针，不再作为唯一方案：

```sh
tools/run_original_hsl.sh
tools/hsl_capture.sh --dry-run tools/routes/p1_title_to_player_control.txt
tools/hsl_capture.sh --dry-run tools/routes/p1_player_control_action_menu_probe.txt
tools/hsl_capture.sh --dry-run tools/routes/p2_action_menu_move_select_cancel.txt
tools/hsl_capture.sh --no-launch tools/routes/p2_action_menu_move_select_cancel.txt
```

- `hsl_window.swift`：严格发现 HSL Wine 窗口；候选不唯一时失败。
- `hsl_input.swift`：对显式 window id 发送 HID 输入；首次使用需要 Accessibility 权限。
- `hsl_capture.sh`：旧 window-only 路线采样入口；先校验整条 route，再发送输入。
- `hsl_original_control.py` / `hsl_win32_control.c`：Wine 内部单步输入与 cnc-ddraw 游戏画面采样；每步需要核对实际结果。
- `p1_title_to_player_control.txt`：从标题进入无菜单的第一可操作状态；它也是 `hsl_capture.sh` 的默认路线。
- `p1_player_control_action_menu_probe.txt`：从该状态执行一次有界右键菜单探针，不把未提升的结果写成事实。
- `hsl_original_probe_units.py PID [label]`：只读 dump 原作战斗内全部 live 单位（`*0x4c1bc8` 记录 × 对象表 `0x4c34c0`：阵营字、等级、HP／MP、格坐标、八个物品槽、死亡标、身份栏已知字节 `0x4c6d80[obj+0xa2]`（`known_serial`／`known`，lane P4）；PID 为 `wine tasklist` 的任务 pid），每次一份 `ignored/original-probe-units/units-<label>.json`，另带回合计数 `round_0x4c1bbc` 与全局 RNG 种子标志 `rng_seeded_0x4c1e8c`（2026-09-25 前的回执把后者误标为 `round_counter_0x4c1e8c`）——17 关护送对照包与身份栏采样的取样脚本。
- `hsl_runtime_probe.py`：只读 scalar trace。`hsl_win32_memread.c`（`tools/build_runtime_helpers.sh --win32-rpm` → `ignored/bin/hsl_win32_memread.exe`）除 `--read-u32 name=0xADDR` 外支持有界字节段 `--read-bytes name=0xADDR:0xLEN`（≤ 0x40000，输出 hex）：`WINEPREFIX=… wine ignored/bin/hsl_win32_memread.exe --pid <wine tasklist pid> --read-u32 templates_ptr=0x4c1afc`，再按指针 `--read-bytes templates=0x<ptr>:0x18edc` 一次读出 PLAYERS 模板表（原版存档格式包）。`--repeat N --interval-ms M` 在同一进程内以 `Sleep(M)` 间隔重复读同一组地址，每样本一行 JSON 并附 `sample`／`tick_ms`（`GetTickCount`）／`qpc_us`——用于按节拍数 tick（[原版 tick 率](../docs/evidence_packets/runtime_observations/original_tick_rate/README.md)）；`repeat=1` 时输出与旧格式相同。
- `hsltools/evidence/visual_index.py`：检查 curated 原作截图索引。
- `hsl_opening_choreography_packet.py` / `_check.py`：生成并检查 opening choreography gate。
- `hsltools/levels/message_text.py`：检查从 RESOURCE.TXT 恢复的对白正文与说话人（`--level 52` 检查第二战 evidence）；早期 global.obs 负证据不再代表当前文本状态。

### Godot capture harness

`tests/capture_*.gd` 生成当前 Godot 的可见截图/manifest，输出到 `ignored/`。它们是人工视觉审查输入，不是自动 parity 证明。

原先随截图驱动一起说明的离线核对：`hsltools/probes/traversal.py`离线核对原函数／落点前段，`hsltools/data/terrain_heights.py`重建两张源WRD完整哈希；只有前者`--execute`或后者`--pak`读取原本体。`hsltools/probes/mobility.py`检查78次已保存完整刷新返回，只有`--execute <原EXE>`重新执行。`hsltools/probes/ai_navigation.py`普通运行检查118组保存的原结果，`--execute <hsl01.exe>`才重新执行。回复／驱毒资源用 `python3 tools/hsl.py check support_magic`，原数值／应用前段回执用 `hsltools/probes/support.py`；加 `--execute` 才执行本机SHA锁定EXE。成长原函数复跑使用 `uv run --with unicorn==2.1.4 python tools/hsl_native_growth_refresh_probe.py --check`；普通产品和 full verify 不依赖 Unicorn。

`tests/capture_campaign_handoff_review.gd` 在第一战 dev seam 上显式设定胜利结果与 Leonard 等级／金币夹具，确认结局台词后（原版无结果页，脚本置 `hold_finished_battle` 后直接调 `start_next_battle`），记录重新加载进入第二战开场；输出 `ignored/campaign-handoff-review/`，图证见 [承接回执](../docs/evidence_packets/runtime_observations/campaign_handoff/README.md)。

奖励与存档使用 `tests/capture_battle_reward_review.gd -- prepare` 和后续独立进程 `-- resume`，完整命令见 [奖励验收](../docs/evidence_packets/runtime_observations/battle_rewards/README.md)。只写 `ignored/battle-reward-review/partial.save`；来源字段用 `python3 tools/hsl.py check battle_rewards`，13段原字节合同用 `hsltools/evidence/reward.py`，加 `--exe` 才读取 SHA 锁定的本机 hsl01.exe。

`tests/capture_first_battle_review.gd` 专用于本轮地图预告、原尺寸攻击/受击、地图法术、状态与成长 UI 的渲染夹具，并用真实 Godot 鼠标事件确认加点。它会改夹具数据，不能冒充自然游玩；正常路线仍使用下方 `run_first_battle_playthrough.gd`，其中附带存活演员可见性检查与少量关键帧截图。

地图死亡与升级的当前验收使用 `tests/capture_combat_aftermath_review.gd`：正常时钟、实际鼠标选命令／目标及鼠标／键盘确认，逐帧读取遗言、淡出、EXP、成长与下一角色。它明确设定邻接1HP敌人、99EXP／60ST和玩家／下一队友速度与控制资格，不覆盖 RNG 或攻击结果；输出 `ignored/combat-aftermath-review/`，不能算自然获取经验或完整通关。`python3 tools/hsl.py check combat_aftermath_data` 与 `tests/run_combat_aftermath_tests.gd` 已进入完整门禁；前者只检查 tracked 源表，不冒称新原包或 EXE 验证。复跑图证见 `docs/evidence_packets/runtime_observations/combat_aftermath/README.md`。

```sh
# 真实渲染窗口，正常时钟，自动发送 Godot 鼠标/键盘事件；不修改战斗数值
tools/play.sh --script res://tests/run_first_battle_playthrough.gd -- hold
tools/play.sh --script res://tests/run_first_battle_playthrough.gd -- advance
# 有界规则抽样：默认数据，20 seeds × 3 策略，无画面/输入验收含义
godot --headless --path . --script res://tests/audit_first_battle_balance.gd
```

开发开关（与 `tests/README` 的 `HSL_AUTOPLAY_*`／`HSL_RNG_SEED` 同一写法，只在环境变量里存在、不进产品数据）：`HSL_CUTIN_PLAYBACK_SPEED=0.4 tools/play.sh …` 把攻击特写整段放慢到 0.4 倍以便逐帧审看；不设＝1.0 原速（产品默认），非正数或非数字 `push_error` 并按 1.0。唯一读取点 `game/battle/runtime/CombatPresentationTiming.gd`（`PLAYBACK_SPEED`），各演出模块经 `Timing.scaled` 换算，受击三段与施法引导的可见时长不随它变。`HSL_DEBUG_PAUSE`：P 停格／N 单步（[DebugPause](../game/debug/DebugPause.gd)）的开关，`tools/play.sh` 默认 `1`（实玩与 `playtest.sh` 照常能用），`0` 关；不设时无窗口进程开、有窗口进程关，正式玩家不会误触。`HSL_OPTIONS_PRESET=original|comfort`：无窗口进程里替换玩家的重製選項预设（「舒适全开」冒烟用，打印 `OPTIONS_PRESET_OVERRIDE`；有窗口时忽略），唯一读取点 `game/settings/GameOptions.gd`，见 [OPTIONS](../docs/OPTIONS.md)。

完整路线输出到 `ignored/first-battle-playthrough/`，规则抽样到 `ignored/first-battle-balance/`。GUI 只在内建屏运行，前一窗口退出后再开下一条。检查退出状态、明确的 PASS 以及日志无 `SCRIPT ERROR:` / `ERROR:` / 资源泄漏；Godot 退出 0 不等于成功。两类较长验收不加入常规快速门禁；`verify.sh` 自己在导入前清理生成缓存并执行 cold import。

### Shared presentation references

Coverage list: `docs/evidence_packets/runtime_observations/presentation_reference/cases.json`; conclusions in `docs/evidence_packets/static_reverse/native_presentation_helpers.md`.

- `hsltools/assets/command_frames.py`: imports/checks every declared BCMD frame, including the five-frame Status icon.
- `hsl_record_window.swift`: explicit Wine/Godot window recording, built-in display guard, 1–60 seconds, application audio but no microphone/whole-desktop capture; `--list` reports eligible windows; `--no-audio` records video only. Known limit (2026-09-22): against the original's Wine window ScreenCaptureKit delivered only the first ~0.9 s of frames in every attempt (Godot windows record normally); measure original timing through `hsl_win32_memread.exe --repeat` instead.
- `PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference record/check/report`: records raw receipts, validates audio/video/actual duration, checks curated media hashes and event coverage, and builds `ignored/presentation-reference/compare.html`. Incomplete reference cases remain visible; `check --require-complete` currently fails intentionally on missing original states.

The Win32 control helper accepts explicit `--focus` before an input action; the Python wrapper exposes the same flag. Focus and input injection do not prove the game accepted an action. Keep original sampling bounded and inspect its output before the next step. Do not attempt to unlock a screen through the automation.

### 原函数合同与完整动作程序接入

优先读取 `docs/evidence_packets/static_reverse/native_presentation_helpers.md` 和 `animal_program_execution.md`。不必先开 Wine 才能检查菜单或动作顺序。

```sh
python3 tools/hsl.py check menu_layout
python3 tools/hsl.py check command_frames
python3 tools/hsl.py check panel_assets
python3 tools/hsl.py check animal_programs
python3 tools/hsl.py check combat_animation
# 明确更新 ordinary 接入数据时使用，不重导任何 SHP 像素：
PYTHONPATH=tools python3 -m hsltools.assets.combat_animation --bind-programs
# 可选原指令分析依赖，不属于普通运行/验证依赖：
uv run --no-project --with 'unicorn>=2,<3' --python /opt/homebrew/bin/python3 \
  python tools/hsl_native_presentation_probe.py --output ignored/native-menu-rerun.json
```

Godot 只读取 compact 资源/合同，不执行原 EXE。普通动作仅绑定当前明确支持的三类 opcode，未知指令拒绝接入，不静默降级。源派发调用次数、映射秒数和整体画面一致分别记录。
