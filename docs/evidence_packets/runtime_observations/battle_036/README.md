# 薩魯司海岸（level 36）：正式战斗

> evidence: runtime-measured; resource-derived; static-derived · status: live · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行，不是原 EXE 现场。STORY036、WINFAIL036、EVEF 编队、克羅蒂 009 安装、no-attack 与 item 252 token 顺序为 resource-derived/static-derived；镜头、等待、强制胜利与结果页是 remake pacing，不能据此声称原版等价。

## 回执

- [first-control.png](first-control.png)：开场后首次控制，16 名单位、7 名受控。
- [key-dialogue.png](key-dialogue.png)：克羅蒂安装/no-attack 关键对白段。
- [result.png](result.png)：强制胜利结果页，续接 source actSetNextPlayLevelEvent(36,gameBigMapLevel)。
- [review_manifest.json](review_manifest.json)：完整窗口化采样 manifest。

验证：capture_battle_review.gd -- --level=36 输出 BATTLE_REVIEW_PASS；夹具只证明 event_1 状态与结算流转。

## 边界

克羅蒂条件安装、no-attack 消费点、item 252 native timing 和 source scheduler 仍为 provisional。宝箱 record 24 的 source 坐标在地图外，正式宝箱产物显式记录为 skipped_out_of_bounds。
