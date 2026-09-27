# Runtime Observations

> evidence: runtime-measured · status: record-only · updated: 2026-09-08

This directory contains only curated, tracked observations that current development depends on.

## Visual contract

- `first_battle_visual_evidence_index.json`
- `first_battle_visual_evidence_index.md`
- `first_battle_visuals/`

The index is the authority. File names are not semantics; use each record's `status`, `visual_state`, `use_for`, and `not_for` fields. `move_overlay_primary` is mandatory for spatial-contract work.

## Opening contract

- `first_scene_opening_choreography_packet.json`
- `first_scene_opening_choreography_packet.md`

The packet combines the opening timeline, curated stills, actor/map-resource evidence, and the current Godot capture status. Missing generated capture output is represented honestly as `missing_generated_capture`; it is not silently inferred.

New raw screenshots, video, and traces stay outside tracked data or under temporary `ignored/`; only compact conclusions are promoted here.
