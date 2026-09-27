# Original story corpus (all narrative scripts, resource-derived)

> evidence: resource-derived; provisional · status: record-only · tools: hsl_chapter_dialogue.py, hsl_resource_scanner.py, hsltools/data/story_corpus.py, test_hsl_story_corpus.py · updated: 2026-09-27

## 结论

- 原版 `hsl.pak` 的 284 个叙事脚本（152 STORY、130 winfail、STORYOVER、TOWNDEF）共 2793 次消息引用、1792 个不同消息 id，全部能在 RESOURCE.TXT `[name]` 表里解析；STORY 编号、流转边与 opcode 覆盖都可逐项数出（resource-derived）。
- 重制 `tools/hsltools/data/story_corpus.py` 把它们写成 `content/imported/hsl/story_corpus/`，与 16 份逐关对白证据逐字对比 0 差异（resource-derived）。
- 本包只恢复文本与动作顺序，不恢复时序、条件真值、镜头／走位目标或 handler 副作用；`???` 说话人标签是重制选择（provisional）。

## 证据

### resource-derived：范围

`resource-derived` text and script structure only. `tools/hsltools/data/story_corpus.py` reads every
narrative script of `hsl.pak` and the `[name]` section of `DATA\\RESOURCE.TXT`, and writes the message text and
the source order of the script actions. It restores **text and action order** — not timing, not the truth value of
`actCheck*` / `teCheck*` branch conditions, not camera / walk targets, not handler side effects. A file name or
number here is resource naming, not a statement that the engine reaches that level. Speaker names appear only where
[`tools/hsltools/levels/message_text.py`](../../../tools/hsltools/levels/message_text.py) (the former `hsl_chapter_dialogue`) already has a per-level `SPEAKER_IDS`
table (levels 1, 2, 3, 5, 6, 7, 8, 9, 10, 12, 51, 52, 53, 58, 60, 65) or the script names the resource id itself
(`actShapeMessage` / `teShapeMessage` `[shape][name id][message id]`); everywhere else the `SID_*` token is kept.
Labels for `???` actors inside those tables remain remake choices (`provisional`), exactly as the per-level evidence
files state.

Machine-readable output: `content/imported/hsl/story_corpus/index.json` (schema `hsl_story_corpus.v1`) and
`content/imported/hsl/story_corpus/scripts/<FAMILY><nnn>.json` (schema `hsl_story_corpus_script.v1`; 284 files,
about 4.5 MB in total). Every record carries the source member, `byte_length`, `sha256` and `evidence_tier`.

### resource-derived：计数（index.json summary）

| Family | Files | Sections (events) | Message references | Distinct message ids | Ids without text |
| --- | --- | --- | --- | --- | --- |
| `story` (`DATA\\STORYnnn.TXT`) | 152 | 152 `[story]` | 1310 | 822 | 0 |
| `winfail` (`DATA\\winfailnnn.txt`) | 130 | 585 `[win]`/`[fail]`/`[event]` | 970 | 557 | 0 |
| `storyover` (`DATA\\STORYOVER.TXT`) | 1 | 1 | 10 | 10 | 0 |
| `towndef` (`DATA\\TOWNDEF.TXT`) | 1 | 191 `[town_event]` + 62 `[item]` | 503 | 433 | 0 |
| **all** | 284 | — | 2793 | **1792** (union) | **0** |

Every referenced message id resolves in the 2570-entry `[name]` table. Of the 2793 references, 342 are `message =`
win-board labels, 12 are `defNoOne` narration, 281 name their speaker by resource id (`actShapeMessage` ×9,
`teShapeMessage` ×269, `teCheckMoney` ×2, `teSecretManBuyThing` ×1) and 638 carry a `speaker_name` from a
`SPEAKER_IDS` table; the remaining 2145 keep only their token. 54 distinct `SID_*` tokens occur; only the 9 party
tokens are defined in `EXTRAS.H` (`index.json` → `extras_sid_defines`), the `SID_PLAYERn` / `SID_ENEMYnnn` tokens are script-side
symbols whose definitions live outside this corpus.

Level flow: 159 `actSetNextPlayLevelEvent` / `teSetNextPlayLevelEvent` edges (116 return to the big map with
`gameBigMapLevel`): the 153 `act` edges (114 to the big map) equal the counts of `big_map_flow.json`, plus 6 `te` edges from TOWNDEF. They are listed per script in `index.json`; the derived conventions stay in
[`world_map_data.md`](../static_reverse/world_map_data.md#resource-derived大地图流转脚本惯例).

### resource-derived：STORY 编号

Present: 1–45 (35 files), 51–82 (31), 97–99 (3), 501–578 (78), 900–904 (5).
Gaps inside those blocks: **4, 11, 14, 16, 20, 23, 25, 27, 35, 42, 46–50, 54, 83–96**.
STORY files without a matching winfail (story-only by the seed convention): 8, 9, 55–58, 60–72, 74, 81, 82.
Every winfail has a STORY.

### resource-derived：对照开场编译器的 opcode 覆盖

All 152 STORY scripts and STORYOVER use only tokens that `ACTION_KIND` maps. The 18 tokens that stay unmapped
occur in winfail scripts only and are all condition tokens of the winfail interpreter (`actCheckPlayer` 129 scripts,
`actCheckEnemyTotalNumber` 103, `actCheckRoundNumber` 38, `actTRUE` 26, `actCheckPlayerHPLow` 15,
`actCheckEnemy` 14, `actCheckPlayerArrivePos` 14, `actCheckEnemyNumber` 12, `actCheckPlayerAttacked` 10,
`actCheckPlayerTotalNumber` 5, `actCheckAnyPlayerArrivePos` 2, `actCheckEventNotExist` 2, `actCheckRoundDisp` 2,
`actCheckNextSerialNumber`, `actCheckNotPlayerAttacker`, `actCheckPlayerArriveSysPos`,
`actCheckSerialPlayerAttacked`, `actFALSE` 1 each). `te*` tokens of TOWNDEF are the town interpreter's and are
not measured against `ACTION_KIND`. A mapped kind names the source intent only, not a proven handler.

### resource-derived：与逐关对白证据一致

`--check` and `tools/test_hsl_story_corpus.py` compare the corpus with every tracked
`content/imported/hsl/chapter01/message_text_evidence.json` (level 51) and
`content/imported/hsl/chapter01/battle*/message_text_evidence.json` (levels 1, 2, 3, 5, 6, 7, 8, 9, 10, 12, 52, 53,
58, 60, 65): 16 files, 371 shared message ids compared word for word, 71 speaker names compared, every id the
evidence lists in `script_message_sources` present in the level's STORY / WINFAIL corpus file — **0 differences**
(receipt: `STORY_CORPUS_CHECK_PASS ... evidence_files=16 compared_messages=371 compared_speakers=71`). Evidence
ids that are speaker-name lookups rather than script messages (for example 0, 305) are outside the corpus and are not
compared.

## 重制接线

### 重制：claim limits

`tools/hsltools/data/story_corpus.py` used to embed the four boundary sentences below as the constant `CLAIM_LIMITS`
and copy them into `index.json` → `claim_limits`. The text now lives only here; the code keeps the short id list
`CLAIM_LIMIT_IDS` (same order) and `index.json` records the ids plus this packet's path (`claim_limits_packet`).
**An id is a reference, not semantics**: the tier of each row is the evidence column.

| id | evidence | Boundary (original text) |
| --- | --- | --- |
| `text_and_action_order_only` | resource-derived | Only message text (RESOURCE.TXT [name]) and the source order of script actions are restored. |
| `tokens_not_engine_semantics` | resource-derived | Action timing, actCheck*/teCheck* branch conditions, camera targets and handler side effects are recorded as tokens only; no engine semantics are inferred. |
| `speaker_name_from_speaker_ids_tables` | resource-derived; provisional | speaker_name is filled only where tools/hsl_chapter_dialogue.SPEAKER_IDS has a level table (or a te/actShapeMessage names the resource id explicitly); other speakers keep their SID_ token. Labels for ??? actors in those tables are remake choices, provisional. |
| `numbers_are_resource_naming` | resource-derived | File names and numbers are resource naming; whether a STORY number is a level the engine can reach is not proven here. |

### 重制：解析链（不另写解析器）

| Step | Reused module |
| --- | --- |
| PAK member access | `tools/hsl_resource_scanner.py` (`find_decoded_paks_packages` / `find_paks_record_by_name` / `read_paks_record_bytes`) |
| STORY / WINFAIL / STORYOVER structure | `hsltools.sources.scripts.parse_text_metadata` → `hsltools.levels.seed._compact_script` (the same `sections[].actions[].chain[]` shape as the tracked battle seeds) |
| message ids | `hsltools.levels.message_text` (`MESSAGE_ACTIONS`, `ALTERNATE_MESSAGE_ACTIONS`, case-insensitive spelling such as `actMEssage`); the per-message walk is cross-checked against `seed_message_ids` on every script |
| message text | `hsltools.sources.tables.parse_table` (cp950, colour controls removed, `#` → line break) |
| speaker slots | `DATA\\EXTRAS.H` `SID_*` defines via `parse_text_metadata` (9 named party slots 0–8); per-level speaker names via `SPEAKER_IDS` |
| TOWNDEF | `tools/hsl_world_map.parse_towndef` with its `MESSAGE_ARG_POSITIONS` / `teSelectInsertEvent` / shape-name positions |
| level flow | `tools/hsl_big_map_flow.symbols` / `resolve` (`gameBigMapLevel` = 49 from the tracked `towndef.json`) |
| opcode coverage | `tools/hsl_opening_timeline_compile.ACTION_KIND` + `canonical_action_name` (imported, not copied) |

## 复现

`python3 tools/hsl.py check story_corpus`（内存重建逐字节比对；无 PAK 时做离线一致性）

## 边界

- Message box layout, playback timing, portrait binding, blocking behaviour and `actDelay` time scale.
- Which branch of `actMessageIfExist` / `teSelectInsertEvent` plays, and when `actCheck*` / `teCheck*` conditions hold.
- Camera and walk targets beyond the preserved argument lists; inserted-object lifetime.
- The meaning of `message = -1,<id>` versus `message = SID_x,<id>` board labels (`-1` is kept as written).
- `SID_PLAYERn` / `SID_ENEMYnnn` definitions (not in `EXTRAS.H`); the corpus records the token, not its slot.
