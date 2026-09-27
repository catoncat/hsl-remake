# 第二战模板属性补充探针

> evidence: static-derived; provisional: synthetic initialization · status: record-only · functions: 0x448840 · tools: hsl_native_stats_probe.py · updated: 2026-09-10

Evidence: `static-derived`; synthetic initialization remains `provisional`.
Checked 2026-09-10. This extends the existing bounded `0x448840` probe with
the level-52 templates needed for M2. It does not claim native battle-start
levels, NPC adjustment, status effects, or final faction/control semantics.

Reproduce with the same ephemeral Unicorn dependency used by the first-battle
packet; nothing is installed into the project environment:

```sh
uv run --with unicorn==2.1.4 python tools/hsl_native_stats_probe.py \
  --actors 1 21 23 24 25 26 69 \
  --output ignored/native-stats/second-battle.json
cmp ignored/native-stats/second-battle.json \
  docs/evidence_packets/static_reverse/second_battle_template_stats.json
```

The five existing first-battle actor results are byte-for-value identical to
`first_battle_template_stats.json`. New equipped synthetic results are:

| Template | Source mode | HP | MP | Attack | Defense | Speed | Hit |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 025 | `pmEnemy` | 91 | 24 | 58 | 46 | 16 | 92 |
| 069 | `pmPlayer` | 40 | 0 | 54 | 38 | 42 | 98 |

Actor 025 is the `SID_ENEMY025` checked by `WINFAIL052` and has a directly
joined EVEF/object placement candidate. Actor 069 is deliberately not promoted
to a second-battle faction solely from its name or `defProcEnemy` object process:
its PLAYERS template says `pmPlayer`, while its map object uses sprite 022. That
cross-source mismatch remains explicit and is excluded from the first M2 roster
until the control/identity mapping is resolved or a deliberate remake role is
chosen.
