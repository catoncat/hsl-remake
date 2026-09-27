# 世界地图与城镇初始化、到达及 te 条件

> evidence: static-derived; resource-derived · status: live · functions: 0x426b70, 0x426bb0, 0x426bf0, 0x426c70, 0x426ce0, 0x427200, 0x42c1c0, 0x42cc10, 0x42d090, 0x44e0e0, 0x454650, 0x4546c0, 0x454a20, 0x454ae0, 0x454cd0, 0x454db0, 0x454e20, 0x4606a9 · tools: hsltools/probes/world_town.py · updated: 2026-09-19

P-027 的原作研究交付。`static-derived` 指对指定原 EXE 的实际指令执行及其字节；`resource-derived` 指原 PAK 的表、OBS、EVEF、SHP。机器回执为 [original_world_town.json](original_world_town.json)，离线与重跑入口为 `tools/hsltools/probes/world_town.py`。本包不修改或验收 `game/world`、城镇解释器及其生成器；这些产品的当前状态仍看各自回执。

## 执行范围

当前包包含 100 个城镇记录的两次完整初始化、12 次根／子项选择完整返回、74 组地图变更 helper、22 组 te VM／失败阶段、32 组表现 helper／前段、27 组到达前段、21 组神秘商人及 16 组物品查找／可选消费。普通 helper 和 supplied-program VM 分支正常返回；地图新游戏设置、到达请求、失败对白创建、速度设置及状态栏绘制准备止于具名边界。没有用 stub 代替原 callee，没有把屏幕采样或模型标签当原指令回执。

`native-final.log` 对应新增状态栏文字前段，`native-final-queries.log` 另补齐根／子项 getter；两次原指令重跑均退出 0，打印 `WORLD_TOWN_NATIVE_PASS maps=74 vm=22 visuals=32 arrivals=27 secrets=21 items=16 initialized_towns=100 executed_now=True`。原始日志在 `ignored/world-town-research/`；长期事实由本包的输入、输出、指令字节和可复跑工具保存。六项 Python 回归检测篡改输出、边界和字节，完整仓库门禁结果另记本次提交说明。

## 城镇归属与初始树

`0x454ae0` 将 `0x4c1d74` 指向的 **100×264 字节**清零，然后完整调用 `0x454a20`。后者通过带 town id 的调用逐项建立树，并非一张“12 城×event”的静态矩阵。每城有 8 个根槽，每根存根 event code 加 7 个子项，尾部两个 DWORD 为入城／离城事件覆盖；本入口重置后均为 0。`0x454650` 的查询地址为 `town*264 + root_slot*32 + child_slot*4`，根节点与其子项共享同一条记录。

下表是两次完整原初始化的相同结果。名称／id 来自原 `extras.h`，根／子项来自原指令输出；空表表示**该新游戏入口后为空**，不表示这个城在整个流程中没有事件。

| town id | 城镇 | 初始根节点 | 初始子项 |
| --- | --- | --- | --- |
| 1 | 歐姆村 | 1, 2, 3 | 无 |
| 4 | 米蘭多 | 4, 5, 6, 7 | 7 → 8, 12, 13, 14 |
| 6 | 席達鎮 | 16, 17, 18, 20 | 20 → 21, 22, 23 |
| 9 | 曼多力亞 | 空 | 空 |
| 11 | 薛維斯港 | 空 | 空 |
| 14 | 兩棲族部落 | 空 | 空 |
| 16 | 命運神殿 | 空 | 空 |
| 23 | 瑪哈亞鎮 | 空 | 空 |
| 25 | 戈黎塔尼港 | 空 | 空 |
| 27 | 亞雷比斯 | 空 | 空 |
| 35 | 沙羅尼亞 | 空 | 空 |
| 42 | 斐達克 | 空 | 空 |

其余 88 个槽位也为空。菜单归属由这组可变记录及后续带 town／parent 的增删调用决定；`TOWNDEF.TXT` 是 event 的定义，不含可替代运行时树的永久城镇归属。段尾注释、event 编号邻近或“该镇附近的事件”不能作为初始菜单来源。现有 `teCheckTEExist`、神秘商人回执还执行了查询和加入子项的实际 helper。

`teCreateSubEventMenu`（10）在 `0x454e20` 返回 2，保存后续程序位置，不重新运行初始树。**边界**：回执证明 VM 的返回／游标和可变父子记录；完整菜单对象创建、焦点／返回导航及后期所有树变更未在本探针执行。使用者应从当前城镇／当前根的现有子项生成 UI，不从 TOWNDEF 注释重新归类。

## bigmap.dat 的三个独立字段

原文件长 5600 字节：100×40 字节点记录，再接 100×16 字节路线记录，其中 45 个点、44 条路线非空。点数组运行时位于 `0x4c4a20`，路线数组位于 `0x4c43c0`。

| 字段 | 已确认用途 | 原入口／回执 |
| --- | --- | --- |
| 点、路线 `+0`（field0） | 展示阶段：0 不显示、1 揭示阶段、2 稳定显示；与 Hidden 位分开 | `0x426b70/0x426bb0/0x426bf0`；点 `0x427df0`、路线 `0x4280d0` 的模式回调 |
| `+4`（field1） | Hidden `0x08000000`、Visit `0x10000000`、Town `0x20000000`、General `0x40000000`、Battle `0x80000000` | 类型替换 `0x426c70`、到达 `0x427ab3..0x427b95` |
| 点 `+8` | 可变事件值；原文件的 45 个非空点初值均等于点号，但后续可独立改写 | getter `0x426ce0`、setter `0x426c70`、到达前段 |

普通模式 setter 在 Hidden 时不改值；已有 mode2 也不被普通 setter 降回 0/1。路线强制 setter `0x426bf0` 可替换 mode2，但仍受 Hidden 限制。`0x426c70(point,event,flags)` 中 event=-1 保留原 event；flags 非零先清 Visit，含 Town／General／Battle 时清旧类型再 OR 新值；flags=0 不清 Visit／类型。不能把“不显示”与“禁止揭示”的 Hidden 位合并成一个布尔值。

原新游戏在读取两组记录后，于 `0x42c86e..0x42ca2a` 将点 1 设 mode2，并 OR 下列 Hidden 位；该前段止于后续初始化调用之前：

* 点：11, 12, 13, 14, 15, 16, 22, 25, 26, 27, 28, 31, 32, 33, 34, 38, 43。
* 路线：10, 11, 12, 13, 14, 20, 23, 24, 25, 26, 29, 30, 31, 32, 33, 34, 37, 43。

这支持“原初始可见点为歐姆村，其余须经展示阶段揭示”，不支持重制默认绘制全部点的原版等价声明。

### 到达／默认 level

`0x427ab3` 先读目的点当前 `+8`，再读类型；不存在“到达时发现 event 缺失便用点号”的补偿分支。点 N 初始 event=N 是 **bigmap 文件已给出的数据**。27 组原前段使用不同 event／type／Visit／selected／概率输入：

| 当前记录 | 原分支 |
| --- | --- |
| event=0 | 不请求关卡／城镇 |
| General，未 Visit | 使用当前 event 请求关卡 |
| General，已 Visit | 先过 encounter ratio 与 1..100 抽样，再在当前 event 上加 0..2 |
| Battle，未 Visit／已 Visit | 未访问使用 event；已访问加 0..2，不走 General 的 encounter 检查 |
| Town | 仅当它是实际选定目的点时写城镇 id 为 event，进入 phase15，并标 Visit；路过不进城 |

General 的判断在 Battle 之前。关卡请求用 `0x42cc10`；探针在调用前 `0x427b3e` 停止，因此关卡加载、UI 和请求后的 Visit 写入另列，不冒称完整切关。城镇／无动作前段止于 `0x427b95`。

**negative-evidence：独立默认 level 表。** 在本次检查的 raw load→`+8` setter/getter→到达路径中没有第二张缺省表，实际输入为当前点记录。没有据此断言整个 EXE 绝无其他场景选择表；接入不得删去源文件已有的默认 event，也不应另造点号 fallback。

## 大地图对象、行走和状态栏

原 `PROCESS.DEF` 与表 `0x477c2c` 将 point32／track33／walker35／statusbar51 分别连接 `0x427df0`、`0x4280d0`、`0x427420`、`0x427230`。原 OBS／EVEF／SHP 哈希、45 点和 44 路线的完整 join 保存在回执 `object_sources`；这一段 join 是 `resource-derived`，不会伪装成原 loader 完整执行。

| 项目 | 可采用的结论 | 边界 |
| --- | --- | --- |
| `m_pnt` | 原 45 个点全部以 `M_PNT001.SHP` 为 shape 起始、`obj_Shape_Number=3`；`POINT.H` 的 Battle0／General1／Town2 经 `0x427f0d` 加到基础 frame，故是连续三帧选型 | 不是直接按三个不同文件名字分配类型；动态 bmpm 类型与 OBS 的视觉类型分开 |
| 点命中区 | 原初始化写相对 `[-16,-16,16,16]` 的方框 | 32 像素范围已执行；鼠标按下／放开与重叠优先级未执行 |
| `m_trk` 落点 | level049 EVEF 给出对象锚点，SHP 给出 draw origin；顶左为锚点减 origin。44 条记录均已保存。第 1 条锚点(910,527)，origin(51,60)，53×61 图像 | 不用包围盒左上冒充源锚点；地图缩放／颜色还需表现验收 |
| 路线 mode1 | `0x4280d0` 用 `0x4606a9` 取得原 shape 边界，逐逻辑更新扩张裁剪矩形，完成后设路线 mode2、端点 mode1并减 pending 计数。lane TOWNMAP 读 r2 反汇编补全时钟：子状态 0 那一 tick 置裁剪位 `[obj] \|= 0x1000000`、半边 `+0x94 = 0`，取 `0x4606a9` 的 shape `+0xc/+0x10`（draw origin）与 `+8/+4`（宽／高），计数 `+0x90 = max(\|w−ox\|, \|ox\|, \|h−oy\|, \|oy\|)`（锚点到最远边的距离）；子状态 1 每 tick 半边 +1、计数 −1，计数到 0 那 tick 设 mode2、清裁剪位、两端点 `0x426b70(point,1)`、`[0x4c1abc]+0x88` 减一；每 tick 尾 `0x428280` 把裁剪写成锚点（`+4/+8`，即 EVEF 位置＝路线 from 点）± 半边的正方形。第 1 条（origin (51,60)、53×61）为 60 tick | **negative-evidence**：被检查的回调没有“红→白插值”算法；不能由截图或贴图颜色推导调色时钟 |
| 行走速度 | `0x4277ed` 设置 `+0x88=0x20000`，即 16.16 定点值 2；前段止于 `0x427816` 动画调用前 | 不能直接换算 120px/s 等实时速度；每秒回调频率、转向完整时钟仍未确认 |
| 配乐 | `0x42c1c0` 查询 signed-short 表 `0x477b44`；level49 返回 track6，参数 -1 读当前 level，level≥100 返回 -1 | track 编号不是现代音频文件名；本包没有改变配乐 |
| `Status_Bar` | 原 obj12 绑定状态栏回调；位置为 camera+(0,412)。`0x427200` 算“完成度”，`0x42d090` 将累计秒数写成 `h:mm:ss`。原 RESOURCE360 为“完成度：”；新增绘制前段实际生成“完成度： 42%”，停在首个文字 renderer `0x427309` | 它不是角色 HP／MP 条。完成度分母是命名点数减1，分子为 mode2 且非 Hidden 的点，结果最高100；精确成像、累计计时器每秒来源尚未执行 |

`Status_Bar` 的位置／百分比／时间 formatter 为完整 helper 返回；标签拼接是 bounded prefix，不把未执行的 renderer 说成绘制成功。

**路线进入 mode1 的写者（lane TOWNMAP，r2 反汇编，未执行）。** `0x426e40(point, 行走者)` 把点记录 `+0x18..+0x24` 的路线逐条交给普通 setter `0x426bb0(track, 1)`（Hidden 或已 mode2 不变），每成功一条行走者 `+0x88`（待揭示计数）加一，并记 `0x4c1abc`＝行走者（`0x4280d0` 完成时减它）。它只由行走者过程 `0x427420` 调用：

| 行走者子状态 `+0x8c` | 原实现 |
| --- | --- |
| 0 | 等 `0x460989()` 为 0；计数清零；显示请求 `0x4c1bb0` 为 0 时揭示当前点 `0x4c1ba4` 的路线；→ 1 |
| 1 | 计数 > 0 就等（揭示未完）。请求为点号（<100 且 `0x426ef0` 通过）：每 tick 调 `0x43bf30` 把镜头滚向该点，到位才揭示该点的路线、请求改 −1；请求为 −1：镜头滚回当前点，到位再揭示当前点、请求改 0；请求为 0：→ 2，并把点击目标 `0x4c1ab8` 置 −1（揭示期间的点击作废） |
| 2 | 当前点写入、若有 `0x4c1bb4`（走到某点的请求）就设为目标；→ 3 起行走 |

即：进图先揭示脚下各路线并等完，再处理 teBMSetShowTrackPoint 的点——镜头滚过去、揭示、等完、镜头滚回来——之后才接受点击。重制 `WorldMapRuntime` 照此排序（lane TOWNMAP：`_advance_show_sequence`，揭示期间丢弃点击）；镜头滑行步长按战斗的 32 取（大地图上 `0x43bf30` 是否走剧情步长 16 未读）。

## te 条件不是统一的“失败就终止”

opcode 按原 `TOWNDEF.H`；实现入口为 `0x454e20`。VM 返回值 0 为本次继续／等待，1 为结束当前事件，2 为交给子菜单；是否跳到另一事件必须看各分支对程序指针的实际改写。

| token | 已执行的语义与地址 |
| --- | --- |
| `teCheckMoney` 16 | `0x4555a5` 比较金币；足够时 `0x455627` **立即减去 cost**并继续。500 支付500变0。余额不足不扣款，进入提示；提示创建前止于 `0x4555f4`。另执行 `0x455eb6` 的完成阶段，等待标志未清不结束，完成后 phase清0、返回1，没有隐式跳转或退款。 |
| `teCheckPlayerExist` 18、`teCheckItemExist` 19 | 这版原 VM 对两枚 opcode 正常返回0，只前进 opcode 一个 DWORD，未检查对象，也不消费头文件所注释的参数；probe 使用跟随的999哨兵核对游标。不能按名称把它们实现成全局条件。它们与29的实质物品查询必须分开。 |
| `teCheckItemExecEvent` 29 | 原 `0x454cd0` 按两个共享物品库及当前队员八槽查询；找到时可按 delete 参数消费一份，再经 `0x44e0e0` 切到指定 event。未找到则继续原程序；event0也不自动终止。16例覆盖两个库／队员／缺失及消费／只查。 |
| `teCheckTEExist` 33 | `0x455db7` 调 `0x4546c0` 查 town／parent／child；找到且 event非0转指针，找到且 event0返回1，未找到继续。不是“未找到便终止”。 |
| `teCheckJobUp` 31、`teCheckJobUp2` 32 | 无合格角色的原前段进入100号失败提示阶段，止于 `0x455d39`；另执行提示结束后的阶段，fail event=-1结束，非负有效 event转指针，尚在等待不跳转。成功转职／选择角色／写回能力分支未执行。 |
| `teAppearSecretMan` 36 | 原完整 helper `0x454db0` 用全局缓存0／-1／正event分别表示未决／失败／已选。未决时仅在 `rand(100)+1 < threshold` 的严格比较成功才加入子项；相等失败并缓存-1。非0缓存不重新抽签；force可绕过。`0x479398` 的9个short为123,113,114,115,116,117,118,119,120，按当前索引选event，而非随机挑商品表。 |

本包的金额、指针、角色与阶段是显式夹具，不是实际城镇存档快照。原记录破损、负cost等未列输入不属于重制应接受的合同。

### 尚未确认／P-028 附加项

**negative-evidence（有范围）**：本次对 `0x454e20` 的 shop／delay 分派及已列 helper 的检查，没有取得买入／卖出 handler、入包选择以及消息输入时钟的完整执行回执。因此本包不支持把现有“按标价买、半价卖、指定角色首空格入包”升级为原版事实；其中买入价、卖出价 price×50÷100 与重要物品拒收（含消息 606／607）后来由 [原作商店交易](original_shop_transaction.md) 以静态阅读确认（static-derived，未执行），“指定角色首空格入包”仍是重制交互改写。`teCreateShop` 返回与实际成交是两层；`teDelay` 的逻辑计数也不能证明墙钟秒数。if_wait=0是否仍需实际输入、全转职成功链、secret阈值的所有设定入口及默认值继续未确认。替换这些边界需要对应 handler 的有界执行，或单步原运行路线；不需要为此阻塞本包已经完整回答的 P-027 项目。

## 复跑

```sh
python3 tools/hsl.py check world_town
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate world_town --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
```

原 PAK／EXE只读。`known_functions.json` 只挂已核对职责及 `confirmed_scope`；function_catalog 仍是候选目录，未调用 Jev 产生事实。
