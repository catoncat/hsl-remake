# First battle audio sources

> evidence: static-derived · status: live · functions: 0x409610, 0x42c180, 0x42c1c0, 0x42c250, 0x42c340, 0x43de90, 0x43dec0, 0x4477b0, 0x459990, 0x45a0b0, 0x45a390 · tools: hsltools/assets/actor_audio.py, hsltools/assets/interface_audio.py · updated: 2026-09-05

Checked: 2026-09-05. EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

## Music (static-derived)

`0x42c1c0` resolves a level number into a signed word from `0x477b44 + level*2`. Argument -1 uses current level global `0x4c1bb8`. For level 51, address `0x477baa` contains `13 00`: track 19.

`0x42c340` calls that resolver with -1 and passes its result to `0x42c250`. At `0x42c2ba` the latter formats `music\%02d.wav`; at `0x42c2f2` it calls loader `0x45a0b0` with flag 4. The no-argument script-dispatch branch at `0x452a80` (actPlayLevelMusic) calls `0x42c340`. The whole music flow (loop, stops, title, world map, town, GameClear, every story script) is in [original_music.md](original_music.md). STORY051 starts with `actPlayLevelMusic`.

Reproduce:

```sh
r2 -e scr.color=0 -q -c 'pd 12 @ 0x42c1c0; px 2 @ 0x477baa; pd 65 @ 0x42c250; pd 5 @ 0x42c340; pd 8 @ 0x452a80' "$HSL_ORIGINAL_DIR/hsl01.exe"
```

The active Wine game directory contains no music directory. The hsl.pak member inventory contains no music WAV member; checked Documents/Downloads/Wine paths yielded no music/19.wav. This proves absence only in the checked locations, not on the entire machine. User confirmed extraction is the Agent responsibility; continue self-service investigation and deprioritize missing BGM. The tracks were later obtained from the user's Steam 經典版 ([steam_classic_edition.md](../resource_inventory/steam_classic_edition.md)).

## Character sounds (resource-derived)

`tools/hsltools/assets/actor_audio.py` joins the tracked PLAYERS.TXT character codes 1/21/23/24/26 to their explicit sound_walk/sound_attack/sound_miss/sound_dead fields, extracts exactly six named PAK members, and normalizes their encoded WAV headers using the existing importer. Output: `content/imported/hsl/chapter01/actor_audio.json` and audio_normalized files. Source and decoded checksums plus PCM profiles are recorded. `--check` requires no external game installation.

All five use DEAD0003 and MISS0001. Character 24 uses WALK0012; the others use WALK0011. Characters 1/21/23 use ATTACK01; 24/26 use ATTACK05. These are explicit table associations, not filename guesses. Native table parser reads sound_walk at `0x44bae2` and stores its resolved identifier at `0x44bb00` in template offset +8 (word).

Not established: complete scenario-unit-to-character initialization, walking frame triggers, repeated playback cadence, relative volume, panning, attack/death choreography. Walk sounds are now wired as described below. Attack/miss/dead sounds are also connected to settled combat events using remake timing, following the user-approved preference for improved presentation over exact historical reproduction. PCM validation does not prove auditory equivalence or in-game timing.


## Walking cues (static-derived; live presentation still provisional)

- `0x409610` resolves the actor's live character record at `[0x4c1bc8] + object[+0xa4] * 0x1fc`. Its default branch `0x4096e1..0x4096e9` reads word `+8` and calls audio wrapper `0x42c180`. This joins the parser's `sound_walk` field to actual playback.
- Two battle movement paths advance a displacement component by four pixels (`0x4411fe..0x44126a`, `0x443f85..0x443ff1`). They decrement a counter at `+0x9e`, play the walking sound at zero (`0x441298`, `0x44401f`), reload eight, and advance the path cursor. Eight four-pixel increments make one 32-pixel cell. The remake emits the corresponding cue after each completed grid-path segment.
- Scripted motion uses a distinct check at `0x454041..0x45408a`: it excludes the relevant disabled-motion flag and invalid motion state, checks the animation counter against delay minus one, then plays only when current frame minus group start is 0 or 3. The remake uses those two relative frames for its scripted opening walk. Exact subframe delay still depends on the unresolved native tick/frame clock.
- The sound wrapper checks audio enable state, resolves the sound id and calls `0x45a390` with volume 255. Original overlap flags, attenuation and platform mixing are not reproduced exactly.
- `0x409610` also has environment-dependent alternatives via `0x43dec0` and `0x43de90`. Only the explicit default actor walking sounds are currently connected; do not claim all terrain footstep variants.

`ActorRuntime` owns one `AudioStreamPlayer` child for its walk presentation. Ordinary player and AI paths emit per-segment cues; the opening call selects scripted frame cues. Zero-duration correction, cancel and node exit stop playback and cancel its schedule. Walking completion keeps the final sound tail; no separate battle state or timer is added.

Verification: live scene actors load their table-selected streams, movement tests check no premature cue, each completed cell including the last, scripted frame 0/3, and silence after cancellation. A non-headless Godot run recorded the actual Master bus through `AudioEffectRecord`: 48 kHz stereo, 3.37 s, nonzero soldier/beast/scripted sections separated by silence, peak 19291/32767. Raw recording stays in `ignored/audio-review/walk-output.wav`. This proves mixed output, not subjective original loudness or exact audiovisual timing.

The two cue modes are required by the two native call paths; the cue helpers are shared by movement and frame advancement. No credible removable abstraction remained. Ablation removed an added node-exit cleanup hook: it did not resolve the warning and duplicates engine lifecycle handling. The focused audio test now allows 100 ms for AudioServer to release stopped voices asynchronously before test-process shutdown; the test passes without resource warnings.


Movement pacing follow-up: the battle walker initializes the packed path cursor/countdown to `0x00080000` at `0x4410b7` and `0x443d70`, so the first footstep also follows eight displacement increments. The remake now assigns each 32-pixel path segment the same provisional 0.18 s, rather than compressing an entire multi-cell walk into that duration. Native updates-per-second, acceleration options and exact timing remain unresolved; the structural correction does not establish the final tempo.


## Interface confirmation and item use (resource-derived, static-derived)

`resource.h` binds `sfxAccept=398` and `sfxUseItem=402`; RESOURCE.TXT maps them to `WAV\ACCEPT01.WAV` and `WAV\MHEAL001.WAV`. `tools/hsltools/assets/interface_audio.py` extracts those two named PAK members, decodes the XOR-A8 WAV header and records both source and decoded hashes. `--check` validates the tracked symbol/name mappings, decoded hashes and PCM profiles without the original installation. Both are 11,025 Hz mono, 8-bit PCM: confirmation 4,409 frames (0.400 s), healing 21,129 frames (1.916 s).

Native confirmation call path at `0x43e920` pushes 398, calls name resolver `0x4477b0` at `0x43e92b`, loader `0x459990` at `0x43e931`, then playback wrapper `0x42c180` at `0x43e93a`. Item-use path pushes 402 at `0x40a349`, reaching the same wrapper at `0x40a35d`. These establish original playback of the explicitly named resources, without claiming every original UI trigger has been recovered.

Reproduce the static call-site inspection:

```sh
r2 -e scr.color=0 -q -c 'pd 12 @ 0x43e920; pd 12 @ 0x40a349' "$HSL_ORIGINAL_DIR/hsl01.exe"
```

The remake uses one reusable interface `AudioStreamPlayer` at -6 dB. Releasing the pointer on the same enabled command plays confirmation; successful healing plays the item-use cue. Rejected item use does not play it. Trigger timing, relative volume and single-voice overlap are modern presentation choices; no unproven cancel cue is substituted. Existing character sounds remain separately mixed. The two events share a three-line helper; no credible removable abstraction or duplicated mechanism warranted an executable ablation experiment.

Verification: a non-headless real-scene harness recorded the Master bus through `AudioEffectRecord` after opening voices had drained, clicked/released Move, then used a potion through the actual panel with a wounded-player fixture. The 48 kHz stereo mix is 3.424 s; initial/gap/final windows are silent, confirmation peak 10073/32767 and healing-window peak 6419/32767. Raw capture: `ignored/interface-audio-review/output.wav`. This demonstrates actual mixed output and complete tails, not subjective listening equivalence or a full battle route. Runtime tests cover confirmation release, successful potion sound and rejected full-health silence.


## Game Over (resource-derived, static-derived)

`resource.h` explicitly binds `sfxGameOver=628`; RESOURCE maps 628 to `WAV\GAMEOVER.WAV`. The same interface-audio importer now includes this third member (16 kHz, mono, signed 16-bit PCM, 106,667 frames / 6.667 s). Original call site `0x42aebe` pushes 628; `0x42aed3` resolves its name, `0x42aed9` loads it, and `0x42aee2` calls playback wrapper `0x42c180`. Reproduce with `r2 -e scr.color=0 -q -c 'pd 20 @ 0x42aea0' "$HSL_ORIGINAL_DIR/hsl01.exe"`.

The remake plays it when the failure result first becomes visible, after death-line dialogue and combat presentation. It reuses the existing interface audio player; refreshing the result does not restart the sound. Victory does not borrow this failure cue. This is resource-correct audio with a modern presentation trigger, not native game-over screen/timing equivalence.

A real-scene settled-outcome fixture recorded the Master bus and captured both result variants in `ignored/result-review/`. Both actual mouse-button input sequences reload the real scene and verify HP 30, recovery-item quantity 3 and no outcome. This tests end-screen presentation and restart, not the combat route producing those outcomes. The separate full battle routes remain documented in the playability audit.


## Level-up cue (resource-derived, static-derived)

`resource.h` binds `sfxLevelUp=401`; RESOURCE maps it to `WAV\LEVELUP2.WAV`. The interface-audio importer now includes this resource and verifies its source binding, decoded hash and PCM profile: 22,050 Hz mono 8-bit PCM, 46,084 frames / 2.090 s. Native call site `0x40854f` pushes 401; `0x408554` calls name resolver `0x4477b0`, `0x40855a` loads it through `0x459990`, then `0x408563` calls audio wrapper `0x42c180`. Reproduce with `r2 -e scr.color=0 -q -c 'pd 10 @ 0x40854d' "$HSL_ORIGINAL_DIR/hsl01.exe"`.

Runtime listens to the existing once-per-strike cut-in impact signal and reads the settled experience receipt. Only `level_after > level_before` plays the cue, at the same frame as visible upgrade text. Ordinary gain and later visual refreshes are silent. Normal, special and counter receipts share this signal; no extra schedule or presentation flag is added. Timing and -6 dB interface-player mixing are remake choices, not original choreography equivalence.

A non-headless real-scene fixture set the player near the threshold and an adjacent foe to one HP, then used actual deterministic attack settlement: 21 EXP, level 1 → 2. `ignored/growth-review/upgrade.png` was visually checked and `output.wav` captured the Master mix through the complete cue tail. This is a controlled upgrade demonstration, not a natural full-battle leveling route. Runtime tests check delayed onset, visible upgrade, matching stream, non-repetition and silence on ordinary EXP. No credible removable abstraction remained; the event subscription reuses the existing impact and sound paths.

## Missing music source follow-up — 2026-09-05

Read-only inspection of the Wine installation, Downloads game copy and archived original copy still found no music directory; an exact Spotlight `19.wav` query found no file. The Documents/Downloads archive inventory did not reveal a matching game-disc or music archive. These are bounded local negative observations, not proof that the soundtrack is unavailable everywhere.

A [disc owner's catalogue](https://www.omega.idv.tw/kdb120/viewthread.php?threadid=5692) publishes a CUE with data track 01 and audio tracks 02–19. A [separate gamerip catalogue](https://downloads.khinsider.com/game-soundtracks/album/the-legend-of-fancy-realm-windows-gamerip-1995) lists 18 audio tracks numbered 1–18. The first 17 CUE spans match the ordered rip durations with only short gaps (approximately 0.95–2.15 seconds) between them. This supports an **inference** that rip Track 18 corresponds to CD track 19, which is the local EXE's first-battle music lookup. The final CUE track has no following boundary, so its duration cannot be independently checked from that listing alone.

Compact source URLs, indices, duration comparison and limits are in `first_battle_music_candidates.json`. These catalogue findings do not constitute an extracted local music asset or verified PCM equivalence. At that investigation checkpoint, no BGM file had been integrated. The rip page's year metadata also disagrees with the photographed-disc catalogue; it is not used as historical authority.

A follow-up inspected central-directory names in all 44 ZIP archives discovered under Documents/Downloads (including ignored/hidden paths), without extracting unrelated content: no `19.wav`, HSL disc image/CUE, or music-directory audio entries. One non-ZIP archive was unrelated by name and was not opened. Mounted-volume names did not identify a game disc. No I/O errors occurred in the ZIP scan. The user subsequently confirmed no other copy exists and explicitly allowed online sourcing or original composition. The tracks were later obtained from the user's Steam 經典版 (see [steam_classic_edition.md](../resource_inventory/steam_classic_edition.md)). The original track identity and missing local file remain separate source facts.
