# 共享表现对照基准

> evidence: runtime-measured · status: live · tools: capture_presentation_reference.gd, hsltools/assets/command_frames.py, hsltools/evidence/presentation_reference.py · updated: 2026-09-11

日期：2026-09-11。目标是按**状态与转换**对照，而非把素材导入或规则测试通过当成还原完成。本目录的 `cases.json` 是覆盖清单；`media/` 是短、可独立播放的游戏画面和声音。原始长录像仍在 `ignored/presentation-reference/`，不作为产品依赖。

继续采样／调参前先读 [原版表现逻辑的离线恢复](../../static_reverse/presentation_source_recovery.md)：菜单源帧、布局算术、更新计数与 ANIMAL 顺序已有直接调查入口，含可复跑命令和未确认边界。先用这些证据收窄问题，再对剩余差异采样；本页已有录像与覆盖清单继续保留，不因静态研究而自动标记 matched。

## 当前工作入口：源函数优先（2026-09-12）

本轮实际门禁、两条正常时钟渲染路线及交付边界见 [2026-09-12 验收记录](delivery-20260912.md)。

本轮已将研究转为可执行对照，见 [菜单原函数与接入](../../static_reverse/native_presentation_helpers.md) 和 [ANIMAL 完整程序](../../static_reverse/animal_program_execution.md)。默认顺序为资源/原指令/离线渲染；本页录像是残余视觉问题的参考，不是每章开工都要重录的前提。

三个原菜单 helper 已实际隔离执行并供 Godot 回归；普通攻击已从完整源程序绑定 setup/wait/继续取指/让出边界。状态、物品、成长和选敌复用原版身份栏、槽条和装备视图。移动后非致死攻击的新原版样本进入下一角色，因此移除了旧的额外两按钮确认。更新后的六类重制参考与已取得的原版静止/悬停/移出、状态退出、物品选择和行动交接都在 `cases.json`。

`check --require-complete` 仍只表示“所有要求的视频证据齐全”，当前会报告原版完整施法、物品取消片段、原版四维成长和战利品等缺口；不将源码对照通过偷换成这些录像已经存在。普通 `check`、独立源码合同与 full verify 继续使用。以下 9 月 11 日采样过程保留为历史，不应继续据其锁屏状态或旧帧数安排长时间原版操作。

## 已取得的原版事实（历史采样）

- 原版 1.06 第一战 Move 悬停中，图标本体有多帧变化；`original-hover-loop.mp4` 证明持续悬停的循环，**不包含进入和退出**。六种命令的源 SHP 共 20 帧，已经由 `hsltools/assets/command_frames.py` 可重复导入。当前播放频率 8fps 仍是待校准值。
- `original-five-menu.mp4` 为移动后稳定画面：攻击移到顶点，剩余五项重排，而非保留六个旧位置的空洞。当前共享菜单按剩余命令数重排，恢复上右特殊技、下左道具的顺序，并以脚点上方约一格为中心。两项布局使用同一规则外推；尚未把它称为已验证的原版行动策略。
- `original-hit.mp4` 是 023→021 普通非致死攻击，包含出招、独立目标镜头、受伤、返回地图。事件时间来自 4fps 联系表的人工检查，误差约 ±0.125s；不能代替精确引擎 tick 证明。受伤画面约保留 1.5s，不应该跟随攻击者最后一帧直接结束。
- 原版玩家移动并击杀敌人后还出现了战利品窗口，离开后继续 NPC 行动。这一分支已加入覆盖清单，不能再被“第一战已完整”一句话略掉。当前重制版尚无对应战利品流程。

## 当前共享实现

`BattleCommandMenu` 读取全部源帧，悬停循环不会被每帧的指针刷新重新归零。菜单几何只由当前命令集合计算。移除了永久阵营脚环和头顶血条的绘制及其无效数据维护；真正的移动/攻击格不受影响。

`CombatPresentationTiming` 是无战斗状态的共享时序模块。普通攻击的完整源 pose 时长之后，另有目标准备、受伤和恢复预算。挥击 `released` 与命中 `impact` 分开，各触发一次；武器命中声从 ITEM 的武器类别与同名 resource.h 音效关联，原生派发函数仍未证明。

施法新增独立的 `sfxCastMagic` 和源 object399 `Cast_Star`，先在施法者位置播放，再进入既有目标特效。此处粒子轨迹、密度和施法时长仍是 provisional；原版完整施法录制尚未取得。不能因已有六张星光素材，就宣称整个原版施法过程已还原。

## 可重复工作流

原版：先确认画面与进入条件，列出明确窗口，再录 1–60 秒。仅录该游戏窗口和应用音频，不录整个桌面或麦克风。

```sh
swiftc -parse-as-library tools/hsl_record_window.swift -o ignored/bin/hsl_record_window
ignored/bin/hsl_record_window --list
PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference record --window WINDOW_ID --seconds 15 \
  --kind original --label menu-hover --precondition '当前关卡与动作前状态'
```

Win32 helper 新增显式 `--focus`，同一 helper 先聚焦再注入输入。原版单步动作仍需看结果，不能把“已注入”当作动作成功。本轮实际有效路线使用约 160ms 按键/点击；不自动重试游戏操作。

重制版优先使用 **Godot 自带 Movie Maker**，而不是依赖前台窗口的采样。以下是改变初始条件的渲染夹具：60fps 仿真时间、独立动作声音，不是自然游玩或实机帧率证明。

```sh
tools/play.sh --screen 0 --write-movie ignored/presentation-reference/remake-attack.avi \
  --fixed-fps 60 --disable-vsync --script res://tests/capture_presentation_reference.gd -- attack movie
# attack 可换成 menu 或 magic；输出相应的事件时间 JSON。
PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference check
PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference report
```

对照页：`ignored/presentation-reference/compare.html`。同名事件定位，两侧保持原速，支持帧步进与声音分别试听；证据不全的事件按钮禁用。`check` 校验清单、时序和媒体哈希；`check --require-complete` 还要求完整覆盖，当前应明确失败，因为原版施法、悬停出入及其他 UI 仍待采样。

## 失败也保留为事实

外部窗口录制曾发生“逻辑事件已经前进，录像仍停在旧菜单”的情况；另一次锁屏让请求 40 秒的原片实际只剩约 10 秒。这些片段没有被提升为当前表现通过证据。录制工具现在校验音轨、真实音量和实际长度；短于请求长度会失败。重制版改用 Movie Maker，真实输出帧已经另行检查。

本轮后段 Mac 锁屏，ScreenCaptureKit 无可用显示器，原版施法与剩余原版状态被阻塞；未尝试解锁。每个缺口都在 `cases.json` 中独立保留，当前没有任何 case 被标成 `matched`。锁屏不阻塞离线生成重制版参考片。
