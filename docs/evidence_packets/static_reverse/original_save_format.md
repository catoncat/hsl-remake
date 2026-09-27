# Original Save Format (戰場記錄 HSLBAT.SAV / 回憶錄 HSLnn.SAV) and the 回憶錄 generator

> evidence: static-derived; runtime-measured: sample round trip, native codec equality, the PLAYERS template dump, the Wine loads of the generated 回憶錄 and the native second-tier 回憶錄 the generator reproduces table for table; provisional: replayed story flow, fixture levels / attributes · status: record-only · functions: 0x407ec0, 0x42c700, 0x42cc10, 0x42ccc0, 0x42ce10, 0x42da60, 0x42e040, 0x42e070, 0x42e640, 0x42ec10, 0x42f7a4, 0x434680, 0x4348f0, 0x448420, 0x448840, 0x44cb10, 0x450710, 0x4545c0, 0x454740, 0x4547a0, 0x454870, 0x4548b0, 0x45a7b0, 0x45b016, 0x45b089 · tools: hsl_original_control.py, hsl_win32_memread.c, hsltools/data/_original_save_codec.py, hsltools/data/original_save.py, hsltools/data/original_save_members.py · updated: 2026-09-27

## 结论

- Original: a save is twelve sections — a `0x68` header, slot codes, mode bytes, 201 live actor records of `0x1fc`, two item lists, encounter ratios, town trees, big-map points and tracks, a battle-only tail and a sliding-dword XOR checksum — each block compressed by a private LZW (`0x45b016`／`0x45b089`) (static-derived; runtime-measured: the tracked HSLBAT sample round-trips byte-exact and the original codec matches the Python one on 12 inputs).
- Remake tooling: `hsltools/data/_original_save_codec.py` reproduces the codec; `hsltools/data/original_save.py` generates 回憶錄 presets by replaying the story's table writes and synthesising members from the runtime PLAYERS template dump (`original_save_members.py`); the generated second-tier preset equals the native `HSL_second_tier_native.SAV` table for table (runtime-measured).
- Differences: preset levels, attributes and inventories are fixtures and the replayed flow covers only table writes (provisional); battle-tail semantics and why a direct battle-level header leaves enemies uninstalled are unread. The game itself does not read these files (tooling for original-side comparison).

## 证据

### File layout (static-derived: writer `0x42e070`, reader `0x42e640`, peek/load `0x42ec10`, checksum `0x42e040`; EXE sha256 `f0b5f835…`)

Every compressed block is `u32 length` followed by `length` bytes of the block codec; the reader passes a fixed expected size (`0x42e640`), so block sizes are part of the format.

| # | Section | Size (decoded) | Original owner | Notes |
| --- | --- | --- | --- | --- |
| 1 | header | `0x68` | the `0x42e070` field list (table below) | version word 100 |
| 2 | registered slot codes | raw `0x54` | `0x4c4360[21]` (i32) | 0 empty; `800 + slot` after `0x450710` registers a pmPlayer object; `0x4348f0` → `0x42c700(slot, up code)` replaces it by the consumed `obj_Player<N>Up<tier>` code (`818` / `819` after the second titles, native); bit 31 set = registered but disabled |
| 3 | player-mode bytes | raw 200 | `0x4c6d80[200]` | one byte per live actor index; the sample sets index 0 (雷歐納德) and 23/24 (two level-51 actors) |
| 4 | live actor records | `0x18edc` = 201 × `0x1fc` | `*0x4c1bc8` | registered slot `n` lives at index `n + 1`; `0x44cb10` installs battle actors from index 21 upward |
| 5, 6 | two item lists | `u32 capacity`, `u32 count`, then LZW(`capacity × 8`) | `*0x4c1d10`, `*0x4c1d1c` (`0x44f720` lists) | new game: capacity 5, count 0 |
| 7 | encounter ratios | 200 = u16[100] | `0x4c27e0` | per big-map point (`0x4545c0`, `BMSetPointEncounterRatio`); new game 10 |
| 8 | town menu trees | `0x6720` = 100 × `0x108` | `*0x4c1d74` | per town: the menu tree (`teAddTE`/`teDeleteTE`), u16 `+0x100` exec event (`0x454740`), u16 `+0x102` exit exec event (`0x454780`); see [original_world_town.md](original_world_town.md) |
| 9 | big-map points | 4000 = 100 × 40 | `0x4c4a20` | the `bigmap.dat` point table with live mode / flags / event words (`+0`, `+4`, `+8`) |
| 10 | big-map tracks | `0x640` = 100 × 16 | `0x4c43c0` | the `bigmap.dat` line table with live mode / flags |
| 11 | battle tail | variable | `0x4079f0` queue, `0x44e970` flag tables, per-object records | 戰場記錄 only; the codec keeps it verbatim (`battle_tail`) |
| 12 | checksum | `u32` | `0x42e040` | over every byte before it |

Header fields (store order is irrelevant, the offsets are the contract):

| Offset | Type | Name | Original global |
| --- | --- | --- | --- |
| `0x00` | u32 | version | constant 100 |
| `0x04`, `0x08` | i32 | camera x / y | `0x4c091c`, `0x4c0920` |
| `0x0c` | i32 | current big-map point | `0x4c1ba4` |
| `0x10` | i32 | next level | `0x4c1ba8` |
| `0x14` | i32 | walk-from point | `0x477c18` (−1 when standing) |
| `0x18` | i32 | level files id | `0x4c1bac` (49 on the big map) |
| `0x1c` | i32 | current level | `0x4c1bb8` |
| `0x20` | u32 | round counter | `0x4c1bbc` |
| `0x24`, `0x26` | i16 | show-track point, walk-to point | `0x4c1bb0`, `0x4c1bb4` |
| `0x28` | i32 | gold | `0x4c1bcc` |
| `0x2c` | i32 | level flag | `0x4c1ba0` (1 in the sample) |
| `0x30` | i32 | 雷歐納德's level (list row) | `record(slot 0) + 0x9c` |
| `0x34` | i32 | play seconds (list row clock) | `0x4c1bc0` |
| `0x38`, `0x3c` | u32 | RNG state (damage stream, see [damage random](original_damage_random.md)) | `0x4c3044`, `0x4c3040` |
| `0x40`, `0x42` | u16 | secret-man index / word | `0x4c1bd4`, `0x4c1bd0` |
| `0x44` | i32 | secret-man event | `0x4c1d70` |
| `0x48` | u32 | serial state | `0x4c1ad4` |
| `0x4c`..`0x58` | u32/i32 | over flag, three over scores | `0x4c1bd8`..`0x4c1be4` |
| `0x5c`, `0x5e` | i16 | sys arrive y / x | `0x4c296c`, `0x4c2968` |
| `0x60`, `0x64` | i32 | reserved (0 in the sample) | — |

The 讀取回憶錄 / 儲存回憶錄 list row is rendered from the header alone (`0x42ec10(slot, 0)` peeks the header and restores the globals): point name from `0x4c1ba4`, `等級` from `0x30`, the clock from `0x34`.

### Block codec `0x45b016` / `0x45b089` (static-derived; runtime-measured cross-check)

An LZW variant with 9..13-bit codes emitted LSB-first (`0x45a8bc`), escape code `0x100` followed by 1 (width grows) or 2 (dictionary prune), dictionary codes `0x101..0x1fff` kept as a first-child / next-sibling tree with a free list (`0x45a7b0` init, `0x45abd5` step, `0x45aad7` add, `0x45ab7e` lookup, `0x45aa43` / `0x45a925` prune), blocks shorter than 10 bytes stored verbatim, and the sliding-dword XOR checksum `0x42e040`. It is not a generic LZW; the sample round trip is byte-identical only because the tree order, free-list order, width growth and prune order match.

Native cross-check (unicorn on the mapped EXE): on 12 inputs — zeros, random bytes, a 26 400-byte periodic block, a 30 000-byte random block, a 102 108-byte skewed block, and the six blocks of a generated 回憶錄 — the original `0x45b016` produced exactly the Python encoder's bytes, and the original `0x45b089` decoded every Python-encoded block back to its input.

### Tracked native files (runtime-measured, written by the original v1.06 under Wine)

| File | What it is |
| --- | --- |
| [`HSLBAT_first_control.SAV`](original_save_format/HSLBAT_first_control.SAV) (6178 bytes, sha256 `97546502…`) ＋ [`.json`](original_save_format/HSLBAT_first_control.json) | 儲存戰場記錄 at 雷歐納德's first action menu of level 51: fresh new-game tables (`bigmap.dat` copied into the point / track tables, gold 1000, slot 0 = 800, encounter ratios 10) plus the level-51 placement; live records at index 1 (雷歐納德) and 21..31; both item lists capacity 5 / count 0; every point mode 0 except point 1 (mode 2); the `bmpmHidden` points are the ones the new-game reset hides; battle tail 2455 bytes. A second 戰場記錄 from the same route (untracked) also round-trips byte-exact |
| [`HSL_second_tier_native.SAV`](original_save_format/HSL_second_tier_native.SAV) ＋ [`.json`](original_save_format/HSL_second_tier_native.json) | the 回憶錄 the original wrote after running both second-tier job-ups from the generated `before_second_tier_at_temple` preset |
| [`PLAYERS_templates_runtime.bin`](original_save_format/PLAYERS_templates_runtime.bin) ＋ [`.json`](original_save_format/PLAYERS_templates_runtime.json) | the template table `*0x4c1afc` read from the running original on the big map (`hsl_win32_memread.exe --read-bytes templates=<*0x4c1afc>:0x18edc`): 66 of 201 slots non-zero, exactly the 66 PLAYERS.TXT rows at index = code; 66 × 508 bytes in code order, with sha256, codes, the handle rule and the name → handle map |

### Level-entry header (static-derived; runtime-measured)

A level that is not a big-map point (the 51 → 52 → 58 → 60 → 53 prologue chain) is reached only through `actSetNextPlayLevelEvent level,event` → `0x42cc10(level, event)`: `0x4c1ba8` (next level) = `level`, `0x4c1bac` (level files) = `event`, then the level-switch request. The main loop `0x42f7a4` sets `0x4c1ba4` (current point) to `walk_from_point`, or to `0x4c1bb8` (current level) when that is −1 (and to 1 when the result is 0), and calls the level runner `0x42da60(next_level)`, which stores `current_level = next_level` and loads WINFAIL / OBJ / ICO / WRD / BIN / STORY of `level_files` (`0x42ce10`). 讀取回憶錄 goes through the same runner: `0x42ccc0(slot)` records the pending slot in `0x4c1ae4` and requests the switch; `0x42da60` performs the load (`0x42ec10(slot, 1)`, which restores `0x4c1ba4` / `0x4c1ba8` / `0x4c1bac` / `0x4c1bb8` from the header), and the loop's next `0x42da60(next_level)` runs the saved level with the saved files — which is how the big-map presets (`level_files` 49) reach the map from inside the level-51 battle. `level_entry_header` therefore writes `next_level = level_files = current_level = entry_level`, `walk_from_point −1`, `walk_to_point 0`, `show_track_point 0`, camera 0 / 0 and `current_point 1`.

Wine load of `level53_pre_battle` (route in [battle_053](../runtime_observations/battle_053/README.md)): the row read 歐姆村 等級01 0:15; one click entered STORY058 with `0x4c1bb8 / 0x4c1ba8 / 0x4c1bac` = 58 / 58 / 58 and `0x4c1ba4` = 1, STORY058 → STORY060 → level 53 chained natively, and level 53 installed 緹娜 from the PLAYERS 002 row (L2 36/36 by the install-time level inference).

**A battle level cannot be entered this way (negative-evidence, runtime-measured).** A header with `next_level = level_files = current_level = 5` (呼嘯平原) loads STORY005 with the four registered party records exactly as written (001 L7 39/39 attack 82 defense 54 speed 19, 002 L4 38/38, 003 L6 42/42, 004 L7 50/50), but the nine EVEF enemies sit in live slots 21–29 with **uninstalled records** (code 0, L1, HP 1/1), and the first player 待機 fires WINFAIL005's `actCheckEnemyTotalNumber,0` win section (903 / 904) and returns to the big map. The same enemies install normally when level 5 is reached from the big map (codes 36 / 38, L4–L8, 52–94 HP). So `entry_level` only works when the entered level is story-only and the battle is reached by the native `actSetNextPlayLevelEvent` chain; to start a battle that is a big-map point, stand on the neighbouring point with the battle point unvisited.

### Wine loads of generated presets (runtime-measured, `tools/hsl_original_control.py` single-step, game-window sampling only)

- First single-slot form of `second_tier_at_amphibian_gate`: the row read point name / level / clock from the header; the big map appeared with the 兩棲族部落 background and exec event 153 ran at once (1735 with 雷歐納德's face, 1736 / 1737 without face or name because slots 1 / 2 were not registered); root menu 武器店 / 護甲店 / 道具店 / 集會場; 整理裝備 showed 雷歐納德 終焉劍使 with the exchanged record but the sample's level-1 derived layer (HP 30/30 — the original does not recompute it on load, which is why the generator refreshes it). The 回憶錄 the original wrote afterwards differed from the generated file only by `walk_to_point 14 → 0`, `show_track_point −1 → 0`, `camera_y 469 → 480`, the clock, town 14's exec event `153 → 0` (event 153 ends with `teSetExecEvent town_兩棲族部落 0`) and point 15 / track 14 mode `0 → 2`.
- Four presets as generated now: the list showed 兩棲族部落 等絁41 1:00 / 命運的神殿 等絁41 4:00 / 古代神殿遺跡 等絁36 8:00 / 命運的神殿 等絁41 4:14 from the headers. `second_tier_at_amphibian_gate`: event 153 plays 1736 as 緹娜's face message; 整理裝備 shows 雷歐納德 終焉劍使 Lv41 165/335 (力量 80 反應 62 精神 50 體質 60, 攻擊力 227 防禦力 150 移動力 7, 闇刃劍 / 鐵護額 / 騎士鎧甲 / 皮靴) and 緹娜 聖主 Lv40 154/284 MP 116/276. `before_second_tier_at_temple`: entered 命運神殿; the five members with first titles — 雷歐納德 劍豪 41, 緹娜 神官 40, 琥 神射手 35, 漢克斯 暗殺者 35, 雪拉 精靈使 33. `level37_pre_jobup`: stood on 古代神殿遺跡 (完成度 70%) with all nine members (雷歐納德 劍豪 36 … 克羅蒂 魔劍士 32); the level-37 install from these records was not observed. `after_second_tier_at_temple`: 神殿中樞 → 祈求 → event-87 member menu held only 離開 — the same post-state the original showed after the native job-ups.
- `level17_pre_battle`: the row read 席達鎮 等級01 2:00; 完成度 31% with 艾瓦台地 an unvisited point one track north; clicking it walked the party there and ran the level-17 opening (24 live records at first control). A form standing **on** point 17 loaded onto the point but clicking did nothing — a load parks the walker without arriving, and the `0x427ab3` arrival runs a General point's event only while its `bmpmVisit` is clear (static-derived). Battle in [original_level17_escort](../runtime_observations/original_level17_escort/README.md). `level02_pre_battle` has not been loaded in Wine.

### The native second-tier 回憶錄 and the byte-level readings it fixed (runtime-measured; static-derived)

With `before_second_tier_at_temple` loaded, 神殿中樞 → 祈求 opened event 87's member menu; 雷歐納德 → 1349 → 69 → `teCheckJobUp2` succeeded (「雷歐納德的稱號由劍豪變成終焉劍使」, 79's 命運神殿 writes ran), then 緹娜 → 70 → 「緹娜的稱號由神官變成聖主」; 儲存回憶錄 wrote `HSL03.SAV` = the tracked `HSL_second_tier_native.SAV`. Its diff against the loaded file: slot codes 800 / 801 → 818 / 819, the two records, town 16 (79's tree writes), town 14 (the `0x434680` list, byte-equal to `content/world/town_job_up_writes.json`), and the standing header words. Three readings follow:

1. `0x4348f0` adds `+0x194..+0x1a0` as **16-bit words** (`cx`/`dx` word adds, static-derived), not dwords; the high halves are `0x448840` work values (`+0x196` = the low word, or 12 when it is 0) and are not summed (a dword sum doubles the work half, `0xc0000 + 0xc0000 = 0x180000`, still visible in the native file's untouched slots 2–4). Switching back to dword adds leaves `native_second_tier` green because the refresh overwrites the only differing half — this row rests on the listing, not on the native bytes.
2. `0x448840` clears `+0x18c` and rebuilds it from the equipment: each non-zero slot's item flag word goes through `0x448420`, whose `+0xa0`-class bits map to `0x40 → 0x800000`, `0x200 → 0x8000`, `0x400 → 0x1000`, `0x800 → 0x4000000`, `0x1000 → 0x1000000`, `0x2000 → 0x2000000`, `0x4000 → 0x40`; a record with no magic ORs `0x4000`. The item flag word uses the bits `equipment.py` names plus three the 66 templates pin (`action_twice 0x8`, `double_attack 0x8000`, `mp_auto_restore 0x200`); an item declaring any other boolean without an evidenced bit makes synthesis fail.
3. `0x4348f0` ends with `0x42c700(slot, up code)`: the registered slot code becomes the consumed `obj_Player<N>Up<tier>` object (818 / 819 observed; 809–817 for the first tiers follow from the same call, static-derived).

`synthesize('001', ['010', '019'])` and `synthesize('002', ['011', '020'])` equal the native records byte for byte; dropping the `+0x18c` rebuild fails both `original_save:members` (template 001 at `0x18d`) and `native_second_tier` (slot 0 at `0x18c`).

### Live actor records and the PLAYERS template dump (static-derived; runtime-measured)

The original never builds a live record from PLAYERS.TXT at install time: the parser fills a **template table** `*0x4c1afc` (201 × `0x1fc`, index = PLAYERS code) once at start-up, `0x44cb10(index, 1)` copies template → live for the same index ([original_priest.md](original_priest.md), [original_campaign_actors.md](original_campaign_actors.md)), and the constructor `0x407ec0` writes its install-time words and calls the refresh `0x448840`. A registered party slot `n` is live index `n + 1`, i.e. PLAYERS row `n + 1` (`0x407eff`). The live table dumped alongside the templates had only index 1 filled although slots 0–4 were registered: registration (`0x42cb30`) writes the slot code only, the record is filled at the next battle install — so an all-zero record of a registered slot shows as an empty `等級0` member.

`original_save:members` proves from tracked data only:

- template `001` differs from 雷歐納德's live record in the HSLBAT sample by **one dword**: `+0x14` = `304 << 16` (the install-time dead-message word `0x407ec0` writes for a player; RESOURCE 304 is the generic dying line). Level actors additionally carry `+0x84` = their code and the level's own item / mode writes; the templates have `+0x84` = 0 and `+0x134` = 0.
- every template field the generator relies on equals its PLAYERS.TXT column (code, name id, job, job_show_name, class, mode, size_type / carry_item, job_up_code object, the four attributes twice, level, exp, kill_exp, gold, stamina, six equipment words, five base resists, move, eight items) — 52 fields × 66 rows;
- the derived layer of every template (caps `+0x74..`, max HP / MP, attack, defense, speed, hit ratio, magic attack, move work, five working resists, exp threshold and the three `+0x19a/+0x19e/+0x1a2` work halves) is re-derived **byte for byte** by `hsltools.model.jobs.calculate` from the record's own job, mode, base attributes, equipment, base resists and additive layer (`+0x1a4..+0x1b0` dwords, the signed `+0x1b4`/`+0x1b6` MP / HP pair — PLAYERS 066 declares `hit_point -10000` — and `has_magic` = any of the six magic words `+0x174..+0x188`);
- the eight resource-handle words match the rule below for all 66 rows;
- `synthesize('001')` (template copy + `+0x14`) equals 雷歐納德's live record in the HSLBAT sample byte for byte.

Resource-handle words (static-derived rule, verified on the dump) are PAK directory positions from the sorted archive directory — not RESOURCE.TXT ids and not raw PAK record indexes:

| record word | half | PLAYERS.TXT column | value |
| --- | --- | --- | --- |
| `+0x08` | lo / hi | `sound_walk` / `sound_dead` | WAV handle |
| `+0x0c` | lo / hi | `sound_miss` / `sound_attack` | WAV handle |
| `+0x10` | lo / hi | `sound_hit` / `sound_walkwater` | WAV handle |
| `+0x20` | lo / **hi** | class (`+0x20`, TYPE.H `classHuman` 101 …) / `sound_shoothit` (`+0x22`) | class word / WAV handle |
| `+0x5c` | u32 | `picture` | shape handle |

WAV handle = `1 + index` of the name in the case-insensitive sort of the 220 `@:\wav\` PAK names (0 = column absent): `Attack01.WAV` → 5, `Attack05.wav` → 7, `Dead0003.wav` → 54, `Miss0001.wav` → 136, `Walk0011.wav` → 187, `Walk0012.wav` → 188, `FLY003.WAV` → 89, `BOMB0028.WAV` → 44. Shape handle = index of the name in the case-insensitive sort of all 4519 `*.shp` PAK names: `face0000.shp` → `0x1075`, `face0001.shp` → `0x1076`, `FACE0020.shp` → `0x1089`, `face0021.shp` → `0x108a`. `+0x14` is the `dead_message` pair (`hi` = first id, `lo` = second) for rows that declare it, else 0 in the template and the install word for players.

## 重制接线

This packet feeds development tooling, not the game runtime (hence `record-only`); consumers name it in their module docstrings: `tools/hsltools/data/original_save.py`, `tools/hsltools/data/_original_save_codec.py`, `tools/hsl_original_probe_units.py`, `tools/hsltools/probes/enemy_turn.py` (reads `HSLBAT_first_control.SAV`).

- **Codec**: `_original_save_codec.py` reproduces the compressor instruction for instruction.
- **Generator**: `python3 tools/hsl.py generate 'original_save:*'` (or `python3 -m hsltools.data.original_save --state <preset> --out DIR`) starts from the tracked sample, drops its registration, live records and mode bytes, replays the story's script writes in order through the same table helpers the original VM calls (`BMSetPointFlag`/`Mode`/`Event`, `SetBMWalkToPoint`, `teAddTE`/`teDeleteTE`, `teSetTownExecEvent` — WINFAIL win sections and TOWNDEF events named per preset), marks the travelled points shown (mode 2 + `bmpmVisit`; tracks whose both ends are travelled follow from `world_map.json`; points a replayed write left hidden are skipped and listed in the receipt), synthesises every party member from the template dump, writes the big-map header for standing at `point` (`walk_to_point = point`, so a load arrives at the point: a town opens, a general point runs its event) and emits `content/generated/hsl/development/original_saves/<preset>.SAV` with a receipt JSON (applied flow, skipped non-write tokens, per-member record summary incl. `job_up_ready` = the `0x434770` attribute test, town trees, point words, header). Install as `<hsl>/SAVES/HSL00.SAV`; the list shows it as the first row.
- **Member synthesis** (`original_save_members.py`): template copy → `+0x14` player word → spec `level` / `exp` / `attributes` (both the working `+0x4c..` and base `+0x64..` rows) / `inventory` (eight slots) / `equipment` → `0x448840` refresh with HP / MP at maximum (including the `+0x18c` rebuild) → one `0x4348f0` exchange per `job_up_history` entry (first tier `0x80000000`, second `0x40000000`; each admitted only while `record+0x60` names the matching `obj_Player<N>Up<tier>` object of OBJ-ALL.H; the consumed up code goes into the slot code as `0x42c700` does) → refresh again. The exchange follows [original_town_job_up.md](original_town_job_up.md) with the **target template** as source, so 緹娜's second title carries `FACE0020`'s handle `0x1089` and 017's own sounds. Party entries use the remake's carry vocabulary (`actor_id`, `level`, `exp`, `attributes`, `inventory`, `equipment`, `job_up_history`); the registered slot is `code − 1`. The generator copies handle words from the dump; the PAK is read only when the dump is rebuilt (`HSL_ORIGINAL_MEMORY_DUMP=<json> hsl generate original_save:members`).
- **Town job-up writes**: `content/world/town_job_up_writes.json` is read directly (`hsl check town_job_up_writes` validates its TOWNDEF references).

| preset | state | party (slot: row, level, titles) | `ORIGINAL_SAVE_PRESET_PASS` |
| --- | --- | --- | --- |
| `second_tier_at_amphibian_gate` | after both second titles: chapter-1 writes, temple writes (TOWNDEF 32 / 51 / 53 / 60 / 79), 兩棲族部落 141 / 151 and the `0x434680` writes pre-applied; standing at point 14 | 0: 001→010→019 Lv41 · 1: 002→011→020 Lv40 | `point=14 slots=0,1 flow=22` |
| `before_second_tier_at_temple` | one step before: first titles, base attributes exactly at cap − 50, 劍之魂 283 / 福音之書 284 in the two members' slots, 神殿中樞 76 → {77, 78} open (TOWNDEF 32 / 51 / 53 / 60), town 14 still at its chapter-1 tree; standing at point 16 | 0: 001→010 Lv41 · 1: 002→011 Lv40 · 2: 003→012 Lv35 · 3: 004→013 Lv35 · 4: 005→014 Lv33 | `point=16 slots=0,1,2,3,4 flow=18` |
| `after_second_tier_at_temple` | the previous preset after both `teCheckJobUp2` successes: TOWNDEF 79 on town 16 (80's writes never run — its `teCheckTEExist 76/81` finds 81 and branches to 87), the `0x434680` writes, 283 / 284 consumed, slot codes 818 / 819; standing at point 16. Every table but the standing header words equals the native `HSL_second_tier_native.SAV` | 0: 001→010→019 Lv41 · 1: 002→011→020 Lv40 · 2–4 as before | `point=16 slots=0,1,2,3,4 flow=20` |
| `level37_pre_jobup` | before 古代神殿遺跡: main-path WINFAIL win writes through 36 (no chapter 2–3 town events); standing at point 37 so the load starts level 37 | 0–6: 001–007 with first titles Lv33–36 · 7: 008 咕嚕 base Lv32 · 8: 009 base Lv32 | `point=37 slots=0,1,…,8 flow=30` |
| `level53_pre_battle` | after the prologue battles 51 / 52 (their win sections write no saved table), the header holds what WINFAIL052's `actSetNextPlayLevelEvent 58,58` leaves (`next_level = level_files = current_level = 58`), so the load runs STORY058 → STORY060 → level 53 逃出克萊恩城; only slot 0 is registered and every other record is zero, so `obj_Story_Player2` installs 緹娜 from her PLAYERS 002 template (see [battle_053](../runtime_observations/battle_053/README.md)) | 0: 001 (PLAYERS row as-is; absent from 53) | `entry_level=58 slots=0 flow=2` |
| `level05_pre_battle` | before 呼嘯平原: WINFAIL001 / 002 / 003 win writes; standing at 自由都市 米蘭多 (point 4, the town menu opens on load) with point 5 (bmpmBattle, event 5) shown but unvisited, so one click on the orange marker walks track 4 and runs level 5 natively (STORY005, 3 dialogue lines, then the objective card); not an `entry_level` preset (see [battle_005](../runtime_observations/battle_005/README.md)) | 0: 001 L7 · 1: 002 L4 · 2: 003 L6 · 3: 004 L7 (levels, exp, base attributes, equipment and items copied from the remake chapter autoplay's seed-1 hand-off into level 5; 緹娜's spell bits stay the template's) | `point=4 slots=0,1,2,3 flow=3` |
| `level06_pre_battle` | before 席達鎮 (level 6): WINFAIL001 / 002 / 003 / 005 win writes (005 arms 席達鎮 exec event 19); standing in 席達鎮 (point 6) with the initial tavern sub-menu 20 → {21, 22, 23}, so 酒館 → 沃斯菲塔士兵 (TOWNDEF 23, `teSetNextPlayLevelEvent 6,6`) runs STORY006 and level 6 natively (see [battle_006](../runtime_observations/battle_006/README.md)) | 0: 001 L8 · 1: 002 L5 (水剎) · 2: 003 L7 · 3: 004 L8 (逆刃) (copied from the remake playtest kit's level-6 entry `memoir_05`; 5 unspent points of 001 / 002 spent on the main attribute because the install re-infers the level from the base attributes; learned skills OR-ed into `+0x174` / `+0x158` as word[type] bit (code − 1)) | `point=6 slots=0,1,2,3 flow=4` |
| `level02_pre_battle` | before 戈爾山道: WINFAIL001 win (歐姆村 exec event 9); standing in 歐姆村 (point 1) with point 2 shown but unvisited, so walking to it runs its event and starts level 2 (緹娜 joins inside it) | 0: 001 · 2: 003 (PLAYERS rows as-is) | `point=1 slots=0,2 flow=1` |
| `level17_pre_battle` | before 艾瓦台地 (escort of 064 / 062): main-path WINFAIL win writes through 15; standing in 席達鎮 (point 6) with point 17 shown but unvisited | 0–4: 001–005 (PLAYERS rows as-is: template levels Lv1/2/4/7/6; see [original_level17_escort](../runtime_observations/original_level17_escort/README.md)) | `point=6 slots=0,1,2,3,4 flow=15` |

provisional: levels, attributes and inventories are fixtures chosen so the `0x434770` test holds exactly where the preset claims it; the replayed flow covers only tokens that write saved tables (`actSetNextPlayLevelEvent` and presentation tokens are listed as skipped); the `+0x14` word of members other than 雷歐納德 is set to his observed value (`0x407ec0` rewrites it at the next install); the two shared item lists stay at capacity 5 / count 0 (story items sit in a member's eight slots, which `teCheckItemExecEvent` `0x454cd0` also searches).

## 复现

`python3 tools/hsl.py check original_save:sample original_save:members original_save:native_second_tier`（`ORIGINAL_SAVE_CHECK_PASS`；`ORIGINAL_SAVE_MEMBERS_PASS templates=66 fields=3432 handles=87 synthesized_001=sample`；`ORIGINAL_SAVE_NATIVE_SECOND_TIER_PASS bytes=3211 preset=after_second_tier_at_temple slots=818,819 tables=5`）. The Wine loads and the memory dump are 不可再生：原版侧唯一记录 beyond the tracked files.

## 边界

- The semantics of every live actor record field beyond what the generator writes and verifies, the battle-only tail sections, and the `0x4c1ba0`/`0x4c1ad4` header words beyond what the sample shows are not claimed.
- `native_second_tier` compares the header minus `camera_y` / `show_track_point` / `walk_to_point` / `play_seconds`, slots 0 / 1's codes and records, every other record, and the mode / ratio / town / point / track tables; slots 2–4 are skipped (the native file carries the before-preset's input there), so `811`–`813` and the word-add width rest on the static reading.
- The original parks the walker on save (`walk_to_point 16 → 0`, `show_track_point −1 → 0`, `camera_y 289 → 337`); the generator keeps `walk_to_point = point` so a load arrives at the point.
- Whether the original ever writes a level-entry header itself is not derived (a 回憶錄 can only be saved on the big map or in a town).
- Why the post-load level run skips enemy installation is not traced (`0x42ec10(slot, 1)` → `0x42da60` path).
