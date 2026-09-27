# 原版如何显示简体：Big5 文本＋简体字形的位图字库

> evidence: static-derived: 码位→字形表与绘制循环、各界面字库（0x460884 全部 70 个调用点的字库指针）; resource-derived: 字库字形与逐字审读; runtime-measured: 2026-09-24 原版录像全简体; negative-evidence: EXE 无 Big5→GB 转换; provisional: 鍾針魘三字未判读 · status: live · functions: 0x411d70, 0x412060, 0x4123b0, 0x412ad0, 0x413040, 0x42f230, 0x45f798, 0x460884, 0x4608e4, 0x460ace · tools: hsltools/assets/workteam_simplified.py, hsltools/checks/simplified_display.py, hsltools/data/simplified_chars.py, hsltools/sources/original_font.py · updated: 2026-09-28

## 结论

- 原版：文本资源按 Big5 繁体存，hsl01.exe 显示时不做 Big5→GB 转换；简体来自位图字库 `DATA\FONT.24`／`DATA\FONT.15`——按 Big5 码位排字形，绝大多数繁体码位上画的是简体字形；2026-09-24 原版录像里标题菜单、对白、状态页、关卡标题卡都是简体（static-derived；resource-derived；runtime-measured）。
- 重制：文字源保持繁体，显示时经唯一接缝 `game/text/SimplifiedDisplayTranslation.gd` 按 `content/generated/hsl/text/simplified_chars.json` 一字换一字，烘焙繁体字的图经 `simplified_images.json` 换成重画图（resource-derived）。
- 原版每个界面只用两张字库之一，由各 `0x460884` 调用点传入的字库指针决定：`[0x4c1ae0]` FONT.24 画对白、胜负条件面板、施法名字幕、升级窗与资料页正文、得物窗／商店／仓库行、系统设定面板、大地图状态栏、城镇台词；`[0x4c1adc]` FONT.15 画行动环图标说明、描述框、资料页按钮标签、条旁 cur/max、大地图地点名；每字先在 (+1,+1) 画阴影色再画正文（static-derived，下表）。重制各窗按同表选 `FONT_BODY`／`FONT_SMALL`，字格顶即原版传入的 y（static-derived）。
- 差异：原版字库 `職`／`翻` 码位互换的 bug 不照搬；`噁` 的扩展 E 区字形显示为 恶；鍾 針 魘 三字字形未判读，暂用 OpenCC 候选（provisional）。

## 证据

| 事实 | 来源 | 等级 |
| --- | --- | --- |
| 文本是 Big5 繁体：`RESOURCE.TXT`、`ITEM.TXT`、`PLAYERS.TXT` 等全部按 cp950 无错解码，内容是繁体（長劍、緹娜……） | `content/imported/hsl/global/tables/`、`content/imported/hsl/chapter01/source_texts/RESOURCE.TXT` | resource-derived |
| EXE 只装载位图字库：`0x42f230`–`0x42f31b` 装载 `DATA\FONT.15`＋`ASCFONT.15`（全角 16×15）与 `DATA\FONT.24`＋`ASCFONT.24`（全角 24×24） | hsl01.exe；另见 [成长窗](../original_growth_window.md) | static-derived |
| 码位→字形表在装载时按四段常数生成（`0x460ace` 装载函数，无外部映射参数时走 `0x460c32`–`0x460d1b`）：Big5 序号 `0x13A0–0x1537`（A140–A3BF 符号）→字形 13094 起；`0x1577–0x2A8F`（A440–C67E 常用字）→字形 0 起；`0x2A90–0x2BFC`（C6A1–C8FE）→字形 13502 起；`0x2C28–0x4A34`（C940–F9D5 次常用字）→字形 5401 起；共 13867 个字形 | hsl01.exe | static-derived |
| 序号公式 `0x45f798`：`(lead−0x81)×157 + (trail≤0x7E ? trail−0x40 : trail−0x62)`；绘制循环 `0x4608e4`：字节 ≥0xA1 取两字节查表、画 `table[序号]` 号字形，0 号跳过 | hsl01.exe | static-derived |
| 在 EXE 与 hsl.pak 中都没有 GB 编码表或转换代码的调用者（`imul 0x9d` 全 EXE 只此一处，唯一调用者是上面的绘制循环） | hsl01.exe objdump | negative-evidence |
| 字库文件 `FONT.24` 998424 字节＝13867×72、`FONT.15` 416010 字节＝13867×30，无文件头；按上表取字形，`體`→体、`說`→说、`長`→长、`戰`→战；`後`、`於` 保持繁体形 | hsl.pak `@:\data\Font.24`／`Font.15`；`PYTHONPATH=tools python3 -m hsltools.sources.original_font show 體說長戰後於` | resource-derived |

### 各界面用哪张字库（0x460884 调用点）

`0x460884(字库, 模式, x, y, 串, 面, 前进, 颜色, …)` 是全 EXE 唯一的文字绘制入口，第一个参数是字库对象；全 EXE 70 个调用点，每个都在调用前从 `[0x4c1adc]`（FONT.15）或 `[0x4c1ae0]`（FONT.24）取这个参数，另 3 处引用是装载 `0x42f29c`／`0x42f31b`／`0x42f320`（static-derived，`objdump -d` 全文扫描）。带 `@` 色码的行由包装函数画：FONT.15 的 `0x411d70`（逐字）／`0x412060`（按宽居中），FONT.24 的 `0x4123b0`／`0x4128f0`／`0x412ad0`／`0x412d80`／`0x413040`／`0x4132f0` 等；`0x411d70`、`0x412060`、`0x4123b0` 起始色为 @1 白 `0xffff`、阴影 `0x8430`（`0x411d8e`／`0x411d96`、`0x41207f`／`0x412087`、`0x4123ce`／`0x4123d6`），阴影画在 (x+1, y+1)，前进 FONT.15 半角 8、FONT.24 半角 12。

`@N` 色码：包装函数遇 `@`（`0x411dba cmp 0x40`）取下一字节减 `'0'` 为 N，前景取 `0x476b44+4N`、阴影取 `0x476b46+4N`（`0x411e67`–`0x411e78`，static-derived）。全表（RGB565 → RGB，前景／阴影）：

| 码 | 前景 | 阴影 |
| --- | --- | --- |
| @0 | `0x9d1f` (156,162,255) 淡蓝 | `0x2150` |
| @1 | `0xffff` (255,255,255) 白 | `0x8430` |
| @2 | `0xfa8a` (255,81,82) 红 | `0x8000` |
| @3 | `0xcff9` (206,255,206) 绿 | `0x542a` |
| @4 | `0xf51e` (247,162,247) 粉 | `0x794f` |
| @5 | `0xffef` (255,255,123) 黄 | `0x8420` |
| @6 | `0xfffb` (255,255,222) 米白 | `0x842c` |
| @7 | `0x5e9d` (90,211,239) 青 | `0x02ce` |

EXE 里成串的色码字符串：`@1`／`@2`／`@3`／`@6` 在 `0x476c80`／`0x476c84`／`0x476c50`／`0x476c88`，`@5` `0x47856c`，`@4` `0x4785d0`（只有 `0x4353b3` 一处读者）；`@6` 的读者是背包行 `0x435e1f`／`0x435ea4`（重要物）与得物窗 `0x414f03`／`0x4150d9`。

| 界面 | 字库 | 调用点与字行 |
| --- | --- | --- |
| 对白框（`0x414220`） | FONT.24 | 名字与正文 `0x413040`（`0x4142ff`／`0x4143aa`）、`0x412d80`（`0x414352`）；第 i 行字格顶 ＝ 文字窗顶 ＋ 28·i − 上卷量；▼／□ 直调 `0x41480a`／`0x414848`／`0x414888`，阴影 (+1,+1) `0x8430` |
| 胜负条件面板（`0x413a80`） | FONT.24 | `0x412ad0` ×4（`0x413adb`／`0x413b13`／`0x413b55`／`0x413b89`），行 x＋20，标题 y＋17、胜利行 y＋51 起、失败标题 y＋145、失败行 y＋179 起，行距 28 |
| 施法名字幕（`0x43e110`／`0x43e1c0`） | FONT.24 | 阴影 (+1,+1) 黑 0、正文白（[施法叠层](../original_cast_overlays.md)） |
| 升级窗、资料页正文与技能名（`0x437a40` 以后的窗过程） | FONT.24 | `0x4123b0` ×10、`0x4132f0` ×7（悬停重画） |
| 得物窗、商店（`0x414c00`） | FONT.24 | `0x4123b0`（`0x415371`）、`0x4128f0`（`0x414f6e`）、`0x4132f0`（`0x4155f8`） |
| 仓库窗（`0x4285e0`） | FONT.24／FONT.15 | 行 `0x4123b0` ×7、`0x4132f0` ×7；另 `0x411d70`（`0x428fb4`）与直调 `0x42a3ec`／`0x42a41e` 用 FONT.15 |
| 系统设定面板（`0x424680`） | FONT.24 | 直调 `0x4251ac`／`0x4251e4`／`0x425216`／`0x42524b` |
| 大地图状态栏（`0x427230`） | FONT.24 | 直调 `0x427309`／`0x42733b`／`0x427399`／`0x4273ca` |
| 大地图地点名（point 过程 `0x427df0`） | FONT.15 | `0x427e99`（阴影 `0x8430`，(x+1, y+1)）、`0x427ee0`（白）；x ＝ 点 x − 8·⌊字节数/2⌋，y ＝ 点 y − 25 |
| 城镇台词（`0x454e20`） | FONT.24 | 直调 `0x4562ec`／`0x4563a5` |
| 行动环图标说明字（`0x43e5d0`） | FONT.15 | `0x43e686`／`0x43e6b4`（[原生表现辅助](../native_presentation_helpers.md)） |
| 物品描述框（`0x436d70`） | FONT.15 | `0x412060(x+8, y+12, …, 45 半角, 行高 16)`（`0x436e20`） |
| 资料页按钮标签（`0x43a640`） | FONT.15 | 直调 `0x43a6f1`／`0x43a723`，(中心x − 21 + (42 − 8·字节数)/2, 中心y + 13) |
| 条旁 cur/max（`0x4365f0`） | FONT.15 | `0x411d70`（`0x4366cf`），条对象 `+0x80` 位 0x100 置位时 |
| 资料页另两行（`0x4384d5`／`0x438a92`） | FONT.15 | `0x411d70(x+0x16／x+0x1e, y+0x82, …, 行距 28)`，所画内容未读 |
| 城镇 select 选择窗（`0x4264a0`，行过程 `0x4264f0`） | FONT.24 | 平时 `0x412760`（阴影 `0x8430` 在 (+1,+1)、再白）、悬停 `0x412680` 用 `0x42c130` 脉冲绿、淡入淡出 `0x413040`；行 ＝ 窗 ＋ (17, 17 ＋ 28·i)（[original_world_town](../../runtime_observations/original_world_town/README.md)） |
| 未对应界面 | — | `0x42b2b0`（FONT.24：`0x4123b0`）、`0x423c90`（FONT.15 直调 `0x423f22`）、`0x42d3f0`（FONT.15 直调 `0x42d713`／`0x42d762`） |

### 逐字审读（glyph_review.json）

[`glyph_review.json`](glyph_review.json) 记录重制文本源里出现的每个"仅繁体字"（OpenCC `TSCharacters` 的键，共 672 个；含只出现在制作名单转写 `workteam_simplified.LINES` 里的 8 个姓名用字 鄧彥陳楊滄吳鄭劉，按文字行审读并经第二模型交叉判读，均为简体形；重製選項说明文字用到的 暫節緩頁飄駐 按字形位图目读，均为简体形 暂节缓页飘驻）在原版 FONT.24 上画成什么（resource-derived，目读字形位图；OpenCC 只提供候选形）：

- 656 个画成 OpenCC 的第一候选简体形；3 个画成别的简体形：`餘`→馀（与 WINDOW41 烘焙的"残馀点数"一致）、`鍊`→链、`囉`→罗。
- 7 个**原版字库保留繁体形**：後 於 夥 乾 徵 殭 麼（Over002 烘焙的结局文字里同样是"後"）。
- `職` 码位上画的是"翻"、`翻` 码位上画的是"职"（原版字库 bug：原版把"職業"显示成"翻业"、"翻騰"显示成"职腾"）；重制不照搬，显示 职／翻。
- `噁` 画成 口＋恶（U+2BAC7，扩展 E 区，系统字体没有）；重制显示 恶。
- 未能判读 3 个（24 px 下 钅／金 或 厂／广 分不清）：鍾 針 魘，重制暂用 OpenCC 候选（钟 针 魇），属 provisional。
- `絶` 不在 Big5（只出现在英文注释"絶技"里），原版无此字形。

## 重制接线

### 重制的单一转换点

与原版"文本不动、字形在显示层换"同构：文字源（生成数据、GDScript 字面量、`label.text`、存档）保持繁体原文，显示时经唯一接缝换成原版画出的字形。

- 文字：autoload `game/text/SimplifiedDisplay.gd` 安装 `game/text/SimplifiedDisplayTranslation.gd`（Godot `Translation`），每个 Control 显示文字时按 `content/generated/hsl/text/simplified_chars.json` 一字换一字（`hsl generate simplified_chars`，输入本包 `glyph_review.json`＋OpenCC 候选表）。一字对一字保证下标不变；`BattleUISkin.line_starts` 按显示形测量换行。
- 图片：`SimplifiedDisplay.texture_path` 按 `content/generated/hsl/text/simplified_images.json` 把烘焙繁体字的图换成简体重画。唯一一张是通关制作名单 `workteam.SHP`：`hsl generate workteam_simplified` 按 Big5 转写逐格处理（121 格）——只有仅繁体且 `glyph_review.json` 读为简体形的字（45 格，如 鄧→邓、漢→汉、劇→剧）清格后按原图行框／列距／墨色印原版 FONT.24 在同码位的字形，水平按原图该格字样居中（FONT.24 墨迹占格内第 1–23 列、原图字样占第 0–21 列，不居中会让重画字贴住右邻、左边空出一道缝）；字形换成游戏字库的，属 remake-invented；其余 76 格（繁简相同的字、半角 2D／3D、字库自己画繁体的字）保留原图字样逐像素不动。原因：FONT.24 只换字体不换字，而且有的字形不能用——`伋` 的亻画成类似 1 的粗笔（`信` 同），早先全格换字时名单里 4 处 林汝伋 读作乱码；`昶` 按原图保留（曾见的"昶空白"来自早于最终产物的对照图，产物里该格一直是原图字样）。未审读、属 `remake_choices` 或字形为空的仅繁体字让构建直接失败，不悄悄保留繁体。转写里两个存疑字按原图文字行判读（resource-derived）：吳致**松**（木旁竖笔贯通到格顶、无山头，不是 崧）、王浩**辰**（厂框、无宀，不是 宸）；与 FONT.24 候选字形的逐像素相似度两者相近（松 0.838／崧 0.855，辰 0.785／宸 0.802，字体不同，不作判据）。`image_inventory.json` 的 `redrawn_with_font24`／`shape_lettering_kept_for` 记两组字。标题 logo `Title002`（幻世錄）按品牌图保留。
- 检查：`hsl check content:simplified_display`——玩家可见字串（与 `content:player_copy_traditional` 同一范围）经表后不得剩下仅繁体字（原版字库自己保留的 後於夥乾徵殭麼 除外），表里没有的新繁体字直接失败；图片清单每张 sha256 不变，繁体图须有已登记的简体重画或保留理由；制作名单另逐格核对（`workteam_simplified.check_cells`，无需原版）：保留格及重画格以外的像素与原图一致，重画格有墨、只用原图墨色、且不同于原图。
- 方向参数：同一接缝可产出全繁——卸下 Translation（或换一张恒等表）即为繁体显示；那时需要重画的是全部简体烘焙图（WINDOW10／21／30／41、标题与系统卷轴 Title021–063、Over001／002、49 张关卡标题卡）。现只实现全简体方向。

字串盘点（不分方向，可复跑）：`PYTHONPATH=tools python3 -m hsltools.checks.simplified_display inventory`——某次基线扫描 902 个文件的 67 583 条玩家可见字串，762 个文件含仅繁体字，共 598 个不同的仅繁体字，仅简体字 0 个。

### 各窗字库

`game/text/OriginalBitmapFont.gd` 一个 FontFile 挂两面，请求字号 `BattleUISkin.FONT_BODY` 画 FONT.24、`FONT_SMALL` 画 FONT.15；各窗按上表选：`BattleDialogue`（名字、正文、▼）、`BattleWinFailBoard`、`BattleAttackCue`、`BattleGrowthPanel`、各面板金额与行名用 `FONT_BODY`；`BattleCommandMenu` 说明字、各面板描述框（行 (8, 12＋16i)）、资料页按钮标签（中心 y＋13）、`BattleItemUsePresentation` 与 `MagicImpactPresentation` 的条旁 cur/max、`WorldMapRuntime` 地点名用 `FONT_SMALL`。`BattleUISkin.text` 把字格顶放在原版传入的 y（FONT.24 行高 24 ＝ 字格）；`BattleUISkin.label` 默认色为 @1 白＋`0x8430` 阴影 (+1,+1)。没有原版对应物的重制窗（重製選項页、标题提示、续玩提示、重制按钮）沿用两面之一，属 remake-invented。

provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_font_script/README.md`（`SimplifiedDisplay.gd`、`SimplifiedDisplayTranslation.gd`；各窗字库与字行同一写法）。

## 复现

`PYTHONPATH=tools python3 -m hsltools.sources.original_font show 體說後職 [FONT.15]`（需原版安装，只打印文字字形）；无需原版：`python3 tools/hsl.py check content:simplified_display`。

## 边界


- 原版字形已导入为重制默认字体（OPT-FONT 原版值），系统字体只是改良值。
- 上表"未对应界面"四个函数与资料页 `0x4384d5`／`0x438a92` 两行画什么未读（provisional，替换证据：读出其串来源或 Wine 帧对上）；`MagicImpactPresentation` 条旁文字的位置、`WorldMapRuntime` 地点名的显示条件（`0x427df0` 开头的判断）未读。
- 不声明原版对扩展区以外所有 13867 个码位的画法；只审读了重制文本源用到的 672 个仅繁体字。
- 烘焙在素材图里的文字不经过字库，另见 [`image_inventory.json`](image_inventory.json)。
