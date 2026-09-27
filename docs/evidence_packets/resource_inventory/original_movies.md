# Original movies: movie.pak start / end animation and audio (resource-derived + static-derived)

> evidence: resource-derived; static-derived · status: record-only · functions: 0x42da60, 0x42def0, 0x45a6d0, 0x45b266, 0x45b554, 0x45c530, 0x45c570, 0x45c5f0, 0x45d180 · tools: hsl_resource_scanner.py, hsltools/assets/movie_import.py · updated: 2026-09-19

**Claim boundary.** This packet describes the container, the two `.ani` animations and the two `.snd` tracks
of the original `movie.pak`, how the original executable plays them, and what the remake imports. Every
statement carries its evidence tier. Nothing here claims that the remake's playback is equivalent to the
original presentation; only the decoded frames and samples are the original data.

Machine-readable output: `content/imported/hsl/movie/manifest.json` (schema `hsl_movie_import.v1`), the WAV
files and WebP sprite sheets next to it. The full PNG frame sequences stay untracked under `ignored/movie/<name>/`.

```bash
/opt/homebrew/bin/python3 tools/hsl.py generate movie_import           # read $HSL_ORIGINAL_DIR/movie.pak, write tracked outputs + ignored/movie/ frames
/opt/homebrew/bin/python3 tools/hsl.py check movie_import   # no PAK: re-hash tracked outputs, validate manifest / sheet grids / WAV headers
/opt/homebrew/bin/python3 -m unittest tools.test_hsl_movie_import
```

## Container (resource-derived)

`movie.pak` is a PAKS container with the same directory format as `hsl.pak` (decoded by
`tools/hsl_resource_scanner.py`; no second parser). Four records, all inside the data region:

| Record | Bytes | sha256 |
| --- | ---: | --- |
| `?:\movie\start.snd` | 1,588,482 | `cdbf4a81e05807be034cee4a9324c90024f08dddf9aa64ccc644a84796d43a41` |
| `?:\movie\start.ani` | 36,855,137 | `3e295511eea8dc32b930ef28acf67cc2998e0505403fe6bb95538629c186caf8` |
| `?:\movie\end.ani` | 32,116,556 | `9aa43708bdccc46ea5e8fa42704f0d11ef3b8516693c64fd214aa0858e000f45` |
| `?:\movie\End.snd` | 371,220 | `64ea623225030fb57562ebb46bdd33408668886435abec093539ebc547fba1b6` |

## `.ani` = Autodesk Animator FLI (resource-derived)

The "unknown" header fields of the task brief are the standard 128-byte FLI header read as u16 pairs:

| Offset | Field | start.ani | end.ani | Tier |
| --- | --- | --- | --- | --- |
| 0x00 u32 | file size | 36,855,137 | 32,116,556 | resource-derived (equals record length) |
| 0x04 u16 | magic | 0xAF11 (FLI) | 0xAF11 | resource-derived |
| 0x06 u16 | frames | 742 | 501 | resource-derived (the brief's `[1]` = frames<<16 \| 0xAF11) |
| 0x08 / 0x0A u16 | width / height | 320 / 240 | 320 / 240 | resource-derived (`[2]` = 0x00F00140) |
| 0x0C / 0x0E u16 | depth / flags | 8 / 0 | 8 / 0 | resource-derived (`[3]`) |
| 0x10 u32 | speed | 4 | 4 | resource-derived (`[4]`; FLI jiffies = 1/70 s, **not used by the player**, see below) |
| 0x14–0x7F | reserved | all zero | all zero | resource-derived |

Frames start at 0x80. Each frame is a 16-byte header (u32 size, u16 magic `0xF1FA`, u16 chunk count, 8 reserved
zero bytes) followed by chunks (u32 size including the 6-byte header, u16 type). Chunk types present, counted by
`tools/hsltools/assets/movie_import.py`:

| Chunk | start.ani | end.ani | Meaning (Autodesk FLI spec) |
| --- | ---: | ---: | --- |
| 4 COLOR256 | 1 | 1 | palette packets of 8-bit RGB (both files: one packet, skip 0, 256 colours; the first 10 and last 8 entries are the Windows system palette) |
| 15 BRUN | 1 | 1 | first frame, byte-run compressed full frame |
| 12 LC | 685 | 410 | line-delta compressed frame (u16 first line, u16 lines; per line u8 packets of skip / signed count) |
| 16 COPY | 19 | 81 | uncompressed 320×240 frame |
| (none) | 38 | 10 | frames with zero chunks = repeat of the previous frame |

Decoded frame streams: start 743 frame records, end 502; the last record of each is the FLI **ring frame** whose
result is byte-identical to frame 0 (`ring_frame_matches_first_frame: true`), so the exported film is the header's
742 / 501 frames. **Cross-check:** the pure-Python decoder output (RGB24, all 742 + 501 frames) is byte-identical to
an independent decode by FFmpeg 9.0.1's `flic` decoder (`cmp` on raw RGB dumps, 170,956,800 and 115,430,400
bytes; ffprobe also reports 743 / 502 frames, 320×240 pal8). No unknown chunk type occurs; the decoder raises on any.

Content (visual, resource-derived from the decoded frames; interpretation is not a claim about the story): start.ani
is a pre-rendered 3D flight through a forest, a winged figure, a castle at sunset and a fortress wall with fires;
end.ani shows a chained demonic skull with glowing eyes in a stone hall, an explosion and a fade to white.

start.ani frame 500（原版帧见私有档案：`resource_inventory/original_movies_start_frame_0500.png`） end.ani frame 120（原版帧见私有档案：`resource_inventory/original_movies_end_frame_0120.png`）

## `.snd` = RIFF WAVE with a 38-byte XOR 0xA8 prefix (resource-derived + static-derived)

| | start.snd | End.snd |
| --- | --- | --- |
| fmt chunk size | 18 (WAVEFORMATEX, cbSize 0) | 16 |
| format | PCM mono 16,000 Hz 16-bit | PCM mono 11,025 Hz 8-bit |
| data bytes | 1,588,436 | 371,175 (+1 RIFF pad byte) |
| duration | 49.639 s | **33.667 s** (the brief's ≈11.6 s assumed 16-bit 16 kHz; the record is 8-bit 11,025 Hz) |

The obfuscation is a fixed **38-byte** prefix XOR 0xA8, not "the header up to `data`": in End.snd (16-byte fmt)
the `da` of the data marker is obfuscated and `ta` is clear, in start.snd (18-byte fmt) the marker is clear.
static-derived: the sound loader at `hsl01.exe 0x45a6d0` calls `0x45b266(buffer, 0xA8, 0x26)` when the buffer
does not start with `RIFF`, then reads the data size at `20 + fmt_size + 4` and the samples at `+ 8` without
checking the `data` tag. The importer restores the tag and writes standard WAVs whose samples are the original bytes.

## Original playback (static-derived, bounded radare2 read of hsl01.exe, ~20 min)

| Fact | Address | Tier |
| --- | --- | --- |
| Movie entry `play_movie(ani, snd)`: waits 1000 ms, allocates a 320×240 buffer, sets up a surface (`0x45c570(buf, 320, 240, 0, 0, cb 0x42deb0)`, `0x45c530(3, …)`), calls the player with volume `[0x477c20]` = 255 | `0x42def0` | static-derived |
| Player: loads the FLI (`0x45d180`, accepts 0xAF11 / 0xAF12, streams frames from the file), loads and starts the .snd once, then **schedules frame i at `i / [0x4a1920]` seconds** from the start tick; the float global `0x4a1920` is **15.0** in `.data` and is only rewritten (`70 / speed`) when it is zero — its three code references are all inside this routine, so the FLI header speed = 4 (17.5 fps as jiffies) is never used | `0x45c5f0` | static-derived |
| Scheduler tolerances: a frame is drawn as soon as `elapsed − due ≥ −0.1 s`; when `elapsed − due > 0.25 s` frames are decoded without drawing (callback arg 1) for up to 45 consecutive frames; the callback returning −1 aborts | `0x45c5f0` | static-derived |
| Consistency: 742 / 15 = 49.47 s vs 49.64 s of start.snd; 501 / 15 = 33.40 s vs 33.67 s of End.snd (both within 0.3 s) | manifest `audio_video_duration_delta_s` | resource-derived |
| **start.ani** is played by the level-entry routine when the level is **51** and the global `0x4c1ae4` is zero (`cmp ebx, 0x33`) | `0x42da60` | static-derived (the trigger); what `0x4c1ae4` means is **provisional** — it is set to 1 by a routine at `0x42cca3` that also sets `0x4c1b00 \|= 0x90000000`, read as a reload / re-entry marker |
| **end.ani** is played by the `actPlayMovie` opcode handler | `0x451b1c` | static-derived (WINFAIL059 contains the token, resource-derived) |
| Debug hotkeys: with `[0x4c1ae8]` non-zero, key `C` (VK 0x43) plays start, `D` (0x44) plays end (`0x45b554` is a "key just pressed" bit test on the keyboard state at `0x4c2394`) | `0x42d600` | static-derived, not a product path |

## Remake import (what the tracked assets are)

| Output | Content |
| --- | --- |
| `content/imported/hsl/movie/start.wav`, `end.wav` | de-obfuscated WAV, samples verbatim (1,588,482 / 371,220 bytes) |
| `start_sheet_00..03.webp` (4 sheets, 11,158,458 bytes) | 742 frames, 12 columns × 17 rows of 320×240 per full sheet (3840×4080), row-major, lossy WebP quality 85 |
| `end_sheet_00..02.webp` (3 sheets, 11,453,482 bytes) | 501 frames, same grid |
| `manifest.json` | per movie: source members and sha256, FLI header, chunk counts, frame count / rate (15) / duration, decoded-frame sha256, audio format and duration, sheet files with frame ranges / grid / sha256, thumbnail, `claim_limit` |
| `ignored/movie/<name>/frame_NNNN.png` | full lossless frame sequence for review (not tracked) |

The build is deterministic (two runs produced identical hashes). Both movies stayed within the 12 MB per-movie
budget at quality 85, so no quality step-down or frame-rate halving was applied; if a future source needed that the
tool fails below quality 60 instead of silently changing the frame rate.

## Unresolved / not claimed

- The meaning of the global `0x4c1ae4` that suppresses the opening movie (provisional; replace with a bounded
  execution or a runtime observation of a reloaded level 51).
- The original display path (surface set-up `0x45c570`, mode argument 3, frame callback `0x42deb0`, whether the
  320×240 frames are scaled to the 640×480 screen and how) was not analysed; the remake decides its own scaling.
- Audio/video synchronisation in the original is "start .snd, then pace frames from the same tick"; drift handling
  beyond the 0.1 s / 0.25 s tolerances above is not modelled.
- The sprite sheets are lossy; pixel-exact review must use the untracked PNG frames or re-run the importer.
- Whether the original skips the movie on a key press (the callback's −1 path) is not confirmed.
