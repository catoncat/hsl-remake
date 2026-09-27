# 实际 Wait 触发 AI 施法／特殊技

> evidence: runtime-measured · status: live · tools: capture_ai_decision_review.gd · updated: 2026-09-14

2026-09-14，内建屏640×480窗口位于 `(1760,400)`。`capture_ai_decision_review.gd` 通过 `Viewport.push_input` 点击真实Wait按钮，后续完全由Runtime正常AI循环、公共结算和演出推进。未发送桌面鼠标键盘，未直接触发按钮signal或调用AI执行来代替交互验收。

两条显式四人夹具均保留原角色技能拥有权；调整队列／位置、400HP、关闭反击。026魔法倾向设100以稳定这条视觉路线，原95以及各种概率／奇偶组合由原函数回归另测；友军Leonard有ST100并由AI控制，正常第一战仍是玩家控制、ST0。先行可控角色Wait，然后该AI行动，再交给后继可控角色。

| 图证 | 观察及收据 |
| --- | --- |
| [法师幻火](enemy026_1-cast.png) | 实际地图目标处出现源火焰；魔法类别通过共同资格，MP30→22，一次扣8 |
| [友军气刃斩](leonard-cast.png) | 实际特殊技演出与名称；ST100→80，一次扣20，与玩家同一结算路径 |
| [后继控制](leonard-handoff.png) | 演出完毕进入下一可控角色操作；队列index=2，即先行玩家、AI各完成一次；没有重复AI动作 |

[receipt.json](receipt.json)保留原类别选择的99上界样本、目标索引、单笔扣费、下一角色和零失败记录。视觉检查确认幻火在地图上、气刃斩使用原技能图像，技能标题／生命与气力显示可见；不把这些画面声称为原游戏自然路线或完整原版时序。

```sh
godot --path . --position 1760,400 --resolution 640x480 \
  --script res://tests/capture_ai_decision_review.gd
```

在其他机器运行时须先确定内建屏位置。整条脚本有55秒上界，成功输出 `AI_DECISION_RENDER_REVIEW_PASS`；原始文件在 `ignored/ai-decision-review/`。这是展示验收，200组原函数返回及坏输入／队列原子性见 [原AI证据](../../static_reverse/original_ai_decisions.md)。
