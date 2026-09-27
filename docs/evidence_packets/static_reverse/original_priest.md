# 玩家槽1的002祭司：绑定、成长与资源行动链

> evidence: static-derived; resource-derived · status: live · functions: 0x409e40, 0x42c700, 0x42caa0, 0x42cac0, 0x448840, 0x44cb10 · tools: hsltools/data/priest.py, hsltools/probes/mana_item.py, hsltools/probes/priest.py, hsltools/probes/priest_motion.py, run_support_magic_tests.gd · updated: 2026-09-27

证据等级为`static-derived`（有界原指令）与`resource-derived`（源表／程序）。本批先核对第三战受控角色，发现“029／jobWise就是战斗緹娜”的旧路由假设错误，未把演出头像或模型候选当作战斗模板证据。

## 绑定更正

`STORY053.TXT`先删除`SID_ENEMY029`，再插入`obj_Story_Player2`，随后使用`SID_PLAYER1`和`SHAPE002_CLIMB`。原002表明确`name_1`、jobPriest、錫杖82和治癒之水；029是jobWise演出模板，没有武器／初始法术，ANIMAL只有P068一张静态姿态及等待。002则有完整六帧普通攻击和上下运动命令。

[绑定与刷新回执](original_priest.json)实际执行五组槽配置，合计20个helper正常返回和五段安装分支：`0x42c700`设置槽，`0x42caa0`读取启用对象code，`0x42cac0`反查0起始槽；`0x407eff..0x407f14`已进入玩家对象分支后把记录索引设为`slot+1`，止于后续初始化前；`0x44cb10(index,1)`完整复制同索引0x1fc源模板到live，逐字节哈希相同。特意把安装前索引设为29，玩家槽1仍得到2。这证明角色路由，不能扩张为整次原actInsertActor／首次队伍全局初始化。

## 祭司85的完整刷新

`0x448840`分发表第5项进入`0x44946f`。源002力量／反应／精神／体质为16／11／15／15，四项cap均88。22组输入各执行两次完整原刷新，第二次先写入错误派生值；44次正常返回覆盖等级折点、四属性成长、cap、source mode、空装备、合法法杖及移动／范围／回复／减耗／连续行动装备。

每步保持原整数除法；s/d/m/c为四属性，Lh仅在source mode含0x10000时等于等级：

```text
HP = s/6 + Lh + 160*c/100
MP = 110*m/100 + c/4
攻击 = 28*d/100 + 98*(s/2)/100 + 6
防御 = c/3 + m/7 + 22*s/100 + d/4
魔击 = 30*m/100 + 2*level；超44部分折半，然后+45
速度 = 94*d/100
五抗 = 百分比*m/100 + c/除数，各自最多50
地/水/风/火/心的百分比、除数为(40,3)/(46,2)/(24,3)/(38,4)/(32,3)
```

之后走已验证公共刷新：源加值、等级攻击补正、当前装备、当前HP/MP夹取、抗性总上限80、移动0..12。换装／升级不回满资源，source mode不换成临时控制权，当前队列不追溯重排。Python独立模型与Godot分别对拍原返回。002手动五点分配沿用当前玩家成长合同，不冒充原自动入队加点或动态学技。

## 完整普通程序与回魔物品

`SID_PLAYER1`普通action包含向上`aniSetSubSpeed(192,16<<16,1<<16,0)`、向下`aniSetAddSpeed(64,0,1<<16,16<<16)`和停止。[39次有界更新](original_priest_motion.json)逐次执行原dispatcher到绘制尾部前，再独立执行`0x40351e..0x4035eb`运动尾段及真实速度helper，无renderer替身。先按当前速度移动，再改变／夹速度；累计上升136后回到基线。

编译器只开放这两个垂直方向、整数定点速度和停止；不声称任意三角／小数运动已支持。原绘制在运动尾部之前，Cutin因此读取前一更新的位置；命中、逐击状态、遗言、最终EXP仍消费现有收据。六帧最后一帧作为受击姿态来自已检查原图的重制绑定，完整原受击handler和精确时钟仍未知。002原站立／挥击图面向左，不由k_action推断朝向。

实拍发现沿旧普通镜头1:1摆放时，起跳的头部／法杖会越过画面上沿。本批按整段源pose和运动边界计算一个固定的较宽构图比例，使起跳全过程完整可见；不逐帧缩放或改变源运动样本，也不移动HUD。这是明确的重制镜头选择，不把该比例冒充原renderer数值。

源002初始携带241和244。[42个物品入口前段](original_mana_item.json)从`0x409e40`实际读取244的`add_mp=30`，止于MP写入后、气力／解除／显示前的`0x40a275`。恢复封顶到缺失MP，不抽随机数，HP与毒／禁魔／麻痺不变，包含满条、零上限和飞行输入。

原版满MP目标也能用回魔药：`0x409e40` 把回复量夹到0，state108 浮出0，`0x444aba` 消耗一件；目标是相邻一格与自己（见[物品命令包](original_item_actions.md)）。麻痺者不能自行用药，回魔不解除禁魔。本批没有声明原AI自动回魔策略，AI继续按真实剩余MP选择合法治疗／物理／物品／等待。

## 接入、系统对照和边界

`hsltools/data/priest.py`提供002模板与独立`PriestTrial.tscn`，共用唯一PlayLoop、地图、装备、攻法援物、AI、经验与恢复。player_unit_id进入存档配置；开发目标适配器共用结算出口，败北姓名、死亡声、初始镜头按实际主角读取。零移动不会再回退为雷欧纳德的5格。

| 对照缺口 | 本批实际接入 | 仍未证明 |
| --- | --- | --- |
| 后续受控角色与援护循环 | 正确002绑定、独立祭司派生、原治疗／法杖／回魔、贡献EXP／成长、当前装备与第二行动 | 入队自动调级／加点、学习／转职 |
| 普通攻击节奏 | 原起跳、减速、落地和停止程序，六帧与逐击快照 | 全ANIMAL、原全局更新／渲染时钟 |
| 主角与恢复 | 非Leonard控制／镜头／零预算、取消与移动资格、AI回退、存档与三终态 | 正式WINFAIL053及第三战编队由presentation单独接入 |
| 其余能力 | 复用末击附毒、未来槽取消、麻痺、双击／两次行动 | MP打击正向、弱化／随机多状态、复活仍未开放 |

029仍用于离场演出，jobWise87不因旧候选被错误启用；月花圓舞未实现，按既有命令合同隐藏，不借用氣刃斬。第一／第二战授予不变；开发场景的附加库存、受伤同伴及站位明确标注。PLAYERS原包字节差异和固定NPC策略继续保持。

三个探针默认离线检查，只有显式execute才重新运行固定EXE，写回另需write。原文件只读，未调用候选模型。[十一条实玩及截图](#复现)按具名路线、后续构图补拍和未知旧进程退出码分别记录；最终完整门禁退出码写本批提交说明。当前Godot测试不升级为全职业、正式第三战或原全局初始化等价。

## 复现

`python3 tools/hsl.py check priest`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [priest](../runtime_observations/priest/receipt.json) | manual、healing_growth、mana_extra、phase_mobility、melee_series、ai_heal、ai_silence、ai_paralysis、victory、defeat、escape | `capture_priest_review.gd`、`run_support_magic_tests.gd` |
