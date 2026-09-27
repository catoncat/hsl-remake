# 拉格納沼地（level 32）：正式战斗

> evidence: runtime-measured; resource-derived; static-derived · status: live · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行，不是原 EXE 现场。STORY032、WINFAIL032、EVEF 编队、毒雾对象与 item 252 token 顺序为 resource-derived/static-derived；镜头、等待、serial cursor 与强制胜利是 remake pacing，不能据此声称原版等价。

## 回执

- [first-control.png](first-control.png)：开场后首次控制，22 名单位、3 名受控。
- [key-dialogue.png](key-dialogue.png)：强制胜利对白段。
- [result.png](result.png)：强制胜利结果页，续接 source big-map hand-off 33,34。
- [review_manifest.json](review_manifest.json)：完整窗口化采样 manifest。

验证：capture_battle_review.gd -- --level=32 输出 BATTLE_REVIEW_PASS；夹具只证明结算流转。

## 边界

actCheckNextSerialNumber（交接计数定时器）与 actInsertStoryObjectWaitPos 的坐标请求已进入共享解释器，噴人沼氣的喷毒照原版（[噴人沼氣包](../../static_reverse/original_poison_gas.md)）；原生等待时钟与 item 252 timing 为 provisional。
