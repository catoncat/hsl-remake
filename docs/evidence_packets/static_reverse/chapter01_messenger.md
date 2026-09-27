# First-battle messenger

> evidence: resource-derived · status: record-only · updated: 2026-09-05

2026-09-05, resource-derived.

`obj-051.h` assigns `obj_Story_Level51_Object1 = 100`. Original PAK member `@:\data\obj-051.obs`, Object 100, names SHAPE\021-00001.SHP, ENEMY021_Total, defProcEnemy, SID_ENEMY021, extra-data ID 21. Reproduce by extracting that member with `hsl_resource_scanner.find_decoded_paks_packages`, `find_paks_record_by_name`, and `read_paks_record_bytes`, then selecting `obj_code = 100`.

WINFAIL051 inserts Object 100, changes its ID to 10000, walks displacement `(32,32)`, speaks message 368, and walks back to `(267,209)` before deleting it. The remake uses the current exit marker as the gate anchor, preserves that displacement, uses imported 021 directional walk frames and default footstep sound, and waits for arrival/exit before continuing dialogue. Half-second walk and camera cut/restore are presentation choices; native absolute coordinate mapping and camera curve are not claimed. The actor is visual-only and does not enter the battle roster. The subsequent `actWalkAndDeleteWait,SID_ENEMY026,1` and `SID_ENEMY021,1` commands now drive one departure each. Current selection is the first living matching roster member; native ordinal lookup among defeated/reinforced actors remains unconfirmed. Terrain routing, ignoring transient unit occupancy during the paused scene, uses the existing tactical path solver. Departure removes a living actor without recording damage or a kill.
