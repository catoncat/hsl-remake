# 第一战验收盘点

2026-09-17导航接续：源目标持有／锁定、等待唤醒与守备半径进入相同PlayLoop；全图合法路径可以绕障碍、重新选择不可达或死亡目标，空格中心由玩家／AI／支援共用。正常时钟真实控件的续追、击败后重选、待机、MP／禁魔和四目标空格施法见[导航验收](evidence_packets/runtime_observations/ai_navigation/README.md)。默认胜敗／撤离与本批最终完整门禁分别记在该包及提交说明；不把合成位置、HP和授予说成正式关卡新增能力。

核对日期：2026-09-17。范围按项目 Mission：第一章第一战「弃卒」，不是第二关或全游戏系统。用户已允许保留原作特色并改善交互、节奏及规则，不再把逐像素/逐帧等价作为完成门槛。

## 当前验收入口

盗贼／翼战士及宿魔刀：[六职业来源中的88／92独立分支、四模板与末击削魔](evidence_packets/static_reverse/original_mobile_jobs.md)进入共同PlayLoop、永久／装备／临时层与成长／保存；目标MP减少不等于使用者回魔。`MobileJobsTrial.tscn`公开演练与[实际输入](evidence_packets/runtime_observations/mobile_jobs/README.md)覆盖两职业、攻法援物、AI重新报价、第二行动及三终态和跨战重开；第一战默认编队／授予不变。

攻防增益与退魔：[原规则](evidence_packets/static_reverse/original_stat_magic.md)与[16条实际控件](evidence_packets/runtime_observations/stat_magic/README.md)覆盖重复／到期／驱散、不同角色、当前装备与升级、移动资格、两次行动、AI重选、保存与三终态／重开。`StatMagicTrial.tscn`明确提供演练技能／资源；正式第一战默认能力保持源声明。

角色来源与祭司能力接续：[002祭司源绑定／独立job85](evidence_packets/static_reverse/original_priest.md)和[十一条实际输入](evidence_packets/runtime_observations/priest/README.md)已接入初始錫杖／治疗、成长、MP药及非Leonard主角。随后[月花圓舞](evidence_packets/static_reverse/original_moon_dance.md)恢复源初始自身范围绝技、逐目标五段、一次气力付款和最终经验；[十三条实玩](evidence_packets/runtime_observations/moon_dance/README.md)覆盖取消／移动、普通双击后接绝技、额外行动、AI重选、大型去重、状态回退及三终态／重开。两类开发演练与正式第一战授予分开，029仍保留开场演出身份，不作为祭司战斗模板。

武器尾部的[原效果／队列／EXP caller证据](evidence_packets/static_reverse/original_weapon_effects.md)已接入普通／反击末击，毒牙／針、鎮魂之斧和通用防护装备共用来源与换装事务；附毒不增发法术经验，取消未来槽不执行该角色本轮尾部。阶段回退、独立第二行动、AI驱毒／耗魔／禁魔／待机、三终态及重开的[十五条实玩](evidence_packets/runtime_observations/weapon_effects/README.md)明确了概率重试、失败进程和开发设置；正式第一／第二战没有新增授予。

大型角色的[原3×3命中／占格／完整flood与039来源](evidence_packets/static_reverse/original_large_actor.md)已接入共享空间合同；边缘攻法援物、空格区域去重、整块绕路与死亡释放、双击／再行动／状态／成长／存档及三终态由[十三条实际输入](evidence_packets/runtime_observations/large_actor/README.md)记录。海輝魔只在独立开发场景和明确夹具中出现；不更改原第一／第二战编队，不把旧“大型八方向扩展”措辞延续为斜向移动规则。

麻痺的[原新行动入口／计时／解除证据](evidence_packets/static_reverse/original_paralysis.md)已接入同一PlayLoop：地靈縛、多目标免疫／贡献、精靈石玩家／AI解围、防护装备和成长、跳过绕过额外行动、到期后正常恢复及终态冻结。具体[14条实际输入与图证](evidence_packets/runtime_observations/paralysis/README.md)区分显式授予夹具；正式首战未新增技能或道具，原完整dispatcher／wake／大型占地仍分别保留。用药反馈提前开放后继菜单的实玩回归已由共用busy门禁修正。

施法装备接续：[六件源装备](evidence_packets/static_reverse/original_casting_equipment.md)加入防护／主魔法命中和血衣转化，按同一职业、当前装备、末次行动与保存事务生效；满魔仍损生命、防护不清旧状态。血衣回魔后攻法援物、AI重新选择和三终态／重开有[十六条实际输入](evidence_packets/runtime_observations/casting_equipment/README.md)，默认第一战不增加这些装备。

三职业派生与资源装备：首／次战六模板按源mode、职业cap与当前装备统一初始化，补NPC遗漏的职业／装备抗性；手动成长和固定NPC策略独立。减耗、末次毒伤→HP→MP回复、白光之翼／双击联动、AI回魔后的新决策与保存／终态，由[职业与资源实际验收](evidence_packets/runtime_observations/role_resources/README.md)记录。法师／重装兵手动成长和装备授予是明确夹具，不是默认增加可控伙伴；原高位dispatcher其余分支仍未宣布完成。

白光之翼连续两次行动：首次行动收尾按当前装备授予独立第二行动，第二次重新读取资源／站位／目标，末次才毒伤与状态／队列交接；与普通追加一击分开。预览、换装、升级、第二段保存恢复和清敌／败北／撤离／重开的来源与失败范围见[额外行动验收](evidence_packets/runtime_observations/extra_action/README.md)。默认不赠送装备，原高位状态机其余分支不由此宣布完成。

角色通行接续：源单格地面／飞行／不阻挡与WRD高字节已进入同一玩家／AI路径；同侧可经过、占格不能停，预算截止在同伴格时退至之前合法格。选格显示实际路径和费用，移动后攻／法／援、换装与F5/F9后取消、清敌／败北／撤离及鼠标重开由[13条具名路线](evidence_packets/runtime_observations/actor_traversal/README.md)验证。真实败北暴露的AI播放标记遗留已修复，终态清理不再次结算。默认hold第7回合206.061秒撤离、advance第3回合78.799秒败北，两条正常时钟／鼠标重开通过；不把这些结果当统计平衡。源能力、原函数完整返回与玩家落点前段、夹具授予和大型体型边界见[原角色通行](evidence_packets/static_reverse/original_actor_traversal.md)。

追加攻击接续：極光之劍可通过原道具流程换装、预览与取消；普通及反击各自追加一击，死亡截断，逐击实际HP／暴击／声音、系列末气力和全交锋后的经验／领取／后继共同完成。依据和未支持被动见[原追加攻击](evidence_packets/static_reverse/original_extra_attack.md)，实际控件及胜利／败北／撤離、终态保存和重开见[本批验收](evidence_packets/runtime_observations/extra_attack/README.md)。额外攻击不复制法术、费用或回合，正式第一战不自动获得该装备。

装备移动接续：源基础加当前装备后统一刷新移動力，三件源装备的装卸、两个饰品叠加、升级保留、待移动取消／保存、AI可达性和清敌／败北／撤离均由[七条实际输入](evidence_packets/runtime_observations/equipment_mobility/README.md)验证。成长左栏改为完整可滚动预览，实际滚轮到移動力并确认。默认advance原数值路线第6回合167.446秒败北、鼠标重开通过；该默认路线不额外授予装备或能力，其他职业、原飞行通行及全局初始化仍保留。

普通交锋接续：原伤害、武器元素附加、暴击／反击概率和氣刃斬已进入共同事务；气力使用暴击前queued量，EXP／数字使用实际扣血。来源及边界见[原证据](evidence_packets/static_reverse/original_ordinary_special.md)，真实控件和默认整场结果见[普通／绝技验收](evidence_packets/runtime_observations/ordinary_special/README.md)。本批保留已收口的友军移动援助；不由新数值通过宣称全局RNG或全部原表现恢复。

新增[风火／最终EXP](evidence_packets/runtime_observations/magic_experience/README.md)与[友军移动援助](evidence_packets/runtime_observations/ally_support/README.md)两批连续链：原贡献换算、等级差／连续数／装备、支援成长及终态保存已经接入；随后完成友军扫描／续查、独立施援位置和真实药品相邻援助。新包分别记录默认整场与显式授予技能／调整HP的实际控件夹具。单次默认战果不是长期难度统计，十条支援路线也不等于全部职业／原AI已经还原。

9 月 14 日新增 [已审查的原录像参考](evidence_packets/runtime_observations/original_gameplay_reference/README.md)，随后已完成 [对白／选择第一批修正](evidence_packets/runtime_observations/dialogue_selection/README.md)：魔擊力恢复 `%` 后缀，共用 BOARD02 对白与实际行数分页，新增同坐标选格／技能名和下缘目标的信息避让。既有“移除百分号更正确”的结论撤回。图证、实际输入、夹具设置与未恢复的原字体／信息公开条件均在新包记录。

2026-09-15 接续：[地图死亡与经验收尾](evidence_packets/runtime_observations/combat_aftermath/README.md) 已把整次交锋、来源遗言、地图淡出、EXP／升级提示和后继交接串联。普通／气刃斩／地图法术／致命反击及多个死者共用只读表现；定向回归覆盖末敌胜利和主角被反击致死。空命令菜单的类型错误随真实终态路径修复。遗言第一非零项、字体和时钟是明确重制选择，原完整死亡 handler 未因此恢复。

金币／掉落／领取与单战恢复已有独立 [奖励验收](evidence_packets/runtime_observations/battle_rewards/README.md)：实际击杀后领取、满包交换／取消／放弃／延期、末敌胜利；两个独立进程保存及恢复部分领取状态，不重发余额、EXP或物品。来源与明确重制资格见 [奖励合同](evidence_packets/static_reverse/battle_reward_inputs.md)。完整門禁与默认路线结果见对应提交说明，不将夹具冒称自然获取重要物品。本页按具体版本定位验收，不把历史截图、过时速度和旧规则当当前合同；当前代码细节与测试入口见 [ARCHITECTURE](ARCHITECTURE.md) 和 [测试路由](../tests/README.md)。

`0d5f7c1`（依赖研究提交 `19b387b`）仍是 9 月 12 日菜单／普通 action／鼠标浏览基线；[delivery-20260912.md](evidence_packets/runtime_observations/presentation_reference/delivery-20260912.md) 记录其完整门禁、正常时钟胜／败路线和鼠标重开。2026-09-13 的后续成长 slice 在此基础上把 Leonard 从旧三选项重制规则迁到五点／四属性 SwordMan cap 与派生刷新；规则证据见 [original_growth_refresh.md](evidence_packets/static_reverse/original_growth_refresh.md)，真实 Control 输入和截图见 [growth_refresh/README.md](evidence_packets/runtime_observations/growth_refresh/README.md)。完整背包／换装、其他职业成长、AI／队友等不能由这批成长验收推断已恢复。当前摘要与下一步统一看 [PROJECT](PROJECT.md#next-steps)。下方较早轮次的速度、构图与旧三选项记录按历史理解。

## 最新实玩反馈的处理

状态后续：中毒／禁魔显示、满血使用解毒草、取消不耗药、健康目标禁用及解毒后下一队友已由独立合成状态夹具验收，见 [status_effects](evidence_packets/runtime_observations/status_effects/README.md)。初始角色没有被添加异常；后续受支持状态施加另见 [status_application](evidence_packets/runtime_observations/status_application/README.md)，正常第一战没有新增施毒者。图证不代表全状态系统或原版状态演出已还原。

2026-09-13 给予后续：已以合成背包、真实 Control 鼠标完成连续给予两件、双方满包交换、预览取消及移动后取消给予再撤销移动。双方 code 守恒、八槽顺序、旧信号不重复提交和退出会话的一次行动结算均有定向回归；源证据与未证明资格／移动边界见 [original_give_exchange.md](evidence_packets/static_reverse/original_give_exchange.md)，图证见 [give_exchange](evidence_packets/runtime_observations/give_exchange/README.md)。没有修改正常开场库存，也不据此声称全药品效果或全角色控制已恢复。

公共交接后续：双可控角色夹具原先能复现 Wait/Use 跳过后继，现已修复。真实鼠标 Wait、Use、Give 完成后都能查看第二位角色的状态并选择其移动，队列只前进一格。普通攻击／特殊技耗尽在完整演出之后交接，玩家→玩家、玩家→AI 和队尾均有回归。见 [action_handoff](evidence_packets/runtime_observations/action_handoff/README.md)；这不是第一战默认增加了可控队友。

公共动作后续：`Move→Cancel→Move→Give→next ally`、`Drop→Attack→next ally`、未移动直接特殊技和Wait均已走真实Control／正常动画时钟；取消移动后立即显示原位置移动范围，攻击/落空/特殊技完成结束当前角色。新图证与夹具边界见 [action_state](evidence_packets/runtime_observations/action_state/README.md)；角色资格、全技能/状态公式仍不能由此宣称已恢复。

技能费用后续：共享MP/ST规则已从原getter/门槛及扣除caller恢复；真实Control验证19ST不可施放、20ST可施放、选敌取消保留资源、确认扣费一次且不跳过下一角色。原费用证据、半费低MP边界及图片归档限制见 [skill_resources回执](evidence_packets/runtime_observations/skill_resources/README.md)。后续 [原气力证据](evidence_packets/static_reverse/original_stamina.md)另行覆盖增长／60上限、装备加倍／停止与积气后实际释放；完整技能资格不由费用或气力验收包办。

技能目标后续：当前攻击类技能与法师AI共用源function和RANGE规则；真实Control验证两格十字排除斜角敌人、失败/取消不扣费、轴向目标成功后精确交接下一角色，见 [skill_targets](evidence_packets/runtime_observations/skill_targets/README.md)。未实现辅助/复合function及坏范围数据不会被执行成伤害；完整原状态/角色模式资格仍独立保留。

回复／驱毒后续：[support_magic](evidence_packets/runtime_observations/support_magic/README.md)记录八条实际输入链：自身／友军治疗、两种高级治疗、范围驱毒、AI自疗／自清毒及无MP用药退路。选取、取消、真实滚轮、一次扣费、光效上方逐目标文字及下位行动者交接均沿正式Runtime；可控但非当前行动的队友能只读查看状态。源能力登记不改正式第一战的拥有权，测试授予／HP／速度／概率在回执明确声明。18组原数值正常返回与24组应用前段见 [支持证据](evidence_packets/static_reverse/original_support_magic.md)；全局AI、原最终EXP和粒子／时钟不由此称作一致。

共同结算后续：玩家与AI使用同一纯技能结果和PlayLoop提交入口，按tracked初始技能声明拒绝不拥有的技能；现有伤害策略保留provisional。真实Control完成 `Move→Special→Cancel→Special→next ally`，资源/坐标/后继一致，图证见 [skill_resolution](evidence_packets/runtime_observations/skill_resolution/README.md)。新的PLAYERS原包字节复核未通过，不能由本次产品测试称为完整原拥有权证明。

2026-09-13 晚续接：免费丢弃已接入。内建屏 Control 鼠标验证了取消／确认、丢弃后移动、移动后再次丢弃、撤销移动不恢复已丢物、继续选择攻击；队列始终未交接。见 [discard_action/README.md](evidence_packets/runtime_observations/discard_action/README.md)。这是受控库存夹具的操作验收，未声称原完整给予／整理或自然通关。

2026-09-13 装备接续：八槽有序库存、满包给予拒绝、Leonard 受支持装备的原子交换与当前六槽刷新已接入。[equipment/README.md](evidence_packets/runtime_observations/equipment/README.md) 记录额外银剑夹具的鼠标预览／取消／确认、防具卸下／重新装备及满包拒绝。正常开场道具不变；状态页显示当前装备。原暂持流程、完整行动消耗和所有被动／其他职业不由此宣称一致。

用户在 9 月 11 日指出六项未通过体验验收的问题；下方历史验证只说明当时能运行，不代表用户已接受。当前修正与实际图证见 [`first_battle_feedback/README.md`](evidence_packets/runtime_observations/first_battle_feedback/README.md)。

现在：0.20 秒逐格移动；完整地图攻击预告；原尺寸单人攻击/受击分镜和底部状态栏；专用施放画面；原表地图法术及缺失特效阶段；致死显示延后和脚点深度排序；原版窗体的状态、成长页面；安全资源导入启动器。Leonard 成长已采用原五点预算、四基础属性、SwordMan cap 和 `0x448840` 派生刷新；暂存／跨级累积未用点数仍是重制交互选择，其他职业和转职未因此完成。原版精确时钟、随机粒子轨迹、部分混色和完整 UI handler 尚未声称一致。

## 历史验证（构图与时间参数以最新记录为准）

下表是各轮次已取得的验收摘要；其中“本轮”指原回执对应版本。完整当前能力以 PROJECT 为准，不能从旧表中的“未完成”撤销后来交付。

| 用户体验 | 当前证据 | 判断 |
| --- | --- | --- |
| 普通启动、七段对白、原版标题、首次行动 | 正式入口 `project.godot`；既有正常速度 continuity 记录；本轮正常速度完整路线再次经过七段对白 | 已验证连续交接 |
| 原版角色、地图、肖像和图标 | 活跃 manifest 与资源校验器；当前对白、标题、首次控制截图人工检查 | 已使用原版资源；菜单/排版为重制设计 |
| 移动、选敌、攻击、技能、道具、状态 | 正式 PlayLoop/Runtime；运行时回归覆盖取消、占格、射程、消耗、相邻用药和面板状态；主场景路线实际移动与攻击 | 已接通可玩操作 |
| 普通攻击与法术演出 | 图片朝向独立于 ANIMAL.k_action；反击保持站位，逐阶段演出与 SHP 锚点；实际渲染关键帧和一次性命中回归 | 原版资源 + 经画面核对的重制编排；非原版逐帧/混合模式等价 |
| 升级选择与确认 | 每级最多 5 点力量/反应/精神/体质；SwordMan cap/刷新、预览、增减、暂存、状态页重开；实际鼠标事件确认与规则/运行时回归 | Leonard 四维成长已接入原函数合同；原完整 EXP award、其他职业/转职及原 UI 暂存语义仍有边界 |
| 道具界面原版素材 | 原包 i_use / ICONBOX / ICONRECT；表格类别与图片哈希校验；实际鼠标事件给相邻友军用药 | 已接入共用药包类别与物品格；不是每件道具独立图片 |
| 中途剧情与胜负 | 本轮正常速度坚守路线第 9 回合撤离；冒进路线积攒气力并使用气刃斩后第 5 回合失败；原文收尾、结果页和鼠标重开通过 | 已验证两种结果；不把单次路线当统计平衡 |
| 音效 | 角色行走/攻击/落空/死亡、两类法术、气刃斩、确认/用药/Game Over/升级已绑定原版资源；实际混音采样及触发回归 | 已接通主要原版音效 |
| 背景音乐 | 原版 STORY051 act0 的 actPlayLevelMusic 查表得 19（[原版配乐](evidence_packets/static_reverse/original_music.md) §4）；曲目文件为 Steam 經典版原曲导入的 `content/imported/hsl/music/19.ogg`（`music_import` 校验） | 原版曲目 19，整首循环 |
| 自动验证可信度 | Godot 输出错误但返回 0 的情况会失败；完整门禁在导入前清理生成缓存；新全流程驱动对未接受的输入立即非零失败 | 不能仅凭退出 0 或末尾 PASS 判断成功 |

2026-09-05 反馈中的第一批规则/节奏修正和本轮升级交互、道具素材、演出编排均已接通，并完成正常速度两种结果与重开验证。当前是可交付试玩的第一战切片，不是声称用户已认可最终手感。配乐已换成原版曲目（[原版配乐](evidence_packets/static_reverse/original_music.md)），NPC 等级已改按原出生调级（2026-09-25，[触发条件](evidence_packets/static_reverse/original_auto_growth.md#开战调级的触发条件)），不再是固定一级。当前证明见 [`first_battle_polish/README.md`](evidence_packets/runtime_observations/first_battle_polish/README.md)。

未声称原版 AI、完整初始化随机序列、逐帧时间尺度或原曲 PCM 等价（配乐是原曲 WAV 的 Ogg Vorbis 有损编码）。第二关、全装备更换、转职及本战未出现的状态效果属于后续范围。现有路线证明能够游玩与重开，不证明长期难度统计或所有策略都已平衡。

成长点、属性与行动仍由 PlayLoop 持有，面板只有未提交草稿；演出复用既有 clip 时钟与 receipt。没有新增音频管理器、战斗阶段或第二份战斗状态。本地交付不包含推送或发布，提交状态以 Git 为准。

## 历史：试玩反馈第一批修正

开场气力照原版：第 51 关雷歐納德首次登记，取 PLAYERS 气力 20，第一回合就能放氣刃斬（原版裁判与 Wine 首控存档同为 20，[开场实测](evidence_packets/static_reverse/original_stamina.md#开场实测)），此前"开局不能直接使用特殊技"的重制选择已随原版实测取消。固定双方+5已被原攻击／受击增长helper替换，详见 [original_stamina](evidence_packets/static_reverse/original_stamina.md)；60上限和20×expend费用分别有独立原指令证据。当前伤害输入仍标注重制边界。

六个菜单图标改为等半径近似正六边形（上下 ±90、左右 ±78 / 上下 ±45），保留图标下方说明和屏幕边缘整体收纳。敌军剧情退场及传令兵往返改用城门格 `[8,6]`，脚点 `(272,208)`；它位于原地图门洞，接近源脚本 `(267,209)`，与玩家桥边撤离格 `[14,10]` 分离。用户确认的是城门终点；精确落格属于当前地图映射选择。

逐格行走由 0.18 秒调整为 0.30 秒；战斗表现时间以 0.4 倍推进，普通攻击约 2.2–2.4 秒，法术/气刃斩 3.75 秒。动作顺序与一次性命中/音效事件保留，战斗数值和回合速度没有随动画缩放。此为可读性调整，不声称原版精确时钟。

第一批记录中的定向验证：气力获取与技能门槛、移动中间帧与到达、菜单对称/屏幕边界、城门路径与离场名单、攻击与反击/法术命中只触发一次均通过。该轮正常启动与菜单还用原生 Computer Use 的真实按键检查；原作实玩未成功，不作为原版对照证据。本轮没有启动 Wine，新的渲染交互通过 Godot 输入事件测试。

## 历史：第二批修正与边界

这一节记录 9 月 8 日的历史第二批修正：当时升级从自动加属性改为每级 3 点生命／攻击／防御选择。该三选项规则已在 2026-09-13 被上方五点四维 SwordMan 实现替换；这里保留只是为了说明旧截图／旧平衡记录的来源，不能再当当前产品合同。

道具列表使用原版共用药包类别图及物品格；名称、数量、目标与治疗前后 HP 保持可读，较长列表可滚动。攻击图的朝向经原始图片检查，不再误读 k_action；反击不交换左右站位，技能飞行/受击/火花/收势衔接，原始锚点和加色消除错误黑底。攻击已结算但特写未入队的短窗口也拒绝新命令，避免抢过未呈现的交锋。

正常速度的完整路线证明剧情、气力积攒、技能、结果和重开仍通顺；升级与相邻用药使用独立可见场景夹具和鼠标事件验证，未伪装成在这两条路线中自然发生。规则层另外抽样 seeds 10–29 × 三种固定策略共 60 场：坚守撤离 20/20 胜，纯冒进不治疗 20/20 败，先治疗再推进 20/20 胜。使用默认属性与伤害，未据此盲调数值；纯规则策略与渲染路线的控制器不同，不能比较为同一回放。

**仍待用户试玩判断**：这一历史三选项版本当时的成长价值、出招观感、剧情/操作节奏，以及更多自主打法的难度。四维属性分配后来已按新证据替换；全随机序列、下一关、换装、其他职业成长或转职仍未完成，也没有证明跨所有随机种子与玩家策略的平衡。


## 历史：2026-09-11 后续反馈

后续SR-048已按[原风火和经验](evidence_packets/runtime_observations/magic_experience/README.md)替换简化伤害／EXP合同：新增原施法数值、短HP/MP条→伤害→最终EXP、支援入账与成长、连续数／经验装备和终态保存。下面历史21EXP等数字只描述旧版本，不覆盖当前原换算；新的多目标、击杀／非击杀、支援、禁魔／资源不足及恢复有独立回执。

用户认可改进但再次指出菜单动画、行动后布局、额外指示器、受伤音画和施法分段仍不一致。因此本轮建立可持续覆盖清单，而不是继续把零散素材加入当作完整还原。

已有原版悬停循环、移动后五菜单与普通非致死攻击的带音轨样本；重制版三种共享过程已接入离线 Movie Maker 参考片。菜单重排/完整源帧、移除额外环与血条、独立受伤预算/声音及施法者阶段已实现。覆盖、媒体校验和原版等价是三个不同结论；当前对齐清单没有任何 matched 项。

上一次锁屏造成的采样中断是历史记录，不是当前继续开发的阻塞。现改用源定义→原指令→离线表现验证→必要短视觉核对，详见 [原菜单函数执行对照](evidence_packets/static_reverse/native_presentation_helpers.md)。不能把所有录像是否齐全当作源代码实现的前置条件。

## 源规则与公共面板的验收来源

菜单已消费原 EXE 整数坐标表、obj-051 的循环/往返选择，以及实际执行过的展开 helper；不再靠等半径圆和固定 fps 猜全部行为。移动后五项重排、开合、悬停复位和命中区域使用同一模块。移动后普通非致死攻击的原版新证据显示直接交接；当前在完整演出后自动继续，不再留下错误的额外两按钮确认。

状态／物品／成长面板已整理为顶部身份栏、原版三种槽条和共享装备区；魔击力读取属性刷新结果而非命中率，当前已恢复百分号后缀，数值公式保持不变。道具具有四命令子菜单、列表、地图对象选择及逐级取消；使用／给予／丢弃／受支持换装由 PlayLoop 提交并拒绝取消后的旧回调。状态页装备仍只读，Item→Equip 负责换装请求；Leonard 四维成长及换装不能推成其他职业刷新、全装备被动或转职完成。

普通战场不再默认显示回合／目标调试文字，`--debug-hud` 才显示；选敌改用原版身份栏与简短准确命中率。menu/attack/magic/status/items/growth 六类离线参考通过真实渲染，其中物品／成长由真实 Control 输入完成，不能等同于自然通关。自然路线与完整门禁的最终结果以本次交付日志／提交说明为准。

原作完整施法时钟、受击 handler、死亡／战利品及其他全游戏变体仍分别保留证据边界。源码函数对照已经通过的部分不会因此倒退为“没实现”，也不会据此把全部视觉 case 标成 matched。

后续系统审计确认的原作五点预算／四基础属性已继续追到 cap loader 与 SwordMan 派生刷新，并于 2026-09-13 接入 Leonard；见 [机制审计](evidence_packets/static_reverse/original_mechanics_audit.md) 与 [成长刷新证据](evidence_packets/static_reverse/original_growth_refresh.md)。鼠标边缘触发也已接入共享镜头。八槽库存顺序／容量和受支持换装的后续证据见 [库存／装备恢复](evidence_packets/static_reverse/original_inventory_equipment.md)；原 UI 暂持、行动消耗、AI 与多伙伴能力仍有明确缺口。
