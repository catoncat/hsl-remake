# 原版菜单函数已执行对照：数据、计数与展开

> evidence: static-derived · status: live · functions: 0x409090, 0x43ea30, 0x45e5a6, 0x45e5d9, 0x45e80d · tools: hsl_native_presentation_probe.py, hsltools/assets/combat_animation.py, hsltools/assets/command_frames.py, hsltools/assets/menu_layout.py, run_presentation_contract_tests.gd · updated: 2026-09-14

本包承接 [表现逻辑离线恢复研究](presentation_source_recovery.md)，不是原版引擎的完整重放器。它把该研究给出的窄函数入口变成了可复跑的原指令输出，并接入当前 Godot 菜单。原作本体只读；开发探针不启动 Wine、不调用系统输入，也不修改原作进程。

## 证据与接入

| 内容 | 原版入口／输入 | 当前消费方 | 证明边界 |
| --- | --- | --- | --- |
| 图标身份、帧数与循环方式 | `data\\obj-051.obs` 的 `defProcBattleCommandString`、Data3/Data8；BCMD SHP | `hsltools/assets/command_frames.py` → `source_objects.json`／manifest → `BattleCommandMenu` | Data3 非零走循环，零走往返；不把第一张图当全部动画 |
| 菜单位置 | EXE `0x4a35fc/0x4a39fc` 两张 256 项整数表；生成函数 `0x43ea30` | `hsltools/assets/menu_layout.py` → `native_layout.json` → `CommandPresentationRules.centers` | 横纵 66/72、中心 y−28、六／七项索引特例；不是未经检查的浮点圆 |
| 循环换帧 | `0x45e5a6..0x45e5d8` | `frame_at(..., looped=true)` | 合成对象按原始指令逐次执行，D=6 时七次调用推进 |
| 往返换帧 | `0x45e5d9..0x45e641` | `frame_at(..., looped=false)` | 两端不重复；三帧是 0→1→2→1→0，不是 0→1→2→0 |
| 展开运动 | 菜单在 `0x43e72a..0x43e73b` 以容差 2、最大步进 8 调用 `0x45e80d` | `opening_step` 与菜单自身可见位置 | 两轴距离均不超过 2 才吸附；其余距离算术右移一位后限制在 ±8 |
| 悬停缩放参数 | `0x43e7b6` 写入 16.16 值 `0x15800` | manifest 参数与图标尺寸 | 原图 42px；没有把 54px 手调值继续当原版参数 |

EXE 身份固定为 SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。原包命令定义与帧都有来源摘要；菜单表保存原字节摘要。当前扩展了 use/give/equip/drop 四类图标，不把有图标等同于全部装备玩法已实现。

## 原指令输出，而不是自我生成的预期值

开发入口：[`hsl_native_presentation_probe.py`](../../../tools/hsl_native_presentation_probe.py)。输出：[`native_presentation_helpers.json`](native_presentation_helpers.json)。

探针加载原 EXE 的 PE sections，显式构造栈、返回地址和对象字段。每次调用只允许上述三个函数之一的指令地址，最多执行 256 条指令，并确认返回到预定停止地址。没有把未知函数 stub 成成功，也没有依赖正在运行的原作。

换帧覆盖循环／往返两种模式各自的 1、2、3、5 帧；每例保留初态与 84 次更新，共 680 个帧号样本。展开覆盖垂直、斜向、负坐标、临界吸附及非零起点的六条轨迹。`run_presentation_contract_tests.gd` 用同一输入逐步比较 Godot 与这些原函数输出，不用 Godot 模型反过来生成其预期值。

```sh
# 可选分析依赖只用于重跑原函数；不加入游戏或普通验证环境。
uv run --no-project --with 'unicorn>=2,<3' --python /opt/homebrew/bin/python3 \
  python tools/hsl_native_presentation_probe.py \
  --output ignored/presentation-reference/native-helpers-rerun.json

# 与已整理的原函数输出比较；先检查版本差异，不盲目覆盖基准。
cmp ignored/presentation-reference/native-helpers-rerun.json \
  docs/evidence_packets/static_reverse/native_presentation_helpers.json

python3 tools/hsl.py check menu_layout
python3 tools/hsl.py check command_frames
tools/play.sh --headless --script res://tests/run_presentation_contract_tests.gd
```

目前将菜单更新映射到每秒 60 次是单独的表现时钟选择。函数调用计数等价不证明原作主循环每秒必定调用 60 次，不证明 Wine 显示帧率，也不能推导 ANIMAL 的 aniDelay。ANIMAL 的完整程序恢复由另一条已授权研究线负责，见 [协作入口](../../../PARALLEL_WORK.md)。

### ANIMAL 最小 live 接入

已读研究线交付的 [完整程序与 dispatcher 前段证据](animal_program_execution.md)，并由 `PYTHONPATH=tools python3 -m hsltools.assets.combat_animation --bind-programs` 绑定现有六类角色的 ordinary action。保留全部有效指令原序，Delay setup 与等待退出分别占调用，SetShape 让出，Flash 继续读取同次后继指令。雷欧纳德帧 1/2/3 首次出现在第 14/24/29 次调用结果，末段等待收束于 60 次；不再简单累加原文 12/8/3/30 后丢掉动作自身的调用边界。新 Python 和 Godot 回归保护这些界限及原始闪光偏移。

ordinary 通道支持 Delay/SetShape/InsertAttackFlash 与 002／004／006 的速度／位移／缩放（`combat_animation.ACTION_OPCODES`）；未知操作明确拒绝绑定。s_action 施法引导自 R30 起由 `AnimalCastLead` 按 handler 读法播放（`0x45e80d` 在 aniMoveToCenter 与施法对象滑入处以容差 16、步 32 复用同一 `opening_step`），m_action 数据保留、条带未导入。作者源文件末尾转交现有重制受击调度，不伪造原 loader 隐式 Over 或其公共尾部已执行。运行时仍用既有 cut-in 时钟与 immutable receipt，不再次结算伤害。

鼠标入口另使用 [完整滚动请求探针](original_mechanics_audit.md) 验证边缘方向，实际浏览仍走现有 camera pan/clamp；原请求 ±12 与最终每秒速度分开。五点/四维成长等其他规则的恢复由同一审计登记，未被本包的菜单／攻击接入覆盖。

## 行动集合与上层交接不可混淆

已修正 `core_logic.json` 的旧摘要：mode 1 在 `0x43eb32..0x43eb39` 跳过的是首个 UTF-16 Move 字符，不是 Wait；mode 2 是 oqz 系列，也不是“只有魔法／特殊技”。玩家入口在 `0x443a3c` 调用 mode 0，在 `0x4440e1` 调用 mode 1，在 `0x44416f` 调用 mode 3（道具子菜单）。

进一步直接读取的 `0x409090` 通过 actor 索引定位实时资料并读取武器表 `+0x84`，还处理 `+0x18c/+0x2c` 的分支。它不是“本行动已经攻击”的布尔值；不能靠此函数返回零推断攻击预算已经耗尽。`0x444825` 在后置交换收束后转至 `0x4454a5` 的行动收尾，而不是无条件重新生成相同菜单；完整状态变体仍须分别研究。

既有补充短片 `presentation_reference/media/menu_after_both-original.mp4` 记录了一个明确情形：第一战雷欧纳德移动后普通攻击，目标从 22 HP 变为 2 HP，演出后直接进入下一角色，没有额外 Wait 确认。该历史样本仍有效。后续 [公共行动恢复](original_action_state_machine.md) 已用 EXE 证明未移动的普通攻击、落空和特殊技也在完成后结束；当前不再要求 moved 与 attacked 同时为真，但仍等待地图预告、攻击／反击、剧情和成长面板结束，再通过 PlayLoop 单一出口交接。

只攻击未移动、特殊装备、多次行动与其他状态不由这个样本一并证明。两项菜单的几何仍可按原表计算并单独测试；这不意味着本案例应该显示两项菜单。

## 共享面板与行为边界

状态／物品／成长共用 `BattleVitals`、`BattleEquipmentView` 和 `BattleUISkin`，读取 `shared/panels/manifest.json`。身份栏在面板顶部，生命／魔力／气力使用源槽条，左侧属性与右侧装备分离；魔击力来自已有原属性探针，不再误放命中率。战斗受击时同一身份栏仍位于特写底部。数值取当前战斗输入，不复制原版截图中的等级、HP 或金币。

物品路径为子菜单→列表→地图对象／丢弃确认。逐级取消不消费物品或行动；取消后的旧回调、重复确认及非法接收者不提交。使用、给予和丢弃的有效操作由 PlayLoop 更新；装备页面当前只读已装备项目，初始清单没有可更换的装备，不声称实现了全装备系统。给予／丢弃结束行动是明确的重制策略。

成长继续采用已存在的生命／攻击／防御三项规则，本轮校正面板及真实输入，不冒充原作四维成长。原版完整施法／死亡／战利品处理仍不能由菜单 helper 的通过推出；它们与本包已经恢复的菜单函数严格区分。

## 验证方式

源数据检查、原函数输出对照、真实输入夹具、正常时钟通关和原版视觉等价是不同层次。当前定向测试还保护展开期间不能点到重叠图标、悬停移出复位、重复指针刷新不重置动画、边缘图标和文字可见，以及完整受伤后才交接。

`capture_presentation_reference.gd` 通过 Godot Movie Maker 输出 menu/attack/magic/status/items/growth 六类参考；物品和成长使用 Control 输入事件而不是直接提交数值。完整门禁仍是 `tools/verify.sh`。双侧视频清单仍保留缺失项，原函数通过不会自动把整个视觉 case 标成 matched；不要为了让视频覆盖表全绿重开长时间 Wine 采样。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/runtime/CommandPresentationRules.gd` rules：0x43ea30 integer tables 0x4a35fc／0x4a39fc, six／seven-count indexing
- `game/battle/scene/BattleCommandMenu.gd` layout：0x43ea30 integer centers via CommandPresentationRules
