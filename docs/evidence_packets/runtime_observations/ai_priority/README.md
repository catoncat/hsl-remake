# AI 自救与残血机会：实际 Control 验收

> evidence: runtime-measured · status: live · tools: capture_ai_priority_review.gd · updated: 2026-09-14

2026-09-14，SR-037。`tests/capture_ai_priority_review.gd` 在有渲染的 Godot 窗口中，以实际Wait按钮的按下／释放事件触发 Runtime。随后由正常时钟完成AI选择、用药或移动／攻击演出和下一可控角色交接，未用直接AI调用替代这条可见路线。

| 路线 | 实际观察与收据 | 图像 |
| --- | --- | --- |
| 自救 | 身上两份241回复药，HP4→44，只耗一份；显示+40HP，期间下一角色菜单隐藏；重复收据不重复反馈 | [self-medicine-effect.png](self-medicine-effect.png) |
| 近战机会 | 普通搜索有健康近敌，实际进攻改为另一个HP8残血目标，走合法路径后攻击 | [wounded-melee-effect.png](wounded-melee-effect.png) |
| 法术机会 | 对残血对象使用受支持伤害法术，一次MP扣除，播放当前地图法术效果 | [wounded-magic-effect.png](wounded-magic-effect.png) |
| 后继控制 | 各路线只有一个AI行动收据，队列index2直接到enemy023_1；反馈完毕显示其真实命令菜单 | [self-medicine-handoff.png](self-medicine-handoff.png) |

图像已人工检查：回血文字位置和数额、近战分镜、地图法术与后继菜单正常；测试脚本另断言反馈门禁、重复抑制、唯一扣费和交接。精简实际结果及PNG SHA-256见 [receipt.json](receipt.json)。未改变动作素材、默认镜头合同或常规演出速度。

这是明确的重制运行夹具：五单位队列与位置、健康HP400／残血HP8／自救HP4、两份自救药、counter0；026的魔法倾向设100保证可见类别，正常来源95仍由纯规则覆盖。初始角色／敌我控制与当前第一战不等同，未声称原作自然游玩或整个AI恢复。其余角色默认空包仍保留；真实给予后友军用药另由 `run_ai_priority_tests.gd` 的共享PlayLoop组合回归证明。

渲染设备已确认是内建屏；启动参数`--position 160,160 --resolution 640x480`，root记录640×480像素，macOS Retina窗口按屏幕缩放显示。图片只保存游戏viewport，没有截取桌面。原规则证据与限制见 [original_ai_priority.md](../../static_reverse/original_ai_priority.md)。

```sh
godot --headless --path . --import
godot --path . --position 160,160 --resolution 640x480 \
  --script res://tests/capture_ai_priority_review.gd
```

图片及原始详细回执先写入`ignored/ai-priority-review`，55秒总上限；无系统鼠标／键盘操作。渲染失败必须保留原失败信息，不把headless结果代称可见验收。
