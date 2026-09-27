# Original movies: movie.pak start / end animation and audio

> evidence: resource-derived; static-derived; runtime-measured: remake playback frame check · status: live · functions: 0x42da60, 0x42def0, 0x45a6d0, 0x45b266, 0x45b554, 0x45c530, 0x45c570, 0x45c5f0, 0x45d180 · tools: hsl_resource_scanner.py, hsltools/assets/movie_import.py, test_hsl_movie_import.py · updated: 2026-09-27

## 结论

- Original: `movie.pak` holds two Autodesk FLI animations (`start.ani` 742 frames, `end.ani` 501 frames, 320×240, 8-bit) and two RIFF WAVs whose first 38 bytes are XOR 0xA8; the player `0x45c5f0` paces frame i at `i / 15.0` s from the sound start, ignoring the FLI speed field; `start` plays on entering level 51 (`0x42da60`), `end` on `actPlayMovie` (`0x451b1c`) (resource-derived; static-derived).
- Remake: `hsltools/assets/movie_import.py` decodes both films byte-identically to FFmpeg, restores standard WAVs, and packs WebP sprite sheets plus `content/imported/hsl/movie/manifest.json`; `game/title/MoviePlayer.gd` plays them at 15 fps with audio and clock started together (resource-derived; runtime-measured: remake playback frame check).
- Differences: scaling to 640×480, the skip key and the meaning of the suppressing global `0x4c1ae4` are remake reads (provisional); the original display path is unread.

## 证据

### Container (resource-derived)

`movie.pak` is a PAKS container with the same directory format as `hsl.pak` (decoded by `tools/hsl_resource_scanner.py`; no second parser). Four records, all inside the data region:

| Record | Bytes | sha256 |
| --- | ---: | --- |
| `?:\movie\start.snd` | 1,588,482 | `cdbf4a81e05807be034cee4a9324c90024f08dddf9aa64ccc644a84796d43a41` |
| `?:\movie\start.ani` | 36,855,137 | `3e295511eea8dc32b930ef28acf67cc2998e0505403fe6bb95538629c186caf8` |
| `?:\movie\end.ani` | 32,116,556 | `9aa43708bdccc46ea5e8fa42704f0d11ef3b8516693c64fd214aa0858e000f45` |
| `?:\movie\End.snd` | 371,220 | `64ea623225030fb57562ebb46bdd33408668886435abec093539ebc547fba1b6` |

### `.ani` = Autodesk Animator FLI (resource-derived)

Standard 128-byte FLI header:

| Offset | Field | start.ani | end.ani |
| --- | --- | --- | --- |
| 0x00 u32 | file size | 36,855,137 | 32,116,556 (equals record length) |
| 0x04 u16 | magic | 0xAF11 (FLI) | 0xAF11 |
| 0x06 u16 | frames | 742 | 501 |
| 0x08 / 0x0A u16 | width / height | 320 / 240 | 320 / 240 |
| 0x0C / 0x0E u16 | depth / flags | 8 / 0 | 8 / 0 |
| 0x10 u32 | speed | 4 | 4 (FLI jiffies = 1/70 s, **not used by the player**) |
| 0x14–0x7F | reserved | all zero | all zero |

Frames start at 0x80. Each frame is a 16-byte header (u32 size, u16 magic `0xF1FA`, u16 chunk count, 8 reserved zero bytes) followed by chunks (u32 size including the 6-byte header, u16 type):

| Chunk | start.ani | end.ani | Meaning (Autodesk FLI spec) |
| --- | ---: | ---: | --- |
| 4 COLOR256 | 1 | 1 | one palette packet, skip 0, 256 colours; the first 10 and last 8 entries are the Windows system palette |
| 15 BRUN | 1 | 1 | first frame, byte-run compressed full frame |
| 12 LC | 685 | 410 | line-delta compressed frame (u16 first line, u16 lines; per line u8 packets of skip / signed count) |
| 16 COPY | 19 | 81 | uncompressed 320×240 frame |
| (none) | 38 | 10 | zero chunks = repeat of the previous frame |

Decoded frame streams: start 743 frame records, end 502; the last record of each is the FLI **ring frame**, byte-identical to frame 0 (`ring_frame_matches_first_frame: true`), so the exported film is the header's 742 / 501 frames. The pure-Python decoder output (RGB24, all 742 + 501 frames) is byte-identical to FFmpeg 9.0.1's `flic` decoder (`cmp` on raw RGB dumps, 170,956,800 and 115,430,400 bytes; ffprobe reports 743 / 502 frames, 320×240 pal8). No unknown chunk type occurs; the decoder raises on any.

Content (visual reading of the decoded frames): start.ani is a pre-rendered 3D flight through a forest, a winged figure, a castle at sunset and a fortress wall with fires; end.ani shows a chained demonic skull with glowing eyes in a stone hall, an explosion and a fade to white.

start.ani frame 500（原版帧见私有档案：`resource_inventory/original_movies_start_frame_0500.png`） end.ani frame 120（原版帧见私有档案：`resource_inventory/original_movies_end_frame_0120.png`）

### `.snd` = RIFF WAVE with a 38-byte XOR 0xA8 prefix (resource-derived; static-derived)

| | start.snd | End.snd |
| --- | --- | --- |
| fmt chunk size | 18 (WAVEFORMATEX, cbSize 0) | 16 |
| format | PCM mono 16,000 Hz 16-bit | PCM mono 11,025 Hz 8-bit |
| data bytes | 1,588,436 | 371,175 (+1 RIFF pad byte) |
| duration | 49.639 s | 33.667 s |

The obfuscation is a fixed **38-byte** prefix XOR 0xA8, not "the header up to `data`": in End.snd (16-byte fmt) the `da` of the data marker is obfuscated and `ta` is clear; in start.snd (18-byte fmt) the marker is clear. The sound loader `0x45a6d0` calls `0x45b266(buffer, 0xA8, 0x26)` when the buffer does not start with `RIFF`, then reads the data size at `20 + fmt_size + 4` and the samples at `+ 8` without checking the `data` tag (static-derived).

### Original playback (static-derived, radare2 read of hsl01.exe)

| Fact | Address |
| --- | --- |
| Movie entry `play_movie(ani, snd)`: waits 1000 ms, allocates a 320×240 buffer, sets up a surface (`0x45c570(buf, 320, 240, 0, 0, cb 0x42deb0)`, `0x45c530(3, …)`), calls the player with volume `[0x477c20]` = 255 | `0x42def0` |
| Player: loads the FLI (`0x45d180`, accepts 0xAF11 / 0xAF12, streams frames from the file), loads and starts the .snd once, then **schedules frame i at `i / [0x4a1920]` seconds** from the start tick; the float `0x4a1920` is **15.0** in `.data` and is rewritten (`70 / speed`) only when zero — its three code references are all inside this routine, so the header speed 4 is never used | `0x45c5f0` |
| Scheduler tolerances: a frame is drawn once `elapsed − due ≥ −0.1 s`; when `elapsed − due > 0.25 s` frames are decoded without drawing (callback arg 1) for up to 45 consecutive frames; the callback returning −1 aborts | `0x45c5f0` |
| Consistency (resource-derived): 742 / 15 = 49.47 s vs 49.64 s of start.snd; 501 / 15 = 33.40 s vs 33.67 s of End.snd (both within 0.3 s; manifest `audio_video_duration_delta_s`) | — |
| **start.ani** plays in the level-entry routine when the level is **51** and `0x4c1ae4` is zero (`cmp ebx, 0x33`); `0x4c1ae4` is set to 1 at `0x42cca3` together with `0x4c1b00 \|= 0x90000000` (read as a reload / re-entry marker, provisional) | `0x42da60` |
| **end.ani** plays in the `actPlayMovie` opcode handler (WINFAIL059 contains the token, resource-derived) | `0x451b1c` |
| Debug hotkeys: with `[0x4c1ae8]` non-zero, key `C` (VK 0x43) plays start, `D` (0x44) plays end (`0x45b554` is a key-just-pressed bit test on the keyboard state at `0x4c2394`); not a product path | `0x42d600` |

### Remake playback check (runtime-measured, remake side)

Frames from the title review capture at 640×480, reduced nearest-neighbour to 320×240, searched for the minimum mean absolute difference (0–255) in the untracked decoded PNG sequence:

| Shot | Best frame | MAD | Wrong-frame control |
| --- | ---: | ---: | --- |
| opening 1 s | 29 | 2.44 | — |
| opening 20 s | 301 (second sheet) | 3.40 | frame 100: 17.4 |
| ending 15 s | 227 | 3.66 | frame 50: 125.7 |

MAD 2–4 is the WebP q85 residual; the order-of-magnitude gap shows the in-sheet row/column and cross-sheet frame mapping are correct.

## 重制接线

| Output | Content |
| --- | --- |
| `content/imported/hsl/movie/start.wav`, `end.wav` | de-obfuscated WAV, samples verbatim (1,588,482 / 371,220 bytes) |
| `start_sheet_00..03.webp` (4 sheets, 11,158,458 bytes) | 742 frames, 12 columns × 17 rows of 320×240 per full sheet (3840×4080), row-major, lossy WebP quality 85 |
| `end_sheet_00..02.webp` (3 sheets, 11,453,482 bytes) | 501 frames, same grid |
| `manifest.json` (schema `hsl_movie_import.v1`) | per movie: source members and sha256, FLI header, chunk counts, frame count / rate (15) / duration, decoded-frame sha256, audio format and duration, sheet files with frame ranges / grid / sha256, thumbnail, `claim_limit` |
| `ignored/movie/<name>/frame_NNNN.png` | full lossless frame sequence for review (not tracked) |

- The build is deterministic; both movies fit the 12 MB per-movie budget at quality 85, and the tool fails below quality 60 instead of silently changing the frame rate.
- `game/title/MoviePlayer.gd` shows frame 0, then starts audio and clock together and skips the first delta; `game/title/TitleScreen.gd` plays `start` after the title fade-out and before level 51. Both carry `## provenance:` `rules: static-derived docs/evidence_packets/resource_inventory/original_movies.md` (MoviePlayer also `timing:`).
- provisional: nearest-neighbour doubling to 640×480 and the any-key skip (remake-invented in the MoviePlayer header); `end` is triggered by the `actPlayMovie 140` → `end` mapping.

## 复现

`python3 tools/hsl.py check movie_import`（no PAK needed: re-hashes tracked outputs, validates manifest, sheet grids and WAV headers; `generate movie_import` rebuilds from `$HSL_ORIGINAL_DIR/movie.pak`）.

## 边界

- The meaning of `0x4c1ae4` that suppresses the opening movie (provisional; replace with a bounded execution or a runtime observation of a reloaded level 51).
- The original display path (surface set-up `0x45c570`, mode argument 3, frame callback `0x42deb0`, whether the 320×240 frames are scaled to the 640×480 screen and how) was not analysed; the remake decides its own scaling.
- Audio/video synchronisation in the original is "start .snd, then pace frames from the same tick"; drift handling beyond the 0.1 s / 0.25 s tolerances is not modelled.
- The sprite sheets are lossy; pixel-exact review must use the untracked PNG frames or re-run the importer.
- Whether the original skips the movie on a key press (the callback's −1 path) is not confirmed.
- The playback check proves the remake plays the imported assets by the manifest, not frame equivalence with the original player.
