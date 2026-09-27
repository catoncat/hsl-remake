# 宝箱：实例内容、接触、开启与待领取队列

> evidence: static-derived; resource-derived: 各关 OBS 宝箱模板的 obj_Attribute、PROCESS.DEF objattrATTACKFLAG、resource.h sfxGetTreasure; runtime-measured: 整个原映像经 0x42da60 进 1／2／3／6／19／28 关的首回合箱表、0x4156d0 整段领取的抽取与映像改动、同进程再进同关后的箱表、35 关 77 只箱首回合可见性普查 · status: live · functions: 0x407510, 0x411b90, 0x4156d0, 0x415730, 0x42bd50, 0x42c640, 0x42da60, 0x42ebe0, 0x42ec10, 0x445526, 0x4477b0, 0x44f290, 0x44f2d0, 0x44f4e0, 0x458c10, 0x45dc5c, 0x45e224, 0x45e307, 0x45e3ed, 0x45f655, 0x46be17, 0x46cf98 · tools: hsltools/data/treasures.py, hsltools/probes/_treasure_reentry.py, hsltools/probes/treasure.py · updated: 2026-09-27

## 结论

- 原版箱内八个 DWORD 取自 EVEF 实例 `+0x10`，非零值按序（重复保留）压入对象；玩家动作后缀接触后由 `0x4156d0` 把每件以数量 1 加入共享待领队列并置已开位，领取零随机抽取；AI 行动不开箱；已开位只在对象上，新关／再进关按 EVEF 重建，箱子复原；是否可见由对象模板 `objattrATTACKFLAG` 决定，隐藏箱接触时先放 `sfxGetTreasure`（static-derived；runtime-measured）。
- 重制 `game/sim/TreasureRules.gd` 按同一规则给出一次性提案，PlayLoop 持有账本与既有待领池；`game/battle/scene/BattleTreasurePresentation.gd` 只表现已提交的发现，隐藏箱不画、发现时放同一声音（static-derived）。
- 一致：六关首回合箱表、领取改动与 35 关 77 只箱的可见性（隐藏 54、可见 23）均与重制数据对上；删除时的淡出为重制表现（provisional）。

## 证据

**resource-derived**（原 BIN／OBS 完整 SHA 与 seed 再核对；指令锚点合并 SHA `2c2f37da51627bf69ec280d48e07daa5f7b52acf76dc96dbd214ec9797a24e25`）

| 关卡与 EVEF 记录 | 当前 32px 格 | 源内容（实例顺序） |
| --- | --- | --- |
| 歐姆村 1，记录 79 | (20,17) | 202 玻璃戒指、241 回復藥、246 解毒草 |
| 戈爾山道 2，记录 23 | (5,14) | 244 妖精之泉、244 妖精之泉、254 禦之源 |
| 戈爾山道 2，记录 24 | (15,14) | 2 闊刃劍、241 回復藥 |

零值不产生物品，重复 244 是两份。`defProcTreasureBox=41` 经进程表 `0x477cd0` 指向 `0x415730`；OBJ-001／OBJ-002 箱模板只提供形状与对象字段。模板普查：35 关 77 只箱中只有 obj-028.obs 与 obj-080.obs 的 798 `寶藏` 写 `obj_Attribute = objattrATTACKFLAG ; show shape`（PROCESS.DEF 第 76 行 `0x00010000`）；其余 798 `寶藏` 与 obj-028.obs 的 26 `寶藏(隱藏)` 都没有；28 关记录 40、41 为码 26。`0xa05`＝2565＝resource.h `sfxGetTreasure`，RESOURCE 2565＝`WAV\EFF0014.WAV`。

**static-derived**（SHA256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；[original_treasure.json](original_treasure.json)）

| 入口 | 已确认行为 | 边界 |
| --- | --- | --- |
| `0x42dae7` → `0x46be68` → `0x42bd50` | 14 次正常返回：208 字节实例记录，八词非零值按序压到对象 `+0x90`，保留重复 | 尾部以 0 与 777 预填，证明本回调不清零尾部 |
| `0x415730` 初始化 | 6 次正常返回：像素原点 `pixel & ~31`，接触矩形 32×32；消息 bit `0x10000` 决定保留形状或形状字写 `0xffff` | 覆盖对齐、未对齐、负坐标 |
| `0x4156d0` 领取 | 7 个新箱前段：非零内容各以数量 1 入队，再置 `0x08000000`；7 个初始已开箱正常返回；14 例再调一次不再发物 | 新箱停在删除调用 `0x45e3ed` 前（完整领取见 runtime-measured） |
| `0x44f290`／`0x44f2d0` | 有同 code 正数量行则相加，否则追加；零数量行不算持有；241×2 加八份得 10 | 明示 32 槽容量；入队不等于进人物八槽背包 |
| `0x4454f7` 动作后缀，经 `0x46cf98` | 7 个接触前段：tile flag `0x80000` 与 process41 独立检查；合成 16×16 矩形 x=8 接触、x=9 不接触 | 可见箱停领取入口，隐藏箱停声音入口 `0x4477b0`；无标志停 `0x44556f`，无／错对象停 `0x411b90` |

进关与读档：`0x42da60` 先调 `0x42c640`（`0x42c6a4` 调 `0x44f4e0` 释放待领队列 `0x4c1d28`），在 `0x42dad8` 以 `0x45e224` 清空对象池（基址 `[0x4a19c0]`、个数 `[0x4a19c4]`、步长 `[0x4a19c8]`=0xb0，散列桶 `0x4a35ec`）。读档旗 `[0x4c1ae4]`=0 时 `0x42dae7` 以 `0x46be17(0, 0x42bd50)` 按 EVEF 重建；分配器 `0x45e307` 按模板 `0x4a2728[code]` 整块复制 0xb0 字节，新箱无旧已开位。旗 bit31（回憶錄）同样 EVEF 重建再 `0x42ec10(slot,1)`；其余非零值走 `0x42db43` 的 `0x42ebe0(1)`（戰場記錄）恢复存档对象。删除器 `0x45e3ed` 只还池；无全局开箱表，回憶錄块表（[original_save_format](original_save_format.md)）无关卡对象块。队列另在交接 `0x407510` 的 `0x40751c` 释放。`0x4156d0` 唯一调用点是玩家动作后缀 `0x44554c`。

### 隐藏宝物

可见性链：OBS 加载 `0x45dc5c` 把 `obj_Attribute` 写进模板 `+0x80`（[字段覆盖](original_field_coverage.md)）→ EVEF 遍历 `0x46be60` 以 `(x, y, 码, 0)` 调 `0x45e307`，复制模板后 `+0x80 |= 0xb0000000`、`+0x54` 写码 → 调度 `0x45f636..0x45f655` 以 `过程表[+0x64](obj, obj[+0x80])` 调用 → `0x415730` 见 `0x20000000` 清位、置 `0x100000`，消息无 `0x10000` 时形状字 `+0x30` 写 `0xffff`（原版通用隐藏值，同见 `0x4287cc` 写入、`0x428795` 从 `+0x32` 复原）。EVEF 记录只给码与位置。

接触：`0x445526` 见 `+0x30`=`0xffff` 先 `0x4477b0(0xa05,0)` → `0x459990` → `0x42c180` 放声，再进 `0x4156d0`；可见箱直接进 `0x4156d0`，不放声；`0x4156d0` 本身不放声。

**runtime-measured**（`tools/hsltools/probes/_treasure_reentry.py`，诊断用、不注册任务：`_enemy_level.round_sort_machine` 让整个原映像经 `0x42da60`（读档旗 0）进关，停在首次回合排序 `0x407340`；整段执行一次 `0x4156d0`（含 `0x44f2d0`、`0x45e3ed`），计 `0x458c10` 调用；再同进程进同关重读）

| 关 | 首回合箱（隐藏／总数） | 领第一只：队列、活对象 `0x4a19dc` | 同关再进 |
| --- | --- | --- | --- |
| 1 | 1／1，(640,544) 202、241、246 | 空→202×1、241×1、246×1；109→108 | 箱表逐字相同，队列空，活对象 109 |
| 2 | 2／2，(160,448) 244、244、254；(480,448) 2、241 | 空→244×2、254×1；32→31 | 相同，队列空 |
| 3 | 1／1，(608,352) 210 | 空→210×1；28→27 | 相同，队列空 |
| 6 | 2／2，(800,672) 205、253；(384,320) 255、210 | 空→205×1、253×1；62→61 | 相同，队列空 |
| 19 | 3／3 | 空→228×1；12→11 | 相同，队列空 |
| 28 | 2／21（记录 40、41 隐藏） | 空→171×1；51→50 | 相同，队列空 |

六关领取期间 `0x458c10` 调用 0 次，全局流 `0x4795d4／0x4795d8` 与伤害流 `0x4c3044／0x4c3040` 不变；映像只改活对象数 `0x4a19dc` 与队列 `0x4c1d28／0x4c1d2c／0x4c1d30`（6 关另有池空闲提示 `0x4a19d8`、节点提示 `0x4a35f0`）；领后对象 `+0x80` 为 `0x08100000`。再进关的抽取属于开场本身。

`--census <关>`：35 关 77 只全部由模板 bit `0x10000` 决定可见性，隐藏 54、可见 23；`--level 28` 再进关逐只可见性相同。

| 28 关记录 | 码 | 模板 `+0x80` | 首回合 `+0x80` | 形状字 `+0x30` | 可见 |
| --- | --- | --- | --- | --- | --- |
| 17–20、22–35（18 只） | 798 | `0x10000` | `0x80110000` | `0x48f` | 可见 |
| 21 | 798 | `0x10000` | `0x82110000`（另有 `0x02000000`，未追） | `0x48f` | 可见 |
| 40、41 | 26 | `0x0` | `0x80100000` | `0xffff` | 隐藏 |

其余：1、2、3、5、6、7、10、12、13、15、17、19、21、22、24、26、29、30、31、32、33、34、36、37、38、39、41、44、900–904 关的 52 只全部隐藏；80 关记录 46、48、49、50 全部可见；抽查 12（记录 108）、26（52）、80 与模板预测一致。

## 重制接线

- `tools/hsltools/data/treasures.py`：源记录、地图物件位置与物品目录 → `content/generated/hsl/treasures/battles.json`（含 `hidden`）。
- `game/sim/TreasureRules.gd`：行动尾部一次性提案，入既有待领池；隐藏与可见箱同一领取规则。provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_treasure.md`。
- `game/battle/scene/BattleTreasurePresentation.gd`：只显示已提交发现；隐藏箱不画、无悬停提示，发现时放 `sfxGetTreasure`；删除以短淡出表示（provisional）。

## 复现

`python3 tools/hsl.py check treasure`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [treasure](../runtime_observations/treasure/receipt.json) | natural_pickup、full、duplicates、attack、defeat、victory、campaign、resume_pool | `run_treasure_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 接触矩形测试用合成 16×16 角色，不推广到所有演员形状。
- 待领队列容量按 32 槽测试，未测内存扩容。
- 28 关记录 21 的 `0x02000000` 位含义未追。
- 删除时的淡出时长为重制表现。
