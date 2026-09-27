# Random-position winfail actions

> evidence: static-derived: opcode arguments, dispatch locations, slot table and random insert, the 107／108／117／121 handlers (which of them draw, and from which stream); provisional: the shuffle rolls' place in the global sequence (they draw 0x458c10 on the global stream, but the global draws before them are not yet the original's), whatever 0x45e307 draws inside itself · status: live · functions: 0x450840, 0x450f2c, 0x450f99, 0x451d0f, 0x451db7, 0x451e64, 0x458c10, 0x458c80 · tools: run_battle_scene_runtime_tests.gd · updated: 2026-09-29

## Token table

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

The dispatch table assigns the random-position family to cases 0x6a (actInsertObjectRandomPos), 0x6b (actInsertStoryObjectRandomPos), 0x70 (actDeleteRandomPosObject), 0x75 (actSetPlayerPosToRandom0), and 0x79 (actInsertRandomObject); 0x7a is actSetDoublePageMode, 0x7b is actInsertLevelUpStar, and 0x5e/0x7c are the round-display checks. The bounded reading of hsl01.exe 0x450840 shows the random insert actions consume the compiled [code, disp_x, disp_y, pos_id] shape, deletion consumes [id, range, proc_code], player relocation consumes [player_id, serial], and random effects use the effect object's range arguments.

## What 107／108／117／121 do (lane RNGC, static-derived)

Read from `hsl01.exe` (the case bodies the action table `[opcode*4 + 0x4537f4]` reaches). The slot table is `0x4c28e0`: entry i is the y word at `+4i` and the x word at `+4i+2`, both pixel coordinates.

- `actSetPlayerPosToRandom0` 117 (`0x451db7`): `[player id][serial]`. It first zeroes the whole of slot 0 (dword `0x4c28e0 = 0`), then looks the object up with `0x44fad0(player id, serial)`. If there is no such object (−1) slot 0 stays (0, 0). Otherwise slot 0 becomes the object's pixel position: x word = `[obj+4]`, y word = `[obj+8]` (`0x451de4..0x451df7`). No draw.
- `actInsertObjectRandomPos` 107 (`0x450f2c`): `[code][dx][dy][slot]` → `0x407ec0(x + dx, y + dy, code)`, where x and y are that slot's words. It stores the returned object in `0x4c1d38`. It draws nothing and has no candidate search: the object goes exactly at slot + displacement, and the enemy constructor centres it in that pixel's cell ([actor placement](actor_placement_initialization.md)).
- `actInsertStoryObjectRandomPos` 108 (`0x451e64`): the same four arguments → `0x45e307(x + dx, y + dy, code, 0)`, the general object constructor (the level loader's normal-object branch `0x46be17` also calls it). No draw in the handler.
- `actInsertRandomObject` 121 (`0x450f99`): `[code][slot][w][h][delay][count]`, with the anchor being slot `[slot]`'s x and y. Starting from an accumulated delay of 0, it repeats `count` times:
  - `v = rand(w ? w : 1)` at `0x450fe6`, folded: if `v > n/2` (signed, truncating), then `v = n/2 − v`, so the offsets run from −(n−1−n/2) to n/2. The result is added to x.
  - The same with `rand(h ? h : 1)` at `0x451012`, added to y.
  - `0x45e307(x, y, code, 0)`. If an object comes back, it gets `+0xae =` the accumulated delay, `+0xa4 =` the script object's `+0x9c`, and `+0xa8 = +0xaa = 20000`.
  - `rand(delay)` at `0x451075`, added to the accumulator. This draw happens even when no object came back, and `rand(0)` returns 0 without advancing.

  Every draw goes through `0x458c80` on the global stream `0x458c10` (words `0x4795d4／0x4795d8`), not the damage-stream swap `0x42c780`. So one 121 with non-zero w, h and delay draws 3 × count global values.

## Slot table and random insert (R6-L10)

`static-derived` from `hsl01.exe`: the action table `[opcode*4 + 0x4537f4]` sends 106 to `0x451d0f` and 107 to `0x450f2c`.

- `actSetRandomPos` (`0x451d0f`): keeps at most five pairs; each pair is stored at `0x4c28e0 + 4i` as (y at `+0`, x at `+2`). It then walks `i = 0..n-1` and, whenever `0x458c10() & 1`, swaps slot `i` with slot `i+2` (wrapping by subtracting 5). So the slot order is a partial shuffle of the table; the all-even outcome is the table order itself.
- `actInsertObjectRandomPos` (`0x450f2c`): `[code][dx][dy][slot]` → `0x407ec0(x + dx, y + dy, code)`; the enemy constructor then centres the object in the cell holding that pixel (`(v & ~31) + 16`, [actor placement](actor_placement_initialization.md)).

Remake (STORY037's opening): `hsltools/levels/story_scene.py` resolves the five `actInsertObjectRandomPos` of objects with a generated actor template (the gems 067 and guardians 066) against the table order and binds them by insert order (`<symbol>/insertN` and `SID_ENEMY06x/N`), so serial N is slot N-1 in the generated scenario.

Shuffle (lane R6-L11): `BattleLoopInit._load_opening_story_state` runs the `0x451d0f` walk once per battle when the PlayLoop is created — for `i = 0..n-1`, an odd roll swaps slot `i` with slot `i+2` (minus 5 past the end; `r2 pd` at `0x451d5f..0x451da3`) — and moves every unit bound to slot k to the shuffled entry plus its insert displacement (the gem 32 px below its guardian), with its AI home. Each roll is one raw `0x458c10() & 1` on the loop's global stream `global_rng` (`GlobalRandomStream`, the original's words `0x4795d4`／`0x4795d8`; lane RNG-A 2026-09-25 replaced the remake-invented local Park-Miller stream), drawn before the opening's births; the product seeds that stream from the clock and a headless run from `HSL_RNG_SEED`, so a fixed seed (autoplay, tests) keeps its layout; the order is saved with the loop (`opening_story_state.random_slot_order`). The opening presentation reads the same order (`OpeningStoryObjects._set_random_slots`), so the camera, 白光, statue delete and guardian reveal of slot k happen where the PlayLoop placed its pair. The same state lists the stand objects the opening removes (`object_deletes`: 37's five statues, 59's and 77's); `BattleSceneRuntime.apply_opening_object_deletes` hides them at every first-control entry and checkpoint restore, so the dev harness and a restored battle no longer draw a statue over a guardian. STORY010's tree is left out: a later `actInsertStoryObject` at the same anchor replaces it, and story objects are not re-created without the opening (remaining boundary).

actCheckRoundDisp, actDetectRoundDispDisp, and actInsertLevelUpStar remain outside this slice and remain unsupported for battle 028; lane M owns them.
