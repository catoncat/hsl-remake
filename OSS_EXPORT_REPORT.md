# OSS export report

Source: private repository `main` = `50b4658e232679dba3e5ff8c84a73ed33ebffd96` (committed tree only), exported by `tools/oss_export.sh`.
No git history or author metadata is carried; the first commit of the public repository is made by hand.

- written: **1558 files, 68.0 MB**
- dropped: **19212 files, 620.4 MB**
- processed (home path / author e-mail / public .gitignore rules): 19 files
- residual home paths or author e-mails in the written tree: 0
- files naming unreleased work (`docs/internal/unreleased_names.txt`): 0; internal marker lines left: 0

| 类别 | 文件数 | MB |
| --- | ---: | ---: |
| B | 1174 | 20.7 |
| C | 384 | 47.2 |

## Dropped (by reason)

| reason | files | MB |
| --- | ---: | ---: |
| A: evidence screenshots / recordings / renders of the original | 600 | 275.0 |
| A: content/imported decoded media | 16326 | 266.6 |
| A: content/imported text/source/json | 1518 | 35.2 |
| A: content/generated tables (EXE / PAK derived) | 420 | 22.8 |
| A: content/battles assembled level data | 210 | 18.9 |
| A: content/authored placeholder art (recoloured original frames) | 73 | 0.9 |
| excluded directory docs/internal/ | 34 | 0.6 |
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
- `docs/internal/ORIGINAL_COMPLAINTS.md`
- `docs/internal/ORIGINAL_SCRIPT.md`
- `docs/internal/PLAYABILITY.md`
- `docs/internal/ROUNDS.md`
- `docs/internal/SEQUEL_READINESS.md`
- `docs/internal/WEB_DEPLOY.md`
- `docs/internal/lane_brief.md`
- `docs/internal/unreleased_names.txt`
- `docs/internal/web/README.md`
- `docs/internal/web/fetch_templates.py`
- `docs/internal/web/node/audio.mjs`
- `docs/internal/web/node/blank.mjs`
- `docs/internal/web/node/blank2.mjs`
- `docs/internal/web/node/cache_check.mjs`
- `docs/internal/web/node/cache_check_hdr.mjs`
- `docs/internal/web/node/file_scheme.mjs`
- `docs/internal/web/node/insecure.mjs`
- `docs/internal/web/node/package-lock.json`
- `docs/internal/web/node/package.json`
- `docs/internal/web/node/packs_smoke.mjs`
- `docs/internal/web/node/persist.mjs`
- `docs/internal/web/node/smoke.mjs`
- `docs/internal/web/node/throttle.mjs`
- `docs/internal/web/node/touch-e2e/analyze.py`
- `docs/internal/web/node/touch-e2e/explore.js`
- `docs/internal/web/node/touch-e2e/main.js`
- `docs/internal/web/pckprobe/make_big.gd`
- `docs/internal/web/pckprobe/make_pack.gd`
- `docs/internal/web/publish.sh`
- `docs/internal/web/webp_probe.py`
- `legal-assets/README.md`

## Processed files

- `.gitignore`
- `docs/PROJECT.md`
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
