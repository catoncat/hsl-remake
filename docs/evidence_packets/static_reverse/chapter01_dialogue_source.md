# Chapter 01 dialogue source

> evidence: resource-derived; static-derived · status: record-only · functions: 0x447620, 0x447720, 0x4477b0 · tools: hsl_chapter_dialogue.py, hsltools/levels/message_text.py · updated: 2026-09-27

Original `hsl.pak` member `@:\DATA\RESOURCE.TXT` is a cp950 `[name]` table containing resource paths, names and dialogue. `item = id,text` splits on the first comma. `@0` through `@9` are color controls; `#` is a line break. Imported source bytes and SHA-256 are retained in the chapter message manifest. Reproduce the chapter-wide manifest with `PYTHONPATH=. python3 tools/hsl_chapter_dialogue.py --pak <hsl.pak> --chapter` (check `python3 tools/hsl.py check message_text_evidence_check:chapter01`); a level's own manifest with `--level N` (check `message_text_evidence_check:N`, level 51 included).

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

- `0x42f3b9` references `DATA\RESOURCE.TXT`; `0x42f3c4` calls loader `0x447720`.
- `0x447778` passes section `name` to `0x447620`.
- `0x447680..0x447687` splits each entry at comma, parses its numeric ID; `0x4476bb` stores the text pointer at table + ID * 4.
- `0x4477b0` retrieves the indexed text through global `0x4c1b3c`.

STORY051's seven dialogue events use IDs 363, 364, 365, 366, 367, 364, 1101. Death / retreat lines are also imported for later event integration. Text source resolution does not claim original font, message-box layout or handler timing. Current readable layout and automatic preparation are remake presentation choices.

STORY051 actShowSectionName references SHAPE01\WORD051.SHP. The chapter importer decodes that original bitmap and records source/PNG digests; the opening displays it.

## First-battle messenger (resource-derived)

`obj-051.h` assigns `obj_Story_Level51_Object1 = 100`. PAK member `@:\data\obj-051.obs`, Object 100, names SHAPE\021-00001.SHP, ENEMY021_Total, defProcEnemy, SID_ENEMY021, extra-data ID 21 (extract with `hsl_resource_scanner.find_decoded_paks_packages`, `find_paks_record_by_name`, `read_paks_record_bytes`, select `obj_code = 100`). WINFAIL051 inserts Object 100, changes its ID to 10000, walks displacement `(32,32)`, speaks message 368, walks back to `(267,209)` and deletes it; `actWalkAndDeleteWait,SID_ENEMY026,1` and `SID_ENEMY021,1` then drive one departure each.

Remake: the messenger is visual-only (not in the battle roster), anchored on the exit marker with the source displacement and imported 021 walk frames; departures remove a living actor without recording damage or a kill. Provisional: native absolute coordinate mapping, camera curve, half-second walk, and ordinal lookup among defeated/reinforced actors (the remake picks the first living match).
