# 黃昏之丘　陰（level 33）：正式战斗

> evidence: runtime-measured; resource-derived; static-derived · status: live · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行，不是原 EXE 现场。STORY033、WINFAIL033、EVEF 编队与 item 252 token 顺序为 resource-derived/static-derived；镜头、等待、结果页与强制胜利是 remake pacing，不能据此声称原版等价。

## 回执

- [first-control.png](first-control.png)：开场后首次控制，15 名单位、4 名受控。
- [key-dialogue.png](key-dialogue.png)：WINFAIL033 关键对白段。
- [result.png](result.png)：强制胜利结果页；窗口 review 将 source big-map walk hand-off 规范为可见结果页。
- [review_manifest.json](review_manifest.json)：完整窗口化采样 manifest。

验证：capture_battle_review.gd -- --level=33 输出 BATTLE_REVIEW_PASS；夹具先满足 source event_4 的玩家计数条件，world-map hand-off 规范仅属于 review。

## 边界

item 252 native timing、敌方不死军团的实际 AI 与 source big-map walk 的完整消费者仍为 provisional。
