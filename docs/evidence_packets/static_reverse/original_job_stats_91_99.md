# Original job 91/99 stat branches

> evidence: static-derived · status: record-only · functions: 0x448370, 0x448800, 0x448840 · tools: hsltools/probes/job_stats.py · updated: 2026-09-20

## Evidence scope

This packet is **static-derived** from the original executable's complete refresh caller at `0x448840`, with the job cap lookup at `0x448370` and the common post-branch clamp/equipment tail in the same caller. The switch in `0x448840` has separate cases `0x5b` (job 91, jobElfMan) and `0x63` (job 99, jobDarkAngel); neither case aliases the job 90 or job 98 arithmetic. The case values below preserve the integer division and cap order visible in the decompilation.

The existing native actor packet `docs/evidence_packets/static_reverse/original_campaign_actors.json` is also **runtime-measured** evidence from the bounded refresh probe. Fresh representative executions used the same probe backend with the original `hsl01.exe`:

| actor | job | input | magic_attack | resist_by_type (earth/water/air/fire/mind) | normal-return instruction counts |
| --- | ---: | --- | ---: | --- | --- |
| 050 | 99 | PLAYERS initial row, level 1, source equipment | 69 | 80/71/59/80/80 | 608, 606 |
| 058 | 91 | PLAYERS initial row, level 1, source equipment | 139 | 80/80/80/80/80 | 605, 603 |

The representative command was run through `tools/hsltools/probes/job_stats.py`'s `--execute` backend against the SHA-locked original executable. Both executions returned normally and the second refresh repeated the first result after deliberately stale derived fields were injected.

## Dispatch and shared tail

- `0x448840` clears derived fields, selects the job case from the actor job code, then applies source additions, equipment slots, current HP/MP clamps, resistance clamp 0..80, movement clamp 0..12, and the shared EXP threshold. Source mode bit `0x10000` gates only the HP level term.
- `0x448370` loads the four caps from the job-indexed cap table. Job 91 selects cap-table row 11; job 99 selects row 19.
- The attack level bonus remains the shared piecewise result from `0x448800`; it is added after the branch's attack arithmetic.

## Job 91: jobElfMan

The branch begins with a magic-attack source increment of 15, then uses these formulas before source/equipment additions and the shared final clamps:

| field | formula |
| --- | --- |
| caps | cap-table row 11: `str=430, dex=610, mind=1250, con=500` |
| max HP | `str/5 + hp_level + 150*con/100` |
| max MP | `120*mind/100 + con/2` |
| attack | `20*dex/100 + 96*(str/3)/100 + 6` |
| defense | `36*str/100 + mind/8 + dex/4 + con/4` |
| magic attack | `source_magic + 15 + q + 55`, where `q=40*mind/100 + 2*level`, and if `q > 50`, `q=(q-50)/2 + 50` |
| speed | `94*dex/100` |
| earth resist | `min(64, con/3 + 50*mind/100)` |
| water resist | `min(64, 56*mind/100 + con/4)` |
| air resist | `min(64, con/3 + 34*mind/100)` |
| fire resist | `min(64, 50*mind/100 + con/4)` |
| mind resist | `min(64, con/3 + 42*mind/100)` |

## Job 99: jobDarkAngel

The branch begins with a magic-attack source increment of 26, then uses these formulas before source/equipment additions and the shared final clamps:

| field | formula |
| --- | --- |
| caps | cap-table row 19: `str=560, dex=710, mind=530, con=690` |
| max HP | `str/8 + hp_level + 110*con/100` |
| max MP | `36*con/100 + 90*mind/100` |
| attack | `42*dex/100 + 99*(str/2)/100 + 9` |
| defense | `dex/3 + mind/5 + 22*str/100 + con/4` |
| magic attack | `source_magic + 26 + min(86, 28*mind/100 + 26 + level)` |
| speed | `88*dex/100` |
| earth resist | `min(56, 30*mind/100 + con/4)` |
| water resist | `min(56, con/3 + 60*mind/100)` |
| air resist | `min(56, 40*mind/100 + con/4)` |
| fire resist | `min(56, con/3 + 46*mind/100)` |
| mind resist | `min(56, 72*mind/100 + con/2)` |

All divisions are integer divisions in the original 32-bit arithmetic. The source resistance row and equipment effects are added after these branch values; the common tail clamps the final five resistance fields to 0..80.

## Claim limit

This packet establishes the job 91/99 refresh formulas and the two bounded representative returns. It does not establish class-change transactions, native global object scheduling, full battle execution, or original gameplay equivalence. The current remake still uses its explicit progression and equipment policies around this shared refresh entry.
