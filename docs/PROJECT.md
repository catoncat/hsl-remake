# HSL Remake — Current Project State

Checked: 2026-09-25

## Goal

在 Godot 4.x 中重制《幻世录》。终点有两个，按顺序：**① 第一章 127 场战斗能像原版一样从标题玩到章末**（规则一致、节奏一致、画面手感经用户实玩认可）；**② 这套引擎能让用户写续集**——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑（[第四轮](SEQUEL_READINESS.md)）。项目最初的垂直切片（第一战）早已完成并扩展到整章。所有“像原版”的声明必须能追溯到资源、静态分析或本机原作 runtime evidence。

**进度尺（机器可算，不靠感觉）**：字段未消费数见 `hsl check field_coverage`（2026-09-22：22／742）；表现来源中 `remake-invented` 与机制矩阵中的 `provisional` 以各自现行报表为准，不把旧计数当最新状态。2026-09-26 最新 128 场自动对局（ALLYHEAL 合并树 `results.json`）：`win=20 / fail=108 / dead_end=0`（友军与新装入角色照原版带模板背包后 509／517 由输变赢）——伤害流换原版算法、敌方按原版集火而贪心驾驭器不躲，属原版难度非回归（09-25 深门 27／101 是旧数；RNGC 掉落／携带改抽全局流后 3 场翻转）；整章播种走查 `stuck_at=53`（CHAPTER53 判定为伤害串运气，非规则回归），`game_clear=false`，剧情 explorer 57 场景／22 段剧情／三个结局可到 GameClear；**剧情可通不等于战斗可通，也不等于原版难度**。第 5／6 关仍是机器人打法与交接队伍的待办，原作配置与人工难度判断分别见 [第 5 关对照](evidence_packets/runtime_observations/battle_005/README.md)和 [人工验收](PLAYTEST.md)。

2026-09-05 用户确认：不要求逐帧、逐像素 1:1；在保留剧情、关卡设计和角色特色的前提下，可以直接采用更好的交互、动画、界面和节奏。优先完整、顺手的第一章体验；未知原版细节不再默认阻塞实现。资源和规则来源仍需如实标注。

初始完整阵容及后续增援已按各自有界原函数路径调级；登记玩家、一般NPC、出生偏移与最终EXP分配保持独立，替代早期固定一级NPC基线。原全局对象调度／RNG仍不等价，见[成长生命周期](evidence_packets/static_reverse/original_growth_lifecycle.md)。

本轮逐项验收与尚未完成的边界见 [`FIRST_BATTLE_ACCEPTANCE.md`](FIRST_BATTLE_ACCEPTANCE.md)。

## Current status

### 当前交付与后续入口

当前产品路径已注册整章 127 场战斗、剧情／城镇／世界地图交接与三个结局；机器剧情 explorer 可到章末，但机器人自然打关仍卡第 5 关，不能称第一章已经自然通关或原版等价。第一战的胜负／奖励／读档可玩，细项证据见 [奖励合同](evidence_packets/static_reverse/battle_reward_inputs.md)及[奖励验收](evidence_packets/runtime_observations/battle_rewards/README.md)。已验证的提交和未合并工作分别以 Git 与 [协作入口](../PARALLEL_WORK.md) 为准。

2026-09-14 资料审查 `08eca50` 已接收 [原录像参考](evidence_packets/runtime_observations/original_gameplay_reference/README.md)：637 张外部导出帧全部匹配源视频，保留 52 张原帧及 18 类导航；错误解释已更正，原始材料可恢复归档。随后已接入魔擊力百分号、共用源底板的开场／战中对白与完整分页，以及同坐标选格、技能名和目标信息避让；[图证与复跑入口](evidence_packets/runtime_observations/dialogue_selection/README.md)明确了重制取舍与尚未确认的信息公开条件。

已接入系统按下表查当前能力。详细事务、原地址和验证回执按 [机制矩阵](MECHANICS_EVIDENCE_MATRIX.md) → 对应 evidence packet 阅读；不把历史批次的“尚未接入”当当前结论。

| 系统 | 当前玩家能使用的部分 | 仍需接续的部分 |
| --- | --- | --- |
| 戈爾山道与事件入队 | 正式level2从原七人开场开始；击败强盗触发緹娜002与四名023追兵，旧强盗离场后继续第二阶段。真实胜利可进入55／56营地并带三人回到大地图；F9不重建队员／回抽出生，演出前不提前揭示角色 | 条件成员全队管理、复活／离队再入队、全VM调度与原全局随机流未由本片恢复，见[安装证据](evidence_packets/static_reverse/original_player_install.md)及[实玩](evidence_packets/runtime_observations/gol_road/README.md)；正式1／2宝箱由下行独立切片补齐 |
| 原宝箱与未领物品 | 正式歐姆村／戈爾山道三箱按原实例内容开启；完成行动才发现，移动取消不领取；满包交换、重复药品、取消／放弃／稍后、F9及第二行动一致。普通队伍真实胜利可“保留物品並繼續”，经过营地／世界到下一场仍可领 | [原函数与边界](evidence_packets/static_reverse/original_treasure.md)、[八条实际输入](evidence_packets/runtime_observations/treasure/README.md)分开自然取箱与终局夹具；隐藏／其他关卡宝物、AI主动搜箱、原全局永久开箱位未实现，新场与重开按实例重置 |
| 第一战主流程 | 开场、移动／攻击／技能／用药、剧情、胜负与重开 | 原作完整规则和更多自主打法的验收 |
| 菜单与地图浏览 | 源布局和动画 helper 已接入；鼠标靠边滚动，失焦／离窗停止 | 精确原版时钟、最终滚动消费与其余输入变体 |
| 普通攻击／施法表现 | 六类正式角色及开发002／039的原普通action，祭司完整六帧起跳／落地；主攻击／反击系列及逐击暴击、实际扣血和HP/ST快照；原氣刃斬、风火短HP/MP条；全部打击后遗言／淡出、KILL、最终EXP／金币和领取 | 全部ANIMAL opcode、原暴击事件完整表现、完整死亡handler、精确混色／时钟 |
| 初始化与成长 | 七职业共同派生；初始登记玩家推级、NPC与脚本新援一次出生调整，交锋最终EXP使NPC自动分配、玩家保留手动五点；按原职业／等级学魔法，确认基础属性后学绝技。初始声明、learned_skills、出生／永久／装备／临时层分开；F9及跨战保存取得记录和生成流，独立队伍不串人物／金币。**转职**：战斗内 `actPlayerJobUpProcess`（37 咕嚕→**017 邪獸**：咕嚕 按 EVEF 有才產生 随 carry 在 37 上场，攻击 052 守护者后按原函数链 `0x4348f0`→对象描述表 `obj_Data7`→PLAYERS 行（816 → 017，static-derived，见[37 关 token 读法](evidence_packets/static_reverse/original_level37_tokens.md)）转为 017 形态：SHAPE\017 走行帧、P017 切入＋三面板、FLY002 脚步、当前 HP/MP 保留并夹到新上限（`0x407ec0`／`0x448840` 不回满），与城镇转职同一 `merge_source_template`／carry 合同，之后每一关、过场与大地图都以 017 形态出现；052 是被打的 謎之生命體 守护者）与 命運神殿「升級」（`teCheckJobUp`／`teCheckJobUp2`：四属性各 ≥ 当前职业上限−50 即成功，001–009→010–018，雷歐納德／緹娜 再→019／020；转职成员保留等级／经验／属性／装备／库存／已学技能，职业／稱號／来源加性层换成上位模板并经共享刷新，下一场按 carry 的 `job_up_history` 重放；上位职业 81／82／84／86／87／89／97 公式经原生探针复核；转职后按成员当前职业的原学习表继续学技——81／82／84／86／87／89／91／97／99 的魔法门槛与绝技阶级 static-derived 自 `0x4373f0`／`0x437a40` 分派及 714 组原生返回，转职前记录保留原职业） | 上位形态走行帧已导入共享目录（010–017／019／020 与 052，`ActorSpriteKey` 按 `job_up_target_actor_id` 优先取帧，本关 manifest → 共享 manifest → 基础行）、020 肖像 FACE0020 已入共享肖像表；攻击切入也按上位行（010–017／019／020 与 052 的 P0xx 切入帧／flash／dispatch 已自 ANIMAL SID_PLAYER9–19 块导入全关共用的 combat manifest，`BattleCombatCutin.art_key` 同 `frame_key` 法；氣刃斬／毒魔箭／月花 的施放面板仍取基础行——上位行 s_shape 三面板条已导入但构图不同、无消费者）；仍 provisional：37 战斗内转职后站满 HP/MP、已城镇转职到 017 的 咕嚕 在 37 无声明目标（明确拒绝、不叠 052）、018 魍魎劍士 无 SHAPEDEF 绑定（原表注释掉，克羅蒂 第一次转职后保留 009 形态与 009 切入；P018 切入帧存在但未导入）、上位行脚步声沿用基础演员（052 的 FLY002 未导入）、上位行与第六波 32 名演员的 `sprite_facing` 待人工审核（`tools/hsl_sprite_facing_audit.py` → `ignored/g/`）、剧情过场／大地图标记仍按基础行绘制、兩棲族部落 第二次转职后的菜单原生观察、其余职业、未实现技能效果、原对象调度顺序／全局RNG与原作跨关handler；原函数与重制调度边界见[成长生命周期](evidence_packets/static_reverse/original_growth_lifecycle.md)、[原城镇转职](evidence_packets/static_reverse/original_town_job_up.md) |
| 物品与装备 | 八槽库存、给予／交换与重要物保护；七职业当前装备共同刷新；HP／MP药、解除异常、气力酒、临时攻防道具与九类永久能力来源；追加一击／连续行动／移动／元素／气力／EXP、减耗／恢复／血转MP、移动施法／范围、防护、末击附毒／取消未来行动；宿魔刀按实际末击HP损失的三分之一削减目标MP | 生命／魔力永久物、自动整理、完整目标资格、其余职业、弱化／随机状态等未支持被动；削魔不恢复使用者MP |
| 金币与战利品 | 敌方携带／掉落、可控角色击杀及反击奖励、满包交换、取消／放弃、延期跨交锋和状态页重开；F5/F9保存领取、最终经验、连续数和成长 | 原取物handler和跨关经济；当前资格为明示重制选择；携带与掉落已抽原版全局流（0x407c86／0x44f5d3，不入存档，读档后重掷），全局流本身仍不与原版同步 |
| 行动、技能与状态 | 99 种源技能全部共用同一施法事务及最终EXP（`coverage.json`：99／99；基础与上位职业学习表的 79 条学习记录全部可施放）：琥的20ST毒魔箭（伤害与独立毒判定、十字空中心、多目标后一次成长）、水剎／地裂／咒殺／水龍波／熾焰鳥／空鳴破／地龍震 原伤害与元素抗性、滅／裁／極（magicOTHER 零抗性）、逆風裂空／天滅崩雷破 大范围脚印；绝技通道 氣刃斬 与 26 条源绝技（天雷猛襲劍／風狼葬天擊／流星降 等元素绝技乘目标对应抗性，magicOTHER 不乘；排山倒海／妖華紅蓮舞 等自身中心，皇龍閃／龍嘯天驅／翔天刃風擊 **直线**贯穿），范围绝技走与区域魔法相同的逐目标事务；队员初始绝技 銀之手（偷金）／連續突刺／碎岩擊／魔晃斬 与敌方「2」版本（magicOTHER2 同 type 5 不乘抗性）；**衰弱**状态（四属性减幅后走职业公式刷新，状态页显示 live 值）与绝技通道状态族 魂體衰竭／弱體箭／獸神怒號／影纏、支援族 聖靈祝福／萬息秘孔術（一次净化麻痺／中毒／禁魔／衰弱）／萬息集氣法／萬息降靈法／萬息臨界法（回魔封顶）、增益 千羽風靈壁／激怒／精神統一、再行动 天鳴覺醒（原队列语义）／取消行动 獅子吼／吸血劍／竊殺／金之手（偷物进「稍後領取」）——见[原技能功能位](evidence_packets/static_reverse/original_skill_function_bits.md)；地精守護／灼熱波動／退魔共享当前增强，退魔保留其他状态；**第九波**：高阶全域伤害魔法 天地鳴動／怒濤地裂崩／魔燒焚燼／怒炎魔獄燋／烈蝕水彈／極零裂凍破（各元素既有伤害路径，boss 051／052／054／057–060／065 初始持有、劍豪／賢者 学习）、区域增益 地靈聖護／赤炎波動、区域回复 大地之癒／大地之惠、五位复合状态 死骸腐靈獄、**魔障壁**（magicFun_AllUp：五抗性 +rand(14)+7 累加封顶 20／80，退魔不解除，static-derived 自 `0x40b1ee`／`0x448903`）与 job 97 的 神怒；月花五段、普通／反击末击效果、白光之翼独立行动、麻痺入口／尾部与取消／保存保持原有合同 | 高級金之手／百裂突刺2／獅子吼2／吸血劍2 四行源表存在但原作无人持有（PLAYERS／学习表／模板均不引用；059 的 `special_other: 吸血劍2` 按别名位落到 無想冥殺），仅按本尊 policy 登记为数据行；第九波新技能无专属特效素材（降级到各元素既有表现或通用状态效果，provisional）；AI 仍不用绝技通道的支援／增益（獅子吼／金之手 无原桶）、HealMP／StealHP／StealItem 的两次 EXP 换算合并为一次、金之手 的装备偷取加值记 0、直接读 combat_profile 的伤害公式未取衰弱后 live 值、全角色资格、原全局RNG、直线的源障碍停线、新技能的专属特效（现降级到通用效果／风刃帧）、高位状态机其余分支、复活和其余效果；PLAYERS原包字节差异尚未解决 |
| AI、队友与后续关卡 | 原目标／类别、呼叫、自救与友军施援；原辅助优先级下补齐尚缺的攻防增益、对当前增强的敌人退魔，第二行动重新判断；持有／锁定／等待／守备、单格／3×3通行、四邻高差／邻接成本、全图选点／失效重选、身体边缘与空格中心；第二战正式开场及编译胜负事件 | 原全地图flags、完整中心双随机流、完整辅助dispatcher与控制资格、其它队友能力、跨关存档 |

扩展与修改（改剧情、加关卡、换配乐、加 opcode 表现）的入口见[扩展指南](EXTENDING.md)；后续唯一优先级入口是下方 [Next steps](#next-steps)；[机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)记录证据等级，[知识索引](KNOWLEDGE_INDEX.md)定位资料，[协作记录](../PARALLEL_WORK.md)登记文件负责范围。历史研究中的“尚未接入”须结合本表及后续提交判断。

### Live product path

```text
project.godot
└── game/title/TitleScreen.tscn     原版標題畫面（Title001／002／021–028）：開始新故事／戰場記錄／離開遊戲
    ├── game/title/MoviePlayer.gd     開始新故事 → 原开场动画 start.ani（movie.pak；任意键跳过）
    └── BattleSceneRuntime.tscn
        ├── BattleSceneRuntime.gd      scene/input/opening/presentation
        ├── BattlePlayLoop.gd          single mutable battle state
        └── content/battles/campaign.json  start_level "51" → content/battles/battle_051.json（由 `level_battle:51` 生成；其余 127 场同一条数据链）
```

第一战不再有专用规则或开场（S5，2026-09-22）：51 关与其他关一样由 seed→battle 组装、由 winfail 解释器与 `BattleOpeningCoordinator` 驱动；`first_battle.json` 只作约 20 个 Python 生成器的名册模板输入与开发夹具。撤离胜利格按脚本为城门 (8,6)（resource-derived，替换此前 provisional 的 [14,10]）。

普通启动使用 `tools/play.sh`（先导入资源并检查错误），先到标题画面（[回执](evidence_packets/runtime_observations/title_screen/README.md)：布局按原录像参考帧逐 shape 匹配；「開始新故事」清空战役进度、黑场后播放原开场动画（`movie.pak` 的 `start.ani` 742 帧 15 fps＋`start.snd`，由 `hsl generate movie_import`（`hsltools/assets/movie_import.py`）解码为 WebP 精灵表与 WAV，任意键／点击跳过；原作在进入 level 51 时播放，重制放在标题与首场之间；[播放回执](evidence_packets/runtime_observations/original_movies_playback/README.md)）再进入 `product_opening`，「戰場記錄」优先恢复最近的战斗检查点、否则接续已保存的战役位置，「離開遊戲」退出；原 handler 未定位——光标／亮起／淡出为重制读法；配乐照原版放第 03 首（[原版配乐](evidence_packets/static_reverse/original_music.md) §3）；败北结果页可按 Esc／「回主選單」经 Title011／012 的 GAME OVER 画面回标题；战斗中 Esc 卷出原版系统卷轴 Title041——任務說明／儲存戰場記錄／讀取回憶錄／讀取戰場記錄／回主選單 可用；大地图 Esc 卷出战间卷轴 Title051——儲存／讀取回憶錄 走 Title031 八槽列表、回主選單 可用；兩種卷轴的 設定選項 打开 Title039：場景效果／音效音量／音樂音量 生效并持久化，預備動作 未重制；战间 讀取戰場記錄 恢复最近的战斗检查点；整理裝備 打开战间整理裝備画面：受控队伍成员／属性／装备与背包换装走与战斗内相同的规则校验并写回战役 carry，版式为重制读法，[回执](evidence_packets/runtime_observations/party_equipment/README.md)），再按 `STORY051` token 队列推进，到 `first_control_marker` 后打开 Leonard 的行动状态。

安静行动、领取或结果界面按F5保存，F9读回；有存档时开场右上角提供“繼續存檔”。“稍後領取”的物品可从状态页或结果页重开。当前为单战单槽保存，配置不同拒绝读取，不兼容原作存档或任意动画中断。

回复／驱毒来自角色自身初始声明或已提交的职业学习记录，正式第一战没有额外获得治疗术。已验证能力及明确授予夹具的实际输入入口见 [水系回复与自保](evidence_packets/runtime_observations/support_magic/README.md)和[移动友军援助](evidence_packets/runtime_observations/ally_support/README.md)。有实际回复药的AI也能移动到残血同伴身边用药；正式库存不额外增加。点击非当前行动的队友可只读检查其状态，不会切换行动者。

移動力按源基础加当前装备后夹到0..12，玩家范围和AI移动都读同一个move_point。降低装备移动力不会使已经走到的位置瞬移；取消待提交移动会回原点并按当前装备重新选格，已确认的装备仍保留。三件新增支持装备不是默认赠送，来源、成长及实际输入见[移动装备链](evidence_packets/static_reverse/original_equipment_mobility.md)。

普通同侧单位可以经过，但不能作为最终落点；选格显示同一路径与实际消耗，队友格提示“可通過，不能停留”。AI预算截断也必须停在合法格。源固有飞行／不阻挡能力独立于装备预算，首次初始化、成长、换装及恢复保持一致；正式第一战不额外授予飞行。WRD原高度字节保留并离线重建源哈希，见[角色通行](evidence_packets/static_reverse/original_actor_traversal.md)及[实际输入](evidence_packets/runtime_observations/actor_traversal/README.md)。

大型size_type1以单一角色锚点派生3×3占地，地面逐候选检查整块空间，不能套用单格同伴挤过例外。大小角色都四邻移动；身体边缘可选中、攻击、施法、支援或用药，区域按身份去重，死亡同时释放九格。玩家与AI共用当前路径和费用、空格中心、目标失效重选；装卸、升级、额外攻／行动、状态与恢复不复制占格或结算。原039海輝魔以独立开发场景可玩，正式编队不增员，见[来源与入口](evidence_packets/static_reverse/original_large_actor.md)和[十三条实际输入](evidence_packets/runtime_observations/large_actor/README.md)。

白光之翼允许每次轮到时连续行动两次，第二次重新获得当前预算并可独立攻击、施法、支援或用药。第一次的演出／经验／领取／成长完成后显示“再次行動”；最后一次才扣该角色的毒伤／状态时间并交给下一人。第二次卸装、重装或读档不增加次数，胜负／撤离立即结束剩余行动。它与普通攻击追加一击分别计算，正式第一战不默认赠送。见[原额外行动](evidence_packets/static_reverse/original_extra_action.md)与[实际验收](evidence_packets/runtime_observations/extra_action/README.md)。

当前七职业沿各自已验证分支统一刷新。源mode决定HP等级项，不由临时可控或阵营替代；换装／升级不回满当前HP/MP，不追溯重排本轮queue。正式NPC现经原交锋入口取得EXP并自动按职业配额分配，不能套用玩家学技；原登记玩家临时交给AI也保留手动成长身份。`GrowthLifecycleTrial.tscn`提供可独立游玩的治疗升级→新学驱毒→第二行动链及剑士确认加点；初始毒、经验／耐久和装备是明示演练配置，正式默认授予不变，见[成长实玩](evidence_packets/runtime_observations/growth_lifecycle/README.md)。

新接入的[002祭司](evidence_packets/static_reverse/original_priest.md)来自玩家槽1的原绑定／模板复制证据；029仅为第三战开场离场演出角色，不能据其jobWise字段替代战斗模板。原002錫杖、治癒之水、MP药和独立jobPriest85刷新已可用，普通起跳／落地程序和六帧资源已接入；独立`PriestTrial.tscn`通过配置tina作为主角，保存／败北／镜头不再要求Leonard。开发场景的附加库存、站位与受伤同伴明确标注，正式第三战规则尚由presentation线独立接续。

002源初始绝技[月花圓舞](evidence_packets/static_reverse/original_moon_dance.md)已开放：选择自身，对周围敌人逐目标处理五段，整次只付20气力。目标死亡后的后续原抽样不再产生伤害／经验，全段使用施放前等级与连续数，最终统一经验／升级和死亡奖励；与普通双击、反击和额外行动分开。玩家取消／移动、AI重新选点／剩余目标、原资源演出、保存及三终态见[十三条真实输入](evidence_packets/runtime_observations/moon_dance/README.md)。`MoonDanceTrial.tscn`提供独立演练：源地图与角色，额外开发库存、40气力、120HP／20speed加值；正式第一战和PriestTrial仍从原有0气力开始。

资源装备在最后一次行动才执行毒伤→生命回复→魔力回复→生命转魔力，结束后AI重新依据当前资源选行动；减耗只改变各次实际施法费用，重复来源不再次减半。血衣按当前HP上限采样，最低保留1HP，满MP仍损生命。防毒／防禁魔装备只阻止后续状态，不解除已有状态；两件命中饰品合计+20只修正魔法主命中，不提高独立状态成功率。反馈等前一段移动／交锋／遗言／EXP／领取／用药完成才显示，读档不重放，终态不补回复或复活。回复与道具的随机抽取自 2026-09-25 起走原版算法的伤害随机流 `damage_rng`（生成器 `0x458c10`／rand `0x458c80` 逐值对拍，与交锋共用、随单战存档与战役承接保存；单战存档 v5，旧 v4 拒读），不再是独立 `recovery_rng`／`item_rng`；AI 决策等其余随机数改抽原版全局流的工作在 RNG-A 线进行。见[源资源尾部](evidence_packets/static_reverse/original_resource_recovery.md)、[施法装备](evidence_packets/static_reverse/original_casting_equipment.md)及[十六条实际输入](evidence_packets/runtime_observations/casting_equipment/README.md)；原职业装备资格和默认授予保持不变。

### 战役注册现状（按区域）

原作主线 72 关（47 场战斗＋22 段过场，884 条 actMessage）；战役已注册 PAK 中**全部带 STORY 脚本的主范围关卡**（66 个场景）＋特别关 900／901／902／903／904 ＋ level 998 谢幕。逐关流转见[战役总览](evidence_packets/resource_inventory/campaign_overview.md)（自动生成），数字与口径见[范围盘点](evidence_packets/resource_inventory/original_scope_inventory.md)（`hsl check scope_inventory` 随 campaign 注册自动更新）；逐关数据包由[知识索引](KNOWLEDGE_INDEX.md)定位。

- **序章链（正式战斗＋过场）**（已注册：51 → 52 → 58 → 60 → 53 → 1 → 大地图）

  - 能做：
    - 第一战胜利页「下一戰」按 winfail `[52,52]` 进第二战并承接 Leonard 的等级／经验／属性／装备／库存／金币（HP/MP 回满为重制策略，[承接回执](evidence_packets/runtime_observations/campaign_handoff/README.md)）
    - 第二战 STORY052 开场、event1 增援自地图边缘走入、event0／胜败对白进共享对白视图、王座厅 23 个 obj-052 站立物件、`actPlaySound(CLIP001)`（[开场](evidence_packets/runtime_observations/second_battle_opening/README.md)／[增援](evidence_packets/runtime_observations/second_battle_reinforcement/README.md)／[对白](evidence_packets/runtime_observations/second_battle_story_dialogue/README.md)）
    - 胜利 `[58,58]` 进 story-only 尾声 58（STORY058 全部 53 token）→ `[60,60]` 王座厅 60（[回执](evidence_packets/runtime_observations/story_scene_060/README.md)）→ `[53,53]` **level 53 正式战斗**（受控者为 STORY053 安装的 002 祭司；攀绳 shape override、逃出区标记、通用 winfail 解释器 `WinfailScenarioRules` 经 `BattleScenarioRuleAdapter` 提供到达胜利／阵亡失败／回合与数量事件增援；胜负文案由 Win Board 资源标签渲染；campaign 标 `party: separate`；[开场预览回执](evidence_packets/runtime_observations/story_scene_053_preview/README.md)）→ `[1,1]` **level 1 歐姆村正式战斗**（003 弓手、两种 pmNPCPlayer 村民、原编队；胜利执行城镇事件 9 写入并回大地图；[来源](evidence_packets/static_reverse/original_ohm_village.md)／[实际输入](evidence_packets/runtime_observations/ohm_village/README.md)）
    - winfail 事件／结果链作为**脚本演出**播放（生成器编译 `scenario_rules.status_timelines`，解释器触发后按脚本顺序播对白、延时、走位离场、镜头与音效，再恢复回合或显示结果；离场单位的在场／占用／队列由 SR-068 消费，[来源](evidence_packets/static_reverse/original_script_departure.md)）
    - 战役位置随每次跨关 hand-off 写入 `user://campaign_progress.json`，新进程进第一战时提示「繼續／從第一戰重新開始」
  - 边界：
    - 结果消息 122 的第一战展示位置
    - 原全局初始化顺序、增援落点整除读法、原走位／攀绳／淡黑时钟各有重制边界
- **正式战斗**（已注册：第一章 1 歐姆村、2 戈爾山道、3 盜賊洞窟、5 呼嘯平原、6 席達鎮、7 寧靜之森、10 帕尼西雅城廢墟、12 巴瀚納海峽、37 古代神殿遺跡；第二章 13 龍之息（火山）、15 深淵之沼、17 艾瓦台地、18 那可那魯邊境、19 利魯瑪山地、21 回音之谷、22 尼布魯瀑布、24 哈莫特沙漠、26 亞雷比斯、28 眾神的宮殿遺址、29 約瑟河、30 絕望之谷、31 漆黑之森、32 拉格納沼地、33 黃昏之丘　陰、34 沙羅尼亞近郊、36 薩魯司海岸、38 幽闇墳場、39 黃昏之丘　陽、40 聖靈之森、41 悲嘆之湖、43 大地的裂縫、44 亞修頓大橋、45 克萊恩城；终章 59 劫數・地劫神、73 悲嘆之湖・兄弟的抉擇、75 自覺與宿命・塔克斯、76 最終的序曲・妖精王、77 破滅的命運・席德爾、78 接觸・妖精王、79 終焉・咕嚕最終型態、80 禁忌之魂・墳場地下；特别关 900 曼多力亞對峙、901 菲納斯河畔伏擊、902 艾瓦台地　尋、903 哈莫特沙漠　魔騎士團、904 利魯瑪山地再訪；随机遭遇战 501–578）

  - 能做：
    - 大地图点 2 进 `gol_road_battle.json`：原七人开场后强盗剩一名触发緹娜及四名追兵安装、强盗离场，第二阶段胜负续 55／56 营地与大地图（[回执](evidence_packets/runtime_observations/gol_road/README.md)；`story_002.json` 与[旧预览回执](evidence_packets/runtime_observations/story_scene_002_preview/README.md)仅作独立回归）
    - 各关 EVEF 寶藏箱（level 1／2／3／5／6／7／10／12）作关闭宝箱站立物件绘出，正式 1／2／6 的箱子可开（6 的内容取自 seed 记录的 EVEF override words）
    - **6 席達鎮是通用组装器 `hsl generate level_battle:6`（`hsltools/levels/battle.py`）的首个关卡**（预览＋seed＋来源模板 → `battle_006.json`：4 受控槽由 obj_Story_Player1–4 安装、12 村民 friendly、7＋4 士兵与等待 3 回合的隊長，WINFAIL006 的第 5 回合换目标／增援／突圍三种胜利全部现场解释；[回执](evidence_packets/runtime_observations/battle_006/README.md)）
    - 注册的正式战斗由 `tests/run_battle_sweep_tests.gd` 统一扫描（开场→首次控制→强制胜利→交接）
    - **5 呼嘯平原**（`--level 5`：13 单位＝4 受控＋9 敌方 AI，WINFAIL005 的 `win_0`／`fail_0`／`event_0` 时间线、寶藏记录 17 物品字进 `treasures/battle_005.json`；剧情走查改经 `battle_005.json`，`story_005.json` 预览留作独立回归；[回执](evidence_packets/runtime_observations/battle_005/README.md)）
    - **3 盜賊洞窟**（`--level 3`：17 单位＝3 受控＋漢克斯＋13 敌方 AI；STORY003 开场 `actSetPlayerMode pmEnemy`＋`actSetPlayerUndead` 把 漢克斯 置敌／不死，WINFAIL003 胜利段转 pmPlayer、清 undead 后入队并随 carry 进 61，static-derived 自 `0x450840` case 0x42／0x40（[原读法](evidence_packets/static_reverse/original_player_mode.md)）；[回执](evidence_packets/runtime_observations/battle_003/README.md)）
    - **7 寧靜之森**（`--level 7`：25 单位＝4 受控＋21 敌方 AI，第 5 回合插入 6 名 023＋2 名 024、第 6 回合 雪拉 005 经 `obj_Story_Player5` 入队为受控并随 carry 进 64，`tests/run_level7_runtime_tests.gd` 直接推到第 5／6 回合验证；[回执](evidence_packets/runtime_observations/battle_007/README.md)）
    - **10 帕尼西雅城廢墟**（`--level 10`：首次控制 2 受控对 4 敌，琥／漢克斯／雪拉 与后续波次由脚本演员模板在事件段安装，win 0 第 5 回合才武装；打人閃電照原版每 2 次交接落一道、画面内落点九格伤害、劈不死（`DropLightningRules`，[证据](evidence_packets/static_reverse/original_drop_lightning.md)；落雷演出未画）；[回执](evidence_packets/runtime_observations/battle_010/README.md)）
    - **19 利魯瑪山地**（`--level 19`：雷特 1 受控对 4 名 041，增援 041／043／038 与后续队伍安装；[回执](evidence_packets/runtime_observations/battle_019/README.md)）
    - **26 亞雷比斯**（`--level 26`：8 受控（001–007／009）对 4 名 039＋8 名 038，26 个船殼为静态物件并计入 `static_enemy_counts`（fail 2 `SID_ENEMY101,26`＝任一船殼被破坏即失败，重制不模拟破坏），第 14 回合插入 7 名 035；[回执](evidence_packets/runtime_observations/battle_026/README.md)）
    - **29 約瑟河**（`--level 29`：25 单位＝7 受控（001–007）对 023／024 追兵，2 箱，胜利承接 70；[回执](evidence_packets/runtime_observations/battle_029/README.md)）
    - **34 沙羅尼亞近郊**（`--level 34`：23 单位＝緹娜 领 4 受控＋3 名 062 村民对敌，event_1 以现有解释器把 023×5／044×4 转 pmEnemy，`initial_status_overrides.win=[0]` 在控制交接时武装 win_0 为显式重制策略；[回执](evidence_packets/runtime_observations/battle_034/README.md)）
    - **38 幽闇墳場**（`--level 38`：42 单位＝7 受控，033／034／035 三面涌入，到达区 `[7,3]`–`[7,5]` 的 `victory_script` 承接 80；[回执](evidence_packets/runtime_observations/battle_038/README.md)）
    - **40 聖靈之森**（`--level 40`：17 单位＝8 受控，3 个脚本模板槽承接第 14 回合增援，`victory_boss`；[回执](evidence_packets/runtime_observations/battle_040/README.md)）
    - **41 悲嘆之湖**（`--level 41`：24 单位＝8 受控（001–007＋009）对 049／065／056，敌 056 HP 条件胜利承接 73 兄弟的抉擇；[回执](evidence_packets/runtime_observations/battle_041/README.md)）
    - **901 菲納斯河畔伏擊**／**904 利魯瑪山地再訪**（大地图 event 901／904 直接进 `battle_901.json`／`battle_904.json`：22 单位＝5 受控对 023／024，5 单位＝雷特 1 受控对 4 名 041 再加 041／043／038 波次；[901 回执](evidence_packets/runtime_observations/battle_901/README.md)／[904 回执](evidence_packets/runtime_observations/battle_904/README.md)）
    - **12 巴瀚納海峽**（`--level 12`：39 单位＝7 受控对 32 名 038，45×60 地形，1 箱；WINFAIL012 第 8／10／16／23 回合事件链由 `actSetPlayerFixPos`（按 code＋serial 写守备锚点 `ai_home_coord`＋半径 `ai_fixed_radius`，单位沿 0x411080 精化行走到锚点；图外锚点＝撤退点，走到最近图边后由 `actWalkAndDelete` 离场——R23，替代早先「瞬移＋off_map」读法）／`actSetPlayerFly`（traversal.flying）／`actChangePrevInsertObjectID`（插入回执 id）解释，62 个 Enemy101 船殼仍是静态开场物件并计入 `static_enemy_counts`——WINFAIL012 fail 2 `actCheckEnemyNumber SID_ENEMY101,62` 按 0x450840 case 0x24 的严格小于读作「任一船殼被破坏即失败」（[目标计数读法](evidence_packets/static_reverse/original_check_targets.md)），重制不模拟船殼被破坏故该失败不会发生（provisional 边界），事件链由 source-timed 夹具按回合推进；[回执](evidence_packets/runtime_observations/battle_012/README.md)）
    - **22 尼布魯瀑布**（`--level 22`：15 单位＝7 受控对 8 敌，041／043 增援与 051 事件，`actGetItem(14,1)` 经与 teGetItem 同一条队伍物品路径入 carry；[回执](evidence_packets/runtime_observations/battle_022/README.md)）
    - **43 大地的裂縫**（`--level 43`：25 单位＝7 受控对 18 敌，`actDeletePosObject(816,111,4,defProcStandObject)` 按世界坐标＋process code＋方形范围命中站立物件并隐藏其表现节点，`actGetItem(16,1)`；[回执](evidence_packets/runtime_observations/battle_043/README.md)）
    - **80 禁忌之魂・墳場地下**（`--level 80`：30 单位＝7 受控对 23 敌，脚本推进——到达两处删除站立物件、发放物品 112／15 再武装 win_0 的 `victory_script`；[回执](evidence_packets/runtime_observations/battle_080/README.md)）
    - **15 深淵之沼**（`--level 15`：18 单位＝7 受控对 038／037／033，WRD `0x200000` 毒沼格上行动结束即中毒（非飞行、不免疫；敌人全免，[证据](evidence_packets/static_reverse/original_poison_gas.md#地形毒lane-scenemech2026-09-27)），WINFAIL015 第 27 回合 `actSelectInsertEvent`（1810→event 3／1811→event 4）在战斗提示内二选一——所选 event 状态插入同一 `WinfailScenarioRules` 循环并拼进当前提示过场；event_2 安装的 咕嚕 008 带源 range3CellCircle 武器实际上场（射程 builder 落地前曾记 `skipped_unsupported_weapon_range`）；胜利写点 15 遭遇 540 回图；`LEVEL15_RUNTIME_HARNESS` 直接推到第 12／27 回合验证）
    - **18 那可那魯邊境**（`--level 18`：21 单位＝6 受控对 15 名 041／043，STORY018 的 `SID_ENEMY100/1` 绑定到静态门物件 `obj_Story_Level_Door`——`actDeleteObject` 隐藏该地图物件镜像而不虚构 PlayLoop 演员；win_0 直接／win_1 敌总数两条胜利均回点 18）
    - **900 曼多力亞・對峙**（`--level 900`：34 单位＝5 受控＋6 友方村民对 23 敌，酒馆事件 30 挂到点 9；STORY900 對峙 二选一由所选 event 状态插入解释器后拼进提示，WINFAIL900 event 1 武装正式胜负，胜利把点 9 恢复 bmpmTown 回图；`actMoveDispWait` 为无脚步相对滑动、`actShowSectionName` 显示 WORD900）
    - **21 回音之谷**（`--level 21`：20 单位＝7 受控对 041×5／043×3／038×5，WINFAIL021 按敌总数分段增援并插入 塔克斯 053＋049 骑兵，win_0 写点 24 替代战 903 与点 21 遭遇 528）
    - **24 哈莫特沙漠**／**903 哈莫特沙漠　魔騎士團**（`--level 24|903`：各 38 单位＝7 受控对 024／027／030／031／044，WINFAIL024／903 的 049／053／054 到场与 053／054 对白链共用同一解释器；903 是 WINFAIL021 选定的点 24 替代战，共用 24 的地图与开场阵容）
    - **75 自覺與宿命・塔克斯**（`--level 75`：28 单位＝8 受控（001–007＋009）＋塔克斯 054 对 045／049／065，决斗胜利进 57 结局分派；053／054 的成长模板已补进 `progression.json`、job 91／99 入场成长接入 `EntryGrowthRules`）
    - **31 漆黑之森**（`--level 31`：9 单位＝3 受控，胜利续接 `31,71`）
    - **33 黃昏之丘　陰**（`--level 33`：15 单位＝4 受控，保留源大地图交接 `31,32`——无窗口化 world-map 消费者，仅在夹具中规范为结果页）
    - **32 拉格納沼地**（`--level 32`：22 单位＝3 受控对 19 敌，噴人沼氣照原版每 4 次交接喷一次、九格中毒（`actCheckNextSerialNumber` 交接计数定时器＋`PoisonGasRules`，[证据](evidence_packets/static_reverse/original_poison_gas.md)；喷气演出未画）与 `actUseItem` 物品 252）
    - **36 薩魯司海岸**（`--level 36`：16 单位＝7 受控（含 克羅蒂 009 安装）对 055／049／032，`actSetPlayerNoAttack` 状态，胜利续接 `36,gameBigMapLevel`；源宝箱记录 24 坐标在图外，显式记 `skipped_out_of_bounds` 不夹到边缘；[31／32／33／36 回执](evidence_packets/runtime_observations/battle_031/README.md)）
    - **17 艾瓦台地・嚎的歸隊**（`--level 17`：24 单位＝5 受控＋4 友方 艾瓦遺民 对 15 敌，第 6／8 回合源时序插入与 嚎 007 的 obj_Story_Player7 安装由解释器消费；`actSetPlayerExecMode` 只写源执行字段（原 obj+0x64 的 3／5），不动阵营／可控性；胜利写点 17 事件 519、遭遇率 24 后续 `17,67`）
    - **902 艾瓦台地　尋・失落的通路**（`--level 902`：19 单位＝5 受控对 14 魔物，命運神殿 event 53 在未访问 17 时替代进入；`actRandomSetSysArrivePos` 从五个 32 像素对齐候选点用原版全局流 `global_rng` 选一（RNG-A，2026-09-25：抽取算法与播种方式同原版 `0x458c10`，在全局序列中的位置待 AI 优先级链补齐后才与原版逐次对齐），每名指定成员到达同一点后 `actCheckPlayerArriveSysPos` 授予物品 281，胜利续 `17,68`）
    - **30 絕望之谷・不死軍團**（`--level 30`：14 单位＝7 受控对 克羅蒂 053＋049×6，`actCheckRoundDisp`／`actDetectRoundDispDisp` 回合显示计数与 HP 事件链引入 傲 055／席德爾 056，胜利为全员撤离的源路线（清敌不算胜利，sweep 夹具按 event_21 推进），原回合显示 packed-word 调度 provisional）
    - **39 黃昏之丘　陽**（`--level 39`：19 单位＝7 受控对 032／049／065，第 3／5／7 回合以 `actDeletePosPlayerXRange`／`actInsertStoryObjectXRange` 删／插山丘物件（像素参数量化到 32px 格），胜利续图）
    - **44 亞修頓大橋・橋上的決戰**（`--level 44`：原作最大的一场，82 单位＝7 受控对 75 敌，1 胜 2 败分支；高单位数的 AI 节奏与桥面碰撞 provisional）
    - **45 克萊恩城・城門攻防**（`--level 45`：43 单位＝8 受控对 35 敌，战斗内 `actEnterStorageWindow` 打开同一 整理裝備 画面并把改动投影回唯一 PlayLoop）
    - **76 最終的序曲・妖精王**／**77 破滅的命運・席德爾**／**78 接觸・妖精王**／**79 終焉・咕嚕最終型態**（`--level 76|77|78|79`：57 结局分派进入的四场终战，共用 level 58 地图 alias；76 21 单位＝8 受控对 13 敌、妖精王 058 持源 range0Cell 武器 57（保留装备、无普通攻击目标）；77 26 单位＝8 受控对 18 敌，席德爾 056 HP 归零后经 `actSetPlayerPosToRandom0`／白光／`actDeleteRandomPosObject`／`actInsertObjectRandomPos` 换出「059」——无 059 模板／肖像／面板标题，重制以 056 身份上场（provisional）；78 24 单位＝8 受控对 16 敌，**没有 win 段**，event_2 打开 整理裝備 后经 `actSetNextPlayLevelEvent 79,79` 交接到 79，夹具按「事件结束」而不伪造胜利；79 9 单位＝8 受控对 咕嚕最終型態 057（持 range3CellCircle 武器 53），`actInsertRandomObject` 随机特效坐标只作表现记录、`actSetDoublePageMode` 记录为表现请求；随机放置走 loop 自己的 RNG 与 pending_insert→inserts 唯一路径，原全局 RNG 序列未重建）
    - **13 龍之息（火山）・火山突圍**（`--level 13`：16 单位＝7 受控对 051×6＋050×3，胜利为到达出口矩形 (416,288)–(448,288)，回合逾时为败；051 龍 以 profile 声明的 3×3 脚印占位避免源位置互相重叠）
    - **28 眾神的宮殿遺址・神殿守衛**（`--level 28`：16 单位＝7 受控对 050×9，win_0 只在第 4 回合的回合显示／事件链后由 event_2 武装，21 个宝箱内容自 PAK seed；9 个未对齐终点按 nearest_free 记 provisional）
    - **73 悲嘆之湖・兄弟的抉擇**（`--level 73`：9 单位＝8 受控＋倒地的席德爾 056，无 win／fail 段——殺／放 两个选择分支都汇入 event_2，按事件结束交接世界地图并写 over-flag，不伪造胜利）
    - **59 劫數・地劫神**（`--level 59`：9 单位＝8 受控对 地劫神 060——只有站立帧、move_point 0、持 range5CellCircle 武器 55——HP 归零经 `actCheckPlayerHPLow SID_ENEMY060,1,0` 进入暗屏／结局电影 140／`90,998` 通关交接）
    - **随机遭遇战 501–578**（已访 Visit／Battle 点按 ratio 掷中即进 `battle_5NN.json`，标题取大地图点名＋「遭遇戰」，胜利回图站原点；`actCheckEnemy`／`actCheckPlayer` 按原作只计仍在场的 id，从未放置的 class 视为已阵亡（[目标计数读法](evidence_packets/static_reverse/original_check_targets.md)），533 列出的 024／027 因此不再阻断胜利）——`level_battle:50N` 的 encounter 模式只用 seed 组装（EVEF 装位 obj_Data9 槽位＝受控槽、obj_Data7＝怪物模板；基底关地图／地形／配乐；共用演员池 `battle500/`；各关自有时间线／文本证据／地图物件），seed 对基底关逐字节相同的地形与像素相同的地图直接引用不复制
    - **条件编队** `ConditionalPartyRules`（有才產生 ＝ 原 defProcPlayerInstall 的 obj_Data8 条件安装：只有已存在且启用的注册槽进构造器，[原安装分支](evidence_packets/static_reverse/original_player_install.md)，static-derived；carry 代替原「注册且启用」槽表）：进战只安装 carry 里的成员，无 hand-off 的开发启动装满槽
    - 可上场槽 001–009（面板标题表已扩到 39 名演员；unavailable 槽为空）
    - **正式战斗同一读法**：28 关（12／13／15／21／22／24／26／28／29／30／31／32／36／37／38／39／40／41／43／44／45／59／73／75／76／77／80／903）EVEF 里的「咕嚕(有才產生)」／「克羅蒂(有才產生)」记录由 `hsltools/levels/battle.py` 的 `conditional_installs` 按原位置＋STORY 走位组装为 `install_if_carried` 槽，带该成员的 carry 才上场，不带则该槽不出现（此前这些关静默丢掉带 咕嚕 的队伍）
  - 边界：
    - 其余第二章／终章战斗本体待接（缺 token 与模板清单见 Next steps 第 5 项）
    - 来源模板 54 个（[主线角色来源](evidence_packets/static_reverse/original_campaign_actors.md)，`content/generated/hsl/actors/`，含转职上位形态 010–020；005／008／020 缺四项 AI 策略、008 源 32 武器 range 3CellCircle 初始化明确拒绝）
    - 奖励数据（[奖励合同](evidence_packets/static_reverse/battle_reward_inputs.md)）已覆盖全部 66 个 PLAYERS 演员行
    - undead 的 HP 归零免死／受击免伤为 negative-evidence，重制只保留标记
    - 条件编队的「注册但禁用」成员未建模
    - 被阻挡的源装位／终点改落最近空格为 provisional
    - 强制胜利夹具只证明流转不证明战斗
    - 预览宝箱只绘出，开箱属战斗本体
    - job 91（jobElfMan）／99（jobDarkAngel）已有自己的职业属性公式（[原 91／99 职业属性](evidence_packets/static_reverse/original_job_stats_91_99.md)，static-derived 自 `0x448840` case 0x5b／0x63、cap 表行 11／19，原生探针 050／058 复核），`run_campaign_actor_tests` 对 050／053／054／058／060 断言全部字段等价
    - 武器射程只接受 RANGE.TXT 编译出的 range0Cell／1Cell／2Cell／3CellShoot／4CellShoot／5CellShoot／3CellCircle／3CellThrust／5CellCircle（其余 range 符号仍拒绝）；自 2026-09-25（WRANGE）起武器可攻击格、反击判定、敌方武器格显示与玩家施放范围按原版 0x40f8b0／0x40f5d0 在地图上传播（0x4000 格停线、贴墙前方检查、同侧占位格不写入、高度不读；354 次原函数返回逐字节对上，static-derived），技能效果区域与 AI 选位仍平铺（WRANGE2）；局部框裁剪、大型角色起点 provisional
    - `actCheckEnemyNumber` 的静态敌方对象计数（船殼）恒定
    - 攻击切入（`combat_animation/manifest.json`）已覆盖全部 47 名来源演员＋上位形态行 010–017／019／020（原 15 名逐字节不变；新增 32 名——队友 005／007／008／009 与 027–065 魔物、boss——与上位行的绑定由 ANIMAL 程序推导），`_process_missing_ordinary_clip` 的显式降级只剩兜底
    - 新增演员与上位行的 `sprite_facing` 为 provisional（未经视觉审核，运行时不消费该字段；审核表见 `tools/hsl_sprite_facing_audit.py`）
- **完整过场 22 段**（已注册：8／9／65／58／60／55／56／61／62／63／64／66／67／68／69／70／71／72／74／57／81／82）

  - 能做：
    - 自大地图或前一关进入即自动播放全部 STORY token 并交接：8 菲納斯河畔（五人队走入、六句对白、点 9 变战斗点等写入经 `WorldScriptActions.apply_story` 落地并在地图可见，[回执](evidence_packets/runtime_observations/story_scene_008/README.md)）→ 9 廢都（村民游走、緹娜身份揭示，[回执](evidence_packets/runtime_observations/story_scene_009/README.md)）→ 65 廢都室内（[回执](evidence_packets/runtime_observations/story_scene_065/README.md)）→ 66 营地（地图按原 OBS 绑定）
    - 战后营地链 55／56／61／62／63／64（`level55/56.SHP` 两张 640×480 营地全景，61／62／64 别名营地地形 provisional，63 别名 58，[回执](evidence_packets/runtime_observations/story_scene_camp_chain/README.md)）
    - 63 密探 `actShapeMessage`（FACE0054／FACE0008、名字资源 306「???」）经 `BattleDialogue.show_face_message` 显示
  - 边界：走位／跟随／淡黑节奏为重制值
- **开场预览 ＋ 特别关**（仍在产品路径的预览：第二章无带 winfail 的正式缺口；已转正式战斗的 1／2／3／5／6／7／10／12／13／15／17／18／19／21／22／24／26／28／29／30／31／32／33／34／36／38／39／40／41／43／44／45／53／59／73／75／76／77／78／79／80／900／901／902／903／904 的 `story_NNN.json` 预览保留为独立回归，不在产品路径）

  - 能做：
    - 每关自 EVEF／STORY 生成 cast、对白、地图物件、音效与预览场景，播完开场到 `first_control_marker` 停在结束卡
    - 结束卡读生成器写出的 `opening.skip_battle`（胜利段的 next level 与城镇／大地图写入，static-derived），目的地已注册时给「略過戰鬥（視為勝利）→ 續播劇情『…』」／「回到大地圖（不施加戰果）」两行（2→55→56、3→61、6→62→63、7→64、17→67、19→69、31→71；无 next 的关由第一行直接回图并施加胜利写入）
    - 回执：
      - [3](evidence_packets/runtime_observations/story_scene_003_preview/README.md)（漢克斯 在此入队，STORY003 置敌／不死只记录）
      - [5](evidence_packets/runtime_observations/story_scene_005_preview/README.md)
      - [6 预览](evidence_packets/runtime_observations/story_scene_006_preview/README.md)（酒馆事件 23 进关——城镇→关卡→大地图往返为产品路径；现为正式战斗，预览留作独立回归）
      - [7](evidence_packets/runtime_observations/story_scene_007_preview/README.md)
      - [10](evidence_packets/runtime_observations/story_scene_010_preview/README.md)（雨／闪电／燃树特效由 `StoryEffectObjects` 按 `OBJ-ALL.H`／`global.obs` 数据读法呈现，密度速度淡出为重制值）
      - [12 预览](evidence_packets/runtime_observations/story_scene_012_preview/README.md)（薛維斯港 船行 11→12；62 个无步行帧的 Enemy101 船殼作 `static_enemy_object` 绘出；现为正式战斗，预览留作独立回归）
      - [901](evidence_packets/runtime_observations/story_scene_901_preview/README.md)（level 10 胜利把点 8 改为 event 901；「視為勝利」写入酒馆链 27→28→30 揭示 薛維斯港 与路线 10）
    - 900 由酒馆事件 30 挂到点 9（现为正式战斗，STORY900 `actSelectInsertEvent` 二选一由 `select_event_timelines`＋协调器提示接通并把所选 event 状态插入战斗解释器，[合同](architecture/PRESENTATION.md)）
    - 902／903／904 是 TOWNDEF 53 `teBMSetPointEventNotVisit 17,902`、winfail021 `24→903`、winfail902 `19→904` 挂到点上的支线替代战（902 胜利段 `[17,68]` 是营地 67／68 链的唯一入口）
    - 第二章与终章的批量数据链见 [P-048](collaboration/presentation.md)／[P-049](collaboration/presentation.md)
  - 边界：
    - `CampaignProgress.start_skip_battle_handoff` 只施加胜利段的城镇／大地图写入，不模拟被略过战斗的奖励／经验／入队（纯剧情模式金币恒为 0，见 P-055）
    - 「(有才產生)」条件成员（咕嚕／克羅蒂）不安装，其 token 计入 unresolved
    - 配乐照原表 `0x477b44` 放原曲（[原版配乐](evidence_packets/static_reverse/original_music.md) §4）
- **终章与谢幕**（已注册：41→73、45→75→57、57→{76→81→59、77→82、78→79}、38→80；59／79／82 → `[90,998]`）

  - 能做：
    - 73 兄弟的抉擇 STORY 内二选一（两支都回图并写 斐達克 事件）
    - 原结尾动画 `end.ani`（501 帧 15 fps＋`End.snd`）在 59 的 略過戰鬥（視為勝利） 行与正式战斗的 `actPlayMovie` 共用播放器（[来源与格式](evidence_packets/resource_inventory/original_movies.md)）
    - level 998 GameClear（`game/title/GameClearScreen`）：黑场上按原 `defProcClearBOSS` 的 STORYOVER 脚本播 緹娜／漢克斯 尾声独白（[加载者证据](evidence_packets/static_reverse/original_game_clear_epilogue.md)）→ OverBG01／02 上的 Over001／002 叙述 → TITLE011 卡逐槽展示終幕队伍 → workteam 制作群卷轴到「劇終」，任意键跳段，卷毕回标题并清战役自动存档，原创曲《破滅之後》
  - 边界：
    - 57 的 `actSetNextPlayLevelGetOverEvent 0` 已按原规则分派（[原结局分派](evidence_packets/static_reverse/original_ending_dispatch.md)，static-derived：gameoverID1–3 按分排序、首个 flag 条件成立者定 76／77／78，默认 76；`EndingDispatchRules`，结束卡只列该结局一行），over score／flag 由 winfail／剧情／城镇写入共用的世界状态并随进度保存
    - 开发者按键覆盖不建模，预览关只有 `skip_battle` 首胜利段的分到账
    - 57／81 的 `actEnterStorageWindow` 以战间 整理裝備 画面承接（provisional：原窗口内容未测），`actKeepPlayerST` 仍只记录
    - 谢幕版式／时长为重制读法，运行时制作群字串未重制
- **大地图与城镇**（已注册：`content/world/world_map_scene.json`；12 城 191 条 TOWNDEF 事件）

  - 能做：
    - 原数据链入门禁（`hsl check world_map`，`hsltools/data/world_map.py`：bigmap.dat 45 点／44 线、TRACK 折线、12 城、TOWNDEF 191 事件／62 货表、贴图；[结构](evidence_packets/static_reverse/world_map_data.md)）
    - **大地圖可玩**——沿路线旅行、位置落盘、城镇点开城镇、脚本点事件指向已注册关卡时带世界状态 hand-off（[回执](evidence_packets/runtime_observations/world_map_scene/README.md)）
    - **菜单式城镇可玩**——`TownRuntime`＋te 解释器 `TownEventRules`（对话、给金给物、分支、子菜单、商店买卖入 carry 背包、exec／exit、`teSetNextPlayLevelEvent` 进关；[回执](evidence_packets/runtime_observations/town_scene/README.md)）
    - 战斗 winfail 记录与故事 story_records 的城镇／大地图动作在 hand-off 时经 `WorldScriptActions` 施加
    - 流转按原脚本惯例（`hsl check big_map_flow`，`hsltools/data/big_map_flow.py`：151 脚本 352 条指令，[流转惯例](evidence_packets/static_reverse/world_map_data.md#大地图流转脚本惯例resource-derived)：`actSetNextPlayLevelEvent(level, event)` 的 event 为下一关、`gameBigMapLevel` 回图站点 level，无 next 的主线 1–45 默认回图同号点；到达＝城镇点开城镇、Visit 点按 ratio 掷遭遇、Battle／General 点开脚本指派或同号默认关）
    - SR-069 世界／城镇静态合同（`original_world_town.md`：初始菜单树、te 条件语义、到达表、17 个初始隐藏点、点 mode 揭示阶段、m_pnt 三帧、命中 ±16、状态栏完成度／累计时间、配乐 track 6）已对齐进 `WorldMapRules`／`WorldMapRuntime`
    - 第二章入口 兩棲族部落 150／151 无任何脚本 token 添加，现以 `world_map_scene.json` 的 `provisional_unlocks` 桥接（站到点 13 龍之息 后以 150／151 取代 148／149，[架构](ARCHITECTURE.md)）
  - 边界：
    - 路线进入揭示阶段的触发（重制取"进图与到达时揭示当前点路线"）、walker tick、遭遇抽样比较方向、买入后手持槽放置流程与 teDelay 墙钟仍 provisional／negative-evidence（买入价、卖出价 price×50÷100、重要物品拒收及消息 606／607 已 static-derived，见[原作商店交易](evidence_packets/static_reverse/original_shop_transaction.md)；酒館神秘男子按原 9 行价格／货表售出随机礼物并推进计数器，见[原作酒館神秘男子](evidence_packets/static_reverse/original_secret_man.md)，其默认出现率仍 provisional）
    - 150／151 的原引擎规则待 P-051 定位后替换桥接条目

**扩关工具与顺序**（已完成 ①–③）：
- ① 剧情脚本 VM 覆盖——数据驱动 winfail 解释器 `WinfailScenarioRules`（主线 47 战 21 场脚本可完全解释，level 53 由它现场驱动），开场 token 152 个脚本用到的 71 个全部映射
- ② 按关卡参数化的场景生成器（早期 `level_scenario:52|53`；现行通用组装器 `hsl generate level_battle:N`（`hsltools/levels/battle.py`）——全部输入是 tracked 的预览／seed／模板，每关只写一条 `LEVELS` profile，见[扩展指南](EXTENDING.md)）
- ③ level 53 首个非 Leonard 战斗
- ④ 后续正式战斗由 presentation 线按"解锁关卡数／验证成本"逐关组装（3／5／6／7／10／12／13／15／17／18／19／21／22／24／26／28／29／30／31／32／33／34／36／38／39／40／41／43／44／45／59／73／75／76／77／78／79／80／900／901／902／903／904 与遭遇战 501–578 已完成，隔离工作树并行、父线合并统一门禁），单点机制与来源模板此后也由 presentation 自行静态读取补齐。原作全部剧本文本已固化为可复跑语料 `content/imported/hsl/story_corpus/`（`hsl check story_corpus`，`hsltools/data/story_corpus.py`：152 STORY／130 winfail／STORYOVER／TOWNDEF，全部消息 id 有 RESOURCE.TXT 正文，[语料包](evidence_packets/resource_inventory/original_story_corpus.md)）
- 地图别名以 obs 地圖管理員 记录为主证据（60／63／71／76–79／81／82 → 58，61／62／64／66–70 → 55，900 → 9，32↔33 互指，resource-derived；原 loader／回调见[地图绑定](evidence_packets/static_reverse/original_map_binding.md)）

## Working boundaries

武器附毒／行动取消在普通主攻与反击各自的实际末击执行，双击的第一击不重复抽样；提前击杀仍保留原抽样顺序，随后死亡清理不残留毒或占格。武器毒不额外发放法术贡献。取消敌人未来槽不阻止当下反击，也不消耗该目标的毒伤／回复／状态时间；取消选点与撤回移动则保留已经确认的装备、状态和资源，第二行动重新选择不重发第一行动。来源与[实际路线](evidence_packets/runtime_observations/weapon_effects/README.md)包含防护、AI驱毒／回退、存档和三终态；手动体验用`game/battle/development/WeaponEffectsTrial.tscn`，它的额外HP／库存为显式开发设置，正式授予不变。

麻痺使当前玩家／AI失去这次行动，由同一自动入口显示跳过、执行一次已有毒伤／资源／计时尾部，再交给下一人；白光之翼不会因此多跳或多扣一次。精靈石可由相邻队友或AI移动施用，缺MP／禁魔不妨碍道具援助；治疗／驱毒分别保留麻痺，防护装备不清已有状态。完整演出结束前禁止后继操作，保存恢复不补发跳过、资源、EXP或次数。地靈縛、道具及防护没有加入默认第一战授予。见[原麻痺入口](evidence_packets/static_reverse/original_paralysis.md)和[14条实际输入](evidence_packets/runtime_observations/paralysis/README.md)。

普通角色移动后不能施法；冥晦之輪／穹蒼之鍊赋予当前动作的移动后施法资格。取消待提交移动才恢复原地资格，装卸立即重新读取当前能力；白光之翼的第二行动从新位置独立开始，若再次移动仍需权限。AI同样区分本次移动施法与先站位、下次原地施法。奧義之證／穹蒼之鍊把普通武器范围提升一档源十字矩阵，重复来源不叠档，法术范围不变。见[原位置能力](evidence_packets/static_reverse/original_position_equipment.md)与[17条实际输入](evidence_packets/runtime_observations/position_equipment/README.md)；以上饰品不默认赠送。

BattlePlayLoop 是唯一可变战斗状态所有者；输入与表现镜像不能独立修改 HP、库存、经验、坐标或队列。代码分层与按任务入口见 [ARCHITECTURE](ARCHITECTURE.md)，资源定位见 [KNOWLEDGE_INDEX](KNOWLEDGE_INDEX.md)，原规则证据等级见 [机制矩阵](MECHANICS_EVIDENCE_MATRIX.md)。

已批准的重制选择继续有效：开场0气力、0.20秒逐格移动、原资源驱动的可读演出、玩家五点四维成长及未用点数。**配乐已改用原曲**（2026-09-26 交付）：09-23 用户判定 14 首原创曲不符合游戏气质，09-26 同意改用原曲；18 首原曲从用户所购 Steam 經典版导入（[取得、清单与已知用法](evidence_packets/resource_inventory/steam_classic_edition.md)），标题、大地图、城镇、各关与通关尾声按[原版配乐](evidence_packets/static_reverse/original_music.md)在同一时刻放同一首，默认音樂音量恢复为满；原创曲已从游戏删除（git 历史保留）。过去固定一级NPC的运行入口已由初始阵容调级替换；独立保存的生成RNG、玩家先于NPC的初始化调度和跨战补满为明示重制选择。[普通／氣刃斬](evidence_packets/static_reverse/original_ordinary_special.md)、[追加攻击](evidence_packets/static_reverse/original_extra_attack.md)、[连续两次行动](evidence_packets/static_reverse/original_extra_action.md)、[气力](evidence_packets/static_reverse/original_stamina.md)、[风火](evidence_packets/static_reverse/original_magic_damage.md)和[最终EXP](evidence_packets/static_reverse/original_experience.md)分别有原函数／有界调用证据；原全局RNG、全职业、高位状态机其余分支与其他被动及AI组合仍有独立边界。

角色控制仍有 staged 规则（转职已进 play loop 与城镇解释器），已接战役路由与跨启动续战见下方扩关进度；共享carry保存永久取得值并使用新场景来源重算，和单战完整快照分开。跨关补血／队伍延续为明示重制策略，不能替代原handler证据。BattleSceneRuntime仍较大，后续命中opening/input时按实际职责抽离，状态继续归PlayLoop；不另造聚合规则或场景状态机。

验收与历史反馈见 [FIRST_BATTLE_ACCEPTANCE](FIRST_BATTLE_ACCEPTANCE.md)，详细当前事务分别在 [战斗系统](architecture/BATTLE_SYSTEMS.md) 和 [表现合同](architecture/PRESENTATION.md)。旧三选项成长、固定六边形菜单和旧动画速度只解释历史截图，不能覆盖当前代码。PLAYERS 原包字节差异、原敌方 ??? 公开条件、精确时钟／字体／分页、完整死亡 handler 与原完整 AI 仍有各自证据边界。

## Delivery boundary

第一战已跑通正常开场、战术操作、中途剧情、撤离胜利／失败与重开。地图死亡和经验收尾的 [历史图证](evidence_packets/runtime_observations/combat_aftermath/README.md) 不追溯覆盖新增金币／领取；后续 [奖励验收](evidence_packets/runtime_observations/battle_rewards/README.md) 独立记录真实领取、满包、延期、末敌胜利及两个进程的部分领取恢复。

后续验收必须说明默认路线还是设置过数据的夹具；测试绿只证明当前合同。新的原录像观察不追溯改变旧测试范围；最终手感和自主打法仍需实玩判断。本地提交与剩余改动以 Git 为准，默认不 push。

## Next steps

**收口冲刺已于 2026-09-20 收口**（`70f358f7`：快门 130 s／全门 288 s，工具 306 → 一个 `hsltools` 包、检查台账归零、规则套件进程内、BattleSceneRuntime／BattleOpeningCoordinator 抽成模块、unit schema 两侧校验、证据包机器可读头）；决策记录、度量与遗留见 [收口冲刺](CONSOLIDATION.md)（遗留在其 §10）。功能 lane 解冻：派活与回执用 [lane 任务书模板](templates/lane_brief.md)，合并前跑快门、阶段收口跑全门。**第二轮「第一章真实可玩」已于 2026-09-21 收口**（决策记录与回执见 [第二轮](PLAYABILITY.md) §5／§6）：无夹具的自动对局（`tests/support/Autoplay.gd`，深门套件）把 127 场注册战斗打到自然胜负——**dead_end 0、SCRIPT ERROR 0、四次全量逐字相同**（`HSL_RNG_SEED` 缝，结果 [`results.json`](../content/generated/hsl/development/autoplay/results.json) regen-and-compare）；explorer 回绿进 `--deep`（整章 22 s）；它抓出并修掉的真实缺陷：遭遇战 fail 段 `SID_雷歐納德` 未绑定（全灭后敌军无限行动）、阵亡结算模板只覆盖 15／66 演员（怪物死亡即无结果页）、绝技切入缺帧永不结束、台词头像缺失；新增重制显式规则 `party_wiped`（全灭判负）与「未上场 ≠ 阵亡」（provisional）。更聪明的驾驭器 `HSL_AUTOPLAY_BRAIN=scored` 是探索工具：主线 20 关 greedy 0／60 → scored 3／60（fresh 编队无魔法／绝技打不过脚本增援），**不据此声称主线可通**。59 个绝技的专属特效已按原 EFFECTS.TXT 脚本导入并由 `SkillEffectScriptPlayer` 播放（24／24 opcode，借用 氣刃斬 的行 0）。第三轮起步：原版存档编解码器与「跳到指定局面」的存档生成器（`hsl generate original_save:<preset>`，[原版存档格式](evidence_packets/static_reverse/original_save_format.md)）让原作对照不再依赖通关；有界原生探针 `check_player` 关掉了遭遇战判定的两条待证项。

**第四轮「续集就绪」已于 2026-09-23 收口**（[SEQUEL_READINESS](SEQUEL_READINESS.md) §6）：从零手写的 level 200＋新角色（蕾雅 102 新职业、龍炎斬／龍息，托蘭 103）只靠 `content/authored/` 数据跑通标题→开场→机器人打到胜利；派生 oracle 全部达成——unit schema required 只含规则键、逐关分支与 `FirstBattleScenarioRules` 已删、`JobStatsRules` 无逐职业分支、`game/` 代码内 `chapter01` 路径字面量 0（`engine:chapter_paths` 防回退，余 38 处为 provenance 证据引用）。作者入口见 [AUTHORING](AUTHORING.md)。

**先处理用户实玩的现行问题**（2026-09-23 列出；**第五轮已于 2026-09-24 收口**：12 条 lane 全部合并；**第六轮已于 2026-09-24 收口**：12 条 lane 合并——表现照原版录屏（P1–P4）、关卡可赢与剧本闸门（L8／L10／L11）、全简体（L9b／L9c）、章节机器人（L3c）、录屏对账工具（V2）、门禁偶发泄漏（T1），收口深门 VERIFY_PASS 680 s（`1581d363`）；登记与门禁见[协作入口](../PARALLEL_WORK.md)。下表已合并项待用户实玩验收——验收前不算"已修好"）：

| 顺序 | 玩家看到的问题与下一步验收 | 工作边界 |
| --- | --- | --- |
| 1 | 升级加点窗与选格人物面板：**已合并** `3d08165d`（R5-L1）＋`b4a643fd`（R5-L7）——任何己方成员升级都在 EXP／$／獲得物品窗／LEVEL UP 美术字之后（R6-P3 照原版顺序）、下一次行动交接前弹窗（敌方回合反击同样），按角色记录，状态页「成長點」对任何有点数成员可用；结束战斗那一击的升级在胜利对白／过场／结果页之前弹窗（09-26 GROWTHWIN 起照原版 0x43bbd3／0x438839：点数没分完时右键／Esc 不关窗，只有点满后的 OK 能关；旧存档暂缓的点数在首个安静时刻弹窗；失败不弹）；一次升多级一个窗给全部点数（用户定）；移动／攻击／魔法／绝技选格时光标下任何存活单位都显示身份栏。**剩余**：终局"结算前弹窗"按 [原升级窗时机](evidence_packets/static_reverse/original_growth_window.md) 静态读法，原版是否等窗关闭未实机核实（provisional）。 | 待用户实玩验收。 |
| 2 | 技能范围与音效：**已合并**——选格预览与结算共用 `SkillTargetRules.cast_footprint`（`3d08165d`，101 技能逐格一致，毒魔箭按[毒魔箭证据](evidence_packets/static_reverse/original_poison_arrow.md)画十字），结算脚印画成洋红填充＋白边、与施放范围分开（`b4a643fd`，用户定醒目样式，配色 remake-invented）；氣刃斬命中声与全部技能同类漏音由特效对象命令程序补回（`abde33fe`，310 个声音，[对象声音证据](evidence_packets/static_reverse/original_effect_object_sounds.md)）。**剩余**：9 个声音时刻为估计。 | 声音待用户带声实玩验收。 |
| 3 | 第 5／6 关：原版第 6 关入口**已合并** `4660d59b`（R5-L6：`tools/play_original.sh` 一条命令放入回憶錄第 1 行并可 `--restore` 还原，[PLAYTEST](PLAYTEST.md)「对照原版：第 6 关」）；第 5／6 关开局与原版逐项一致（[battle_006](evidence_packets/runtime_observations/battle_006/README.md)、[battle_005](evidence_packets/runtime_observations/battle_005/README.md)），机器人打不过是机器人缺口不是规则缺口。章节机器人**已合并** `445e8f7f`（R5-L3：直接冲目标、中值前瞻、每级 2 点體質）＋`b20d5d52`（R5-L3b：攻击位分配、药品经济、经验分配、模拟越过脚本触发）——播种章节走查越过第 5、6 关与遭遇战 509，新卡点第 7 关 寧靜之森（中途加入的必活 雪拉 独自施法被打死）。R6-L3c **已合并** `334d78a6`：lookahead 加致命格判定、结阵与必活单位护送，40 局 7→15 胜。**剩余**：第 7 关仍 0/13（敌人按入场成长到 77–105 HP，static-derived，非缺陷；第 5 回合援军刷在出发区）、memoir_05 仍 1/5；机器人线暂停，续做时允许机器人知道剧本援军位置；深门整章行走的 600 s 墙钟预算高负载下会提前耗尽，应改确定性预算；重制与原版难度对比待用户用 `tools/play_original.sh` 实玩。 | 不把机器人败局当关卡过难证据。 |
| 4 | 地图／剧情类：**已合并** `149e77de`（R5-L4）＋`262d312e`（R5-L4b）＋`30e878e4`（R5-L4c）——WRD 0x4000 进入通行／站位（房屋、柱子下不再可走）、约 100 个剧情物件回原像素、53 关绳索垂下展开且竖井封死、剧情走位按地形并行（第 6 关撤退 18.5 s → 2.7 s）、开场镜头按原版焦点；开场单位照原版留在源格（生成器不再挪动，88 名回位，第 5／6 关开场与原版读出逐格一致）；39 关第三次震动 89 格塌陷；单位与建筑按原版 32 px 行排序（[原版绘制顺序](evidence_packets/static_reverse/original_draw_order.md)，11／14 名被建筑遮挡的单位原版同样被挡，飞行单位深 10 行）；大地图演出盘点与原版城镇／大地图实录已入库。开场站在 0xff 格的 4 名地面单位（含 552 玩家可控的 咕嚕）原版同样只能沿崖移动、下不来（R5-L4c：静态＋原版移动函数实跑，重制读法一致，不改规则）；28 关打倒守门兵开对应门、80 关墙在事件首检打开（战中地形编辑）。R6-L8 **已合并** `f9d77892`（HPLow 门槛按原版 ≤1：41／59／75–79 可赢、30–37 首领剧情触发）＋R6-L10 **已合并** `6e9aec5c`（37 关宝石／守卫成真单位、打中 5 号宝石召出 052 即可赢；80 关 怨念體 回归、倒下后墙才开；修不死首领被魔法／特技击倒即死）。R6-L11 **已合并** `f4cf06e9`：剧本链中间的 `actCheckEventNotExist` 按原版作闸门（全 128 场只有 37／80 用到）——37 关 5 号宝石须最后打才删守卫、出 052，别的宝石最后打整组重来，随机槽按原版洗牌；80 关两个宝物都拿到才赢（下方宝物在 怨念體 倒下才开的墙后）；宝石与 怨念體 按原版加色绘制；30 关 克羅蒂 用 053 属性（127 → 271 HP），21／24／903 关敌方 克羅蒂 不再画成 018 魍魎劍士；跳过开场不再残留雕像；范围魔法按原版波及宝石（均 static-derived，洗牌随机流 remake-invented）。**剩余**：18 关城门未建成单位（缺证据；门下 (29,10) 墙缝重制可直接走过，原版门挡住三方移动、可被普攻打掉）；80 关 怨念體 原格压墙暂放 (25,9)；37 关按闸门要依次打 5 颗宝石，机器人探针未赢（机器人缺口，不是规则缺口）；绳索长度、61 名脚本走位终点挪格为 provisional。 | 已合并项待用户实玩验收。 |
| 5 | 界面整类：**已合并** `d061b8cb`（R5-L5）＋`084190a2`（R5-L5b）＋`de8a1ade`（R5-L6b）——气力条按原版 20／40／60 分段点亮（亮一格＝够放一次 expend-1 绝技）、菜单高亮按字形对齐、状态页等 7 个界面的文字／三条／装备图标／金钱框对齐、对白／城镇／装备说明换行不拆 378 个专名、按钮不再被撑高、默认静音；按原版实录（[标题饰物](evidence_packets/runtime_observations/original_title_ornaments/README.md)、[大地图与城镇](evidence_packets/runtime_observations/original_world_town/README.md)）标题宝珠／书只做竖直浮动、大地图底条减法压暗且黑色网格线保持可见、城镇构图照原版（重制多出的城名／金錢／同伴与「離開城鎮」放在原版留白处）；商店按原版獲得物品窗的商店分支重做（成员条、背包、货表、金钱框，右键／Esc 退店、根菜单右键／Esc 离城）。**剩余**：商店里买入直接入背包首空格、裝備／倉庫／丟棄暗置、保留「離開」按钮为重制选择（原版为光标持物手放、按钮行为未拍）；原版位图字体未导入（系统字，冒号位置差约 15 px，留给用户定）；抗性行已换原版元素宝石＋百分数（R6-P3），小字仍是系统字；重制多出的便利功能保留给用户日后判断。 | 已合并项待用户实玩验收。 |
| 6 | 阵亡演出：**已合并** `abde33fe`（R5-L2）＋`b4a643fd`（R5-L7）——按 [原版阵亡处置](evidence_packets/static_reverse/original_death_disposal.md)（static-derived）遗言后 16 tick 从脚底向上拉伸到 5 倍高并淡出，死亡音效在遗言之后、拉伸开始时响，所有死亡来源共用。R6-P1 **已合并** `07e11772`：遗言期间换 SHAPEDEF hit 跪姿（static-derived）、遗言按原版奇偶选句（随机源为确定性散列，remake-invented）、灵魂上移 37→47 px（原版录屏 47–56 px），原版录屏 15 处阵亡全部对上 `dead0003.wav`（[证据](evidence_packets/runtime_observations/dialogue_death/README.md)）。**剩余**：混合方式按叠加处理、未读实；灵魂时长保留静态 16 tick（录屏 0.27–0.32 s）。 | 待用户实玩验收。 |
| 7 | **2026-09-24 用户追加**（①已完成；②已完成；③待做）：①~~界面繁简混排~~——已修（R6-L9b，合并 `24c186c2`）：用户拍板**全简体**，与其原版一致。原版文本资源是 Big5 繁体，简体来自位图字库 FONT.24／FONT.15 在繁体码位画的简体字形（[证据](evidence_packets/static_reverse/original_font_script/README.md)）；重制在唯一显示接缝按原版字库逐字表显示简体，数据与存档保持繁体，通关制作名单重画为简体，`hsl check content:simplified_display` 拦截未审阅的繁体字。遗留：简繁切换低优先（只留接缝；繁体方向要重画约 80 张图，含 49 张金色书法关卡标题卡）；後於夥乾徵殭麼随原版字库保留繁体；鍾針魘暂用 OpenCC（provisional）；原版 職業 的显示与标题 logo 幻世錄 待原版核对。②~~`tools/play_original.sh --restore` 不处理原版退出时在 `SAVES/` 新写的 12 字节 `HSL.CFG`~~——已修：装入时一并记录 `HSL.CFG`（副本或"原本没有"标记），`--restore` 照原样放回或把新写的移进备份目录（`tools/test_hsl_play_original.py` 用假原版离线验证存档目录逐字节还原）。③进原版每趟常超 10 分钟上限（R5-L6 第 2 趟 17 分 40 秒、R5-L6b 第 1 趟约 11 分钟）：单步控制每步要"点击＋检查"两次调用，从标题读档走到第 6 关约 40 步、8–9 分钟。验收：①界面文字与原版字库一致，检查含消融；②玩完一次原版后 `--restore` 让 `SAVES/` 与进原版前逐字节相同；③从启动原版到第 6 关开战一趟 ≤3 分钟。 | 推荐做法（可换）：②安装预设时记下 `HSL.CFG` 的有无并备份，`--restore` 照原样还原或删除；③给常用对照点（第 6 关开战前、城镇选单）各存一个已走到位的原版存档，再给 `tools/hsl_original_control.py` 加"一次发一串操作、只在检查点截图"的批量路线。②③只改 `tools/`，②不开原版也能先做。 |
| 8 | **2026-09-24 录屏对账后的表现整类**（方法：先按像素／声音／资源三路量原版，模型描述只当标签）：R6-P1 **已合并** `07e11772`——说话人／目标／行动者统一高亮、对白板溶解开合与正文逐行擦出（战斗／剧情／城镇／谢幕共用）；R6-P2 **已合并** `2eb717c7`——镜头按原版逐 tick 滑动、五个面板滑入滑出、胜负条件面板真实显示、敌方移动前蓝色范围预告、切入白光在地图上放大（[证据](evidence_packets/runtime_observations/camera_panel_motion/README.md)）。R6-P4 **已合并** `c79af847`——标题左下 V1.06 与确认后停留淡黑、选目标与敌方预告用原版黄色 I_RECT01 格框、存档先問確定／取消再显示完成板、任務說明用胜负条件面板（[证据](evidence_packets/runtime_observations/menus_ui/README.md)）。R6-P3 **已合并** `15af0a3f`——特写守方照原版被击退 105 px、落空侧滑，所有切入共用一套站位；KILL（连杀时在阵亡者头上）／EXP／$／獲得物品／LEVEL UP 换原版美术字并按原版顺序，升级音随 LEVEL UP 响；身份栏抗性行换五颗元素宝石（[证据](evidence_packets/runtime_observations/closeup_floaters/README.md)）。**待用户决定**与**剩余**：并入第 9 行与差异清单（状态页存档／读档确认框、状态页左栏证据冲突、敌方移动预告两簇时长、声音侧除阵亡外未认出原版音效仍在清单里）。 | 已合并项待用户实玩验收。 |
| 9 | **2026-09-25 第七轮「照原版补齐演出与走位」**（用户实玩指出第一关走位、标题卡动画等与原版不同；负责人把代码头与证据包里所有"自己定的／暂定"汇总成[差异清单](evidence_packets/static_reverse/parity_gap_inventory.md)，此后按它报剩余条数：116 → 107，拆出新条目会让数上升）：已合并——章节标题卡（`589524ea`）、走路镜头跟随与原版光标（`37f2bbc8`）、第一关追击按原版 `0x4111a0`（`ddbcc532`）、镜头落点 (320,192)／结算前对准／速度滚动减速（`f862f57d`）、AI 起手覆盖层与镜头跟光标／特写中线 y 330（`0fac7893`）、面板压暗／翻页提示 ▼□／升级面板按钮（`f3a4b485`）、对白框位／19 字换行／4 行上卷（`b653db16`，框位可 `git revert f00f68f7`）、地图施法抬手／升级星光／地图伤害数字字形（`5187c7b8`）、原版 effProc 特效轨迹回放与施法残影（`716537d2`）、同速玩家先动／AI 攻击站位 `0x413390`／追击 80% 跳过（`d7bc17c4`，录屏第一战 1–3 回合 26 个原版 AI 行动全部可由重制产生）。暂停：位图字体（`paused/R7-FONT-bitmap-font`）、特写与法术数字（`paused/R7-DIGITS-all-numbers`）。**下一步待与用户确认**：用户要求按复刻品质影响排序（规则＞演出＞外观），首选第一关敌人走位逐格一致——静态读出原版 AI 随机数每次启动按时钟播种、不入存档（未运行验证），故目标改为同状态同随机数时每个敌人落点与目标一致、在同样的决策点按同样概率抽取、存读档语义一致（用户 09-25 同意）；剩整回合对照（模拟器试验中）与第 6 关两段式重调级。**待用户决定**：特殊技页照原版总先开技能页；去掉伤害附加词与「命中 99%」；胜负条件面板照原版等按键；确认对白框位置照原版；敌人起手范围沿用洋红还是换原版；对白页码「1 / 2」是否要回。登记与门禁见[协作入口](../PARALLEL_WORK.md)。 | 已合并项待用户实玩验收。 |
| 10 | **2026-09-25 第八轮「原版当裁判：随机流与规则对齐」**（负责人改由 Claude Code 会话担任，lane 为其子代理；派活与合并按 [lane 任务书模板](templates/lane_brief.md)，每条 lane 交回后另派独立怀疑者复核关键断言）。**已合并**（main `8f63f2e3`，深门 `VERIFY_PASS mode=deep seconds=944`）：第 6 关 opcode 73 两段式调级（LV6 `6972d617`，其余 137 战场开场逐字段不变）；特殊技取金封顶与击杀金钱读同一 live `+0x98`（GOLD `2c97b81f`）；重制敌人回合导出器 `tests/export_enemy_turns.gd`（TURNDUMP `b0f0bee3`，录屏 1–3 回合 26 个原版 AI 行动均有种子逐格复现）；敌方／NPC 击杀与取金所得记到自己身上、之后掉落与被偷上限按累计（GOLD2 `a20eacbf`）；阵亡占格原版在下一名行动前已清、重制一致不改（CORPSE `9994a9cd`）；**原版敌人回合裁判**——整个 hsl01.exe 在 unicorn 里逐帧跑原帧体，整回合含真攻击与伤害流逐次抽取，`hsl check enemy_turn` 离线校验、`hsl generate enemy_turn` 重生成（ORACLE `8e89c06a`；同速按注册槽稳定排序、NPC 开场调级抽全局流均为模拟器实测）；伤害／命中／暴击／状态／回复共用一条原版算法的伤害随机流并随存档（RNGB `8a7f50e4`）；同速 NPC 先后按原版注册槽——139 战场 4543 对同速 NPC 零不一致，新门禁 `registration_order`（SLOTORDER `13e4db8c`）。**目标定义（用户 09-25 定"按负责人推荐"）**：AI 一致性＝规则等价＋结果分布等价——敌人"找谁、打谁、站哪、何时放法术"的规矩与原版一样，随机选择只要求多种子下的比例一致，不追逐次抽取一致；原版裁判用来抓规则类差异。用户另立原则：他指出的"和原版不一样"是感觉与线索，不是规格——查清原版后照原版做（原版有 bug 除外），证据与其结论冲突时按证据。**09-26 进展**：AI 决策规则照原版已合并（AI-PRIO `442c0aa9` 批：持有目标槽序扫描／锁定／保留、0x40d8b0 逐槽换目标、0x413390 站位半格偏置、AI 地形射程、法术分支与 11% 侧移、L52 两名 069 装入）——裁判判为规则类的差异在 5 关 × 3 种子归零，随机类按 32 种子分布对照通过；128 关 × 3 种子批量对照（AI-PRIO 之前）规则类差异 370 行／68 关、79% 为持有目标，复跑中（BATCH2）以取剩余清单（预计剩站位／法术分支与目标／阵亡跳位／"重制无目标"）。交锋逐值对拍 1111/1111（DMGCHECK 修正敌方发起不回写命中加成 0x442405）。自动对局 128 场 win=17 fail=111 dead_end=0：敌方按原版集火、贪心驾驭器不躲，属原版难度非回归；整章 stuck_at=53（伤害串运气，CHAPTER53 判定）。用户拍板的四项界面照原版已合并（UI6）。测试政策与效率节拍（AGENTS.md）落地：测试净减约 2,540 行、套件 52→49／47→44、规则批次 214→127 s；verify 并发锁 2 槽、lane 定向验证、publish 预检、差异清单／来源对账降警告、回执 JSON 紧凑化、sweep 只按胜负判红。**09-26 续**：AI-PRIO 后复跑 128 关规则类差异 370→82 行（追击等距落点 32、持有目标残余 31、增益法术不施 13、505 关阵亡后本轮结束 3；AI-PRIO-2 在修）；交锋逐值对拍 1111/1111；玩家用药照原版（满值也能用且扣一件，目标＝自己＋相邻己方 pmPlayer 非 no_attack，ITEMRULES）；玩家出生 1014 次全库对照 1013 次一致（TINA53：第 53 关緹娜 L2 重制本就正确、重放漏推等级已修），唯一差异第 3 关漢克斯最大 HP 42→50（HANKS3：0x448840 只看刷新那刻的 pmPlayer 位，出生阵营 birth_player_mode）；规则代码整理 −345 行、来源头 −33%（RULESCUT）。**09-26 下午（用户实玩反馈跳队，全部照原版）**：敌人面板"？"在任何一方确认攻击目标时揭示、空名杂兵姓名印 ???（KNOWN）；光标画进 640×480 画面随窗口缩放（CURSOR）；特殊技页原版版面四块窗板对录屏偏移 0、付不起的行红字（SKILLPAGE）；撤离目标格只画原版 obj_Story_Show_Pos（ESCAPEMARK）；伤害／回复／MP／MISS 原版位图数字一个入口（DIGITS）；删自加结果页——胜利淡黑进下一段、败北 GAME OVER 回标题（RESULTPAGE）；069／022 切入与面板补齐、全库演员演出资源零缺口（CUTIN069）。规则：升级窗点满才能关（GROWTHWIN）；宝箱三问一致、新发现原版多数宝箱隐藏踏上才发现（TREASURE→HIDDENCHEST 排队）；行动队列五问一致（TURNQ）；AI 剩余差异回放判定只剩 3 处真差异（AI-PRIO-2）。掉落／NPC 出生携带／剧本随机位置三处照原版抽全局流 0x458c10、删自加 reward_rng 与 random_position_rng、opcode 107／108 不抽随机数、121 每对象三抽、全局流不入存档读档重掷（RNGC，72 个原版调用喂重制全对）。《参数与选项系统》设计页 docs/OPTIONS.md 三件用户 09-26 拍板按推荐（默认全部原版、开场气力先用裁判实测再定、预设「原版／舒适／自定」），版面网页预览已给用户（ignored/decisions/options_preview.html）；底座已合并（OPTIONS-B1：注册表 content/authored/options/remake_options.json、GameOptions 读点接口、GameSettings preset／presentation、設定選項窗下「重製選項 ›」二级页、HSL_OPTIONS_PRESET／HSL_DEBUG_PAUSE 开发缝、门禁多一份 comfort 冒烟）。宝箱隐藏照原版（HIDDENCHEST：隐藏由 OBS 模板 obj_Attribute 的 objattrATTACKFLAG 决定，全库 77 只箱隐藏 54／可见 23，踩上先放 sfxGetTreasure）并接成第一张选项卡 OPT-TREASURE（读点 BattleSceneRuntime reveal_all_chests）。换边单位普通切入整段镜像、剧本换阵营翻 side_swapped、battle JSON 快照多 1 归零（CUTMIRROR）。开场气力裁判实测（STAMINA-MEASURE：首次登记取 PLAYERS 列，只有雷歐納德 20／雷特 8，携带进关清 0，六段 actKeepPlayerST 连战保留余气）→ 不做成选项，STAMINA-RULE 照原版实现中。**走位一致三条的现状**：①同状态同随机数→同格同目标：规则类差异在 5 关归零（AI-PRIO），128 关剩余清单复跑中；②同决策点同概率：目标定义已改为"规则等价＋分布等价"（用户 09-25），随机类按 32 种子分布对照通过，不复刻抽取结构；③存读档语义：伤害流随存档、全局流不入存档，均已按原版（RNGB／RNG-A）。开场气力照原版已合并（STAMINA-RULE：首次登记取 PLAYERS 列、携带进关清 0、actKeepPlayerST 保留余气；胜负不变）；第二张选项卡 OPT-INFO 已接（OPTIONS-S2：头顶命中率／击数、敌人数值公开、飘字说明字；法术命中先亮血条查明是原版行为、两预设保留）；特殊技／魔法页缺口关掉（SKILLPAGE2：Wine 实拍四块板偏移 0、九行以上原版滚动条、列表按元素类型×码位、悬停名脉冲绿；只剩 FONT.24）；云漂移与移動背景视差照原版（CLOUDDRIFT：每 tick 按 obj_Data7 角度／obj_Data8 速度小数累加、逐轴回绕，移動背景随镜头 obj_Score/640・obj_HitPoint/480）；启动脚本 unset __CFBundleIdentifier（从 Ghostty 启动时游戏窗口被归到终端名下）。友军 AI 给残血玩家用回復藥照原版（ALLYHEAL，用户实玩反馈属实：装入角色整条复制模板含背包 0x44cb10，骑士 024 原本无药；落点 0x40d530→0x413390 四邻远侧优先）；任何画面 Tab 开关「重製選項」（OPTIONS-HOTKEY）；门禁改为按改动范围自动选 affected／fast（lane 不再跑快门）。**开局盘面全字段对拍**（OPENSNAP，玩家全部 127 场 × 2502 单位 × 103 字段 vs 原版首回合停点）：544 行差异全归因，已修三类自检 0；新发现并修掉实例物品被丢（玩家第 2 场 · 惡夢的終曲（LEVEL052）骑士原版两瓶药重制一瓶，find(0) 对浮点 0.0 恒 −1）；OPENFIX 修离网格向下取整／走位终点阻挡格原地站／歐姆村（LEVEL001）村民阵营字／死亡台词，差异 544→256 行、121→59 单位，胜负不变。剩余排队：门／船壳登记为演员 89 单位（巴瀚納海峽 LEVEL012／那可那魯邊境 LEVEL018／亞雷比斯 LEVEL026，需运行时分支）、大体型站阻挡格 6、古代神殿遺跡（LEVEL037）随机落点顺序（规则）、无武器元素字 0、057 st_x2、068 obj_Y1、LEVEL080 嚎终点。友军给残血玩家用药照原版（ALLYHEAL，玩家第 1／2 场骑士带药、四邻远侧落点）。界面文字换原版点阵字 FONT.24／FONT.15（FONT：1837 全角字＋半角，玩家可见字串 69,579 条缺字 0，技能页名字对 Wine 实拍偏移归零；系统字为 OPT-FONT 改良值）。AI 行动种类频率对拍（AIFREQ：118 关 × 3 回合 × 3 种子，唯一真缺口拉格納沼地（LEVEL032）毒气机关未实现→POISONGAS 在做；附带发现原版前 3 回合打死雷歐納德的关远多于重制：帕尼西亞城（LEVEL010）／菲納斯河畔（LEVEL516）／曼多力亞（LEVEL900）原版第 2 回合即败，LEVEL028 守卫打雷歐納德原版 3/3 重制 0/3 → LETHALITY 在查）。开源审计 docs/OPEN_SOURCE_PLAN.md（OSSAUDIT：推荐新仓库历史从零；Steam 版 hsl.exe 1.06 与锁定的 hsl01.exe 非同一构建；四件待用户拍板）。门／船壳照原版登记为演员（ACTORS100：巴瀚納海峽 LEVEL012／那可那魯邊境 LEVEL018／日沒灣 LEVEL026 甲板不再画门图、门可被攻击、船壳为敌方候选目标；大体型开局站阻挡格；对拍缺位 89→0）。Godot 导入固定开销砍掉（IMPORTSPEED：.gdignore docs/tools/contact_sheets、缓存自动播种、没变就跳过导入；新树首次 164→44 s、热启动 17→0.9 s）。拉格納沼地（LEVEL032）噴人沼氣照原版进规则层（POISONGAS：每 4 次行动结束喷一次、中心 5 级周围 3 级、REPLAY 43/43；演出 GASFX 在做）。「原版前 3 回合打死雷歐納德的关远多于重制」查明 10 关里 9 关是对拍口径（重制导出停在模板阵容未跑开场出生）＋3 样本抽样，修口径后分布对上（LETHALITY，产品规则不变）；唯一真分叉曼多力亞 · 對峙（LEVEL900）村民第 1 回合前被挪位→VILLAGER900 在查；LEVEL010 打人閃電与地形毒两处场景机关→SCENEMECH 在做。曼多力亞 · 對峙（LEVEL900）村民第 1 回合前挪位机制照原版（VILLAGER900：WINFAIL900 event 1 的 actWalk 由交接扫描启动、走位落格；无插入模板的关也装 walk_only_source，16 种子结束回合 r1 5/4 r2 11/12）。噴人沼氣演出（GASFX：镜头→3 团烟→中毒者左右抖 60 tick→停 90／40 tick）。帕尼西亞城（LEVEL010）打人閃電与深淵之沼（LEVEL015）地形毒进规则层（SCENEMECH：REPLAY 42/42、5/5；落雷演出 drop-lightning-presentation 待画）。选项卡再接三张（OPTIONS-S3：升級加點方式／敗北後重來／游標；八张卡已接六张，剩操作提示、演出节奏）。界面四处照原版（UIFIX：行动环魔法在特殊技前、标题版本号 137 墨迹点差 0、切入字幕 FONT.24 正文面 235 点差 0、退出时正在播的曲子释放）。新口径重跑 AI 频率与批量分类（AIFREQ2：127 关 11,067 对 11,056 行动无逐行显著差异，按关只剩法术进攻 34 vs 65；AI-PRIO-2 的 3 处真差异按行动者算已 0 处；规则类候选 76 行未回放；分类器入库 _batch_rules.py）。升级窗原版路径每升一级一个窗＋GAME OVER 逐 tick＋章末回标题（GROWTHWIN2）。落雷演出与光标演出期间隐藏／物品图标（FXQUEUE）。无窗口进程不读玩家存储预设、门禁 affected 推迟套件时自动改快门（负责人）。法术进攻两簇回放归随机结构、规则不改（AIMAGIC：041 风刃 16 种子 10 对 16 p=0.33，049 精神法术四关 25 对 33 p=0.36）——全库 AI 行动种类两边无可确证规则差异。选项卡八张全接（OPTIONS-S4：操作提示、演出节奏；默认原版预设下图标说明字／路径线与费用栏／撤离常驻金格／待机与再次行动提示／走位快进全部关闭，这是 OPTIONS §5 预告并经用户 09-26 同意的"默认原版关掉重制便利"）；「預備動作」查明是原版 設定選項 自己的起手动作开关（0x477c14 第 1 位），应照原版做成一行（排队 READYACTION）。回放判定工具落地（BATCH3：原版抽签喂给重制 AI，49 关 × 3 种子首轮回放，74 行规则类候选确证规则差异 0 行——AI 规则层到此收口，剩分布口径缺口 AISupportPlanning.choose/99 与 LEVEL037 队列顺序）。城镇与大地图 6 条（TOWNMAP：城镇根画面去城名／金钱条／离开钮、商店只 6 钮右键退、事件时序 teDelay N+1 tick、大地图路线揭示按原版逐 tick 正方形扩张、行走者原尺寸、揭示期间不接受点击；整理裝備原版是商店共用窗口另一模式，待做 M–L）。原版 設定選項「預備動作」照原版可用（READYACTION：0x401e74 读 0x477c14 第 1 位，关掉时法术／绝技起手横幅残影不出、停顿按 0x4030f7／0x403199 子状态保留，GameSettings.ready_action）。AI 与玩家用药演出照原版三段（ITEMFX：引导——光标停用药者 12 tick 滑到目标目标亮起 12 tick；效果——施法姿势、用药音、16 颗 WAT04／WAT01 星点或 NUM510 闪光；数字——脚下 HP／MP 小条与头上绿色数字；用户 09-27 反馈"看不清给谁吃药"属实）。合并流程：parity curation JSON 的 add-add 冲突改由 tools/merge_curation_json.py 三方并集自动解（今晚手工解了四次）。三个小尾巴照原版（SMALLTAILS：船壳共用一份记录 HP 并池、落雷用当前镜头 presentation_view、烟对象 defProcFireSmoke 停留／偏移／上飘／淡出 12 次抽取进规则层）。「整理裝備」照原版是商店共用窗口模式 0（PARTYEQUIP：系统卷轴第 1 项与剧情 57／81 同入口，9 钮版面对 Wine 实拍偏移 0，倉庫暗置）。地图演出三条照原版（STRIKEFX：地图普攻无效果对象——删挥击轨迹与红染、落空音即放；受击 0x407230 换 hit 帧并 60 tick 抖动；法术特效原点无 y 偏移、"高 14 px"是从脚底量的误读）。状态页与身份栏四条照原版（STATUSPAGE：状态页开页总是属性页——录屏里的道具列表是物品／交换窗、旧"证据冲突"解开；未交手单位不开页，重制附加物挂 OPT-INFO／GUIDE／GROWTH；身份栏狀態按位连单字「毒封痲弱攻防」或「正常」；气力条混合级 /16 叠画、红宽少 1 px）。开源四件用户 09-27 拍板（新仓库从零、规则数据公开、MIT＋CC BY 4.0、截图换重制画面）；OSS2 落地 LICENSE／LICENSE-docs／NOTICE／CONTRIBUTING／README 重写、个人路径清零、删 docs/external/typesafe、截图分类 650 处与 9 张样板；OSS1 落地 HSL_ORIGINAL_DIR／HSL_ORIGINAL_PAK、原版缺席 SKIP（1,347 任务）、派生物清单 19,317 条、可再生性实测 79.7% 逐字节（4 个读自己再改写的根文件是从空目录起步的最大障碍）、tools/oss_export.sh（1,883 文件 51.2 MB）。公开仓库 https://github.com/catoncat/hsl-remake 已建（私有，首次推送＝main 319a30ed 导出树 1,897 文件 54 MB，复扫零原版媒体零本机用户名；OSS3／WINPORT 落地复扫后切公开）。Windows／Linux 可移植（WINPORT：Steam 目录按平台探测、play.ps1／godot.ps1、doctor 移到 Python、.gitattributes 与 case_collisions、三平台 CI；Windows 未真机验证）。**在跑**：OSS3。排队：（4 个根文件拆手写底稿＋生成、PNG 清单改像素哈希、截图全量替换 104 处与三个 capture 脚本修复、原版表 17 个的导入变换）、状态页页按钮排、说明框悬停、其他窗口气力条脉动。排队：READYACTION、开源四件拍板、烟对象运动、船壳共用 HP、落雷镜头近似。**下一步**：其余选项卡（OPT-GUIDE／GROWTH／PACE／RETRY／CURSOR）、批量对照改回放判定为主（BATCH3）、排队演出小项（光标隐藏与物品图标、GAME OVER 细节）、FONT.24 位图字体导入。六项界面差异 09-25 已拍板全部照原版并合并（UI6）。 | 已合并项待用户实玩验收；旧战斗存档（v4）在新版本拒读。 |

以下 1–6 为其后的系统性候选；每项可独立认领与合并，来源链接指向证据包，历史回执见 [presentation 留言](collaboration/presentation.md)。

1. **技能侧边界**（第二轮已做：两次 EXP 换算分开、公式读衰弱后 live 值、AI 绝技通道支援／净化——均 static-derived；专属特效素材导入与 opcode 播放器——`skill_effects` 任务＋`SkillEffectScriptPlayer`，24／24 opcode，时序换算与几何 provisional，见 [表现合同](architecture/PRESENTATION.md)）——**剩余**：闇瑩蝶舞 SP08 原 PAK 仅 3 帧、obj_Special51_05 无定义（negative-evidence，D7）。（2026-09-23 K1 核实：绝技桶遍历与有用魔法桶恒接受早已由 `0ebe0f95`／`08a36c06` 关闭；治疗与增益绝技的切入文字已按原版只报非零变化；P7：功能绝技落地时只显示名字、未落地「閃避」、偷金飘「$」，同原版 0x404643 的 EXP 判定。）来源：[原技能功能位](evidence_packets/static_reverse/original_skill_function_bits.md)、[原直线范围](evidence_packets/static_reverse/original_line_ranges.md)、[原绝技元素抗性](evidence_packets/static_reverse/original_special_element.md)。
2. **转职收尾**（第二轮 R3 已做：上位行 010–020 脚步／攻击音表 `job_up_audio`、s_shape 三面板接入切入、过场与大地图按 carry 转职行绘制、37 目标改 017 且 HP/MP 保留、018 negative-evidence 注释）——**剩余**：大地图 walker 原 shape 未定位（标记跟随转职为重制表现）；转职目标行无条带时退基础行条带（原版该情形未知，provisional）；（2026-09-23 J1：004／006／007／009、053／054／055／057 的绝技条带已自原版导入，056 原版无条带＝negative-evidence；052 守护者走／攻／死音效已接）；兩棲族部落 第二次转职后菜单的原生观察（需 Wine 与用户键鼠，route 见 [原城镇转职](evidence_packets/static_reverse/original_town_job_up.md)）。来源：[原城镇转职](evidence_packets/static_reverse/original_town_job_up.md)、[成长生命周期](evidence_packets/static_reverse/original_growth_lifecycle.md)、[37 关 token 读法](evidence_packets/static_reverse/original_level37_tokens.md)。
3. **explorer 覆盖**（2026-09-23 X1：深门 explorer 走遍 22 个注册剧情场景、三个结局都到 GameClear，缺一即失败）——**剩余**：结局 77／78 的旗标靠注入（自然挣得需 73 关释放 席德爾 与 37 关敌方转职的选择分支夹具）；战斗 80、12／13／15、19／22／26／28／38／43 不在 explorer 路径上。
4. **视觉审核**：`sprite_facing` 是无消费者的元数据（运行时不读），审核已按消融关闭——等出现消费者时由 lane 用解码帧判定（审核表工具 `tools/hsl_sprite_facing_audit.py` 保留）；76／77／78／79／44／45 的回执包。
5. **正式扩关**：全部关卡共用同一 PlayLoop 与 `BattleOpeningCoordinator`；一关由预览转正式只改 `content/battles/campaign.json` 一行（预览场景 → `hsl generate level_battle:N` 组装）。其余第二章／终章战斗本体待接。
   - 所需 token 静态读法已备：[fixpos／fly／prev-insert](evidence_packets/static_reverse/original_fixpos_fly_prev_insert.md)、[getitem／deletepos](evidence_packets/static_reverse/original_getitem_deletepos.md)、[select-insert-event](evidence_packets/static_reverse/original_select_insert_event.md)、[use-item／no-attack](evidence_packets/static_reverse/original_use_item_no_attack.md)、[exec-mode／sys-arrive](evidence_packets/static_reverse/original_exec_mode_sys_arrive.md)、[回合显示](evidence_packets/static_reverse/original_round_display.md)、[整理装备窗口](evidence_packets/static_reverse/original_storage_window.md)、[随机位置](evidence_packets/static_reverse/original_random_position.md)、[站立型敌方精灵](evidence_packets/static_reverse/original_static_shape_enemy.md)、[原武器射程](evidence_packets/static_reverse/original_weapon_ranges.md)。
   - 来源模板：[主线角色来源](evidence_packets/static_reverse/original_campaign_actors.md)（`content/generated/hsl/actors/` 54 个）。
   - 已有独立来源与实际入口的机制链：[歐姆村](evidence_packets/static_reverse/original_ohm_village.md)、[地图绑定](evidence_packets/static_reverse/original_map_binding.md)、[戈爾山道两阶段战斗／事件入队](evidence_packets/runtime_observations/gol_road/README.md)、[正式1／2宝箱领取与跨场保留](evidence_packets/runtime_observations/treasure/README.md)。
6. **仍独立未接**：其余技能效果、高阶转职、原全局 dispatcher／RNG、完整地图 fallback、原对象调度顺序与跨关 handler。

不重做：闭合的成长／水剎／弓手／地图／緹娜入队及三箱事务；预览注册不代表战斗完成，其他预览宝箱仍只绘出；world／town 保持原负责范围。奖励切片的验收条件与回执已收敛到 [奖励验收](evidence_packets/runtime_observations/battle_rewards/README.md)，后续触及领取或存档时复用其 sequence/revision、原子交换、死亡去重和配置校验。

每个可见问题先明确"原录像证据 → 当前重制表现 → 所属模块 → 验收条件"；未知原版细节标 provisional 并注明替换证据，不把全部原作考证变成统一发布前置条件。已知显示边界留在对应证据包，不与上面的下一项功能争夺优先级。

## Validation

当前唯一完整非 GUI 门禁有三档：

```sh
tools/verify.sh          # 快门（默认）：热导入缓存、并行 Python 检查与 Godot 套件；合并前、lane 报告前都跑它
tools/verify.sh --full   # 全门：先删 .godot 与 *.import 证明冷克隆可导入，其余与快门相同；阶段收口与波末跑
tools/verify.sh --deep   # 深门：快门全部 ＋ verify_runner.py deep（全程剧情 explorer 约 1 分钟、127 场自动对局 sweep 约 12–16 分钟，regen-and-compare results.json）；阶段收口与波末跑
```

快门与全门运行**同一组**检查与套件——检查由 `tools/hsl.py` 注册表按仓库数据枚举（1,287 个原生任务全部在进程池里跑；历史命令台账只作 provenance，每条须恰好被一个任务 `replaces`，否则注册表加载即报错；`tools/hsl.py list` 看任务集，`hsl check level_battle:37` 只跑命中的一条）；Godot 套件由 `tools/verify_runner.py godot` 枚举 `tests/run_*.gd`：继承 `tests/support/TestSuite.gd` 的规则套件在**一个** Godot 进程里经 `tests/run_all.gd` 顺序运行，场景套件各自独立进程、独立 `HOME`（user:// 互不污染），注册场景 sweep 按 `HSL_SWEEP_LEVELS` 分 4 片并校验片并集覆盖全部注册战斗；sweep 与走查走 `--fixed-fps 60`（headless 每帧固定睡 6.9 ms 是原来慢的根因，快钟令 step 恒 1/60 并跳过帧睡眠；`HSL_TEST_FIXED_FPS=0` 回实时钟）。退出不删缓存，下一次定向测试或门禁直接热跑。

用户实玩验收走 [PLAYTEST](PLAYTEST.md)：`tools/playtest.sh N` 用独立存档直进验收关（难度卡点与手感清单），回报格式固定；任何画面按 P 停格、停格时 N 走一帧（调试用）。首次环境或工具问题先单独运行 doctor；verify 自带诊断。最后一次完整结果必须记录在提交说明或交付报告中；文档不长期硬编码测试数量。只读原录像时无需启动 Wine／Godot GUI，新视觉实现仍须实际截图／录屏验收。

效率约定：门禁按**切片批次**跑，回执记最后一个通过的提交号；同一 diff 与环境的通过结果可复用。多条线各用**隔离 HOME** 运行门禁与窗口化捕获；起重负载任务前先看 `uptime`，几条线同时跑门禁时用 `HSL_VERIFY_JOBS=3` 限制每条线的并行度（八条线各开八路曾把 load 压过 100）。实测数字见 [收口冲刺 §6](CONSOLIDATION.md#6-度量基线与目标)：串行旧门禁空载约 14 分钟、三条 lane 同时跑时约 45 分钟；现快门约 2 分钟、全门约 5 分钟（空载），Godot 段约 70 s，下界是规则套件分片中最重的一片（约 50 s）。

**验证分层**：`_run_registered_story_sweep` 对每个注册的 story 场景做启动→跑完→交接／卡片的回归扫描；`tests/run_story_mode_walkthrough_tests.gd` 以产品同一条路把第一章剧情模式从 歐姆村 走到 薛維斯港 上船（正式战斗强制胜利／预览→視為勝利→营地段→大地图→城镇事件→900 對峙選擇一→港口船长→命運神殿），证明地图／城镇／场景交接首尾相连而不证明任何战斗；深门覆盖的全程自动探索 `tests/run_story_mode_explorer_tests.gd`（与 sweep／章节走查并行）从 歐姆村 战后地图一路走到 GameClear（正式战斗强制胜利、预览取胜利行、57 取首条路线），即剧情模式已首尾贯通。
