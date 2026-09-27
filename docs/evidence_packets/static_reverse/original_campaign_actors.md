# 主线角色模板、职业刷新与学习来源

> evidence: static-derived · status: live · functions: 0x42c700, 0x42caa0, 0x42cac0, 0x4373f0, 0x437970, 0x437a40, 0x44cb10 · tools: hsltools/data/campaign_actors.py, hsltools/probes/campaign_actor.py, run_campaign_actor_tests.gd, test_hsl_campaign_actors.py, test_hsl_level_battle.py · updated: 2026-09-29

## 交付与口径

`python3 tools/hsl.py check campaign_actor_data` 检查 34 个未放置模板：既有第一章／第二章／随机遭遇角色，加上最终章 059／060；具体 actor 文件和来源记录由 `CAMPAIGN_ACTORS` 驱动。产物为 `content/generated/hsl/actors/0NN.json`（`hsl_source_actor_template.v1`）及 `roles/profiles.json`；后者由 PLAYERS.TXT 中的已审查角色组成，并包含 059／060。每条有 PLAYERS.TXT 原行号／哈希、职业 symbol／TYPE.H 值、初始等级是否声明、证据等级和完整原函数结果。旧关卡编组不变。

源字段／OBJ 过程声明为 **resource-derived**；[同名原执行包](original_campaign_actors.json)是 **static-derived**，不是原作 GUI 观测。原 EXE SHA256 为 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。执行了 34 角色 ×15 输入 ×2 次完整刷新（1020 返回）、99 个推级／配额／出生调整、206 个学习调用，以及 4 个新玩家槽的 16 次完整 helper 返回和 4 个工厂前段。所有原 callee 保持执行；模板、队伍等级和字符串缓冲区是明示夹具。

## 第 37／80 关的守卫与怨念體（066／067／068）

R6-L10 把 PLAYERS 66／67／68 加入 `CAMPAIGN_ACTORS`，同一原执行包重跑（stats／growth 旧条目逐条不变，只追加三者）：

- 066（第 37 关守卫，`jobCrazyWarrior`、pmEnemy、`hit_point -10000`）与 067（柱子寶石，`jobCrazyWarrior`、pmMagicAttack、`no_attack 1`、`hit_point -10000`）的原刷新 `0x448840` 返回 **最大 HP 1**（static-derived）：源 HP 半字 `+0x1b6` 按有符号读，公式值加 −10000 后在公共收尾夹到 1。两者再由 STORY037 `actSetPlayerUndead` 设成不死身，所以普通攻击「毫無效果」（WINFAIL037 2096）。原推级 `0x40e870` 同样把该半字当有符号：探针的回读与期望模型相应改为有符号 16 位回绕（`hsltools/probes/auto_growth.py`；既有角色的正值不受影响）。
- 068（第 80 关怨念體，`jobPriestMaster` 86、pmEnemy、`size_type 1`、1200 HP、move 0）原刷新 1 级最大 HP 1293、MP 92；源魔法 8 种全部是已支持的技能 id。
- 067 没有 `find_type`／`find_range`／`ai_call_range`／`ai_fixed`，模板照旧保留缺项（`source.ai.missing_required`），不借别人的策略。

## 敌方 克羅蒂 053：规则行与造型分开（R6-L11）

对象 `Enemy053(克羅蒂)`（第 21／24／30／36／71／903 关的 obs 记录）写 `obj_Data6 = SID_ENEMY053`、`obj_Data7 = 53`、造型 `SHAPE\009-00001.SHP`（resource-derived）。构造器 `0x407ec0` 复制 PLAYERS 行 `obj_Data7`，所以单位的规则模板是 053（`jobDarkSwordMan` 99、源 HP 220、`name_8`＝克羅蒂、`FACE0008`、`level_adjust_range 30,1`），不是 009；画面按 SHAPEDEF 的 `SID_ENEMY053` 块走 `SHAPE\009-*`（与 obs 造型字段一致），死亡姿势取该块的 `SHAPE\009-P.SHP`，切入取 ANIMAL `SID_ENEMY053` 块自己的 P053 条（其 s_shape 为 P009_201）。

- 第 30 关此前把她建成 009 模板（玩家 009 的属性、`jobMagicSwordMan`、源 HP 70）；`hsltools/levels/battle.py` 现在对预览带 `source_actor_code` 的 EVEF 敌人按该行建（单位 id `actor053_1`，关卡 profile `unit_ids`）。
- `hsltools/sources/actor_walk_frames._shape_fields` 先认演员自己的 `SID_ENEMYnnn` 块，再按站立造型的编号猜：旧顺序把 053 落到 `SID_PLAYER17`（018 魍魎劍士，`SHAPE\053-*`）的块上，第 21／24／903 关的敌方 克羅蒂 因此一直画成 018 的造型——同一类问题，一并改正；死亡姿势表（`actor_hit_poses`）同理。全部演员里只有 053 的块选择变化。
- 附带发现（未改，属转职表现）：SHAPEDEF 的 `SID_PLAYER17`（018）块没有被注释，绑定的是 `SHAPE\053-*`；被注释掉的是另一份 `SHAPE\018-*` 块。“018 无 SHAPEDEF 绑定、转职后保留 009 形态”的现行读法因此与资源不符（resource-derived）。

## 四种新增职业

| 职业 | 刷新入口分支 | 原 cap（力／敏／精神／体质） | 学习归属 |
| --- | --- | --- | --- |
| 93 `jobWindWarrior` | `0x44a446`，接翼战士公共数值分支 | 550／770／390／730 | `0x4783fc` tier2；先检查高阶风系门槛，再 fall through 基础风系 |
| 95 `jobCrazyWarrior` | `0x44a8a6`，接兽战士公共数值分支 | 750／500／350／850 | `0x478444` tier2；无等级自动魔法 |
| 96 `jobMutantMonster` | `0x44ab84` | 80／84／80／106 | 原魔法／特殊学习分派均无该职业分支；源初始持有不受影响 |
| 98 `jobMagicSwordMan` | `0x44b168`、`0x44b430` | 90／82／90／90 | `0x4784ac` tier1；独立土／精神／风魔法门槛 |

`0x4786bc` 的 20 行 cap 与 `0x44b820` 职业跳表均有原字节指纹。93／95 的不同抗性系数保留，93 的魔法加 20 在基础上限之后应用；96／98 使用自己的整数除法顺序。公共收尾把装备／源加成后的负攻击、防御、魔法攻击和速度夹到 0，032 的基础输入实际命中这一边界。Python 数值模型与 Godot 实现独立对拍，不以抄写新 Godot 结果充当原证据。

`0x4373f0` 魔法以 stored level+1 检查；`0x437a40` 选择职业特殊表，`0x437970` 返回第一项未持有且满足基础属性／tier 的技能。魔法／特殊初始 mask 来自 PLAYERS 和 mag-spc.h，后天持有保存在独立学习记录。表已进 `roles/growth_lifecycle.json`；效果未实现的技能继续显示不可用，不授予近似技能。

玩家 005／007／008／009 的槽 4／6／7／8 经 `0x42c700`、`0x42caa0`、`0x42cac0` 及完整 `0x44cb10` 复制核对，工厂 `0x407eff→0x407f14` 仅作有界前段；global.obs 的物件 804／806／807／808 与 SID_PLAYER4／6／7／8 是独立资源声明。来源 mode、当前阵营、可控性、原对象种类不能互相替代。

## 组装输入与边界

模板坐标 `[0,0]` 是 **provisional 未放置标记**；组装方必须用本关 EVEF／脚本锚点替换。未声明的 level1／EXP0 仅为 pre-birth 数值核对输入；`InitialRosterGrowthRules`／`EntryGrowthRules` 按实际已登记队伍、原属性推级与源调级参数产生战斗等级，不能把该 1 宣称为原遭遇等级。四种新职业也通过原配额及 cap 填充分支。

飞行不是职业继承：本批声明飞行的为 **038／035／041／043／056／051**；034 与036同为翼战士但没有源飞行，051另有 `size_type=1`。本批 `no_block` 均为 false；模板分别保留字段是否写在源表中及现行缺字段读法，通行规则沿用[既有单格](original_actor_traversal.md)与[大型](original_large_actor.md)合同。每个档案保留首次匹配的 OBJ 来源和过程变体；本批敌方样例过程均 `defProcEnemy`，玩家是 `defProcPlayer`，不升级为整个原 dispatcher 的行为证明。

005／008 缺少 `find_type`、`find_range`、`ai_call_range`、`ai_fixed`，保留缺项；作为受控玩家不借用敌人 AI，若组装为自动角色需另有已审查的策略。064 的 `pmNPCPlayer` 与024的 `pmPlayer` 源模式不使它们自动成为受控伙伴。

**008 的源装备32保留 `range3CellCircle`，当前装备目录明确不支持该攻击范围，因此原样战斗初始化返回 `unsupported_equipment`。** 属性原返回与模板已交付；替换证据是原范围 builder／矩阵及玩家、AI、反击的共同范围测试后接入真实武器，再解除 `source.runtime_blockers`。不能卸掉、换爪或改近战范围来声称咕嚕已正式可玩。Godot 仅以明确的无装备数值夹具对拍其96分支，另测试原装备初始化应拒绝；其余24个模板正常初始化。

转职事务、原完整 parser／constructor／dispatcher、全局随机流、负属性／溢出区间与实际各关体验不在本片原版等价声明内。没有新增场景、图像、动效或默认角色授予。

## 复跑与验收

```sh
uv run --no-project --with unicorn==2.1.4 --with pillow --python /opt/homebrew/bin/python3 tools/hsl.py generate campaign_actor --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
python3 tools/hsl.py check campaign_actor
python3 tools/hsl.py check campaign_actor_data
python3 -m unittest discover -s tools -p 'test_hsl_campaign_actors.py'
bash tools/godot.sh --headless --path . --script res://tests/run_campaign_actor_tests.gd
```

定向 Python 4 项＋既有角色资源4项通过；Godot **10,524 检查通过**，覆盖独立原返回、所有模板初始化及008明确拒绝、不可变输入、cap／出生随机边界和学技 mask。未作 GUI 人工验收；本片无布局／动效变更，正式组装仍由 presentation 线独立验收。完整门禁和提交回执见[本线协作记录](../../collaboration/source-research.md)。
