# First Scene Opening Choreography Packet

> evidence: runtime-measured; resource-derived; provisional · status: record-only · tools: hsl_opening_choreography_packet.py, hsltools/evidence/opening_choreography_packet.py · updated: 2026-09-01

This packet is the current input contract for opening choreography work. It is generated from current evidence and is not a claim of original parity.

## Current Truth

- Schema: `hsl_first_scene_opening_choreography_packet.v1`
- Evidence tier: `mixed-runtime-measured-resource-derived-godot-rendered-provisional`
- Direct STORY051 actor motion count: `1`
- Current Godot autoplay final event: ``
- Current Godot map object spawn count: `0`
- Opening capture segment-record stages: `0`
- Autoplay capture segment-record stages: `0`
- Opening capture camera-contract stages: `0`
- Autoplay capture camera-contract stages: `0`

## Choreography Segments

### transition_context

- Claim: Opening transition visual anchors exist, but they are not battlefield camera or actor path proof.
- Implementation status: `visual_anchor_only`
- Can drive runtime motion: `false`
- Original evidence ids: `opening_transition_rain_frame, opening_transition_castle_wall_frame`
- Godot capture stages: `opening_music, opening_delay`
- Not proven: `battlefield camera crop, actor formation, camera curve`

### upper_gate_bridge_context

- Claim: Upper gate/bridge formation frames constrain candidate camera context and foreground overlap.
- Implementation status: `candidate_camera_anchor`
- Can drive runtime motion: `false`
- Original evidence ids: `p1_route_upper_formation_11, p1_route_upper_formation_12`
- Godot capture stages: `opening_music, opening_delay`
- Not proven: `complete enemy entry path, first-control idle, continuous camera movement`

### leonard_story_walk

- Claim: STORY051 contains exactly one direct opening walk token, for SID_PLAYER0/Leonard.
- Implementation status: `current_godot_provisional_motion`
- Can drive runtime motion: `true`
- Original evidence ids: `opening_lower_formation_before_dialogue`
- Godot capture stages: `actor_walk_token`
- Not proven: `exact path coordinate semantics, speed, facing, foot anchor`

### dialogue_lower_context

- Claim: Dialogue actor/message id order is resource-derived and constrained by lower-formation original-runtime frames.
- Implementation status: `original_resource_dialogue_overlay`
- Can drive runtime motion: `false`
- Original evidence ids: `opening_dialogue_leonard, opening_dialogue_map_only_gap, opening_dialogue_soldier`
- Godot capture stages: `dialogue_message_363`
- Not proven: `original message box layout, first-control idle`

### status_and_first_control_handoff

- Claim: Status token order and Godot autoplay handoff are implemented as provisional queue consumption.
- Implementation status: `compressed_autoplay_handoff`
- Can drive runtime motion: `false`
- Original evidence ids: `first_control_action_menu, p1_route_action_menu_13`
- Godot capture stages: `status_tokens_setup, winfail_board_refresh, autoplay_first_control`
- Not proven: `original status handler side effects, exact handoff frame, first_control_idle_no_menu`

## Actor Motion Status

- `SID_PLAYER0` / `001`: `direct_story051_walk_token`; direct motion: `actWalkDispWait(SID_PLAYER0,1,0,-96,2)`; dialogue ids: `363, 367`.
- `SID_ENEMY021` / `021`: `dialogue_actor_only_no_direct_walk_token`; direct motion: `none`; dialogue ids: `1101`.
- `SID_ENEMY023` / `023`: `dialogue_actor_only_no_direct_walk_token`; direct motion: `none`; dialogue ids: `364, 366`.
- `SID_ENEMY024` / `024`: `dialogue_actor_only_no_direct_walk_token`; direct motion: `none`; dialogue ids: `365, 364`.
- `SID_ENEMY026` / `026`: `known_first_scene_actor_no_story051_motion_token`; direct motion: `none`; dialogue ids: `none`.

## Missing Original Truth

- `first_control_idle_no_menu`
- `complete_enemy_gate_entry_paths`
- `complete_friendly_entry_paths`
- `continuous_camera_curve`
- `original_delay_time_scale`
- `dialogue_text_source`
- `actor_foot_anchor_and_path_timing`

## Forbidden Inferences

- Do not infer enemy or allied entry paths from dialogue speaker tokens alone.
- Do not treat p1_route_upper_formation_11/12 as first-control idle truth.
- Do not treat opening_dialogue_map_only_gap as proof that player control has started.
- Do not treat the current Godot token overlay as original UI or original handler timing.
- Do not convert EVEF placement candidates or map-object anchors into final actor foot positions.
