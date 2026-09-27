# Steam 經典版（幻世錄 1.06）：取得、清单、两套数据包与原曲

> evidence: resource-derived; static-derived: Steam hsl.exe 选包开关与 hsl01.exe 曲目调用点; negative-evidence: 本机原作目录与 hsl.pak 没有 music 文件; provisional: 两套数据包的先后与差异含义 · status: record-only · functions: 0x42b6b0, 0x42c1c0, 0x42c250, 0x4561d0 · tools: hsl_steam_classic.py · updated: 2026-09-26

**范围。** 用户 2026-09-26 购得 Steam《幻世錄 重製版》（app 4030150，UserJoy，2026-09-10 发售），包里完整收录 1998 年经典版，目录名 `GAME-PAK/`。本包记录怎样取得和核对这份目录、里面有什么、它和本机原作（`$HSL_ORIGINAL_DIR`）差在哪里，以及原曲 `music\NN.wav` 目前已知的用法。它不改变复刻的数据依据：复刻继续以本机原作为准，而本机的 `hsl.pak` 正是 Steam 里的 `hsl-cn.pak`（见下文）。

**位置与边界。** 目录放在仓库外：`~/hsl-steam/fancy-realm/GAME-PAK`（环境变量 `HSL_STEAM_CLASSIC`，代码里用 `hsltools.paths.STEAM_CLASSIC_ROOT`）。游戏文件不进仓库，也不要拿它覆盖 `$WINEPREFIX`（现有静态工具按 `hsl01.exe` 的 SHA 锁定）。Steam 账号只由用户本人登录（第一次扫码，之后记住登录），代理不经手账号和密码。

```bash
python3 tools/hsl_steam_classic.py fetch            # 打印 DepotDownloader 命令，由用户本人执行
python3 tools/hsl_steam_classic.py verify           # 逐文件 sha1 对照固定清单 → STEAM_CLASSIC_VERIFY … ok=191 bad=0 missing=0
python3 tools/hsl_steam_classic.py pakdiff --text   # 本机 hsl.pak 对 Steam 两个包逐成员比较，--text 附文本行差异（Big5）
python3 tools/hsl_steam_classic.py music            # 列出 music\*.wav 的格式与时长
```

## 取得（resource-derived）

- Steam 只有一个 Windows depot 4030151，完整下载 4.3 GB、安装后 9.6 GB。固定清单是 manifest `8466173651794257887`（2026-09-23），逐文件列表见 [`steam_classic_files.json`](steam_classic_files.json)（schema `hsl_steam_classic_files.v1`：路径相对 `GAME-PAK/`，附大小和 sha1；0 字节的 `Magpie/portable` 在 Steam 清单里哈希全为 0，列表记为 `null`，`verify` 按空文件的 sha1 核对）。
- 本机没有 Steam。下载工具是 DepotDownloader v3.4.0 的 macOS arm64 版，放在 `~/hsl-steam/bin/`。用 `-filelist`（内容 `regex:^GAME-PAK/`）只下经典版：2026-09-26 实测约 7 MB/s，191 个文件共 819,601,484 字节，用时 43 秒。重制版本体（约 8.9 GB）没有下载。

## 清单（resource-derived）

| 项 | 大小（字节） | 说明 |
| --- | ---: | --- |
| `hsl.exe` | 806,912 | Steam 1.06 程序；本机的 `hsl01.exe` 是 798,720 字节，两者不是同一个构建 |
| `hsl.pak` | 287,661,653 | Steam 默认读取的数据包（下文称"台版包"） |
| `hsl-cn.pak` | 287,687,381 | 加 `-langcn` 参数时读取（下文称"cn 包"）；成员与本机 `hsl.pak` 几乎全同 |
| `movie.pak` | 70,931,518 | 与本机 `movie.pak` 逐字节相同 |
| `music\02.wav`–`19.wav`、`null.wav` | 见下文 | 原曲；本机原作目录里没有 |
| `Readme.txt` | 4,749 | UTF-8，标注"幻世錄 HSL 版本 1.06"；说明的参数只有 `-nomagpie`、`-nosfx`、`-fullscreen`；存档放在 `SAVES\` |
| `Magpie\` | 约 30 MB | GPLv3 画面放大模块（Readme 说明基于 github.com/Blinue/Magpie 修改），不是游戏数据 |

两个包里的文字都是 Big5 繁体中文，"cn"只是 Steam 程序里的参数名，不代表简体。

## 两套数据包：Steam 程序怎样选（static-derived，Steam `hsl.exe` 地址）

下面三个地址属于 **Steam `hsl.exe`**，不是 `hsl01.exe`，所以没有写进本包头部的 functions 字段：

- `0x42ede0` 打开数据包：`[0x4c2b2c] == 1` 时读 `HSL-CN.PAK`，否则读 `HSL.PAK`。
- `0x457500` 解析命令行：`-langcn` 把标志设为 1，`-langtw` 设为 0；不带参数时为 0，读 `HSL.PAK`。Readme 没有提到这两个参数。
- 本机 `hsl01.exe` 里只有 `HSL.PAK` 这一个包名。

Steam 客户端实际给玩家带哪个参数（例如是否按商店语言带 `-langcn`），目前没有验证。

## 与本机原作逐成员比较（resource-derived）

| 比较 | 成员数 | 相同 | 内容不同 | 仅左侧 | 仅右侧 |
| --- | --- | ---: | ---: | --- | --- |
| 本机 `hsl.pak` → Steam `hsl-cn.pak` | 5600 → 5600 | 5599 | 0 | `shape\mark0100.shp` | `data\a.txt` |
| 本机 `hsl.pak` → Steam `hsl.pak`（台版包） | 5600 → 5574 | 5476 | 98 | 26 个（见下） | 0 |

cn 包多出的 `data\a.txt` 是一份 UTF-8 的统计输出，看起来是移植团队误打进包的：开头是 `(h5) E:\HSL\GAME_DIR\DATA>python stat_story.py`，统计全部剧情脚本共有 71 种 action、2825 次使用（其中 `actPlayDefaultLevelMusic` 78 次、`actPlayLevelMusic` 50 次、`actPlayMusic` 40 次）。游戏本身不读这个文件。

**本机有、台版包没有的 26 个成员：**

- `data\level097–099`：.bin、.wrd，另有 `level099.h`
- `data\obj-097–099`：.h、.obs
- `data\story097–099.txt`、`data\winfail097–099.txt`
- `shape\mark0100.shp`
- 根目录的 `update1.txt`–`update6.txt`，内容依次为：
  - "更新版V1.0"
  - "更新版V1.02"
  - "更新版V1.03"
  - "更新版V1.03"（第 4 个文件也写 V1.03）
  - "更新版V1.05"
  - "更新版V1.06"，外加"亞修頓大橋隨機戰場""守護聖者名稱"两行

**内容不同的 98 个成员**（按目录分：`shape01` 46、`shape` 31、`data` 20、`animal` 1）：

| 成员 | 差异（左＝本机／cn，右＝台版） |
| --- | --- |
| `data\players.txt` | 雷特（第 6 条）：str 35→32，con 34→32，hit_point 16→10，defense 8→6。嚎（第 7 条）：str 38→32，dex 14→12，mind 10→2，con 40→36 |
| `data\resource.txt` | 第 87 条：`公主` → `守護聖者`（位于职业名"祭司、神官"与"盜賊、暗殺者"之间）。第 2155 条：首都`斐達克` → `婓達克`（台版是错字）。第 658 条：本机给"拉爾斯帝國、法魯西翁大陸、沃斯菲塔共和國"加了颜色标记，台版没有。本机文件头多 3 行颜色／换行说明注释 |
| `data\towndef.txt` | 第 77 行货物表：台版 `item_id` 里有两个空位（`124,,125,,127`）。第 865、867 行：头像 `FACE0083` → `FACE0064` |
| `data\winfail026.txt` | 本机多 `actBMSetPointEvent,26,0,bmpmTown` 和 `actBMSetPointEncounterRatio,26,0` 两行 |
| `data\winfail044.txt` | 本机多 `actDeleteFailStatus,1` |
| `data\winfail052.txt` | 台版启用了 `action = actDEMO ; for demo loop`，本机这一行被注释掉 |
| `data\winfail015.txt` | 台版末尾多两行空行 |
| `data\animal.txt` | 第 145 行附近：本机把 `aniInsertAttackFlash,-194,-143` 注释掉、改用 `-300,-60`，台版用前者 |
| 二进制，未解码比较 | `data\font.15`、`data\font.24`；`data\level502/526/573/574/575.bin`、`data\level900.wrd`；`data\obj-045/057/078/081.obs`；`animal\bg029.shp` |
| `shape01\word*.shp`（46 个） | 关卡标题字图：001–003、005–007、010、012、013、015、017–019、021、022、024、026、028–034、036–041、043–045、051–053、059、075–080、900–902 |
| `shape\*.shp`（31 个） | `mark0012`，`over001`、`over002`，`title021`、`title024`–`026`、`title032`、`title033`、`title039`、`title041`–`047`、`title051`–`057`、`title061`–`063`，`window10`、`window21`、`window30`、`window41` |

复刻至今导入的都是左侧（本机＝cn 包）的值。例如雷特、嚎的属性，第 87 条职业名，第 26／44 关的胜负脚本，都来自本机这一份。

## 原曲（resource-derived＋static-derived）

18 首原曲加一个 `null.wav`，格式都是 22050 Hz、立体声、16 位 PCM，合计 26.6 分钟：

| 曲号 | 秒 | 曲号 | 秒 | 曲号 | 秒 |
| --- | ---: | --- | ---: | --- | ---: |
| 02 | 63.8 | 08 | 61.8 | 14 | 138.9 |
| 03 | 48.2 | 09 | 68.9 | 15 | 60.7 |
| 04 | 54.9 | 10 | 48.4 | 16 | 121.6 |
| 05 | 64.3 | 11 | 85.6 | 17 | 134.6 |
| 06 | 80.2 | 12 | 96.3 | 18 | 142.2 |
| 07 | 68.9 | 13 | 129.3 | 19 | 129.0 |
| `null` | 0.5 | | | | |

negative-evidence：本机原作目录里没有 `music\` 文件夹，本机 `hsl.pak`（以及 Steam 的两个包）也没有任何 music 成员。所以这份 Steam 目录是原曲在本机的唯一来源。

`hsl01.exe` 里目前已经确认的用法（static-derived）：

- `0x42c250` 按 `music\%02d.wav` 拼出文件名，交给 `0x45a0b0` 播放。exe 里另有 `music\null.wav` 字符串，用途还没定位。
- `0x42c1c0` 把参数换成曲号：参数 −1 表示取当前关卡 `[0x4c1bb8]`；关卡号 ≥ 100 时返回 −1（不放音乐）；其余情况查 int16 表 `0x477b44`。关卡表里出现的曲号有 2、3、6、8、9、11–19。level 51 的查表过程见 [第一战音频](../static_reverse/first_battle_audio.md)，大地图（level 49）用 6 号，见 [世界／城镇合同](../static_reverse/original_world_town.md)。
- 剧情脚本的 `actPlayMusic` 直接点名曲号，已见 4、8、9、10。
- `defProcTownBOSS`（过程表第 57 项，`0x4561d0`）在 `0x4564e1` 播 5 号，也就是城镇画面的音乐。
- `defProcClearBOSS`（第 74 项，`0x42b6b0`，见 [通关尾声](../static_reverse/original_game_clear_epilogue.md)）依次压入 7、4、2 号（`0x42b6da`／`0x42b8a0`／`0x42b960`）。

还没弄清的部分：标题画面放哪首；每首循环、停止和切换的规则；三种 `actPlay*Music` 在全部脚本里的出现位置和语义；GameClear 各段与 7／4／2 的对应；城镇 5 号结束后恢复哪首。这些会在接入原曲时另写一个静态证据包，在那之前以本节为准。如需把原曲转码进仓库，照 `movie_import` 的先例做：原始文件留在仓库外，只把转码结果放进 `content/imported/`。

## 开放问题（未验证）

1. **两个包哪个更新**（provisional）。倾向 cn 包（＝本机）更新，理由有五条：
   - 只有 cn 包带 V1.0–V1.06 的更新说明。
   - 只有 cn 包有 097–099 关，符合 V1.06 说明里的"亞修頓大橋隨機戰場"。
   - 只有 cn 包改掉了"婓達克"这个错字。
   - cn 包把 `actDEMO`（"for demo loop"）注释掉了。
   - "守護聖者名稱"读作"改了守護聖者这个名字"时，正好对上第 87 条从 `守護聖者` 变成 `公主`。

   反向读法也成立：如果那一行的意思是"新增守護聖者这个名字"，台版包就应该更新。目前没有其他证据能在两种读法之间定案。
2. Steam 客户端实际用哪个参数启动 `hsl.exe`（`-langcn`／`-langtw`／不带），也就是 Steam 玩家默认看到哪套数据。
3. `actDEMO` 在台版 52 关启用后的实际效果。
4. 未解码的二进制差异具体改了什么：字库、5xx 遭遇战地形、level900、四个 obs、标题字图、窗口图。
5. Steam `hsl.exe` 1.06 与本机 `hsl01.exe` 的代码差异：没有比较，现有静态结论只对 `hsl01.exe` 成立。
6. 雷特、嚎两套属性值哪套是某个版本的"正式"数值：复刻用的是本机值，要改必须用户拍板。
