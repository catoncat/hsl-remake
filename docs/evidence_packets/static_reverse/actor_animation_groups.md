# Original actor animation groups

> evidence: resource-derived; provisional · status: live · functions: 0x446c40, 0x45e525, 0x45e5a6 · updated: 2026-09-05

Extracted exact original PAK member `@:\data\SHAPEDEF.TXT` to `content/imported/hsl/global/tables/SHAPEDEF.TXT`. For SID_PLAYER0 and the currently imported Enemy021/023/024/026 definitions, the table explicitly maps:

| Field | Source group | Frame count |
| --- | --- | --- |
| stand | 0 | 6 |
| walk_up | 3 | 6 |
| walk_down | 1 | 6 |
| walk_left | 4 | 6 |
| walk_right | 2 | 6 |

Previous importer incorrectly labelled all five source groups as walking directions. Group 0 is a standing sequence, so the former live call walk/0 animated standing poses during displacement.

The importer reads the named fields and frame counts from SHAPEDEF.TXT, records its digest, and rejects missing or unsupported mappings. Numeric `facing_code` is retained solely as the historical source-file group index; named animation keys carry the actual semantics. ActorRuntime selects up/down/left/right at each path segment and returns to stand/0 on arrival. No new gameplay direction state is owned by the actor.

`0x446c40` selects start/count pairs from per-actor shape definitions and calls engine sequence helper `0x45e525`; the delay argument and looping behavior are now traced below; real-time tick frequency remains unconfirmed. The resource table proves state/direction-to-resource association, not movement speed, original timeline cadence, pose blending, or full visual parity. A dominant-axis choice for any non-grid diagonal opening segment remains provisional; battle paths use cardinal grid edges.

Regressions cover right→up corner resources, initial and final standing resources, completion stopping walking frame updates, and original per-frame draw origins. Runtime captures verify displaced walking poses. The six standing frames now loop in the live scene using the manifest's provisional 8 fps.


## Standing loop and delay

Static-derived on EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`:

- State 0 at `0x442139..0x442151` selects the standing sequence with delay 10; nonzero movement states use delay 2 at `0x442153`. `0x4455ee..0x445616` has the corresponding second actor path.
- `0x446c40` selects a shape start/count pair. State 0 uses the first pair at `0x446c64..0x446c6e`; the helper passes the supplied delay unchanged to `0x45e525`.
- `0x45e525` stores current/start frame, current/reset count, and current/reset delay. `0x45e5a6` decrements delay and advances only below zero, then reloads it. At the end it restores the frame count and subtracts that count from the frame index, thereby looping.
- Thus the examined standing path uses 11 animation updates per frame, versus 3 for walking on this path. These counts do not establish updates per second; the existing manifest 8 fps remains provisional and is not a native frequency claim.

Live `ActorRuntime` advances standing frames from its process delta using the existing manifest fps and preserves fractional elapsed time. State changes reset that elapsed time; the idle clock does not touch a walking sequence. Frame drawing continues through the existing original SHP anchors, and there are no standing footstep cues. This is a small direct presentation change with no credible additional abstraction to remove.

Verification covers all five actor types: hold duration, frame advance, complete six-frame wrap, fixed world foot point, walking isolation, and return to the standing loop. A real 640×480 Godot recording (`ignored/idle-review/idle.mp4`) shows Leonard at world `(496,560)` while standing sources progress through frames 1, 2, 4 and 6 in successive samples. Rendered frames were inspected; the original cadence and complete sprite/color parity remain unproven.
