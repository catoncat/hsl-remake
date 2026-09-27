# 正式宝箱：领取、行动交接与跨场保留

> evidence: runtime-measured · status: live · tools: capture_treasure_review.gd, run_treasure_tests.gd · updated: 2026-09-19

本包记录实际 **Godot重制版**，不是原游戏整场运行。原 EVEF 内容及有界执行见[原宝箱证据](../../static_reverse/original_treasure.md)；[receipt.json](receipt.json)保存八条唯一路线、精简前后状态、真实进程与原尺寸帧哈希。

## 玩家入口

正式歐姆村和戈爾山道使用原三只箱。走到箱格并完成行动后显示发现提示，再进入物品领取；取消暂定移动不会领取。满包可交换，取消选项不消耗物品，稍后领取会保留。普通队伍胜利后确认延后，可以点击“保留物品並繼續”进入后续剧情；它与“查看待领物品”分别显示。

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 0 res://game/battle/development/OhmVillage.tscn
# 或同一正式戈爾山道配置：
tools/godot.sh --screen 0 res://game/battle/development/GolRoad.tscn
```

本轮枚举的内建屏是0，复跑前须重新确认。窗口640×480、正常时间倍率，验收进程各有独立user目录，不改玩家存档。

## 八条完成的真实控件路线

| 路线 | 起点与输入 | 已验证结果 |
| --- | --- | --- |
| `natural_pickup` | [preceding_party.json](preceding_party.json)精确提取此前未改编队的歐姆村自然胜利存档，逐人物对照原窗口收据；Leonard Lv2/EXP87、Hu Lv4/EXP32，原有物品、钱包及生成流。不重做歐姆村，Gol正常原开场 | 实际走到东箱、移动中F5/F9、Esc退回再选格、Wait发现、取消领取、领取闊刃劍、F9、延后回復藥并恢复下一行动。**不是本次Gol自然通关** |
| `full` | 明示前置：Leonard在歐姆村箱格，八份241、白光之翼、永久攻击+3及禁魔两回 | 满包必须选交换槽；取消无变化；玻璃戒指入包、换出药留下；F9后延迟领取，第二行动前状态不扣，实际装备戒指不重发永久增益／EXP，第二次Wait不再开箱 |
| `duplicates` | Hu在Gol西箱格，源角色／装备／库存不加值 | 两份244分别领取，F9仍是两份；254放弃先取消后确认，箱保持已开且下一行动继续 |
| `attack` | Hu在Gol东箱；一名既有强盗1HP、合法射程内，命中补偿1000 | 真实弓击杀、经验和既有战利品先结束，然后发现箱；交锋序列与领取序列分离，原掉落和箱内物品并存；F9不重播攻击或开箱 |
| `defeat` | Hu1HP在东箱，较快先动，随后相邻高攻击／速度且命中补偿1000的原强盗 | Wait开箱后延后，真实AI攻击触发琥死亡与正确003头像对白；F9保留已开箱／待领列表，实际重新挑战恢复新场七人和未开箱 |
| `victory` | 明示第二阶段前置：原入队事件已完成，两追兵剩余，第一名1HP在合法弓范围；Hu在箱格，白光之翼、速度+300、命中补偿1000 | Wait取箱并延后，第二独立行动实际射击触发原win_0和完整尾声；胜利冻结后续开箱／行动，F9精确恢复，显示互不重叠的查看与保留继续按钮。**不是自然战斗难度证明** |
| `campaign` | 不同进程读取上一条真实末击生成的victory.save；同时检查生产PID不等于读取PID、存档SHA不变 | F9恢复完整原快照，真实继续按钮进入55黄昏→56清晨→世界；三人、钱包、成长与待领物品逐场JSON一致并落盘 |
| `resume_pool` | 使用上一条真实world carry，明确选择下一次Gol正式入口作为夹具，播放原开场；不是声称原地图一定再次选择同场 | 真实界面显示“保留的物品”，领取一件后F9，原新场箱未被开启，延后剩余物品并恢复行动。此路线只验证旧物品池，不宣称完整成员再入队／世界遭遇逻辑 |

## 进程与复跑

四个采纳进程均实际退出0，运行期间HEAD／未提交差异指纹不变。第二个进程也完成过victory，但该路线只采纳后续专门的生产进程，避免重复计数或用旧帧代表新的继续按钮。逐帧断言次数不是覆盖率。

| 日志（ignored/treasure/） | 采纳 | 秒 | 原日志SHA256 |
| --- | --- | --- | --- |
| render-pickup-final.log | natural_pickup | 28.694 | b975397ea1773f53b8d1225df8ab0e310806f9919068652b71718c4f2d26a176 |
| render-variants-final.log | full、duplicates、attack、defeat | 60.910 | 8e855bd6dab70ccef04e81fefccd7ff95797dc5982f10a10e520e961ea9dc280 |
| render-victory-producer.log | victory，PID22605 | 17.510 | 7241c11f7304b6630332814b1b66ef045a2de76f50fc8c6df3a4823f8a5b544d |
| render-fresh-carry.log | campaign、resume_pool，PID24459 | 36.299 | a217b56578e43db9da0508f94951d2fc8d0c0c16bcc51f52f58570074cd68822 |

```sh
tools/godot.sh --screen 0 --script res://tests/capture_treasure_review.gd -- natural_pickup
tools/godot.sh --screen 0 --script res://tests/capture_treasure_review.gd -- full duplicates attack defeat
# 必须分为两个进程且顺序执行；不能把场景重建冒充跨进程恢复：
tools/godot.sh --screen 0 --script res://tests/capture_treasure_review.gd -- victory
tools/godot.sh --screen 0 --script res://tests/capture_treasure_review.gd -- campaign resume_pool
```

最后一条需要上一条留下的`ignored/treasure-review/victory.save`及生产信息。旧Ohm二进制存档不作为仓库测试依赖；preceding_party的输入、哈希和原逐人物一致校验来源已整理在本包。

## 已检查画面

![只移动尚未开箱，F9保持](natural_pickup-restored-1.png)

![发现提示先于后继控件](natural_pickup-discovery-1.png)

![实际领取一件后F9](natural_pickup-restored-2.png)

![满包明确交换，药物留下](full-exchange-preview.png)

![重复原物品分别取得](duplicates-duplicates-claimed.png)

![原交锋掉落与宝箱待领并存](attack-after-attack-loot.png)

![琥实际败北对白的源头像](defeat-hu-defeat-dialogue.png)

![胜利后查看与保留继续分离](victory-victory-deferred.png)

![另一进程恢复并跨场后继续领取](resume_pool-carried-item-claimed.png)

receipt中的16张均以原640×480检查；另外包括取消后下一行动、实际换装、败北／重开、黄昏／清晨营地和世界返回。音频记录是实际播放流，不是物理扬声器或原版时钟测量。

## 实际发现的缺陷与修正

跨战JSON里的空槽0.0曾使领取界面错误提示“背包已滿”，但库存规则认为可插入；独立红例退出1，修复为先验证再规范持久库存，UI使用同一个插入提案兼容旧合法存档。篡改的宝箱交接队列索引曾在校验前越界，小数／字符串交锋序列曾被截断接受；现访问前严格拒绝。实际琥败北缺少说话人2→003头像，已窄修原有映射。

只保存pending_rewards字段仍不够：真实胜利页原先隐藏所有有待领物品的继续按钮。source-owned战役子类现开放安静、普通队伍、明确延后的合法入口，领取打开中和独立队伍仍拒绝。最后跨场夹具也发现开发入口在AI被待领物品阻挡时无限快进；循环现让出领取，正式开场和headless回归均覆盖该边界。

先前数次自动打法以队员阵亡结束，不进入自然通关统计。移动取消后返回move_select、已选接收者无需重开popup、胜利会重新打开原待领列表等正确产品行为，验收脚本已按合法操作修正，不削弱规则。一次前段进程完成victory／campaign后在开发入口卡住，被终止143，其具名结果未冒称整进程PASS；最终上表是修复后的完整进程。原时钟、隐藏宝物、所有关卡宝箱、全局永久开箱标志、AI主动搜箱和完整成员再入队仍不由本片恢复。

`tests/run_treasure_tests.gd`目前78项覆盖原内容、零随机、既有领取、满包交换、第二行动、终态、保存篡改、JSON空槽、真实继续控件及开发入口让出。完整验收仍以最终稳定差异的`tools/verify.sh`退出回执和本地提交为准，窗口或定向数量不替代完整门禁。
