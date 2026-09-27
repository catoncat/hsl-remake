# First-Battle Core Logic Evidence

Checked: 2026-09-17（普通／武器／暴击和氣刃斬数值、最终EXP及当前入口更正；更详细边界按机制矩阵）

本文件是第一战核心规则的人工可读摘要。机器权威入口：

```text
content/generated/hsl/static/hsl01/core_logic.json
content/generated/hsl/static/hsl01/index.json
tools/hsltools/checks/core_logic.py
```

Raw 反编译不跟踪；需要复核时使用 `tools/hsl_exe_static_export.py` 或 `tools/hsl_exe_decompile.py`，输出到 `ignored/static/hsl01/`。

## Current implementation map

| Recovered surface | Static anchor | Current module | Live status |
| --- | --- | --- | --- |
| live stat refresh / field join | `0x448840` | `ProgressionRules` | Leonard/SwordMan growth and current equipment refresh live |
| equipment effects and replacement | `0x448420`, `0x436f30`, `0x437020` | `EquipmentRules` + PlayLoop atomic operation | supported numeric equipment live; [scope](evidence_packets/static_reverse/original_inventory_equipment.md) |
| ordered backpack | `0x436e30`, `0x436e80` | `InventoryRules` | eight slots, first-empty insertion, left-compacting removal; original UI lifecycle still partial |
| discard action / item-window close | `0x438868`, `0x4389ce`, `0x444c19` | PlayLoop + Runtime item callback | discard preserves action; original held-return/full-bag closure is static-derived; [scope](evidence_packets/static_reverse/original_item_actions.md) |
| continuous Give / full-bag exchange / action policy | `0x438cbf`, `0x444def`, `0x444bff`; Use118→4 | `InventoryRules.exchange`, `ActionBudgetRules`, PlayLoop Give session | atomic inventories; same-code comparison and one charge at session exit; [scope](evidence_packets/static_reverse/original_give_exchange.md) |
| command / movement phase / action handoff | command tables; `0x44429b`, `0x4454a5`, `0x443c1a/0x443c38` | ActionBudgetRules + PlayLoop outcome + read-only Runtime | cancel reselects movement; attack/miss/special end even unmoved; one player/AI advance; [limits](evidence_packets/static_reverse/original_action_state_machine.md) |
| native eligible queue selection | `0x4074a0` | bounded development-only probe | eight complete no-rebuild returns; original readiness differs from product bookkeeping; no runtime EXE dependency |
| MP/ST resource costs and availability | `0x409890/0x409980`, `0x408fe0/0x409040`, MP debit `0x442ba9..0x442bcf` | SkillResourceRules + PlayLoop player/mage quote | 32 original helper cases; debit block distinguished from full return; no negative resources; [scope](evidence_packets/static_reverse/original_skill_resources.md) |
| skill function / target coverage / enumeration | `0x409850/0x409870`, `0x444e9e/0x44504a`, `0x4100e0/0x4104d0` | SkillTargetRules + source TYPE/RANGE | current Attack-only player/AI targeting shares exact source ranges; 32 original one-cell helper fixtures, partial role/status semantics; [scope](evidence_packets/static_reverse/original_skill_targets.md) |
| shared supported skill resolution / initial declaration | inherited resource/target anchors; tracked PLAYERS/MAG-SPC aliases | SkillResolutionRules + PlayLoop `_resolve_skill` | one atomic player/AI effect path; registered native numeric policies, PLAYERS archive comparison unresolved; [original transaction](evidence_packets/static_reverse/shared_skill_resolution.md) and [new Qi Blade](evidence_packets/static_reverse/original_ordinary_special.md) |
| hit chance | `0x409a60`, queued draw `0x403ef8/0x403f47` | `CoreCombatRules.hit_chance` / shared strike | actual miss enforced with 0–99 draw; full RNG sequence still partial |
| poison / no-magic / antidote | `0x443ade`, `0x441f69`, `0x40b910`, `0x43eaf0`, `0x40a2e6` and shared infliction helpers | StatusEffectRules / StatusApplicationRules / ItemUseRules / single PlayLoop handoff | infliction, immunity, overlap, expiry and cure live; actor flag4 is paralysis, not queue readiness; [scope](evidence_packets/static_reverse/original_status_application.md) |
| ordinary damage, weapon bonus, critical and Qi Blade | `0x409be0`, `0x409af0`, `0x403f39`, `0x40a7b0` | CoreCombatRules / SpecialDamageRules / shared transaction | 148 ordinary/helper returns +34 suffixes;20 special returns +24HP applications, [boundaries](evidence_packets/static_reverse/original_ordinary_special.md) |
| combat resolve / counter gate | `0x4423c0` | `CoreCombatRules.attack_back_triggered` + PlayLoop exchange | live normal-strike path |
| queue rebuild by live speed | `0x407340` | `CoreTurnQueue.rebuild` | live |
| current queue object | `0x407540` | `CoreTurnQueue.current` | live |
| queue advance | `0x407510` | `CoreTurnQueue.advance` | live |
| end-turn queue advance / readiness metadata | `0x407510`; `0x40b910` is a separate status-duration reference | `CoreTurnQueue.end_turn` | live simplified handoff; clearing remake action_ready does not establish full native status tick |
| BCmd menu builder | `0x43ea30` | `CoreTurnQueue.build_command_menu` | live identity surface |
| AI action selection | `0x40c570` | AIDecisionRules / shared PlayLoop action | live ordinary/magic/special selection; 96 original normal returns |
| AI target selection | `0x40bb80` | AIDecisionRules / source profiles | live source selectors; 104 original normal returns; reachability composition provisional |
| AI call broadcast / adoption | `0x40bee0`, `0x43f6c2..0x43f74e` | AICallRules / PlayLoop unit target ID | live ordinary-first fallback, exact side/circle broadcast; 28 normal returns + 12 prefixes; lifecycle cleanup explicit remake policy |
| AI actor process entry | `0x43ede0` | compact packet only | not live |
| engine cross-object dispatch | `0x45f5f7` | compact packet only | not a battle speed queue |
| WRD load | `0x46bb65` | generated terrain packet | live data input |
| WRD reachability | `0x40f8b0`, `0x40f5d0` | `TacticalGridRules` candidate model | live provisional |
| WRD blocking attribute | `0x40ed50` | `WrdTerrainTiles` | live `0xff` blocking |

## Resolved field joins

Current compact evidence joins live actor fields as:

- `+0x4c` → `str`
- `+0x50` → `dex`
- `+0x54` → `mind`
- `+0x58` → constitution/vitality family

The first two are consumed by current combat calculations. Naming is tied to the stat-refresh path, not guessed from table column order alone.

## Hit chance

Current implementation follows the recovered `0x409a60` family:

1. Take half the attacker/defender dex delta.
2. Clamp that delta to `[-30, 30]`.
3. Add it to live hit ratio.
4. Clamp the raw chance to `[20, 100]`.
5. Subtract defender avoid ratio.
6. Keep a minimum final chance of 10.

The live PlayLoop uses `CoreCombatRules.resolve_attack` for player and AI strikes. It samples damage first (`0x44250d`), then raw rand(100) (`0x403ef8`); raw draw at or above the queued percentage misses (`0x403f47`). On a hit, critical chance has its own one-based draw. Misses apply zero damage and consume the action. Original instructions use the hash-locked local EXE; current replay evidence is in [ordinary/special](evidence_packets/static_reverse/original_ordinary_special.md). Counter, critical and contribution EXP are now composed in the live path, while native global PRNG identity and extra-strike passives remain separate. The queued percentage adds the actor accumulator and clamps100; ordinary misses add trunc(base chance/10), positive actual damage clears it. The flags-bit-1 exemption is outside this path. Pure previews retain a deterministic source; live resolution supplies an RNG.

## Damage

`CoreCombatRules.preview_damage` models the independently executed `0x409be0` helper; old `0x409bca` is padding, not a valid entry:

- base attack minus live defense;
- weak/non-positive damage bands;
- a clamped strength delta term;
- bounded random noise terms;
- optional weapon variance/resistance contribution;
- a small positive fallback when the result would be non-positive.

The positive-domain branches, sign handling, RNG order including rand0, weapon exclusive/equal/reversed bounds and resistance have normal original returns. Critical impact and raw fallback have bounded suffix evidence. `queued_damage` is the original pre-critical stamina input; actual capped HP loss supplies feedback and [final EXP](evidence_packets/static_reverse/original_experience.md). Source-zero counter/critical rates refresh to12/8 before equipment, while nonzero rates (Leonard critical14) are retained. Full initialization, unknown passives and exact native presentation remain separate; see [formulas and limits](evidence_packets/static_reverse/original_ordinary_special.md).

## Turn queue and commands

`CoreTurnQueue` uses a descending `live_speed` insertion sort and preserves source addresses in summaries. Current unresolved points:

- equal-speed tie-break;
- exact round/wait delay semantics;
- complete BCmd post-select handler mapping;
- relationship between battle queue eligibility and broader engine object scheduling.

Do not conflate the battle queue with `0x45f5f7`: that address is an engine cross-object process dispatcher using priority buckets, not proof of player/friendly/enemy battle order.

Current BCmd numeric identities from the static menu table:

| ID | Current name |
| ---: | --- |
| 110 | move |
| 111 | attack |
| 112 | item |
| 113 | wait |
| 118 | magic |
| 119 | special |
| 122 | status |

Move, Attack, Wait, Item and Status are live. Magic and Special are offered only to actors with supported source-owned abilities and obey the shared resource/status gates; Leonard starts with0ST and must earn his special's20ST cost. Current visible commands come from `BattlePlayLoop.IMPLEMENTED_COMMANDS`.

## WRD terrain

`level051.wrd` is represented by:

```text
content/generated/hsl/static/hsl01/level051_terrain.json
```

Current facts:

- `WORL` grid: 24×24, 576 cells.
- 123 cells have the blocking attribute (`0xff` high byte in the decoded source model).
- Level 051 has base step cost1 and separate live-occupant clearance cost. The [original four-neighbor flood](evidence_packets/static_reverse/original_movement.md) records arrival before charging onward adjacency; cliff blocking is distinct from low-bit obstacle flags.

Still unresolved:

- equal-cost path tie-break;
- meaning of unused middle bits for other maps;
- exact original occupancy and map-object footprint joins;
- actor-specific terrain capability.

## AI evidence boundary

The former nearest-target scaffold has been replaced by source profiles and the recovered target/action kernels; see [original_ai_decisions.md](evidence_packets/static_reverse/original_ai_decisions.md). Call broadcast and ordinary-search fallback now also feed the same action transaction, with original normal-return versus prefix boundaries documented in [original_ai_calls.md](evidence_packets/static_reverse/original_ai_calls.md). The original actor process and engine dispatch are still evidence inputs, not a replacement for the single PlayLoop owner.

Whole-AI equivalence is not claimed: target retention/wait state, low-HP and healing/support priorities, full path/ability scoring and owner+0x12c binding remain incomplete. Reachable-strike preference, SID filtering, live side mapping and stable-ID cleanup are explicit remake policies. Dialogue speakers, actor IDs and current turn order cannot fill missing original policy semantics.

## Reproducible checks

```sh
/opt/homebrew/bin/python3 tools/hsl.py check core_logic_check
/opt/homebrew/bin/python3 tools/hsl.py check static_index_check
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_tests.gd
```

For a disputed address, generate a narrow raw decompilation under `ignored/`, update the compact JSON/checker, then update this document. Do not commit long disassembly output.


## Counter call-site recovery

`0x4423c0` phase 0 checks the request bit 0, defender no-attack property,
weapon/range capability, defender status bit 4 and the counter percentage.
The range-mask lookup decides whether it sets pending flag `0x10000`.
Phase 4 clears that flag if defender HP is non-positive and otherwise returns 2
for a pending counter after primary resolution. Phase 0 is eligibility setup,
not evidence that the counter strike happens first. Caller response handling at `0x444602` swaps attacker/defender and uses flags 1; the alternate path at `0x4414d3` uses flags 3. Bit 0 blocks further counter selection and scales damage to 80%, retaining 1 when truncation would produce zero. The live normal path now performs the same single-response order using the current normal weapon RANGE masks. Native roster/status initialization, full presentation and alternate flags-bit-1 accumulator exemption remain unresolved.

Recheck the compact instruction anchors without a decompiler plugin:

```sh
python3 tools/hsl_combat_resolution_probe.py
```

The anchors are in `core_logic.json` under `combat_resolution.instruction_anchors`.
Raw disassembly remains outside tracked product inputs. Missing decompiler plugins
now fail the wrapper instead of producing a misleading `.c` artifact.

The normal hit branch at `0x404098` writes actual damage to `0x4c13fc` (overkill is clipped), and `0x40a6e1` guarantees positive EXP for a nonzero damage base. This establishes the normal-strike compensation reset without integrating the still-incomplete EXP amount/level-up model.
