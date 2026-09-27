# Original scope inventory versus remake coverage

> evidence: resource-derived · status: record-only · tools: hsltools/data/scope_inventory.py, hsltools/data/story_token_coverage.py, hsltools/data/winfail_coverage.py, hsltools/levels/battle.py · updated: 2026-09-27

**Claim boundary.** Counts only. The original-side numbers are `resource-derived`: record names and INI-style
section headers read from `hsl.pak` by `tools/hsltools/data/scope_inventory.py`. The remake-side numbers come from the
tracked `content/battles/campaign.json` and the scenario files it references. Nothing here establishes semantics
for unimplemented levels, and nothing here claims original equivalence for implemented ones (see
[机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md) for that).

Machine-readable output: `content/generated/hsl/static/hsl01/scope_inventory.json` (schema `hsl_scope_inventory.v1`). The remake-side counts below are a snapshot; current counts are in that JSON (`python3 tools/hsl.py check scope_inventory`).

```bash
PYTHONPATH=. python3 tools/hsl.py generate scope_inventory                 # rebuild from the PAK (needs $WINEPREFIX)
python3 tools/hsl.py check scope_inventory                      # offline: remake side vs campaign.json + internal totals
PYTHONPATH=. PYTHONPATH=tools python3 -m hsltools.data.scope_inventory --check --rescan  # also compare original-side counts with the PAK
```

## Original scope (hsl.pak, 5,600 records)

| Range | Levels (LEVEL*.BIN) | Battles (with WINFAIL) | Story-only (STORY without WINFAIL) | actMessage tokens |
| --- | --- | --- | --- | --- |
| Main story, level 0–99 | 72 | 47 | 22 | 884 |
| Battle stubs, level 500–578 | 78 | 78 | 0 | 0 |
| Specials, level 900+ | 7 | 5 | 0 | 31 |

Three main-range level bins (0, 49, 54) have neither STORY nor WINFAIL scripts; they are counted as levels but not as
content. The 500-range battle stubs carry no dialogue and are read as generic encounter maps (`provisional`: their
trigger route — random encounters or free battles — is not established by this scan).

Global tables (INI sections): MAGIC.TXT 39 `[magic]`, SPECIAL.TXT 60 `[special]`, ITEM.TXT 239 `[item]`,
PLAYERS.TXT 66 `[character]`, TRACK.TXT 44 `[track]`, TOWNDEF.TXT 191 `[town_event]` + 62 `[item]` shop lists,
`bigmap.dat` 5,600 bytes. The world layer (bigmap / TOWNDEF / TRACK) has no remake counterpart yet.

## Remake coverage (campaign.json at the time of this packet)

| Measure | Value |
| --- | --- |
| Main-range levels reachable through the campaign | 5 of 72 (51, 52, 58, 60, 53) |
| Main-range battles with a battle scenario | 2 of 47 (51 playable; 52 `product-opening-provisional`) |
| Story-only scenes / opening previews | 2 (58, 60) / 1 (53) |
| actMessage tokens inside registered levels | 63 of 884 |

`--check` recomputes the remake side from the current campaign registry, so these numbers move with each
registered level without hand editing; only the original side needs `--rescan`.

## Ordering rationale (planning input, not evidence)

The remaining work is ranked by how many original levels each item unlocks per unit of verification cost:

1. **Script VM coverage** — every level runs on the same 128 action tokens; the opening compiler maps ~37 and
   win/fail rules are still hand-written per level (51, 52, 53). A data-driven winfail interpreter plus opening-token
   coverage is the multiplier for all 47 battles and 22 story scenes. Coverage is measured by
   `tools/hsltools/data/winfail_coverage.py` and `tools/hsltools/data/story_token_coverage.py` once they land.
2. **Level-parametrized scenario generation** — done: `level_battle:N` (`tools/hsltools/levels/battle.py`) assembles every
   main-line battle, 51／52／53 included since S5／S11, from seed + manifest chain + `content/battles/levels/NNN.json`, without per-level Python.
3. **Level 53 as the first non-Leonard battle** — proves controlled-unit generalization (PLAYERS 002 template) and
   escape-style win/fail on the existing PlayLoop.
4. **Job model and roster** — 20 jobs / 66 characters versus 4 modeled jobs (80/85/90/94); level 1 already needs
   jobBowMan 83 (the controlled 琥, PLAYERS row 003), jobThief 88 (028 raiders) and jobWingWarrior 92 (036, flying),
   plus the pmNPCPlayer villagers 061/062. Owned by the source-research line (static evidence first).
5. **World layer** — from level 1 onward the town / big-map layer is the flow controller (`actSetTownExecEvent`,
   TOWNDEF, TRACK); it is a new subsystem, scheduled after the battle chain generalizes.

Everything above item 4 is presentation-line scope; items 4–5 need static evidence before implementation.
