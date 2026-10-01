# OSS export report

Source: private repository `main` = `b69f132ae092a59d95ed7d35a4261a35621dece0` (committed tree only), exported by `tools/oss_export.sh`.
No git history or author metadata is carried; the first commit of the public repository is made by hand.

- written: **1542 files, 67.1 MB**
- dropped: **19147 files, 610.5 MB**
- processed (home path / author e-mail / public .gitignore rules): 18 files
- residual home paths or author e-mails in the written tree: 0

| 类别 | 文件数 | MB |
| --- | ---: | ---: |
| B | 1158 | 19.8 |
| C | 384 | 47.2 |

## Dropped (by reason)

| reason | files | MB |
| --- | ---: | ---: |
| A: evidence screenshots / recordings / renders of the original | 600 | 275.0 |
| A: content/imported decoded media | 16285 | 257.0 |
| A: content/imported text/source/json | 1518 | 35.2 |
| A: content/generated tables (EXE / PAK derived) | 420 | 22.7 |
| A: content/battles assembled level data | 210 | 18.9 |
| A: content/authored placeholder art (recoloured original frames) | 73 | 0.9 |
| excluded directory docs/internal/ | 10 | 0.5 |
| excluded directory docs/audits/ | 8 | 0.3 |
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
- `docs/audits/JOBMODEL_2026-09-28.md`
- `docs/audits/PARITY_TRIAGE_2026-09-28.md`
- `docs/audits/STATE_COVERAGE_2026-09-28.md`
- `docs/audits/TOOLS_AUDIT_2026-09-27.md`
- `docs/external/typesafe/README.md`
- `docs/internal/CONSOLIDATION.md`
- `docs/internal/FIRST_BATTLE_ACCEPTANCE.md`
- `docs/internal/LANE_TIMELOG.md`
- `docs/internal/OPEN_SOURCE_PLAN.md`
- `docs/internal/ORIGINAL_SCRIPT.md`
- `docs/internal/PLAYABILITY.md`
- `docs/internal/ROUNDS.md`
- `docs/internal/SEQUEL_READINESS.md`
- `docs/internal/WEB_DEPLOY.md`
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
