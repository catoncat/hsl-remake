# 漆黑之森（level 31）：正式战斗

> evidence: runtime-measured; resource-derived; static-derived · status: live · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行，不是原 EXE 现场。STORY031、WINFAIL031、EVEF 编队与 item 252 token 顺序为 resource-derived/static-derived；镜头、等待、强制胜利与结果页是 remake pacing，不能据此声称原版等价。

## 回执

- [first-control.png](first-control.png)：开场后首次控制，9 名单位、3 名受控。
- [key-dialogue.png](key-dialogue.png)：WINFAIL031 增援/胜利段对白。
- [result.png](result.png)：强制胜利结果页，续接 source actSetNextPlayLevelEvent(31,71)。
- [review_manifest.json](review_manifest.json)：完整窗口化采样 manifest。

验证：capture_battle_review.gd -- --level=31 输出 BATTLE_REVIEW_PASS；夹具只推进 WINFAIL031 的 source event_4 胜利状态，不证明 AI、平衡或原版节奏。

## 边界

item 252 的 native timing、脚本演员实际退场时钟和 big-map 后续由 shared remake route 处理，均为 provisional。
