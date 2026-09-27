# 原版战斗分出胜负后的流程：没有结果页（static-derived）

> evidence: static-derived; runtime-measured: 2026-09-24 第一战录屏胜利段（509.5–516.9 s） · status: live · functions: 0x42aea0, 0x42afc0, 0x42cb90, 0x42cbd0, 0x42cc10, 0x42dc90, 0x453a80, 0x45e307 · updated: 2026-09-27

## 结论

原版战斗分出胜负后**不弹任何结果页**，也不等按键：胜利直接走画面转场进 winfail 写好的下一关／事件（剧情、大地圖或下一战），败北直接转场进 GAME OVER（level 999），GAME OVER 画面按键或 160 tick 后回标题（level 0）。原版没有「重新挑戰」选项。

## 静态读（hsl01.exe）

| 事实 | 证据 | 等级 |
| --- | --- | --- |
| winfail 结果位检查每帧读状态位：bit 1（胜）调 `0x42cc10`，bit 2（败）调 `0x42cbd0` | `0x453a80` | static-derived |
| 胜：`[0x4c1b00] & 0x38000000` 已有离场请求或字节 `0x460989` 置位时跳过；否则 `[0x4c1b00] \|= 0x90000000`，把下一关／事件写进 `[0x4c1ba8]`／`[0x4c1bac]`，调 `0x42dc90(2)` 画面转场 | `0x42cc10` | static-derived |
| 败：下一关写 999（GAME OVER），`[0x4c1b00] \|= 0x88000000`，同一转场 `0x42dc90(2)` | `0x42cbd0` | static-derived |
| GAME OVER 的 BOSS 物件过程 `defProcGameOverBOSS`（PROCESS.DEF 58）：首帧播 GAMEOVER.WAV（RESOURCE 628），计数置 60 | `0x42aea0` | static-derived |
| phase 0：计数 > 40 时不收输入（首帧起前 20 tick）；计数归零（第 60 tick）或有输入时建字物件 `0x45e307(320,240,1,0)`，进 phase 1 等字物件交回（phase 1 不读输入） | `0x42aea0` `0x42af6f`–`0x42afb7` | static-derived |
| 字物件 `defProcGameOverWord`：首调缩放 `+0x20/+0x24 = 0x800`（1/32）、透明级 `+0x28 = 0`、半透明位 `0x20000000`、重装计数 4；此后每 tick 缩放 +0x200（到 0x10000 止，约 124 tick），计数每 4 tick 归零时透明级 +1（16 级，到 16 后下一次归零清半透明位）；本 tick 见输入置 `+0x80 \|= 0x10000`：缩放每 tick 再 +0x400、重装计数减半为 2。缩放满且透明级满的同一 tick（不加速时第 128 tick）进自身 phase 1，下一 tick 把 BOSS 阶段 +1 | `0x42afc0` | static-derived |
| phase 2 把计数置 160；phase 3 计数归零或有输入调 `0x42cb90`：下一关写 0（标题），`\|= 0x88000000`，转场 `0x42dc90(2)`；只有这一条出口 | `0x42aea0`、`0x42cb90` | static-derived |

## 录像（2026-09-24 中午 12.03.22 第一战，胜利段）

| 时刻 | 画面 | 等级 |
| --- | --- | --- |
| 509.5–511.5 s | 最后一名敌人的遗言 | runtime-measured |
| 511.5–513.5 s | EXP 71 | runtime-measured |
| 513.5 s 起 | 雷歐納德胜利台词（对白板） | runtime-measured |
| 约 515.8 s | 对白板关闭 | runtime-measured |
| 516.0–516.2 s | 战场淡到全黑（约 0.2 s） | runtime-measured |
| 516.2–516.4 s | 保持全黑 | runtime-measured |
| 516.4–516.9 s | STORY052 剧情画面淡入 | runtime-measured |

全程没有结算页，也没有等待按键。败北没有录像，按上表静态读。

## 复现

静态读无生成脚本，锚点按上表地址在 hsl01.exe 复核；录像段不可再生：原版侧唯一记录。
