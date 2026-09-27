# Current Runtime Architecture

攻防增益／退魔：`StatEnhancementRules`保存packed正向状态合同，`StatMagicRules`生成单目标变化；既有`SkillResolutionRules`／PlayLoop负责一次MP付款、贡献／EXP与当前派生值提交。AI援助桶5、驱散进攻桶、末次计时v4及Checkpoint共同读取当前来源。表现为`SkillEffectScriptPlayer`（effCode27／06／33 脚本）／Vitals／状态页／TurnEndCue，入口`game/battle/development/StatMagicTrial.tscn`，定向`tests/run_support_magic_tests.gd`（stat 部分；试验场景启动在`run_battle_scene_runtime_tests.gd`）；[证据与边界](evidence_packets/static_reverse/original_stat_magic.md)。

Checked: 2026-09-17

本文描述当前 live code 与接手入口。历史实现、截图和验证过程留在各 evidence packet／Git 历史，不作为现行代码合同；产品优先级只看 PROJECT。

## Task routing

视觉任务先读 [已审查的录像观察](evidence_packets/runtime_observations/original_gameplay_reference/README.md)，再按下表进入实际模块。录像参数和截图不是新的运行时配置；对白／选择的后续实现与对照见 [可见验收](evidence_packets/runtime_observations/dialogue_selection/README.md)。

| 任务 | 代码入口 | 验证与约束 |
| --- | --- | --- |
| 查一个模块的规则／版式／文字／时序／配乐各自从哪来，或新增模块 | 模块文件头 `## provenance:` 块（见下方 [Provenance headers](#provenance-headers)）；汇总 [PROVENANCE](PROVENANCE.md) | `python3 tools/hsl.py check provenance`；改头后 `generate provenance` |
| 开场／战中对白和分页 | `BattleDialogue`；Runtime `_update_opening_overlay/advance_opening_timeline` 和 Presentation `_update_dialogue_page/advance_dialogue` | runtime／presentation tests；共享 BOARD02、原肖像与原版四行窗口（名字占第 0 行、38 字节断行、确认后逐行上卷）；完整 RESOURCE 正文不截断；消息推进仍归原调用者 |
| 非第一战的 scenario 开场（level 52） | `BattleOpeningCoordinator`；scenario `opening.actor_bindings` 与编译 timeline；Runtime 只在 `_ready/_apply_startup_mode/_process/_input` 四处委托 | second_battle_opening tests＋[开场回执](evidence_packets/runtime_observations/second_battle_opening/README.md)；镜头目标／走位／插入／标题／状态 token 按源顺序播放，节奏为明示重制值；结束前把全部 actor 复位到 PlayLoop 格 |
| 玩家看到的文字是简体（原版字库画法） | autoload `game/text/SimplifiedDisplay.gd` 安装唯一接缝 `SimplifiedDisplayTranslation.gd`（Godot `Translation`）；逐字表 `content/generated/hsl/text/simplified_chars.json`（`hsl generate simplified_chars`，输入 [原版字库审读](evidence_packets/static_reverse/original_font_script/README.md)） | `hsl check content:simplified_display`（玩家文字经表后不得剩仅繁体字、烘焙繁体字的图须有简体重画或保留理由；消融 `tools/test_hsl_simplified_display.py`）＋ui_class_contract `simplified_display`；文字源（数据、GDScript 字面量、`label.text`、存档）保持繁体原文，只在 Control 显示时一字换一字；新繁体字无审读即失败；烘焙繁体字的图经 `SimplifiedDisplay.texture_path` 换成 `hsl generate workteam_simplified` 这类重画；测量换行用 `label.atr` 的显示形 |
| 调试停格／逐帧（用户实玩调试：P 停格、N 走一帧；开发开关） | autoload `game/debug/DebugPause.gd`，由 `HSL_DEBUG_PAUSE` 开关（`1` 开、`0` 关；不设时无窗口进程开、有窗口进程关；`tools/play.sh`／`tools/playtest.sh` 默认设 `1`，关时节点仍在但不收键、不碰暂停）：`SceneTree.paused` 冻结全部场景（节点、tween、动画、音频随暂停）；自身 always 处理且 `process_priority` 最先，单步帧的 `_process`／计时器／tween 走完才重新冻结；保持为 root 最后一个子节点，使 P／N 先于各场景"任意键"处理（跳动画、翻对白）被收走 | 无专属测试（开发工具，TESTCUT2 删）；游戏代码的 SceneTree 计时器一律 `create_timer(秒, false)`，除续战提示、鼠标光标、Tab 重製選項页与停格本身外不得 always／when_paused 处理，否则停格时仍会走 |
| 鼠标光标（全游戏同一支原版红宝石权杖） | autoload `game/cursor/GameCursor.gd`：读 `content/imported/hsl/shared/game_cursor/manifest.json`（`hsl generate game_cursor`，155 个原版 OBS 的 object 2 游標），照原版画进游戏自己的 640×480 画面：root 视口最上层 CanvasLayer（1025，高于内嵌弹窗 1024）上的 Sprite2D，随窗口与画面一起缩放，热点 = SHP draw origin 落在指针所在逻辑像素；窗口有焦点且指针在画面内才隐藏系统指针，信箱边／窗外／失焦还原系统箭头；always 处理跟手，6 tick 一帧、换帧随暂停停 | `tests/run_game_cursor_tests.gd`（热点落在红宝石与指针逻辑像素、源尺寸画在最上层、逐 tick 换帧、普查 `game/` 别无光标来源或隐藏系统指针）＋`hsl check game_cursor`；[证据](evidence_packets/runtime_observations/game_cursor/README.md)；原版隐藏条件与持物图标未接 |
| 重製選項 Tab 入口（任何画面按 Tab 开关重製選項页） | autoload `game/settings/RemakeOptionsHotkey.gd`：`_input` 收 Tab → CanvasLayer 100 上懒建 `RemakeOptionsPage`（与 設定選項 › 重製選項 同一页），开着时 `SceneTree.paused`、键鼠全进页，Tab／Esc／右键关页并还原开页前的暂停；自身排在当前场景之后（停格开着时紧挨其前），Tab 先于场景各处理；系统卷轴里的页已开时 Tab 留给那一页；页开着时有人放开暂停（停格 P／N）下一处理帧重新暂停。页关闭且取值变了对 `remake_options_listeners` 组调 `remake_options_changed()`（BattleSceneRuntime 重读 OPT-TREASURE） | 无专属测试（AGENTS 测试政策）；窗口化截图人工验收 |
| 状态、肖像、资源和装备信息 | `BattleStatusPanel.show_unit`、`BattleVitals`、`BattleEquipmentView`、`BattleUISkin` | runtime／presentation tests；魔擊力格式化 live 值加 `%`，不缩放数值；单人镜头的左右栏始终属于同一角色 |
| 菜单开合／悬停／命中 | `BattleCommandMenu`、`CommandPresentationRules` | `run_presentation_contract_tests.gd`；复用源 BCMD 与原整数布局，不重新写固定六边形 |
| 移动／攻击格与镜头／脚点／遮挡 | Runtime `_configure_move_overlay/_refresh_move_overlay/_refresh_attack_overlay`；`MapSceneConfig`、`BattleCameraController`、`ActorRuntime` | curated visual index＋runtime tests；方形单格，保持 viewport→logical→world→grid 与单一占格真相 |
| 装备移动力、初始化／成长与取消 | `MobilityRules`、`EquipmentRules`、`ProgressionRules`；PlayLoop初始化／change_equipment；Checkpoint | equipment_mobility tests；源base+当前装备夹0..12，唯一move_point驱动玩家／AI；取消重新算现预算、不回滚装备；严格恢复一致性 |
| 永久能力来源、原始抗性与物品获得 | `PermanentCapabilityRules`、`ItemResolutionRules`、`ProgressionRules`、PlayLoop初始化及StatusPanel | permanent_items tests；独立九字段、实际库存一次采样和付款、原始与派生两处80、共同成长／当前装备／状态／保存／终态；[源合同](evidence_packets/static_reverse/original_permanent_items.md) |
| 职业源mode、属性／cap与派生刷新（公式表 `content/authored/roles/job_formulas.json`） | `hsltools/data/job_formulas.py`／`model/jobs.py`、`hsltools/data/role_profiles.py`、`JobStatsRules`、`ProgressionRules`、第一／第二战生成器 | job_stats tests；216完整原返回，源mode独立控制HP等级项，NPC职业／装备抗性、MP、当前资源夹取与重复刷新；固定NPC不新增经验 |
| 槽1→002祭司、非Leonard控制与初始回魔 | `hsltools/probes/priest.py`／`hsltools/data/priest.py`、JobStats85、`DevelopmentBattleRules`、Runtime／Checkpoint主角字段、ItemUseRules | priest tests；44完整刷新／20绑定返回／39运动更新／42物品前段；原治疗与EXP、减耗／移动／第二行动、六帧起跳、当前资源和三终态；029仍为演出角色 |
| 减耗、末次行动毒伤／HP／MP回复 | `ResourceRecoveryRules`、`TurnEndRules`、PlayLoop `_advance_current_actor`、`BattleTurnEndCue` | resource_recovery tests；当前装备与上限、独立保存RNG／不可变尾部收据；最后动作才恢复，原先用药／交锋先展示，终态及读档不重放 |
| 施法装备、防护／命中与生命转魔力 | `StatusApplicationRules.modifiers`、`ResourceRecoveryRules`、`TurnEndRules`、装备面板及尾部数字 | casting_equipment tests；当前来源OR防护、主命中增量；回血回魔后才转换，满MP代价／1HP保底、两次行动／升级／AI重选／终态和保存 |
| 脚本离场、已播游标与恢复 | `BattlePresenceRules`、Winfail／PlayLoop、`BattleScriptPresentation`／`BattleDepartureView`、Checkpoint／Settlement | departure tests；历史与在场分离、九格释放、AI交锋事件、脚本配置摘要、开场F9及跨战；[来源](evidence_packets/static_reverse/original_script_departure.md) |
| 开场／事件等待、守备唤醒与对象同步 | `ScriptWaitRules`、Winfail／PlayLoop消费游标、`BattleScriptCoordinator`、NavigationCue／Checkpoint | script_wait tests；源052四个wait2，当前实例覆盖及增援按序设置，重复／恢复不重放；指定对象停止才继续，其他运动不阻塞；[地址及边界](evidence_packets/static_reverse/original_script_wait.md) |
| 脚本增援调级与独立出生加成 | `EntryGrowthRules`／`ReinforcementGrowthRules`、PlayLoop生成事务、Progression／BattleReward／Checkpoint | entry_growth tests；128数值函数＋16VM序列、显式零覆盖、职业配额、占地成功才抽样、实例奖励、第二行动前新阵容、保存RNG链；[原函数与范围](evidence_packets/static_reverse/original_auto_growth.md) |
| 初始全阵容、NPC交锋成长与动态学技 | `InitialRosterGrowthRules`、`LearningRules`、Progression／PlayLoop、Aftermath／GrowthPanel、Checkpoint | growth_lifecycle tests；原caller、手动／自动分支、初始声明／取得位分层、等级／基础属性资格、真实第三战跨队游标红绿回归；[来源与可玩入口](evidence_packets/static_reverse/original_growth_lifecycle.md) |
| 独立队伍间的生成流延续 | `GrowthCampaignProgress`薄继承既有CampaignProgress、`CampaignCarryRules.initialization_only` | 不改目标／世界／story／队伍政策，只把唯一PlayLoop的游标放入已完成handoff；不携带别队人物、金币或临时状态，重开从入场游标重放 |
| 原实例宝箱、待领物品与跨场继续 | `hsl_treasure_data`、`TreasureRules`、PlayLoop／Reward／Checkpoint、`BattleTreasurePresentation`、`GrowthCampaignProgress` | 原三箱八物、完成行动才发现、独立领取／交锋序列、满包交换／取消／第二行动／F9；普通队伍已延后物品经真实继续按钮保留，JSON空槽与开发入口让出；[原地址](evidence_packets/static_reverse/original_treasure.md)及[八条实际输入](evidence_packets/runtime_observations/treasure/README.md) |
| 关卡原地图的装载来源 | `hsl_source_map_binding` → `hsl_battle_seed.build/check` → 既有Runtime地图Texture2D | 先读OBS，再按完整obj_Shape_Name取PAK；离线钉住原OBS／SHP哈希和尺寸，旧别名仅兼容注记，不创建场景侧第二份真相；[源边界](evidence_packets/static_reverse/original_map_binding.md)与[实际场景](evidence_packets/runtime_observations/map_binding/README.md) |
| 移动后施法阶段与普通攻击范围装备 | `PositionCapabilityRules`、PlayLoop命令／确认／`weapon_pattern`、AISkillPlanning／AISupportPlanning／AINavigationRules | position_equipment tests；当前来源与阶段、取消／装卸／独立第二行动／保存、AI原地或移动施法；源范围索引只影响普通和反击 |
| 麻痺入场跳过、计时／解围与恢复 | `ActionEntryRules`、`StatusEffectRules`、PlayLoop `step_ai_turn/_return_to_player`、`ItemUseRules`／AISupportPlanning、`SkillEffectScriptPlayer`（地靈縛 effCode05） | paralysis tests；原入口绕过额外行动查询、一次完整尾部／终态优先；地靈縛、精靈石、防护／成长、友军解除、现状态重决策、存档与有限可见反馈 |
| 角色通行、高差、路径预览与停留 | `ActorTraversalRules`、`TacticalGridRules`、`AINavigationRules.advance_path`、`BattleMovementPreview`；`WrdTerrainTiles` | actor_traversal tests；可经过格与可停格分开，原高字节h、固有能力／存档一致，AI前缀不落同伴身上；结果可见时清理终态AI播放 |
| 大型角色占地、身体边缘与区域去重 | `FootprintRules`、`ActorTraversalRules`、`SkillTargetRules`、PlayLoop与Checkpoint；Runtime只读命中 | large_actor tests；单一actor派生3×3，占格／释放、整块四邻路径／停留、攻击／反击和空格施法、道具邻接、AI重规划、源039及开发场景；[来源](evidence_packets/static_reverse/original_large_actor.md) |
| 白光之翼、同角色第二次行动与恢复 | `ExtraActionRules`、PlayLoop `_advance_current_actor`、`BattleExtraActionCue`、Checkpoint | extra_action tests；第一次完成按当前装备授予一次，第二次后才状态／队列；换装／成长／保存不增加次数，AI重新决策，提示避开源菜单 |
| 当前选格、技能名和目标信息避让 | `BattleSelectionCursor`、`BattlePresentation.show_selection/preview_target` | Runtime 在镜头更新后传入同一命中格的逻辑矩形；不持有目标资格；取消／离窗／模态时清除；下缘目标的信息栏移到上方是重制取舍 |
| 普通攻击、气刃斩、地图法术 | `BattleAttackCue`、`BattleCombatCutin`、`CombatPresentationTiming`、`AnimalCastLead`（绝技切入的 ANIMAL s_action 施法引导）、`BattlePresentation` | presentation／runtime／animal_program tests；消费原程序与不可变 receipt，impact 一次，不复制 HP 或回合状态 |
| 改任何演出时长、帧率或速度 | `game/common/OriginalTick.gd`（唯一 tick 常数：16 ms＝62.5 tick/s；`seconds(n)`／`ticks(s)`／`ticks_from_host_seconds`）；数字寿命、受击预算与 `PLAYBACK_SPEED` 在 `CombatPresentationTiming`；行走／待机节奏在 `ActorRuntime` | 以 tick 计的量一律 `OriginalTick.seconds(n)`，头部 timing 写来源；无 tick 依据的重制节拍如实标 remake-invented；证据见 [tick 率](evidence_packets/runtime_observations/original_tick_rate/README.md)、[tick 计数](evidence_packets/static_reverse/original_tick_counts.md)与[映射表](evidence_packets/runtime_observations/original_tick_rate/tick_mapping.md) |
| 新增一个技能／法术的演出 | `skill_effects/manifest.json` 的 `rows[skill_id].presentation`（`script` 默认走 `SkillEffectScriptPlayer`；`dedicated_module` 指定 `game/battle/scene/<Module>.gd`，须 `extends SkillPresenter.gd`）；Cutin 只持 `presenters` 列表 | skill_effect_script／presentation tests；`hsl check skill_effects` 守 manifest；Cutin 无按技能名分派 |
| 普通／反击伤害、暴击、武器附加与氣刃斬 | `CoreCombatRules`、`SpecialDamageRules`、`SkillResolutionRules`；`EquipmentRules/ProgressionRules`刷新 | ordinary_special tests；原数值／RNG对拍，queued伤害供气力、actual伤害供经验与显示；换装及成长不丢当前武器／概率 |
| 月花圓舞、自身范围与逐目标五段 | `RepeatedSpecialRules`、SkillResolution／SkillTarget、PlayLoop绝技选择、`MoonDancePresentation`、Checkpoint | moon_dance tests；315原应用／14前段、一次20ST付款、HP0后抽样零贡献、全段使用既有连杀／等级、最后经验和死亡去重；实际13路线与三终态 |
| 追加攻击与整段交锋 | `CombatSequenceRules`；PlayLoop `_resolve_attack_series`、`_award_experience`；Cutin逐击快照 | extra_attack tests；主／反击各最多两击，死亡截断、末击积气、参与者一次EXP，死亡／掉落／播放共用序列遍历；不是额外回合 |
| 武器末击附毒、未来行动取消与防护 | `WeaponEffectRules`、PlayLoop `_apply_strike/change_equipment`、`CoreTurnQueue.cancel_pending`、Checkpoint及Cutin受击快照 | weapon_effect tests；每击EXP后按实际末击取当前来源，取消→附毒→气力；不重复机会／贡献，反击与第二行动独立，取消选点和取消未来槽分开 |
| 盗贼／翼战士、宿魔刀与逐击MP | `JobStatsRules`／`hsltools/data/role_profiles.py`、`WeaponEffectRules`、PlayLoop `_apply_strike`、`BattleCombatCutin` | mobile_jobs tests；184职业完整刷新、54原HP／削魔组合与75caller前段；末击实际HP/3削目标MP，不回魔；004／006源映射、默认能力差异、当前装备／永久／状态、AI重选／保存／跨战／三终态 |
| 地图法术短资源条／实际伤害、支援最终EXP | `MagicImpactPresentation`、`ExperienceRules`、PlayLoop `_award_experience`、`BattleAftermath` | magic_experience tests；原数值→每目标经验→动作一次入账→表现；接收者反馈完毕才显示EXP／遗言，不另造胜利经验池 |
| 自身／友军回复、范围驱毒与AI自保 | `SupportMagicRules`、`AISelfPreservation`、`SkillEffectScriptPlayer`（effCode12–15）；共同SkillResolution／PlayLoop | support_magic／status_application／runtime tests；原取值与应用前段分别标注，源技能不额外授予；文字高于光效层 |
| 水剎学习／原持有→实际十字范围施法 | 初始book／Learning、共同SkillResolution／StatusApplication、水抗索引1、`SkillEffectScriptPlayer`（effCode08）／Cutin／MagicImpact | water_strike tests及[真实输入](evidence_packets/runtime_observations/water_strike/README.md)；22完整数值返回＋44HP前段、空中心／多目标／巨体去重、一次费用／经验、当前AI与独立第二行动、F9；原图音与重制粒子／时钟分开 |
| 歐姆村双受控角色／村民、弓与毒魔箭 | `hsl_ohm_village_data`、`JobStatsRules`83、`PositionCapabilityRules`、`PoisonArrowRules`／`PoisonArrowPresentation`；现有PlayLoop／成长／Winfail／Checkpoint | [来源与范围](evidence_packets/static_reverse/original_ohm_village.md)、[实际流程](evidence_packets/runtime_observations/ohm_village/README.md)：18人源编队，061/062 friendly_ai无装备，原有符号弓范围／空手无普通目标，ST范围伤害＋独立毒、单次最终EXP；53→正式001→回图同一carry与生成游标 |
| 戈爾山道两阶段与脚本入队 | `ActorInitializationRules`共用初始模板校验、`ScriptActorCreationRules`纯事务、PlayLoop `_consume_script_actors`；`BattleScriptActorPresentation`与既有子协调器只读逐动作收据 | gol_road tests／[实玩](evidence_packets/runtime_observations/gol_road/README.md)；注册玩家不重复初始化，NPC出生流按安装顺序续接；整批成功后才入场／结局，原子失败不留下半队；新演员延迟至源安装token才显示；保存按配置／动作／出生／游标验证 |
| AI持有目标、等待、全图续追与空格施法 | `AINavigationRules`、`AISkillPlanning`／`AISupportPlanning`、`SkillTargetRules.candidate_centers`、`BattleNavigationCue` | ai_navigation及既有AI套件；中心与真实目标分开，路径和待机只读；场景／存档仍由PlayLoop提交 |
| AI友军目标、移动施援与相邻用药 | `AISupportRules`、`AISupportPlanning`、`AISkillPlanning.choose`；PlayLoop `_prepare_ai_turn/_execute_ai_support_item` | ai_support tests；扫描／续查与合法位置分开，真实技能／库存和一次提交；Runtime移动完成后消费编号物品反馈 |
| 行动交接、地图死亡／经验和领取 | `BattlePlayLoop._settle_action/finish_exhausted_action/_commit_rewards`、`BattleAftermath`、`BattleSettlementController`、`BattleLootPanel` | battle_reward／combat_aftermath／action_handoff tests；遗言／淡出→EXP→金币→领取→成长／后继；所有发奖和库存提交归 PlayLoop |
| 单战保存与恢复 | `BattleCheckpoint`、`BattleSettlementController.save_battle/load_battle` | 版本／配置／校验和、原子写入；静止边界保存与开场读回；已结算交锋不重放，UI旧回调失效；存档槽按场景 id 分开 |
| story-only 关卡（level 58 尾声、level 60 第二幕、level 53 开场预览回归场景） | `BattleSceneRuntime.is_story_scene`（`level_kind: story` 时不建 PlayLoop，`BattleSceneStage.spawn_actor_node` 供 cast 生成）、`BattleOpeningCoordinator` story mode（`story_actors` 生成、前向绝对／相对／跟随／删除走位、脚本物件、淡黑、叙述、`scene_end_marker` → `CampaignProgress.start_story_handoff` 或章末卡；开场预览的尚未重製卡读 `opening.skip_battle` 成两行选择——「略過戰鬥（視為勝利）」经 `CampaignProgress.start_skip_battle_handoff` 施加胜利段城镇／大地图写入后交接、「回到大地圖（不施加戰果）」为原路径；`actShapeMessage` 改写为带 `face_member` 的对白经 `BattleDialogue.show_face_message` 显示脚本自带人脸）、`content/battles/story_058.json`／`story_060.json`／`story_053.json`／营地与王座廳链 `story_055|056|061|062|063|064.json`（`tools/hsltools/levels/story_scene.py`；ActorRuntime `set_shape_override` 承接 actChangeShape） | story_scene tests＋[53 回执](evidence_packets/runtime_observations/story_scene_053_preview/README.md)／[58 回执](evidence_packets/runtime_observations/story_scene_058/README.md)／[60 回执](evidence_packets/runtime_observations/story_scene_060/README.md)／[营地链回执](evidence_packets/runtime_observations/story_scene_camp_chain/README.md)；无战斗状态、carry 原样透传；节奏与跟随规则为重制值；skip_battle 只施加胜利段的世界写入 |
| 战役承接（胜利→下一战／续战／章末） | `CampaignProgress`（`start_next_battle`：胜利战斗结束淡出后由 `BattleSceneRuntime.leave_finished_battle` 调用，无结果页；`pending` 一次性 hand-off、`user://campaign_progress.json` 持久位置与首关启动的续战提示；下一关未重制时结束本章并 `restart_campaign`；`party: separate` 关卡不施加 carry 而原样传递）、`CampaignCarryRules`、PlayLoop `apply_campaign_carry`、`content/battles/campaign.json` | campaign／third_battle_runtime tests＋[承接回执](evidence_packets/runtime_observations/campaign_handoff/README.md)；只承接受控单位的等级／属性／装备／库存与金币，经共享成长刷新后进入新 loop；`next_level_event` 来自 winfail 脚本 |
| 非 Leonard 受控战斗（level 53 緹娜逃出克萊恩城） | `content/battles/battle_053.json`（`python3 tools/hsl.py generate level_battle:53`，`obj_Story_Player2` 安装注册槽位 1 → 受控 `tina` = PLAYERS 002 祭司模板 `actors/002.json`；预览 `story_053.json` 画的是 029）、`BattleScenarioRuleAdapter` `winfail` → `WinfailScenarioRules`（从 seed 的 WINFAIL053 解释逃出胜利／受控者阵亡／回合与数量事件增援／Win Board 资源标签；手写 `ThirdBattleScenarioRules` 已退役）、`BattleOpeningCoordinator` 战斗模式的仅演出 cast（`story_actors`）与玩家槽位 `story_objects.spawns_unit_id` 显隔、`BattlePresentation._objective_board_text/_result_board_text` | winfail_rules／third_battle_scenario_load／third_battle_runtime tests；PlayLoop 对受控单位 id 无假设，Runtime 以 `player_unit_id` 定镜头与菜单；002／023 固定模板与走位节奏为重制值 |
| winfail 脚本演出（事件／胜负结果链的对白、延时、走位离场、镜头、音效） | `hsltools.levels.scenario.status_timelines`（各装配器共用）编译 `scenario_rules.status_timelines`、`WinfailScenarioRules.commit_outcome`（PlayLoop `_resolve_outcome` 调用）、`BattleSceneRuntime._maybe_start_script_cutscene`／`_on_script_cutscene_finished`、`BattleOpeningCoordinator.start_cutscene`、`BattlePresentation.mark_story_message_shown` | third_battle_runtime（53 win_0 与注入的 消息→延时→walk-and-delete→消息 链）＋整链 review（52 win_0 378）；解释器负责规则，协调器只演出；离场单位的队列消费待 P-025 |
| 標題畫面（主场景；開始新故事／戰場記錄／離開遊戲） | `game/title/TitleScreen.gd`（读 `content/imported/hsl/global/title/manifest.json`：Title shape 贴图、参考帧布局、三项菜单；宝珠／书固定在第一项旁竖直浮动（原版实录）、悬停亮起、黑场淡出后 `change_scene_to_file(BattleSceneRuntime.tscn)`；`CampaignProgress.reset_campaign／queue_resume` 决定新战役或接续） | `run_title_screen_tests.gd`；资源与布局由 `tools/hsltools/assets/title_assets.py` 生成、`--check` 入门禁，布局测量复跑 `tools/hsl_title_layout_probe.py`；不在标题里另建第二份战役状态 |
| 战斗内系统卷轴（任務說明／儲存戰場記錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單） | `game/battle/scene/BattleSystemMenu.gd`（读 title manifest 的 `system_items`／`confirm_items`：Title041 卷轴自底边卷入 (190,67)，Title042–047 亮起项，Title061–063 確定／取消）；`BattleSceneInput.handle_input` 在 `action_menu` 且无可取消交互时 Esc → `system_menu.open()`，卷轴激活期间输入全部路由给它；动作经 `settlement_controller.save_battle／load_battle`、`CampaignProgress.load_progress／resume_saved_progress`、`change_scene_to_file(TitleScreen)` | `run_system_menu_tests.gd`；不碰 PlayLoop，设定選項 未重制只提示 |
| 战间卷轴（大地图 Esc：儲存／讀取回憶錄 八槽、回主選單） | 同 `BattleSystemMenu`（`variant=world`，读 manifest `world_items`／`memoir_list`）；`WorldMapRuntime.handle_input` Esc／右键 → `runtime.world_system_menu.open()`；`CampaignProgress.save_memoir／load_memoir／memoir_entries／current_progress_record`（`user://memoir_NN.json`） | `run_system_menu_tests.gd` 世界段；整理裝備 → `arrange_equipment_requested` → `BattleSceneMenus._open_party_equipment` → `game/world/PartyEquipmentScreen`（窗体＝`TownShopScreen` 的 `MODE_ARRANGE`，原版共用状态窗模式 0；`game/sim/PartyEquipmentRules.gd` 沙盒 loop 换装、`project` 回写 carry）；讀取戰場記錄 → `CampaignProgress.battle_record_entries／queue_battle_record` → `BattleSettlementController.tick` 首帧 `load_battle()` |
| 設定選項（場景效果／預備動作／音效音量／音樂音量） | `game/settings/GameSettings.gd`（`user://settings.json`，Master＝音效、Music 总线补偿＝音乐、`scene_effects_enabled`、`ready_action_enabled`）；`BattleSystemMenu` options 阶段（Title039＋宝珠旋钮，读 manifest `options_rows`／`options_groove`，第二行 `ready_action` 开关）；`StoryEffectObjects.insert` 读 `scene_effects_enabled`；`BattleCombatCutin.cast_lead` 读 `ready_action_enabled`（关＝`AnimalCastLead.skipped`）；音乐播放器 `bus = GameSettings.music_bus()` | `run_system_menu_tests.gd` 設定選項 段 |
| 战斗结束 → 离场（胜：下一段；败：GAME OVER → 标题） | `BattlePresentation.battle_finished`（终态旗标，无可见结果页）、`BattleSceneRuntime._advance_battle_end`／`leave_finished_battle`（约 0.2 s 黑场后：败北 `change_scene_to_file(GameOverScreen.tscn)`，胜利 `CampaignProgress.start_next_battle`；原版 0x42cc10／0x42cbd0，见 [战斗结束流程](evidence_packets/static_reverse/original_battle_end_flow.md)）、`game/title/GameOverScreen.gd`（Title011／012，淡入后任意键或 160 tick 淡出回 `TitleScreen`） | `run_title_screen_tests.gd`（GAME OVER 阶段与败北离场）；不清存档，不改 PlayLoop 结局 |
| 通关 → GameClear 谢幕 → 标题 | `campaign.json` `"998"`（`kind: game_clear` → `game/title/GameClearScreen.tscn`）、`BattleOpeningCoordinator._finish_story`（`next_destination` 为 game_clear 时记录、清战役位置、`change_scene_to_file`）、`game/title/GameClearScreen.gd`（OverBG01／02、Over001／002、workteam 三阶段与黑场，任意键跳段／回标题，原创曲《破滅之後》） | title_screen tests（三阶段、跳段、回标题）＋story_scene 扫描（82 → GameClear）；形状与顺序 resource-derived（obj-998.obs），版式／时长／配乐为重制读法，逐槽队员展示未重制 |
| 大地圖（世界地图）场景与点位旅行 | `content/world/world_map_scene.json`（`level_kind: world_map`；`BattleSceneRuntime._is_world_map` 时不建 PlayLoop、只在 `_ready/_apply_startup_mode/_process/_input` 四处委托）、`game/world/WorldMapRules.gd`（对 `content/imported/hsl/global/world_map/world_map.json` 与共享世界状态 `hsl_world_state.v1` 的只读查询：可达点、路线折线朝向、m_trk 贴图落点、展示阶段 `point_mode`／`track_mode`（0 不显示／1 揭示／2 稳定）与揭示 `reveal_tracks_at`／`finish_track_reveal`、完成度 `completion_percent`、点类型／Visit 位与到达判定 `arrival`：原 handler 分支——event 0 无动作、General 未访开 event／已访先 ratio 再 +0..2、Battle 已访 +0..2、Town 仅目的点入城）、`game/world/WorldMapRuntime.gd`（只绘制展示阶段 ≥1 的点／线，路线揭示为沿长轴展开的裁剪、端点即时出现，M_PNT001..003 按 Battle／General／Town 三帧，命中框 ±16，底部 STATUS_BAR 状态栏（按原版帧减法压暗底图，文字位置／颜色按原帧）显示完成度与 `CampaignProgress.play_seconds` 累计时间；队伍标记沿折线旅行、到达先按到达前旗标判分支再标 Visit 并揭示该点路线、有数据的城镇点开 `TownRuntime`、无数据城镇卡与未重制关卡卡、边缘卷动、离城后按世界状态重绘图层并执行脚本留下的 `pending_walk`（teSetBMWalkToPoint 送船）；到达时先按 `world_map_scene.json` 的 `provisional_unlocks`（脚本从不发出、剧情却依赖的城镇树改写，逐条标 provisional／basis／replacement_evidence；现仅 `amphibian_second_stage`：站到点 13 龍之息 后 兩棲族部落 集會場 以 150／151 取代 148／149）经 `WorldScriptActions.apply_actions` 施加一次，`state.provisional_unlocks_applied` 记账、`unlock_records` 回报）、`CampaignProgress.next_destination`（`next_level_event [level, event]` 按原脚本惯例：`event` 为下一关，`gameBigMapLevel`(49) 回大地图站在点 `level`，无 next 的主线 1–45 关默认回图站同号点）、`start_world_handoff/update_world_state(world, carry)`（世界状态随 hand-off 透传，进图时 `WorldScriptActions.place_party` 站到目的点，每次到达与每次城镇交易后连同 carry 落盘） | world_map／campaign tests＋[大地圖回执](evidence_packets/runtime_observations/world_map_scene/README.md)；数据结构与流转脚本惯例见[世界地图数据](evidence_packets/static_reverse/world_map_data.md)（`tools/hsltools/data/big_map_flow.py`）；三字段／隐藏点线／到达分支／三帧标记／命中框／状态栏内容按 SR-069 静态合同（[原合同](evidence_packets/static_reverse/original_world_town.md)）；状态栏画法与排版、网格线可见按原版帧（[原版大地图／城镇实录](evidence_packets/runtime_observations/original_world_town/README.md)）；旅行速度、揭示动画时长与触发、遭遇抽样方向、队伍贴图、配乐为重制值 |
| 菜单式城镇（TownBG＋菜单树＋对白板＋商店） | `game/world/TownRuntime.gd`（由 `WorldMapRuntime._open_town` 挂在 `UI` 下：根菜单＝`TownEventRules.menu_entries`、入城自动跑 `towns[id].exec_event`、离城先跑 `exit_exec_event`；逐条播放解释器 effects——player/shape message 走 `BattleDialogue`＋`town_portraits.json`、get_gold/get_item 走旁白、根画面构图按原版帧（不压暗大地图、TownBG (158,148)、WINDOW70 石纹菜单板 (60,60) 里白字行；teShapeMessage 上方对白板、tePlayerMessage 下方）、select／player_select／sub_menu 选项作为石纹板文字行、无点名／金钱条／离开按钮（右键／Esc 离城、退子菜单、取消选人）、teCreateShop 开 `game/world/TownShopScreen.gd`（原版状态窗式商店：WINDOW10 成员条、WINDOW20 背包、WINDOW90 货表、WINDOW40 金钱、上一位／下一位／裝備／買賣／倉庫／丟棄 按钮，悬停出 WINDOW50 说明；点货行买入所显示成员的首空格，拿起背包物放到货表卖出，拒绝消息在 BOARD02；右键／Esc 依次关消息、放回手上物、退店），根菜单右键／Esc 离城；每次 run 结束把 `run.state` 交回地图并把 party 差额写回 carry）、`game/world/WorldPartyRules.gd`（纯函数：carry↔城镇 party 视图、`buy` 首个空格＋扣标价、`sell` 按原 `0x414ab0` 的 price×50÷100、重要物品拒收——价格与两条拒绝消息 606／607 为 static-derived（[原作商店交易](evidence_packets/static_reverse/original_shop_transaction.md)），`apply_party` 差额入包并对无空格物品给 dropped 回执）、`game/sim/TownEventRules.gd`（te 解释器，纯字典） | town_scene tests＋[城镇回执](evidence_packets/runtime_observations/town_scene/README.md)；te 读法见[城镇事件读法表](evidence_packets/static_reverse/town_event_semantics.md)；根画面与商店构图、右键／Esc 退店离城 runtime-measured（[原版大地图／城镇实录](evidence_packets/runtime_observations/original_world_town/README.md)，对白上下分工 provisional）；重制多出功能的位置、买入直接入包、暗置的 裝備／倉庫／丟棄、每句等待确认、teDelay／tePlaySound 只记录、入包规则为重制读法；初始菜单树 provisional（P-027） |

上表首场模块位于 `game/battle/scene/`，公共镜头／坐标规则位于 `game/battle/runtime/`，纯战斗规则位于 `game/sim/`（PlayLoop 与 6 个 `BattleLoop*` 在 `game/sim/loop/`），全游戏共用的 tick 与界面皮肤（`OriginalTick`、`BattleUISkin`）位于 `game/common/`，测试位于 `tests/`。用函数／类名搜索定位，避免依赖会变化的行号。原版现象、当前行为、待实现差异必须分开记录。

## Runtime flow

```text
project.godot
  ↓
BattleSceneRuntime.tscn
  ↓
BattleSceneRuntime._bootstrap_runtime()
  ├── BattleScenario.load_file(scenario_path) + BattleScenarioRuleAdapter validation
  ├── load resource/evidence manifests from scenario paths
  ├── BattlePlayLoop.create(..., scenario)
  ├── apply campaign carry → initialize_roster_growth (battle only)
  ├── create MapSceneConfig / Camera2D
  ├── spawn map objects and ActorRuntime nodes
  └── configure SceneTimeline / UI
  ↓
product_opening → first_control_marker → queued NPC actions → player action menu
```

## Scene tree

```text
BattleSceneRuntime
├── BattleMusic
├── World
│   ├── MapBackdrop
│   ├── MapObjectsBack
│   ├── MoveOverlay（RangeCellOverlay：原版范围格填充＋I_rect 边框，逐 tick 脉动）
│   ├── Actors
│   └── MapObjectsForeground
├── Camera2D
├── UI
│   ├── ActionMenu
│   └── OpeningOverlay
└── BattlePresentation
```

`.tscn` 只定义稳定骨架；actor、map object、button 和 overlay cell 由代码构造。

### Runtime modules

`BattleSceneRuntime.gd` 是场景根与生命周期（`_ready`／`_process`／`_bootstrap_runtime`、AI 播放、脚本过场桥接、select／move／attack／cancel 交互操作）。它持有的 `play_loop` 只经 **`apply_loop(next, reason)`** 写入——写入、记 `loop_write_reason`、并在同一调用里做镜像步 `_sync_from_play_loop`（ActorRuntime 生成／格位／离场与击败可见性、`unit_grid_coords`、选中、待撤回移动、最后攻击；在动的 actor 不被拉回，所以走位 tween 先起再 apply）；规则操作后的交互态用 `mirror_interaction()` 跟随 loop 的 `interaction`，只有开场协调器写 loop 不知道的 `Interaction.OPENING_TIMELINE`。交互态与场景侧读到的 loop 键分别以 `game/sim/Interaction.gd`（含唯一格哨兵 `NO_CELL`）与 `game/sim/LoopKeys.gd` 拼写一次；PlayLoop／sim 内部仍写字面量（S6e）。四个战斗模态面板登记在 `modal_panels`（输入优先级 magic→growth→item→status），`modal_open(ignoring)` 是唯一"面板已打开"谓词，面板各自 `handle_input(event) -> bool` 处理右键／Esc 关闭。以下 `RefCounted` 模块各持一个 `runtime` 引用，不拥有状态，以公开成员 `scene_input`／`menus`／`stage`／`overlays` 从 runtime 寻址（`runtime.menus.set_action_menu_visible(...)`），runtime 上不再有转发壳；被跨文件调用的成员一律无下划线：

| 模块 | 职责 | 状态归属 |
| --- | --- | --- |
| `BattleSceneInput`（`scene_input`） | `handle_input` 分派链（模态面板接管→cutin／对白／已分胜负不收地图输入→开场→指针）、指针 hit-test（logical → grid／unit／command）、`disarm_pointer_scroll` | `pointer_*`／`hovered_*`／`held_command_id` 镜像仍在 runtime |
| `BattleSceneMenus`（`menus`） | `build_panels` 实例化面板与卷轴、接信号并登记 `modal_panels`；`choose_command`、道具／给予／换装／成长处理器、整理裝備 屏、action menu 的 rebuild／anchor／visible | 面板节点为 runtime 成员；命令集来自 `BattlePlayLoop.IMPLEMENTED_COMMANDS` |
| `BattleSceneStage`（`stage`） | ActorRuntime 生成与帧行重装、EVEF 站立物件／背景音生成 | `map_object_records`／`background_sound_records` 记在 runtime |
| `BattleSceneOverlays`（`overlays`） | 决定 Move／攻击／魔法／绝技覆盖层的格集合与调色板，交给 `World/MoveOverlay` 上的 `RangeCellOverlay` 绘制 | `move_overlay_cells`／`attack_overlay_cells` 镜像在 runtime |

只读的 `*_summary` 合同不在产品目录：[tests/support/RuntimeReadback.gd](../tests/support/RuntimeReadback.gd) 以静态函数读一个已启动的 runtime（`RuntimeReadback.interaction_summary(scene)`），交互操作本身不返回摘要。

## State ownership

| State | Owner | Rule |
| --- | --- | --- |
| 单位坐标、HP/MP/ST、状态、库存/装备、击败、成长与派生数值、金币／领取记录、行动标记、队列、结果 | `BattlePlayLoop`（合同门面；`BattleLoopInit`／`Rewards`／`Script`／`AI`／`Combat`／`Inventory` 是对同一 loop 字典操作的静态模块，[模块表](architecture/BATTLE_SYSTEMS.md#battleplayloopgd)） | 唯一可变 combat truth |
| actor position/frame/visible | `ActorRuntime` | 从 PlayLoop 同步的表现 |
| `play_loop` 的写入 | `BattleSceneRuntime.apply_loop(next, reason)` | 场景内外（模块、协调器、结算、tests/support）唯一写入口；写入即镜像 |
| `unit_grid_coords` | `BattleSceneRuntime` | 锚点表现镜像，由 apply_loop 的镜像步维护，不可独立 mutation；命中查询交回PlayLoop footprint |
| `interaction_state` | `BattleSceneRuntime` | loop `interaction` 的镜像（`mirror_interaction`）＋ 开场专有 `Interaction.OPENING_TIMELINE`；取值只用 `game/sim/Interaction.gd` |
| 模态面板可见性 | 各面板节点 | `modal_panels`／`modal_open()` 是唯一"已打开"谓词；面板自己处理关闭输入 |
| opening event cursor | `SceneTimeline` | 纯队列游标 |
| input dispatch / pointer hit-test | `BattleSceneInput` | 只写 runtime 的指针镜像，规则调用走 runtime 的交互操作 |
| menu/dialogue/panels/combat playback | 对应 `Battle*` view | 仅显示游标、播放状态和未提交草稿 |
| camera transform / clamp / pan | `BattleCameraController` | 共享场景能力，只读 `MapSceneConfig` |
| scenario common parsing / resource paths | `BattleScenario` | 跨 battle 共享规范化边界 |
| 全局共享表的路径（技能书／targeting／growth_lifecycle／AI profiles／entry_growth／rewards／装备目录／名册肖像表／地图物件与战斗 UI 预览目录／界面音效／切入与特效 manifest） | `game/sim/ContentPaths.gd` | scenario 不能覆盖的引擎级表只在此登记，导入素材都在 `content/imported/hsl/shared/`；逐关素材（`chapter01/battleNNN/`）只经 scenario `resources` 取，引擎不拼章节目录（`hsl check engine:chapter_paths`）；`resources.portraits` 是本场对白 speaker 子集，由 Runtime 配给两块对白板（无默认表，缺则 push_error 且不画脸）；面板选中任意单位的脸走 `ContentPaths.actor_portraits()` |
| unit 字典形状（scenario `playable_units`／`script_actor_templates[*].actor`／actor 模板／carry 合并后的名册） | `content/schema/unit.schema.json`（`tools/hsltools/schema/unit.py` 从全部 tracked 单位推导，任务 `unit_schema`） | 唯一合同，两侧校验：Python `LevelBattleTask.render` 渲染后校验（违规 `CheckFailed`）；GDScript `game/sim/UnitSchema.gd` 在 `BattlePlayLoop.create`（scenario 名册归一化后、初始化前）、脚本模板归一化后、`apply_campaign_carry` 合并后校验，违规 `scenario_error=unit_schema:units[<id>].<path>: <reason>` 明确失败；调用方自带的 `units` 数组视为内存态不校验 |
| battle JSON 合同（哪些键必需、哪些键有默认值） | `content/schema/battle.schema.json`（手写，`hsl_battle.v1`；任务 `battle_schema` 校验全部 tracked 战斗） | `BattleScenario.load_file` 对 `rule_adapter` 属战斗适配器的文档校验并填 `default`，标 `contract`；`BattlePlayLoop.create` 对未经 load_file 的内存字典补同一校验，违规 `scenario_error=battle_schema:$.<path>: <reason>`；写法与最小示例见 [逐步表「手写一场战斗」](MODDING_LEVELS.md#7-手写一场战斗battle-json-的合同) |
| 第一战（level 51）配置 | `content/battles/battle_051.json`（`level_battle:51` 由 seed／`story_051.json` 组装，`rule_adapter: winfail`） | 与其余正式战斗同一路径；`content/battles/first_battle.json` 只是已审核的 001／021／023／024／026 模板名册（Python 生成器输入）与纯 loop 机制测试的 `development_battle` 夹具（`tests/support/BattleFixture.gd`），不再是可进入的战斗 |
| 跨关 hand-off（下一场景路径＋carry） | `CampaignProgress.pending`（静态，进程内一次性）＋ `user://campaign_progress.json`（最后一次 hand-off 的落盘副本） | Runtime `_bootstrap_runtime` 消费一次；落盘副本只在新进程进入首关时经玩家确认转成 `pending`；不是第二份战斗状态 |
| 世界状态（当前大地图点、点／路线旗标覆盖、点事件、城镇菜单树、结局输入 `over_score`／`over_flag`） | hand-off 的 `world` 字典（`hsl_world_state.v1`），由 `WorldMapRuntime` 在到达时改写并经 `CampaignProgress.update_world_state` 落盘；战斗与 story 场景原样透传；`over_score`／`over_flag` 由 `actAddOverScore`／`actSetOverFlag`（战斗 winfail、剧情记录、`skip_battle`）与城镇 `teAddOverScore` 写入，`EndingDispatchRules.route` 在 57 的结束卡上按原分派读出结局（[原结局分派](evidence_packets/static_reverse/original_ending_dispatch.md)） | 不是第二份战斗状态；查询走 `WorldMapRules`，te／act 改写走 `TownEventRules`，UI 消费走 `TownRuntime`；脚本记录的 act 城镇／大地图动作——战斗的 `winfail_runtime.pending_world_flags` 在 `CampaignProgress.prepare_handoff`、故事场景的 `story_records`（town_*／bigmap_* kind）在 `start_story_handoff`／大地圖出口——经 `game/world/WorldScriptActions.gd` 施加到 hand-off 的 `world`（尚无世界状态时先按大地圖场景起点与 12 城初始树种一份）；城镇交易改写的是 hand-off 的 `carry`（金币与各成员 8 格背包），经 `WorldPartyRules` 写回 |

Mutation 顺序固定：

```text
input → PlayLoop operation → sync scene/actors → present
```

禁止直接移动 actor node 后再倒推 sim state。

## Module map

| 边界 | 代码 | 详细合同 |
| --- | --- | --- |
| 转职（战斗内 `actPlayerJobUpProcess`、城镇 `teCheckJobUp`／`teCheckJobUp2`） | `JobUpRules`（`apply` 战斗内模板交换；`merge_source_template`／`replay_history` 城镇合并与下一战重放）、`TownEventRules._step_check_job_up`、`WorldPartyRules.member_records`→carry 写回、`CampaignCarryRules.apply` 重放 `job_up_history`、`LearningRules.source_jobs` | [37 关 token 读法](evidence_packets/static_reverse/original_level37_tokens.md)、[原城镇转职](evidence_packets/static_reverse/original_town_job_up.md)；carry 只存 flags／目标行／历史，数值由共享成长刷新派生，不建第二套刷新 |
| 场景配置与跨关策略 | BattleScenario、BattleScenarioRuleAdapter、CampaignProgress／CampaignCarryRules | [场景／队列／战斗](architecture/BATTLE_SYSTEMS.md#scenario-queue-and-combat)；[承接回执](evidence_packets/runtime_observations/campaign_handoff/README.md) |
| 一关的逐关知识（战斗档案、场景 spec、演员清单、说话人表、sweep 夹具） | `content/battles/levels/NNN.json`；读取器 `tools/hsltools/levels/profile.py`；消费者 `hsltools/levels/{battle,story_scene,actors,message_text}.py`、`tests/support/BattleForceWin.gd` | [关卡档案](architecture/LEVEL_PROFILES.md) |
| 为重制版写的一关／一名角色（无原作记录） | `content/authored/levelNNN/`（原脚本文法 STORY／winfail、对白、ASCII 地形、单位表）经 `tools/hsltools/levels/authored.py`（任务 `authored_level:N`）组成同形的 seed／timeline／`battle_NNN.json`；角色行 `content/authored/roles/characters.json` 经 `tools/hsltools/sources/tables.py character_rows()` 接在 PLAYERS.TXT 之后进入六张全局表与名册脸表 `content/generated/hsl/roles/actor_portraits.json` | [加关卡与角色逐步表](MODDING_LEVELS.md) |
| loop 复制、只读配置键、冻结断言、存档半边 | BattleLoopConfig（`CONFIG_SHARED`／`copy`／`same_state`）、PlayLoop `copy`、TestSuite `own`／`assert_config_frozen`、BattleCheckpoint v3 | [配置／状态分离](architecture/BATTLE_CONFIG_STATE.md) |
| 坐标与纯移动／战斗／队列 | TacticalGridRules、CoreCombatRules、CoreTurnQueue | [战斗合同](architecture/BATTLE_SYSTEMS.md#scenario-queue-and-combat)；下方 Coordinates |
| 行动与一次性交接 | ActionBudgetRules；PlayLoop _settle_action、_advance_current_actor | [行动完成](architecture/BATTLE_SYSTEMS.md#action-completion) |
| 背包、给予、装备与成长 | InventoryRules、EquipmentRules、EquipmentCatalog、ProgressionRules | [库存装备](architecture/BATTLE_SYSTEMS.md#inventory-and-equipment)、[成长](architecture/BATTLE_SYSTEMS.md#growth) |
| 战斗道具、禁魔解除／气力／临时增益 | `ItemUseRules`预检、`ItemResolutionRules`不可变收据、PlayLoop唯一提交、`BattleItemText` | tactical_items tests；抽样走共用伤害随机流damage_rng、真实槽位一次扣除、增益仅首次抽样、阶段／AI自救友援／保存与终态共用 |
| 技能费用、目标、效果与状态 | SkillResourceRules、SkillTargetRules、SkillResolutionRules、SupportMagicRules、StatusEffectRules、StatusApplicationRules | [技能](architecture/BATTLE_SYSTEMS.md#skills)、[状态](architecture/BATTLE_SYSTEMS.md#status-lifecycle) |
| 普通交锋气力与装备修饰 | StaminaRules；PlayLoop _apply_strike、change_equipment | [气力](architecture/BATTLE_SYSTEMS.md#stamina) |
| AI 目标、呼叫、自救、机会与友军支援 | AIDecisionRules、AICallRules、AIPriorityRules、AISkillDecisionRules、AISkillPlanning、AISelfPreservation、AISupportRules／Planning；PlayLoop _prepare_ai_turn | [AI](architecture/BATTLE_SYSTEMS.md#ai) |
| 开场、菜单、面板、移动与交锋收尾 | Runtime、各 Battle* view、ActorRuntime | [表现合同](architecture/PRESENTATION.md) |

只读取本次修改命中的详细章节。先搜索定义及调用者，再改对应模块；不能因符号名字像目标规则就当作已经接入。

## Staged modules

ActorRoleRules 的完整角色控制、ProgressionRules 的转职资格有 focused tests，但尚未 live。第二战使用同一场景／PlayLoop：`product_opening` 由 `BattleOpeningCoordinator` 播放编译的 STORY052 timeline（见 [STORY052 开场脚本](evidence_packets/static_reverse/second_battle_opening_script.md)与[开场回执](evidence_packets/runtime_observations/second_battle_opening/README.md)），随后进入共享 NPC 前置行动与 Leonard 菜单；dev first-control seam 仍可绕过开场。winfail052 的 event0 对白、event1 插入走入、CLIP001 音效已接入；胜利 `[58,58]` 经 `CampaignProgress` 进入 story-only 的 `story_058.json`，由同一 coordinator 的 story mode 播放 STORY058 至章末卡（level 60 尚无场景）。第一战（`battle_051.json`）同样由 coordinator 播放编译的 STORY051 timeline，回合 4／6 的事件（等待台词、信使 10000 进出城门、026／021 离场、胜利条件武装）与胜负结果链由 `WinfailScenarioRules` 解释、coordinator 作为 script cutscene 演出；手写的 `FirstBattleScenarioRules`／`FirstBattleStoryStage`／Runtime `opening_*` 已删除。第一战的手动存档、奖励领取不等于已有跨关承接。

这些与“已 live 的 Leonard 成长、背包／换装、技能及 AI”分开；具体后续顺序仍由 [PROJECT](PROJECT.md#next-steps) 维护。

## Coordinates

当前唯一输入链：

```text
viewport position
→ logical 640×480
→ Camera2D world position
→ MapSceneConfig.world_to_grid
→ unit/grid/menu hit
```

当前限制：

- actor hit 仍基于 grid occupancy，不是精确 sprite/Area2D shape。
- command hit 基于 Godot Control rect；live 菜单只创建已实现命令的按钮。
- projection `origin=(0,0)`, `cell=(32,32)` 来自原版 player/enemy 初始化；ActorRuntime 放在格中心。EVEF 初始编队由 `tools/hsltools/data/first_battle_formation.py` 生成并校验；NPC 开场后由正常 AI 前置行动移动，原版精确路径尚未恢复。
- edge scroll 的原触发阈值已接入，实际速度仍用明确的重制值；完整 z-order／foot anchor 和原版 release timing 仍有未核齐的边界。

## Data and evidence layers

```text
content/battles/        live scenario config
content/schema/         shared JSON data contracts (unit.schema.json; both sides validate)
content/imported/       reusable original-derived inputs
content/generated/      compact reproducible derived facts
docs/evidence_packets/  curated evidence required for decisions
game/                   product code
tests/                  current automated contracts
tools/                  generators/checkers/capture tools
```

仓库外/ignored 的 raw copy、capture、decompilation 和 cache 不能成为产品代码默认依赖。

## Provenance headers

每个 `game/**/*.gd` 模块的文件头（`extends`／`class_name`／首段 `##` 说明之后、第一个 `signal`／`var`／`enum`／`func` 之前，preload 常量可在前）带一个来源块，由 `python3 tools/hsl.py check provenance` 强制、`generate provenance` 汇总成 [PROVENANCE](PROVENANCE.md)：

```gdscript
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#16
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   strings: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   timing: remake-invented
##     (面板淡入时长为重制自选；备注写不下一行时接在 `##     ` 续行上，读取时以一个空格拼回)
```

- 维度五个、按此顺序：`rules`（规则语义）、`layout`（位置尺寸／窗体资源）、`strings`（文字）、`timing`（时序／动效）、`audio`；模块不涉及的维度省略（即 n/a），至少有一行来源。
- 一行一个来源 `##   <维度>: <标签> [<仓库相对路径>[#锚点]] [(<备注>)]`，同一维度有几个来源就写几行（相邻）；每行不超过 120 字符，长备注折到 `##     ` 续行；同一标签可对不同路径重复，同一路径不重复。旧写法（`n/a` 行、一行内 `;` 分隔多项）检查器仍能读，只为旧夹具保留，`game/` 不再用。标签 = [AGENTS「Evidence language」](../AGENTS.md#evidence-language)的七个层级 ＋ `runtime-reference`（按原版参考帧目测复刻，无量测）＋ `remake-invented`（重制自己决定，原版无对应证据；用户允许改善但必须可见）。
- `resource-derived`／`static-derived`／`runtime-measured`／`runtime-reference` 必须带路径且文件存在（来源可定位）；其余标签路径可选。`#锚点` 是自由文本（章节或行号），不校验。
- 备注写疑点或决定：生成页会把每个 `provisional` 与 `remake-invented` 的备注列成清单。
- 头只登记来源，不改行为；新增模块没有该块，门禁 FAIL。改了头之后 `python3 tools/hsl.py generate provenance` 更新生成块。

## Extension rules

- 新 battle field 先进入 scenario schema，再由 loader 规范化。新 unit 键先改生成器，再 `python3 tools/hsl.py generate unit_schema`（推导 `content/schema/unit.schema.json`）与 `generate level_battle`，GDScript 侧自动读同一文件；运行时新增的 unit 键登记到 `hsltools/schema/unit.py` `RUNTIME_PROPERTIES`（可选键），否则 carry 合并后的名册会被 `UnitSchema` 拒绝。
- 规则文件不内嵌成段散文（claim limits、读法）：原文进证据包，代码只留短 id（`WinfailCompiler.CLAIM_LIMIT_IDS` → [winfail_claim_limits](evidence_packets/static_reverse/winfail_claim_limits.md)；`TownEventRules.PACKET_READING_TOKENS` → [town_event_semantics](evidence_packets/static_reverse/town_event_semantics.md)；运行时摘要的 `claim_limit` → [remake_notes](evidence_packets/runtime_observations/remake_notes.md)）。
- 新 rule 优先放纯模块，并由 PlayLoop 调用；不要放进 scene。
- 新 visual state 不得复制 sim truth。
- 新 evidence 先进入 machine-readable packet/checker，再改实现。
- 修改 Camera/projection/Move/hit-test/z-order 前先过 curated visual index。
- `BattleSceneRuntime.gd` 新增长逻辑前，优先放进对应模块（见 [Runtime modules](#runtime-modules)）或抽独立 coordinator；camera contract 已迁入 `BattleCameraController`，非第一战开场已由 `BattleOpeningCoordinator` 承担（其选择提示／结束卡／剧情对象／标题镜头影片四个模块在 `game/battle/runtime/opening/`，见[表现合同](architecture/PRESENTATION.md)），input／menus／stage／overlays 已按缝抽出且无转发壳，readback 住在 tests/support；第一战 opening 已迁入同一 coordinator。

## Tests

按 [tests/README.md](../tests/README.md) 选择定向套件及实际命令。tools/godot.sh 与完整门禁共享日志诊断；退出 0 但存在脚本／资源错误或泄漏仍然失败。可见改动的截图／录屏要求见 [表现验收](architecture/PRESENTATION.md#validation)。

完整非 GUI 门禁只有 tools/verify.sh（快门默认热缓存；`--full` 在导入前清理生成缓存证明冷克隆可导入；`--deep` 在快门之后再跑长端到端套件 `verify_runner.py deep`；各档退出都保留缓存）；复用通过结果前先确认 diff、资源和验证环境未变。
