# 原对象指定地图：P-033／P-047

> evidence: static-derived · status: live · functions: 0x430370, 0x45dc5c, 0x45fc01, 0x46dd50 · tools: hsltools/checks/source_map_binding.py, hsltools/probes/map_binding.py · updated: 2026-09-28

## 结论与范围

本包区分**源对象绑定**、**有界原指令**和**Godot接入**。源路径来自本关 `OBJ-NNN.OBS` 中 `obj_Process_Code = defProcIconBG` 的 `obj_Shape_Name`，不是由关卡号拼文件名，也不由相同 WRD 或对白推断。原 `PROCESS.DEF` 的 index1 经 `0x477c30` 指向 `0x430370`。源记录、EXE身份、指令字节和逐例输出见 [JSON](original_map_binding.json)。

157个命名OBJ文件中，154个有唯一该类对象。其中153个具有 `obj_Data9 = 1`，可作为本关地图形状；level49是 `SHAPE\ICONRECT.SHP`、未声明Data9的世界地图控制器，不能把它当作普通关卡底图。OBJ000／998／999没有该记录。本包不改变或证明 `game/world` 的绘制路径。

| 关卡 | 明确的源路径 | 排除的猜测 |
| --- | --- | --- |
| 32／33 | `SHAPE31\LEVEL33.SHP`／`SHAPE31\LEVEL32.SHP` | 两者都有同号形状，但实际互换，不能“有同号文件就选它” |
| 55／56 | `SHAPE41\LEVEL55.SHP`／`SHAPE41\LEVEL56.SHP` | 同为营地地形，不等于同一晨昏图 |
| 60／63／71 | `SHAPE41\LEVEL58.SHP` | 无同号文件不是沿用上一个场景 |
| 61／62／64／66–70 | `SHAPE41\LEVEL55.SHP` | 不需要逐关补手写别名或用对白猜夜营 |
| 73 | `SHAPE41\LEVEL41.SHP` | 缺73形状不构成地图来源未知 |
| 900／901 | `SHAPE01\LEVEL09.SHP`／`SHAPE01\LEVEL08.SHP` | 事件号与地图号分开 |

这些是resource-derived路径；153条绑定不等于153场已完成游戏。

## 证据：原指令执行

`tools/hsltools/probes/map_binding.py`只在显式`--execute`时运行原EXE，默认离线检查保存结果；没有调用模型重新解释。

27条装载前段覆盖32／33、55／56／58、60／61／66／901及原大小写、ASCII小写、形状注册表缺名。从 `load_obs_template 0x45dc5c` 内的 `0x45e145` 开始，真实调用 `0x46dd50` 读取字段与 `0x45fc01` 查找有序形状名；成功路径停止于 `0x45e193`，已经把索引双字写入对象`+0x30`，尚未进入资产IO。缺名路径停止`0x45e172`，未进入外层符号回退。输入源节点／字符串区和预载形状表是明确合成内存；原字符串是实际OBS字段，两个查找callee均执行原指令。注册标志`0x4bb92c=1`明确关闭查找helper内部符号回退，不据此推断完整缺名策略。

背景回调 `0x430370` 另外18例：15次完整返回、3次Data9=0普通更新在`0x4303eb`绘制调用之前停止。初始化写零坐标与模式位，Data9=1保留源形状；Data9=0将形状低字设为FFFF。普通Data9=1更新只复制已记录全局字段，忽略消息不变。完整对象前后字节、调用边界和原RNG全局不变均被检查。释放消息与绘制callee没有执行，不能声称完整原背景renderer等价。

较早raw回执未记录关闭符号回退的夹具标志，正式checker拒绝了它；本片重新执行上述45条有界路径并写入完整配置。没有靠给旧测量结果补字段冒称新执行。原sources指纹与指令锚点不变，旧raw保留在ignored。

## 重制接线：实际接入

`hsl_battle_seed.build`先读本关OBS，经 `hsl_source_map_binding.source_map_member` 取得**完整目录和文件名**，再读取那个PAK成员。拒绝缺失／重复manager、非Data9=1分支、不合法路径或缺少精确资源；不会退回同名文件、别的目录或上一关。此失败策略是明确的重制输入合同，非原缺名fallback结论。

已有 `MAP_ALIASES` 只保留旧seed的兼容注记，不再选择资源。注记与真实资源不一致时也不能写入错误地图号；新的关卡无需增加条目。离线 `hsl_battle_seed.check` 和 `python3 tools/hsl.py check source_map_binding`同时检查原OBS哈希、完整PAK路径、原SHP哈希及像素尺寸，不能用“尺寸相同”掩盖错图。

独立测试只替换PAK IO，真实执行OBS解析、seed组装、SHP／WRD解码和PNG写入：红色同名诱饵与绿色声明资源证明目录不能丢；没有登记的合成关987证明不依赖别名；缺声明文件时必须报错。该合成关不注册为游戏。真实原PAK还重建55／56／60／61（现有产品数据未变），以及隔离输出32／33／66；后者不替另一线创建或覆盖章节场景。实际原场景输入／像素核对与handoff见 [渲染回执](#复现)。

## 复现

`python3 tools/hsl.py check map_binding`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [map_binding](../runtime_observations/map_binding/receipt.json) | 61 营地报告、56 晨间营地、60 王座厅 | `hsltools/checks/source_map_binding.py`；截图驱动已退役，回执为历史记录 |

## 未确认边界

negative-evidence只针对已检查对象：000／998／999无该类记录，49走另一个控制器分支，生成器明确拒绝；不由这些个例推断全引擎不存在其他地图机制。缺字段／缺名后的完整符号回退、原PAK装载整体返回、背景释放／绘制和精确墙钟未执行，仍独立。若要扩展Data9=0或fallback，须补相应真实caller／callee边界，不能放宽当前检查。
