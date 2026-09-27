# 脚本离场、事件游标与真实恢复验收

> evidence: runtime-measured · status: live · tools: capture_departure_review.gd, run_departure_tests.gd, run_first_battle_playthrough.gd · updated: 2026-09-18

SR-068基线`8d282d95ede45a56d4c64793ae08b827c81779c4`。原请求／注销证据见[原指令](../../static_reverse/original_script_departure.md)，这里记录Godot正常时钟、内建屏1、640×480窗口和实际鼠标／键盘操作。机器回执[receipt.json](receipt.json)将各进程、具名成功路线和图片哈希分开；[默认整场](default-hold.json)独立于下面的作者演练。

## 实際走通

| 路线 | 覆盖行为 |
| --- | --- |
| walk／delete | 实际攻击触发事件、对白与行走／直接删除；事件前后F5/F9、新场景开场F9，已离场节点不重建、已播文字不再出现 |
| giant | 原039身体边缘选中／交锋，整块九格释放后实际走入原中心；读档没有大型幽灵对象或旧占格 |
| second／blocked | 先实际用药获得第二行动，再交锋触发当前角色离场；毒／禁魔／MP0共存时法术不可用、普通攻击合法；离场不补第二次资源／状态尾部 |
| mage／support | 装备源移动施法饰品、实际走位后風刃／治癒之水；新资源付款与支援贡献结算完成后播放离场 |
| ai／paralysis | 友军AI拥有真实風刃，在新交锋事件后离场，不再使用第二行动；同伴实际治疗麻痺角色后触发该角色离场，队列／保存仍一致 |
| kill／victory／defeat／escape | 实际击杀与EXP／成长、清敌、致命反击、撤离格待机；先完成离场演出，再显示结果与重开按钮；终态F5/F9与新场景F9、实际点击重开 |
| carry | 使用已离場队友的持久角色资料进入实际新战斗场景；新场景按自身阵容生成该角色，保留持久成长／装备，清空旧在场和事件游标；新场景再F5/F9 |
| rearm | 同一个事件再次激活，两个同code对象依次成为首个在场实例；两次独立攻击之间保存恢复，按每次真实离场ID走位／隐藏，不能让第一次的旧图像复现 |

演练明确提供有限库存、当前HP／EXP／速度、状态／AI策略和事件901，保留原地图与角色素材，不替换RNG、伤害、付款或结算。初始角色为004／006／002／026及039；不是把这些角色、道具或剧情赠送给正式第一战。跨战目的地是作者指定的开发场景，通过实际Runtime的一次性handoff入口载入；不是新宣称的原作关卡衔接。

## 人工图证

[离场对白](walk-dialogue.png)、[直接淡出](delete-fade.png)、[大型边缘目标](large-edge-target.png)、[大型离场后恢复](large-restored.png)、[当前角色离开后的继任者](owner-restored.png)核对了画面和在场状态。

[AI离场](ai-dialogue.png)、[交锋升级](kill-growth.png)、[清敌结果](victory.png)、[败北结果](defeat.png)、[撤离结果](escape.png)、[实际新战斗承接](carry-destination.png)与[重复事件恢复](rearmed-restored.png)分别检查过。图片逐一关联机器回执的源帧与哈希；逻辑原16tick与0.24秒重制淡出各自标明，不由一帧截图推断时钟等价。

## 回归与失败记录

最初演练使用不支持的`actSet*Status`，事件未激活；改为源支持的`actInsert*Status`。实际走通又发现无开场的开发配置缺少Coordinator而一直等待、AI新交锋漏交攻击后事件、开场F9被旧演出吞掉、已播游标与脚本定义未绑定，以及静态演员绑定不能代表再次触发时的新实例，均已修正。后续终态补验暴露重开按钮被脚本隐藏后未恢复，已与结果可见条件统一；没有专用结果板时按当前受控者显示败北姓名。

重复事件还暴露解释器把serial1固定为开场对象；修正为当前仍注册／在场的同类实例，再按该次回执绑定图像。新增4组原注销→再次查询组合执行，配合两次实际攻击之间的F5/F9验证这一语义。纯规则检查需显式完成第一次交锋展示阶段才能开始第二行动，不放宽`already_attacked`门禁。

十四条初步路线中的两个进程在已经完成具名范围后失败：一组完成五条后发现006测试策略缺项，另一组完成AI后发现麻痺夹具修改的是复制前的旧角色引用。只采用其此前完成的路线，后续失败分别修正，不把这两个进程称为全绿。最终终态和rearm使用独立进程回执；重复的早期终态不作为最终标签／控制验收。

默认第一战`hold`使用正式开场／地图／阵容，零HP／坐标／库存／EXP／RNG覆盖；第8回合、205.229秒撤离，真实按钮重开成功，原日志`ignored/script-departure/default-hold-close.log`退出0。它只固定新开第一战的进程内入口以避免读取其他工作树的战役位置，不删除用户战役存档。

```sh
tools/godot.sh --screen 1 --script res://tests/capture_departure_review.gd
tools/godot.sh --headless --script res://tests/run_departure_tests.gd
tools/godot.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- hold
tools/verify.sh
```

完整门禁结果以本批提交说明的实际日志和退出码为准。旧版本缺少离场策略／脚本身份摘要的存档显式不兼容，不猜测迁移、不删除原文件；后续原VM其它高位分支与等待请求继续独立研究。
