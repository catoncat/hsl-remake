# 原版数据字段覆盖：重制消费了哪些、漏了哪些

> evidence: resource-derived: 列、行数、单位数、出现次数; static-derived: 0x45dc5c OBS loader 与 0x407ec0 演员构造的字段读法、0x42bd50 EVEF 分支; negative-evidence: 命中／伤害公式无地形项; provisional: 阵营位覆盖的玩家可见后果 · status: record-only · functions: 0x407ec0, 0x409a60, 0x409be0, 0x42bd50, 0x43ea30, 0x442a90, 0x452197, 0x45dc5c · tools: hsltools/checks/field_coverage.py · updated: 2026-09-27

_本文件由 `hsl generate field_coverage` 逐字节生成；改 [`field_coverage.py`](../../../tools/hsltools/checks/field_coverage.py) 的 `FIELD_NOTES`／`SUSPECTS`，不要手改这里。机读版 [field_coverage.json](../../../content/generated/hsl/development/field_coverage.json)。_

## 1. 为什么

lane R16 发现重制一直没读关卡 .BIN 的逐单位实例字（wait_round／fixed_point／物品，535 单位），玩家实玩才发现"敌人分批下来"的节奏全没了。这类"整个概念没读"的缺口要系统地找：对原版每张表／每种记录，列出全部字段、原数据里有多少行／单位／出现次数不是默认值、重制在哪里消费（文件:函数，每条引用在生成时核对存在）或 UNCONSUMED。状态词表：`consumed` 进入规则或表现；`passthrough` 生成器复制进数据、无运行时读者；`recorded` 运行时记录不生效；`unconsumed` 没有任何重制代码读；`dead` 原数据从不非默认或原 loader 自己不读。

## 2. 总览

| 表 | 记录 | 字段 | consumed | passthrough | recorded | unconsumed | dead |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [players](#players) PLAYERS.TXT | \[character] rows | 102 | 88 | 0 | 0 | 6 | 8 |
| [item](#item) ITEM.TXT | \[item] rows | 72 | 66 | 0 | 0 | 1 | 5 |
| [magic](#magic) MAGIC.TXT | \[magic] rows | 14 | 13 | 0 | 0 | 1 | 0 |
| [special](#special) SPECIAL.TXT | \[special] rows | 13 | 13 | 0 | 0 | 0 | 0 |
| [range](#range) RANGE.TXT | \[range] rows | 3 | 3 | 0 | 0 | 0 | 0 |
| [shapedef](#shapedef) SHAPEDEF.TXT | \[define] rows | 14 | 14 | 0 | 0 | 0 | 0 |
| [evef_actor](#evef_actor) level .BIN EVEF 演员实例字 | defProcPlayer／defProcEnemy 记录 0x10..0x2C 与 0x50+4i | 26 | 20 | 0 | 0 | 0 | 6 |
| [evef_object](#evef_object) level .BIN EVEF 非演员记录 | EVEF 记录 × 对象过程 | 5 | 4 | 0 | 0 | 0 | 1 |
| [obj](#obj) OBJ-NNN.obs / global.obs \[Object] | \[Object] blocks | 40 | 17 | 11 | 0 | 3 | 9 |
| [wrd](#wrd) levelNNN.wrd 地形 | WORL header + width×height u32 cells | 9 | 6 | 3 | 0 | 0 | 0 |
| [actor_record](#actor_record) live actor record（0x1fc） | 201 × 0x1fc records (*0x4c1bc8) | 82 | 79 | 2 | 0 | 1 | 0 |
| [defines](#defines) EXTRAS.H / ANIMAL.H / TYPE.H #define groups | #define groups by prefix | 17 | 13 | 1 | 0 | 3 | 0 |
| [story](#story) STORY opcode（ACTION.H act*） | ACTION.H tokens | 139 | 52 | 0 | 22 | 0 | 65 |
| [winfail](#winfail) WINFAIL opcode | winfail tokens | 120 | 66 | 0 | 53 | 1 | 0 |
| [town_event](#town_event) TOWNDEF te opcode | te tokens | 46 | 44 | 0 | 0 | 0 | 2 |
| [animal](#animal) ANIMAL.H ani* opcode（演员程序 + 绝技特效脚本） | ani* opcodes | 36 | 33 | 0 | 0 | 0 | 3 |
| [effects](#effects) EFFECTS.TXT eff* opcode（法术特效） | \[effect] blocks | 4 | 4 | 0 | 0 | 0 | 0 |
| **合计** | 17 表 | 742 | 535 | 17 | 75 | 16 | 99 |

## 3. 嫌疑排序

按「原数据有非默认值的行／单位数 × 语义已知且影响玩法」排序；P1 = R16 同级的整概念缺口并给出复现关卡，P2 = 局部规则缺口，P3 = 表现或单点。R21 只审计；R21 排出的两条 P1（obj_X1／obj_HitPoint）已由 R22 接入并从本表移除。

| # | 优先级 | 表.字段 | 量 | 语义 | 玩家会看到什么 | 复现 |
| --- | --- | --- | --- | --- | --- | --- |

### 全部 unconsumed（按量排序）

| 表.字段 | 量 | 语义 |
| --- | --- | --- |
| `players.class` | rows_nondefault 66 | classHuman／classMonster…（+0x20 低字） |
| `obj.obj_X2` | rows 10 | 模板 +0x18（特效 WAV／ObjectMove 参数） |
| `magic.effect_caster` | rows_nondefault 8 | 施法者侧特效（8 行） |
| `players.sound_hit` | rows_nondefault 4 | 被击音效（4 行；记录 +0x10 lo 句柄） |
| `item.high_cost` | rows_nondefault 4；items_unsupported 4 | 高价（4 行非 0） |
| `players.sound_walkwater` | rows_nondefault 2 | 水中行走音效（2 行） |
| `players.sound_shoothit` | rows_nondefault 1 | 射击命中音效（1 行，+0x22） |
| `players.no_shadow` | rows_nondefault 1 | 不画影子（bit 0x100，1 行） |
| `players.no_showshape` | rows_nondefault 1 | 不显示形体（bit 0x20，1 行） |
| `obj.obj_Y1` | placed_actor_rows 1；rows 22 | 模板 +0x14；演员：≠0 → live +0x134（0x407ec0）；特效：WAV；ObjectMove：位移 |
| `obj.obj_Y2` | rows 1 | 模板 +0x1c |
| `winfail.actMEssage` | occurrences 1 | — |
| `actor_record.install_code` | — | +0x84 安装时对象码 |
| `defines.TYPE.H class*` | — | 种族／类别码 |
| `defines.TYPE.H objattr*` | — | obj_Attribute 旗 |
| `defines.TYPE.H other` | — | 其余 #define（gameBigMapLevel／gameTempResourceID／plane*…） |

## 4. 静态读法（本包新增，static-derived）

**OBS loader `load_obs_template 0x45dc5c`** 按字段名把 `[Object]` 写进对象模板：`obj_Mode`→+0x00、`obj_Plane`→+0x0c、`obj_X1`→+0x10、`obj_Y1`→+0x14、`obj_X2`→+0x18、`obj_Y2`→+0x1c、`obj_ZoomX`／`obj_ZoomY`→+0x20／+0x24、`obj_Data`→+0x28、`obj_ShapeSub`→+0x2c、`obj_Name`→+0x34、`obj_Process_Code`→+0x64、`obj_Collide_X1/Y1/X2/Y2`→+0x68..+0x74、`obj_Shape_Delay`→+0x7c（并复制到 +0x7e）、`obj_Attribute`→+0x80、`obj_Score`→+0x84、`obj_HitPoint`→+0x88、`obj_Data1..Data9`→+0x8c..+0xac；`obj_ReadShape` 与 `obj_Code` 由同一 loader 单独读。`obj_X`／`obj_Y`、无下划线的 `obj_CollideX1` 和小写 `obj_mode` 不在字段名表里——原版也丢弃。

**演员构造 `0x407ec0`**（模板 +0x64 过程 3 defProcPlayer／5 defProcEnemy）：`+0xa4`（obj_Data7）为 PLAYERS 编号，经 `0x44cb10` 复制模板到 live 记录后依次：`+0xac`（obj_Data9）≠0 → live `+0x28` 在 pmPlayer 0x10000 与 pmEnemy 0x20000 之间互换并 `+0xa0 |= 8`；`+0xa8`（obj_Data8）≠0 → live `+0x14` 死亡台词字（−1 写 0）；`+0x88`（obj_HitPoint）≠0 → live `+0x1b6`（HP 加值半字）`+=`；`+0x9c`（obj_Data5）≠0 → 高半字 `+0x9e` 非零写 live `+0x04` 名字 id，低半字写 live `+0x1c` 称号 id；`+0x10`（obj_X1）≠0 → live `+0x28` 阵营模式直接覆盖；`+0x14`（obj_Y1）≠0 → live `+0x134`；然后 `0x448840` refresh。每个用过的模板字随即清零（一次性安装参数）。R22 起 `payload_inspector.parse_text_metadata` 保留 `obj_X1`／`obj_HitPoint`，`hsltools/levels/battle.py:install_player_mode` 按同一顺序（PLAYERS mode → obj_Data9 互换 → obj_X1 覆盖）写单位 `player_mode`，`_apply_object_install` 把 obj_HitPoint 加进 growth source hit_point；R29 起 `install_title_name` 把 obj_Data5 解成单位 `title`／`display_name`、`install_dead_message` 把 obj_Data8 解成单位 `dead_message`；R31 起脚本 `actSetPlayerName`（opcode 89 → `0x451590`：`0x44fad0(code, serial)` 后 `[name]` 写 live +0x04、`[job name]` 写 +0x1c，0x4515d2／0x4515d9，static-derived）由 `script_title_name` 作最后写者——全库仅 STORY029 两处（023 #1／#2 → 梅爾／凱文，稱號 376 一般兵），WINFAIL 无用例（negative-evidence）；obj_Y1 仍未进数据链，obj_Score 只有 mapobjMoveBG 的视差比进数据链（CLOUDDRIFT）；obj_Attribute 只有宝箱模板进数据链（HIDDENCHEST：ATTACKFLAG 决定画不画）。

**死亡台词字 live `+0x14` 的三个写者与两个读者**（R29，static-derived）：PLAYERS `dead_message` 对由模板复制进来（高字＝第一 id、低字＝第二 id）；构造 `0x407ec0` 在 `0x407fd0..0x407fe7` 把 obj_Data8 原样覆盖（−1 写 0）；STORY／WINFAIL `actSetDeadMessage`（opcode 60，跳表 `0x4537f4[60]` → `0x452197`）经 `0x44fad0(code, serial)` 找到对象后写同一字 `msg1 << 16 | msg2`——三者后写者胜，脚本层在安装之后执行即覆盖对象层。死亡读者 `0x43ef91`（`0x43ea30` 演员状态机的死亡分支）与 `0x4434b2`（`0x442a90`）读法相同：字为 0 不说；first＝高半字、second＝低半字，任一半为 0 时复制另一半；`0x458c10() & 1` 非零取 second 否则 first；再以 `0x4072b0`（actMessage 的对白框）由死者本人说出。重制：单位 `dead_message` 即安装后的这个字（`hsltools/levels/battle.py:dead_message_ids`），BattleAftermath 取第一条（provisional：原版两半字随机；替换证据＝按 0x458c10 序列复现或 Wine 44 关观察 021 死时 2263／2264 的分布）；脚本层 actSetDeadMessage（R31）：STORY 开场的写入在装配时经开场 token/serial 绑定写单位字（`battle.py:apply_story_dead_messages`，351 处全部可解析——队员的 741／846／742／906… 与 29 关 023 的 1684／1686、19 关 041 的 1455），WINFAIL 的在运行时经 `WinfailActions.write_dead_message` 写单位字（同链插入的目标由 ScriptActorCreationRules 回放时写，6 关增援 隊長 969；文本由 BattleAftermath 用关卡 message texts 解析）；WinfailScenarioRules.dead_messages 的 fail 页记录形状不变。

**命中／伤害公式无地形项**：`0x409a60`（命中）只读攻守 dex、live hit_ratio、avoid_hit_ratio；`0x409be0`（伤害）只读攻防、str、武器属性三元组（core_logic.json）。地形对防御／回避的加成为 negative-evidence；WRD 高度只影响通行（高差 >2 阻地面、0xff 悬崖）。

**EVEF 非演员记录**：148 关全部 EVEF 记录中，只有 defProcEnemy（0x10／0x14 物品、0x50..0xb0 覆盖字）与 defProcTreasureBox（0x10..0x40）在 code／x／y 之外有非零字；defProcStandObject／PlayerInstall／Cursor／BattleBOSS／combined 记录只有位置。宝箱 28 关记录 33 有 13 个非零字，原 `0x42bd50` 宝箱分支只读八个（有界执行，original_treasure.md）。装备实例字 idx 18–23 在 148 关中 0 单位使用；gold idx 0 仅 53 关记录 17（R27 起 `BattleRewardRules.kill_gold` 按 `0x42bd50` 字 0 → live `+0x98` 的写法读它作击杀金钱与入场成长金钱输入；该实例值 100 与 023 模板同值，生成物无数值差）。

## 5. 逐表字段

### players

**PLAYERS.TXT** · 来源 `content/imported/hsl/global/tables/PLAYERS.TXT` · 记录 \[character] rows · 66 行

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/campaign_actors.py:build` | 非默认行 66；声明行 66 | 角色编号＝模板表索引（0x44b980） | — |
| `name` | consumed | `tools/hsltools/levels/actors.py:_resolve_name` | 非默认行 66；声明行 66 | RESOURCE 名字 id | — |
| `sound_dead` | consumed | `tools/hsltools/assets/actor_audio.py:build` | 非默认行 66；声明行 66 | 死亡音效 WAV | — |
| `sound_walk` | consumed | `tools/hsltools/assets/actor_audio.py:build` | 非默认行 64；声明行 64 | 行走音效 | — |
| `sound_attack` | consumed | `tools/hsltools/assets/actor_audio.py:build` | 非默认行 66；声明行 66 | 攻击音效 | — |
| `sound_miss` | consumed | `tools/hsltools/assets/actor_audio.py:build` | 非默认行 64；声明行 64 | 未命中音效 | — |
| `job` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 66；声明行 66 | 职业码 → 0x448840 数值分支 | — |
| `class` | unconsumed | UNCONSUMED | 非默认行 66；声明行 66 | classHuman／classMonster…（+0x20 低字） | 原 0x448840／AI 是否按 class 分支未追；重制不读 |
| `status` | dead | — | 非默认行 0；声明行 15 | PLAYERS 初始状态位（15 行全 0） | 原 live +0x24 由回合 tick 改写；数据全 0 |
| `mode` | consumed | `tools/hsltools/levels/battle.py:install_player_mode` | 非默认行 66；声明行 66 | pmPlayer／pmEnemy／pmNPCPlayer 阵营位 | 模板值经 OBJ obj_Data9 互换与 obj_X1 覆盖后写单位 player_mode（见 obj 表） |
| `str` | consumed | `game/sim/CoreCombatRules.gd:hit_chance` | 非默认行 66；声明行 66 | 力量（伤害 str 项） | — |
| `dex` | consumed | `game/sim/CoreCombatRules.gd:hit_chance` | 非默认行 66；声明行 66 | 敏捷（命中 dex 项） | — |
| `mind` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 66；声明行 66 | 精神 → 魔攻／抗性 | — |
| `con` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 66；声明行 66 | 体质 → HP | — |
| `attack_damagex2` | consumed | `game/sim/CoreCombatRules.gd:critical_impact` | 非默认行 12；声明行 12 | 暴击（双倍伤害）几率 | — |
| `hit_point` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 55；声明行 55 | HP 加值（+0x1b6 半字） | — |
| `defense` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 40；声明行 47 | 防御加值 | — |
| `picture` | consumed | `tools/hsltools/assets/portraits.py:build` | 非默认行 66；声明行 66 | 头像 SHP | — |
| `job_up_code` | consumed | `tools/hsltools/data/original_save.py:build` | 非默认行 11；声明行 18 | 转职目标对象码（存档生成／城镇转职） | — |
| `weapon_skill` | dead | — | 非默认行 0；声明行 2 | 2 行全 0，EXE 无 loader 字段 | — |
| `magic_skill` | dead | — | 非默认行 0；声明行 2 | 2 行全 0 | — |
| `exp` | consumed | `tools/hsltools/data/progression.py:build` | 非默认行 1；声明行 12 | 初始经验 | — |
| `kill_exp` | consumed | `game/sim/ExperienceRules.gd:from_contribution` | 非默认行 64；声明行 66 | 击杀经验 | — |
| `gold` | consumed | `game/sim/BattleRewardRules.gd:drops` | 非默认行 58；声明行 63 | 击杀金钱 | — |
| `level` | consumed | `tools/hsltools/data/role_profiles.py:build` | 非默认行 12；声明行 12 | 初始等级 | — |
| `stamina` | consumed | `game/sim/ActorInitializationRules.gd:prepare` | 非默认行 2；声明行 32 | 开场气力：首次登记／NPC 构造整条复制模板（0x44cb41／0x44cb88） | — |
| `weapon_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 49；声明行 49 | 武器槽 | — |
| `head_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 32；声明行 41 | 头部槽 | — |
| `armor_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 33；声明行 41 | 身体槽 | — |
| `foot_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 32；声明行 41 | 脚部槽 | — |
| `other1_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 11；声明行 25 | 饰品 1 | — |
| `other2_equip` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 4；声明行 23 | 饰品 2 | — |
| `resist_earth` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 43；声明行 45 | 地抗基值 | — |
| `resist_water` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 43；声明行 45 | 水抗基值 | — |
| `resist_air` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 43；声明行 45 | 风抗基值 | — |
| `resist_fire` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 39；声明行 45 | 火抗基值 | — |
| `resist_mind` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 39；声明行 45 | 心抗基值 | — |
| `move_point` | consumed | `game/sim/TacticalGridRules.gd:movement_reachability_envelope` | 非默认行 62；声明行 64 | 移动力 | — |
| `item1` | consumed | `tools/hsltools/data/consumables.py:build` | 非默认行 15；声明行 16 | 初始背包槽 1 | — |
| `item2` | consumed | `tools/hsltools/data/consumables.py:build` | 非默认行 6；声明行 12 | 初始背包槽 2 | — |
| `item3` | consumed | `tools/hsltools/data/consumables.py:build` | 非默认行 2；声明行 12 | 初始背包槽 3 | — |
| `item4` | consumed | `tools/hsltools/data/consumables.py:build` | 非默认行 1；声明行 12 | 初始背包槽 4 | — |
| `item5` | dead | — | 非默认行 0；声明行 12 | 初始背包槽 5（数据全 0） | — |
| `item6` | dead | — | 非默认行 0；声明行 12 | 初始背包槽 6（数据全 0） | — |
| `item7` | dead | — | 非默认行 0；声明行 12 | 初始背包槽 7（数据全 0） | — |
| `item8` | dead | — | 非默认行 0；声明行 12 | 初始背包槽 8（数据全 0） | — |
| `special_other` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 11；声明行 12 | 初始绝技位（其他系） | — |
| `special_fire` | dead | — | 非默认行 0；声明行 3 | 初始绝技位（火，全 0） | — |
| `special_water` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 1；声明行 4 | 初始绝技位（水） | — |
| `special_earth` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 4；声明行 6 | 初始绝技位（地） | — |
| `special_wind` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 1；声明行 4 | 初始绝技位（风） | — |
| `special_mind` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 3；声明行 6 | 初始绝技位（心） | — |
| `special_other2` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 3；声明行 6 | 初始绝技位（其他 2） | — |
| `magic_other` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 5；声明行 12 | 初始魔法位（其他） | — |
| `magic_fire` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 10；声明行 15 | 初始魔法位（火） | — |
| `magic_water` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 14；声明行 18 | 初始魔法位（水） | — |
| `magic_earth` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 14；声明行 19 | 初始魔法位（地） | — |
| `magic_wind` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 12；声明行 15 | 初始魔法位（风） | — |
| `magic_mind` | consumed | `tools/hsltools/data/skill_book.py:build` | 非默认行 11；声明行 17 | 初始魔法位（心） | — |
| `find_type` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 非默认行 47；声明行 47 | 目标选择策略 | — |
| `find_range` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 非默认行 47；声明行 47 | 搜索半径 | — |
| `ai_call_range` | consumed | `game/sim/AINavigationRules.gd:guard_allows` | 非默认行 47；声明行 47 | 呼援半径 | — |
| `ai_fixed` | consumed | `game/sim/AINavigationRules.gd:guard_allows` | 非默认行 0；声明行 47 | 守备半径（模板全 0；EVEF 字 15 写 8） | — |
| `ai_check_dying` | consumed | `game/sim/AIPriorityRules.gd:choose_check` | 非默认行 47；声明行 47 | 濒死自救概率 | — |
| `ai_check_hp` | consumed | `game/sim/AIPriorityRules.gd:choose_check` | 非默认行 42；声明行 47 | 低血阈值 | — |
| `ai_help_otherhp` | consumed | `game/sim/AISupportRules.gd:next_check` | 非默认行 23；声明行 24 | 援友治疗概率 | — |
| `ai_help_status` | consumed | `game/sim/AISupportRules.gd:next_check` | 非默认行 26；声明行 26 | 援友解状态概率 | — |
| `ai_help_attack` | consumed | `game/sim/AISupportRules.gd:next_check` | 非默认行 26；声明行 26 | 援友增益概率 | — |
| `ai_lock` | consumed | `game/sim/AINavigationRules.gd:acquire` | 非默认行 47；声明行 47 | 锁定目标概率 | — |
| `ai_att_special` | consumed | `game/sim/AIDecisionRules.gd:select_action` | 非默认行 18；声明行 28 | 用绝技概率 | — |
| `ai_att_magic` | consumed | `game/sim/AIDecisionRules.gd:select_action` | 非默认行 22；声明行 28 | 用魔法概率 | — |
| `ai_magic_multi_first` | consumed | `game/sim/AISkillPlanning.gd:prepare` | 非默认行 14；声明行 28 | 范围魔法优先 | — |
| `level_adjust_range` | consumed | `game/sim/ReinforcementGrowthRules.gd:prepare` | 非默认行 46；声明行 48 | 入场调级范围 | — |
| `level_adjust_disp_range` | consumed | `game/sim/ReinforcementGrowthRules.gd:prepare` | 非默认行 42；声明行 48 | 入场调级位移 | — |
| `avoid_hit_ratio` | consumed | `game/sim/CoreCombatRules.gd:hit_chance` | 非默认行 2；声明行 2 | 回避率（+0x19a） | — |
| `steal_ratio` | consumed | `game/sim/SpecialUtilityRules.gd:prepare` | 非默认行 2；声明行 2 | 偷窃加成字（+0x194；0x448840 → +0x196 工作字＝字或 12；0x40b5a8 偷物 rand(100)+1 < get_ratio+10+工作字） | R27 起 equipment.initial_physical_fields 写单位 combat_profile.base_steal_ratio／steal_ratio，ProgressionRules.refresh_growth_stats 重算，JobUpRules 按 0x434aa6 相加基字；2 行（004=30／013=20），其余 64 行走默认 12 |
| `find_flag` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 非默认行 21；声明行 22 | 目标筛选旗（AIF_*） | — |
| `speed` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 22；声明行 22 | 速度加值 → 行动序 | — |
| `attack_power` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 24；声明行 24 | 攻击加值 | — |
| `magic_attack_power` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 22；声明行 23 | 魔攻加值 | — |
| `move_fly` | consumed | `game/sim/ActorTraversalRules.gd:mode` | 非默认行 12；声明行 12 | 飞行（+0xa0 bit 0x1） | — |
| `attack_back` | consumed | `game/sim/CoreCombatRules.gd:attack_back_triggered` | 非默认行 2；声明行 2 | 反击率 | — |
| `sound_hit` | unconsumed | UNCONSUMED | 非默认行 4；声明行 4 | 被击音效（4 行；记录 +0x10 lo 句柄） | 演员音频导入只取 dead／walk／attack／miss |
| `dead_message` | consumed | `tools/hsltools/data/combat_aftermath.py:build` | 非默认行 12；声明行 12 | 死亡台词 id 对 | — |
| `no_poison` | consumed | `game/sim/StatusApplicationRules.gd:modifiers` | 非默认行 16；声明行 16 | 免毒（bit 0x40） | — |
| `magic_point` | consumed | `tools/hsltools/model/jobs.py:source_profile` | 非默认行 22；声明行 26 | MP 加值 | — |
| `size_type` | consumed | `game/sim/FootprintRules.gd:radius` | 非默认行 7；声明行 7 | 大型占地 | — |
| `double_attack` | consumed | `game/sim/CombatSequenceRules.gd:attack_count` | 非默认行 2；声明行 2 | 二连击（bit 0x200） | — |
| `st_x2` | consumed | `game/sim/StaminaRules.gd:effects` | 非默认行 2；声明行 2 | 气力双倍（bit 0x4000） | — |
| `job_show_name` | consumed | `tools/hsltools/data/combat_aftermath.py:build` | 非默认行 47；声明行 47 | 显示称号 id | — |
| `move_magic_use` | consumed | `game/sim/PositionCapabilityRules.gd:effects` | 非默认行 2；声明行 2 | 移动后可施法（bit 0x400） | — |
| `carry_item` | consumed | `game/sim/BattleRewardRules.gd:carry` | 非默认行 29；声明行 30 | 掉落表 id | — |
| `find_no_id` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 非默认行 6；声明行 6 | 排除目标 SID | — |
| `sound_walkwater` | unconsumed | UNCONSUMED | 非默认行 2；声明行 2 | 水中行走音效（2 行） | 重制无水面行走音 |
| `no_paralyze` | consumed | `game/sim/StatusApplicationRules.gd:modifiers` | 非默认行 9；声明行 9 | 免麻痹（bit 0x800） | — |
| `no_disablemagic` | consumed | `game/sim/StatusApplicationRules.gd:modifiers` | 非默认行 9；声明行 9 | 免封魔（bit 0x1000） | — |
| `sound_shoothit` | unconsumed | UNCONSUMED | 非默认行 1；声明行 1 | 射击命中音效（1 行，+0x22） | — |
| `no_weaken` | consumed | `game/sim/StatusApplicationRules.gd:modifiers` | 非默认行 6；声明行 6 | 免虚弱（bit 0x2000） | — |
| `no_attack` | consumed | `game/sim/AINavigationRules.gd:acquire` | 非默认行 3；声明行 3 | 不攻击（bit 0x2） | — |
| `no_shadow` | unconsumed | UNCONSUMED | 非默认行 1；声明行 1 | 不画影子（bit 0x100，1 行） | 表现层未读；玩家可见差异为一个角色多了影子 |
| `no_block` | consumed | `game/sim/ActorTraversalRules.gd:source` | 非默认行 1；声明行 1 | 不阻挡（bit 0x10） | — |
| `no_showshape` | unconsumed | UNCONSUMED | 非默认行 1；声明行 1 | 不显示形体（bit 0x20，1 行） | core_logic 记有位；表现层未读 |

### item

**ITEM.TXT** · 来源 `content/imported/hsl/global/tables/ITEM.TXT` · 记录 \[item] rows · 239 行

- items_unsupported = items whose equipment.py row lists the field in unsupported_fields (the generator's own coverage declaration).

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 239；声明行 239；unsupported 物品 0 | 物品编号 | — |
| `name` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 239；声明行 239；unsupported 物品 0 | RESOURCE 名字 id | — |
| `cost` | consumed | `game/world/WorldPartyRules.gd:buy` | 非默认行 221；声明行 221；unsupported 物品 0 | 售价（商店买卖） | — |
| `type` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 239；声明行 239；unsupported 物品 0 | 物品类型（itemType*） | — |
| `icon` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 239；声明行 239；unsupported 物品 0 | 图标 | — |
| `attack_range` | consumed | `tools/hsltools/data/attack_ranges.py:weapon_ranges` | 非默认行 92；声明行 92；unsupported 物品 1 | 武器射程码 | — |
| `attack_damage` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 222；声明行 223；unsupported 物品 0 | 武器伤害／防具防御／速度加值（按 type） | — |
| `get_ratio` | consumed | `game/sim/BattleRewardRules.gd:drops` | 非默认行 226；声明行 239；unsupported 物品 0 | 掉落／被偷概率 | — |
| `important` | consumed | `game/sim/InventoryRules.gd:discard_error` | 非默认行 5；声明行 6；unsupported 物品 0 | 重要物品不可丢 | — |
| `use_job` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 238；声明行 239；unsupported 物品 0 | 可装备职业 | — |
| `hit_ratio` | consumed | `game/sim/CoreCombatRules.gd:hit_chance` | 非默认行 92；声明行 92；unsupported 物品 0 | 武器命中 | — |
| `add_weapon_hit` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 5；声明行 6；unsupported 物品 0 | 命中加值 | — |
| `add_magic_hit` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 2；声明行 3；unsupported 物品 0 | 魔法命中加值 | — |
| `add_attack_power` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 17；声明行 18；unsupported 物品 0 | 攻击加值 | — |
| `add_magic_power` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 37；声明行 38；unsupported 物品 0 | 魔攻加值 | — |
| `add_mp` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 4；声明行 5；unsupported 物品 0 | MP 上限加值 | — |
| `add_hp` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 6；声明行 7；unsupported 物品 0 | HP 上限加值 | — |
| `add_move` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 5；声明行 6；unsupported 物品 0 | 移动力加值 | — |
| `add_speed` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 38；声明行 39；unsupported 物品 0 | 速度加值 | — |
| `add_defense` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 29；声明行 30；unsupported 物品 0 | 防御加值 | — |
| `add_attack_range` | consumed | `game/sim/PositionCapabilityRules.gd:effects` | 非默认行 2；声明行 3；unsupported 物品 0 | 射程 +1 | — |
| `mp_use_half` | consumed | `game/sim/SkillResourceRules.gd:amounts` | 非默认行 1；声明行 2；unsupported 物品 0 | MP 消耗减半 | — |
| `hp_damage_half` | dead | — | 非默认行 1；声明行 2；unsupported 物品 1 | 受伤减半（数据 1 行为 0） | — |
| `action_twice` | consumed | `game/sim/ExtraActionRules.gd:equipment` | 非默认行 5；声明行 6；unsupported 物品 0 | 再行动 | — |
| `exp_x2` | consumed | `game/sim/ExperienceRules.gd:multiplier` | 非默认行 1；声明行 2；unsupported 物品 0 | 经验双倍 | — |
| `gold_x2` | consumed | `game/sim/BattleRewardRules.gd:gold_multiplier` | 非默认行 1；声明行 2；unsupported 物品 0 | 金钱双倍（1 行 230；item 位 0x20 → +0x18c，0x442819 经 0x40e2d0 翻倍） | 曾误记 dead；REWARD 接入 |
| `st_x2` | consumed | `game/sim/StaminaRules.gd:effects` | 非默认行 1；声明行 2；unsupported 物品 0 | 气力双倍 | — |
| `keep_status_good` | consumed | `game/sim/StatusApplicationRules.gd:equipment_modifiers` | 非默认行 2；声明行 3；unsupported 物品 0 | 免所有异常 | — |
| `hp_auto_restore` | consumed | `game/sim/ResourceRecoveryRules.gd:effects` | 非默认行 2；声明行 3；unsupported 物品 0 | HP 自动回复 | — |
| `mp_auto_restore` | consumed | `game/sim/ResourceRecoveryRules.gd:effects` | 非默认行 3；声明行 4；unsupported 物品 0 | MP 自动回复 | — |
| `move_magic_use` | consumed | `game/sim/PositionCapabilityRules.gd:effects` | 非默认行 2；声明行 3；unsupported 物品 0 | 移动后可施法 | — |
| `no_special` | dead | — | 非默认行 0；声明行 1；unsupported 物品 0 | 禁绝技（数据 1 行为 0） | — |
| `no_magic` | dead | — | 非默认行 0；声明行 1；unsupported 物品 0 | 禁魔法（ITEM 数据 1 行为 0；同名状态另有来源） | — |
| `double_attack` | consumed | `game/sim/CombatSequenceRules.gd:attack_count` | 非默认行 3；声明行 4；unsupported 物品 0 | 二连击 | — |
| `attack_cancel` | consumed | `game/sim/WeaponEffectRules.gd:effects` | 非默认行 1；声明行 2；unsupported 物品 0 | 击中取消行动 | — |
| `attack_weaken` | consumed | `game/sim/WeaponEffectRules.gd:resolve` | 非默认行 1；声明行 2；unsupported 物品 0 | 击中衰弱（1 行 51；item+0xa0 位 0x20000，0x409310 分支 25% → 0x409240） | R21 曾误记 dead；R27 随 random_status_error 一并接入 |
| `attack_nomagic` | consumed | `game/sim/WeaponEffectRules.gd:resolve` | 非默认行 1；声明行 2；unsupported 物品 0 | 击中禁魔（1 行 66；位 0x80000 → 0x409210） | R21 曾误记 dead；R27 接入 |
| `random_status_error` | consumed | `game/sim/WeaponEffectRules.gd:resolve` | 非默认行 2；声明行 3；unsupported 物品 0 | 击中随机异常（2 行 71／209；位 0x40000，0x409310 以 rand(100)+1 选衰弱／禁魔／麻痺／中毒一位替换状态字，再各 25%） | R27 接入；71 朧月 仍因 range6CellShoot 不可装 |
| `attack_paralysis` | dead | — | 非默认行 0；声明行 1；unsupported 物品 0 | 击中麻痺（位 0x100000 → 0x409110；数据 1 行为 0，随机位可选中该分支） | WeaponEffectRules.resolve 已实现分支，无数据行 |
| `attack_poison` | consumed | `game/sim/WeaponEffectRules.gd:effects` | 非默认行 2；声明行 3；unsupported 物品 0 | 击中中毒 | — |
| `attack_decmp` | consumed | `game/sim/WeaponEffectRules.gd:effects` | 非默认行 1；声明行 2；unsupported 物品 0 | 击中削 MP | — |
| `avoid_poison` | consumed | `game/sim/StatusApplicationRules.gd:equipment_modifiers` | 非默认行 2；声明行 3；unsupported 物品 0 | 免毒 | — |
| `avoid_nomagic` | consumed | `game/sim/StatusApplicationRules.gd:equipment_modifiers` | 非默认行 1；声明行 2；unsupported 物品 0 | 免封魔 | — |
| `avoid_weaken` | consumed | `game/sim/StatusApplicationRules.gd:equipment_modifiers` | 非默认行 1；声明行 2；unsupported 物品 0 | 免衰弱（1 行 220；位 0x2000000，0x40e2f0 免疫查询） | R21 曾误记 dead；R27 随 equipment.py status_effect_flags 接入 |
| `avoid_paralysis` | consumed | `game/sim/StatusApplicationRules.gd:equipment_modifiers` | 非默认行 2；声明行 3；unsupported 物品 0 | 免麻痹 | — |
| `high_cost` | unconsumed | UNCONSUMED | 非默认行 4；声明行 5；unsupported 物品 4 | 高价（4 行非 0） | equipment.py unsupported_fields；原语义未追（疑商店卖价／不可卖） |
| `no_addst` | consumed | `game/sim/StaminaRules.gd:effects` | 非默认行 1；声明行 2；unsupported 物品 0 | 不加气力 | — |
| `hp_transfer_mp` | consumed | `game/sim/ResourceRecoveryRules.gd:transfer_values` | 非默认行 1；声明行 2；unsupported 物品 0 | HP 转 MP | — |
| `add_steal_ratio` | consumed | `game/sim/EquipmentRules.gd:effect_delta` | 非默认行 1；声明行 2；unsupported 物品 0 | 偷窃加成（1 行 131 隱忍黑衣 20；item+0x40，0x448420 加到 +0x196 工作字） | equipment.py NUMERIC add_steal_ratio→effects.steal_ratio；131 因此 supported |
| `add_miss_hit` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 1；声明行 2；unsupported 物品 0 | 回避加值 | — |
| `add_attack_back` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 2；声明行 3；unsupported 物品 0 | 反击加值 | — |
| `add_weapon_dmgx2` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 5；声明行 6；unsupported 物品 0 | 暴击加值 | — |
| `magic_attack_type` | consumed | `tools/hsltools/data/equipment.py:weapon_magic` | 非默认行 17；声明行 17；unsupported 物品 0 | 武器属性伤害三元组 | — |
| `take_off` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 5；声明行 5；unsupported 物品 0 | 不可卸下 | — |
| `add_resist` | consumed | `tools/hsltools/data/equipment.py:build` | 非默认行 30；声明行 30；unsupported 物品 1 | 抗性加值（属性,值） | — |
| `add_defnese` | dead | — | 非默认行 1；声明行 1；unsupported 物品 1 | 拼写错误列（1 行；loader 无此字段名） | 原 PLAYERS/ITEM loader 按名字查字段，错拼即丢弃 |
| `cure_poison` | consumed | `game/sim/ItemUseRules.gd:prepare` | 非默认行 3；声明行 3；unsupported 物品 0 | 消耗品解毒 | — |
| `cure_no_magic` | consumed | `game/sim/ItemUseRules.gd:prepare` | 非默认行 3；声明行 3；unsupported 物品 0 | 消耗品解封魔 | — |
| `cure_paralysis` | consumed | `game/sim/ItemUseRules.gd:prepare` | 非默认行 3；声明行 3；unsupported 物品 0 | 消耗品解麻痹 | — |
| `cure_weaken` | consumed | `game/sim/ItemUseRules.gd:prepare` | 非默认行 3；声明行 3；unsupported 物品 0 | 消耗品解衰弱（3 行；loader 0x447fe2 → item+0xa0 位 0x10000000，0x40a31f 清 +0x38 与 flag 8 后 0x448840 刷新） | R27 起 249／251／252 登记为消耗品；ItemResolutionRules 在解除后刷新派生属性 |
| `add_st` | consumed | `tools/hsltools/data/consumables.py:build` | 非默认行 1；声明行 1；unsupported 物品 1 | 消耗品加气力 | — |
| `global_add_weapon_power` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久攻击 | — |
| `global_add_defense` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久防御 | — |
| `global_add_magic_power` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久魔攻 | — |
| `global_add_speed` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久速度 | — |
| `global_add_resist_earth` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久地抗 | — |
| `global_add_resist_fire` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久火抗 | — |
| `global_add_resist_water` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久水抗 | — |
| `global_add_resist_air` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久风抗 | — |
| `global_add_resist_mind` | consumed | `game/sim/PermanentCapabilityRules.gd:apply_sample` | 非默认行 1；声明行 1；unsupported 物品 1 | 永久心抗 | — |
| `local_add_weapon_power` | consumed | `game/sim/StatMagicRules.gd:prepare` | 非默认行 1；声明行 1；unsupported 物品 1 | 本战攻击增益 | — |
| `local_add_defense` | consumed | `game/sim/StatMagicRules.gd:prepare` | 非默认行 1；声明行 1；unsupported 物品 1 | 本战防御增益 | — |

### magic

**MAGIC.TXT** · 来源 `content/imported/hsl/global/tables/MAGIC.TXT` · 记录 \[magic] rows · 39 行

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/skill_coverage.py:build` | 非默认行 39；声明行 39 | 魔法编号 | — |
| `name` | consumed | `tools/hsltools/data/skill_coverage.py:build` | 非默认行 39；声明行 39 | 名字 id | — |
| `type` | consumed | `game/sim/SpecialDamageRules.gd:element_resistance` | 非默认行 39；声明行 39 | 属性 | — |
| `range` | consumed | `game/sim/SkillTargetRules.gd:candidate_centers` | 非默认行 39；声明行 39 | 施法范围 | — |
| `effect_range` | consumed | `game/sim/SkillTargetRules.gd:effect_cells` | 非默认行 39；声明行 39 | 效果范围 | — |
| `expend` | consumed | `game/sim/SkillResourceRules.gd:amounts` | 非默认行 39；声明行 39 | MP 消耗 | — |
| `damage` | consumed | `game/sim/NativeMagicRollRules.gd:roll` | 非默认行 39；声明行 39 | 伤害区间 | — |
| `hit_ratio` | consumed | `game/sim/NativeMagicRollRules.gd:roll` | 非默认行 39；声明行 39 | 命中 | — |
| `function` | consumed | `game/sim/SkillTargetRules.gd:function_mask` | 非默认行 39；声明行 39 | 功能位（magicFun_*） | — |
| `use_ratio` | consumed | `game/sim/AISkillPlanning.gd:choose` | 非默认行 39；声明行 39 | AI 使用概率 | — |
| `effect_proc` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 非默认行 39；声明行 39 | eff_proc_Local／Global（特效镜头模式） | Local 在每个受影响格播放、Global 在光标格中心播放一次（0x442b58／0x442d81） |
| `effect_code` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 非默认行 39；声明行 39 | EFFECTS 脚本编号 | 39 段 effCode 脚本经 special_effect_scripts.json 编成 tick 时间线；144 个效果对象中 131 个按原生 effProc* 轨迹（effect_motion.json）运动，13 个仍未复原 |
| `status_hit_ratio` | consumed | `game/sim/StatusApplicationRules.gd:prepare` | 非默认行 6；声明行 6 | 状态命中 | — |
| `effect_caster` | unconsumed | UNCONSUMED | 非默认行 8；声明行 8 | 施法者侧特效（8 行） | 表现层未读 |

### special

**SPECIAL.TXT** · 来源 `content/imported/hsl/global/tables/SPECIAL.TXT` · 记录 \[special] rows · 60 行

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/skill_coverage.py:build` | 非默认行 60；声明行 60 | 绝技编号 | — |
| `name` | consumed | `tools/hsltools/data/skill_coverage.py:build` | 非默认行 60；声明行 60 | 名字 id | — |
| `type` | consumed | `game/sim/SpecialDamageRules.gd:element_resistance` | 非默认行 60；声明行 60 | 属性 | — |
| `range` | consumed | `game/sim/SkillTargetRules.gd:candidate_centers` | 非默认行 60；声明行 60 | 施放范围 | — |
| `effect_range` | consumed | `game/sim/SkillTargetRules.gd:effect_cells` | 非默认行 60；声明行 60 | 效果范围 | — |
| `expend` | consumed | `game/sim/SkillResourceRules.gd:amounts` | 非默认行 60；声明行 60 | 气力消耗 | — |
| `damage` | consumed | `game/sim/SpecialDamageRules.gd:roll` | 非默认行 60；声明行 60 | 伤害区间 | — |
| `hit_ratio` | consumed | `game/sim/SpecialDamageRules.gd:roll` | 非默认行 60；声明行 60 | 命中 | — |
| `use_ratio` | consumed | `game/sim/AISkillPlanning.gd:choose` | 非默认行 60；声明行 60 | AI 使用概率 | — |
| `function` | consumed | `game/sim/SkillTargetRules.gd:function_mask` | 非默认行 60；声明行 60 | 功能位 | — |
| `attackpow_ratio` | consumed | `game/sim/SpecialDamageRules.gd:roll` | 非默认行 60；声明行 60 | 攻击力系数 | — |
| `attack_code` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 非默认行 60；声明行 60 | 攻方特效脚本（ANIMAL 程序） | — |
| `defense_code` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 非默认行 60；声明行 60 | 守方特效脚本 | — |

### range

**RANGE.TXT** · 来源 `content/imported/hsl/global/tables/RANGE.TXT` · 记录 \[range] rows · 24 行

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/attack_ranges.py:compile_ranges` | 非默认行 24；声明行 24 | 范围码 | — |
| `size` | consumed | `tools/hsltools/data/attack_ranges.py:compile_ranges` | 非默认行 24；声明行 24 | 方阵边长 | — |
| `data` | consumed | `tools/hsltools/data/attack_ranges.py:compile_ranges` | 非默认行 24；声明行 24 | 格值：>0 可达、≤0 不可（射击盲区为负） | 只取符号；值的大小（距离环）未消费，原 0x4100e0 用带符号值 |

### shapedef

**SHAPEDEF.TXT** · 来源 `content/imported/hsl/global/tables/SHAPEDEF.TXT` · 记录 \[define] rows · 66 行

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | SID | — |
| `hit` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 被击帧 SHP | — |
| `stand` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 站立帧 SHP | — |
| `stand_num` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 站立帧数 | — |
| `walk_up` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 上行帧 | — |
| `walk_up_num` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 上行帧数 | — |
| `walk_down` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 下行帧 | — |
| `walk_down_num` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 下行帧数 | — |
| `walk_left` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 左行帧 | — |
| `walk_left_num` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 左行帧数 | — |
| `walk_right` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 右行帧 | — |
| `walk_right_num` | consumed | `tools/hsltools/assets/combat_animation.py:build` | 非默认行 66；声明行 66 | 右行帧数 | — |
| `use_magic` | consumed | `tools/hsltools/assets/job_casts.py:build` | 非默认行 66；声明行 66 | 施法帧 | — |
| `use_magic_num` | consumed | `tools/hsltools/assets/job_casts.py:build` | 非默认行 66；声明行 66 | 施法帧数 | — |

### evef_actor

**level .BIN EVEF 演员实例字** · 来源 `content/generated/hsl/chapter01/battle*_seed.json placements\[].actor_instance` · 记录 defProcPlayer／defProcEnemy 记录 0x10..0x2C 与 0x50+4i

- status of idx 0..24 is tied to hsltools.data.evef_instances.RUNTIME_APPLIED; units/levels come from the tracked seeds.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `items` | consumed | `game/sim/ActorInitializationRules.gd:apply_instance_words` | 单位 20；关 11 | 0x10..0x2C 八个实例物品 → 空槽 | — |
| `gold` | consumed | `game/sim/BattleRewardRules.gd:kill_gold` | 单位 1；关 1；idx 0 | idx 0 → live +0x98 击杀金钱覆盖 | 1 单位（53 关记录 17，100，与 023 模板同值）；入场成长的金钱输入经 ReinforcementGrowthRules 同一读法 |
| `find_type` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 23；关 6；idx 1 | idx 1 | — |
| `find_flag` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 16；关 5；idx 2 | idx 2 | — |
| `find_range` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 4；关 2；idx 3 | idx 3 | — |
| `ai_call_range` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 4 | idx 4 | — |
| `ai_fixed` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 4；关 1；idx 5 | idx 5 | — |
| `ai_check_dying` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 6 | idx 6 | — |
| `ai_check_hp` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 7 | idx 7 | — |
| `ai_help_otherhp` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 8 | idx 8 | — |
| `ai_help_status` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 9 | idx 9 | — |
| `ai_help_attack` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 10 | idx 10 | — |
| `ai_lock` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 11 | idx 11 | — |
| `ai_att_special` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 12 | idx 12 | — |
| `ai_att_magic` | consumed | `game/sim/AINavigationRules.gd:instance_profile` | 单位 0；idx 13 | idx 13 | — |
| `wait_round` | consumed | `game/sim/AINavigationRules.gd:initialize` | 单位 535；关 66；idx 14 | idx 14 → ai_wait_remaining | — |
| `fixed_point` | consumed | `game/sim/AINavigationRules.gd:approach_home` | 单位 12；关 3；idx 15 | idx 15 → 守备锚点 | — |
| `level_adjust_range` | consumed | `game/sim/ReinforcementGrowthRules.gd:prepare` | 单位 13；关 4；idx 16 | idx 16（16 位） | 19／904 关 4 单位值 0x80000000 → 低字 0；原 16 位写同样得 0 |
| `level_adjust_disp_range` | consumed | `game/sim/ReinforcementGrowthRules.gd:prepare` | 单位 13；关 4；idx 17 | idx 17（16 位） | — |
| `weapon` | dead | — | 单位 0；idx 18 | idx 18 → +0xec（数据 0 单位） | — |
| `armor` | dead | — | 单位 0；idx 19 | idx 19 → +0xf0（数据 0 单位） | — |
| `head` | dead | — | 单位 0；idx 20 | idx 20 → +0xf4（数据 0 单位） | — |
| `foot` | dead | — | 单位 0；idx 21 | idx 21 → +0xf8（数据 0 单位） | — |
| `other1` | dead | — | 单位 0；idx 22 | idx 22 → +0xfc（数据 0 单位） | — |
| `other2` | dead | — | 单位 0；idx 23 | idx 23 → +0x100（数据 0 单位） | — |
| `stamina` | consumed | `game/sim/ActorInitializationRules.gd:apply_instance_words` | 单位 11；关 3；idx 24 | idx 24 → +0xe8 气力 | — |

### evef_object

**level .BIN EVEF 非演员记录** · 来源 `content/generated/hsl/chapter01/battle*_seed.json placements\[].records` · 记录 EVEF 记录 × 对象过程

- records per process: combined 67, defProcBattleBOSS 149, defProcCursor 149, defProcEnemy 1593, defProcPlayerInstall 1106, defProcStandObject 834, defProcTreasureBox 77
- Word census (which record offsets are non-zero per process) was measured once from the original level .BIN: only defProcEnemy (0x10/0x14 items, 0x50..0xb0 overrides) and defProcTreasureBox (0x10..0x40) carry words beyond code/x/y.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/levels/seed.py:_placements` | — | +0x04 对象码（OBJ 表 join） | — |
| `x` | consumed | `tools/hsltools/levels/seed.py:_placements` | — | +0x08 像素 x | — |
| `y` | consumed | `tools/hsltools/levels/seed.py:_placements` | — | +0x0c 像素 y | — |
| `treasure_words` | consumed | `game/sim/TreasureRules.gd:initialize` | 记录 77 | 宝箱 0x10..0x2C 八个物品字 | 28 关记录 33 有 13 个非零字（0x10..0x40）；原 0x42bd50 宝箱分支只读八个（static-derived, executed），尾部五个原版也丢 |
| `stand_object_words` | dead | — | 记录 2305 | defProcStandObject／PlayerInstall／Cursor／BattleBOSS／combined 记录 0x10 以后的字 | 148 关全部为 0——非演员 EVEF 记录只有 code／x／y |

### obj

**OBJ-NNN.obs / global.obs \[Object]** · 来源 `original hsl.pak @:\data\obj-NNN.obs (census) + battle seeds object_data_fields` · 记录 \[Object] blocks · 13419 行

- resource-derived census of 148 level obj-NNN.obs + global.obs read once from hsl.pak (13,419 [Object] blocks); the loader field list is static-derived from load_obs_template 0x45dc5c, the actor consumption from 0x407ec0. Re-measure with PYTHONPATH=tools python3 -m hsltools.checks.field_coverage --census (needs the original PAK).

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `obj_code` | consumed | `tools/hsltools/levels/seed.py:_object_lookup` | 行 13419 | 对象码 | — |
| `obj_name` | consumed | `tools/hsltools/levels/seed.py:_placements` | 行 13419 | 对象名（模板 +0x34） | — |
| `obj_Plane` | consumed | `tools/hsltools/levels/seed.py:_script_object_entry` | 行 13419 | 模板 +0x0c 图层 | — |
| `obj_Shape_Name` | consumed | `tools/hsltools/levels/seed.py:_placements` | 行 13419 | SHP 资源 | — |
| `obj_Shape_Number` | consumed | `tools/hsltools/levels/seed.py:_script_object_entry` | 行 13419 | 帧数 | — |
| `obj_Process_Code` | consumed | `tools/hsltools/levels/seed.py:_role_for_object` | 行 13419 | 模板 +0x64 过程码 | — |
| `obj_ReadShape` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 3800 | 预读形体旗（loader 单独读） | 进 object_data_fields，无运行时读者 |
| `obj_Shape_Delay` | consumed | `tools/hsltools/levels/seed.py:_script_object_entry` | 行 1245 | 模板 +0x7c 帧间隔 | — |
| `obj_Mode` | consumed | `tools/hsltools/levels/map_objects.py:build` | 行 251 | 模板 +0x00 显示模式（engADDCOLOR…） | — |
| `obj_mode` | dead | — | 行 1 | 小写拼写（1 行） | loader 按名字大小写匹配，原版亦丢 |
| `obj_X` | dead | — | 行 148 | 地图管理员 obj_X（148 行） | 0x45dc5c 不读 obj_X／obj_Y（只有 obj_X1..Y2） |
| `obj_Y` | dead | — | 行 148 | 地图管理员 obj_Y（148 行） | 同上 |
| `obj_X1` | consumed | `tools/hsltools/levels/battle.py:install_player_mode` | 行 99；已放置演员 102 | 模板 +0x10；演员：≠0 → live +0x28 阵营模式覆盖（pmNPC／pmPlayerEnemy／pmEnemy／pmPlayer）（0x407ec0）；特效对象：WAV | 102 个已放置敌军声明；81 个阵营与模板不同：pmNPC 39（7 关 21、21 关 13、57／531／532／533），pmPlayerEnemy 36（6 关 12、9 关 14、34 关 3、65 关 7 名村民），pmPlayer 6（900 关）；21 个 pmEnemy→pmEnemy 无变化。R22：导入器写单位 `player_mode`（放置与脚本插入同路），运行时 ActorRoleRules.side_mask 按位判敌我；特效对象的 WAV 值只随 object_data_fields 记录 |
| `obj_Y1` | unconsumed | UNCONSUMED | 行 22；已放置演员 1 | 模板 +0x14；演员：≠0 → live +0x134（0x407ec0）；特效：WAV；ObjectMove：位移 | 1 个演员（80 关 Enemy068 = obj_Story_Level_Enemy68Star）未消费；13 个法术效果对象的 WAV 由 special_effect_scripts.py:program_sounds 按 effProc 相位接入（R5-L2） |
| `obj_X2` | unconsumed | UNCONSUMED | 行 10 | 模板 +0x18（特效 WAV／ObjectMove 参数） | 10 行，均非演员；其中 7 个法术效果对象的 WAV 由 special_effect_scripts.py:program_sounds 接入（R5-L2），余为 ObjectMove 参数 |
| `obj_Y2` | unconsumed | UNCONSUMED | 行 1 | 模板 +0x1c | 1 行 |
| `obj_ZoomX` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 24 | 模板 +0x20 缩放 | 进 object_data_fields |
| `obj_ZoomY` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 24 | 模板 +0x24 缩放 | 进 object_data_fields |
| `obj_Data` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 44 | 模板 +0x28 通用字 | 进 object_data_fields |
| `obj_Data1` | dead | — | 行 0 | 模板 +0x8c（数据 0 行） | — |
| `obj_Data2` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 107 | 模板 +0x90（mapobjWaterMove 波幅等） | 进 object_data_fields |
| `obj_Data3` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 3580 | 模板 +0x94（mapobjMoveBGFlash level／DropRain delay…） | 进 object_data_fields |
| `obj_Data4` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 147 | 模板 +0x98 | 进 object_data_fields |
| `obj_Data5` | consumed | `tools/hsltools/levels/battle.py:install_title_name` | 行 317；已放置演员 12 | 模板 +0x9c；演员：低字 → live +0x1c 称号 id、高字 → +0x04 名字 id（0x407ec0） | R29：导入器写单位 `title`／`display_name`（display_name 为安装后 +0x04 逐字，portraits.panel_name，306 → ???），BattleVitals 状态面板读之；12 个已放置敌军（17 关 工人 062 1235×3、58／60／63 关 027 992×2、901 关 隊長 024 977×3）与 6／7 关脚本插入的 隊長 024 977；58／60／63 关未登记为战斗 |
| `obj_Data6` | consumed | `tools/hsltools/levels/story_scene.py:build` | 行 3967 | 模板 +0xa0；演员：SID 形体 token | S11：预览把 EVEF 演员绑到 token／序号（原 scenario.py:_story_cast 已随 52／53 并入通用路径删除） |
| `obj_Data7` | consumed | `tools/hsltools/levels/story_scene.py:build` | 行 958 | 模板 +0xa4；演员：PLAYERS 编号 → 0x44cb10 模板复制 | S11：预览的 actor_id；battle.py 按 templates() 取审核过的源模板 |
| `obj_Data8` | consumed | `tools/hsltools/levels/battle.py:install_dead_message` | 行 3077；已放置演员 129 | 模板 +0xa8；演员：→ live +0x14 死亡台词字（−1 清零；两 id 可打包高低字） | R29：导入器按死亡分支 0x43ef91／0x4434b2 的读法解字写单位 `dead_message`（−1 → 空表＝静默），BattleAftermath 死亡对白读之，PLAYERS.dead_message 只在单位无此字时用；129 个已放置敌军（18 关：6／17／24／29／32／34／44／53／77／79／531／532／552／554／575／900／901／903）。脚本层 actSetDeadMessage 写同一字、后写者胜：R31 起 STORY 开场的写入由装配器 `script_dead_message` 落进单位（29 关 023 #1／#2 的 −1→1684／1686、队员 741…），WINFAIL 的由 `WinfailActions.write_dead_message` 在运行时写单位（6 关增援 隊長 957→969，同链插入后由 ScriptActorCreationRules 按序回放） |
| `obj_Data9` | consumed | `tools/hsltools/levels/map_objects.py:build` | 行 7620；已放置演员 112 | 模板 +0xac；地图对象：mapobj* 类型；演员：≠0 时 pmPlayer↔pmEnemy 互换并置 +0xa0 bit 0x8（0x407ec0） | 演员分支 R22 由 battle.py:install_player_mode 读：112 个已放置敌军全是 pmPlayer 模板翻成 pmEnemy；脚本插入里有 pmEnemy→pmPlayer 方向（34 关 044、44 关 021 到场为友军）；bit 0x8 语义未追；R34：0x448840 的 hp_level 项按 live +0x28 P 位算——JobStatsRules.base_values 读 ActorRoleRules.side_mask（安装后的 player_mode，缺省按 role），互换成 pmEnemy 的 L1 023 = 28 HP（runtime-measured battle_053） |
| `obj_ShapeSub` | dead | — | 行 0 | 模板 +0x2c（数据 0 行） | — |
| `obj_Collide_X1` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 1096 | 模板 +0x68 碰撞框 | 进 object_data_fields；运行时 hit-test 用自己的 footprint |
| `obj_Collide_Y1` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 1096 | 模板 +0x6c | — |
| `obj_Collide_X2` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 1096 | 模板 +0x70 | — |
| `obj_Collide_Y2` | passthrough | `tools/hsltools/levels/seed.py:_placements` | 行 1096 | 模板 +0x74 | — |
| `obj_CollideX1` | dead | — | 行 5 | 无下划线拼写（5 行推車） | loader 字段名不匹配，原版亦丢 |
| `obj_CollideY1` | dead | — | 行 5 | 同上 | — |
| `obj_CollideX2` | dead | — | 行 5 | 同上 | — |
| `obj_CollideY2` | dead | — | 行 5 | 同上 | — |
| `obj_Attribute` | consumed | `tools/hsltools/data/treasures.py:chest_hidden` | 行 226 | 模板 +0x80 objattr* 旗（FLAG7／ATTACKFLAG）；宝箱：无 objattrATTACKFLAG 0x10000 → 0x415730 形状字 0xffff（隐藏宝物） | 226 行（176 地图对象、宝箱、特效）；只有宝箱模板保留（obj-028／obj-080 的 798 写 ATTACKFLAG＝可见，其余宝箱无此字段＝隐藏），生成器写 treasures `hidden`，BattleTreasurePresentation 不画隐藏箱；地图对象与特效的值导入器仍不保留（站立物件的固定图层语义见绘制顺序包） |
| `obj_Score` | consumed | `game/battle/runtime/MapObjectDrift.gd:add_background` | 行 55 | 模板 +0x84；地图对象 mapobj 参数（x range／level） | CLOUDDRIFT：mapobjMoveBG 的横向视差 x = x0 + trunc((镜头x − x0)·score/640)，−1 钉画面（0x43d4c1，original_map_object_drift.md）；导入器只对 mapobjMoveBG 保留；mapobjFlash 的 level 等其余用法仍不保留 |
| `obj_HitPoint` | consumed | `tools/hsltools/levels/battle.py:_apply_object_install` | 行 96；已放置演员 46 | 模板 +0x88；演员：≠0 → live +0x1b6 HP 加值半字 +=（0x407ec0，在 refresh 前）；地图对象：mapobj 参数（delay／y range） | 46 个已放置敌军：024 +50（25）、023 +20（18）、024 +30（3）。R22：加进单位 growth_profile.source.hit_point 与 max_hp／hp（`object_hit_point`），脚本插入的 024 隊長 +30／+50 同路；地图对象：mapobjMoveBG 的纵向视差 /480 由 MapObjectDrift.add_background 读（CLOUDDRIFT），其余 mapobj 的值不保留 |

### wrd

**levelNNN.wrd 地形** · 来源 `content/generated/hsl/static/hsl01/levelNNN_terrain.json` · 记录 WORL header + width×height u32 cells

- 83 tracked terrain packets, 85102 cells.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `magic` | consumed | `tools/hsltools/sources/wrd.py:decode_wrd` | — | "WORL" | — |
| `version` | passthrough | `tools/hsltools/sources/wrd.py:decode_wrd` | — | 版本（全部 3） | — |
| `flags` | passthrough | `tools/hsltools/sources/wrd.py:decode_wrd` | — | 头旗（全部 0） | — |
| `width` | consumed | `game/sim/WrdTerrainTiles.gd:load_tiles` | — | 格宽 | — |
| `height` | consumed | `game/sim/WrdTerrainTiles.gd:load_tiles` | — | 格高 | — |
| `element_size` | consumed | `tools/hsltools/sources/wrd.py:decode_wrd` | — | 4 | — |
| `t` | passthrough | `game/sim/WrdTerrainTiles.gd:load_tiles` | — | bits 0..23 tile id → tiles\[].tile_id | 无运行时读者；地图用整幅 SHP 绘制，tile 索引不用于绘制或规则 |
| `h` | consumed | `game/sim/ActorTraversalRules.gd:height_delta` | 非零格 43246；悬崖格 28169 | bits 24..31 源高度（0xff 悬崖；高差 >2 阻地面） | 值域 0..21／255；命中／伤害公式（0x409a60／0x409be0）无地形项 → 地形防御／回避加成 negative-evidence |
| `b` | consumed | `game/sim/WrdTerrainTiles.gd:load_tiles` | — | h==255 派生旗 | — |

### actor_record

**live actor record（0x1fc）** · 来源 `docs/evidence_packets/static_reverse/original_save_format.md + hsltools/data/original_save_members.py REC` · 记录 201 × 0x1fc records (*0x4c1bc8)

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `code` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x0 | +0x00 PLAYERS 编号 | — |
| `name_id` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x4 | +0x04 名字 id | — |
| `sound_walk_dead` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x8 | +0x08 WAV 句柄对 | — |
| `sound_miss_attack` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xc | +0x0c WAV 句柄对 | — |
| `sound_hit_walkwater` | passthrough | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x10 | +0x10 WAV 句柄对 | 生成器复制；运行时无被击／水行音 |
| `dead_message` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x14 | +0x14 死亡台词字 | — |
| `job` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x18 | +0x18 | — |
| `job_show_name` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1c | +0x1c | — |
| `class_shoothit` | passthrough | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x20 | +0x20 class 字／+0x22 射击命中 WAV | — |
| `mode` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x28 | +0x28 阵营模式 | — |
| `size_carry` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x2c | +0x2c size_type／carry_item | — |
| `str` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x4c | +0x4c 工作力量 | — |
| `dex` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x50 | +0x50 | — |
| `mind` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x54 | +0x54 | — |
| `con` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x58 | +0x58 | — |
| `face` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x5c | +0x5c 头像句柄 | — |
| `job_up_code` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x60 | +0x60 | — |
| `base_str` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x64 | +0x64 基础力量（成长写入） | — |
| `base_dex` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x68 | +0x68 | — |
| `base_mind` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x6c | +0x6c | — |
| `base_con` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x70 | +0x70 | — |
| `cap_str` | consumed | `tools/hsltools/model/jobs.py:calculate` | 偏移 0x74 | +0x74 属性上限 | — |
| `cap_dex` | consumed | `tools/hsltools/model/jobs.py:calculate` | 偏移 0x78 | +0x78 | — |
| `cap_mind` | consumed | `tools/hsltools/model/jobs.py:calculate` | 偏移 0x7c | +0x7c | — |
| `cap_con` | consumed | `tools/hsltools/model/jobs.py:calculate` | 偏移 0x80 | +0x80 | — |
| `install_code` | unconsumed | UNCONSUMED | 偏移 0x84 | +0x84 安装时对象码 | 运行时无对应键 |
| `exp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x88 | +0x88 | — |
| `exp_threshold` | consumed | `game/sim/ProgressionRules.gd:exp_to_next` | 偏移 0x8c | +0x8c 升级阈值 | — |
| `kill_exp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x90 | +0x90 | — |
| `gold` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x98 | +0x98 击杀金钱 | — |
| `level` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x9c | +0x9c | — |
| `capability_flags` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xa0 | +0xa0 能力位（move_fly／no_attack／…；bit 0x8 由 0x407ec0 阵营互换置位，语义未追） | — |
| `defense` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xb4 | +0xb4 工作防御 | — |
| `speed` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xb8 | +0xb8 | — |
| `hit_ratio` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xbc | +0xbc | — |
| `attack` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xc0 | +0xc0 | — |
| `weapon_magic_type` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xc4 | +0xc4 | — |
| `magic_attack` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xd0 | +0xd0 | — |
| `hp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xd8 | +0xd8 | — |
| `max_hp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xdc | +0xdc | — |
| `mp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xe0 | +0xe0 | — |
| `max_mp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xe4 | +0xe4 | — |
| `stamina` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xe8 | +0xe8 | — |
| `weapon` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xec | +0xec | — |
| `head` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xf0 | +0xf0 | — |
| `armor` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xf4 | +0xf4 | — |
| `foot` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xf8 | +0xf8 | — |
| `other1` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0xfc | +0xfc | — |
| `other2` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x100 | +0x100 | — |
| `resist_work` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x104 | +0x104 五个工作抗性 | — |
| `resist_base` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x118 | +0x118 五个基础抗性 | — |
| `move_work` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x12c | +0x12c | — |
| `move` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x130 | +0x130 | — |
| `job_up_flags` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x134 | +0x134 转职旗（0x407ec0 亦以 obj_Y1 覆写） | — |
| `items` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x138 | +0x138 八槽 | — |
| `special_words` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x158 | +0x158 七个绝技位字 | — |
| `magic_words` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x174 | +0x174 六个魔法位字 | — |
| `effect_flags` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x18c | +0x18c 装备效果位（0x448420） | — |
| `add_steal` | consumed | `game/sim/ProgressionRules.gd:refresh_growth_stats` | 偏移 0x194 | +0x194 偷窃加成字（→ +0x196 工作字，默认 12） | combat_profile.base_steal_ratio／steal_ratio；见 PLAYERS.steal_ratio |
| `add_avoid` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x198 | +0x198／+0x19a 回避 | — |
| `add_attack_back` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x19c | +0x19c／+0x19e 反击 | — |
| `add_damagex2` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1a0 | +0x1a0／+0x1a2 暴击 | — |
| `add_attack` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1a4 | +0x1a4 | — |
| `add_magic` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1a8 | +0x1a8 | — |
| `add_defense` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1ac | +0x1ac | — |
| `add_speed` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1b0 | +0x1b0 | — |
| `add_mp_hp` | consumed | `tools/hsltools/data/original_save_members.py:synthesize` | 偏移 0x1b4 | +0x1b4 MP／+0x1b6 HP 加值半字（obj_HitPoint 加在这里） | — |
| `wait_round` | consumed | `game/sim/AINavigationRules.gd:initialize` | 偏移 0x1b8 | +0x1b8 等待回合 | — |
| `find_type` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 偏移 0x1c0 | +0x1c0 | — |
| `find_flag` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 偏移 0x1c4 | +0x1c4 | — |
| `find_range` | consumed | `game/sim/AIDecisionRules.gd:select_target` | 偏移 0x1c8 | +0x1c8 | — |
| `ai_call_range` | consumed | `game/sim/AINavigationRules.gd:guard_allows` | 偏移 0x1cc | +0x1cc | — |
| `ai_fixed` | consumed | `game/sim/AINavigationRules.gd:guard_allows` | 偏移 0x1d0 | +0x1d0 | — |
| `ai_check_dying` | consumed | `game/sim/AIPriorityRules.gd:choose_check` | 偏移 0x1d4 | +0x1d4 | — |
| `ai_check_hp` | consumed | `game/sim/AIPriorityRules.gd:choose_check` | 偏移 0x1d8 | +0x1d8 | — |
| `ai_help_otherhp` | consumed | `game/sim/AISupportRules.gd:next_check` | 偏移 0x1dc | +0x1dc | — |
| `ai_help_status` | consumed | `game/sim/AISupportRules.gd:next_check` | 偏移 0x1e0 | +0x1e0 | — |
| `ai_help_attack` | consumed | `game/sim/AISupportRules.gd:next_check` | 偏移 0x1e4 | +0x1e4 | — |
| `ai_lock` | consumed | `game/sim/AINavigationRules.gd:acquire` | 偏移 0x1e8 | +0x1e8 | — |
| `ai_att_special` | consumed | `game/sim/AIDecisionRules.gd:select_action` | 偏移 0x1ec | +0x1ec | — |
| `ai_att_magic` | consumed | `game/sim/AIDecisionRules.gd:select_action` | 偏移 0x1f0 | +0x1f0 | — |
| `level_adjust` | consumed | `game/sim/ReinforcementGrowthRules.gd:prepare` | 偏移 0x1f8 | +0x1f8／+0x1fa 调级半字 | — |

### defines

**EXTRAS.H / ANIMAL.H / TYPE.H #define groups** · 来源 `content/imported/hsl/global/tables/{EXTRAS.H,ANIMAL.H,TYPE.H}` · 记录 #define groups by prefix

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `EXTRAS.H SID_*` | consumed | `tools/hsltools/levels/story_scene.py:build` | define 9 | 九名主角的 SID 形体编号 | — |
| `EXTRAS.H town_*` | consumed | `game/sim/TownEventRules.gd:_town_arg` | define 12 | 城镇编号符号 | — |
| `ANIMAL.H aniK*` | passthrough | `tools/hsltools/assets/animal_programs.py:build` | define 3 | 演员动作方向键（aniKStop／Right／Left） | 进 animal_programs.json k_action；运行时不读 |
| `ANIMAL.H ani* (opcodes)` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | define 36 | ANIMAL 程序 opcode 表（见 animal 表逐条） | — |
| `TYPE.H mapobj*` | consumed | `tools/hsltools/levels/map_objects.py:build` | define 15 | 地图对象类型 | — |
| `TYPE.H magic* (elements)` | consumed | `game/sim/SpecialDamageRules.gd:element_resistance` | define 19 | 属性与双属性组合 | — |
| `TYPE.H magicCode*` | consumed | `tools/hsltools/data/skill_coverage.py:build` | define 32 | 技能编号 | — |
| `TYPE.H magicFun_*` | consumed | `game/sim/SkillTargetRules.gd:function_mask` | define 20 | 功能位 | — |
| `TYPE.H pm*` | consumed | `game/sim/WinfailActions.gd:_player_mode_arg` | define 9 | 阵营模式常量 | — |
| `TYPE.H job*` | consumed | `tools/hsltools/model/jobs.py:source_profile` | define 23 | 职业码 | — |
| `TYPE.H class*` | unconsumed | UNCONSUMED | define 8 | 种族／类别码 | 见 PLAYERS.class |
| `TYPE.H AI_*／AIF_*` | consumed | `game/sim/AIDecisionRules.gd:select_target` | define 13 | find_type／find_flag 常量 | — |
| `TYPE.H itemType*／itemIcon*` | consumed | `tools/hsltools/data/equipment.py:build` | define 20 | 物品类型与图标 | — |
| `TYPE.H bm*／gameBM*` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_mode` | define 3 | 大地图点／线模式 | — |
| `TYPE.H eng*` | consumed | `tools/hsltools/levels/map_objects.py:build` | define 0 | 显示模式（engADDCOLOR…） | — |
| `TYPE.H objattr*` | unconsumed | UNCONSUMED | define 0 | obj_Attribute 旗 | 见 obj.obj_Attribute |
| `TYPE.H other` | unconsumed | UNCONSUMED | define 127 | 其余 #define（gameBigMapLevel／gameTempResourceID／plane*…） | 按需消费，未逐一登记 |

### story

**STORY opcode（ACTION.H act*）** · 来源 `content/generated/hsl/static/hsl01/story_token_coverage.json + game/battle/runtime/BattleOpeningCoordinator.gd` · 记录 ACTION.H tokens

- consumed = compiler kind handled by BattleOpeningCoordinator (or applied by the winfail interpreter in cutscene mode); recorded = RECORD_ONLY_KINDS; dead = no STORY script uses the token (the actCheck* conditions live in the winfail table).
- Some recorded kinds are pre-baked by level assembly instead of interpreted at runtime (actSetPlayerMode / actSetPlayerUndead → battle.py role_overrides, actSetPlayerName → battle.py apply_story_word_writes／script_title_name — opcode 89 handler 0x451590 writes [name] to live +0x04 and [job name] to +0x1c after 0x44fad0(code, serial): the corpus has two uses, STORY029 naming its 023 #1／#2 梅爾／凱文 under 一般兵, no WINFAIL use (negative-evidence); actSetPrevInsertObjectAdjustLevel → battle.py trace_opening bakes the range／disp-range pair into the unit field script_insert.adjust_level, born by InitialRosterGrowthRules → ReinforcementGrowthRules.prepare; the WINFAIL layer folds the same token into the runtime insert request); recorded here means the opening coordinator itself does not act on them.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `actAddOverScore` | dead | — | 关 0；出现 0；op 128 | game_over_score_add | — |
| `actAddTE` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 3；op 80 | town_event_add | — |
| `actAdjustAllPlayerLevel` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 73 | player_level_adjust_all | — |
| `actBMClearPointFlag` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 2；op 134 | bigmap_point_flag_clear | — |
| `actBMClearTrackFlag` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 4；出现 4；op 135 | bigmap_track_flag_clear | — |
| `actBMSetPointEncounterRatio` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 137 | bigmap_point_encounter_ratio | — |
| `actBMSetPointEvent` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 3；op 136 | bigmap_point_event | — |
| `actBMSetPointFlag` | dead | — | 关 0；出现 0；op 132 | bigmap_point_flag_set | — |
| `actBMSetPointMode` | dead | — | 关 0；出现 0；op 130 | bigmap_point_mode | — |
| `actBMSetShowTrackPoint` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 2；op 138 | bigmap_show_track_point | — |
| `actBMSetTrackFlag` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 2；op 133 | bigmap_track_flag_set | — |
| `actBMSetTrackMode` | dead | — | 关 0；出现 0；op 131 | bigmap_track_mode | — |
| `actChangePlayerID` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 2；op 90 | player_id_change | — |
| `actChangePosObjectProcCode` | dead | — | 关 0；出现 0；op 103 | position_object_proc_code_change | — |
| `actChangePrevInsertObjectID` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 4；op 32 | inserted_object_id_change | — |
| `actChangeShape` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_shape_change` | 关 1；出现 1；op 13 | actor_shape_change | — |
| `actChangeShapeWait` | dead | — | 关 0；出现 0；op 14 | actor_shape_change_wait | — |
| `actCheckAnyPlayerArrivePos` | dead | — | 关 0；出现 0；op 126 | \[x1]\[y1]\[x2]\[y2] | — |
| `actCheckEnemy` | dead | — | 关 0；出现 0；op 35 | \[num]\[id1]\[id2]\[...] | — |
| `actCheckEnemyNumber` | dead | — | 关 0；出现 0；op 36 | \[code]\[num] | — |
| `actCheckEnemyTotalNumber` | dead | — | 关 0；出现 0；op 37 | \[num] | — |
| `actCheckEventNotExist` | dead | — | 关 0；出现 0；op 114 | \[num]\[event1]\[event2]\[...] | — |
| `actCheckNextSerialNumber` | dead | — | 关 0；出现 0；op 100 | \[num] | — |
| `actCheckNotPlayerAttacker` | dead | — | 关 0；出现 0；op 116 | \[player id] | — |
| `actCheckPlayer` | dead | — | 关 0；出现 0；op 38 | \[num]\[id1]\[id2]\[...] | — |
| `actCheckPlayerArrivePos` | dead | — | 关 0；出现 0；op 41 | \[player code]\[serial]\[x1]\[y1]\[x2]\[y2] | — |
| `actCheckPlayerArriveSysPos` | dead | — | 关 0；出现 0；op 87 | \[player code]\[serial] | — |
| `actCheckPlayerAttacked` | dead | — | 关 0；出现 0；op 42 | \[attack player id]\[attacked player id] | — |
| `actCheckPlayerHPLow` | dead | — | 关 0；出现 0；op 65 | \[code]\[serial]\[ratio(%)] | — |
| `actCheckPlayerTotalNumber` | dead | — | 关 0；出现 0；op 39 | \[num] | — |
| `actCheckRoundDisp` | dead | — | 关 0；出现 0；op 94 | \[number] | — |
| `actCheckRoundNumber` | dead | — | 关 0；出现 0；op 40 | \[num] | — |
| `actCheckSerialPlayerAttacked` | dead | — | 关 0；出现 0；op 110 | \[attacked player id]\[serial] | — |
| `actDEMO` | dead | — | 关 0；出现 0；op 44 | demo | — |
| `actDarkScreen` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_screen_darken` | 关 1；出现 1；op 48 | screen_darken | — |
| `actDelay` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_opening_delay` | 关 152；出现 1481；op 1 | opening_delay | — |
| `actDeleteDarkScreen` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_screen_darken_clear` | 关 0；出现 0；op 49 | screen_darken_clear | — |
| `actDeleteEventStatus` | dead | — | 关 0；出现 0；op 27 | event_status_disable | — |
| `actDeleteFailStatus` | dead | — | 关 0；出现 0；op 26 | fail_status_disable | — |
| `actDeleteObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_delete` | 关 5；出现 5；op 16 | actor_delete | — |
| `actDeletePlayerCode` | dead | — | 关 0；出现 0；op 71 | player_code_delete | — |
| `actDeletePosObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_position_object_delete` | 关 4；出现 4；op 77 | position_object_delete | — |
| `actDeletePosPlayerXRange` | dead | — | 关 0；出现 0；op 104 | position_actor_delete_x_range | — |
| `actDeleteRandomPosObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_random_position_object_delete` | 关 1；出现 5；op 112 | random_position_object_delete | — |
| `actDeleteShowPosObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_show_position_marker_clear` | 关 7；出现 7；op 59 | show_position_marker_clear | — |
| `actDeleteTE` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 81 | town_event_delete | — |
| `actDeleteWinStatus` | dead | — | 关 0；出现 0；op 25 | win_status_disable | — |
| `actDetectRoundDispDisp` | dead | — | 关 0；出现 0；op 124 | round_disp_detect | — |
| `actEarthQuake` | dead | — | 关 0；出现 0；op 102 | earthquake | — |
| `actEnterStorageWindow` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_storage_window_enter` | 关 2；出现 2；op 139 | storage_window_enter | — |
| `actExecWinFailProcess` | dead | — | 关 0；出现 0；op 68 | winfail_process_exec | — |
| `actFALSE` | dead | — | 关 0；出现 0；op 113 | — | — |
| `actGetItem` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 85 | item_grant | — |
| `actInsertEventStatus` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_event_status_enable` | 关 50；出现 160；op 24 | event_status_enable | — |
| `actInsertFailStatus` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_fail_status_enable` | 关 128；出现 142；op 23 | fail_status_enable | — |
| `actInsertLevelUpStar` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_level_up_star_insert` | 关 0；出现 0；op 123 | level_up_star_insert | — |
| `actInsertObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_object_insert` | 关 7；出现 34；op 18 | object_insert | — |
| `actInsertObjectRandomPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_object_insert_random_position` | 关 1；出现 10；op 107 | object_insert_random_position | — |
| `actInsertRandomObject` | dead | — | 关 0；出现 0；op 121 | random_object_insert | — |
| `actInsertShowPosObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_show_position_marker` | 关 7；出现 40；op 58 | show_position_marker | — |
| `actInsertStoryObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_story_object_insert` | 关 11；出现 65；op 47 | story_object_insert | — |
| `actInsertStoryObjectRandomPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_story_object_insert_random_position` | 关 1；出现 5；op 108 | story_object_insert_random_position | — |
| `actInsertStoryObjectWait` | dead | — | 关 0；出现 0；op 78 | story_object_insert_wait | — |
| `actInsertStoryObjectWaitPos` | dead | — | 关 0；出现 0；op 99 | story_object_insert_wait_position | — |
| `actInsertStoryObjectXRange` | dead | — | 关 0；出现 0；op 105 | story_object_insert_x_range | — |
| `actInsertWinStatus` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_win_status_enable` | 关 97；出现 99；op 22 | win_status_enable | — |
| `actKeepPlayerST` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 2；出现 2；op 69 | player_stamina_keep | — |
| `actMessage` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_dialogue_message_id` | 关 74；出现 918；op 10 | dialogue_message_id | — |
| `actMessageIfExist` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_dialogue_message_if_exist` | 关 2；出现 2；op 11 | dialogue_message_if_exist | — |
| `actMove` | dead | — | 关 0；出现 0；op 52 | actor_move | — |
| `actMoveDisp` | dead | — | 关 0；出现 0；op 54 | actor_move_disp | — |
| `actMoveDispWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_move_disp_wait` | 关 1；出现 1；op 55 | actor_move_disp_wait | — |
| `actMoveWait` | dead | — | 关 0；出现 0；op 53 | actor_move_wait | — |
| `actOver` | dead | — | 关 0；出现 0；op 0 | script_over | — |
| `actPlayDefaultLevelMusic` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_music` | 关 78；出现 78；op 63 | default_level_music | — |
| `actPlayLevelMusic` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_music` | 关 50；出现 50；op 45 | opening_music | — |
| `actPlayMovie` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_movie_play` | 关 0；出现 0；op 120 | movie_play | — |
| `actPlayMusic` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_music` | 关 40；出现 40；op 46 | music_track | — |
| `actPlaySound` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_sound_effect` | 关 10；出现 21；op 15 | sound_effect | — |
| `actPlayerJobUpProcess` | dead | — | 关 0；出现 0；op 118 | player_job_up_process | — |
| `actRandomSetSysArrivePos` | dead | — | 关 0；出现 0；op 86 | system_arrive_position_random | — |
| `actReplaceEventStatus` | dead | — | 关 0；出现 0；op 30 | event_status_replace | — |
| `actReplaceFailStatus` | dead | — | 关 0；出现 0；op 29 | fail_status_replace | — |
| `actReplaceWinStatus` | dead | — | 关 0；出现 0；op 28 | win_status_replace | — |
| `actRestoreShape` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_shape_restore` | 关 1；出现 1；op 17 | actor_shape_restore | — |
| `actScrollBGToObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_object_target` | 关 11；出现 15；op 20 | camera_object_target | — |
| `actScrollBGToPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_position_target` | 关 28；出现 51；op 19 | camera_position_target | — |
| `actScrollBGToPosSpeed` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_position_target_speed` | 关 17；出现 19；op 75 | camera_position_target_speed | — |
| `actScrollBGToRandomPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_random_position_target` | 关 1；出现 5；op 111 | camera_random_position_target | — |
| `actSelectInsertEvent` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_event_select_insert` | 关 2；出现 2；op 79 | event_select_insert | — |
| `actSetBGToObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_object_target` | 关 5；出现 5；op 21 | background_object_target | — |
| `actSetBGToPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_camera_position_set` | 关 26；出现 26；op 97 | camera_position_set | — |
| `actSetBMWalkToPoint` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 95 | bigmap_walk_to_point | — |
| `actSetBMWalkerPlayerID` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 96 | bigmap_walker_player_id | — |
| `actSetDeadMessage` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_dead_message_registration` | 关 129；出现 381；op 60 | dead_message_registration | — |
| `actSetDoublePageMode` | dead | — | 关 0；出现 0；op 122 | double_page_mode | — |
| `actSetNextPlayLevelEvent` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_next_level_event` | 关 20；出现 20；op 43 | next_level_event | — |
| `actSetNextPlayLevelGetOverEvent` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 129 | next_level_get_over_event | — |
| `actSetOverFlag` | dead | — | 关 0；出现 0；op 127 | game_over_flag | — |
| `actSetPlayerExecMode` | dead | — | 关 0；出现 0；op 83 | player_exec_mode | — |
| `actSetPlayerFixPos` | dead | — | 关 0；出现 0；op 84 | player_fix_position | — |
| `actSetPlayerFly` | dead | — | 关 0；出现 0；op 92 | player_fly_flag | — |
| `actSetPlayerMode` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 66 | player_mode_set | — |
| `actSetPlayerName` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 2；op 89 | player_name_set | — |
| `actSetPlayerNoAttack` | dead | — | 关 0；出现 0；op 101 | player_no_attack_flag | — |
| `actSetPlayerPosToRandom0` | dead | — | 关 0；出现 0；op 117 | player_position_random0 | — |
| `actSetPlayerUndead` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 13；出现 22；op 64 | player_undead_flag | — |
| `actSetPlayerWalkShape` | dead | — | 关 0；出现 0；op 115 | player_walk_shape | — |
| `actSetPrevInsertObjectAdjustLevel` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 2；op 56 | inserted_object_adjust_level | — |
| `actSetPrevInsertObjectEquip` | dead | — | 关 0；出现 0；op 72 | inserted_object_equip | — |
| `actSetPrevInsertObjectFly` | dead | — | 关 0；出现 0；op 91 | inserted_object_fly_flag | — |
| `actSetPrevInsertObjectRandomID` | dead | — | 关 0；出现 0；op 109 | \[id]			(......... NOT USE .......) | — |
| `actSetPrevInsertObjectST` | dead | — | 关 0；出现 0；op 82 | inserted_object_stamina | — |
| `actSetPrevInsertObjectWaitRound` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_inserted_object_wait_round` | 关 4；出现 12；op 33 | inserted_object_wait_round | — |
| `actSetRandomPos` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_random_position_set` | 关 1；出现 1；op 106 | random_position_set | — |
| `actSetTownExecEvent` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 1；op 70 | town_exec_event | — |
| `actSetTownExitExecEvent` | dead | — | 关 0；出现 0；op 98 | town_exit_exec_event | — |
| `actSetUseShapeWait` | dead | — | 关 0；出现 0；op 57 | actor_use_shape_wait | — |
| `actSetWaitRound` | dead | — | 关 0；出现 0；op 34 | actor_wait_round | — |
| `actSetWalkSoundMode` | recorded | `game/battle/runtime/BattleOpeningCoordinator.gd:RECORD_ONLY_KINDS` | 关 1；出现 2；op 76 | walk_sound_mode | — |
| `actShapeMessage` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_shape_message` | 关 2；出现 9；op 74 | shape_message | — |
| `actShowSectionName` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_section_title_resource` | 关 50；出现 50；op 12 | section_title_resource | — |
| `actShowWinFailStatus` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_winfail_board_refresh` | 关 128；出现 128；op 31 | winfail_board_refresh | — |
| `actTRUE` | dead | — | 关 0；出现 0；op 67 | — | — |
| `actUseItem` | dead | — | 关 0；出现 0；op 93 | item_use | — |
| `actWaitPlayer` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_action_wait` | 关 19；出现 21；op 88 | actor_action_wait | — |
| `actWaitPrevInsertPlayer` | dead | — | 关 0；出现 0；op 119 | inserted_player_wait | — |
| `actWalk` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk` | 关 27；出现 159；op 2 | actor_walk | — |
| `actWalkAndDelete` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_and_delete` | 关 5；出现 13；op 4 | actor_walk_and_delete | — |
| `actWalkAndDeleteWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_and_delete_wait` | 关 5；出现 7；op 5 | actor_walk_and_delete_wait | — |
| `actWalkDisp` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_disp` | 关 30；出现 328；op 6 | actor_walk_disp | — |
| `actWalkDispWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_disp_wait` | 关 26；出现 103；op 7 | actor_walk_disp_wait | — |
| `actWalkFollow` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_follow` | 关 2；出现 2；op 50 | actor_walk_follow | — |
| `actWalkFollowWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_follow_wait` | 关 2；出现 2；op 51 | actor_walk_follow_wait | — |
| `actWalkPrevInsertObject` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_inserted_object_walk_disp` | 关 1；出现 4；op 8 | inserted_object_walk_disp | — |
| `actWalkPrevInsertObjectWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_inserted_object_walk_disp_wait` | 关 3；出现 12；op 9 | inserted_object_walk_disp_wait | — |
| `actWalkToPlayerDisp` | dead | — | 关 0；出现 0；op 61 | actor_walk_to_actor_disp | — |
| `actWalkToPlayerDispWait` | dead | — | 关 0；出现 0；op 62 | actor_walk_to_actor_disp_wait | — |
| `actWalkWait` | consumed | `game/battle/runtime/BattleOpeningCoordinator.gd:_ev_actor_walk_wait` | 关 35；出现 95；op 3 | actor_walk_wait | — |

### winfail

**WINFAIL opcode** · 来源 `content/generated/hsl/static/hsl01/winfail_token_coverage.json + game/sim/WinfailCompiler.gd` · 记录 winfail tokens

- consumed = SUPPORTED_CONDITIONS (WinfailConditions.condition_holds) ∪ APPLIED_ACTIONS (WinfailActions.apply_actions); recorded = WORLD_FLAG_ACTIONS ∪ PRESENTATION_ACTIONS (WinfailCompiler vocabulary).

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `actDelay` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1191 | — | — |
| `actMessage` | consumed | `game/sim/WinfailActions.gd:_act_message` | 出现 580 | — | — |
| `actInsertObject` | consumed | `game/sim/WinfailActions.gd:_act_insert_object` | 出现 372 | — | — |
| `actInsertEventStatus` | consumed | `game/sim/WinfailActions.gd:_act_insert_status` | 出现 211 | — | — |
| `actExecWinFailProcess` | consumed | `game/sim/WinfailActions.gd:_act_exec_win_fail_process` | 出现 180 | — | — |
| `actWalkPrevInsertObject` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 154 | — | — |
| `actCheckPlayer` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 153 | — | — |
| `actWalkPrevInsertObjectWait` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 148 | — | — |
| `actDeleteEventStatus` | consumed | `game/sim/WinfailActions.gd:_act_delete_status` | 出现 141 | — | — |
| `actSetNextPlayLevelEvent` | consumed | `game/sim/WinfailActions.gd:_act_set_next_play_level_event` | 出现 133 | — | — |
| `actInsertStoryObject` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 127 | — | — |
| `actCheckEnemyTotalNumber` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 109 | — | — |
| `actDeleteObject` | consumed | `game/sim/WinfailActions.gd:_act_delete_object` | 出现 91 | — | — |
| `actInsertShowPosObject` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 76 | — | — |
| `actSetPlayerMode` | consumed | `game/sim/WinfailActions.gd:_act_set_player_mode` | 出现 69 | — | — |
| `actCheckRoundNumber` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 68 | — | — |
| `actWalkAndDelete` | consumed | `game/sim/WinfailActions.gd:_act_delete_object` | 出现 68 | — | — |
| `actScrollBGToPos` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 59 | — | — |
| `actPlaySound` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 57 | — | — |
| `actSetPrevInsertObjectWaitRound` | consumed | `game/sim/WinfailActions.gd:_act_set_prev_insert_object_wait_round` | 出现 55 | — | — |
| `actCheckPlayerArrivePos` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 54 | — | — |
| `actTRUE` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 50 | — | — |
| `actInsertWinStatus` | consumed | `game/sim/WinfailActions.gd:_act_insert_status` | 出现 44 | — | — |
| `actBMSetPointEvent` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 43 | — | — |
| `actRestoreShape` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 42 | — | — |
| `actScrollBGToObject` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 40 | — | — |
| `actAddTE` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 39 | — | — |
| `actBMSetPointEncounterRatio` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 37 | — | — |
| `actWalk` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 35 | — | — |
| `actCheckPlayerAttacked` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 34 | — | — |
| `actSetPlayerFixPos` | consumed | `game/sim/WinfailActions.gd:_act_set_player_fix_pos` | 出现 34 | — | — |
| `actCheckEventNotExist` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 32 | — | — |
| `actCheckSerialPlayerAttacked` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 30 | — | — |
| `actSetPlayerWalkShape` | consumed | `game/sim/WinfailActions.gd:_act_set_player_walk_shape` | 出现 30 | — | — |
| `actWalkAndDeleteWait` | consumed | `game/sim/WinfailActions.gd:_act_delete_object` | 出现 27 | — | — |
| `actWalkDisp` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 26 | — | — |
| `actCheckEnemy` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 25 | — | — |
| `actShowWinFailStatus` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 25 | — | — |
| `actWalkDispWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 24 | — | — |
| `actCheckPlayerHPLow` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 23 | — | — |
| `actWaitPlayer` | consumed | `game/sim/WinfailActions.gd:_act_wait_player` | 出现 22 | — | — |
| `actMessageIfExist` | consumed | `game/sim/WinfailActions.gd:_act_message_if_exist` | 出现 21 | — | — |
| `actSetDeadMessage` | consumed | `game/sim/WinfailActions.gd:_act_set_dead_message` | 出现 21 | — | — |
| `actSetPlayerUndead` | consumed | `game/sim/WinfailActions.gd:_act_set_player_undead` | 出现 21 | — | — |
| `actCheckEnemyNumber` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 20 | — | — |
| `actDeletePosPlayerXRange` | consumed | `game/sim/WinfailActions.gd:_act_delete_pos_player_x_range` | 出现 20 | — | — |
| `actSetPrevInsertObjectFly` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 20 | — | — |
| `actDeleteFailStatus` | consumed | `game/sim/WinfailActions.gd:_act_delete_status` | 出现 15 | — | — |
| `actDeleteTE` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 15 | — | — |
| `actSetPlayerPosToRandom0` | consumed | `game/sim/WinfailActions.gd:_act_set_player_pos_to_random0` | 出现 13 | — | — |
| `actWalkWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 13 | — | — |
| `actDeletePosObject` | consumed | `game/sim/WinfailActions.gd:_act_delete_object` | 出现 12 | — | — |
| `actInsertFailStatus` | consumed | `game/sim/WinfailActions.gd:_act_insert_status` | 出现 12 | — | — |
| `actSetWaitRound` | consumed | `game/sim/WinfailActions.gd:_act_set_wait_round` | 出现 12 | — | — |
| `actUseItem` | consumed | `game/sim/WinfailActions.gd:_act_use_item` | 出现 11 | — | — |
| `actAddOverScore` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 10 | — | — |
| `actGetItem` | consumed | `game/sim/WinfailActions.gd:_act_get_item` | 出现 10 | — | — |
| `actInsertRandomObject` | consumed | `game/sim/WinfailActions.gd:_act_insert_random_object` | 出现 10 | — | — |
| `actInsertStoryObjectXRange` | consumed | `game/sim/WinfailActions.gd:_act_insert_story_object_x_range` | 出现 10 | — | — |
| `actSetPrevInsertObjectAdjustLevel` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 10 | — | — |
| `actSetTownExecEvent` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 10 | — | — |
| `actBMClearPointFlag` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 9 | — | — |
| `actInsertLevelUpStar` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 9 | — | — |
| `actBMClearTrackFlag` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 8 | — | — |
| `actDeleteShowPosObject` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 8 | — | — |
| `actSetPlayerFly` | consumed | `game/sim/WinfailActions.gd:_act_set_player_fly` | 出现 8 | — | — |
| `actWaitPrevInsertPlayer` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 8 | — | — |
| `actChangePrevInsertObjectID` | consumed | `game/sim/WinfailActions.gd:_act_change_prev_insert_object_id` | 出现 7 | — | — |
| `actBMSetPointFlag` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 6 | — | — |
| `actEarthQuake` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 6 | — | — |
| `actCheckPlayerArriveSysPos` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 5 | — | — |
| `actCheckPlayerTotalNumber` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 5 | — | — |
| `actKeepPlayerST` | consumed | `game/sim/WinfailActions.gd:_act_keep_player_st` | 出现 5 | — | — |
| `actBMSetTrackFlag` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 4 | — | — |
| `actInsertStoryObjectRandomPos` | consumed | `game/sim/WinfailActions.gd:_act_insert_object` | 出现 4 | — | — |
| `actSetBMWalkToPoint` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 4 | — | — |
| `actSetPlayerExecMode` | consumed | `game/sim/WinfailActions.gd:_act_set_player_exec_mode` | 出现 4 | — | — |
| `actSetWalkSoundMode` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 4 | — | — |
| `actCheckAnyPlayerArrivePos` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 3 | — | — |
| `actDarkScreen` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 3 | — | — |
| `actScrollBGToPosSpeed` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 3 | — | — |
| `actSetPrevInsertObjectST` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 3 | — | — |
| `actWalkToPlayerDispWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 3 | — | — |
| `actChangeShape` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 2 | — | — |
| `actCheckRoundDisp` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 2 | — | — |
| `actDeletePlayerCode` | consumed | `game/sim/WinfailActions.gd:_act_delete_player_code` | 出现 2 | — | — |
| `actEnterStorageWindow` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 2 | — | — |
| `actSetDoublePageMode` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 2 | — | — |
| `actSetOverFlag` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 2 | — | — |
| `actSetPlayerNoAttack` | consumed | `game/sim/WinfailActions.gd:_act_set_player_no_attack` | 出现 2 | — | — |
| `actBMSetShowTrackPoint` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 1 | — | — |
| `actCheckNextSerialNumber` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 1 | — | — |
| `actCheckNotPlayerAttacker` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 1 | — | — |
| `actDeleteRandomPosObject` | consumed | `game/sim/WinfailActions.gd:_act_delete_random_pos_object` | 出现 1 | — | — |
| `actDeleteWinStatus` | consumed | `game/sim/WinfailActions.gd:_act_delete_status` | 出现 1 | — | — |
| `actDetectRoundDispDisp` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 1 | — | — |
| `actFALSE` | consumed | `game/sim/WinfailConditions.gd:condition_holds` | 出现 1 | — | — |
| `actInsertObjectRandomPos` | consumed | `game/sim/WinfailActions.gd:_act_insert_object` | 出现 1 | — | — |
| `actInsertStoryObjectWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actInsertStoryObjectWaitPos` | consumed | `game/sim/WinfailActions.gd:_act_insert_story_object_wait_pos` | 出现 1 | — | — |
| `actMEssage` | unconsumed | UNCONSUMED | 出现 1 | — | — |
| `actMoveDispWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actPlayLevelMusic` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actPlayMovie` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actPlayerJobUpProcess` | consumed | `game/sim/WinfailActions.gd:_act_player_job_up_process` | 出现 1 | — | — |
| `actRandomSetSysArrivePos` | consumed | `game/sim/WinfailActions.gd:_act_random_set_sys_arrive_pos` | 出现 1 | — | — |
| `actSelectInsertEvent` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actSetBMWalkerPlayerID` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 1 | — | — |
| `actSetTownExitExecEvent` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 1 | — | — |
| `actSetUseShapeWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actShowSectionName` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 1 | — | — |
| `actBMSetPointMode` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 0 | — | — |
| `actBMSetTrackMode` | recorded | `game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS` | 出现 0 | — | — |
| `actChangeShapeWait` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |
| `actDeleteDarkScreen` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |
| `actPlayMusic` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |
| `actSetBGToObject` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |
| `actSetBGToPos` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |
| `actSetPrevInsertObjectEquip` | consumed | `game/sim/WinfailActions.gd:_act_folded_into_insert` | 出现 0 | — | — |
| `actWalkToPlayerDisp` | recorded | `game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS` | 出现 0 | — | — |

### town_event

**TOWNDEF te opcode** · 来源 `content/imported/hsl/global/world_map/towndef.json + game/sim/TownEventRules.gd` · 记录 te tokens

- consumed = TownEventRules.SUPPORTED_TOKENS; recorded = RECORDED_ONLY_TOKENS; dead = zero TOWNDEF uses and not executed.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `teAddSelfTE` | consumed | `game/sim/TownEventRules.gd:_world_tree_edit` | 出现 16；op 1 | — | — |
| `teDeleteSelfTE` | consumed | `game/sim/TownEventRules.gd:_world_tree_edit` | 出现 23；op 2 | — | — |
| `teAddTE` | consumed | `game/sim/TownEventRules.gd:_world_tree_edit` | 出现 21；op 3 | — | — |
| `teDeleteTE` | consumed | `game/sim/TownEventRules.gd:_world_tree_edit` | 出现 11；op 4 | — | — |
| `tePlayerMessage` | consumed | `game/sim/TownEventRules.gd:_te_player_message` | 出现 184；op 5 | — | — |
| `teDeletePlayerMessage` | consumed | `game/sim/TownEventRules.gd:_te_delete_player_message` | 出现 0；op 6 | — | — |
| `teShapeMessage` | consumed | `game/sim/TownEventRules.gd:_te_shape_message` | 出现 269；op 7 | — | — |
| `teDeleteShapeMessage` | consumed | `game/sim/TownEventRules.gd:_te_delete_shape_message` | 出现 0；op 8 | — | — |
| `teCreateShop` | consumed | `game/sim/TownEventRules.gd:_te_create_shop` | 出现 31；op 9 | — | — |
| `teCreateSubEventMenu` | consumed | `game/sim/TownEventRules.gd:_te_create_sub_event_menu` | 出现 13；op 10 | — | — |
| `teSetExecEvent` | consumed | `game/sim/TownEventRules.gd:_world_set_exec_event` | 出现 14；op 11 | — | — |
| `teGetGold` | consumed | `game/sim/TownEventRules.gd:_te_get_gold` | 出现 2；op 12 | — | — |
| `teSetNextPlayLevelEvent` | consumed | `game/sim/TownEventRules.gd:_te_set_next_play_level_event` | 出现 6；op 13 | — | — |
| `teDelay` | consumed | `game/sim/TownEventRules.gd:_te_delay` | 出现 171；op 14 | — | — |
| `teSelectInsertEvent` | consumed | `game/sim/TownEventRules.gd:_te_select_insert_event` | 出现 18；op 15 | — | — |
| `teCheckMoney` | consumed | `game/sim/TownEventRules.gd:_te_check_money` | 出现 2；op 16 | — | — |
| `teExecEvent` | consumed | `game/sim/TownEventRules.gd:_te_exec_event` | 出现 19；op 17 | — | — |
| `teCheckPlayerExist` | consumed | `game/sim/TownEventRules.gd:_te_check_exist_noop` | 出现 0；op 18 | — | — |
| `teCheckItemExist` | consumed | `game/sim/TownEventRules.gd:_te_check_exist_noop` | 出现 0；op 19 | — | — |
| `teBMSetPointFlag` | consumed | `game/sim/TownEventRules.gd:_world_bm_flag` | 出现 0；op 20 | — | — |
| `teBMSetTrackFlag` | consumed | `game/sim/TownEventRules.gd:_world_bm_flag` | 出现 3；op 21 | — | — |
| `teBMClearPointFlag` | consumed | `game/sim/TownEventRules.gd:_world_bm_flag` | 出现 12；op 22 | — | — |
| `teBMClearTrackFlag` | consumed | `game/sim/TownEventRules.gd:_world_bm_flag` | 出现 12；op 23 | — | — |
| `teBMSetShowTrackPoint` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_show_track_point` | 出现 8；op 24 | — | — |
| `teBMSetPointEvent` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_point_event` | 出现 1；op 25 | — | — |
| `teSetTownExecEvent` | consumed | `game/sim/TownEventRules.gd:_world_set_exec_event` | 出现 2；op 26 | — | — |
| `teBMSetPointMode` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_mode` | 出现 1；op 27 | — | — |
| `tePlaySound` | consumed | `game/sim/TownEventRules.gd:_te_play_sound` | 出现 6；op 28 | — | — |
| `teCheckItemExecEvent` | consumed | `game/sim/TownEventRules.gd:_te_check_item_exec_event` | 出现 8；op 29 | — | — |
| `tePlayerSelectInsertEvent` | consumed | `game/sim/TownEventRules.gd:_te_player_select_insert_event` | 出现 2；op 30 | — | — |
| `teCheckJobUp` | consumed | `game/sim/TownEventRules.gd:_te_check_job_up` | 出现 8；op 31 | — | — |
| `teCheckJobUp2` | consumed | `game/sim/TownEventRules.gd:_te_check_job_up` | 出现 2；op 32 | — | — |
| `teCheckTEExist` | consumed | `game/sim/TownEventRules.gd:_te_check_te_exist` | 出现 4；op 33 | — | — |
| `teBMSetPointEventNotVisit` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_point_event` | 出现 1；op 34 | — | — |
| `teGetItem` | consumed | `game/sim/TownEventRules.gd:_te_get_item` | 出现 23；op 35 | — | — |
| `teAppearSecretMan` | consumed | `game/sim/TownEventRules.gd:_world_appear_secret_man` | 出现 7；op 36 | — | — |
| `teDeleteSecretMan` | consumed | `game/sim/TownEventRules.gd:_world_delete_secret_man` | 出现 8；op 37 | — | — |
| `teSetSecretAppearRatio` | consumed | `game/sim/TownEventRules.gd:_world_set_secret_appear_ratio` | 出现 1；op 38 | — | — |
| `teSecretManBuyThing` | consumed | `game/sim/TownEventRules.gd:_te_secret_man_buy_thing` | 出现 1；op 39 | — | — |
| `teMenuMoveOut` | consumed | `game/sim/TownEventRules.gd:_te_menu_move_out` | 出现 1；op 40 | — | — |
| `teSetBMWalkToPoint` | consumed | `game/sim/TownEventRules.gd:_world_set_bm_walk_to_point` | 出现 2；op 41 | — | — |
| `teBMSetTrackMode` | consumed | `game/sim/TownEventRules.gd:_world_bm_set_mode` | 出现 4；op 42 | — | — |
| `teSetTownExitExecEvent` | consumed | `game/sim/TownEventRules.gd:_world_set_town_exit_exec_event` | 出现 1；op 43 | — | — |
| `teAddOverScore` | consumed | `game/sim/TownEventRules.gd:_world_add_over_score` | 出现 5；op 44 | — | — |
| `teCheckJobUpDeny` | dead | — | 出现 0；op 100 | — | — |
| `teCheckMoney2` | dead | — | 出现 0；op 101 | — | — |

### animal

**ANIMAL.H ani* opcode（演员程序 + 绝技特效脚本）** · 来源 `content/generated/hsl/animation/animal_programs.json + content/generated/hsl/skills/special_effect_scripts.json + game/battle/scene/SkillEffectScriptPlayer.gd` · 记录 ani* opcodes

- consumed = every channel using the opcode has its interpreter: action → combat_animation.ACTION_OPCODES (compile_action binds the program into the manifest dispatch BattleCombatCutin plays, one update per tick); s_action → AnimalCastLead.CAST_OPCODES (the 絶技 lead the special cut-in plays); m_action → AnimalCastLead.CAST_OPCODES (the same four opcodes over the imported m_shape strips, the map magic presenter plays the lead; casters without an imported strip keep CAST_LEAD_IN); effect → SkillEffectScriptPlayer.IMPLEMENTED_OPCODES.

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `aniOver` | dead | — | 出现 0；op 0 | — | — |
| `aniDelay` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action + game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 563；op 1 | \[counter] | — |
| `aniInsertObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 124；op 2 | \[code]\[x]\[y] | — |
| `aniSetAddSpeed` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 1；op 3 | \[angle]\[speed]\[step]\[max] | — |
| `aniSetSubSpeed` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 4；op 4 | \[angle]\[speed]\[step]\[min] | — |
| `aniSetStopSpeed` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 1；op 5 | — | — |
| `aniNextShape` | dead | — | 出现 0；op 6 | — | — |
| `aniSetShape` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 182；op 7 | \[shape number disp] | — |
| `aniProcShapeToEnd` | dead | — | 出现 0；op 8 | \[delay counter] | — |
| `aniSetZoom` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 6；op 9 | \[zoom(xx.xx)] | — |
| `aniSetXYDisp` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action + game/battle/scene/AnimalCastLead.gd:compile + game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 45；op 10 | \[xdisp]\[ydisp] | — |
| `aniInsertAttackFlash` | consumed | `tools/hsltools/assets/combat_animation.py:compile_action` | 出现 59；op 11 | \[xdisp]\[ydisp] | — |
| `aniShadowBG` | consumed | `game/battle/scene/AnimalCastLead.gd:compile` | 出现 37；op 12 | — | — |
| `aniMoveToCenter` | consumed | `game/battle/scene/AnimalCastLead.gd:compile` | 出现 37；op 13 | — | — |
| `aniInsertCastObject` | consumed | `game/battle/scene/AnimalCastLead.gd:compile` | 出现 37；op 14 | \[xdisp]\[ydisp]\[shp1 disp]\[delay1]\[delay2] | — |
| `aniInsertSpecialBG` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 16；op 15 | \[shape id] | — |
| `aniPlaySound` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 138；op 16 | \[id] | — |
| `aniProcessHitMiss` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 55；op 17 | — | — |
| `aniProcessHitMissMulti` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 9；op 18 | — | — |
| `aniInsertRandomObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 93；op 19 | \[code]\[x]\[y]\[x range]\[y range]\[delay]\[number] | — |
| `aniInsertAngleObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 6；op 20 | \[code]\[x]\[y]\[degree num]\[base delay]\[delay] | — |
| `aniInsertAngleObjectMakeShape` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 1；op 21 | \[code]\[x]\[y]\[degree num]\[base delay]\[delay] | — |
| `aniInsertTornadoObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 2；op 22 | \[code]\[x]\[y]\[y step]\[radius]\[radius step]\[start angle]\[angle step]\[start zoom]\[zoom step]\[number] | — |
| `aniInsertRandomObjectDelay` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 48；op 23 | \[code]\[x]\[y]\[x range]\[y range]\[base delay]\[delay]\[number] | — |
| `aniInsertRandomObjectFixDelay` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 67；op 24 | \[code]\[x]\[y]\[x range]\[y range]\[base delay]\[delay]\[number] | — |
| `aniInsertDistanceObjectFixDelay` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 5；op 25 | \[code]\[x]\[y]\[x disp]\[y disp]\[base delay]\[delay]\[number] | — |
| `aniInsertRoundRandomObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 2；op 26 | \[code]\[x]\[y]\[radius]\[x shr]\[y shr]\[delay]\[start angle]\[number] | — |
| `aniInsertHitRandomObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 38；op 27 | \[code]\[x]\[y]\[x range]\[y range]\[delay]\[number] | — |
| `aniInsertHitRandomObjectDisp` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 5；op 28 | \[code]\[x disp]\[y disp]\[x range]\[y range]\[delay]\[number] | — |
| `aniInsertHitRandomObjectFixDelay` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 11；op 29 | \[code]\[x]\[y]\[x range]\[y range]\[base delay]\[delay]\[number] | — |
| `aniShowHitResult` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 50；op 30 | — | — |
| `aniNoSpecialDarkBG` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 3；op 31 | — | — |
| `aniShowAttacker` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 2；op 32 | — | — |
| `aniDoublePageMode` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 15；op 33 | — | — |
| `aniPlayHitSound` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 43；op 34 | \[id] | — |
| `aniShowHitResultNoWait` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile` | 出现 5；op 35 | — | — |

### effects

**EFFECTS.TXT eff* opcode（法术特效）** · 来源 `content/imported/hsl/shared/first_skill/effects.txt + content/imported/hsl/global/tables/effects.h` · 记录 \[effect] blocks

| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `effWait` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 出现 178；op 1 | \[counter] 等待 | 169 段 \[effect] = 130 段 specCode（绝技，ani*）＋ 39 段 effCode（魔法，eff*）；四个 eff* 全部解释，60 tick/s 时钟 provisional |
| `effInsertObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 出现 91；op 2 | \[code]\[x disp]\[y disp] | 位移相对效果原点（受影响格）；有原生轨迹的对象按 effect_motion.json 逐帧运动，其余按 shape_number×(shape_delay+1) 至少 48 tick 后淡出 |
| `effInsertRandomObject` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 出现 115；op 3 | \[code]\[x disp]\[y disp]\[x range]\[y range]\[delay range]\[number] | 偏移为 rand(范围) 折进 (−范围/2, 范围/2]、延迟逐个累加 rand(延迟范围)（解释器 0x423873／0x423951） |
| `effPlaySound` | consumed | `game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect` | 出现 60；op 4 | \[code] | — |

## 6. 边界

- Test green or a citation resolving proves the remake reads the field, not that it applies the original semantics; original equivalence stays per-mechanic evidence.
- Opcode tables count script occurrences, not player-visible weight; a token used once in the finale can matter more than a hundred actDelay.
- The OBJ census and the EVEF word census are measured from the original PAK and pinned in this module; rerun the --census CLI when the seeds change.
- 引用核对只证明文件与符号存在并被生成器／规则读到，不证明语义与原版等价；每条机制的等价声明仍以各自证据包为准。
- `evef_actor` 的状态与 `hsltools/data/evef_instances.py` 的 `RUNTIME_APPLIED` 绑定，二者不一致时 `hsl check field_coverage` 失败。
