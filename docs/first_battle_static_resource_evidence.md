# First-Battle Static and Resource Evidence

Checked: 2026-09-01

本文件 summarizes the original-resource and script inputs used by the current first-battle remake. The active original installation is outside the repository:

```text
$HSL_ORIGINAL_DIR
```

Tracked engineering inputs live under `content/imported/hsl/` and `content/generated/hsl/`. The complete resource-member inventory is `docs/evidence_packets/resource_inventory/resource_manifest.json`.

## Battlefield map and terrain

### Visual map

`LEVEL51.SHP` is decoded as the 768×768 first-battle visual backdrop:

```text
content/imported/hsl/shared/shape_previews/battle_ui/LEVEL51.SHP.png
```

It proves the background image only. It does not by itself prove grid projection, camera crop, terrain cost, unit coordinates, object z-order, or collision.

### WRD

The compact terrain packet is:

```text
content/generated/hsl/static/hsl01/level051_terrain.json
```

Facts currently retained:

- 24×24 cells;
- 576 total cells;
- 123 blocking cells;
- original raw source basename, byte length, and SHA-256;
- tile ids and blocking bits represented in a compact grid.

The live runtime consumes this packet through `WrdTerrainTiles`. Precise path tie-break, non-level-051 bit meanings, and map-object footprint joins remain unresolved.

## First-battle objects

Current imported object contracts:

```text
content/imported/hsl/chapter01/map_objects.json
content/imported/hsl/chapter01/map_object_visibility_evidence.json
content/imported/hsl/chapter01/map_object_alignment.json
```

The current visible map-object set contains:

- 6 × `tree07.SHP`
- 2 × `FIRE01-01.SHP`
- 1 × `bar004a.SHP`
- 1 × `bar004b.SHP`

Tree/fire/bridge identities and previews are resource-derived. Bridge placement has a narrow runtime-measured alignment using curated p1-route stills. Exact anchor formula, plane order, animation, clipping, and collision footprint are not proven globally.

## Actors and control roles

Current playable slice uses original actor resources:

| Actor id | Current role |
| --- | --- |
| 001 | Leonard, player controlled |
| 021 | enemy AI |
| 026 | enemy AI |
| 023 | friendly AI |
| 024 | friendly AI |

Role evidence combines resource/script structure and user confirmation; it is not inferred from sprite ids alone.

The live scenario contains one instance of each actor for the mechanics slice. That is not the complete original battle roster or final formation.

## Actor walking resources

Manifest:

```text
content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json
```

For actor ids 001/021/023/024/026, the importer has 30 SHP images per actor:

- 5 source facing codes;
- 6 pose records per facing code.

Contact sheets are stored next to the manifest. The frames are real original-derived resources. The semantic mapping of facing codes, exact idle/walk cycle, foot anchors, transparency edge cases, playback speed, and script-motion timing are still candidates.

## Opening script

Tracked inputs:

```text
content/imported/hsl/chapter01/source_texts/STORY051.TXT
content/imported/hsl/chapter01/scripts/story051.json
content/imported/hsl/chapter01/opening_timeline.json
```

The imported action order includes music, delays, Leonard's direct motion token, seven message references, dead-message registration, section-title resource, status insertion, and win/fail-board refresh.

The one direct actor-motion token currently allowed to drive Godot presentation is:

```text
actWalkDispWait(SID_PLAYER0,1,0,-96,2)
```

This does not establish the complete enemy/friendly entry choreography, movement speed, camera curve, or meaning of every argument.

## Win/fail script

Tracked inputs:

```text
content/imported/hsl/chapter01/source_texts/winfail051.txt
content/imported/hsl/chapter01/scripts/winfail051.json
```

The script IR supports the staged scenario rules for:

- a warning check around local round value 4;
- objective switch around local round value 6;
- enemy maintenance targets for 021/026 groups;
- Leonard defeat;
- enemy-clear and arrival victory statuses;
- a next-level event.

These are resource-derived script facts. Visible turn numbering, exact predicate/handler side effects, camera timing, spawn positions, and original UI presentation still need runtime/static joins. The live PlayLoop has not yet connected these staged rules.

## Global tables

Canonical tracked source tables:

```text
content/imported/hsl/global/tables/
```

Important next-integration inputs include:

- `PLAYERS.TXT`
- `TYPE.H`
- `RANGE.TXT`
- `ITEM.TXT`
- `SPECIAL.TXT`
- `MAGIC.TXT`
- `OBJ-ALL.H`

Use parsed fields and explicit joins; do not replace them with hand-written constants or infer command meaning from icon order alone.

## UI, effects, and audio

Current compact indexes/assets:

```text
content/imported/hsl/chapter01/ui_preview_index.json
content/imported/hsl/chapter01/shape_preview_index.json
content/imported/hsl/chapter01/audio_normalized.json
content/imported/hsl/shared/shape_previews/
content/imported/hsl/chapter01/audio_normalized/
```

These prove that candidate resources can be decoded and loaded. They do not prove owner traversal, command handler identity, exact frame sequence, trigger timing, or UI lifecycle.

The old asset-browser, atlas-plan, combined-preview, verbose terrain, blocker, and projection manifests were removed because they duplicated current imported assets or preserved obsolete readback-era experiments.

## Dialogue text boundary

Current evidence:

```text
content/imported/hsl/chapter01/message_text_evidence.json
tools/hsltools/levels/message_text.py
```

Known message ids are resource-derived, but the text table is not yet resolved. The tracked negative-evidence summary records that the complete resource index has no message-named record candidate and that one checked `global.obs` was an object script with no relevant u16 message-id hits.

Negative evidence only blocks overclaiming. It does not prove that localized text is absent. Current Godot labels such as `SID_PLAYER0: message#363` are placeholders, not original dialogue.

## Visual runtime reference

All active original-runtime stills are self-contained under:

```text
docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json
docs/evidence_packets/runtime_observations/first_battle_visuals/
```

Use evidence ids and per-record claim limits. Do not revive uncurated galleries or external-video screenshots as truth.

## Reproducible checks

```sh
/opt/homebrew/bin/python3 tools/hsl.py check imported_content_check
/opt/homebrew/bin/python3 tools/hsl.py check imported_script_ir_check
PYTHONPATH=tools /opt/homebrew/bin/python3 -m hsltools.evidence.actor_walk_manifest content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json --actors 001 021 023 024 026
/opt/homebrew/bin/python3 tools/hsl.py check visual_evidence_index
```
