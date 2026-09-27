# 源地图绑定：生成器到实际场景

> evidence: runtime-measured · status: live · tools: capture_map_binding_review.gd, hsltools/checks/source_map_binding.py · updated: 2026-09-19

[机器回执](receipt.json)记录三个完整窗口进程、六张原尺寸审核图及七个真实PAK重建输出。原数据／有界指令见 [P-033证据](../../static_reverse/original_map_binding.md)，不能把此处Godot结果当作原游戏renderer测量。

## 玩家路径

| 路线 | 实际结果 |
| --- | --- |
| 61 营地报告 | 本关无同号地图，从OBS取得`SHAPE41\LEVEL55.SHP`；夜营图、原人物与对白完整播放并交接 |
| 56 晨间营地 | 实际使用`LEVEL56.SHP`，不是相似WRD对应的夜营；对白与离场、交接保持原有产品流程 |
| 60 王座厅 | 取得`LEVEL58.SHP`，护送、对白后正常进入第三战开场，不把上一场图像留在新场景 |

全部通过实际键盘事件推进，`Engine.time_scale=1`，使用进程独立user目录；没有修改角色、剧本、镜头或存档政策。内建屏实测编号0、640×480。每个进程均真实退出0、验证期间差异不变；SHA和命令在JSON中分别保存，不由截图存在推断PASS。

验收器同时核对当前场景的seed完整原成员名、SHP哈希与尺寸、`Runtime.map_backdrop.texture`的实际资源及全部RGBA像素。它在仓库验收中读取原PNG作对照，会产生“Image.load_from_file不适于export”的测试专用警告；正式Runtime仍按导入Texture2D加载，未改变导出行为。

![夜营](061-00-camp-framed.png)
![夜营对白](061-dialogue-847.png)
![晨营](056-00-camp-morning-framed.png)
![晨营对白](056-dialogue-819.png)
![王座厅](060-00-throne-framed.png)
![交接第三战](060-scene-end-handoff.png)

## 生成与回归

55／56／60／61通过新入口从原PAK重建到正式路径，现有PNG与seed内容没有变化；32／33互换与66借用夜营也真实重建成功，但输出只留ignored，未替presentation增加章节场景。测试将两个目录中的同名SHP赋予不同颜色，真实OBS／SHP／WRD解码及PNG生成证明旧逻辑选错、新逻辑选择正确；无登记别名仍能生成，缺精确成员时明确失败。未把只替换PAK IO的合成987关登记到产品。

```sh
python3 -m unittest tools.test_hsl_battle_seed
python3 tools/hsl.py check source_map_binding
tools/godot.sh --headless --import
tools/godot.sh --screen 0 --script res://tests/capture_map_binding_review.gd -- --level=61
tools/godot.sh --screen 0 --script res://tests/capture_map_binding_review.gd -- --level=56
tools/godot.sh --screen 0 --script res://tests/capture_map_binding_review.gd -- --level=60
```

运行窗口前重新确认内建屏编号。原探针、Python测试／全seed检查已加入`tools/verify.sh`；最终完整门禁的实际进程回执在`ignored/map-binding/verify-close.json`，结果以对应本地提交正文为准，不能用本包的三个窗口进程代替全门禁。
