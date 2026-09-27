# 随机位置 winfail 动作：槽位表、洗牌与 107／108／117／121

> evidence: static-derived: opcode arguments, dispatch locations, slot table and random insert, the 107／108／117／121 handlers (which of them draw, and from which stream); provisional: the shuffle rolls' place in the global sequence (they draw 0x458c10 on the global stream, but the global draws before them are not yet the original's), whatever 0x45e307 draws inside itself; runtime-measured: LEVEL037 进关后的洗牌结果（模拟器整镜像，单样本） · status: live · functions: 0x450840, 0x450f2c, 0x450f99, 0x451d0f, 0x451db7, 0x451e64, 0x458c10, 0x458c80 · tools: run_battle_scene_runtime_tests.gd · updated: 2026-09-28

## 结论

- 原版 `actSetRandomPos` 最多存五组像素点并做一次部分洗牌（每槽一次 `0x458c10() & 1`），107／108 把对象放在槽位＋位移处不抽随机，117 把槽 0 设为某对象位置，121 每个对象在全局流上抽 3 次（static-derived）。
- 重制 `BattleLoopInit._load_opening_story_state` 在 PlayLoop 创建时于全局流 `global_rng` 上跑同一洗牌，并把绑定到槽 k 的单位移到洗牌后的位置；开场表现读同一顺序（static-derived 输入）。
- 原版古代神殿遺跡 · 守護者之戰（LEVEL037）进关后五个守卫对按插入序落在表项 2、3、0、1、4（第 1、2 对落在 (8,14)／(20,14)），与重制同一遍历在掷骰 1、1、0、0、0 下的结果相同（runtime-measured，单样本）。
- 洗牌随机源与原版相同：都是全局流 `0x458c10`（重制 `global_rng`），不是伤害流；随机位置插入 `0x450f55` 构造后不经 `0x44fbd0` 落点替代，重制同样保留请求格（static-derived，见 [original_script_entry](original_script_entry.md)）。
- 差异：洗牌抽取在全局序列中的位置、`0x45e307` 内部的抽取未对齐（provisional）。

## 证据

### resource-derived

```c
#define actCheckRoundDisp			94	// [number]
#define actSetRandomPos				106	// [num][x1][y1][x2][y2][....]
#define actInsertObjectRandomPos	107	// [code][disp x][disp y][pos id]
#define actInsertStoryObjectRandomPos	108	// [code][disp x][disp y][pos id]
#define actDeleteRandomPosObject	112	// [id][range][proc code]
#define actSetPlayerPosToRandom0	117 // [player id][serial]
#define actInsertRandomObject		121	// same as effInsertRandomObject
#define actSetDoublePageMode		122 // [mode]
#define actInsertLevelUpStar		123	// [sound id]
#define actDetectRoundDispDisp		124	// [num]
```

分派：0x6a（107）、0x6b（108）、0x70（112）、0x75（117）、0x79（121）；0x7a actSetDoublePageMode、0x7b actInsertLevelUpStar、0x5e／0x7c 回合显示检查（见 [original_round_display](original_round_display.md)）。

### static-derived（动作表 `[opcode*4 + 0x4537f4]`）

槽位表 `0x4c28e0`：第 i 项 y 字在 `+4i`、x 字在 `+4i+2`，均为像素。

| token | 入口 | 原版 |
| --- | --- | --- |
| `actSetRandomPos` 106 | `0x451d0f` | 最多存五对；然后 `i = 0..n-1`，`0x458c10() & 1` 为真时交换槽 i 与槽 i+2（越界减 5；`0x451d5f..0x451da3`）；全偶时即表序 |
| `actInsertObjectRandomPos` 107 | `0x450f2c` | `0x407ec0(x + dx, y + dy, code)`，返回对象存 `0x4c1d38`；不抽随机、无候选搜索；敌方构造器把对象居中到该像素所在格 `(v & ~31) + 16`（[actor_placement_initialization](actor_placement_initialization.md)） |
| `actInsertStoryObjectRandomPos` 108 | `0x451e64` | `0x45e307(x + dx, y + dy, code, 0)`（通用对象构造器，关卡加载普通对象分支 `0x46be17` 也调它）；handler 不抽随机 |
| `actSetPlayerPosToRandom0` 117 | `0x451db7` | 先把槽 0 整字清零，再 `0x44fad0(player id, serial)`；找不到时槽 0 保持 (0,0)，否则 x 字 = `[obj+4]`、y 字 = `[obj+8]`（`0x451de4..0x451df7`）；不抽随机 |
| `actInsertRandomObject` 121 | `0x450f99` | `[code][slot][w][h][delay][count]`，锚点为槽 `[slot]`；累计延迟从 0 起重复 count 次：`v = rand(w ? w : 1)`（`0x450fe6`），`v > n/2` 时 `v = n/2 − v`，加到 x；同法 `rand(h ? h : 1)`（`0x451012`）加到 y；`0x45e307(x, y, code, 0)`，返回对象写 `+0xae` = 累计延迟、`+0xa4` = 脚本对象 `+0x9c`、`+0xa8 = +0xaa = 20000`；`rand(delay)`（`0x451075`）加到累计值（无对象返回也抽，`rand(0)` 返回 0 不推进） |

所有抽取经 `0x458c80` 走全局流 `0x458c10`（字 `0x4795d4／0x4795d8`），不是伤害流 `0x42c780`；一次 w、h、delay 均非零的 121 抽 3 × count 个全局值。

## 重制接线

- STORY037 开场：`tools/hsltools/levels/story_scene.py` 把五个有生成模板的 `actInsertObjectRandomPos`（宝石 067、守卫 066）按表序解析并按插入序绑定（`<symbol>/insertN`、`SID_ENEMY06x/N`），serial N 即槽 N-1。
- 洗牌：`BattleLoopInit._load_opening_story_state` 在 PlayLoop 创建时跑一次 `0x451d0f` 的遍历，每次抽 `global_rng`（`GlobalRandomStream`）的一个 `0x458c10() & 1`，先于开场出生；产品从时钟播种，无头运行用 `HSL_RNG_SEED`；顺序随 loop 存档（`opening_story_state.random_slot_order`）；绑定到槽 k 的单位移到洗牌后的位置加插入位移（宝石在守卫下方 32 px），连同 AI home。
- 开场表现 `OpeningStoryObjects._set_random_slots` 读同一顺序；`opening_story_state.object_deletes` 列出开场删除的站立物件（37 的五座雕像、59、77 的），`BattleSceneRuntime.apply_opening_object_deletes` 在每次首次控制入口与存档恢复时隐藏它们。

## 复现

`tools/godot.sh --headless --script res://tests/run_battle_scene_runtime_tests.gd`

## 边界

- 洗牌抽取在全局序列中的位置：之前的全局抽取尚未与原版一致（provisional）。
- `0x45e307` 内部是否抽随机本包未读。
- STORY010 的树不在 `object_deletes` 里：之后同锚点的 `actInsertStoryObject` 取代它，而没有开场时剧情对象不会重建。
