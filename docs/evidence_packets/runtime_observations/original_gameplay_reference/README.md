# 原版录像：已审查的视觉参考

> evidence: runtime-measured · status: record-only · tools: hsltools/evidence/gameplay_reference.py · updated: 2026-09-28

核对日期：2026-09-14。用途是定位可见差异、查看连续过程和制定窄问题；产品范围与开发顺序仍以 [PROJECT](../../../PROJECT.md#next-steps) 为准。

外部交付的原版录像 `record.mp4` 是本包来源。原始交付的图像提取可靠，文字解释存在错误和无依据的精确断言，已由本页取代。审查过程、纠错和保存位置见 [AUDIT.md](AUDIT.md)；交给视频模型的补充任务见 [CAPTURE_SPEC.md](CAPTURE_SPEC.md)。

## 结论

- 637 张外部交付 PNG 的 RGB 像素全部在原录像解码帧中找到，正式包保留 52 张原帧＋18 张接触表＋11 张细节图；下文 V01–V10 是本录像内的可见观察，只作视觉参考与窄问题入口（runtime-measured）。
- 原交付的文字解释有错误与无依据的精确断言，已由本页取代，纠错见 [AUDIT.md](AUDIT.md)；录像观察不升级为全局规则，参考帧存在不等于重制已修复。

## 证据

### 使用前先分清三件事

| 层次 | 本包能提供什么 | 不能据此声称什么 |
| --- | --- | --- |
| 图像来源 | 637 张原交付 PNG 的 RGB 像素全部在原视频解码帧中找到；正式包保留 52 张原帧 | 不证明外部模型逐一理解了所有 14,685 帧 |
| 可见观察 | 下表列出的局部外观、同一次动作的前后画面，标为 `runtime-measured`，范围仅限本录像 | 不把样本值、单次路线、动画姿势变成全游戏规则 |
| 实现决策 | 对照已有资源／静态证据及当前代码，形成待修复项 | 不由参考图或测试绿宣称已接入、原版等价或用户验收通过 |

录制文件是 **638×480、30 fps、489.5 秒、14,685 帧**；项目逻辑视口仍是 640×480。它是带 Screenflare 水印的 H.264/YUV420P 录像，不是无损的 640×480 原始 framebuffer。缺少的横向两像素、压缩和水印会影响坐标、颜色与文字判断；不要先拉伸成 640 再报告“像素精确”。AAC 音轨本轮未审听、未标注。

### 按问题找图

目录编号保留原交付名称，避免破坏引用；以本表和 `manifest.json.label` 为语义，不能从旧目录名推断内容。接触表仅作导航，可能跨越相邻操作；查看原尺寸 `frame_*.png` 才适合核对细节。

| 问题 | 连续过程入口 | 已保留的关键原帧 |
| --- | --- | --- |
| 开场、标题、初始任务文字 | 01 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/01_title_and_opening/contact_sheet.jpg`） | [标题（重制画面）](../../../screenshots/remake/title-framed.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/01_title_and_opening/frame_001.png`）、[章节字样（重制画面）](../../../screenshots/remake/section-title-card.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/01_title_and_opening/frame_038.png`） |
| 对话框、姓名、正文、淡出 | 02 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/02_dialogue_system/contact_sheet.jpg`） | [完整对白（重制画面）](../../../screenshots/remake/dialogue-board-bottom.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/02_dialogue_system/frame_004.png`）、另一说话人（原版帧见私有档案：`runtime_observations/original_gameplay_reference/02_dialogue_system/frame_016.png`） |
| 菜单悬停和切入移动 | 03 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/03_action_ring_menu/contact_sheet.jpg`） | 菜单（原版帧见私有档案：`runtime_observations/original_gameplay_reference/03_action_ring_menu/frame_007.png`） |
| 移动格、脚点和镜头变化 | 04 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/04_movement_range_and_cursor/contact_sheet.jpg`） | 原尺寸网格（原版帧见私有档案：`runtime_observations/original_gameplay_reference/04_movement_range_and_cursor/frame_001.png`） |
| 系统菜单及其开合 | 05 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/05_system_scroll_menu/contact_sheet.jpg`） | [菜单展开（重制画面）](../../../screenshots/remake/battle-system-scroll.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/05_system_scroll_menu/frame_003.png`） |
| 状态值、装备提示、技能页 | 06 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/06_status_and_stats_screen/contact_sheet.jpg`） | 魔擊力 17%（原版帧见私有档案：`runtime_observations/original_gameplay_reference/06_status_and_stats_screen/frame_006.png`）、技能页（原版帧见私有档案：`runtime_observations/original_gameplay_reference/06_status_and_stats_screen/frame_028.png`） |
| 道具子菜单、持物光标与选目标 | 07 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/07_item_equip_and_trade/contact_sheet.jpg`） | 子菜单（原版帧见私有档案：`runtime_observations/original_gameplay_reference/07_item_equip_and_trade/frame_011.png`）、目标选择（原版帧见私有档案：`runtime_observations/original_gameplay_reference/07_item_equip_and_trade/frame_017.png`）、道具页（原版帧见私有档案：`runtime_observations/original_gameplay_reference/07_item_equip_and_trade/frame_031.png`） |
| 气刃斩选目标，原目录误标普通攻击 | 08 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/08_attack_target_selection/contact_sheet.jpg`） | 技能名与红格（原版帧见私有档案：`runtime_observations/original_gameplay_reference/08_attack_target_selection/frame_004.png`） |
| 气刃斩列表、选目标、取消 | 09 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/09_special_skill_selection/contact_sheet.jpg`） | 列表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/09_special_skill_selection/frame_007.png`）、选目标（原版帧见私有档案：`runtime_observations/original_gameplay_reference/09_special_skill_selection/frame_013.png`） |
| 帝国兵普通攻击、一般兵受击 | 10 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/10_combat_normal_soldier/contact_sheet.jpg`） | 攻击（原版帧见私有档案：`runtime_observations/original_gameplay_reference/10_combat_normal_soldier/frame_009.png`）、受击前（原版帧见私有档案：`runtime_observations/original_gameplay_reference/10_combat_normal_soldier/frame_015.png`）、受击后（原版帧见私有档案：`runtime_observations/original_gameplay_reference/10_combat_normal_soldier/frame_021.png`） |
| 重装兵攻击与法师受击 | 11 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/11_combat_knight_and_mage/contact_sheet.jpg`） | 重装兵（原版帧见私有档案：`runtime_observations/original_gameplay_reference/11_combat_knight_and_mage/frame_007.png`）、法师受击（原版帧见私有档案：`runtime_observations/original_gameplay_reference/11_combat_knight_and_mage/frame_014.png`） |
| 雷欧纳德普通攻击、死亡、KILL | 12 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/contact_sheet.jpg`） | 起手（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/frame_004.png`）、刀光（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/frame_008.png`）、目标 5/22（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/frame_015.png`）、扣至 0（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/frame_022.png`）、KILL 2（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/frame_039.png`） |
| 气刃斩分镜与地图交接 | 13 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/contact_sheet.jpg`） | 眼部横幅（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_001.png`）、持剑（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_007.png`）、双框（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_014.png`）、极速线（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_027.png`）、目标 22/22（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_041.png`）、命中（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_047.png`）、伤害 22（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_055.png`）、遗言（原版帧见私有档案：`runtime_observations/original_gameplay_reference/13_leonard_special_skill_cutin/frame_067.png`） |
| 幻火在地图上的前摇、爆破与受击 | 14 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/contact_sheet.jpg`） | 红格（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_006.png`）、前摇（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_016.png`）、爆破（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_036.png`）、24/43（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_041.png`）、伤害 19（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_046.png`）、EXP（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_051.png`） |
| EXP 与金钱字样 | 15 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/15_post_attack_settlement_floats/contact_sheet.jpg`） | EXP 27（原版帧见私有档案：`runtime_observations/original_gameplay_reference/15_post_attack_settlement_floats/frame_006.png`）、$ 100（原版帧见私有档案：`runtime_observations/original_gameplay_reference/15_post_attack_settlement_floats/frame_011.png`） |
| 战利品取物前后与持物状态 | 16 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/contact_sheet.jpg`） | [取物前（重制画面）](../../../screenshots/remake/loot-window.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/frame_003.png`）、持物（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/frame_006.png`）、入包后（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/frame_008.png`）、再次持物（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/frame_019.png`） |
| 报告、目标变更与后续战斗 | 17 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/17_story_events_and_victory/contact_sheet.jpg`） | 对白（原版帧见私有档案：`runtime_observations/original_gameplay_reference/17_story_events_and_victory/frame_013.png`）、[地图目标文字（重制画面）](../../../screenshots/remake/mission-card.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/17_story_events_and_victory/frame_018.png`） |
| 结束、结算及宫殿过场 | 18 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/18_ending_and_next_scene/contact_sheet.jpg`） | 死亡对白（原版帧见私有档案：`runtime_observations/original_gameplay_reference/18_ending_and_next_scene/frame_004.png`）、金钱（原版帧见私有档案：`runtime_observations/original_gameplay_reference/18_ending_and_next_scene/frame_007.png`）、结束台词（原版帧见私有档案：`runtime_observations/original_gameplay_reference/18_ending_and_next_scene/frame_010.png`）、宫殿（原版帧见私有档案：`runtime_observations/original_gameplay_reference/18_ending_and_next_scene/frame_014.png`） |

### 已审查的观察与使用边界

以下观察都是 `runtime-measured`，指本录像中的可见现象。对应原帧见上表；数值公式仍回到 [机制矩阵](../../../MECHANICS_EVIDENCE_MATRIX.md) 和源表／原函数证据。

**V01 对话。** `02/frame_004` 的面板上沿约在录制坐标 y=320，左肖像、右姓名与正文分区，正文白色、姓名浅绿色；当前页可见三行正文。`detail_crops/dialogue_box_detail.png` 是裁切片，不能用其 145 像素高度推断完整对话框。字体家族、原字号、精确行高／阴影和全部分页条件仍未测定；用原 RESOURCE 正文，不能转写模型编出的台词。

**V02 空间。** `04/frame_001` 的单格为轴对齐方形，横纵间距约 32 像素；可达格集合形成菱形外轮廓。这与已有 `cell=(32,32)` 的来源合同相容，不支持把单格改成 64×32 等轴测菱形。颜色和半透明程度可作视觉参考，精确 RGBA／混合模式待源素材或受控取样。脚点、镜头、网格、遮挡和点击必须一起核对。

**V03 菜单。** 本样本显示六项菜单、图标动画与悬停变化；不能推导所有状态永远六项。现有 BCMD／EXE 布局和展开 helper 证据继续有效；秒数、输入触发与边缘布局按具体状态对照。

**V04 身份栏。** `10`、`12`、`13` 的特写为先攻方、后受击方的单人分镜；底部左右区域属于当时显示的同一个角色：左边肖像／资源，右边档案。它不是“左攻方、右守方”的双人状态栏。部分敌人字段实际显示 `???`，不能从本包声称任意悬停都会公开准确 HP、等级或 90% 命中率。

**V05 状态页。** `06/frame_006` 的原版 UI 确实显示“魔擊力 17%”。审查时 `BattleStatusPanel.show_unit` 只格式化整数，旧项目文档把去掉百分号写作原版正确性修复，现已更正；后续 [对白／选择修正](../../static_reverse/original_dialogue_board.md) 已恢复后缀。该证据只支持显示后缀，不支持把规则数值乘／除 100 或改成命中率。四基础属性和装备布局可参照；宝石的元素语义、全职业属性和状态颜色不能仅靠颜色猜测。

**V06 攻击与受击。** `12` 展示目标从 5/22 到 0/22，并显示 5；`13/frame_055` 清楚显示 22，原报告把动画中重叠的两位数读成了 2。数值是此时此目标的结果，不是固定伤害公式。受击存在专用姿势，不支持把所有立绘统一旋转 20°～30°。HP 条是否插值、震屏幅度与先后帧差，需要连续原帧测量。

**V07 气刃斩。** 眼部横幅、持剑框、侧面特写、紫色线条、目标青色命中特效、受击及地图遗言的顺序有图支持。原交付 `Frame 001~080` 是采样图片编号，不是 80 个连续视频帧，更不是已测得的六段边界。音效名称和时刻未验证。

**V08 地图法术。** `14` 可辨“幻火”、地图暗化、火焰、一个目标的 24/43 HP 和伤害 19。不能据此认定填满的 3×3 范围、所有附近单位同时受伤，或把 43／24 读成伤害；范围、资格和结算读 MAGIC／RANGE 及共享技能规则。

**V09 结算。** `15` 有紫色系 EXP 27、金色 $ 100；`12` 有 KILL 2。本包没有证明“连击”、固定上升 35px、1.2 秒、前置加号或 LEVEL UP 完整演出。`16` 展示“獲得物品”、绿色选中条目、持物、入包前后与资金 1410；掉落触发、满包、放弃、重复确认、金币规则尚不能从单条成功路线恢复。

**V10 剧情。** `17` 的目标文字显示在地图上，本样本不支持“羊皮纸任务横幅”。`18/frame_010` 可见“現在，才是真正的開始……”；实际正文仍以导入 RESOURCE 为准。录像时刻不等于回合号，下一场景画面不证明产品已实现正式跨关。原结尾接触表混入的桌面尾帧已从正式资料排除。

## 重制接线

本页不直接被规则消费；界面模块（如 `BattleDialogue`、`BattleSystemMenu`、`BattleItemPanel`、`BattleLootPanel`、`BattleEquipmentView`）的 provenance 头以 `runtime-reference` 引用本包具体帧，视觉差异应指向本包帧号与当前重制帧。

## 复现

### 帧号、时刻与复核

`manifest.json` 是机器入口。每张保留原帧记录文件 SHA-256、RGB 像素 MD5、录制尺寸及 `source_frames`；后者是从完整视频像素匹配得到的 **零起算解码帧号**。本录像 `秒数 = source_frame / 30`。若完全相同画面对应多帧，保留全部候选，不假装唯一时刻。

例如 `04/frame_001` 对应源帧 1057，即 35.233… 秒；它不是第 1 个视频帧，也不能由分类开始时间机械计算。接触表各格的 `export_ordinal` 和源帧候选单独列出；细节裁切仍标 `legacy_detail`，仅作导航，不用来报告新测量。

```sh
# 不依赖原视频、Wine、raw 目录；也纳入 tools/verify.sh。
/opt/homebrew/bin/python3 tools/hsl.py check gameplay_reference

# 有原始归档时，额外重解码录像，复核保留原帧的像素／帧号。
PYTHONPATH=tools /opt/homebrew/bin/python3 -m hsltools.evidence.gameplay_reference \
  --video ../hsl-fork-raw-archive-20260914-gameplay/record.mp4
```

## 边界

- 校验成功只证明文件和索引一致；不能自动证明本页描述、交互因果、音效、游戏 tick 或重制版视觉一致。`.gdignore` 防止 Godot 将研究参考图片当产品资源导入。
