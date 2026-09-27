# Battle sound sources: actor sounds, footsteps, interface, GAME OVER, level-up

> evidence: static-derived; resource-derived: PLAYERS.TXT sound fields, resource.h／RESOURCE.TXT sound bindings, PAK WAV members; runtime-measured: remake Master-bus recordings · status: live · functions: 0x409610, 0x42c180, 0x42c1c0, 0x42c250, 0x42c340, 0x43de90, 0x43dec0, 0x4477b0, 0x459990, 0x45a0b0, 0x45a390 · tools: hsltools/assets/actor_audio.py, hsltools/assets/interface_audio.py · updated: 2026-09-27

## 结论

- Original: actor sounds come from explicit PLAYERS.TXT `sound_*` fields; the walk sound plays every eight 4-pixel steps on the two battle movement paths and on scripted frames 0／3; confirmation (398), item use (402), level-up (401) and GAME OVER (628) are pushed by named call sites to the shared wrapper `0x42c180` (static-derived; resource-derived).
- Remake: `hsltools/assets/actor_audio.py` and `hsltools/assets/interface_audio.py` extract and normalise exactly the named PAK WAVs; `ActorRuntime` emits the per-cell and scripted-frame walk cues, the interface player plays confirmation／item use／level-up, `GameOverScreen` plays GAMEOVER.WAV (resource-derived; static-derived).
- Differences: trigger timing within an event, relative volume, overlap and the per-cell walk tempo are remake choices (provisional); terrain footstep variants (`0x43dec0`／`0x43de90`) are not connected. Music is in [original_music.md](original_music.md).

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

### Actor sounds (resource-derived)

| Characters | walk | attack | miss | dead |
| --- | --- | --- | --- | --- |
| 1／21／23 | WALK0011 | ATTACK01 | MISS0001 | DEAD0003 |
| 24 | WALK0012 | ATTACK05 | MISS0001 | DEAD0003 |
| 26 | WALK0011 | ATTACK05 | MISS0001 | DEAD0003 |

Explicit table associations from PLAYERS.TXT, not filename guesses. The native table parser reads `sound_walk` at `0x44bae2` and stores its resolved identifier at `0x44bb00` in template offset +8 (word) (static-derived); the handle numbering is in [original_save_format.md](original_save_format.md).

### Walking cues (static-derived)

| Fact | Address |
| --- | --- |
| Live character record at `[0x4c1bc8] + object[+0xa4] * 0x1fc`; default branch reads word `+8` and calls the audio wrapper | `0x409610`, `0x4096e1..0x4096e9` → `0x42c180` |
| Two battle movement paths advance a displacement component by 4 px, decrement `+0x9e`, play the walk sound at zero, reload 8 and advance the path cursor: one sound per 32-px cell | `0x4411fe..0x44126a` (`0x441298`), `0x443f85..0x443ff1` (`0x44401f`) |
| The packed path cursor／countdown starts at `0x00080000`, so the first footstep also follows eight increments | `0x4410b7`, `0x443d70` |
| Scripted motion plays only when the animation counter equals delay − 1 and current frame − group start is 0 or 3, excluding the disabled-motion flag and invalid motion state | `0x454041..0x45408a` |
| The wrapper checks audio enable, resolves the id and calls the mixer with volume 255 | `0x42c180` → `0x45a390` |
| Environment-dependent alternatives | `0x43dec0`, `0x43de90` |

### Interface, GAME OVER and level-up (resource-derived; static-derived)

| Cue | resource.h → RESOURCE | PCM | Call site |
| --- | --- | --- | --- |
| `sfxAccept=398` | `WAV\ACCEPT01.WAV` | 11,025 Hz mono 8-bit, 4,409 frames (0.400 s) | `0x43e920` push 398 → `0x4477b0` (`0x43e92b`) → `0x459990` (`0x43e931`) → `0x42c180` (`0x43e93a`) |
| `sfxUseItem=402` | `WAV\MHEAL001.WAV` | 11,025 Hz mono 8-bit, 21,129 frames (1.916 s) | `0x40a349` push 402 → `0x42c180` (`0x40a35d`) |
| `sfxLevelUp=401` | `WAV\LEVELUP2.WAV` | 22,050 Hz mono 8-bit, 46,084 frames (2.090 s) | `0x40854f` push 401 → `0x4477b0` (`0x408554`) → `0x459990` (`0x40855a`) → `0x42c180` (`0x408563`) |
| `sfxGameOver=628` | `WAV\GAMEOVER.WAV` | 16 kHz mono signed 16-bit, 106,667 frames (6.667 s) | `0x42aebe` push 628 → resolve `0x42aed3` → load `0x42aed9` → `0x42c180` (`0x42aee2`) |

### Remake output (runtime-measured, remake side)

Non-headless Godot runs recorded the Master bus through `AudioEffectRecord`: walk cues 48 kHz stereo 3.37 s, soldier／beast／scripted sections separated by silence, peak 19291/32767; confirmation＋potion 3.424 s, confirmation peak 10073/32767, healing peak 6419/32767, silent gaps. These prove mixed output and complete tails, not subjective loudness or original audiovisual timing.

## 重制接线

- `tools/hsltools/assets/actor_audio.py` → `content/imported/hsl/chapter01/actor_audio.json` and normalised WAVs (source and decoded checksums, PCM profiles); per-level copies via `level_actors:<N>`.
- `tools/hsltools/assets/interface_audio.py` extracts ACCEPT01／MHEAL001／GAMEOVER／LEVELUP2, decodes the XOR-A8 header and records source and decoded hashes.
- `game/battle/runtime/ActorRuntime.gd` owns one walk `AudioStreamPlayer`: per completed grid segment on player and AI paths, frames 0／3 on scripted walks; cancel, zero-duration correction and node exit stop it.
- One interface `AudioStreamPlayer` at −6 dB: confirmation on releasing an enabled command, item use on a successful application (rejected use is silent; `game/battle/scene/BattleItemUsePresentation.gd` `audio:` provenance), level-up only when the settled receipt shows `level_after > level_before`.
- `game/title/GameOverScreen.gd` plays GAMEOVER.WAV as the GAME OVER screen fades in (`rules:` provenance).
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/first_battle_audio.md`.
- provisional: the per-cell walk tempo and every trigger moment inside an event; replacement points are the tick clock ([original_tick_rate](../runtime_observations/original_tick_rate/README.md)) and the named call sites above.

## 复现

`python3 tools/hsl.py check actor_audio interface_audio`（no original installation needed）；static call sites: `r2 -e scr.color=0 -q -c 'pd 12 @ 0x43e920; pd 12 @ 0x40a349; pd 10 @ 0x40854d; pd 20 @ 0x42aea0' "$HSL_ORIGINAL_DIR/hsl01.exe"`.

## 边界

- Complete scenario-unit-to-character initialisation, repeated playback cadence, relative volume, panning and original overlap flags are not established; PCM validation does not prove auditory equivalence.
- Only the default actor walking sounds are connected; the terrain variants of `0x409610` are not claimed.
- Not every original UI trigger has been recovered; no unproven cancel cue is substituted.
- Exact subframe delay of scripted footsteps depends on the unresolved native tick／frame clock.
- The music tracks come from the Steam 經典版 ([steam_classic_edition.md](../resource_inventory/steam_classic_edition.md)); the older catalogue comparison of CD track numbers is kept as data in `first_battle_music_candidates.json` and is not a source claim.
