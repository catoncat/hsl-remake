# 四邻路径与邻接阻挡代价

> evidence: static-derived · status: live · functions: 0x40eb80, 0x40f200 · tools: hsltools/probes/movement.py, run_ai_navigation_tests.gd · updated: 2026-09-17

2026-09-17，接续[持有目标与地图候选](original_ai_navigation.md)。本包把原普通单格移动的扩展成本接入同一玩家范围、AI当回合站位和全图追击路径；不是原全部地图模式、对象占地或路径缓存的重建。

## 原指令与可重复证据

[hsltools/probes/movement.py](../../../tools/hsltools/probes/movement.py)读取SHA锁定的原EXE；[原结果](original_movement.json)含58组完整`0x40f200`扩展和80组完整`0x40eb80`邻格代价返回。原函数及callee未经替换，未知callee拒绝执行；每次检查返回地址、栈恢复和指令上限。输入为明确的9×9合成地图，覆盖开放地、单障碍、墙、整列阻断、多障碍和地图边角，移动预算1／2／4／6。

扩展从中心以`budget+1`标记开始，依次进入上、下、左、右四个邻格；递归继续检查合法范围、阻挡和剩余量。八方向的目标距离判定见导航包；普通四邻扩展不意味着普通角色可以对角行走，也不等于大体型八格占地已经接入。

`0x40eb80`按进入方向检查前方和两侧，排除刚来的格子。没有相关阻挡返回1，有则返回2；一格处有多个障碍也只返回2。普通模式使用`0x74000`，测试分别覆盖`0x4000/0x10000/0x20000/0x40000`。相反，WRD的`0xff000000`高字节会阻止进入该格，却不匹配这个邻接代价mask。两种地图在同样障碍布局下的可达边界确实不同，不能统称“每个墙边都多扣一点”。

一个关键顺序是：**先登记当前格的到达余量，再为继续扩展扣邻接代价。** 因此第一步成本1；之后从当前格前进时，若它邻接相关阻挡，该步成本2。最终落脚格不再支付它自己的继续扩展费用。普通可通行路径的前驱不可能是阻挡，故当前支持域内可以用四个邻格中是否存在相关障碍实现同一结果。58组全部输出格值均与独立最短路径模型一致，不只比较某个终点。

## 产品接入与事务

`TacticalGridRules`统一准备当前占用、显式地块`movement_flags`与成本。活着的其他角色仍按当前保守占用策略阻挡，主角自身不当作障碍；死者立即释放占用和邻接成本。`WrdTerrainTiles`保留0xff地形不可进语义，显式低位flags为0，不为地形墙捏造动态对象flags。额外的自定义`move_cost`继续是明确的场景／测试能力，不能称为原所有地形的公式。

共享扩展完成全部更便宜的路径更新后才构造最终`path`与`path_costs`，避免父路径后来改善而子路径仍保留旧路线。`AINavigationRules`全图搜索保留这些累计到达成本；当回合前缀按实际`move_point`截取，不再另用步数或另一份成本公式。玩家移动范围、AI攻击／法术／支援站位和追击共用这个入口。临时占用或地形改变后重新调用正常AI入口，先核对当前路径、资源和目标；过期施法站位不能移动或扣费。

旧`move_range`镜像及相关读取已移除；剧情离场和开发验收的远距离规划改为显式搜索预算，实际可提交玩家路径仍用本人的移动力。剧情不占用回合时继续采用原有忽略角色占用、遵守地形的演出合同。逐格动画仍每条边0.20秒，移动点代价没有被错误换算成额外动画停顿。

全部状态只由PlayLoop提交；路径对象是只读提案，不能让表现层反推坐标。路径线及落点消费实际已提交的路线，移动完成后才展示攻击／施法／援助，数字和后继继续走原有一次交接。

## 当前边界

完整原对象通行资格、盟友穿越、各模式mask、所有高度差、大型占地、原缓存250项的执行节流与完整平分路径顺序仍未等价。全图最短路径是对已证成本的重制组合；所选路线本身标为provisional，独立成本来源标static-derived。替换这些边界需要对应原模式完整输入和路径恢复／对象资格探针，不以当前可达集合或实玩通过一并宣称恢复。

## 验证

Godot导航套件逐格对照58份原扩展结果，并核对每条路径累计成本、活人邻接／死亡释放、全图前缀与当回合范围一致、目标不可达后的替换和旧站位原子拒绝。Python检查器覆盖保存结果、边界篡改拒绝及地形墙／对象阻挡差异。实际控件路径和完整第一战记录在[导航实玩](../runtime_observations/ai_navigation/README.md)。

```sh
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate movement --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
python3 tools/hsl.py check movement
python3 -m unittest tools.test_hsl_native_movement_probe
tools/godot.sh --headless --script res://tests/run_ai_navigation_tests.gd
```

普通检查不再次执行原EXE；只有`--execute`做本机原指令运行。原函数次数、Godot断言数、实际输入路线是不同的证据层次。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/WrdTerrainTiles.gd` rules：0x40eb40 reads the WRD word, 0x74000 flags refuse entry
