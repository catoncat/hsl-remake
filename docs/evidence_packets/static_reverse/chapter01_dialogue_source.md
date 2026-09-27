# Chapter 01 dialogue source

> evidence: resource-derived; static-derived · status: record-only · functions: 0x447620, 0x447720, 0x4477b0 · tools: hsl_chapter_dialogue.py, hsltools/levels/message_text.py · updated: 2026-09-05

2026-09-05, resource-derived / static-derived.

Original `hsl.pak` member `@:\DATA\RESOURCE.TXT` is a cp950 `[name]` table containing resource paths, names and dialogue. `item = id,text` splits on the first comma. `@0` through `@9` are color controls; `#` is a line break. Imported source bytes and SHA-256 are retained in the chapter message manifest. Reproduce the chapter-wide manifest with `PYTHONPATH=. python3 tools/hsl_chapter_dialogue.py --pak <hsl.pak> --chapter` (check `python3 tools/hsl.py check message_text_evidence_check:chapter01`); a level's own manifest with `--level N` (check `message_text_evidence_check:N`, level 51 included).

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

- `0x42f3b9` references `DATA\RESOURCE.TXT`; `0x42f3c4` calls loader `0x447720`.
- `0x447778` passes section `name` to `0x447620`.
- `0x447680..0x447687` splits each entry at comma, parses its numeric ID; `0x4476bb` stores the text pointer at table + ID * 4.
- `0x4477b0` retrieves the indexed text through global `0x4c1b3c`.

STORY051's seven dialogue events use IDs 363, 364, 365, 366, 367, 364, 1101. Death / retreat lines are also imported for later event integration. The old filename search for msg/mess/dialog/talk missed this mixed-purpose table; that negative search is superseded. Text source resolution does not claim original font, message-box layout or handler timing. Current readable layout and automatic preparation are remake presentation choices.

STORY051 actShowSectionName references SHAPE01\WORD051.SHP. The chapter importer now also decodes that original bitmap and records source/PNG digests; the live opening displays it. This resolves visual title presentation, without requiring a decoded text-table representation of the image.
