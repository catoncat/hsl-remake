# Gate fire animation

> evidence: resource-derived · status: record-only · functions: 0x45e5a6 · tools: hsltools/assets/fire_animation.py · updated: 2026-09-08

The two level-51 fire placements (EVEF records 3 and 6) share OBJ-051 object 22. Re-reading the original PAK gives `obj_Shape_Number=10`, `obj_Shape_Delay=3`, `obj_Data9=mapobjNextShape`, `obj_Mode=engADDCOLOR_ZOOM`, and both zoom fields `0x0000a000`. These fields are resource-derived and preserved with the OBS source hash in `content/imported/hsl/chapter01/fire_animation/manifest.json`.

All ten FIRE01 SHP frames are imported with per-frame draw origins and source/PNG hashes. `tools/hsltools/assets/fire_animation.py` regenerates them from the original installation; `--check` checks imported frame count, delay, scale and PNG integrity without Wine or the PAK.

## Static sequence rule

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

- Original PROCESS.DEF maps `defProcStandObject=2`; slot `0x477c34` points to `0x43ccf0`.
- TYPE.H maps `mapobjNextShape=5`. The process switch decrements its selector at `0x43ce83`, so this case uses table slot `0x43d8d0`, pointing to `0x43cf96`.
- That branch calls `0x45e5a6` at `0x43cf97`.
- `0x45e5ad` decrements the signed word at object `+0x7c`; `0x45e5b1` keeps the frame when the result is nonnegative. Otherwise the delay is reloaded from `+0x7e`, the shape index at `+0x30` increments, and remaining frames at `+0x78` decrease. At sequence end the count reloads from `+0x7a` and the shape index wraps.
- Therefore a recurring delay value of 3 gives four process updates between frame changes. Original wall-clock process frequency and initial phase are still unresolved.

## Live presentation and limits

`MapObjectAnimation.gd` plays the ten imported textures, applies each frame's original draw origin at a fixed world anchor, and interprets the zoom as 16.16 fixed point (0.625). It uses Godot additive blending to implement the declared add-color mode. This is not a claim of pixel-identical RGB565 arithmetic.

The provisional presentation clock is 60 updates/second, giving 15 displayed frames/second. Replace it with a measured original process cadence; source delay 3 must not be mislabeled as three milliseconds or three frames/second.

Live scene tests check both fire nodes, delay before a frame change, visible texture advancement, looping and stationary world anchors. Non-headless Godot captures were inspected at frames 0 and 5. The gate flames visibly change shape, remain anchored to the torches, and use the reduced size. Exact mixed color, native tick cadence and initial relative phase remain open.

A redundant manifest blend label was removed: the original OBS mode remains the source declaration and the focused fire renderer implements additive blending directly. The rendering and full gate were rerun after that simplification.
