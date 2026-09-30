"""Field coverage of the original data tables: which fields of every original record type
the remake consumes, and which it ignores (the "missed a whole concept" audit, lane R21).

Lane R16 found that the level .BIN instance words (per-unit wait_round / fixed_point /
items, 535 units) had never been read, and the player noticed enemies no longer come
down in waves. This task makes that class of gap enumerable: for every original table
or record kind it lists every field, how many rows / units / occurrences carry a
non-default value (measured from the tracked imports), and where the remake consumes
it (file:function, validated to exist) or that it does not.

  measured   column lists and non-default counts from content/imported tables, EVEF words
             from the tracked battle seeds, opcode occurrences from the tracked coverage
             reports, interpreter support sets from the GDScript constants
  curated    FIELD_NOTES: status + consumer + semantics per field; SUSPECTS: the ranked
             top list with what the player would notice. Every field of a measured table
             must have a note and every note must name a measured field; every consumer
             citation `path:symbol` must resolve to an existing file that defines the
             symbol (func / def / const / class / module constant)

Status vocabulary (one spelling per concept):
  consumed        enters a remake rule or presentation (consumer = where)
  passthrough     a generator copies it into tracked data, but no runtime rule reads it
  recorded        the runtime receives it and records it without effect (e.g. RECORD_ONLY_KINDS)
  unconsumed      no remake code reads it
  dead            never non-default in the original data, or the original loader itself
                  does not read it — nothing for the remake to consume

Registry task field_coverage (family checks, GeneratedFilesTask): outputs
content/generated/hsl/development/field_coverage.json and the readable packet
docs/evidence_packets/static_reverse/original_field_coverage.md; check is byte-for-byte
against both; `hsl generate field_coverage` rewrites them.
PASS line: FIELD_COVERAGE_PASS tables=N fields=M consumed=… unconsumed=….
"""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from hsltools.assets.combat_animation import ACTION_OPCODES
from hsltools.data import json_bytes
from hsltools.data.evef_instances import RUNTIME_APPLIED, build as evef_instances_table
from hsltools.data.original_save_members import REC
from hsltools.levels.seed import ACTOR_INSTANCE_OVERRIDE_FIELDS
from hsltools.paths import ROOT, TABLES
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask
from hsltools.sources.tables import blocks

OUTPUT_JSON = 'content/generated/hsl/development/field_coverage.json'
OUTPUT_DOC = 'docs/evidence_packets/static_reverse/original_field_coverage.md'
SCHEMA = 'hsl_original_field_coverage.v1'
PACKET_UPDATED = '2026-09-30'  # bump when FIELD_NOTES / SUSPECTS / the static readings change

SEEDS = 'content/generated/hsl/chapter01/'
TERRAIN = 'content/generated/hsl/static/hsl01/'
ITEMS_JSON = 'content/generated/hsl/equipment/items.json'
STORY_COVERAGE = 'content/generated/hsl/static/hsl01/story_token_coverage.json'
WINFAIL_COVERAGE = 'content/generated/hsl/static/hsl01/winfail_token_coverage.json'
TOWNDEF = 'content/imported/hsl/global/world_map/towndef.json'
ANIMAL_PROGRAMS = 'content/generated/hsl/animation/animal_programs.json'
SPECIAL_EFFECTS = 'content/generated/hsl/skills/special_effect_scripts.json'
EFFECTS_TXT = 'content/imported/hsl/shared/first_skill/effects.txt'
OPENING_COORDINATOR = 'game/battle/runtime/BattleOpeningCoordinator.gd'
TOWN_RULES = 'game/sim/TownEventRules.gd'
WINFAIL_ACTIONS = 'game/sim/WinfailActions.gd'
EFFECT_PLAYER = 'game/battle/scene/SkillEffectScriptPlayer.gd'
CAST_LEAD = 'game/battle/scene/AnimalCastLead.gd'
COMBAT_ANIMATION = 'tools/hsltools/assets/combat_animation.py'

STATUSES = ('consumed', 'passthrough', 'recorded', 'unconsumed', 'dead')
INI_TABLES = (('players', 'PLAYERS.TXT', 'character'), ('item', 'ITEM.TXT', 'item'), ('magic', 'MAGIC.TXT', 'magic'),
              ('special', 'SPECIAL.TXT', 'special'), ('range', 'RANGE.TXT', 'range'), ('shapedef', 'SHAPEDEF.TXT', 'define'))
DEFAULT_VALUES = {'0', '', '0,0', '-1'}

# --- curated notes ------------------------------------------------------------------------
# table -> field -> (status, consumer 'path:symbol' | None, semantics, note | None)
# Consumers name the first place the field turns into a rule/presentation input; generators are
# named when the runtime reads the generated key they write.
CA = 'tools/hsltools/data/campaign_actors.py:build'
JOBS = 'tools/hsltools/model/jobs.py:source_profile'
AIP = 'tools/hsltools/data/ai_profiles.py:build'
BOOK = 'tools/hsltools/data/skill_book.py:build'
EQ = 'tools/hsltools/data/equipment.py:build'
CONS = 'tools/hsltools/data/consumables.py:build'
SAVE = 'tools/hsltools/data/original_save_members.py:synthesize'
UNRESOLVED_OBS = 'load_obs_template 0x45dc5c 写入模板字；演员构造 0x407ec0 只读 obj_Data5／7／8／9、obj_X1／Y1、obj_HitPoint（本包 static-derived），其余过程各自读法未追'

FIELD_NOTES: dict[str, dict[str, tuple]] = {
    'players': {
        'code': ('consumed', CA, '角色编号＝模板表索引（0x44b980）', None),
        'name': ('consumed', 'tools/hsltools/levels/actors.py:_resolve_name', 'RESOURCE 名字 id', None),
        'sound_dead': ('consumed', 'tools/hsltools/assets/actor_audio.py:build', '死亡音效 WAV', None),
        'sound_walk': ('consumed', 'tools/hsltools/assets/actor_audio.py:build', '行走音效', None),
        'sound_attack': ('consumed', 'tools/hsltools/assets/actor_audio.py:build', '攻击音效', None),
        'sound_miss': ('consumed', 'tools/hsltools/assets/actor_audio.py:build', '未命中音效', None),
        'sound_hit': ('consumed', 'tools/hsltools/levels/actors.py:build_audio', '被击音效（4 行；记录 +0x10 lo 句柄）', '普攻命中音链第二级：攻方无 sound_shoothit 时 0x409790 放目标的 sound_hit，都无才按武器图标（爪／刺回退 405）；actor_audio hit 事件，BattlePresentation._play_hit_sound 放（docs/evidence_packets/static_reverse/original_unconsumed_fields.md）'),
        'sound_walkwater': ('consumed', 'tools/hsltools/assets/interface_audio.py:walk_water_rows', '水中行走音效（2 行，均同 sound_walk）', None),
        'sound_shoothit': ('consumed', 'tools/hsltools/levels/actors.py:build_audio', '射击命中音效（1 行，+0x22）', '紅龍 051 BOMB0028；普攻命中音链第一级，0x406dc9..0x406dd7 每次出手写 [0x4c13f8]，不看武器；actor_audio shoothit 事件'),
        'job': ('consumed', JOBS, '职业码 → 0x448840 数值分支', None),
        'class': ('consumed', 'tools/hsltools/assets/panel_assets.py:definitions', '种族（+0x20 低字，TYPE.H class* → RESOURCE 101–106／243／244）', '原版只作显示：0x42b3b3 GameClear 状态表「種族」、0x4351a0 身份栏文字（0x4477b0）、0x4349b3 非零复制；有界扫描内未见 class 常量比较（839 处 [reg+0x20] 读取后 10 条指令，negative-evidence），无规则效果；重制 panel_assets 写 race，BattleVitals 状态面板与 GameClear 表显示之'),
        'status': ('dead', None, 'PLAYERS 初始状态位（15 行全 0）', '原 live +0x24 由回合 tick 改写；数据全 0'),
        'mode': ('consumed', 'tools/hsltools/levels/battle.py:install_player_mode', 'pmPlayer／pmEnemy／pmNPCPlayer 阵营位', '模板值经 OBJ obj_Data9 互换与 obj_X1 覆盖后写单位 player_mode（见 obj 表）'),
        'str': ('consumed', 'game/sim/CoreCombatRules.gd:hit_chance', '力量（伤害 str 项）', None),
        'dex': ('consumed', 'game/sim/CoreCombatRules.gd:hit_chance', '敏捷（命中 dex 项）', None),
        'mind': ('consumed', JOBS, '精神 → 魔攻／抗性', None),
        'con': ('consumed', JOBS, '体质 → HP', None),
        'attack_damagex2': ('consumed', 'game/sim/CoreCombatRules.gd:critical_impact', '暴击（双倍伤害）几率', None),
        'hit_point': ('consumed', JOBS, 'HP 加值（+0x1b6 半字）', None),
        'defense': ('consumed', JOBS, '防御加值', None),
        'picture': ('consumed', 'tools/hsltools/assets/portraits.py:build', '头像 SHP', None),
        'job_up_code': ('consumed', 'tools/hsltools/data/original_save.py:build', '转职目标对象码（存档生成／城镇转职）', None),
        'weapon_skill': ('dead', None, '2 行全 0，EXE 无 loader 字段', None),
        'magic_skill': ('dead', None, '2 行全 0', None),
        'exp': ('consumed', 'tools/hsltools/data/progression.py:build', '初始经验', None),
        'kill_exp': ('consumed', 'game/sim/ExperienceRules.gd:from_contribution', '击杀经验', None),
        'gold': ('consumed', 'game/sim/BattleRewardRules.gd:drops', '击杀金钱', None),
        'level': ('consumed', 'tools/hsltools/data/role_profiles.py:build', '初始等级', None),
        'stamina': ('consumed', 'game/sim/ActorInitializationRules.gd:prepare', '开场气力：首次登记／NPC 构造整条复制模板（0x44cb41／0x44cb88）', None),
        'weapon_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '武器槽', None),
        'head_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '头部槽', None),
        'armor_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '身体槽', None),
        'foot_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '脚部槽', None),
        'other1_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '饰品 1', None),
        'other2_equip': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '饰品 2', None),
        'resist_earth': ('consumed', JOBS, '地抗基值', None),
        'resist_water': ('consumed', JOBS, '水抗基值', None),
        'resist_air': ('consumed', JOBS, '风抗基值', None),
        'resist_fire': ('consumed', JOBS, '火抗基值', None),
        'resist_mind': ('consumed', JOBS, '心抗基值', None),
        'move_point': ('consumed', 'game/sim/TacticalGridRules.gd:movement_reachability_envelope', '移动力', None),
        'item1': ('consumed', CONS, '初始背包槽 1', None),
        'item2': ('consumed', CONS, '初始背包槽 2', None),
        'item3': ('consumed', CONS, '初始背包槽 3', None),
        'item4': ('consumed', CONS, '初始背包槽 4', None),
        'item5': ('dead', None, '初始背包槽 5（数据全 0）', None),
        'item6': ('dead', None, '初始背包槽 6（数据全 0）', None),
        'item7': ('dead', None, '初始背包槽 7（数据全 0）', None),
        'item8': ('dead', None, '初始背包槽 8（数据全 0）', None),
        'special_other': ('consumed', BOOK, '初始绝技位（其他系）', None),
        'special_fire': ('dead', None, '初始绝技位（火，全 0）', None),
        'special_water': ('consumed', BOOK, '初始绝技位（水）', None),
        'special_earth': ('consumed', BOOK, '初始绝技位（地）', None),
        'special_wind': ('consumed', BOOK, '初始绝技位（风）', None),
        'special_mind': ('consumed', BOOK, '初始绝技位（心）', None),
        'special_other2': ('consumed', BOOK, '初始绝技位（其他 2）', None),
        'magic_other': ('consumed', BOOK, '初始魔法位（其他）', None),
        'magic_fire': ('consumed', BOOK, '初始魔法位（火）', None),
        'magic_water': ('consumed', BOOK, '初始魔法位（水）', None),
        'magic_earth': ('consumed', BOOK, '初始魔法位（地）', None),
        'magic_wind': ('consumed', BOOK, '初始魔法位（风）', None),
        'magic_mind': ('consumed', BOOK, '初始魔法位（心）', None),
        'find_type': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '目标选择策略', None),
        'find_range': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '搜索半径', None),
        'ai_call_range': ('consumed', 'game/sim/AINavigationRules.gd:guard_allows', '呼援半径', None),
        'ai_fixed': ('consumed', 'game/sim/AINavigationRules.gd:guard_allows', '守备半径（模板全 0；EVEF 字 15 写 8）', None),
        'ai_check_dying': ('consumed', 'game/sim/AIPriorityRules.gd:choose_check', '濒死自救概率', None),
        'ai_check_hp': ('consumed', 'game/sim/AIPriorityRules.gd:choose_check', '低血阈值', None),
        'ai_help_otherhp': ('consumed', 'game/sim/AISupportRules.gd:next_check', '援友治疗概率', None),
        'ai_help_status': ('consumed', 'game/sim/AISupportRules.gd:next_check', '援友解状态概率', None),
        'ai_help_attack': ('consumed', 'game/sim/AISupportRules.gd:next_check', '援友增益概率', None),
        'ai_lock': ('consumed', 'game/sim/AINavigationRules.gd:acquire', '锁定目标概率', None),
        'ai_att_special': ('consumed', 'game/sim/AIDecisionRules.gd:select_action', '用绝技概率', None),
        'ai_att_magic': ('consumed', 'game/sim/AIDecisionRules.gd:select_action', '用魔法概率', None),
        'ai_magic_multi_first': ('consumed', 'game/sim/AISkillPlanning.gd:prepare', '范围魔法优先', None),
        'level_adjust_range': ('consumed', 'game/sim/ReinforcementGrowthRules.gd:prepare', '入场调级范围', None),
        'level_adjust_disp_range': ('consumed', 'game/sim/ReinforcementGrowthRules.gd:prepare', '入场调级位移', None),
        'avoid_hit_ratio': ('consumed', 'game/sim/CoreCombatRules.gd:hit_chance', '回避率（+0x19a）', None),
        'steal_ratio': ('consumed', 'game/sim/SpecialUtilityRules.gd:prepare', '偷窃加成字（+0x194；0x448840 → +0x196 工作字＝字或 12；0x40b5a8 偷物 rand(100)+1 < get_ratio+10+工作字）', 'R27 起 equipment.initial_physical_fields 写单位 combat_profile.base_steal_ratio／steal_ratio，ProgressionRules.refresh_growth_stats 重算，JobUpRules 按 0x434aa6 相加基字；2 行（004=30／013=20），其余 64 行走默认 12'),
        'find_flag': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '目标筛选旗（AIF_*）', None),
        'speed': ('consumed', JOBS, '速度加值 → 行动序', None),
        'attack_power': ('consumed', JOBS, '攻击加值', None),
        'magic_attack_power': ('consumed', JOBS, '魔攻加值', None),
        'move_fly': ('consumed', 'game/sim/ActorTraversalRules.gd:mode', '飞行（+0xa0 bit 0x1）', None),
        'attack_back': ('consumed', 'game/sim/CoreCombatRules.gd:attack_back_triggered', '反击率', None),
        'dead_message': ('consumed', 'tools/hsltools/data/combat_aftermath.py:build', '死亡台词 id 对', None),
        'no_poison': ('consumed', 'game/sim/StatusApplicationRules.gd:modifiers', '免毒（bit 0x40）', None),
        'magic_point': ('consumed', JOBS, 'MP 加值', None),
        'size_type': ('consumed', 'game/sim/FootprintRules.gd:radius', '大型占地', None),
        'double_attack': ('consumed', 'game/sim/CombatSequenceRules.gd:attack_count', '二连击（bit 0x200）', None),
        'st_x2': ('consumed', 'game/sim/StaminaRules.gd:effects', '气力双倍（bit 0x4000）', None),
        'job_show_name': ('consumed', 'tools/hsltools/data/combat_aftermath.py:build', '显示称号 id', None),
        'move_magic_use': ('consumed', 'game/sim/PositionCapabilityRules.gd:effects', '移动后可施法（bit 0x400）', None),
        'carry_item': ('consumed', 'game/sim/BattleRewardRules.gd:carry', '掉落表 id', None),
        'find_no_id': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '排除目标 SID', None),
        'no_paralyze': ('consumed', 'game/sim/StatusApplicationRules.gd:modifiers', '免麻痹（bit 0x800）', None),
        'no_disablemagic': ('consumed', 'game/sim/StatusApplicationRules.gd:modifiers', '免封魔（bit 0x1000）', None),
        'no_weaken': ('consumed', 'game/sim/StatusApplicationRules.gd:modifiers', '免虚弱（bit 0x2000）', None),
        'no_attack': ('consumed', 'game/sim/AINavigationRules.gd:acquire', '不攻击（bit 0x2）', None),
        'no_shadow': ('dead', None, '不画影子（bit 0x100，1 行）', '全 EXE 找不到读 0x100 的地方；重制不画单位影子，无可见差别'),
        'no_block': ('consumed', 'game/sim/ActorTraversalRules.gd:source', '不阻挡（bit 0x10）', None),
        'no_showshape': ('consumed', 'game/battle/runtime/ActorRuntime.gd:hide_shape', '不显示形体（bit 0x20，1 行）', None),
    },
    'item': {
        'code': ('consumed', EQ, '物品编号', None),
        'name': ('consumed', EQ, 'RESOURCE 名字 id', None),
        'cost': ('consumed', 'game/world/WorldPartyRules.gd:buy', '售价（商店买卖）', None),
        'type': ('consumed', EQ, '物品类型（itemType*）', None),
        'icon': ('consumed', EQ, '图标', None),
        'attack_range': ('consumed', 'tools/hsltools/data/attack_ranges.py:weapon_ranges', '武器射程码', None),
        'attack_damage': ('consumed', EQ, '武器伤害／防具防御／速度加值（按 type）', None),
        'get_ratio': ('consumed', 'game/sim/BattleRewardRules.gd:drops', '掉落／被偷概率', None),
        'important': ('consumed', 'game/sim/InventoryRules.gd:discard_error', '重要物品不可丢', None),
        'use_job': ('consumed', EQ, '可装备职业', None),
        'hit_ratio': ('consumed', 'game/sim/CoreCombatRules.gd:hit_chance', '武器命中', None),
        'add_weapon_hit': ('consumed', EQ, '命中加值', None),
        'add_magic_hit': ('consumed', EQ, '魔法命中加值', None),
        'add_attack_power': ('consumed', EQ, '攻击加值', None),
        'add_magic_power': ('consumed', EQ, '魔攻加值', None),
        'add_mp': ('consumed', EQ, 'MP 上限加值', None),
        'add_hp': ('consumed', EQ, 'HP 上限加值', None),
        'add_move': ('consumed', EQ, '移动力加值', None),
        'add_speed': ('consumed', EQ, '速度加值', None),
        'add_defense': ('consumed', EQ, '防御加值', None),
        'add_attack_range': ('consumed', 'game/sim/PositionCapabilityRules.gd:effects', '射程 +1', None),
        'mp_use_half': ('consumed', 'game/sim/SkillResourceRules.gd:amounts', 'MP 消耗减半', None),
        'hp_damage_half': ('consumed', 'game/sim/CoreCombatRules.gd:resolve_attack', '受伤减半（1 行 302 替身雕像；loader 0x447e1b 置 item+0xa0 bit 4 → +0x18c）', '0x4423c0 在 0x442545 调 0x40e2a0：守方有该位时非零伤害减半，得 0 取 1；只在普攻／反击'),
        'action_twice': ('consumed', 'game/sim/ExtraActionRules.gd:equipment', '再行动', None),
        'exp_x2': ('consumed', 'game/sim/ExperienceRules.gd:multiplier', '经验双倍', None),
        'gold_x2': ('consumed', 'game/sim/BattleRewardRules.gd:gold_multiplier', '金钱双倍（1 行 230；item 位 0x20 → +0x18c，0x442819 经 0x40e2d0 翻倍）', '曾误记 dead；REWARD 接入'),
        'st_x2': ('consumed', 'game/sim/StaminaRules.gd:effects', '气力双倍', None),
        'keep_status_good': ('consumed', 'game/sim/StatusApplicationRules.gd:equipment_modifiers', '免所有异常', None),
        'hp_auto_restore': ('consumed', 'game/sim/ResourceRecoveryRules.gd:effects', 'HP 自动回复', None),
        'mp_auto_restore': ('consumed', 'game/sim/ResourceRecoveryRules.gd:effects', 'MP 自动回复', None),
        'move_magic_use': ('consumed', 'game/sim/PositionCapabilityRules.gd:effects', '移动后可施法', None),
        'no_special': ('dead', None, '禁绝技（数据 1 行为 0）', None),
        'no_magic': ('dead', None, '禁魔法（ITEM 数据 1 行为 0；同名状态另有来源）', None),
        'double_attack': ('consumed', 'game/sim/CombatSequenceRules.gd:attack_count', '二连击', None),
        'attack_cancel': ('consumed', 'game/sim/WeaponEffectRules.gd:effects', '击中取消行动', None),
        'attack_weaken': ('consumed', 'game/sim/WeaponEffectRules.gd:resolve', '击中衰弱（1 行 51；item+0xa0 位 0x20000，0x409310 分支 25% → 0x409240）', 'R21 曾误记 dead；R27 随 random_status_error 一并接入'),
        'attack_nomagic': ('consumed', 'game/sim/WeaponEffectRules.gd:resolve', '击中禁魔（1 行 66；位 0x80000 → 0x409210）', 'R21 曾误记 dead；R27 接入'),
        'random_status_error': ('consumed', 'game/sim/WeaponEffectRules.gd:resolve', '击中随机异常（2 行 71／209；位 0x40000，0x409310 以 rand(100)+1 选衰弱／禁魔／麻痺／中毒一位替换状态字，再各 25%）', 'R27 接入；71 朧月 range6CellShoot 走 0x40f8b0 通用传播，可装'),
        'attack_paralysis': ('dead', None, '击中麻痺（位 0x100000 → 0x409110；数据 1 行为 0，随机位可选中该分支）', 'WeaponEffectRules.resolve 已实现分支，无数据行'),
        'attack_poison': ('consumed', 'game/sim/WeaponEffectRules.gd:effects', '击中中毒', None),
        'attack_decmp': ('consumed', 'game/sim/WeaponEffectRules.gd:effects', '击中削 MP', None),
        'avoid_poison': ('consumed', 'game/sim/StatusApplicationRules.gd:equipment_modifiers', '免毒', None),
        'avoid_nomagic': ('consumed', 'game/sim/StatusApplicationRules.gd:equipment_modifiers', '免封魔', None),
        'avoid_weaken': ('consumed', 'game/sim/StatusApplicationRules.gd:equipment_modifiers', '免衰弱（1 行 220；位 0x2000000，0x40e2f0 免疫查询）', 'R21 曾误记 dead；R27 随 equipment.py status_effect_flags 接入'),
        'avoid_paralysis': ('consumed', 'game/sim/StatusApplicationRules.gd:equipment_modifiers', '免麻痹', None),
        'high_cost': ('consumed', 'game/battle/scene/BattleEquipmentView.gd:item_flags', '高价（4 行非 0；loader 0x448164 置 item+0xa0 bit 0x800，并入 +0x18c）', '只有说明框 0x430710 在 0x432946 测该位写 618 高價值，无规则效果；equipment.py INERT_FIELDS 照原版可装'),
        'no_addst': ('consumed', 'game/sim/StaminaRules.gd:effects', '不加气力', None),
        'hp_transfer_mp': ('consumed', 'game/sim/ResourceRecoveryRules.gd:transfer_values', 'HP 转 MP', None),
        'add_steal_ratio': ('consumed', 'game/sim/EquipmentRules.gd:effect_delta', '偷窃加成（1 行 131 隱忍黑衣 20；item+0x40，0x448420 加到 +0x196 工作字）', 'equipment.py NUMERIC add_steal_ratio→effects.steal_ratio；131 因此 supported'),
        'add_miss_hit': ('consumed', EQ, '回避加值', None),
        'add_attack_back': ('consumed', EQ, '反击加值', None),
        'add_weapon_dmgx2': ('consumed', EQ, '暴击加值', None),
        'magic_attack_type': ('consumed', 'tools/hsltools/data/equipment.py:weapon_magic', '武器属性伤害三元组', None),
        'take_off': ('consumed', EQ, '不可卸下', None),
        'add_resist': ('consumed', EQ, '抗性加值（属性,值）', None),
        'add_defnese': ('dead', None, '拼写错误列（1 行；loader 无此字段名）', '原 PLAYERS/ITEM loader 按名字查字段，错拼即丢弃'),
        'cure_poison': ('consumed', 'game/sim/ItemUseRules.gd:prepare', '消耗品解毒', None),
        'cure_no_magic': ('consumed', 'game/sim/ItemUseRules.gd:prepare', '消耗品解封魔', None),
        'cure_paralysis': ('consumed', 'game/sim/ItemUseRules.gd:prepare', '消耗品解麻痹', None),
        'cure_weaken': ('consumed', 'game/sim/ItemUseRules.gd:prepare', '消耗品解衰弱（3 行；loader 0x447fe2 → item+0xa0 位 0x10000000，0x40a31f 清 +0x38 与 flag 8 后 0x448840 刷新）', 'R27 起 249／251／252 登记为消耗品；ItemResolutionRules 在解除后刷新派生属性'),
        'add_st': ('consumed', CONS, '消耗品加气力', None),
        'global_add_weapon_power': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久攻击', None),
        'global_add_defense': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久防御', None),
        'global_add_magic_power': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久魔攻', None),
        'global_add_speed': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久速度', None),
        'global_add_resist_earth': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久地抗', None),
        'global_add_resist_fire': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久火抗', None),
        'global_add_resist_water': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久水抗', None),
        'global_add_resist_air': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久风抗', None),
        'global_add_resist_mind': ('consumed', 'game/sim/PermanentCapabilityRules.gd:apply_sample', '永久心抗', None),
        'local_add_weapon_power': ('consumed', 'game/sim/StatMagicRules.gd:prepare', '本战攻击增益', None),
        'local_add_defense': ('consumed', 'game/sim/StatMagicRules.gd:prepare', '本战防御增益', None),
    },
    'magic': {
        'code': ('consumed', 'tools/hsltools/data/skill_coverage.py:build', '魔法编号', None),
        'name': ('consumed', 'tools/hsltools/data/skill_coverage.py:build', '名字 id', None),
        'type': ('consumed', 'game/sim/SpecialDamageRules.gd:element_resistance', '属性', None),
        'range': ('consumed', 'game/sim/SkillTargetRules.gd:candidate_centers', '施法范围', None),
        'effect_range': ('consumed', 'game/sim/SkillTargetRules.gd:effect_cells', '效果范围', None),
        'expend': ('consumed', 'game/sim/SkillResourceRules.gd:amounts', 'MP 消耗', None),
        'damage': ('consumed', 'game/sim/NativeMagicRollRules.gd:roll', '伤害区间', None),
        'hit_ratio': ('consumed', 'game/sim/NativeMagicRollRules.gd:roll', '命中', None),
        'function': ('consumed', 'game/sim/SkillTargetRules.gd:function_mask', '功能位（magicFun_*）', None),
        'use_ratio': ('consumed', 'game/sim/AISkillPlanning.gd:choose', 'AI 使用概率', None),
        'effect_proc': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', 'eff_proc_Local／Global（特效镜头模式）', 'Local 在每个受影响格播放、Global 在光标格中心播放一次（0x442b58／0x442d81）'),
        'effect_code': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', 'EFFECTS 脚本编号', '39 段 effCode 脚本经 special_effect_scripts.json 编成 tick 时间线；144 个效果对象中 131 个按原生 effProc* 轨迹（effect_motion.json）运动，13 个仍未复原'),
        'status_hit_ratio': ('consumed', 'game/sim/StatusApplicationRules.gd:prepare', '状态命中', None),
        'effect_caster': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_caster', '施法者侧特效（8 行）', '架势结束后在施法者格建对象并等 N＋2 tick 再进受者阶段，Local 另多 1 次调用（0x442c4f／0x442f77）；镜头先滑到施法者是状态 0 对所有魔法做的，重制只给这 8 行补上'),
    },
    'special': {
        'code': ('consumed', 'tools/hsltools/data/skill_coverage.py:build', '绝技编号', None),
        'name': ('consumed', 'tools/hsltools/data/skill_coverage.py:build', '名字 id', None),
        'type': ('consumed', 'game/sim/SpecialDamageRules.gd:element_resistance', '属性', None),
        'range': ('consumed', 'game/sim/SkillTargetRules.gd:candidate_centers', '施放范围', None),
        'effect_range': ('consumed', 'game/sim/SkillTargetRules.gd:effect_cells', '效果范围', None),
        'expend': ('consumed', 'game/sim/SkillResourceRules.gd:amounts', '气力消耗', None),
        'damage': ('consumed', 'game/sim/SpecialDamageRules.gd:roll', '伤害区间', None),
        'hit_ratio': ('consumed', 'game/sim/SpecialDamageRules.gd:roll', '命中', None),
        'use_ratio': ('consumed', 'game/sim/AISkillPlanning.gd:choose', 'AI 使用概率', None),
        'function': ('consumed', 'game/sim/SkillTargetRules.gd:function_mask', '功能位', None),
        'attackpow_ratio': ('consumed', 'game/sim/SpecialDamageRules.gd:roll', '攻击力系数', None),
        'attack_code': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile', '攻方特效脚本（ANIMAL 程序）', None),
        'defense_code': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile', '守方特效脚本', None),
    },
    'range': {
        'code': ('consumed', 'tools/hsltools/data/attack_ranges.py:compile_ranges', '范围码', None),
        'size': ('consumed', 'tools/hsltools/data/attack_ranges.py:compile_ranges', '方阵边长', None),
        'data': ('consumed', 'tools/hsltools/data/attack_ranges.py:compile_ranges', '格值：>0 可达、≤0 不可（射击盲区为负）', '只取符号；值的大小（距离环）未消费，原 0x4100e0 用带符号值'),
    },
    'shapedef': {
        'code': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', 'SID', None),
        'hit': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '被击帧 SHP', None),
        'stand': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '站立帧 SHP', None),
        'stand_num': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '站立帧数', None),
        'walk_up': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '上行帧', None),
        'walk_up_num': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '上行帧数', None),
        'walk_down': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '下行帧', None),
        'walk_down_num': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '下行帧数', None),
        'walk_left': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '左行帧', None),
        'walk_left_num': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '左行帧数', None),
        'walk_right': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '右行帧', None),
        'walk_right_num': ('consumed', 'tools/hsltools/assets/combat_animation.py:build', '右行帧数', None),
        'use_magic': ('consumed', 'tools/hsltools/assets/job_casts.py:build', '施法帧', None),
        'use_magic_num': ('consumed', 'tools/hsltools/assets/job_casts.py:build', '施法帧数', None),
    },
    # EVEF actor instance words (level .BIN records, 0x42bd50 actor branch); status comes from
    # evef_instances.RUNTIME_APPLIED, so the two tables cannot drift.
    'evef_actor': {
        'items': ('consumed', 'game/sim/ActorInitializationRules.gd:apply_instance_words', '0x10..0x2C 八个实例物品 → 空槽', None),
        'gold': ('consumed', 'game/sim/BattleRewardRules.gd:kill_gold', 'idx 0 → live +0x98 击杀金钱覆盖', '1 单位（53 关记录 17，100，与 023 模板同值）；入场成长的金钱输入经 ReinforcementGrowthRules 同一读法'),
        'find_type': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 1', None),
        'find_flag': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 2', None),
        'find_range': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 3', None),
        'ai_call_range': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 4', None),
        'ai_fixed': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 5', None),
        'ai_check_dying': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 6', None),
        'ai_check_hp': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 7', None),
        'ai_help_otherhp': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 8', None),
        'ai_help_status': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 9', None),
        'ai_help_attack': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 10', None),
        'ai_lock': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 11', None),
        'ai_att_special': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 12', None),
        'ai_att_magic': ('consumed', 'game/sim/AINavigationRules.gd:instance_profile', 'idx 13', None),
        'wait_round': ('consumed', 'game/sim/AINavigationRules.gd:initialize', 'idx 14 → ai_wait_remaining', None),
        'fixed_point': ('consumed', 'game/sim/AINavigationRules.gd:approach_home', 'idx 15 → 守备锚点', None),
        'level_adjust_range': ('consumed', 'game/sim/ReinforcementGrowthRules.gd:prepare', 'idx 16（16 位）', '19／904 关 4 单位值 0x80000000 → 低字 0；原 16 位写同样得 0'),
        'level_adjust_disp_range': ('consumed', 'game/sim/ReinforcementGrowthRules.gd:prepare', 'idx 17（16 位）', None),
        'weapon': ('dead', None, 'idx 18 → +0xec（数据 0 单位）', None),
        'armor': ('dead', None, 'idx 19 → +0xf0（数据 0 单位）', None),
        'head': ('dead', None, 'idx 20 → +0xf4（数据 0 单位）', None),
        'foot': ('dead', None, 'idx 21 → +0xf8（数据 0 单位）', None),
        'other1': ('dead', None, 'idx 22 → +0xfc（数据 0 单位）', None),
        'other2': ('dead', None, 'idx 23 → +0x100（数据 0 单位）', None),
        'stamina': ('consumed', 'game/sim/ActorInitializationRules.gd:apply_instance_words', 'idx 24 → +0xe8 气力', None),
    },
    # EVEF non-actor records: which record words each object process carries (measured from the
    # original level .BIN, see evef_processes()).
    'evef_object': {
        'code': ('consumed', 'tools/hsltools/levels/seed.py:_placements', '+0x04 对象码（OBJ 表 join）', None),
        'x': ('consumed', 'tools/hsltools/levels/seed.py:_placements', '+0x08 像素 x', None),
        'y': ('consumed', 'tools/hsltools/levels/seed.py:_placements', '+0x0c 像素 y', None),
        'treasure_words': ('consumed', 'game/sim/TreasureRules.gd:initialize', '宝箱 0x10..0x2C 八个物品字', '28 关记录 33 有 13 个非零字（0x10..0x40）；原 0x42bd50 宝箱分支只读八个（static-derived, executed），尾部五个原版也丢'),
        'stand_object_words': ('dead', None, 'defProcStandObject／PlayerInstall／Cursor／BattleBOSS／combined 记录 0x10 以后的字', '148 关全部为 0——非演员 EVEF 记录只有 code／x／y'),
    },
    # OBJ-NNN.obs / global.obs [Object] fields: template offsets from load_obs_template 0x45dc5c
    # (static-derived, this packet); the actor constructor 0x407ec0 consumes six of them.
    'obj': {
        'obj_code': ('consumed', 'tools/hsltools/levels/seed.py:_object_lookup', '对象码', None),
        'obj_name': ('consumed', 'tools/hsltools/levels/seed.py:_placements', '对象名（模板 +0x34）', None),
        'obj_Mode': ('consumed', 'tools/hsltools/levels/map_objects.py:build', '模板 +0x00 显示模式（engADDCOLOR…）', None),
        'obj_Plane': ('consumed', 'tools/hsltools/levels/seed.py:_script_object_entry', '模板 +0x0c 图层', None),
        'obj_Shape_Name': ('consumed', 'tools/hsltools/levels/seed.py:_placements', 'SHP 资源', None),
        'obj_Shape_Number': ('consumed', 'tools/hsltools/levels/seed.py:_script_object_entry', '帧数', None),
        'obj_Shape_Delay': ('consumed', 'tools/hsltools/levels/seed.py:_script_object_entry', '模板 +0x7c 帧间隔', None),
        'obj_Process_Code': ('consumed', 'tools/hsltools/levels/seed.py:_role_for_object', '模板 +0x64 过程码', None),
        'obj_ReadShape': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '预读形体旗（loader 单独读）', '进 object_data_fields，无运行时读者'),
        'obj_Data': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x28 通用字', '进 object_data_fields'),
        'obj_Data1': ('dead', None, '模板 +0x8c（数据 0 行）', None),
        'obj_Data2': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x90（mapobjWaterMove 波幅等）', '进 object_data_fields'),
        'obj_Data3': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x94（mapobjMoveBGFlash level／DropRain delay…）', '进 object_data_fields'),
        'obj_Data4': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x98', '进 object_data_fields'),
        'obj_Data5': ('consumed', 'tools/hsltools/levels/battle.py:install_title_name', '模板 +0x9c；演员：低字 → live +0x1c 称号 id、高字 → +0x04 名字 id（0x407ec0）', 'R29：导入器写单位 `title`／`display_name`（display_name 为安装后 +0x04 逐字，portraits.panel_name，306 → ???），BattleVitals 状态面板读之；12 个已放置敌军（17 关 工人 062 1235×3、58／60／63 关 027 992×2、901 关 隊長 024 977×3）与 6／7 关脚本插入的 隊長 024 977；58／60／63 关未登记为战斗'),
        'obj_Data6': ('consumed', 'tools/hsltools/levels/story_scene.py:build', '模板 +0xa0；演员：SID 形体 token', 'S11：预览把 EVEF 演员绑到 token／序号（原 scenario.py:_story_cast 已随 52／53 并入通用路径删除）'),
        'obj_Data7': ('consumed', 'tools/hsltools/levels/story_scene.py:build', '模板 +0xa4；演员：PLAYERS 编号 → 0x44cb10 模板复制', 'S11：预览的 actor_id；battle.py 按 templates() 取审核过的源模板'),
        'obj_Data8': ('consumed', 'tools/hsltools/levels/battle.py:install_dead_message', '模板 +0xa8；演员：→ live +0x14 死亡台词字（−1 清零；两 id 可打包高低字）', 'R29：导入器按死亡分支 0x43ef91／0x4434b2 的读法解字写单位 `dead_message`（−1 → 空表＝静默），BattleAftermath 死亡对白读之，PLAYERS.dead_message 只在单位无此字时用；129 个已放置敌军（18 关：6／17／24／29／32／34／44／53／77／79／531／532／552／554／575／900／901／903）。脚本层 actSetDeadMessage 写同一字、后写者胜：R31 起 STORY 开场的写入由装配器 `script_dead_message` 落进单位（29 关 023 #1／#2 的 −1→1684／1686、队员 741…），WINFAIL 的由 `WinfailActions.write_dead_message` 在运行时写单位（6 关增援 隊長 957→969，同链插入后由 ScriptActorCreationRules 按序回放）'),
        'obj_Data9': ('consumed', 'tools/hsltools/levels/map_objects.py:build', '模板 +0xac；地图对象：mapobj* 类型；演员：≠0 时 pmPlayer↔pmEnemy 互换并置 +0xa0 bit 0x8（0x407ec0）', '演员分支 R22 由 battle.py:install_player_mode 读：112 个已放置敌军全是 pmPlayer 模板翻成 pmEnemy；脚本插入里有 pmEnemy→pmPlayer 方向（34 关 044、44 关 021 到场为友军）；bit 0x8 语义未追；R34：0x448840 的 hp_level 项按 live +0x28 P 位算——JobStatsRules.base_values 读 ActorRoleRules.side_mask（安装后的 player_mode，缺省按 role），互换成 pmEnemy 的 L1 023 = 28 HP（runtime-measured battle_053）'),
        'obj_X': ('dead', None, '地图管理员 obj_X（148 行）', '0x45dc5c 不读 obj_X／obj_Y（只有 obj_X1..Y2）'),
        'obj_Y': ('dead', None, '地图管理员 obj_Y（148 行）', '同上'),
        'obj_X1': ('consumed', 'tools/hsltools/levels/battle.py:install_player_mode', '模板 +0x10；演员：≠0 → live +0x28 阵营模式覆盖（pmNPC／pmPlayerEnemy／pmEnemy／pmPlayer）（0x407ec0）；特效对象：WAV', '102 个已放置敌军声明；81 个阵营与模板不同：pmNPC 39（7 关 21、21 关 13、57／531／532／533），pmPlayerEnemy 36（6 关 12、9 关 14、34 关 3、65 关 7 名村民），pmPlayer 6（900 关）；21 个 pmEnemy→pmEnemy 无变化。R22：导入器写单位 `player_mode`（放置与脚本插入同路），运行时 ActorRoleRules.side_mask 按位判敌我；特效对象的 WAV 值只随 object_data_fields 记录'),
        'obj_Y1': ('unconsumed', None, '模板 +0x14；演员：≠0 → live +0x134 低半字＝伴随对象码（0x407ec0）；特效：WAV；ObjectMove engRANGE：框上边', '22 行＝20 个效果对象 WAV（法术引用的 13 个由 special_effect_scripts.py:program_sounds 按 effProc 相位接入，R5-L2）＋逃出克萊恩城（LEVEL053）繩子框上边 464（重制按插入线裁切，同值）＋1 个演员：禁忌之魂・墳場地下（LEVEL080）怨念集合體 068 = 90 号 LevelUp_Star，0x43def0 每 20 tick（第 2 参非零时 8）经 0x415c10 在身边约 ±0x30×±0x10 随机抛 4 颗，重制未接（缺口 actor-companion-effect-object，docs/evidence_packets/static_reverse/original_unconsumed_fields.md）'),
        'obj_X2': ('consumed', 'tools/hsltools/data/special_effect_scripts.py:program_sounds', '模板 +0x18（效果对象第二 WAV，0x415d90 放一次；ObjectMove engRANGE：框右边）', '10 行均非演员：9 个效果对象 WAV，法术引用的 7 个由 program_sounds 接入（R5-L2），余 2 个无法术引用、从不生成；逃出克萊恩城（LEVEL053）繩子框右边 10000（屏外，无可见效果）'),
        'obj_Y2': ('unconsumed', None, '模板 +0x1c（ObjectMove engRANGE：框下边）', '1 行＝逃出克萊恩城（LEVEL053）繩子 800；0x4051d0 创建时 obj_Mode 带 0x1000000 才保留 +0x10..+0x1c（0x4052f1..0x4052fa）；上边 464 与重制插入线同值，下边 800 是否裁到图未核（provisional，docs/evidence_packets/static_reverse/original_unconsumed_fields.md）'),
        'obj_ZoomX': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x20 缩放', '进 object_data_fields'),
        'obj_ZoomY': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x24 缩放', '进 object_data_fields'),
        'obj_ShapeSub': ('dead', None, '模板 +0x2c（数据 0 行）', None),
        'obj_Collide_X1': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x68 碰撞框', '进 object_data_fields；运行时 hit-test 用自己的 footprint'),
        'obj_Collide_Y1': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x6c', None),
        'obj_Collide_X2': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x70', None),
        'obj_Collide_Y2': ('passthrough', 'tools/hsltools/levels/seed.py:_placements', '模板 +0x74', None),
        'obj_CollideX1': ('dead', None, '无下划线拼写（5 行推車）', 'loader 字段名不匹配，原版亦丢'),
        'obj_CollideY1': ('dead', None, '同上', None),
        'obj_CollideX2': ('dead', None, '同上', None),
        'obj_CollideY2': ('dead', None, '同上', None),
        'obj_Attribute': ('consumed', 'tools/hsltools/data/treasures.py:chest_hidden', '模板 +0x80 objattr* 旗（FLAG7／ATTACKFLAG）；宝箱：无 objattrATTACKFLAG 0x10000 → 0x415730 形状字 0xffff（隐藏宝物）', '226 行（176 地图对象、宝箱、特效）；只有宝箱模板保留（obj-028／obj-080 的 798 写 ATTACKFLAG＝可见，其余宝箱无此字段＝隐藏），生成器写 treasures `hidden`，BattleTreasurePresentation 不画隐藏箱；地图对象与特效的值导入器仍不保留（站立物件的固定图层语义见绘制顺序包）'),
        'obj_Score': ('consumed', 'game/battle/runtime/MapObjectDrift.gd:add_background', '模板 +0x84；地图对象 mapobj 参数（x range／level）', 'CLOUDDRIFT：mapobjMoveBG 的横向视差 x = x0 + trunc((镜头x − x0)·score/640)，−1 钉画面（0x43d4c1，original_map_object_drift.md）；导入器对 mapobjMoveBG 与 mapobjFlash 保留；MAPFLASH：mapobjFlash 的 score 是变暗级数（0x43cee7，original_map_object_flash.md，MapObjectFlash.gd 读）'),
        'obj_HitPoint': ('consumed', 'tools/hsltools/levels/battle.py:_apply_object_install', '模板 +0x88；演员：≠0 → live +0x1b6 HP 加值半字 +=（0x407ec0，在 refresh 前）；地图对象：mapobj 参数（delay／y range）', '46 个已放置敌军：024 +50（25）、023 +20（18）、024 +30（3）。R22：加进单位 growth_profile.source.hit_point 与 max_hp／hp（`object_hit_point`），脚本插入的 024 隊長 +30／+50 同路；地图对象：mapobjMoveBG 的纵向视差 /480 由 MapObjectDrift.add_background 读（CLOUDDRIFT），其余 mapobj 的值不保留'),
        'obj_mode': ('dead', None, '小写拼写（1 行）', 'loader 按名字大小写匹配，原版亦丢'),
    },
    # WRD terrain (hsltools/sources/wrd.py, hsl_wrd_terrain.v2)
    'wrd': {
        'magic': ('consumed', 'tools/hsltools/sources/wrd.py:decode_wrd', '"WORL"', None),
        'version': ('passthrough', 'tools/hsltools/sources/wrd.py:decode_wrd', '版本（全部 3）', None),
        'flags': ('passthrough', 'tools/hsltools/sources/wrd.py:decode_wrd', '头旗（全部 0）', None),
        'width': ('consumed', 'game/sim/WrdTerrainTiles.gd:load_tiles', '格宽', None),
        'height': ('consumed', 'game/sim/WrdTerrainTiles.gd:load_tiles', '格高', None),
        'element_size': ('consumed', 'tools/hsltools/sources/wrd.py:decode_wrd', '4', None),
        't': ('passthrough', 'game/sim/WrdTerrainTiles.gd:load_tiles', 'bits 0..23 tile id → tiles[].tile_id', '无运行时读者；地图用整幅 SHP 绘制，tile 索引不用于绘制或规则'),
        'h': ('consumed', 'game/sim/ActorTraversalRules.gd:height_delta', 'bits 24..31 源高度（0xff 悬崖；高差 >2 阻地面）', '值域 0..21／255；命中／伤害公式（0x409a60／0x409be0）无地形项 → 地形防御／回避加成 negative-evidence'),
        'b': ('consumed', 'game/sim/WrdTerrainTiles.gd:load_tiles', 'h==255 派生旗', None),
    },
    # Live actor record (0x1fc stride, original_save_format.md): remake unit-dict counterpart.
    'actor_record': {
        'code': ('consumed', SAVE, '+0x00 PLAYERS 编号', None),
        'name_id': ('consumed', SAVE, '+0x04 名字 id', None),
        'sound_walk_dead': ('consumed', SAVE, '+0x08 WAV 句柄对', None),
        'sound_miss_attack': ('consumed', SAVE, '+0x0c WAV 句柄对', None),
        'sound_hit_walkwater': ('passthrough', SAVE, '+0x10 WAV 句柄对', '生成器复制；运行时无被击音，水行音走 walk_water_rows'),
        'dead_message': ('consumed', SAVE, '+0x14 死亡台词字', None),
        'job': ('consumed', SAVE, '+0x18', None),
        'job_show_name': ('consumed', SAVE, '+0x1c', None),
        'class_shoothit': ('passthrough', SAVE, '+0x20 class 字／+0x22 射击命中 WAV', None),
        'mode': ('consumed', SAVE, '+0x28 阵营模式', None),
        'size_carry': ('consumed', SAVE, '+0x2c size_type／carry_item', None),
        'str': ('consumed', SAVE, '+0x4c 工作力量', None),
        'dex': ('consumed', SAVE, '+0x50', None),
        'mind': ('consumed', SAVE, '+0x54', None),
        'con': ('consumed', SAVE, '+0x58', None),
        'face': ('consumed', SAVE, '+0x5c 头像句柄', None),
        'job_up_code': ('consumed', SAVE, '+0x60', None),
        'base_str': ('consumed', SAVE, '+0x64 基础力量（成长写入）', None),
        'base_dex': ('consumed', SAVE, '+0x68', None),
        'base_mind': ('consumed', SAVE, '+0x6c', None),
        'base_con': ('consumed', SAVE, '+0x70', None),
        'cap_str': ('consumed', 'tools/hsltools/model/jobs.py:calculate', '+0x74 属性上限', None),
        'cap_dex': ('consumed', 'tools/hsltools/model/jobs.py:calculate', '+0x78', None),
        'cap_mind': ('consumed', 'tools/hsltools/model/jobs.py:calculate', '+0x7c', None),
        'cap_con': ('consumed', 'tools/hsltools/model/jobs.py:calculate', '+0x80', None),
        'install_code': ('consumed', 'game/sim/ScriptActorCreationRules.gd:_apply_status', '+0x84 脚本寻址 id', '原版 0x451155（actChangePrevInsertObjectID）写、0x44fa80 返回、0x44fad0 按它找对象；0x407cc0 另在 0x407d94 按对象 +0xa2 经 11 项跳表 0x407e8c 给新建演员写默认码 0..8（末两项与首两项同目标）；改号一路由 _apply_status 记进 actor_bindings、按 SID token 寻址，效果等价；默认码 0..8 在重制里的对应待核'),
        'exp': ('consumed', SAVE, '+0x88', None),
        'exp_threshold': ('consumed', 'game/sim/ProgressionRules.gd:exp_to_next', '+0x8c 升级阈值', None),
        'kill_exp': ('consumed', SAVE, '+0x90', None),
        'gold': ('consumed', SAVE, '+0x98 击杀金钱', None),
        'level': ('consumed', SAVE, '+0x9c', None),
        'capability_flags': ('consumed', SAVE, '+0xa0 能力位（move_fly／no_attack／…；bit 0x8 由 0x407ec0 阵营互换置位，语义未追）', None),
        'defense': ('consumed', SAVE, '+0xb4 工作防御', None),
        'speed': ('consumed', SAVE, '+0xb8', None),
        'hit_ratio': ('consumed', SAVE, '+0xbc', None),
        'attack': ('consumed', SAVE, '+0xc0', None),
        'weapon_magic_type': ('consumed', SAVE, '+0xc4', None),
        'magic_attack': ('consumed', SAVE, '+0xd0', None),
        'hp': ('consumed', SAVE, '+0xd8', None),
        'max_hp': ('consumed', SAVE, '+0xdc', None),
        'mp': ('consumed', SAVE, '+0xe0', None),
        'max_mp': ('consumed', SAVE, '+0xe4', None),
        'stamina': ('consumed', SAVE, '+0xe8', None),
        'weapon': ('consumed', SAVE, '+0xec', None),
        'head': ('consumed', SAVE, '+0xf0', None),
        'armor': ('consumed', SAVE, '+0xf4', None),
        'foot': ('consumed', SAVE, '+0xf8', None),
        'other1': ('consumed', SAVE, '+0xfc', None),
        'other2': ('consumed', SAVE, '+0x100', None),
        'resist_work': ('consumed', SAVE, '+0x104 五个工作抗性', None),
        'resist_base': ('consumed', SAVE, '+0x118 五个基础抗性', None),
        'move_work': ('consumed', SAVE, '+0x12c', None),
        'move': ('consumed', SAVE, '+0x130', None),
        'job_up_flags': ('consumed', SAVE, '+0x134 转职旗（0x407ec0 亦以 obj_Y1 覆写）', None),
        'items': ('consumed', SAVE, '+0x138 八槽', None),
        'special_words': ('consumed', SAVE, '+0x158 七个绝技位字', None),
        'magic_words': ('consumed', SAVE, '+0x174 六个魔法位字', None),
        'effect_flags': ('consumed', SAVE, '+0x18c 装备效果位（0x448420）', None),
        'add_steal': ('consumed', 'game/sim/ProgressionRules.gd:refresh_growth_stats', '+0x194 偷窃加成字（→ +0x196 工作字，默认 12）', 'combat_profile.base_steal_ratio／steal_ratio；见 PLAYERS.steal_ratio'),
        'add_avoid': ('consumed', SAVE, '+0x198／+0x19a 回避', None),
        'add_attack_back': ('consumed', SAVE, '+0x19c／+0x19e 反击', None),
        'add_damagex2': ('consumed', SAVE, '+0x1a0／+0x1a2 暴击', None),
        'add_attack': ('consumed', SAVE, '+0x1a4', None),
        'add_magic': ('consumed', SAVE, '+0x1a8', None),
        'add_defense': ('consumed', SAVE, '+0x1ac', None),
        'add_speed': ('consumed', SAVE, '+0x1b0', None),
        'add_mp_hp': ('consumed', SAVE, '+0x1b4 MP／+0x1b6 HP 加值半字（obj_HitPoint 加在这里）', None),
        'wait_round': ('consumed', 'game/sim/AINavigationRules.gd:initialize', '+0x1b8 等待回合', None),
        'find_type': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '+0x1c0', None),
        'find_flag': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '+0x1c4', None),
        'find_range': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', '+0x1c8', None),
        'ai_call_range': ('consumed', 'game/sim/AINavigationRules.gd:guard_allows', '+0x1cc', None),
        'ai_fixed': ('consumed', 'game/sim/AINavigationRules.gd:guard_allows', '+0x1d0', None),
        'ai_check_dying': ('consumed', 'game/sim/AIPriorityRules.gd:choose_check', '+0x1d4', None),
        'ai_check_hp': ('consumed', 'game/sim/AIPriorityRules.gd:choose_check', '+0x1d8', None),
        'ai_help_otherhp': ('consumed', 'game/sim/AISupportRules.gd:next_check', '+0x1dc', None),
        'ai_help_status': ('consumed', 'game/sim/AISupportRules.gd:next_check', '+0x1e0', None),
        'ai_help_attack': ('consumed', 'game/sim/AISupportRules.gd:next_check', '+0x1e4', None),
        'ai_lock': ('consumed', 'game/sim/AINavigationRules.gd:acquire', '+0x1e8', None),
        'ai_att_special': ('consumed', 'game/sim/AIDecisionRules.gd:select_action', '+0x1ec', None),
        'ai_att_magic': ('consumed', 'game/sim/AIDecisionRules.gd:select_action', '+0x1f0', None),
        'level_adjust': ('consumed', 'game/sim/ReinforcementGrowthRules.gd:prepare', '+0x1f8／+0x1fa 调级半字', None),
    },
    # Script-global headers: define groups (prefix) rather than single symbols.
    'defines': {
        'EXTRAS.H SID_*': ('consumed', 'tools/hsltools/levels/story_scene.py:build', '九名主角的 SID 形体编号', None),
        'EXTRAS.H town_*': ('consumed', 'game/sim/TownEventRules.gd:_town_arg', '城镇编号符号', None),
        'ANIMAL.H aniK*': ('passthrough', 'tools/hsltools/assets/animal_programs.py:build', '演员动作方向键（aniKStop／Right／Left）', '进 animal_programs.json k_action；运行时不读'),
        'ANIMAL.H ani* (opcodes)': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile', 'ANIMAL 程序 opcode 表（见 animal 表逐条）', None),
        'TYPE.H mapobj*': ('consumed', 'tools/hsltools/levels/map_objects.py:build', '地图对象类型', None),
        'TYPE.H magic* (elements)': ('consumed', 'game/sim/SpecialDamageRules.gd:element_resistance', '属性与双属性组合', None),
        'TYPE.H magicCode*': ('consumed', 'tools/hsltools/data/skill_coverage.py:build', '技能编号', None),
        'TYPE.H magicFun_*': ('consumed', 'game/sim/SkillTargetRules.gd:function_mask', '功能位', None),
        'TYPE.H pm*': ('consumed', 'game/sim/WinfailActions.gd:_player_mode_arg', '阵营模式常量', None),
        'TYPE.H job*': ('consumed', 'tools/hsltools/model/jobs.py:source_profile', '职业码', None),
        'TYPE.H class*': ('consumed', 'tools/hsltools/assets/panel_assets.py:definitions', '种族码', '见 PLAYERS.class：只作显示'),
        'TYPE.H AI_*／AIF_*': ('consumed', 'game/sim/AIDecisionRules.gd:select_target', 'find_type／find_flag 常量', None),
        'TYPE.H itemType*／itemIcon*': ('consumed', EQ, '物品类型与图标', None),
        'TYPE.H bm*／gameBM*': ('consumed', 'game/sim/TownEventRules.gd:_world_bm_set_mode', '大地图点／线模式', None),
        'TYPE.H eng*': ('consumed', 'tools/hsltools/levels/map_objects.py:build', '显示模式（engADDCOLOR…）', None),
        'TYPE.H effProc*': ('consumed', 'tools/hsltools/probes/effect_motion.py:table_defines', '效果对象程序码（obj_Data9，跳表 0x4231b0）', '经探针 effect_motion.table_defines 按名字解出程序号（PROCESS.DEF 优先、TYPE.H 同名被遮），EffectObjectMotion 放记录'),
        'TYPE.H objattr*': ('dead', None, 'obj_Attribute 旗', 'TYPE.H 无 objattr 定义（0 条）；objattr* 在 PROCESS.DEF，见 obj.obj_Attribute'),
        'TYPE.H other': ('unconsumed', None, '其余 13 条 #define（gameBigMapLevel／gameTempResourceID／gameover*／bmpm*／effSMOKE）', '按需消费，未逐一登记'),
    },
}

# Opcode tables: token -> (status, consumer, semantics, note) only for the exceptions; the bulk
# status is derived from the interpreter constants and reported per token.
EFFECTS_OPCODES = {
    'effWait': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', '[counter] 等待', '169 段 [effect] = 130 段 specCode（绝技，ani*）＋ 39 段 effCode（魔法，eff*）；四个 eff* 全部解释，60 tick/s 时钟 provisional'),
    'effInsertObject': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', '[code][x disp][y disp]', '位移相对效果原点（受影响格）；有原生轨迹的对象按 effect_motion.json 逐帧运动，其余按 shape_number×(shape_delay+1) 至少 48 tick 后淡出'),
    'effInsertRandomObject': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', '[code][x disp][y disp][x range][y range][delay range][number]', '偏移为 rand(范围) 折进 (−范围/2, 范围/2]、延迟逐个累加 rand(延迟范围)（解释器 0x423873／0x423951）'),
    'effPlaySound': ('consumed', 'game/battle/scene/SkillEffectScriptPlayer.gd:compile_effect', '[code]', None),
}

# The ranked suspects: (table, field, priority, what the player would notice, reproduction).
SUSPECTS = (
)


# --- measured -----------------------------------------------------------------------------

def _read_json(root: Path, relative: str) -> dict:
    return json.loads((root / relative).read_text(encoding='utf-8'))


def ini_table(root: Path, filename: str, section: str) -> tuple[int, dict[str, dict]]:
    """Columns of an INI-like original table with the number of rows declaring them and the
    number carrying a non-default value; column order is first appearance."""
    rows = blocks((root / TABLES / filename).read_bytes(), section)
    declared: Counter[str] = Counter()
    nondefault: Counter[str] = Counter()
    order: list[str] = []
    for row in rows:
        for key, value in row.items():
            if key not in declared:
                order.append(key)
            declared[key] += 1
            if value.strip() not in DEFAULT_VALUES:
                nondefault[key] += 1
    return len(rows), {key: {'rows_declared': declared[key], 'rows_nondefault': nondefault[key]} for key in order}


def seed_paths(root: Path) -> list[Path]:
    return sorted((root / SEEDS).glob('battle[0-9][0-9][0-9]_seed.json'))


def evef_actor_words(root: Path) -> dict[str, dict]:
    """Per instance word: units carrying it and levels, from the evef_instances table."""
    table = evef_instances_table()
    units: Counter[str] = Counter()
    levels: dict[str, set] = {}
    for level, entry in table['levels'].items():
        for unit in entry['units']:
            names = list(unit.get('overrides', {})) + (['items'] if unit.get('items') else [])
            for name in names:
                units[name] += 1
                levels.setdefault(name, set()).add(int(level))
    fields = {}
    for name in ['items'] + list(ACTOR_INSTANCE_OVERRIDE_FIELDS.values()):
        fields[name] = {'units': units.get(name, 0), 'levels': sorted(levels.get(name, ()))}
    return fields


def evef_processes(root: Path) -> dict[str, dict]:
    """Placed EVEF records per object process (from the tracked seeds) and the record keys the
    seed retains for them."""
    processes: Counter[str] = Counter()
    retained: dict[str, set] = {}
    for path in seed_paths(root):
        seed = json.loads(path.read_text(encoding='utf-8'))
        for record in seed['placements']['records']:
            process = record.get('object_process') or ('combined' if 'combined_object_index' in record else 'unmatched')
            processes[process] += 1
            retained.setdefault(process, set()).update(key for key in ('treasure_words', 'actor_instance') if key in record)
    return {process: {'records': count, 'decoded_words': sorted(retained[process])} for process, count in sorted(processes.items())}


# Object table field census of the 148 level .obs + global.obs (measured once from the original
# PAK on 2026-09-22 with the loader field list of 0x45dc5c; the seeds keep only the obj_Data* /
# obj_Collide_* / obj_Mode / obj_X / obj_Y / obj_ReadShape / obj_Zoom* subset, so the census of
# the dropped columns cannot be re-derived from tracked data). rows = [Object] blocks declaring
# the field; placed_actor_rows = defProcEnemy placements whose object declares it.
OBJ_FIELD_CENSUS = {
    'obj_code': 13419, 'obj_name': 13419, 'obj_Plane': 13419, 'obj_Shape_Name': 13419, 'obj_Shape_Number': 13419,
    'obj_Process_Code': 13419, 'obj_ReadShape': 3800, 'obj_Shape_Delay': 1245, 'obj_Mode': 251, 'obj_mode': 1,
    'obj_X': 148, 'obj_Y': 148, 'obj_X1': 99, 'obj_Y1': 22, 'obj_X2': 10, 'obj_Y2': 1, 'obj_ZoomX': 24, 'obj_ZoomY': 24,
    'obj_Data': 44, 'obj_Data1': 0, 'obj_Data2': 107, 'obj_Data3': 3580, 'obj_Data4': 147, 'obj_Data5': 317, 'obj_Data6': 3967,
    'obj_Data7': 958, 'obj_Data8': 3077, 'obj_Data9': 7620, 'obj_ShapeSub': 0,
    'obj_Collide_X1': 1096, 'obj_Collide_Y1': 1096, 'obj_Collide_X2': 1096, 'obj_Collide_Y2': 1096,
    'obj_CollideX1': 5, 'obj_CollideY1': 5, 'obj_CollideX2': 5, 'obj_CollideY2': 5,
    'obj_Attribute': 226, 'obj_Score': 55, 'obj_HitPoint': 96,
}
OBJ_PLACED_ACTOR_ROWS = {'obj_X1': 102, 'obj_HitPoint': 46, 'obj_Data8': 129, 'obj_Data5': 12, 'obj_Data9': 112, 'obj_Y1': 1}
OBJ_CENSUS_NOTE = ('resource-derived census of 148 level obj-NNN.obs + global.obs read once from hsl.pak (13,419 [Object] blocks); '
                   'the loader field list is static-derived from load_obs_template 0x45dc5c, the actor consumption from 0x407ec0. '
                   'Re-measure with PYTHONPATH=tools python3 -m hsltools.checks.field_coverage --census (needs the original PAK).')


def wrd_fields(root: Path) -> dict[str, dict]:
    files = sorted((root / TERRAIN).glob('level[0-9][0-9][0-9]_terrain.json'))
    heights: Counter[int] = Counter()
    versions: Counter[int] = Counter()
    flags: Counter[int] = Counter()
    cells = 0
    for path in files:
        terrain = json.loads(path.read_text(encoding='utf-8'))
        form = terrain['source_format']
        versions[int(form['version'])] += 1
        flags[int(form['flags'])] += 1
        for row in terrain['grid']:
            for cell in row:
                heights[int(cell['h'])] += 1
                cells += 1
    return {
        'files': len(files), 'cells': cells,
        'fields': {
            'magic': {'values': ['WORL']}, 'version': {'values': sorted(versions)}, 'flags': {'values': sorted(flags)},
            'width': {}, 'height': {}, 'element_size': {'values': [4]},
            't': {'cells': cells}, 'h': {'distinct_values': sorted(heights), 'cells_nonzero': cells - heights[0], 'cells_cliff': heights[255]},
            'b': {'cells_true': heights[255]},
        },
    }


def actor_record_fields() -> dict[str, dict]:
    fields = {name: {'offset': f'0x{offset:x}'} for name, offset in REC.items()}
    for name, offset in (('wait_round', 0x1B8), ('find_type', 0x1C0), ('find_flag', 0x1C4), ('find_range', 0x1C8), ('ai_call_range', 0x1CC),
                         ('ai_fixed', 0x1D0), ('ai_check_dying', 0x1D4), ('ai_check_hp', 0x1D8), ('ai_help_otherhp', 0x1DC),
                         ('ai_help_status', 0x1E0), ('ai_help_attack', 0x1E4), ('ai_lock', 0x1E8), ('ai_att_special', 0x1EC),
                         ('ai_att_magic', 0x1F0), ('level_adjust', 0x1F8)):
        fields[name] = {'offset': f'0x{offset:x}'}
    return fields


DEFINE_GROUPS = (
    ('EXTRAS.H SID_*', 'EXTRAS.H', r'SID_'), ('EXTRAS.H town_*', 'EXTRAS.H', r'town_'),
    ('ANIMAL.H aniK*', 'ANIMAL.H', r'aniK'), ('ANIMAL.H ani* (opcodes)', 'ANIMAL.H', r'ani(?!K)'),
    ('TYPE.H mapobj*', 'TYPE.H', r'mapobj'), ('TYPE.H magic* (elements)', 'TYPE.H', r'magic(?!Code|Fun_)'),
    ('TYPE.H magicCode*', 'TYPE.H', r'magicCode'), ('TYPE.H magicFun_*', 'TYPE.H', r'magicFun_'),
    ('TYPE.H pm*', 'TYPE.H', r'pm[A-Z]'), ('TYPE.H job*', 'TYPE.H', r'job[A-Z]'), ('TYPE.H class*', 'TYPE.H', r'class[A-Z]'),
    ('TYPE.H AI_*／AIF_*', 'TYPE.H', r'AI_|AIF_'), ('TYPE.H itemType*／itemIcon*', 'TYPE.H', r'itemType|itemIcon'),
    ('TYPE.H bm*／gameBM*', 'TYPE.H', r'bm[A-Z]|gameBM'), ('TYPE.H eng*', 'TYPE.H', r'eng[A-Z]'), ('TYPE.H effProc*', 'TYPE.H', r'effProc'),
    ('TYPE.H objattr*', 'TYPE.H', r'objattr'),
)
DEFINE = re.compile(r'^\s*#define\s+(\S+)\s+(\S+)', re.M)


def define_groups(root: Path) -> dict[str, dict]:
    names: dict[str, list[str]] = {}
    for header in ('EXTRAS.H', 'ANIMAL.H', 'TYPE.H'):
        text = (root / TABLES / header).read_bytes().decode('cp950', 'replace')
        names[header] = [match.group(1) for match in DEFINE.finditer(text)]
    result: dict[str, dict] = {}
    claimed: dict[str, set] = {header: set() for header in names}
    for group, header, pattern in DEFINE_GROUPS:
        matched = [name for name in names[header] if re.match(pattern, name) and name not in claimed[header]]
        claimed[header].update(matched)
        result[group] = {'defines': len(matched), 'examples': matched[:4]}
    rest = [name for name in names['TYPE.H'] if name not in claimed['TYPE.H']]
    result['TYPE.H other'] = {'defines': len(rest), 'examples': rest[:6]}
    return result


def gd_string_list(source: str, name: str) -> list[str]:
    """String literals of `const NAME := [...]` / `const NAME: Array[String] = [...]`."""
    match = re.search(r'^const %s\b[^=\n]*=\s*\[(.*?)^\]' % re.escape(name), source, re.S | re.M)
    if match is None:
        match = re.search(r'^const %s\b[^=\n]*=\s*\[(.*?)\]' % re.escape(name), source, re.S | re.M)
    if match is None:
        raise ValueError(f'constant {name} not found')
    return re.findall(r'"([^"]+)"', re.sub(r'#[^\n]*', '', match.group(1)))


def gd_handler_table(source: str, name: str) -> dict[str, str]:
    """Token → handler function of a GDScript dispatch table: `static var NAME := {"tok": _fn}`
    (Callables) or `const NAME := {"tok": &"_fn"}` (method names)."""
    match = re.search(r'^(?:const|static var) %s\b[^=\n]*=\s*\{(.*?)^\}' % re.escape(name), source, re.S | re.M)
    if match is None:
        raise ValueError(f'handler table {name} not found')
    return dict(re.findall(r'"([^"]+)":\s*&?"?(\w+)"?', re.sub(r'#[^\n]*', '', match.group(1))))


def story_opcodes(root: Path) -> dict[str, dict]:
    coverage = _read_json(root, STORY_COVERAGE)
    source = (root / OPENING_COORDINATOR).read_text(encoding='utf-8')
    record_only = set(gd_string_list(source, 'RECORD_ONLY_KINDS'))
    handlers = gd_handler_table(source, 'EVENT_HANDLERS')
    quoted = set(re.findall(r'"([a-z_0-9]+)"', source))
    fields = {}
    for token, info in coverage['tokens'].items():
        kind = info.get('compiler_kind')
        if info['story_occurrences'] == 0 and not (info.get('mapped') and kind in quoted and kind not in record_only):
            status = 'dead'  # no STORY script uses it (winfail-only conditions live in the winfail table)
        elif not info.get('mapped') or not kind:
            status = 'unconsumed'
        elif kind in record_only:
            status = 'recorded'
        elif kind in quoted:
            status = 'consumed'
        else:
            status = 'unconsumed'
        fields[token] = {'opcode': info['opcode'], 'arg_doc': info.get('arg_doc', ''), 'occurrences': info['story_occurrences'],
                         'levels': info['story_level_count'], 'compiler_kind': kind, 'status': status,
                         'consumer': f'{OPENING_COORDINATOR}:{handlers.get(kind, "_apply_event")}' if status == 'consumed' else (f'{OPENING_COORDINATOR}:RECORD_ONLY_KINDS' if status == 'recorded' else None)}
    return fields


def winfail_opcodes(root: Path) -> dict[str, dict]:
    coverage = _read_json(root, WINFAIL_COVERAGE)
    sets = coverage['support_sets']
    conditions = set(sets['SUPPORTED_CONDITIONS'])
    applied = conditions | set(sets['APPLIED_ACTIONS'])
    world_flags = set(sets['WORLD_FLAG_ACTIONS'])
    recorded = world_flags | set(sets['PRESENTATION_ACTIONS'])
    totals = coverage['totals']['token_totals']
    handlers = gd_handler_table((root / WINFAIL_ACTIONS).read_text(encoding='utf-8'), 'ACTION_HANDLERS')
    # Script tokens match case-insensitively (WINFAIL002 spells actMEssage once):
    # WinfailCompiler.canonical_action folds a respelling onto the supported name.
    spellings = {name.lower(): name for name in applied | recorded}
    fields = {}
    for token in sorted(set(totals) | applied | recorded, key=lambda name: (-totals.get(name, 0), name)):
        name = token if token in applied | recorded else spellings.get(token.lower(), token)
        status = 'consumed' if name in applied else 'recorded' if name in recorded else 'unconsumed'
        if name != token:
            consumer = 'game/sim/WinfailCompiler.gd:canonical_action'
        elif token in conditions:
            consumer = 'game/sim/WinfailConditions.gd:condition_holds'
        elif token in applied:
            consumer = f'{WINFAIL_ACTIONS}:{handlers.get(token, "apply_actions")}'
        elif token in world_flags:
            consumer = 'game/sim/WinfailCompiler.gd:WORLD_FLAG_ACTIONS'
        elif token in recorded:
            consumer = 'game/sim/WinfailCompiler.gd:PRESENTATION_ACTIONS'
        else:
            consumer = None
        fields[token] = {'occurrences': totals.get(token, 0), 'status': status, 'consumer': consumer}
    return fields


def town_opcodes(root: Path) -> dict[str, dict]:
    towndef = _read_json(root, TOWNDEF)
    source = (root / TOWN_RULES).read_text(encoding='utf-8')
    supported = set(gd_string_list(source, 'SUPPORTED_TOKENS'))
    recorded = set(gd_string_list(source, 'RECORDED_ONLY_TOKENS'))
    handlers = gd_handler_table(source, 'WORLD_TOKEN_HANDLERS') | gd_handler_table(source, 'STEP_HANDLERS')
    usage = towndef['statistics']['token_usage']
    fields = {}
    for token, opcode in towndef['token_ids'].items():
        status = 'consumed' if token in supported else 'recorded' if token in recorded else 'unconsumed'
        if usage.get(token, 0) == 0 and status != 'consumed':
            status = 'dead'
        fields[token] = {'opcode': opcode, 'occurrences': usage.get(token, 0), 'status': status,
                         'consumer': f'{TOWN_RULES}:{handlers.get(token, "_step")}' if status == 'consumed' else (f'{TOWN_RULES}:RECORDED_ONLY_TOKENS' if status == 'recorded' else None)}
    return fields


def animal_opcodes(root: Path) -> dict[str, dict]:
    """ANIMAL.H ani* opcodes by channel: `action` (the ordinary strike program, 66 actors — bound
    by the combat_animation importer into the manifest `dispatch` the cut-in plays), `s_action`
    (the 絶技 caster's lead, interpreted by AnimalCastLead), `m_action` (the magic caster's lead:
    the same program shape over the imported m_shape strips, AnimalCastLead through the map magic
    presenter — R31) and `effect` (the EFFECTS.TXT specCode scripts SkillEffectScriptPlayer plays). An opcode is
    consumed only when every channel that uses it has its interpreter; otherwise the note names
    the channels left."""
    programs = _read_json(root, ANIMAL_PROGRAMS)
    effects = _read_json(root, SPECIAL_EFFECTS)
    implemented = set(gd_string_list((root / EFFECT_PLAYER).read_text(encoding='utf-8'), 'IMPLEMENTED_OPCODES'))
    cast_implemented = set(gd_string_list((root / CAST_LEAD).read_text(encoding='utf-8'), 'CAST_OPCODES'))
    usage_by_channel: dict[str, Counter] = {'action': Counter(), 's_action': Counter(), 'm_action': Counter()}
    for record in programs['records']:
        for channel, program in record['programs'].items():
            usage_by_channel[channel].update(instruction['op'] for instruction in program)
    effect_usage = effects['opcode_counts']
    channels = (('action', usage_by_channel['action'], set(ACTION_OPCODES), f'{COMBAT_ANIMATION}:compile_action'),
                ('s_action', usage_by_channel['s_action'], cast_implemented, f'{CAST_LEAD}:compile'),
                ('m_action', usage_by_channel['m_action'], cast_implemented, f'{CAST_LEAD}:compile'),
                ('effect', effect_usage, implemented, f'{EFFECT_PLAYER}:compile'))
    fields = {}
    for name, definition in programs['opcode_definitions'].items():
        consumers, missing, total = [], [], 0
        for channel, usage, supported, consumer in channels:
            count = usage.get(name, 0)
            total += count
            if count and name in supported:
                if consumer not in consumers:
                    consumers.append(consumer)
            elif count:
                missing.append(channel)
        if total == 0:
            status = 'dead'
        elif missing:
            status = 'unconsumed'
        else:
            status = 'consumed'
        opcode = definition.get('value', definition.get('opcode')) if isinstance(definition, dict) else definition
        parameters = definition.get('parameters', []) if isinstance(definition, dict) else []
        fields[name] = {'opcode': opcode, 'action_program_occurrences': usage_by_channel['action'].get(name, 0),
                        's_action_program_occurrences': usage_by_channel['s_action'].get(name, 0), 'm_action_program_occurrences': usage_by_channel['m_action'].get(name, 0),
                        'skill_effect_occurrences': effect_usage.get(name, 0), 'occurrences': total, 'status': status,
                        'consumer': ' + '.join(consumers) if consumers and not missing else None,
                        'semantics': ''.join(f'[{parameter}]' for parameter in parameters) or '—'}
        if missing:
            # Partly interpreted: the vocabulary has no partial status, so the field stays
            # unconsumed (no consumer) and the note names both sides.
            fields[name]['note'] = ('已解释通道的消费点：' + ' + '.join(consumers) + '；' if consumers else '') + '无解释器的通道：' + '／'.join(missing)
    return fields


def effects_opcodes(root: Path) -> dict[str, dict]:
    text = (root / EFFECTS_TXT).read_bytes().decode('cp950', 'replace')
    action_lines = '\n'.join(line for line in text.splitlines() if re.match(r'^\s*action\s*=', line))
    usage = Counter(re.findall(r'\b(eff[A-Z][A-Za-z]+)\b', action_lines))
    blocks_count = text.count('[effect]')
    header = (root / TABLES / 'effects.h').read_bytes().decode('cp950', 'replace')
    opcodes = {match.group(1): int(match.group(2)) for match in re.finditer(r'^\s*#define\s+(eff[A-Z]\w+)\s+(\d+)', header, re.M)
               if not match.group(1).startswith('effCode')}  # effCode01.. are [effect] block ids, not opcodes
    fields = {}
    for name, opcode in opcodes.items():
        status, consumer, semantics, note = EFFECTS_OPCODES[name]
        fields[name] = {'opcode': opcode, 'occurrences': usage.get(name, 0), 'effect_blocks': blocks_count, 'status': status,
                        'consumer': consumer, 'semantics': semantics, 'note': note}
    return fields


# --- assembly -----------------------------------------------------------------------------

SYMBOL_PATTERNS = {
    '.gd': (r'^\s*(?:static\s+)?func\s+{name}\s*\(', r'^\s*const\s+{name}\b', r'^\s*var\s+{name}\b'),
    '.py': (r'^\s*def\s+{name}\s*\(', r'^\s*class\s+{name}\b', r'^{name}\s*[:=]'),
}


def citation_error(root: Path, citation: str) -> str | None:
    """None when `path:symbol` names an existing file that defines the symbol; a field with
    several consumers lists them as `path:symbol + path:symbol`, each validated."""
    if ' + ' in citation:
        for part in citation.split(' + '):
            error = citation_error(root, part)
            if error:
                return error
        return None
    path, _, symbol = citation.rpartition(':')
    if not path or not symbol:
        return f'{citation!r}: expected path:symbol'
    target = root / path
    if not target.is_file():
        return f'{citation!r}: {path} does not exist'
    patterns = SYMBOL_PATTERNS.get(target.suffix)
    if patterns is None:
        return f'{citation!r}: unsupported file type'
    source = target.read_text(encoding='utf-8')
    if not any(re.search(pattern.format(name=re.escape(symbol)), source, re.M) for pattern in patterns):
        return f'{citation!r}: {symbol} is not defined in {path}'
    return None


# The measure that ranks a field: placed actors before declaring rows, so an OBJ column carried by
# 3,077 menu strings does not outrank one that changes 84 placed enemies.
MEASURE_KEYS = ('placed_actor_rows', 'units', 'rows_nondefault', 'occurrences', 'items_unsupported', 'rows')


def _measure(entry: dict) -> dict:
    return {key: entry[key] for key in MEASURE_KEYS if key in entry}


def _table(title: str, source: str, record_kind: str, fields: dict[str, dict], notes: dict[str, tuple] | None, rows: int | None = None,
           limits: list[str] | None = None) -> dict:
    entries = []
    for name, measured in fields.items():
        entry = {'name': name}
        if notes is not None:
            status, consumer, semantics, note = notes[name]
            entry.update({'status': status, 'consumer': consumer, 'semantics': semantics})
            if note:
                entry['note'] = note
        entry.update(measured)
        entries.append(entry)
    counts = Counter(entry['status'] for entry in entries)
    table = {'title': title, 'source': source, 'record_kind': record_kind, 'fields': entries,
             'counts': {status: counts.get(status, 0) for status in STATUSES}}
    if rows is not None:
        table['rows'] = rows
    if limits:
        table['limits'] = limits
    return table


def build(root: Path = ROOT) -> dict:
    tables: dict[str, dict] = {}
    for table_id, filename, section in INI_TABLES:
        rows, fields = ini_table(root, filename, section)
        tables[table_id] = _table(filename, (TABLES / filename).as_posix(), f'[{section}] rows', fields, FIELD_NOTES[table_id], rows)
    items = _read_json(root, ITEMS_JSON)['items']
    unsupported: Counter[str] = Counter()
    for item in items.values():
        unsupported.update(item.get('unsupported_fields', []))
    for entry in tables['item']['fields']:
        entry['items_unsupported'] = unsupported.get(entry['name'], 0)
    tables['item']['limits'] = ['items_unsupported = items whose equipment.py row lists the field in unsupported_fields (the generator\'s own coverage declaration).']

    evef_words = evef_actor_words(root)
    notes = dict(FIELD_NOTES['evef_actor'])
    for name in ACTOR_INSTANCE_OVERRIDE_FIELDS.values():
        applied = name in RUNTIME_APPLIED
        status = notes[name][0]
        if applied and status != 'consumed':
            raise CheckFailed(f'FIELD_COVERAGE_FAIL\nevef_actor.{name}: evef_instances.RUNTIME_APPLIED lists it but the note says {status}')
        if not applied and status == 'consumed':
            raise CheckFailed(f'FIELD_COVERAGE_FAIL\nevef_actor.{name}: note says consumed but evef_instances.RUNTIME_APPLIED does not list it')
    for name, measured in evef_words.items():
        if measured['units'] and notes[name][0] == 'dead':
            raise CheckFailed(f'FIELD_COVERAGE_FAIL\nevef_actor.{name}: {measured["units"]} units carry it; it is not dead')
    for index, name in ACTOR_INSTANCE_OVERRIDE_FIELDS.items():
        evef_words[name] = {'index': index, **evef_words[name]}
    tables['evef_actor'] = _table('level .BIN EVEF 演员实例字', 'content/generated/hsl/chapter01/battle*_seed.json placements[].actor_instance',
                                  'defProcPlayer／defProcEnemy 记录 0x10..0x2C 与 0x50+4i', evef_words, notes,
                                  limits=['status of idx 0..24 is tied to hsltools.data.evef_instances.RUNTIME_APPLIED; units/levels come from the tracked seeds.'])

    processes = evef_processes(root)
    tables['evef_object'] = _table('level .BIN EVEF 非演员记录', 'content/generated/hsl/chapter01/battle*_seed.json placements[].records', 'EVEF 记录 × 对象过程',
                                   {'code': {}, 'x': {}, 'y': {}, 'treasure_words': {'records': processes.get('defProcTreasureBox', {}).get('records', 0)},
                                    'stand_object_words': {'records': sum(entry['records'] for process, entry in processes.items() if process not in ('defProcEnemy', 'defProcTreasureBox'))}},
                                   FIELD_NOTES['evef_object'],
                                   limits=['records per process: ' + ', '.join(f'{process} {entry["records"]}' for process, entry in processes.items()),
                                           'Word census (which record offsets are non-zero per process) was measured once from the original level .BIN: only defProcEnemy (0x10/0x14 items, 0x50..0xb0 overrides) and defProcTreasureBox (0x10..0x40) carry words beyond code/x/y.'])

    obj_fields = {name: {'rows': count, **({'placed_actor_rows': OBJ_PLACED_ACTOR_ROWS[name]} if name in OBJ_PLACED_ACTOR_ROWS else {})}
                  for name, count in OBJ_FIELD_CENSUS.items()}
    tables['obj'] = _table('OBJ-NNN.obs / global.obs [Object]', 'original hsl.pak @:\\data\\obj-NNN.obs (census) + battle seeds object_data_fields', '[Object] blocks',
                           obj_fields, FIELD_NOTES['obj'], rows=13419, limits=[OBJ_CENSUS_NOTE])

    wrd = wrd_fields(root)
    tables['wrd'] = _table('levelNNN.wrd 地形', TERRAIN + 'levelNNN_terrain.json', 'WORL header + width×height u32 cells', wrd['fields'], FIELD_NOTES['wrd'],
                           limits=[f'{wrd["files"]} tracked terrain packets, {wrd["cells"]} cells.'])

    tables['actor_record'] = _table('live actor record（0x1fc）', 'docs/evidence_packets/static_reverse/original_save_format.md + hsltools/data/original_save_members.py REC',
                                    '201 × 0x1fc records (*0x4c1bc8)', actor_record_fields(), FIELD_NOTES['actor_record'])

    tables['defines'] = _table('EXTRAS.H / ANIMAL.H / TYPE.H #define groups', TABLES.as_posix() + '/{EXTRAS.H,ANIMAL.H,TYPE.H}', '#define groups by prefix',
                               define_groups(root), FIELD_NOTES['defines'])

    tables['story'] = _table('STORY opcode（ACTION.H act*）', STORY_COVERAGE + ' + ' + OPENING_COORDINATOR, 'ACTION.H tokens', story_opcodes(root), None,
                             limits=['consumed = compiler kind handled by BattleOpeningCoordinator (or applied by the winfail interpreter in cutscene mode); recorded = RECORD_ONLY_KINDS; dead = no STORY script uses the token (the actCheck* conditions live in the winfail table).',
                                     'Some recorded kinds are pre-baked by level assembly instead of interpreted at runtime (actSetPlayerMode / actSetPlayerUndead → battle.py role_overrides, actSetPlayerName → battle.py apply_story_word_writes／script_title_name — opcode 89 handler 0x451590 writes [name] to live +0x04 and [job name] to +0x1c after 0x44fad0(code, serial): the corpus has two uses, STORY029 naming its 023 #1／#2 梅爾／凱文 under 一般兵, no WINFAIL use (negative-evidence); actSetPrevInsertObjectAdjustLevel → battle.py trace_opening bakes the range／disp-range pair into the unit field script_insert.adjust_level, born by InitialRosterGrowthRules → ReinforcementGrowthRules.prepare; the WINFAIL layer folds the same token into the runtime insert request); recorded here means the opening coordinator itself does not act on them.'])
    tables['winfail'] = _table('WINFAIL opcode', WINFAIL_COVERAGE + ' + game/sim/WinfailCompiler.gd', 'winfail tokens', winfail_opcodes(root), None,
                               limits=['consumed = SUPPORTED_CONDITIONS (WinfailConditions.condition_holds) ∪ APPLIED_ACTIONS (WinfailActions.apply_actions); recorded = WORLD_FLAG_ACTIONS ∪ PRESENTATION_ACTIONS (WinfailCompiler vocabulary).'])
    tables['town_event'] = _table('TOWNDEF te opcode', TOWNDEF + ' + ' + TOWN_RULES, 'te tokens', town_opcodes(root), None,
                                  limits=['consumed = TownEventRules.SUPPORTED_TOKENS; recorded = RECORDED_ONLY_TOKENS; dead = zero TOWNDEF uses and not executed.'])
    tables['animal'] = _table('ANIMAL.H ani* opcode（演员程序 + 绝技特效脚本）', ANIMAL_PROGRAMS + ' + ' + SPECIAL_EFFECTS + ' + ' + EFFECT_PLAYER, 'ani* opcodes',
                              animal_opcodes(root), None,
                              limits=['consumed = every channel using the opcode has its interpreter: action → combat_animation.ACTION_OPCODES (compile_action binds the program into the manifest dispatch BattleCombatCutin plays, one update per tick); s_action → AnimalCastLead.CAST_OPCODES (the 絶技 lead the special cut-in plays); m_action → AnimalCastLead.CAST_OPCODES (the same four opcodes over the imported m_shape strips, the map magic presenter plays the lead; casters without an imported strip keep CAST_LEAD_IN); effect → SkillEffectScriptPlayer.IMPLEMENTED_OPCODES.'])
    tables['effects'] = _table('EFFECTS.TXT eff* opcode（法术特效）', EFFECTS_TXT + ' + ' + TABLES.as_posix() + '/effects.h', '[effect] blocks', effects_opcodes(root), None)

    problems: list[str] = []
    for table_id, table in tables.items():
        names = {entry['name'] for entry in table['fields']}
        notes = FIELD_NOTES.get(table_id)
        if notes is not None:
            problems += [f'{table_id}.{name}: note without a measured field' for name in notes if name not in names]
        for entry in table['fields']:
            if entry['status'] not in STATUSES:
                problems.append(f'{table_id}.{entry["name"]}: status {entry["status"]!r}')
            if entry.get('consumer'):
                error = citation_error(root, entry['consumer'])
                if error:
                    problems.append(f'{table_id}.{entry["name"]}: {error}')
            elif entry['status'] in ('consumed', 'passthrough', 'recorded'):
                problems.append(f'{table_id}.{entry["name"]}: status {entry["status"]} needs a consumer')
    suspects = []
    for rank, (table_id, name, priority, notice, reproduce) in enumerate(SUSPECTS, 1):
        entry = next((row for row in tables[table_id]['fields'] if row['name'] == name), None)
        if entry is None:
            problems.append(f'suspect {table_id}.{name}: no such field')
            continue
        if entry['status'] == 'consumed':
            problems.append(f'suspect {table_id}.{name}: the field is consumed')
        measure = _measure(entry)
        suspects.append({'rank': rank, 'table': table_id, 'field': name, 'priority': priority, 'status': entry['status'], 'semantics': entry['semantics'],
                         'measure': measure, 'player_would_notice': notice, 'reproduce': reproduce})
    if problems:
        raise CheckFailed('FIELD_COVERAGE_FAIL\n' + '\n'.join(problems))

    totals = Counter()
    for table in tables.values():
        totals.update(table['counts'])
    field_total = sum(len(table['fields']) for table in tables.values())
    unconsumed = [{'table': table_id, 'field': entry['name'], 'semantics': entry.get('semantics', entry.get('compiler_kind', '')),
                   'measure': _measure(entry)}
                  for table_id, table in tables.items() for entry in table['fields'] if entry['status'] == 'unconsumed']
    unconsumed.sort(key=lambda row: -next(iter(row['measure'].values()), 0))
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived (columns, counts, occurrences) + static-derived (OBS loader 0x45dc5c / actor constructor 0x407ec0 field use, EVEF 0x42bd50) + curated consumer map (each citation validated against the tree)',
        'generator': 'python3 tools/hsl.py generate field_coverage',
        'status_vocabulary': {'consumed': 'enters a remake rule or presentation', 'passthrough': 'copied into tracked data, no runtime reader',
                              'recorded': 'runtime records it without effect', 'unconsumed': 'no remake code reads it',
                              'dead': 'never non-default in the data or not read by the original loader'},
        'totals': {'tables': len(tables), 'fields': field_total, **{status: totals.get(status, 0) for status in STATUSES}},
        'suspects': suspects,
        'unconsumed_by_measure': unconsumed,
        'tables': tables,
        'limits': [
            'Test green or a citation resolving proves the remake reads the field, not that it applies the original semantics; original equivalence stays per-mechanic evidence.',
            'Opcode tables count script occurrences, not player-visible weight; a token used once in the finale can matter more than a hundred actDelay.',
            'The OBJ census and the EVEF word census are measured from the original PAK and pinned in this module; rerun the --census CLI when the seeds change.',
        ],
    }


# --- packet -------------------------------------------------------------------------------

def _cell(value) -> str:
    if value is None:
        return '—'
    text = str(value)
    # `[x disp]` argument docs would read as reference links to hsl_docs_check.py
    return text.replace('|', '\\|').replace('\n', ' ').replace('[', '\\[') or '—'


def _measure_text(entry: dict) -> str:
    parts = []
    for key, label in (('rows_nondefault', '非默认行'), ('rows_declared', '声明行'), ('rows', '行'), ('records', '记录'), ('placed_actor_rows', '已放置演员'),
                       ('units', '单位'), ('levels', '关'), ('occurrences', '出现'), ('items_unsupported', 'unsupported 物品'),
                       ('cells_nonzero', '非零格'), ('cells_cliff', '悬崖格'), ('defines', 'define'), ('offset', '偏移'), ('index', 'idx'), ('opcode', 'op')):
        if key in entry and entry[key] not in ({}, []):
            value = entry[key]
            if isinstance(value, list):
                value = f'{len(value)}' if key == 'levels' else ','.join(str(v) for v in value)
            parts.append(f'{label} {value}')
    return '；'.join(parts) or '—'


def render_doc(report: dict) -> str:
    totals = report['totals']
    lines = [
        '# 原版数据字段覆盖：重制消费了哪些、漏了哪些',
        '',
        f"> evidence: resource-derived: 列、行数、单位数、出现次数; static-derived: 0x45dc5c OBS loader 与 0x407ec0 演员构造的字段读法、0x42bd50 EVEF 分支; "
        f"negative-evidence: 命中／伤害公式无地形项; provisional: 阵营位覆盖的玩家可见后果 · status: record-only · functions: 0x407ec0, 0x409a60, 0x409be0, 0x42bd50, 0x43ea30, 0x442a90, 0x452197, 0x45dc5c · "
        f"tools: hsltools/checks/field_coverage.py · updated: {PACKET_UPDATED}",
        '',
        '_本文件由 `hsl generate field_coverage` 逐字节生成；改 [`field_coverage.py`](../../../tools/hsltools/checks/field_coverage.py) 的 `FIELD_NOTES`／`SUSPECTS`，不要手改这里。'
        f'机读版 [field_coverage.json](../../../{OUTPUT_JSON})。_',
        '',
        '## 1. 为什么',
        '',
        'lane R16 发现重制一直没读关卡 .BIN 的逐单位实例字（wait_round／fixed_point／物品，535 单位），玩家实玩才发现"敌人分批下来"的节奏全没了。'
        '这类"整个概念没读"的缺口要系统地找：对原版每张表／每种记录，列出全部字段、原数据里有多少行／单位／出现次数不是默认值、重制在哪里消费（文件:函数，每条引用在生成时核对存在）或 UNCONSUMED。'
        '状态词表：`consumed` 进入规则或表现；`passthrough` 生成器复制进数据、无运行时读者；`recorded` 运行时记录不生效；`unconsumed` 没有任何重制代码读；`dead` 原数据从不非默认或原 loader 自己不读。',
        '',
        '## 2. 总览',
        '',
        '| 表 | 记录 | 字段 | consumed | passthrough | recorded | unconsumed | dead |',
        '| --- | --- | --- | --- | --- | --- | --- | --- |',
    ]
    for table_id, table in report['tables'].items():
        counts = table['counts']
        lines.append(f"| [{table_id}](#{table_id}) {_cell(table['title'])} | {_cell(table['record_kind'])} | {len(table['fields'])} | "
                     f"{counts['consumed']} | {counts['passthrough']} | {counts['recorded']} | {counts['unconsumed']} | {counts['dead']} |")
    lines.append(f"| **合计** | {totals['tables']} 表 | {totals['fields']} | {totals['consumed']} | {totals['passthrough']} | {totals['recorded']} | {totals['unconsumed']} | {totals['dead']} |")
    lines += ['', '## 3. 嫌疑排序', '',
              '按「原数据有非默认值的行／单位数 × 语义已知且影响玩法」排序；P1 = R16 同级的整概念缺口并给出复现关卡，P2 = 局部规则缺口，P3 = 表现或单点。R21 只审计；R21 排出的两条 P1（obj_X1／obj_HitPoint）已由 R22 接入并从本表移除。', '',
              '| # | 优先级 | 表.字段 | 量 | 语义 | 玩家会看到什么 | 复现 |', '| --- | --- | --- | --- | --- | --- | --- |']
    for suspect in report['suspects']:
        measure = '；'.join(f'{key} {value}' for key, value in suspect['measure'].items()) or '—'
        lines.append(f"| {suspect['rank']} | **{suspect['priority']}** | `{suspect['table']}.{suspect['field']}` | {_cell(measure)} | {_cell(suspect['semantics'])} | "
                     f"{_cell(suspect['player_would_notice'])} | {_cell(suspect['reproduce'])} |")
    lines += ['', '### 全部 unconsumed（按量排序）', '', '| 表.字段 | 量 | 语义 |', '| --- | --- | --- |']
    for row in report['unconsumed_by_measure']:
        measure = '；'.join(f'{key} {value}' for key, value in row['measure'].items()) or '—'
        lines.append(f"| `{row['table']}.{row['field']}` | {_cell(measure)} | {_cell(row['semantics'])} |")
    lines += ['', '## 4. 静态读法（本包新增，static-derived）', '',
              '**OBS loader `load_obs_template 0x45dc5c`** 按字段名把 `[Object]` 写进对象模板：`obj_Mode`→+0x00、`obj_Plane`→+0x0c、`obj_X1`→+0x10、`obj_Y1`→+0x14、`obj_X2`→+0x18、`obj_Y2`→+0x1c、'
              '`obj_ZoomX`／`obj_ZoomY`→+0x20／+0x24、`obj_Data`→+0x28、`obj_ShapeSub`→+0x2c、`obj_Name`→+0x34、`obj_Process_Code`→+0x64、`obj_Collide_X1/Y1/X2/Y2`→+0x68..+0x74、'
              '`obj_Shape_Delay`→+0x7c（并复制到 +0x7e）、`obj_Attribute`→+0x80、`obj_Score`→+0x84、`obj_HitPoint`→+0x88、`obj_Data1..Data9`→+0x8c..+0xac；`obj_ReadShape` 与 `obj_Code` 由同一 loader 单独读。'
              '`obj_X`／`obj_Y`、无下划线的 `obj_CollideX1` 和小写 `obj_mode` 不在字段名表里——原版也丢弃。',
              '',
              '**演员构造 `0x407ec0`**（模板 +0x64 过程 3 defProcPlayer／5 defProcEnemy）：`+0xa4`（obj_Data7）为 PLAYERS 编号，经 `0x44cb10` 复制模板到 live 记录后依次：'
              '`+0xac`（obj_Data9）≠0 → live `+0x28` 在 pmPlayer 0x10000 与 pmEnemy 0x20000 之间互换并 `+0xa0 |= 8`；'
              '`+0xa8`（obj_Data8）≠0 → live `+0x14` 死亡台词字（−1 写 0）；'
              '`+0x88`（obj_HitPoint）≠0 → live `+0x1b6`（HP 加值半字）`+=`；'
              '`+0x9c`（obj_Data5）≠0 → 高半字 `+0x9e` 非零写 live `+0x04` 名字 id，低半字写 live `+0x1c` 称号 id；'
              '`+0x10`（obj_X1）≠0 → live `+0x28` 阵营模式直接覆盖；'
              '`+0x14`（obj_Y1）≠0 → live `+0x134`；然后 `0x448840` refresh。每个用过的模板字随即清零（一次性安装参数）。'
              'R22 起 `payload_inspector.parse_text_metadata` 保留 `obj_X1`／`obj_HitPoint`，`hsltools/levels/battle.py:install_player_mode` 按同一顺序（PLAYERS mode → obj_Data9 互换 → obj_X1 覆盖）写单位 `player_mode`，`_apply_object_install` 把 obj_HitPoint 加进 growth source hit_point；'
              'R29 起 `install_title_name` 把 obj_Data5 解成单位 `title`／`display_name`、`install_dead_message` 把 obj_Data8 解成单位 `dead_message`；R31 起脚本 `actSetPlayerName`（opcode 89 → `0x451590`：`0x44fad0(code, serial)` 后 `[name]` 写 live +0x04、`[job name]` 写 +0x1c，0x4515d2／0x4515d9，static-derived）由 `script_title_name` 作最后写者——全库仅 STORY029 两处（023 #1／#2 → 梅爾／凱文，稱號 376 一般兵），WINFAIL 无用例（negative-evidence）；obj_Y1 仍未进数据链，obj_Score 只有 mapobjMoveBG 的视差比进数据链（CLOUDDRIFT）；obj_Attribute 只有宝箱模板进数据链（HIDDENCHEST：ATTACKFLAG 决定画不画）。',
              '',
              '**死亡台词字 live `+0x14` 的三个写者与两个读者**（R29，static-derived）：PLAYERS `dead_message` 对由模板复制进来（高字＝第一 id、低字＝第二 id）；构造 `0x407ec0` 在 `0x407fd0..0x407fe7` 把 obj_Data8 原样覆盖（−1 写 0）；'
              'STORY／WINFAIL `actSetDeadMessage`（opcode 60，跳表 `0x4537f4[60]` → `0x452197`）经 `0x44fad0(code, serial)` 找到对象后写同一字 `msg1 << 16 | msg2`——三者后写者胜，脚本层在安装之后执行即覆盖对象层。'
              '死亡读者 `0x43ef91`（`0x43ea30` 演员状态机的死亡分支）与 `0x4434b2`（`0x442a90`）读法相同：字为 0 不说；first＝高半字、second＝低半字，任一半为 0 时复制另一半；`0x458c10() & 1` 非零取 second 否则 first；再以 `0x4072b0`（actMessage 的对白框）由死者本人说出。'
              '重制：单位 `dead_message` 即安装后的这个字（`hsltools/levels/battle.py:dead_message_ids`），BattleAftermath 取第一条（provisional：原版两半字随机；替换证据＝按 0x458c10 序列复现或 Wine 44 关观察 021 死时 2263／2264 的分布）；脚本层 actSetDeadMessage（R31）：STORY 开场的写入在装配时经开场 token/serial 绑定写单位字（`battle.py:apply_story_dead_messages`，351 处全部可解析——队员的 741／846／742／906… 与 29 关 023 的 1684／1686、19 关 041 的 1455），WINFAIL 的在运行时经 `WinfailActions.write_dead_message` 写单位字（同链插入的目标由 ScriptActorCreationRules 回放时写，6 关增援 隊長 969；文本由 BattleAftermath 用关卡 message texts 解析）；WinfailScenarioRules.dead_messages 的 fail 页记录形状不变。',
              '',
              '**命中／伤害公式无地形项**：`0x409a60`（命中）只读攻守 dex、live hit_ratio、avoid_hit_ratio；`0x409be0`（伤害）只读攻防、str、武器属性三元组（core_logic.json）。地形对防御／回避的加成为 negative-evidence；WRD 高度只影响通行（高差 >2 阻地面、0xff 悬崖）。',
              '',
              '**EVEF 非演员记录**：148 关全部 EVEF 记录中，只有 defProcEnemy（0x10／0x14 物品、0x50..0xb0 覆盖字）与 defProcTreasureBox（0x10..0x40）在 code／x／y 之外有非零字；defProcStandObject／PlayerInstall／Cursor／BattleBOSS／combined 记录只有位置。'
              '宝箱 28 关记录 33 有 13 个非零字，原 `0x42bd50` 宝箱分支只读八个（有界执行，original_treasure.md）。装备实例字 idx 18–23 在 148 关中 0 单位使用；gold idx 0 仅 53 关记录 17（R27 起 `BattleRewardRules.kill_gold` 按 `0x42bd50` 字 0 → live `+0x98` 的写法读它作击杀金钱与入场成长金钱输入；该实例值 100 与 023 模板同值，生成物无数值差）。',
              '']
    lines += ['## 5. 逐表字段', '']
    for table_id, table in report['tables'].items():
        lines.append(f"### {table_id}")
        lines.append('')
        lines.append(f"**{_cell(table['title'])}** · 来源 `{_cell(table['source'])}` · 记录 {_cell(table['record_kind'])}" + (f" · {table['rows']} 行" if 'rows' in table else ''))
        lines.append('')
        for limit in table.get('limits', []):
            lines.append(f'- {limit}')
        if table.get('limits'):
            lines.append('')
        lines.append('| 字段 | 状态 | 消费点 | 量 | 语义 | 备注 |')
        lines.append('| --- | --- | --- | --- | --- | --- |')
        for entry in table['fields']:
            consumer = entry.get('consumer')
            consumer_text = f'`{consumer}`' if consumer else 'UNCONSUMED' if entry['status'] == 'unconsumed' else '—'
            semantics = entry.get('semantics') or entry.get('compiler_kind') or entry.get('arg_doc') or ''
            lines.append(f"| `{entry['name']}` | {entry['status']} | {consumer_text} | {_cell(_measure_text(entry))} | {_cell(semantics)} | {_cell(entry.get('note'))} |")
        lines.append('')
    lines += ['## 6. 边界', '']
    for limit in report['limits']:
        lines.append(f'- {limit}')
    lines += ['- 引用核对只证明文件与符号存在并被生成器／规则读到，不证明语义与原版等价；每条机制的等价声明仍以各自证据包为准。',
              '- `evef_actor` 的状态与 `hsltools/data/evef_instances.py` 的 `RUNTIME_APPLIED` 绑定，二者不一致时 `hsl check field_coverage` 失败。',
              '']
    return '\n'.join(lines)


def summary_line(report: dict, verdict: str) -> str:
    totals = report['totals']
    return (f"FIELD_COVERAGE_{verdict} tables={totals['tables']} fields={totals['fields']} consumed={totals['consumed']} "
            f"passthrough={totals['passthrough']} recorded={totals['recorded']} unconsumed={totals['unconsumed']} dead={totals['dead']}")


class FieldCoverageTask(GeneratedFilesTask):
    name = 'field_coverage'
    family = 'checks'
    inputs = (TABLES.as_posix() + '/', SEEDS, TERRAIN, ITEMS_JSON, STORY_COVERAGE, WINFAIL_COVERAGE, TOWNDEF, ANIMAL_PROGRAMS, SPECIAL_EFFECTS,
              EFFECTS_TXT, OPENING_COORDINATOR, TOWN_RULES, EFFECT_PLAYER, 'game/battle/scene/BattleCombatCutin.gd')
    outputs = (OUTPUT_JSON, OUTPUT_DOC)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/field_coverage.py', 'tools/hsltools/data/evef_instances.py', 'tools/hsltools/levels/seed.py',
               'tools/hsltools/data/original_save_members.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        report = build(ctx.root)
        self.report = report
        return {OUTPUT_JSON: json_bytes(report), OUTPUT_DOC: render_doc(report).encode('utf-8')}

    def check(self, ctx: Context) -> str:
        try:
            return super().check(ctx)
        except CheckFailed as error:
            if 'stale tracked output' in str(error):
                raise CheckFailed(f"FIELD_COVERAGE_FAIL\n{error}\nrun python3 tools/hsl.py generate field_coverage") from error
            raise

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return summary_line(self.report, 'PASS' if mode == 'check' else 'WRITTEN')


def tasks() -> list[FieldCoverageTask]:
    return [FieldCoverageTask()]


# --- census CLI (needs the original PAK) ----------------------------------------------------

def census(pak: Path) -> dict:
    """Re-measure OBJ_FIELD_CENSUS / OBJ_PLACED_ACTOR_ROWS and the EVEF word histogram per
    object process from the original hsl.pak; prints JSON for comparison with the pinned values."""
    from hsltools.levels import seed as seed_module
    from hsltools.sources.scripts import parse_evef

    block = re.compile(r'\[Object\](.*?)(?=\[Object\]|\Z)', re.S)
    field_rows: Counter[str] = Counter()
    placed_actor_rows: Counter[str] = Counter()
    evef_words: dict[str, Counter] = {}
    objects_total = 0

    def scan_objects(raw: bytes) -> dict[str, dict[str, str]]:
        nonlocal objects_total
        text = '\n'.join(line.split(';')[0] for line in raw.decode('cp950', 'replace').splitlines())
        result = {}
        for match in block.finditer(text):
            fields = dict(re.findall(r'^\s*(\w+)\s*=\s*(.+?)\s*$', match.group(1), re.M))
            objects_total += 1
            field_rows.update(fields.keys())
            result[fields.get('obj_code')] = fields
        return result

    levels = sorted(int(path.name[6:9]) for path in seed_paths(ROOT))
    for level in levels:
        names = seed_module.record_names(level)
        records = seed_module._read_records(pak, {'objects': names['objects'], 'level': names['level']})
        objects = scan_objects(records['objects']['data'])
        evef = parse_evef(records['level']['data'], summary_limit=None)
        for row in evef['record_summaries']:
            fields = objects.get(str(row['field_0x04_code_candidate']))
            process = fields.get('obj_Process_Code') if fields else 'unmatched_or_combined'
            for word in row['non_zero_u32']:
                if word['field_offset'] not in (4, 8, 12):
                    evef_words.setdefault(process, Counter())[f"0x{word['field_offset']:02x}"] += 1
            if fields and process == 'defProcEnemy':
                for name in OBJ_PLACED_ACTOR_ROWS:
                    if fields.get(name):
                        placed_actor_rows[name] += 1
    scan_objects(seed_module._read_records(pak, dict(seed_module.GLOBAL_RECORDS))['global_objects']['data'])
    return {'objects': objects_total, 'field_rows': dict(sorted(field_rows.items())), 'placed_actor_rows': dict(placed_actor_rows),
            'evef_words_by_process': {process: dict(sorted(counter.items())) for process, counter in sorted(evef_words.items())}}


def main(argv: list[str] | None = None) -> int:
    import argparse
    from hsltools.paths import ORIGINAL_PAK

    parser = argparse.ArgumentParser(description='field coverage census (original PAK) — the registry task itself runs through tools/hsl.py')
    parser.add_argument('--census', action='store_true', help='re-measure the OBJ field census and EVEF word histogram from the original PAK')
    parser.add_argument('--pak', type=Path, default=ORIGINAL_PAK)
    args = parser.parse_args(argv)
    if not args.census:
        parser.error('use python3 tools/hsl.py check|generate field_coverage; this CLI only offers --census')
    print(json.dumps(census(args.pak), ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
