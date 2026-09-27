# First-battle imperial mage magic

> evidence: resource-derived · status: record-only · tools: hsltools/data/mage_magic.py · updated: 2026-09-05

2026-09-05, resource-derived definitions and assets; live mechanics and staging remain a remake implementation.

`PLAYERS.TXT` character 26 has magic_fire=幻火, magic_wind=風刃 and ai_att_magic=95. `MAGIC.TXT` FIRE/AIR magicCode01 names RESOURCE entries 169/162; both cost 8 MP, target range3CellCircle, affect range0Cell and hit at 96%. Damage fields are 18–32 and 12–26, respectively. Raw magic_point=5 is a base field, not established final MP.

`effects.txt` effCode16 inserts AirWave1/2 followed by AirBlade1/2; effCode23 inserts FlyDrop, FireBomb and FireBomb2. `global.obs` binds their SHP sequences and WIND0002, WIND0001 and BOMB0004 WAVs. `tools/hsltools/data/mage_magic.py` imports these bindings, 24 source images and three WAVs with source/output digests. `--check` compares definitions and object/script bindings against the preserved source and verifies converted asset hashes without requiring the original installation.

Live behavior: a caster with enough MP rolls the source 95% magic preference, selects an affordable spell, stays put when a hostile target is in the three-cell diamond, otherwise uses a reachable casting cell requiring minimal displacement. With no legal cast or insufficient MP it continues the ordinary AI path. Spell resolution consumes MP even on a miss, commits one AI turn and writes the existing last_combat receipt; no second battle state is introduced. Reinforced mages inherit the same initial resource profile.

Remake choices: initial MP 30 from the unadjusted native-template probe without regeneration, random choice between affordable spells, and no magic counter. Damage now uses floor(table roll × (100 - elemental resistance) / 100), minimum 1, with resistance clamped to 0..80; physical armor does not reduce magic. The resistance values come from PLAYERS (missing values modeled as zero) and TYPE.H element indices. Final native damage and AI selection formulas are not recovered. The cast uses original actor/effect images and sound in a compact 1.5-second cut-in, with impact at 0.65 seconds. This is a modern staging of local map-effect resources, not the native effect interpreter; particle counts and movement handlers are not reproduced.

Rendered wind/fire impact screenshots were inspected under ignored/magic-review/. Focused tests cover range-three casting without needless movement, both spells, MP consumption, MP exhaustion leaving state unchanged, and impact/release timing. A simplification experiment removed the separate magic audio player: mutually exclusive queued skill/magic clips now use one ability audio player, restoring each clip's source before playback. The final gate validates that shared player alongside the skill path.
