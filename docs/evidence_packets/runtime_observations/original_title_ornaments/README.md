# 原版标题画面的宝珠与书：上下浮动，不跟随选项

> evidence: runtime-measured: 原版 v1.06 标题画面的宝珠与书只在竖直方向做正弦式浮动，周期约 1.65 s、上下各约 5 px，位置与鼠标停在哪一项无关; provisional: 采样只有 4–5 帧／秒，周期与振幅是拟合值 · status: live · tools: hsl_original_control.py, play_original.sh · updated: 2026-09-27

## 结论

- 原版：宝珠（左）与书（右）水平不动，竖直做周期 1.646 s、振幅约 5 px 的正弦式浮动；停在第 1／2／3 项平均位置差 ≤0.3 px，不跟随选项；两件相位差在三组采样间不一致（runtime-measured）。
- 重制：`game/title/TitleScreen.gd` 按拟合周期与振幅浮动，两件起始相位在进入标题时随机取，不做同步或反相（provisional）。
- 差异：采样 4–5 帧／秒，周期、振幅与正弦形都是拟合值；逐帧计数器未读（provisional）。

## 证据

**runtime-measured（2026-09-24 原版 v1.06，Wine＋cnc-ddraw 640×480）**

- 采样：鼠标停在第 1／2／3 项（`hsl_original_control.py move`／`click`），等 5 s 后 `screencapture -l <窗口 id>` 只截游戏窗口，每项连拍 45 张、间隔 0.15–0.26 s（每项 7.6–9.8 s）；Retina 2× 截图去标题栏后按 2×2 平均缩回 640×480。
- 定位：第 1 项第 1 张的宝珠块 (218,256,30,30) 与书块 (388,240,34,40) 作模板，每张 ±6 px 水平、±18 px 竖直搜索最小平均差；宝珠另用绿色像素质心核对（135 张里 134 张 481 像素、1 张 456 像素），两法一致。
- 入库：逐张位移表 [ornament_track.tsv](ornament_track.tsv) 与 4 格裁切图。

停在第 1 项：浮到最高、沉到最低；停在第 2 项；停在第 3 项（原版帧见私有档案：`runtime_observations/original_title_ornaments/title-ornaments-4-states.png`）

| 量 | 宝珠 | 书 |
| --- | --- | --- |
| 水平位移 | 135 张全为 0 | 135 张全为 0 |
| 竖直范围（相对模板帧） | 0 … +10 px | −2 … +8 px |
| 拟合周期（三组合并） | 1.646 s | 1.646 s |
| 拟合振幅 | 5.1–5.2 px | 5.1–5.2 px |
| 拟合残差（RMS） | 0.4–0.7 px | 0.4–0.7 px |
| 均值：停第 1／2／3 项 | +4.96／+5.00／+5.02 | +2.84／+3.10／+2.93 |
| 640×480 画面上的位置 | 质心 x＝233，y 在 270 与 280 之间往返（球体约 26×26 px） | 书约占 (375,245)–(424,286)（模板帧），整体在其上 2 px 到下 8 px 之间往返 |

- 三组采样间隔各不相同却拟合出同一周期，1.65 s 不是采样混叠。
- 选中项只是文字变金色并出现火花（第 1 项火花见第 1、2 格）。
- 三个文字行（黑色描边竖直范围）：第 1 项 y 243–261、第 2 项 286–303、第 3 项 331–348。宝珠中心总在第 1 项文字中心（y≈252）下方 18–28 px；原版参考帧 01/frame_001 的"约 19 px"对应浮到最高点附近。
- 两件相位差三组分别为 48°、194°、193°（三组相隔几分钟）：两周期可能只差很少，也可能各自计时，采样分辨不出。

## 重制接线

`game/title/TitleScreen.gd` 的宝珠／书浮动；provenance 头写 `runtime-measured docs/evidence_packets/runtime_observations/original_title_ornaments/README.md`。周期与振幅是 provisional，替换点是原版浮动计数器的读数。标题其余读法见 [menus_ui](../menus_ui/README.md)。

## 复现

不可再生：原版侧唯一记录。

## 边界

- 采样率只有 4–5 帧／秒，不是逐帧；逐帧时序要用 `hsl_win32_memread.exe --repeat` 找浮动计数器（ScreenCaptureKit 录原版窗口只得到最初约 0.9 s，见 [tools/README](../../../../tools/README.md)）。
- 书的范围由目测裁切图得到（颜色和旁边的雕像接近，无法用阈值分割），误差约 ±2 px。
- 没有看鼠标不在任何选项上的情况，也没有看从一项换到另一项时是否有过渡动画。
