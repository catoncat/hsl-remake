# Original first-battle attack animation

> evidence: resource-derived; provisional · status: record-only · tools: hsltools/assets/combat_animation.py · updated: 2026-09-05

2026-09-05, resource-derived.

Original PAK `DATA\ANIMAL.TXT` maps SID_PLAYER0 and SID_ENEMY021/023/024/026 to `ANIMAL\Pnnn_001.SHP`, five frames each. `action` entries explicitly select frames 0,1,2,3 with delay counts 12/8/3/30 for Leonard and 12/3/12/30 for the four other types. The fifth frame was visually reviewed for all five actors: each shows recoil, loss of balance or a pained expression. The remake now binds it to received hits; this is a documented visual interpretation, not a recovered native handler. `k_action` is a hit movement flag; its left/right value currently informs provisional facing, checked against the rendered sprites.

Reproduce: `python3 tools/hsl.py generate combat_animation`; `--check` verifies source digest, original delay sequence and generated PNG digests. Imported frames preserve SHP draw origins. Live presentation uses 60 ticks/sec and 0.55 actor scale over original BG051; these are remake choices, not original timing/layout claims. Existing attack/miss/death audio remains active. ANIMAL fh_shape explicitly binds PATT001, PATT021 and PATT023; these flashes now appear at the final strike pose. The other two definitions have no active fh_shape field. Recoil/dodge and flash placement/duration are remake choices. Audio and damage feedback trigger once at the strike pose, including counter clips; Native hurt pose semantics remain pending; current alive recovery and lethal fade are remake choices.

`obj-051.obs` Object 199 (BG) binds `ANIMAL\BG051.SHP`, one frame. The imported 640×320 image now supplies the first-battle cut-in background, displayed without stretching at y=80. Dark letterboxing and bottom result placement are remake layout decisions. The importer/checker covers its PNG digest.
