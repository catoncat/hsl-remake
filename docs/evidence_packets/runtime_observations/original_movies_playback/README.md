# 原作开场／结尾动画在重制中的播放（runtime-measured）

> evidence: runtime-measured · status: live · functions: 0x42da60 · tools: capture_title_review.gd, hsltools/assets/movie_import.py · updated: 2026-09-19

帧来自 `tests/capture_title_review.gd`（窗口化，隔离 HOME，`TITLE_REVIEW_PASS shots=10`），截取 640×480 画面后按最近邻缩回 320×240 存档（播放时为 2× 像素放大，缩回无损）。影片资产与格式结论见 [original_movies](../../resource_inventory/original_movies.md)（`tools/hsltools/assets/movie_import.py`）；播放器合同见 [PRESENTATION](../../../architecture/PRESENTATION.md) 的 Title screen 一节。

| 帧 | 场景 | 说明 |
| --- | --- | --- |
| ![](01-intro-film-frame29.png) | 標題 開始新故事 → 淡出 → 开场动画约 1 s | `transition.status = movie`；start.ani 第 29 帧（`start_sheet_00.webp`） |
| ![](02-intro-film-frame301.png) | 开场动画时钟跳到 20 s | 第 301 帧，来自第二张精灵表 `start_sheet_01.webp`（表边界在第 204 帧）——跨表切区与线程预取正确 |
| ![](03-ending-film-frame227.png) | `MoviePlayer.play("end")` 时钟 15 s | end.ani 第 227 帧（`end_sheet_01.webp`），`audio_playing` 为真 |

## 与解码原帧的比对（runtime-measured）

对每张截图在解码 PNG 帧序列（`ignored/movie/<name>/frame_NNNN.png`，不跟踪）中搜最小平均绝对差（MAD，0–255）：

| 截图 | 最佳匹配帧 | MAD | 对照：错帧 MAD |
| --- | ---: | ---: | ---: |
| 开场 1 s | 29 | 2.44 | — |
| 开场 20 s | 301 | 3.40 | 第 100 帧 17.4 |
| 结尾 15 s | 227 | 3.66 | 第 50 帧 125.7 |

MAD 2–4 是 WebP q85 有损编码的残差量级；错帧的差距大一个量级以上，说明表内行列与跨表帧号映射正确。开场 1 s 处显示第 29 帧而非约第 17 帧，是首张精灵表同步解码（≈0.4 s）落在时钟之前的结果（截图时 `play()` 尚未有"吞掉首帧 delta"的处理；之后 `MoviePlayer` 已改为先显示第 0 帧、再起播音轨与时钟并跳过首帧 delta，音画同起）。

## 边界

- 播放位置（标题淡出之后、level 51 之前）来自原进入 level 51 例程 `0x42da60` 的 static-derived 触发点；结尾片由 `actPlayMovie 140`→`end` 的 provisional 映射播放，两者的原跳过行为、缩放滤镜与音画相位未定位，均为重制读法。
- 本包只证明重制播放器把导入资产按 manifest 正确播出，不证明与原播放器逐帧等价。
