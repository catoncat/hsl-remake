# 站立型敌方精灵来源

> evidence: static-derived · status: live · tools: hsl_actor_walk_manifest.py · updated: 2026-09-24

## Source

`content/imported/hsl/global/tables/SHAPEDEF.TXT` has the `SID_ENEMY060` definition:

- `stand = SHAPE\\60-10001.SHP` and `stand_num = 14`
- `walk_up`, `walk_down`, `walk_left`, and `walk_right` all repeat `SHAPE\\60-10001.SHP`; the definition does not provide five distinct `[0-4]0001` walk groups
- the original PAK contains `@:\\shape\\60-10001.SHP` and the related numbered records, but this slice consumes only the declared standing source frame and does not reinterpret the numbered records as movement or attack frames

This is `resource-derived`. The SHP payload draw origin is read from the existing static SHP header contract (`static-derived:0x45fa75-0x45fab4`) and its pixels are decoded into the Level 59 actor manifest.

## Remake read

`tools/hsl_actor_walk_manifest.py` has an explicit standing-only path. It emits one frame, `60-10001.SHP`, with an idle sequence and no walk sequences. `ActorRuntime` retains the loaded frame when a state has no sequence, so the unit does not borrow another actor's animation. Enemy060's source `move_point = 0` is retained by the generated actor template and the formal battle. Hit flashing remains the shared actor presentation behavior; combat animation is not inferred from this standing source.

Level 59 binds `obj_Story_Level_Enemy60` / `SID_ENEMY060/1` to PlayLoop unit `actor060_1`. The old static-object HP bridge is not used. The unit is targetable through the regular combat selection and its HP condition is consumed by WINFAIL059.

## Limits

The original `defProcEnemy` object registration, native collision rectangle, standing direction, frame timing, attack animation and scheduler are not established by this packet. The remake uses one source standing frame, source move point zero, and the existing hit-flash contract as explicit `provisional` presentation reads.

## Level 37／80 additions (R6-L10)

- `SID_ENEMY068` (level 80 怨念體): `stand = SHAPE\68-001.SHP`, all walk fields repeat it — the same standing-only path, one frame `68-001.SHP` (77×76 px), decoded into the level-80 actor manifest. The EVEF record 45 object (`obj_Data7 = 68`, `obj_Mode engADDCOLOR`) is a PlayLoop unit because PLAYERS 68 now has a generated template (`hsltools.sources.actor_walk_frames.standing_actor_code`); an EVEF standing enemy without a template (level 18's 門 Enemy100, the 12／26 hull pieces) stays a stand sprite. The additive blend is not reproduced (`provisional`).
- `SID_ENEMY067` (level 37 gem): `stand = MAGIC\MIN12_11.SHP` (`stand_num 3`), walk fields `MAGIC\MIN12_21.SHP` (the switched-off look `actSetPlayerWalkShape` selects). The actor manifest takes the declared standing frame only (13×13 px); `actSetPlayerWalkShape`／`actRestoreShape` stay presentation requests without a frame swap (`provisional`).
- `SID_ENEMY066` (level 37 guardian): the SHAPEDEF block for its own SID declares 050's five walk groups (`SHAPE\050-[0-4]0001.SHP`), so `_shape_fields` falls back to `code = SID_ENEMY066` when no stand prefix carries the number and the walk manifest entry `066` holds 050's frames.
