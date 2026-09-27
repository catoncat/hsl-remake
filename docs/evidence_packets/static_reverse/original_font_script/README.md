# 原版如何显示简体：Big5 文本＋简体字形的位图字库

> evidence: static-derived: 码位→字形表与绘制循环; resource-derived: 字库字形与逐字审读; runtime-measured: 用户 2026-09-24 实机录像全简体; negative-evidence: EXE 无 Big5→GB 转换; provisional: 鍾針魘三字未判读 · status: live · functions: 0x42f230, 0x45f798, 0x4608e4, 0x460ace · tools: hsltools/assets/workteam_simplified.py, hsltools/checks/simplified_display.py, hsltools/data/simplified_chars.py, hsltools/sources/original_font.py · updated: 2026-09-24

结论：原版的文本资源是 Big5（繁体）存的，hsl01.exe 显示时**不做**任何 Big5→GB 转换；玩家看到的简体来自字库 `DATA\FONT.24`／`DATA\FONT.15` 本身——它们按 Big5 码位排字形，但绝大多数繁体码位上画的是简体字形。重制显示繁体，是因为重制从未导入这套位图字库，而是把 cp950 解码出的 Unicode 繁体字直接交给系统字体（PingFang SC）去画。

用户 2026-09-24 实机录像（runtime-measured，帧在仓库外 `~/Documents/hsl-fork/ignored/user-video-20260924-1203/f10/`）里原版标题菜单、对白、状态页、关卡标题卡都是简体，与下述字库事实一致。

## 证据

| 事实 | 来源 | 等级 |
| --- | --- | --- |
| 文本是 Big5 繁体：`RESOURCE.TXT`、`ITEM.TXT`、`PLAYERS.TXT` 等全部按 cp950 无错解码，内容是繁体（長劍、緹娜……） | `content/imported/hsl/global/tables/`、`content/imported/hsl/chapter01/source_texts/RESOURCE.TXT` | resource-derived |
| EXE 只装载位图字库：`0x42f230`–`0x42f31b` 装载 `DATA\FONT.15`＋`ASCFONT.15`（全角 16×15）与 `DATA\FONT.24`＋`ASCFONT.24`（全角 24×24） | hsl01.exe；另见 [成长窗](../original_growth_window.md) | static-derived |
| 码位→字形表在装载时按四段常数生成（`0x460ace` 装载函数，无外部映射参数时走 `0x460c32`–`0x460d1b`）：Big5 序号 `0x13A0–0x1537`（A140–A3BF 符号）→字形 13094 起；`0x1577–0x2A8F`（A440–C67E 常用字）→字形 0 起；`0x2A90–0x2BFC`（C6A1–C8FE）→字形 13502 起；`0x2C28–0x4A34`（C940–F9D5 次常用字）→字形 5401 起；共 13867 个字形 | hsl01.exe | static-derived |
| 序号公式 `0x45f798`：`(lead−0x81)×157 + (trail≤0x7E ? trail−0x40 : trail−0x62)`；绘制循环 `0x4608e4`：字节 ≥0xA1 取两字节查表、画 `table[序号]` 号字形，0 号跳过 | hsl01.exe | static-derived |
| 在 EXE 与 hsl.pak 中都没有 GB 编码表或转换代码的调用者（`imul 0x9d` 全 EXE 只此一处，唯一调用者是上面的绘制循环） | hsl01.exe objdump | negative-evidence |
| 字库文件 `FONT.24` 998424 字节＝13867×72、`FONT.15` 416010 字节＝13867×30，无文件头；按上表取字形，`體`→体、`說`→说、`長`→长、`戰`→战；`後`、`於` 保持繁体形 | hsl.pak `@:\data\Font.24`／`Font.15`；`PYTHONPATH=tools python3 -m hsltools.sources.original_font show 體說長戰後於` | resource-derived |

复现（需原版安装，只打印文字字形，不产图）：

```text
PYTHONPATH=tools python3 -m hsltools.sources.original_font show 體說後職 [FONT.15]
```

## 逐字审读（glyph_review.json）

[`glyph_review.json`](glyph_review.json) 记录重制文本源里出现的每个"仅繁体字"（OpenCC `TSCharacters` 的键，共 672 个；含只出现在制作名单转写 `workteam_simplified.LINES` 里的 8 个姓名用字 鄧彥陳楊滄吳鄭劉，2026-09-24 R6-L9c 按文字行审读并经 agy 交叉判读，均为简体形；2026-09-26 OPTIONS-B1 重製選項说明文字新用到的 暫節緩頁飄駐 按字形位图目读，均为简体形 暂节缓页飘驻）在原版 FONT.24 上画成什么（resource-derived，目读字形位图；OpenCC 只提供候选形）：

- 656 个画成 OpenCC 的第一候选简体形；3 个画成别的简体形：`餘`→馀（与 WINDOW41 烘焙的"残馀点数"一致）、`鍊`→链、`囉`→罗。
- 7 个**原版字库保留繁体形**：後 於 夥 乾 徵 殭 麼（Over002 烘焙的结局文字里同样是"後"）。
- `職` 码位上画的是"翻"、`翻` 码位上画的是"职"（原版字库 bug：原版把"職業"显示成"翻业"、"翻騰"显示成"职腾"）；重制不照搬，显示 职／翻。
- `噁` 画成 口＋恶（U+2BAC7，扩展 E 区，系统字体没有）；重制显示 恶。
- 未能判读 3 个（24 px 下 钅／金 或 厂／广 分不清）：鍾 針 魘，重制暂用 OpenCC 候选（钟 针 魇），属 provisional。
- `絶` 不在 Big5（只出现在英文注释"絶技"里），原版无此字形。

## 重制的单一转换点

与原版"文本不动、字形在显示层换"同构：文字源（生成数据、GDScript 字面量、`label.text`、存档）保持繁体原文，显示时经唯一接缝换成原版画出的字形。

- 文字：autoload `game/text/SimplifiedDisplay.gd` 安装 `game/text/SimplifiedDisplayTranslation.gd`（Godot `Translation`），每个 Control 显示文字时按 `content/generated/hsl/text/simplified_chars.json` 一字换一字（`hsl generate simplified_chars`，输入本包 `glyph_review.json`＋OpenCC 候选表）。一字对一字保证下标不变；`BattleUISkin.line_starts` 按显示形测量换行。
- 图片：`SimplifiedDisplay.texture_path` 按 `content/generated/hsl/text/simplified_images.json` 把烘焙繁体字的图换成简体重画。唯一一张是通关制作名单 `workteam.SHP`：`hsl generate workteam_simplified` 按 Big5 转写逐格处理（121 格）——只有仅繁体且 `glyph_review.json` 读为简体形的字（45 格，如 鄧→邓、漢→汉、劇→剧）清格后按原图行框／列距／墨色印原版 FONT.24 在同码位的字形，水平按原图该格字样居中（FONT.24 墨迹占格内第 1–23 列、原图字样占第 0–21 列，不居中会让重画字贴住右邻、左边空出一道缝）；字形换成游戏字库的，属 remake-invented；其余 76 格（繁简相同的字、半角 2D／3D、字库自己画繁体的字）保留原图字样逐像素不动。原因：FONT.24 只换字体不换字，而且有的字形不能用——`伋` 的亻画成类似 1 的粗笔（`信` 同），R6-L9b 全格换字时名单里 4 处 林汝伋 读作乱码；`昶` 按原图保留（负责人所见"昶空白"是早于 L9b 最终产物生成的对照图，产物里该格一直是原图字样）。未审读、属 `remake_choices` 或字形为空的仅繁体字让构建直接失败，不悄悄保留繁体。转写里两个存疑字按原图文字行判读（resource-derived）：吳致**松**（木旁竖笔贯通到格顶、无山头，不是 崧）、王浩**辰**（厂框、无宀，不是 宸）；与 FONT.24 候选字形的逐像素相似度两者相近（松 0.838／崧 0.855，辰 0.785／宸 0.802，字体不同，不作判据）。`image_inventory.json` 的 `redrawn_with_font24`／`shape_lettering_kept_for` 记两组字。标题 logo `Title002`（幻世錄）按品牌图保留，列为待用户决定。
- 检查：`hsl check content:simplified_display`——玩家可见字串（与 `content:player_copy_traditional` 同一范围）经表后不得剩下仅繁体字（原版字库自己保留的 後於夥乾徵殭麼 除外），表里没有的新繁体字直接失败；图片清单每张 sha256 不变，繁体图须有已登记的简体重画或保留理由；制作名单另逐格核对（`workteam_simplified.check_cells`，无需原版）：保留格及重画格以外的像素与原图一致，重画格有墨、只用原图墨色、且不同于原图。消融见 `tools/test_hsl_simplified_display.py`。
- 方向参数：同一接缝可产出全繁——卸下 Translation（或换一张恒等表）即为繁体显示；那时需要重画的是全部简体烘焙图（WINDOW10／21／30／41、标题与系统卷轴 Title021–063、Over001／002、49 张关卡标题卡），见 R6-L9 报告。本包只实现用户选定的全简体。

字串盘点（不分方向，可复跑）：`PYTHONPATH=tools python3 -m hsltools.checks.simplified_display inventory`——2026-09-24 基线扫描 902 个文件的 67 583 条玩家可见字串，762 个文件含仅繁体字，共 598 个不同的仅繁体字，仅简体字 0 个。

## 不支持的结论

- 不声明原版字形的笔画外观：重制仍用系统字体（原版位图字库未导入为重制字体，见 `docs/PROJECT.md` 第 5 行）。
- 不声明原版对扩展区以外所有 13867 个码位的画法；只审读了重制文本源用到的 672 个仅繁体字。
- 烘焙在素材图里的文字不经过字库，另见 [`image_inventory.json`](image_inventory.json)。
