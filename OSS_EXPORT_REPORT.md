# OSS export report

Source: private repository `main` = `7b072bc355d3c87e6d01164136f1546766c760dc` (committed tree only), exported by `tools/oss_export.sh`.
No git history or author metadata is carried; the first commit of the public repository is made by hand.

- written: **1481 files, 49.9 MB**
- dropped: **19008 files, 613.4 MB**
- processed (home path / author e-mail / public .gitignore rules): 18 files
- residual home paths or author e-mails in the written tree: 0

| 类别 | 文件数 | MB |
| --- | ---: | ---: |
| B | 1106 | 18.9 |
| C | 375 | 31.0 |

## Dropped (by reason)

| reason | files | MB |
| --- | ---: | ---: |
| A: evidence screenshots / recordings / renders of the original | 600 | 275.0 |
| A: content/imported decoded media | 16144 | 255.4 |
| A: content/imported text/source/json | 1520 | 35.1 |
| A: content/generated tables (EXE / PAK derived) | 423 | 27.6 |
| A: content/battles assembled level data | 210 | 18.8 |
| A: content/authored placeholder art (recoloured original frames) | 73 | 0.9 |
| excluded directory docs/audits/ | 7 | 0.3 |
| excluded directory docs/internal/ | 8 | 0.3 |
| A: original saves / runtime memory dumps | 12 | 0.1 |
| A: content/generated README / report (migrate) | 5 | 0.0 |
| excluded directory docs/external/typesafe/ | 1 | 0.0 |
| A: content/imported handwritten README (migrate) | 3 | 0.0 |
| excluded directory legal-assets/ | 1 | 0.0 |
| excluded directory asset-dumps/ | 1 | 0.0 |

The per-file list of original-derived files is `content/generated/hsl/original_derived_manifest.json`
(path, SHA-256, generating task); every excluded-directory file is listed below.

- `asset-dumps/README.md`
- `docs/audits/ABILITIES_2026-09-28.md`
- `docs/audits/CODE_AUDIT_2026-09-27.md`
- `docs/audits/DOCS_AUDIT_2026-09-27.md`
- `docs/audits/EVIDENCE_AUDIT_2026-09-27.md`
- `docs/audits/PARITY_TRIAGE_2026-09-28.md`
- `docs/audits/STATE_COVERAGE_2026-09-28.md`
- `docs/audits/TOOLS_AUDIT_2026-09-27.md`
- `docs/external/typesafe/README.md`
- `docs/internal/CONSOLIDATION.md`
- `docs/internal/FIRST_BATTLE_ACCEPTANCE.md`
- `docs/internal/LANE_TIMELOG.md`
- `docs/internal/OPEN_SOURCE_PLAN.md`
- `docs/internal/PLAYABILITY.md`
- `docs/internal/ROUNDS.md`
- `docs/internal/SEQUEL_READINESS.md`
- `docs/internal/lane_brief.md`
- `legal-assets/README.md`

## Processed files

- `.gitignore`
- `tools/oss_sync.sh`
- `docs/OPTIONS.md`
- `docs/PROVENANCE.md`
- `docs/evidence_packets/resource_inventory/original_movies.md`
- `docs/evidence_packets/runtime_observations/battle_005/README.md`
- `docs/evidence_packets/runtime_observations/battle_006/README.md`
- `docs/evidence_packets/runtime_observations/battle_053/README.md`
- `docs/evidence_packets/runtime_observations/effect_motion/README.md`
- `docs/evidence_packets/runtime_observations/map_pose_floaters/README.md`
- `docs/evidence_packets/runtime_observations/menus_ui/README.md`
- `docs/evidence_packets/runtime_observations/original_control/README.md`
- `docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md`
- `docs/evidence_packets/runtime_observations/original_level17_escort/README.md`
- `docs/evidence_packets/runtime_observations/original_title_ornaments/README.md`
- `docs/evidence_packets/runtime_observations/original_world_town/README.md`
- `docs/evidence_packets/static_reverse/battle_reward_inputs.md`
- `docs/evidence_packets/static_reverse/original_cast_overlays.md`
