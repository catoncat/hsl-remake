# 原版配乐：播放引擎、关卡曲目表与各场景何时放哪首（static-derived）

> evidence: static-derived; resource-derived: STORY／WINFAIL／TOWNDEF／STORYOVER 脚本与 obj-998.obs（hsl.pak）、music\NN.wav（Steam 經典版） · status: live · functions: 0x42b6b0, 0x42c1c0, 0x42c250, 0x42c340, 0x42c360, 0x42c380, 0x42d7c0, 0x42da60, 0x42def0, 0x452a80, 0x452a97, 0x452ab7, 0x4561d0, 0x459ec0, 0x45a0b0 · tools: hsl_steam_classic.py · updated: 2026-09-28

核对：r2 静态反汇编 `$HSL_ORIGINAL_DIR/hsl01.exe`（SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`），脚本取自本机 hsl.pak（即 Steam 的 hsl-cn.pak）。曲目文件本身（18 首 `music\02.wav`–`19.wav`，22050 Hz 立体声 16-bit）见 [Steam 經典版](../resource_inventory/steam_classic_edition.md)。本包只记原版程序怎样使用这些曲目。

## 结论

- 曲号就是文件名：PlayMusic(n) 放 `music\%02d.wav`。n = −1 表示不换，当前曲继续放。每次调用都从头放，同一首也会重头开始。
- 每首都是整首无缝循环：读到结尾就接回开头，没有循环点，也没有淡入淡出。
- 换关必停：每次离开关卡都会停乐，新关卡放什么由它的剧本决定（§4）。剧本里没有放乐动作，这一关就是静音。
- 标题 03，在厂商标志之后开始。大地图 06。进城 05，回到大地图时 06 从头放。读「戰場記錄」后放所读关卡的表内曲目；读「回憶錄」不经过这一步（§3.1）。
- 战败画面没有音乐，只有 sfxGameOver 音效。影片一开播就停乐，播完也不恢复。通关尾声依次放 07 → 04 → 02（§3.5）。

## 证据

§1–§4 是逐条读法：播放引擎、曲目表与调用点为 static-derived（r2 反汇编），剧本放乐动作为 resource-derived（hsl.pak 脚本）。

## 1 播放引擎

| 函数 | 行为 |
|---|---|
| PlayMusic(n) `0x42c250` | 依次判断：<br>• [0x4c1af8]（音频可用）为 0 → 直接返回。<br>• 音乐音量 [0x477c24]（默认 255）为 0 → 只把 n 写进 [0x477c10] 就返回。之后没有代码读这个值，所以把音量从 0 调高不会补放，要等下一次调用。<br>• n = −1 → 返回，当前曲照放。<br>• 其余情况：停掉当前流（[0x4c1c74]，0x459dd0），格式化 `music\%02d.wav`（0x42c2ba），调用 0x45a0b0(路径, 音量, 4)（0x42c2f2）。 |
| 流播放器 `0x45a0b0` | 3 个槽（0x4c6fc0，每槽 0x20 字节）。读 80 字节文件头，不是 RIFF 就按 0xA8 异或解码。第三参数 4 乘以头部偏移 28 的 nAvgBytesPerSec，得到 4 秒的缓冲区，不是循环开关。用 timeSetEvent 定时器，回调 0x459f60。 |
| 续流 `0x459ec0` | 数据读完时把读取位置移回数据起点继续读，所以是整首循环，没有循环点。 |
| StopMusic `0x42c380` | 停流，并置 [0x477c10] = −1。调用点：EnterLevel 结尾 0x42dc2a（每次离开关卡），以及影片播放器开头 0x42def1。 |
| 关卡曲目 `0x42c1c0` | 参数 −1 时取当前关卡 [0x4c1bb8]。关卡号 ≥ 100 → 返回 −1。否则读 int16 表 0x477b44[关卡]（§2）。 |
| PlayLevelMusic `0x42c340` | = PlayMusic(关卡曲目(−1))。调用点：actPlayLevelMusic 0x452a80、大地图 0x427532／0x427d31、EnterLevel 0x42dba4／0x42dbc4。 |
| PlayDefaultLevelMusic `0x42c360` | = PlayMusic(关卡曲目(L))，L 为参数。调用点：actPlayDefaultLevelMusic 0x452a97（L 由脚本给出），以及调试热键播完影片后的恢复 0x42d654／0x42d692。 |
| actPlayMusic N | 0x452ab7 → PlayMusic(N)。 |
| 流音量 `0x459d70` | IDirectSoundBuffer::SetVolume 的参数＝(⌊60v/255⌋ − 60) × 40（百分之一 dB，下限 −10000），v 为 0–255 的音量。v = 255 → 0 dB，v = 0 → −24 dB，不是静音。 |

PlayMusic 和 StopMusic 都是立即起停，没有渐变参数。音乐音量与音效音量默认都是 255。

## 2 关卡曲目表 `0x477b44`（关卡 0–99，int16）

| 关卡 | +0 | +1 | +2 | +3 | +4 | +5 | +6 | +7 | +8 | +9 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 13 | 12 | 14 | 2 | 18 | 17 | 13 | 11 | 16 |
| 10 | 15 | 2 | 14 | 15 | 2 | 12 | 2 | 12 | 18 | 17 |
| 20 | 2 | 14 | 17 | 2 | 19 | 2 | 12 | 2 | 13 | 16 |
| 30 | 14 | 13 | 19 | 18 | 17 | 2 | 13 | 14 | 15 | 11 |
| 40 | 16 | 17 | 2 | 16 | 18 | 13 | 2 | 2 | 2 | 6 |
| 50 | 2 | 19 | 16 | 18 | 2 | 8 | 8 | 8 | 8 | 14 |
| 60 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 8 |
| 70 | 9 | 8 | 8 | 9 | 2 | 17 | 13 | 18 | 16 | 14 |
| 80 | 14 | 9 | 9 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| 90 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |

关卡 0 是标题（03），关卡 49 是大地图（06）。关卡 ≥ 100（501–578、900–904、998、999）不查表，一律为 −1。

## 3 谁在什么时候放

### 3.1 换关（EnterLevel `0x42da60`）

- 主循环 0x42f7dd 以 [0x4c1ba8] 调用 EnterLevel。[0x477c18] 是命令行指定的关卡。
- EnterLevel 置当前关卡 [0x4c1bb8]。关卡 51 且不是读档时，先播影片 MOVIE\START。
- 读档分两种，由读档标志 [0x4c1ae4] 区分，两者都经读档器 0x42e640：
  - 戰場記錄（HSLBAT）：入口 0x42cc70 置标志为 1，调用点 0x42406f／0x425899／0x425f03（各菜单的「讀取戰場記錄」）。EnterLevel 以 0x42ebe0 读档，成功后在 0x42dba4 调 PlayLevelMusic，放所读关卡的表内曲目。关卡 ≥ 100 得 −1，离关时已停乐，结果无声。
  - 回憶錄（存档槽）：入口 0x42ccc0 置标志为 槽号|0x80000000，调用点 0x424dd9。EnterLevel 以 0x42ec10 读档，成功后直接跳到 0x42dba9，不调用 PlayLevelMusic。之后放什么由恢复出的物件决定，未查明。
- 不是读档且关卡为 0 → 0x42d7c0(200) 依次显示 0x477d88 形状表里的厂商标志（首项 SHAPE\MARK0001.SHP），然后 PlayLevelMusic，即标题曲 03。
- 其余关卡进场时引擎不放乐，由剧本决定（§4）。
- 离开关卡时（EnterLevel 结尾 0x42dc2a）调用 StopMusic，所以任何换关都先静音。

### 3.2 大地图与城镇

- 大地图是关卡 49。初始化时 0x427532 调用 PlayLevelMusic，放 06。
- 城镇是大地图里的物件，不换关。defProcTownBOSS 0x4561d0 经 0x4545e0 载入城镇（城镇物件由 0x456150 创建）：载入成功就在 0x4564e1 调用 PlayMusic(5)，失败则把结果写成 2。
- 回到大地图：0x427d31 在城镇结果 [esi+0xac] 既不是 0 也不是 2 时再调 PlayLevelMusic，06 从头放。结果为 2（城镇没打开）时不动。

### 3.3 战败

战败 → 0x42cbd0 进关卡 999，离开原关卡时已经停乐。defProcGameOverBOSS 0x42aea0 不调用任何放乐函数，只放 sfxGameOver 音效。

### 3.4 影片

影片播放器 0x42def0 开头就调用 StopMusic（0x42def1）。有两处影片：
- WINFAIL059 act4 的 actPlayMovie（0x451b1c）播 MOVIE\END，之后没有任何恢复放乐的调用。
- 关卡 51 的开场影片 MOVIE\START 也一样；播完后由 STORY051 act0 放 19。

### 3.5 通关尾声（关卡 998，defProcClearBOSS `0x42b6b0`，状态跳转表 0x42b9c0）

| 时刻 | 画面（obj-998.obs 物件） | 音乐 |
|---|---|---|
| 物件首次执行（标志 0x20000000，0x42b6cc） | 等 40 帧 | PlayMusic(7) |
| 状态 1 | 物件 30「GameClear Show」（OVER001.SHP） | 07 继续 |
| 状态 3 | 装载 DATA\STORYOVER.TXT（尾声独白） | 07 继续 |
| 状态 9 | 物件 31「GameClear Show 2」（OVER002.SHP） | 07 继续 |
| 状态 11（0x42b898） | 物件 11–19「GameClear Player」（TITLE011.SHP，defProcClearShowPlayer）逐个出场，共九位主角 | PlayMusic(4) |
| 状态 16–17（0x42b95e） | 倒数 240 帧后，出现物件 20「GameClear Credits」（WORKTEAM.SHP，defProcClearShowWorkTeam） | PlayMusic(2) |
| 状态 19 | 等按键 → 0x42cc10(0,0) 回标题 | 回标题后放 03 |

obj-998.obs 的其余物件：5 MessageBox、10 GameClear BOSS（OVERBG01.SHP）、180–188 players install、799 StoryProcess。

## 4 剧本里的放乐动作

记号：
- `MUS n` = actPlayMusic n。
- `LVL→t` = actPlayLevelMusic，按当前关卡查表得 t。
- `DEF(L)→t` = actPlayDefaultLevelMusic L，查关卡 L 的表内曲目得 t。
- `actN/总数` = 第 0 节里的动作序号（从 0 起）和该节动作总数。

表中只列有放乐动作的脚本。TOWNDEF 和 STORYOVER 没有放乐动作。

| 脚本 | 放乐动作（按先后） |
|---|---|
| STORY001 | MUS 8（act0/36） → LVL→13（act27/36） |
| STORY002 | LVL→12（act0/18） |
| STORY003 | LVL→14（act0/16） |
| STORY005 | LVL→18（act1/26） |
| STORY006 | LVL→17（act1/31） |
| STORY007 | LVL→13（act1/27） |
| STORY008 | MUS 8（act1/25） |
| STORY009 | MUS 8（act1/31） |
| STORY010 | MUS 8（act0/46） → LVL→15（act45/46） |
| STORY012 | MUS 9（act0/43） → LVL→14（act42/43） |
| STORY013 | LVL→15（act0/62） |
| STORY015 | MUS 9（act0/26） → LVL→12（act8/26） |
| STORY017 | LVL→12（act0/28） |
| STORY018 | MUS 9（act0/61） → LVL→18（act59/61） |
| STORY019 | MUS 9（act0/22） → LVL→17（act21/22） |
| STORY021 | LVL→14（act0/40） |
| STORY022 | MUS 8（act0/40） → LVL→17（act39/40） |
| STORY024 | LVL→19（act0/27） |
| STORY026 | MUS 8（act0/32） → LVL→12（act31/32） |
| STORY028 | LVL→13（act0/53） |
| STORY029 | LVL→16（act0/54） |
| STORY030 | LVL→14（act0/57） |
| STORY031 | MUS 9（act0/41） → LVL→13（act19/41） |
| STORY032 | LVL→19（act0/47） |
| STORY033 | MUS 8（act0/63） → LVL→18（act17/63） |
| STORY034 | MUS 9（act0/48） → LVL→17（act47/48） |
| STORY036 | MUS 9（act0/46） → LVL→13（act45/46） |
| STORY037 | MUS 9（act0/87） → LVL→14（act15/87） |
| STORY038 | LVL→15（act0/69） |
| STORY039 | LVL→11（act0/27） |
| STORY040 | LVL→16（act0/29） |
| STORY041 | MUS 9（act0/61） → LVL→17（act17/61） |
| STORY043 | LVL→16（act0/51） |
| STORY044 | LVL→18（act0/26） |
| STORY045 | LVL→13（act0/22） |
| STORY051 | LVL→19（act0/18） |
| STORY052 | LVL→16（act1/55） |
| STORY053 | MUS 8（act1/36） → LVL→18（act35/36） |
| STORY055 | MUS 8（act0/18） |
| STORY056 | MUS 8（act0/12） |
| STORY057 | MUS 10（act0/11） |
| STORY058 | MUS 8（act1/35） |
| STORY059 | LVL→14（act0/51） |
| STORY060 | MUS 8（act1/26） |
| STORY061–069 | MUS 8（各自 act0） |
| STORY070 | MUS 9（act0/14） |
| STORY071 | MUS 8（act0/21） |
| STORY072 | MUS 10（act0/23） |
| STORY073 | MUS 9（act0/6） |
| STORY074 | MUS 9（act0/42） |
| STORY075 | LVL→17（act0/37） |
| STORY076 | LVL→13（act0/37） |
| STORY077 | LVL→18（act0/41） |
| STORY078 | LVL→16（act0/34） |
| STORY079 | LVL→14（act0/35） |
| STORY080 | LVL→14（act0/30） |
| STORY081 | MUS 10（act0/30） |
| STORY082 | MUS 4（act0/16） |
| STORY097／098／099 | LVL→2（act0） |
| STORY501–503 | DEF(2)→12（act0） |
| STORY504–506 | DEF(3)→14（act0） |
| STORY507–509 | DEF(5)→18（act0） |
| STORY510–512 | DEF(7)→13（act0） |
| STORY513–515 | DEF(10)→15（act0） |
| STORY516–518 | DEF(8)→11（act0） |
| STORY519–521 | DEF(17)→12（act0） |
| STORY522–524 | DEF(18)→18（act0） |
| STORY525–527 | DEF(19)→17（act0） |
| STORY528–530 | DEF(21)→14（act0） |
| STORY531–533 | DEF(24)→19（act0） |
| STORY534–536 | DEF(29)→16（act0） |
| STORY537–539 | DEF(12)→14（act0） |
| STORY540–542 | DEF(15)→12（act0） |
| STORY543–545 | DEF(30)→14（act0） |
| STORY546–548 | DEF(31)→13（act0） |
| STORY549–551 | DEF(33)→18（act0） |
| STORY552–554 | DEF(32)→19（act0） |
| STORY555–557 | DEF(34)→17（act0） |
| STORY558–560 | DEF(36)→13（act0） |
| STORY561–563 | DEF(39)→11（act0） |
| STORY564–566 | DEF(40)→16（act0） |
| STORY567–569 | DEF(41)→17（act0） |
| STORY570–572 | DEF(22)→17（act0） |
| STORY573–575 | DEF(44)→18（act0） |
| STORY576–578 | DEF(38)→15（act0） |
| STORY900 | MUS 8（act1/23） |
| STORY901／902／903 | LVL→−1（act0） |
| STORY904 | MUS 9（act0/22） → LVL→−1（act21/22） |
| WINFAIL059 | actPlayMovie（act4/6），停乐 |
| WINFAIL900 | 第 5 节事件 1 act15：LVL→−1 |

由此可得：
- STORY901／902／903 的 LVL 查表得 −1（关卡号 ≥ 100），而进关时已经停乐，所以这三关从头到尾没有音乐。
- STORY904 先放 09，act21 的 LVL 为 −1，所以 09 一直放下去。WINFAIL900 的 LVL 同样为 −1，不换曲。
- 只有 MUS、没有后续 LVL 的关卡（008、009、055–058、060–074、081、082、900），整关都放同一首剧情曲。
- 501–578 每三关共用一个基准关卡的表内曲目。

## 重制接线

- `GameSettings` 按 §1 放原曲、整首循环，音乐音量默认满。
- `BattleOpeningCoordinator`／`OpeningCinematics` 按剧本放乐动作换曲，`BattleSceneRuntime` 读「戰場記錄」时先停乐再放所读关卡的表内曲目（§3.1）。
- `TitleScreen`、`WorldMapRuntime`、`TownRuntime`、`GameClearScreen` 分别放标题、大地图、城镇与通关尾声的曲目（§3.2、§3.5）。

## 复现

```sh
python3 tools/hsl_steam_classic.py music   # 18 首曲目的格式与时长
r2 -e scr.color=0 -q -c 'pd 60 @ 0x42c250; pd 12 @ 0x42c1c0; pd 8 @ 0x42c380; pd 30 @ 0x459ec0; px 200 @ 0x477b44; pd 20 @ 0x42b6b0; pd 6 @ 0x42b898; pd 6 @ 0x42b95e; pd 6 @ 0x4564e1; pd 6 @ 0x427532; pd 8 @ 0x427d31' "$HSL_ORIGINAL_DIR/hsl01.exe"
```

调用点清单用 r2 `axt @ 0x42c250`／`0x42c340`／`0x42c360`／`0x42c380` 列出。脚本里的放乐动作用 `hsltools.sources.pak` 读 hsl.pak，从 STORY*／WINFAIL*／TOWNDEF／STORYOVER 里取 actPlayMusic／actPlayLevelMusic／actPlayDefaultLevelMusic／actPlayMovie 所在行，再按 §1 解析曲号。

## 边界

- 本包只记原版程序怎样使用曲目；曲目文件格式与时长见 [Steam 經典版](../resource_inventory/steam_classic_edition.md)。
