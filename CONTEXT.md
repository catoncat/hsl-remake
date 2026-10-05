# HSL Project Vocabulary and Evidence Policy

> 中文摘要：本页是项目共用的术语和写结论的规矩。
>
> - 「原版」指玩家自备的 1998 年經典版目录，只当行为参考，不是运行依赖。
> - 重制运行时、现行场景、PlayLoop、首次可操作等词各有固定所指，见 Product terms。
> - 证据等级的定义在 [METHOD](docs/METHOD.md#证据分级)；Claim rules 列出写结论时不能混淆的几件事，比如测试通过不等于原版等价。
> - 镜头、投影、脚点、点击判定和遮挡是同一个空间合同，不能分开凭感觉调。
> - 原作运行观测怎么采样、对外能说到什么完成度，也在本页。
> - 文档按用途分事实、做法、记录三类，事实和做法只写现在，见「文档怎么写」。

Checked: 2026-09-27

本文件只定义当前项目必须共享的术语和证据写法。项目进度看 `docs/PROJECT.md`，代码结构看 `docs/ARCHITECTURE.md`，具体资料位置看 `docs/KNOWLEDGE_INDEX.md`。

## Product terms

### Original game

玩家自备的正版《幻世录》1998 年經典版目录（Steam《幻世錄 重製版》里的 `GAME-PAK/`），由 `HSL_ORIGINAL_DIR` 指定，未设时工具按平台找 Steam 库；维护者做运行观测时另用 Wine 前缀里的原作（`$WINEPREFIX/drive_c/hsl`）。它是行为参考实现，不是本项目运行时依赖。普通开发、Godot 测试和静态检查不需要启动原作。

### Remake runtime

当前 Godot 产品路径：

```text
project.godot → game/title/TitleScreen.tscn → BattleSceneRuntime.tscn → BattleSceneRuntime.gd → BattlePlayLoop.gd
```

### Live scenario

`content/battles/battle_051.json`。它是当前产品真正加载的第一战配置，由 `level_battle:51` 从 seed／`story_051.json` 组装，与其余正式战斗同一路径（`rule_adapter: winfail`）。`content/battles/first_battle.json` 保留为已审核的 12 名角色模板名册（Python 生成器输入）与纯 loop 机制测试的 `development_battle` 夹具，不再是可进入的战斗。

### Play loop

`BattlePlayLoop` 持有当前唯一可变战斗状态：单位坐标、HP、击败状态、行动状态、速度队列和基础结果。Scene 和 ActorRuntime 只同步表现。

### First control

开场交接后 Leonard 第一次可以接受玩家命令的状态。当前有行动菜单证据，但仍缺 confirmed `first_control_idle_no_menu`；不得用对白间隙或已打开菜单的截图冒充纯站位真值。

### Player-controlled / friendly AI / enemy AI

- `player_controlled`：当前只有 Leonard。
- `friendly_ai`：第一战与 Leonard 同侧但不接受玩家命令的 023/024。
- `enemy_ai`：第一战敌方 021/026。

Actor id、sprite id、object process 名或 `team` 字段不能单独证明最终控制权；优先使用 live scenario 与 `ActorRoleRules` 的显式 role。

### Current-Godot scaffold

为了让纵切可运行而明确暂定的规则或表现。当前实例与替换证据见机制矩阵；旧的“必中的攻击”“最近目标追击”不能继续当作当前实现摘要。每个 provisional 选择必须标明范围，不是原版事实。

## Evidence tiers

七级来源等级的定义，以及它们在 `game/` 模块头和证据包里怎么标，见 [METHOD](docs/METHOD.md#证据分级)。旧 JSON 里可能还留着历史复合标签，不再扩散新命名。

## Claim rules

1. **测试通过只证明实现合同没有回归。** 它不证明原版 parity。
2. **文件名不是语义。** SHP/BCMD/临时批次编号、截图名称和反编译临时函数名都只能作为定位线索。
3. **导入资源不是机制。** 看到角色帧、UI 图或 WRD 格子，不等于方向、命中、阻挡、时序已经恢复。
4. **runtime 只回答窄问题。** 新采样必须写清 route、窗口、时刻、evidence id 和不支持的结论。
5. **混合证据拆开写。** 不把 `resource-derived + user-confirmed + provisional` 压成一个模糊“已确认”。
6. **所有 provisional 都有替换点。** 数据、代码或文档中写明未来需要哪类证据。
7. **录像元数据不等于引擎合同。** 用户提供的 record.mp4 为 638×480／30fps，项目逻辑视口为 640×480；采样 PNG 序号不是视频帧号。视频模型的文字推断需逐项查图，源帧、像素匹配和局部语义分别验证。入口见 `docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md`。

## 文档怎么写

文档按用途分三类，分开放，各写各的：

- **事实**：游戏和仓库现在是什么——规则、数值、剧情设定、数据格式、守则。
- **做法**：怎么做——流程、工具用法。
- **记录**：工作日志、调查、决定的来由、代理交接、审核、提示词。可以按日期追加，但不当规矩读。

事实和做法只写现在：不写「原来……现在改成……」、搬迁经过、旧地址还能不能用，也不写日期和进度。东西挪了就直接写新位置，来龙去脉留给 git log 和记录。当前进度只写在 [PROJECT](docs/PROJECT.md)，别的文档不另记。

## Spatial contract

Camera、grid/world 投影、actor 脚点、Move overlay、hit-test、前景遮挡和菜单 anchor 是同一个空间合同，不能分别凭感觉调整。

当前强制入口：

```text
docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json
docs/evidence_packets/runtime_observations/first_battle_visuals/move_overlay_primary.png
tools/hsltools/evidence/visual_index.py
```

当前角色格中心由原版初始化确定：`origin=(0,0)`、`cell_size=(32,32)`，渲染位置为格中心。旧 Move probe 的 `(192,64)` 偏移和 IoU `0.776041` 不能继续作为 live 投影；NPC 开场移动、前景锚点和完整视觉合同仍待恢复。

## Original runtime capture policy

- 原作文件由环境变量 `HSL_ORIGINAL_DIR` 指定（含 `hsl.pak`／`hsl01.exe` 的目录）；运行观测用 Wine 前缀 `WINEPREFIX`，原作在 `$WINEPREFIX/drive_c/hsl`。
- 优先通过 `tools/hsl_original_control.py` 做 Wine 内部单步输入和 cnc-ddraw 游戏画面采样；旧 `tools/hsl_capture.sh` 保留 window-only capture。
- 多个 Wine 窗口时必须显式选择 window id；工具不会猜。
- 旧 macOS HID 输入需要 Accessibility 权限；Wine 内部入口要求唯一原作窗口及 Wine 前台状态，不承诺 macOS 后台隔离。
- raw 截图、视频和 trace 放在仓库外 archive 或 `ignored/`，有长期价值的结论再提升到 tracked evidence packet。

## Completion language

当前可说：

> 已接通证据驱动的第一战运行时地基和基础 mechanics-playable 战斗循环。

除非以后有对应证据和验收，不可说：

- 第一战已完成。
- 开场已完整还原。
- AI 已恢复。
- 伤害/命中公式完全确认。
- 第一可操作帧、镜头或 UI 已达到原版 parity。
