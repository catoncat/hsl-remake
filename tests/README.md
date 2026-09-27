# Test routing

按改动命中下面的 [Godot suites](#godot-suites) 表，读实际测试和调用者。定向检查用于开发迭代；完整交付门禁仍只有 [tools/verify.sh](../tools/verify.sh)。产品是否完成看 [PROJECT](../docs/PROJECT.md)，测试存在不等于能力已接入。原版事实写在证据包（[docs/evidence_packets/](../docs/evidence_packets/)），表里「证据」列写包名。

## 测试政策

[AGENTS.md](../AGENTS.md)「测试政策」：测试只守两类——①原版量得的事实（static-derived／模拟器实测），且没有别处覆盖；②不写就会让门禁抓不到伤玩家的回归。重制自定值（provisional、remake-invented、演出时长、面板坐标、某种子下的随机产物、动作计数）不钉数值，只断言不变量。

已由别处覆盖、套件里不再重复的：128 场自动对局（胜负／回合／阵亡）、全程剧情 explorer（每段剧情跑到底、城镇菜单穷举、三个结局可达）、`hsl check enemy_turn／ai_replay／ai_action_frequency／opening_snapshot`（原版 AI 逐帧、频率与开局盘面对照）、`hsl check` 的数据与生成物检查（schema、字段覆盖、来源头、差异清单、文档链接）、`run_scene_smoke`（主入口能启动）。所以机制套件只留原版对拍（`native_*`）与玩家可见的核心路径，不再逐套件写三终态、篡改存档、坏数据拒绝、演出细节和无原版依据的 AI 用例。

本目录的落实：

- **局面只经真实入口造**：从 `static func` 夹具出发，走玩家／AI 同样走的公开入口（`choose_command`／`move_unit_to`／`attack_target`／`use_item`／`step_ai_turn`……）；不用私有函数拼玩家到不了的局面。现存旧用法改到时换成真实路线。
- **随机流只经 [TestSuite](support/TestSuite.gd)**：`stream_of`／`set_stream`／`seed_stream`／`no_draw`／`continues`／`carries_no_stream`，桩用 `zero`／`high`／`no_rng`；不直接写流的内部键。
- **规模按手写断言点和耗时报，不按 `checks=`**（循环里的一处 `check(` 会计上千次）：`grep -ohE '(^|[^[:alnum:]_.])(check|_assert_true|_assert_eq)\(' tests/*.gd tests/*/*.gd | wc -l`。
- 一次性诊断脚本放 [diagnostics/](diagnostics/)，用完即删；新用例优先加进现有套件，不新开文件。

## Harness

Godot 套件按首行分两类，[tools/verify_runner.py](../tools/verify_runner.py) 与 [run_all.gd](run_all.gd) 只看这一行：

| 类别 | 首行 | 运行 |
| --- | --- | --- |
| 规则套件（不启动运行时场景） | `extends "res://tests/support/TestSuite.gd"` | [run_all.gd](run_all.gd) 在一个进程内顺序跑，门禁按 [support/suite_timings.json](support/suite_timings.json) 装箱成 4 片；结果行 `TAG_PASS`，总行 `RULE_SUITES_PASS suites=N` |
| 场景套件（启动战斗／标题／大地图／城镇，等 timer，写 `user://`） | `extends SceneTree` | 一套件一进程、各自独立 `HOME`；结果行各自的 `TAG_PASS` |

入口（仓库根执行；首次或资源／脚本变化后先 `tools/godot.sh --headless --import`，新 `.gd` 由它生成 `.gd.uid`）：

```sh
tools/godot.sh --headless --script res://tests/run_all.gd                       # 全部规则套件
tools/godot.sh --headless --script res://tests/run_all.gd -- run_tests.gd       # 一个规则套件（直接 --script 规则套件也会被改写成这条）
tools/godot.sh --headless --script res://tests/run_battle_scene_runtime_tests.gd  # 一个场景套件
HSL_SWEEP_LEVELS=26,34 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_battle_sweep_tests.gd
HSL_AUTOPLAY_LEVELS=51,501 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd
python3 tools/verify_runner.py godot      # 门禁同款：全部 Godot 套件并行
python3 tools/verify_runner.py deep       # 深门：explorer、自动对局、整章机器人
python3 tools/verify_runner.py godot && python3 tools/verify_runner.py promote-timings   # 改重套件后更新计时（只新增套件用 --missing）
```

- [tools/godot.sh](../tools/godot.sh) 严格诊断：进程非零、SCRIPT ERROR／ERROR 或资源泄漏都算失败，不能只看末尾 PASS。
- 随机种子：无窗口运行默认 `HSL_RNG_SEED=1`（伤害流与进程全局流），两次运行结果行逐字相同；`HSL_RNG_SEED=7` 换种子。
- **快钟**：`FAST_CLOCK_SUITES`（verify_runner）里的场景套件跑 `--fixed-fps 60`，每步恒 1/60 s、不睡帧。开机后等时间线推进的断言用 `TestSuite.await_condition(tree, 条件, 帧上限)`；等音频释放用 `TestSuite.settle_wall_clock`，`quit` 前最后一次等待用 `TestSuite.settle_audio_before_quit`。上快钟的套件在实时钟（`HSL_TEST_FIXED_FPS=0`）下也要通过。
- 规则套件改 loop 的只读配置块（`skill_book`／`ai_profiles`……）用 `TestSuite.own(loop, "ai_profiles")`，就地写共享块会以 `wrote the shared configuration block` 失败（[配置／状态分离](../docs/architecture/BATTLE_CONFIG_STATE.md)）。
- 读已启动 `BattleSceneRuntime` 的状态用 [support/RuntimeReadback.gd](support/RuntimeReadback.gd) 的静态摘要；写 loop 只经 `scene.apply_loop(loop, "test")`。
- 自动对局与整章机器人的旋钮（`HSL_AUTOPLAY_BRAIN`、`HSL_AUTOPLAY_HANDOFF`、`HSL_CHAPTER_START`、`HSL_CHAPTER_BUDGET_SECONDS`……）写在 [support/Autoplay.gd](support/Autoplay.gd)、[support/AutoplayBrain.gd](support/AutoplayBrain.gd) 与两个套件文件头。

## Godot suites

每行：守什么／证据（证据包名，`sr/`＝`static_reverse`，`ro/`＝`runtime_observations`）。

| 套件 | 守什么 | 证据 |
| --- | --- | --- |
| [tests](run_tests.gd) | 核心规则：地形移动、行动队列与同速登记序、命中伤害包、经验升级、第一批 NPC 回合、射程地形传播、伤害／全局随机流与存档、阵营位（谁打谁） | `sr/initial_battle_initiative`、`sr/original_damage_random`、`sr/original_player_mode_sides`、`sr/original_range_terrain` |
| [job_stats](run_job_stats_tests.gd) | 职业初始化与派生属性刷新、主线角色模板 | `sr/original_job_stats`、`sr/original_campaign_actors` |
| [inventory_equipment](run_inventory_equipment_tests.gd) | 八槽库存、换装、原成长输出、给予／满包交换 | `sr/original_inventory_equipment`、`sr/original_give_exchange` |
| [treasure](run_treasure_tests.gd) | 原宝箱 3 箱 8 物、拾取与第二行动、跨场待领 | `ro/treasure` |
| [extra_attack](run_extra_attack_tests.gd) | 追加攻击／白光之翼两次行动的原来源与逐击结算 | `sr/original_extra_attack`、`ro/extra_action` |
| [position_equipment](run_position_equipment_tests.gd) | 射程饰品、施法装备、移动力装备的原返回 | `sr/original_casting_equipment`、`ro/equipment_mobility` |
| [resource_recovery](run_resource_recovery_tests.gd) | 减耗、末次行动毒伤与资源回复的原算术（夹具被 position_equipment 复用） | `sr/original_resource_recovery` |
| [support_magic](run_support_magic_tests.gd) | 回复／驱毒／增益／退魔／祭司与麻痺的原应用、refresh 与 tick | `sr/original_support_magic`、`sr/original_paralysis`、`ro/stat_magic` |
| [mobile_jobs](run_mobile_jobs_tests.gd) | 盗贼／翼战士职业与末击削魔、跨战携带 | `sr/original_mobile_jobs` |
| [moon_dance](run_moon_dance_tests.gd) | 月花圓舞自身中心多段范围的原应用 | `sr/original_moon_dance` |
| [water_strike](run_water_strike_tests.gd) | 水剎真实范围与原数值 | `sr/original_water_strike` |
| [permanent_items](run_permanent_items_tests.gd) | 永久道具四职业对拍、抗性上限、跨战携带 | `ro/permanent_items` |
| [tactical_items](run_tactical_items_tests.gd) | 战内道具原数值、混合状态与独立随机流 | `sr/original_tactical_items` |
| [ordinary_special](run_ordinary_special_tests.gd) | 普通／反击暴击、武器附加、氣刃斬、战斗积气 | `sr/original_ordinary_special`、`sr/original_stamina` |
| [weapon_effect](run_weapon_effect_tests.gd) | 武器末击附毒／状态字与未来行动取消 | `sr/original_weapon_effects` |
| [magic_experience](run_magic_experience_tests.gd) | 风火伤害、支援贡献、最终 EXP 与连续数 | `sr/original_experience` |
| [skill_resolution](run_skill_resolution_tests.gd) | 技能结算的原版数值（命中先于三角骰、各元素抗性槽、衰弱／麻痹／治疗／增益／吸血／回合效果／偷金偷物的原版地址与阈值）、初始拥有来自 PLAYERS 声明、费用、目标模式与覆盖、共同提交、预览脚印＝结算格；坏 descriptor 归 `hsl check skill_coverage` | `sr/original_skill_resources`、`sr/original_skill_targets`、`sr/original_magic_damage`、`sr/original_skill_function_bits`、`sr/original_steal_ratio` |
| [status_application](run_status_application_tests.gd) | 状态施加掷骰、生命周期与到期 | `sr/original_status_application`、`sr/original_status_effects` |
| [entry_growth](run_entry_growth_tests.gd) | 新援入场调级（含第 6 关 opcode 73 两段式）与实例奖励 | `sr/original_auto_growth` |
| [growth_lifecycle](run_growth_lifecycle_tests.gd) | 初始阵容／NPC 升级、动态学技 | `sr/original_growth_lifecycle` |
| [departure](run_departure_tests.gd) | 脚本离场队列的原单步结果 | `sr/original_script_departure` |
| [script_wait](run_script_wait_tests.gd) | 脚本赋值、AI 倒数／唤醒、对象等待 | `ro/script_wait` |
| [ai_decision](run_ai_decision_tests.gd) | AI 目标选择 helper（夹具被多套件复用） | `sr/original_ai_decisions` |
| [ai_skill](run_ai_skill_tests.gd) | AI 技能桶／概率／距离、呼叫 | `sr/original_ai_skills`、`sr/original_ai_calls` |
| [ai_support](run_ai_support_tests.gd) | AI 友军扫描、自救优先级 | `sr/original_ai_support`、`sr/original_ai_priority` |
| [ai_navigation](run_ai_navigation_tests.gd) | AI 四邻扩展逐格对拍、追击精化落点 | `sr/original_ai_navigation`、`ro/battle_051_ai_moves` |
| [actor_traversal](run_actor_traversal_tests.gd) | 角色通行、源高度、同伴经过 | `ro/actor_traversal` |
| [large_actor](run_large_actor_tests.gd) | 3×3 大型占格 flood 与命中去重 | `sr/original_large_actor` |
| [gol_road](run_gol_road_tests.gd) | 戈爾山道两阶段入队与后生 | `ro/gol_road` |
| [ohm_village](run_ohm_village_tests.gd) | 歐姆村编队、弓手近身负格、毒魔箭 | `ro/ohm_village` |
| [winfail_rules](run_winfail_rules_tests.gd) | winfail 解释器：52／53 战 golden 序列、原版 token 语义（0x450840 计数分支、状态挂起与连锁、原生动作、目标板与下一关 token、我方总数）、扫描节拍、全部战斗原则上打得赢；坏 seed／未知 token 归 `hsl check winfail_coverage` | `sr/original_check_targets`、`sr/original_round_display`、`sr/winfail_claim_limits` |
| [town_event_rules](run_town_event_rules_tests.gd) | 城镇 te 解释器：对白／金钱／商店／子菜单／神秘商人／转职 | `sr/town_event_semantics`、`sr/original_secret_man` |
| [story_object_terrain](run_story_object_terrain_tests.gd) | 剧情物件改地形、脚本走位逐格不穿墙 | `sr/original_story_object_terrain`、`sr/original_script_walk_path` |
| [camera_panel_motion](run_camera_panel_motion_tests.gd) | 镜头滑动与面板运动的原节拍、脚本定位镜头 (320,192) | `sr/original_script_camera_scroll` |
| [walk_camera_follow](run_walk_camera_follow_tests.gd) | 第 51 战走路时镜头跟随（生产帧） | `ro/camera_panel_motion` |
| [skill_effect_script](run_skill_effect_script_tests.gd) | EFFECTS.TXT 特效脚本、ANIMAL 程序、切入站位与飘字、地图姿势 | `sr/animal_program_execution`、`ro/effect_motion`、`ro/cutin_floaters` |
| [presentation_contract](run_presentation_contract_tests.gd) | 共享演出合同：对白、身份遮罩、施法叠层、引导、AI 提示镜头 | `sr/native_presentation_helpers`、`ro/menus_ui` |
| [ui_class_contract](run_ui_class_contract_tests.gd) | 全游戏 UI 类问题（原图不拉伸、亮字对位、断词、字库覆盖）、原版光标、段落标题卡 | `sr/original_dialogue_board`、`ro/game_cursor` |
| [battle_scene_runtime](run_battle_scene_runtime_tests.gd) | 战斗场景：空间合同、选择／移动／取消与指针输入、切入序列、成长分配、施法与道具 | `ro/menus_ui`、`sr/original_draw_order` |
| [combat_aftermath](run_combat_aftermath_tests.gd) | 交锋收尾：死亡／经验／终局次序、升级窗弹给谁 | `ro/combat_aftermath`、`sr/original_growth_window` |
| [battle_reward](run_battle_reward_tests.gd) | 金币／掉落／携带与加倍、领取次序 | `ro/battle_rewards` |
| [story_scene](run_story_scene_tests.gd) | 全部 story 场景可启动、略過戰鬥写入、结局分支、营地／王座厅链 | `ro/story_scene_0*` |
| [town_scene](run_town_scene_tests.gd) | 城镇画面：队伍规则、商店买卖 | `ro/town_scene` |
| [campaign](run_campaign_tests.gd) | 战役承接、下一战去向、carry、转职携带、存档进度 | `ro/campaign_handoff` |
| [system_menu](run_system_menu_tests.gd) | 战斗内 Esc 卷轴、战场记录存读、回憶錄 | `ro/menus_ui` |
| [title_screen](run_title_screen_tests.gd) | 标题菜单、战场记录继续、GameClear 谢幕 | `ro/title_screen` |
| [authored_level](run_authored_level_tests.gd) | 自制关卡端到端（[MODDING_LEVELS](../docs/MODDING_LEVELS.md) 的最小原文与 level 200） | — |
| [battle_sweep](run_battle_sweep_tests.gd) | 全部注册战斗产品开场的规模护栏 | `ro/battle_0*` |
| [scene_smoke](run_scene_smoke.gd) | 主入口启动（另以 `HSL_OPTIONS_PRESET=comfort` 跑一次） | — |
| 深门：[autoplay_sweep](run_autoplay_sweep_tests.gd)、[chapter_autoplay](run_chapter_autoplay_tests.gd)、[story_mode_explorer](run_story_mode_explorer_tests.gd) | 128 场自然胜负、整章机器人通关、全程剧情探索（`tools/verify.sh --deep`） | `results.json`／`chapter.json` |

## Python

`tools/test_hsl_*.py` 只守工具逻辑：注册表与门禁（registry、verify_runner、doc_tool_references、evidence_index、godot、play、play_original、shell_var_braces）、仓库级玩家回归（unit_schema、opening_positions、story_object_terrain、story_token_coverage）、解码器与编译器（levels、level_battle、battle_seed、data_tasks、assets_tasks、data_native、payload_inspector、script_vm_semantics、static_export、resource_scanner、runtime_probe、wrd_decode、world_map、story_corpus、movie_import）、独立原指令探针（native_growth、native_growth_refresh、native_map_scroll、enemy_level）。生成器与证据包本身由 `hsl check` 用 tracked 数据校验。

```sh
python3 -m unittest discover -s tools -p 'test_hsl_*.py'
python3 tools/hsl.py check docs            # 文档代码里的工具路径与 hsl 任务名
python3 tools/hsl_docs_check.py            # 链接、图片、标题锚点
```

## Visible acceptance

[play_battle.gd](play_battle.gd) 开发直达指定战斗（`tools/play.sh --script res://tests/play_battle.gd -- 003`），[run_first_battle_playthrough.gd](run_first_battle_playthrough.gd) 正常时钟走完第一战，都不进门禁。`capture_*.gd` 是证据包回执与公开截图的窗口化驱动，不进门禁；用法与原作采样限制见 [工具说明](../tools/README.md#godot-capture-harness)。修改玩家可见布局／动画必须看截图或录屏。
