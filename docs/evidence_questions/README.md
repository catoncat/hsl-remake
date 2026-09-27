# Evidence Questions

本目录保存经过整理的用户复核问题包和答案包。它的目标是把资源、脚本、截图、静态分析或候选机制中最需要人工判断的部分,压缩成小问题,并把答案按证据层级记录下来。

## 文件类型

- `*.questions.json`:问题包。通常引用已经整理过的小图、contact sheet、资源候选或文字证据,用于让用户做有限选择或纠错。
- `*.answers.json`:答案包。记录用户提交的选择、备注、回答时间和上下文说明。
- contact sheet 或小图:如果存在,只能是 curated 小证据。大截图、录屏、burst frame、raw trace 和临时运行产物默认仍放 ignored。

## 证据层级

- 用户明确确认且不确定性低的回答记录为 `user-confirmed`。
- 用户表示好像、可能、不记得、需要更多证据的回答记录为 `user-hypothesis`。
- 用户回答不能自动升级成 `static-derived` 或 `runtime-measured`。只有原版资源、脚本、数据表、可执行文件分析或运行时样本支持时,才可升级。
- 一个结论如果混合了多种来源,要拆成多条 source-tagged facts,不要合并成一个无来源的确定事实。

## 当前答案包

- `2026-06-21-first-battle-visual-objects.answers.json`:用户确认 `tree07.SHP` 是视觉+阻挡对象,`FIRE01-01.SHP` 是动画前景,`bar004a/bar004b` 是必须叠加的桥/木板视觉层;并确认第一战单位 sprite 身份分层:Leonard/player-commanded、AI-Controlled Allies、Enemy Force。
- `2026-06-21-bcmd-icon-identity.answers.json`:用户确认 `BCMD06=交换`,`BCMD07=装备`,`BCMD09=魔法`;`BCMD05` 是治疗相关的可能记忆,`BCMD10/11/12` 可能是特殊技相关且 hash 相同;`BCMD14/15` 未知。

## 使用原则

- 先查 `CONTEXT.md`、`docs/MECHANICS_EVIDENCE_MATRIX.md`、`docs/PROJECT.md` 和当前资源/静态/runtime 证据,再决定是否需要问用户。
- 只问会改变模型边界、资产分类、命令身份、证据路线或可见复刻优先级的问题。
- 不要让用户逐项确认战棋常识,不要把 broad gameplay narration 当作证据包目标。
- 答案应回灌到 `CONTEXT.md`、`docs/MECHANICS_EVIDENCE_MATRIX.md`、Godot 数据或后续 evidence task,并保留 unresolved 分支。
- 证据问答服务玩家可见复刻,不是默认要求 Godot 显示 evidence dashboard。
