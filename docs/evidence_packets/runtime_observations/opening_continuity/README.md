# 当前版本的连续开场验收

> evidence: runtime-measured · status: live · tools: capture_battle_scene_continuity.gd · updated: 2026-09-05

2026-09-05，Godot 4.7.2，640×480。菜单边缘处理与可达攻击 AI 接入后已重新运行并更新本包。此包记录重制版运行结果，不是原作 runtime parity 证据。

从正式场景默认入口开始，不调用 dev first-control，不加速时间。通过 `Input.parse_input_event` 依次注入 Space 按下/释放，确认七段对白：363、364、365、366、367、364、1101；再让标题与前置 AI 行动自然推进至雷欧纳德行动菜单。

复跑：

```sh
godot --headless --path . --import
godot --path . --resolution 640x480 --script tests/capture_battle_scene_continuity.gd
```

脚本输出 `ignored/opening-continuity/`，成功必须出现 `OPENING_CONTINUITY_PASS`。它校验对白顺序、八个取样阶段、标题可见、选中雷欧纳德和菜单可见，35 秒 watchdog 会明确失败。图片由渲染器主动绘制后读取；此前被动等待 `frame_post_draw` 会让截图流程在无下一绘制回调时停住。没有为这个辅助工具问题修改游戏逻辑。

已人工核对：人物与原表头像一致；最长开场对白及士兵长台词均完整显示；两次 364 分别属于一般兵与重装兵；标题在淡入后可见；首次控制时对白消失、菜单与当前角色对应。`receipt.json` 保存事件、说话人、标题状态、交接结果和下列精选截图哈希。

- `soldier-dialogue.png`：长台词、一般兵头像和确认提示。
- `chapter-title.png`：原版「弃卒」标题完成淡入。
- `first-control.png`：首次正常控制、队形及行动菜单。

这是连续开场及视觉交接的验收，不覆盖鼠标设备差异、原版时钟尺度、原版全部入场路线、混音或整个第一章功能。脚本复用正式输入和场景，没有新增产品测试开关；去掉被动绘制等待后同一路线通过。
