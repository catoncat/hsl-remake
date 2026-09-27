# OSS export report

Source: private repository `main` = `319a30ed67f45fadbf19b752560142a3499ac52c` (committed tree only), exported by `tools/oss_export.sh`.
No git history or author metadata is carried; the first commit of the public repository is made by hand.

- written: **1897 files, 54.4 MB**
- dropped: **19320 files, 733.2 MB**
- processed (home path / author e-mail / public .gitignore rules): 3 files
- residual home paths or author e-mails in the written tree: 0

| 类别 | 文件数 | MB |
| --- | ---: | ---: |
| B | 1415 | 19.8 |
| C | 482 | 34.6 |

## Dropped (by reason)

| reason | files | MB |
| --- | ---: | ---: |
| A: evidence screenshots / recordings / renders of the original | 873 | 397.7 |
| A: content/imported decoded media | 16200 | 255.4 |
| A: content/imported text/source/json | 1519 | 35.1 |
| A: content/generated tables (EXE / PAK derived) | 422 | 25.2 |
| A: content/battles assembled level data | 210 | 18.8 |
| A: content/authored placeholder art (recoloured original frames) | 73 | 0.9 |
| A: original saves / runtime memory dumps | 12 | 0.1 |
| A: content/generated README / report (migrate) | 5 | 0.0 |
| excluded directory docs/external/typesafe/ | 1 | 0.0 |
| A: content/imported handwritten README (migrate) | 3 | 0.0 |
| excluded directory legal-assets/ | 1 | 0.0 |
| excluded directory asset-dumps/ | 1 | 0.0 |

The per-file list of original-derived files is `content/generated/hsl/original_derived_manifest.json`
(path, SHA-256, generating task); every excluded-directory file is listed below.

- `asset-dumps/README.md`
- `docs/external/typesafe/README.md`
- `legal-assets/README.md`

## Processed files

- `.gitignore`
- `docs/OPEN_SOURCE_PLAN.md`
- `tools/test_hsl_function_catalog.py`
