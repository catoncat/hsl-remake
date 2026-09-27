# 第一战实玩反馈修复

> evidence: runtime-measured · status: live · tools: capture_first_battle_review.gd, run_first_battle_playthrough.gd · updated: 2026-09-11

日期：2026-09-11。依据是用户本次六项反馈、同一对话前段实际执行的 Wine 单步路线/窗口录屏、原始表和 SHP，以及本轮 Godot 渲染。用户尚未对修改后的版本做最终接受。

## 原作构图参考

`original-attacker.png`、`original-defender.png` 是前段原作录屏的 640×480 游戏区域，来自 `ignored/acceptance-fixes/` 同名已检查图片。原片为 `original-attack.mov`，raw 片不属于产品依赖。本轮恢复施工阶段没有再次启动 Wine。图片证明本次普通攻击先展示攻击者、再展示受击者，下方状态栏占约 160 像素；不能据此证明全部技能、时钟或混色等价。

## 当前实现及复跑

`tools/play.sh` 先检查资源导入再运行，避免完整验证清缓存后直接启动灰屏。

`tools/play.sh --screen 1 --resolution 640x480 --script res://tests/capture_first_battle_review.gd` 生成 `ignored/acceptance-fixes/review/`。这是改变坐标/HP/等级的受控渲染夹具，包含地图范围→移动目标框→锁定、各类普通攻击与受击、风/火/气刃斩、状态页、成长预览与真实鼠标确认。不能把夹具说成自然升级路线。

`tests/run_first_battle_playthrough.gd -- hold` / `-- advance` 使用默认正式入口、正常时钟、真实 Godot 输入，不改 HP、坐标或战斗 RNG。驱动附带存活演员可见性检查和少量 `live-*` 截图。完整非 GUI 门禁仍为 `tools/verify.sh`；最后的退出结果与日志位置在提交说明中记录。

本目录 `current-*` 为复跑夹具截图，`proof.json` 保存哈希及生成来源。它们供人工看画面，不是图片相似度自动断言。

## 六项修正与证据边界

行走 0.30 → 0.20 秒/格，四格固定 0.80 秒；攻击地图预告独立为 0.24 + 0.22 + 0.24 秒。路径、游戏数值、行动速度队列未按动画比例缩放。时间取值是本轮可读性选择，不是假造的原版测量。

普通特写使用原尺寸、原绘制锚点与 640×320 裁切区，不再把预裁切角色缩小成双人全身对战。下方接原版肖像、WINDOW10 和实时数值。P001_201..207 是预合成的施放画面，须使用其中心锚点，不能沿用站立角色的脚点。

ANIMAL 的攻击闪光偏移由 importer/checker 消费。风刃和幻火的原表 `eff_proc_Local` 决定在地图播放；补入 AIR02 和 AIR04_02，保留火焰后续阶段及源 `0x00014000` 缩放。专用气刃斩施放帧、射出/命中画面已消费，但精确的原版复合画面调度、随机粒子运动、更新频率和混合 handler 尚未证明恢复。

致死先结算只改变 PlayLoop 真相；地图演员保留到可见攻击完成，地图法术致死淡出。演员和树木使用同一脚点 Y 深度域，移动中持续更新，修正所有演员永久位于所有前景后面的错误。存活节点存在/visible 检查不能证明每个遮挡像素都与原作相同。

状态/成长使用原版窗体和装备位置，清掉常驻键位说明/最近交锋，保留目标和选敌反馈。成长仍是已实现的生命/攻击/防御三选项，不声称原作四属性加点或全装备系统。首次攻击画面保留 EXP-before，避免未出招就显示升级。
