# 对白、状态与选择反馈验收

> evidence: runtime-measured · status: live · tools: capture_dialogue_selection_review.gd, run_first_battle_playthrough.gd · updated: 2026-09-14

2026-09-14，接续资料审查提交 `08eca50`。本包记录已接入游戏的修正；原始录像观察仍在 [original_gameplay_reference](../original_gameplay_reference/README.md)。图片与运行回执、代码哈希见 `manifest.json`，后续顺序只看 [PROJECT](../../../PROJECT.md#next-steps)。

## 差异、修改与代码入口

| 原录像及旧实现 | 当前实现与图证 | 所属模块 |
| --- | --- | --- |
| [原对白 02/frame_004（重制画面）](../../../screenshots/remake/dialogue-board-bottom.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/02_dialogue_system/frame_004.png`） 是左肖像、石纹金框与姓名／正文分区；[旧开场](before-opening.png) 是较窄黑底 | [开场](opening.png) 复用原 BOARD02 与肖像；姓名和正文、继续符号分离 | `BattleDialogue`；Runtime 只递交当前消息并等待所有显示页 |
| 战中旧代码每 40 字截页，混入姓名／继续提示 | [长台词首页](story-first.png) 和 [末页](story-last.png) 按实际排版每页三行；全文不切片，末页确认才推进消息 | Presentation 保留整条消息队列，共用 Dialogue |
| 原状态 06/frame_006（原版帧见私有档案：`runtime_observations/original_gameplay_reference/06_status_and_stats_screen/frame_006.png`） 显示魔擊力 17%；旧实现丢失后缀 | [状态页](status.png) 显示 17%；成长后定向回归显示 18%，没有乘除 100 | `BattleStatusPanel.show_unit` |
| 原选择 08/frame_004（原版帧见私有档案：`runtime_observations/original_gameplay_reference/08_attack_target_selection/frame_004.png`） 是气刃斩；空格也有技能名和光标 | [空格](special-empty.png)、[合法目标](special-target.png) 保留当前技能名；仅合法敌人展示目标和实际命中率，空格不残留上一目标信息 | `BattleSelectionCursor` 与 Presentation 的选择／预览方法 |
| 底部固定身份栏会覆盖低处选格 | [下缘目标](lower-target.png) 的身份栏转到上方；[移动](move-selection.png) 的光标与实际命中格共用镜头转换 | Runtime 在镜头更新后传入逻辑格矩形；信息栏避让是重制选择 |

BOARD02、肖像与状态底板属于 `resource-derived`。原录像的局部观察范围见 V01–V05；本包的重制运行属于 `runtime-measured`。布局使用 640×480 逻辑视口，未将 638×480 有损录像强行拉伸后当精确测量。当前字体、18px 字号、换行／三行分页、光标角线和呼吸速度、下缘目标的信息栏避让均是明确的重制编排；没有声称恢复原字体、alpha、时钟或完整原 UI handler。

## 实际输入和复跑

`tests/capture_dialogue_selection_review.gd` 使用正常时钟、真实渲染窗口及实际 Control／Runtime 输入入口。鼠标通过 `Viewport.push_input`，键盘通过 `Input.parse_input_event`，以便持续方向键确实驱动相机。回执记录每次截图时的镜头、指针、命中单位、交互状态及显示可见性；不把一张隐藏的面板误当作“没有遮挡”的通过证据。

正式开场经过七次原消息确认到首次控制，再从实际菜单打开状态（该段截图 before-opening.png／opening.png 为历史图证：夹具 first_battle.json 自 ded491cc 起不再带开场段，capture_dialogue_selection_review 现在直接从首次控制开始，回执写 opening_is_product_path:false）。选择部分单独设为 20 ST、一个邻接敌人的夹具，随后通过正常角色选择刷新菜单；不调用攻击结算。它覆盖空格、合法敌人、方向键移到下缘、取消和移动选择。长对白单独排入原消息 369，以实际按键检查两页、同消息刷新不回首页、暂停期间战斗状态不变、末页后恢复正常菜单。两种夹具都不是自然战斗获得气力或自然触发第六回合的证据。

```sh
# 本机已确认内建屏为 0；其他显示器配置先确认编号。
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/capture_dialogue_selection_review.gd

# 无数值／坐标／结果覆盖的正常第一战路线，含剧情、结果与鼠标重开。
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/run_first_battle_playthrough.gd -- hold
```

定向回归在 `run_battle_scene_runtime_tests.gd` 和 `run_presentation_contract_tests.gd`：覆盖七行文本、三个真实长短消息的全部显示行、完整正文与末页、原说话人切换、重复刷新、剧情暂停、成长后的后缀、目标预览无状态变动、镜头变换及取消／离窗清理。它们属于既有 `tools/verify.sh`；最终完整门禁与正常路线结果写入本批提交说明，原日志保存在 `ignored/dialogue-selection-review/`。

本轮正常 hold 路线已取得 `FIRST_BATTLE_PLAYTHROUGH_PASS`／exit 0：187.177 秒、第 8 回合 `victory_escape`，鼠标重开后初始 HP、气力、库存、成长点和未结束状态均恢复。此路线没有触发成长分配；驱动里的旧三项成长键已对齐现行四维，成长交互仍由既有专用回归覆盖。原开场／战中对白、结果交接与重开属于该路线证据，不能据此推成全部打法或音画逐帧等价。

## 仍未确认

原版敌方 `???`、侦察及信息公开条件尚未恢复；当前继续使用已接受的完整属性预览；头顶命中率 UI6 起照原版去掉（用户 2026-09-25 定，绝技命中率在技能页说明框）。选格角框表示范围内的格，不代表空格或友军可被攻击；资格与命中仍由公共规则核对。演出、掉落／取物、音轨与完整原版分页逻辑不属于本批完成声明。自动回归与截图检查不能替代用户对最终手感的接受。
