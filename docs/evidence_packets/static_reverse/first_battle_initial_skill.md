# Leonard's initial technique

> evidence: resource-derived; provisional · status: live · tools: hsltools/data/first_skill.py · updated: 2026-09-05

2026-09-05 — resource-derived. Rebuild with `python3 tools/hsl.py generate first_skill`; validate the imported result with `--check` without the original installation.

`PLAYERS.TXT` character 1 has `special_other=氣刃斬` and raw `stamina=20`. `mag-spc.h` maps that name to bit 1 in the Other special group. `SPECIAL.TXT` magicOTHER/magicCode01 names RESOURCE entry 137, 氣刃斬. The row supplies range2Cell, effect_range range0Cell, expend 1, damage 36–54, hit_ratio 98, attackpow_ratio 100, specCode01/specCode02. These are source fields, not proof of final damage or an ST cost of 1.

The original PAK `data/effects.txt` explicitly associates specCode01 with `MAGIC/SP00_001.SHP`, object 410 and `WAV/SP01-001.WAV`. specCode02 inserts object 411 after 20 delay counts, waits 10, calls aniProcessHitMiss, inserts hit objects 412/413, then waits 60 before aniShowHitResult. `global.obs` maps those objects to two SP01_001 frames, five SP01_011 frames and five SP01_021 frames, with delays 4/1/3/6 respectively. The two moving blade objects share the same image frames but different movement action codes.

The importer preserves original scripts/object definitions, source and output hashes, SHP draw origins, the native range matrices, thirteen PNGs including background, and decoded WAV under `content/imported/hsl/shared/first_skill/`. Manual image inspection confirms the horizontal red background, paired cyan blade shapes, cyan impact burst and fading orange particles. The temporary contact sheet lives under `ignored/skill-review/`.

Historical September5 boundary: expend-to-ST conversion was then unresolved and 20ST was a remake setting. **September13 successor:** [original_skill_resources.md](original_skill_resources.md) proved and executed the `20×expend` getter and eligibility gate. Live SkillResourceRules replaces the duplicate scenario multiplier. **September16 successor:** [original_stamina.md](original_stamina.md) replaces fixed gain5 with the original attack/receive, equipment and cap60 helper, supported by168 complete returns. Approved zero opening ST remains a separate remake choice. The cost successor also records the half-MP threshold/debit discrepancy. Damage and complete effects remain provisional; no special counter is introduced. The older cut-in/particle description belongs to the September5 implementation; current presentation is tracked in PROJECT and later evidence packets.
