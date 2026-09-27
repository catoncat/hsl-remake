# 施法装备与生命转魔力：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_casting_equipment_review.gd, run_position_equipment_tests.gd · updated: 2026-09-18

基线`046b87f`上的SR-057实现，使用原地图、角色美术、装备职业资格和实际鼠标／键盘控件。窗口640×480，仅内建屏1，正常时钟。原指令证据与本组Godot实玩分别记录：前者见[装备源合同](../../static_reverse/original_casting_equipment.md)，本页机器回执为[receipt.json](receipt.json)。合成库存、当前HP／MP、受控法师、概率与场景位置均列入回执，不属于正式第一战额外授予。

## 走通的体验链

| 路线 | 实际覆盖 |
| --- | --- |
| poison_tail、full_mp、one_hp | 血衣装卸预览／取消，毒伤→自动HP→自动MP→扣HP换MP五段；满魔仍损生命，1HP仅推进抽样而无虚假数字／死亡 |
| remove_restore、accuracy | 第二行动卸衣与F5/F9，不重发血量或次数；两个命中饰品共同进入实际風刃命中，移动施放后付款一次 |
| blood_growth、blood_support、blood_item | 第二行动击杀、经验／成长后按新上限转化，下次移动施法并获非击杀贡献；回魔资助减耗治疗；用药声与反馈完成后再转化 |
| poison_guard、silence_guard | 免疫与未保护者同一范围分别反馈；卸掉最后来源后可受状态，重装不清既有状态；防禁魔保留前段伤害，既有禁魔仍禁用列表 |
| detour、ai_blood、ai_silence | 实际地形绕路；AI先无MP／禁魔回退，末尾转化和到期后，下个真实队列周期重新选取并支付减耗風刃 |
| victory、defeat、escape | 第二行动清敌胜利、致命反击败北与源撤离格待机；冻结未执行的转化，终态保存恢复和实际按钮重开 |

默认装备／授予未变；已完成的三职业、双击／两次行动及通行数值证据直接复用。全体场景和默认入口仍由完整非GUI门禁覆盖，本批不把装备夹具写成默认自然通关。

## 图证

血衣的完整代价说明与五段反馈见[装备预览](blood_growth-equip-145-armor.png)、[毒伤](poison_tail-tail-1-0.png)、[转化生命](poison_tail-tail-1-3.png)、[转化魔力](poison_tail-tail-1-4.png)。[混合防毒](poison_guard-impact-1.png)分别显示免疫／中毒，[已有禁魔](silence_guard-still-silenced.png)保持技能不可用。[成长完整预览](blood_growth-growth-resists.png)和[AI再次施法](ai_blood-impact-2.png)覆盖派生上限与下一行动。

三种终态：[清敌](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)。这些图片均已按原尺寸检查；哈希见回执。数字与次序来自已提交事务，0.7秒逐段提示仍是重制可读性时钟。

## 失败修正与证据范围

早期防护夹具装入八件道具后无空间卸装，产品正确拒绝；修正为只提供该路线所需装备及空位。后续剩余路线的进程在四条完成后遇到“新施加1回合禁魔”错误，终止退出143，保留此前四条具名成功范围；改为合法状态的1回合剩余计时。下一进程完成AI禁魔与胜利后，败北夹具同时设置了禁止攻击和致命反击，导致正确跳过反击而未进入败北，进程退出1；修正矛盾后败北／撤离进程退出0。回执将每次进程和可接受路线分开，不称失败进程全绿。

更早的两组五条／三条成功路线有匹配PASS日志和JSON，原终端退出码未保留，按该范围记录。最终完整门禁的真实结果见本批提交说明，不以某条PASS文本代替进程结果。

```sh
tools/godot.sh --screen 1 --script res://tests/capture_casting_equipment_review.gd
tools/godot.sh --headless --script res://tests/run_all.gd -- run_position_equipment_tests.gd
tools/verify.sh
```

原函数执行只覆盖已列getter、完整refresh与转化前段；整个原dispatcher、全局随机流、伙伴自动成长与大型占地不由这些路线证明。
