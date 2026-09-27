#!/usr/bin/env bash
# Assemble the public repository tree (docs/internal/OPEN_SOURCE_PLAN.md 方案甲) into OUT_DIR:
#
#   tools/oss_export.sh OUT_DIR [REF]      REF defaults to HEAD
#
# Reads the committed tree at REF only (git ls-tree + git cat-file; the working tree, ignored/ and .claude/
# are never read) and writes B-class files plus processed C-class files (hsltools.original_content.classify):
#   dropped   every A-class file (original-derived), docs/external/typesafe/ (third-party mirror; its README
#             links the mirrored pages), docs/internal/ and docs/audits/ (process docs), legal-assets/,
#             asset-dumps/, ignored/, .claude/
#   processed text files: /Users/<name> home paths -> ~, author e-mail addresses -> <author e-mail>;
#             .gitignore gains the rules that keep a player's import out of commits
#   added     OSS_EXPORT_REPORT.md (file counts, MB, dropped list by subclass, processed files)
# OUT_DIR must not exist or be empty. It is a plain directory: no git history, no author metadata — the
# new repository's first commit is made by the user. Nothing is pushed or created on GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$([[ -x /opt/homebrew/bin/python3 ]] && echo /opt/homebrew/bin/python3 || command -v python3 || echo python3)}"
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,16p' "$0" >&2; exit 2; }
OUT="$1"
REF="${2:-HEAD}"
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
  echo "OSS_EXPORT_FAIL output directory is not empty: $OUT" >&2
  exit 2
fi
mkdir -p "$OUT"
export PYTHONDONTWRITEBYTECODE=1
exec "$PYTHON_BIN" - "$ROOT" "$OUT" "$REF" <<'PY'
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

root, out, ref = Path(sys.argv[1]), Path(sys.argv[2]).resolve(), sys.argv[3]
sys.path.insert(0, str(root / 'tools'))
from hsltools.original_content import classify  # noqa: E402

# docs/internal/ and docs/audits/ are our process docs (lane briefs, time log, round log, audits); public docs
# may not link them (tools/hsl_docs_check.py PRIVATE_DOCS keeps the two lists in step).
DROPPED_PREFIXES = ('legal-assets/', 'asset-dumps/', 'ignored/', '.claude/', 'docs/external/typesafe/',
                    'docs/internal/', 'docs/audits/')
HOME_PATH = re.compile(rb'/Users/[A-Za-z0-9._-]+')
EMAIL = re.compile(rb'[A-Za-z0-9._-]+@(?:chen\.rs|[A-Za-z0-9-]+\.local)')  # maintainer addresses; the local-host form is not spelled out here
PUBLIC_IGNORE = '''
# Original-derived content (NOTICE.md): imported locally from the player's own copy with
# `HSL_ORIGINAL_DIR=... python3 tools/hsl.py generate ...`, never committed. Checked against the tracked
# content/generated/hsl/original_derived_manifest.json by `python3 tools/hsl.py check original_derived_manifest`.
/content/imported/
/content/battles/*
!/content/battles/levels/
!/content/battles/campaign.json
/content/generated/**
!/content/generated/**/
!/content/generated/hsl/original_derived_manifest.json
!/content/generated/hsl/remake_music/**
!/content/generated/hsl/development/autoplay/**
'''

sha = subprocess.run(['git', 'rev-parse', ref], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
listing = subprocess.run(['git', 'ls-tree', '-r', '-l', '-z', ref], cwd=root, capture_output=True, check=True).stdout
entries = []
for item in listing.split(b'\0'):
    if not item:
        continue
    meta, name = item.split(b'\t', 1)
    mode, kind, obj, size = meta.split()
    entries.append((name.decode(), mode.decode(), obj.decode(), int(size) if size != b'-' else 0))

kept, dropped = [], []
for path, mode, obj, size in entries:
    klass, subclass = classify(path)
    if path.startswith(DROPPED_PREFIXES):
        dropped.append((path, size, 'excluded directory ' + next(p for p in DROPPED_PREFIXES if path.startswith(p))))
    elif klass == 'A':
        dropped.append((path, size, 'A: ' + subclass))
    else:
        kept.append((path, mode, obj, size, klass, subclass))

batch = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
processed = []
written_bytes = 0
for path, mode, obj, size, klass, subclass in kept:
    batch.stdin.write(obj.encode() + b'\n')
    batch.stdin.flush()
    header = batch.stdout.readline().split()
    data = batch.stdout.read(int(header[2]))
    batch.stdout.read(1)
    target = out / path
    target.parent.mkdir(parents=True, exist_ok=True)
    if mode == '120000':
        target.symlink_to(data.decode())
        continue
    if b'\0' not in data[:8192]:
        changed = EMAIL.sub(b'<author e-mail>', HOME_PATH.sub(b'~', data))
        if path == '.gitignore':
            changed = changed.rstrip(b'\n') + b'\n' + PUBLIC_IGNORE.encode()
        if changed != data:
            processed.append(path)
            data = changed
    target.write_bytes(data)
    written_bytes += len(data)
    if mode == '100755':
        target.chmod(0o755)
batch.stdin.close()
batch.wait()

# Original measurement frames / resource renders are not exported: their links become text + archive id
# (docs/internal/OPEN_SOURCE_PLAN.md §2.2; the private repository keeps the links).
sys.path.insert(0, str(root / 'tools'))
from oss_screenshots import export_text  # noqa: E402
processed += [path for path in export_text(out) if path not in processed]

# Residual scan of what was written: no home path, no author e-mail.
residual = [path for path, *_ in kept if (out / path).is_file() and not (out / path).is_symlink()
            and (HOME_PATH.search((out / path).read_bytes()) or EMAIL.search((out / path).read_bytes()))]

mb = lambda n: f'{n / 1048576:.1f}'
by_class = Counter()
by_class_bytes = Counter()
for path, mode, obj, size, klass, subclass in kept:
    by_class[klass] += 1
    by_class_bytes[klass] += size
drop_groups = Counter()
drop_bytes = Counter()
for path, size, reason in dropped:
    drop_groups[reason] += 1
    drop_bytes[reason] += size
lines = [
    '# OSS export report',
    '',
    f'Source: private repository `{ref}` = `{sha}` (committed tree only), exported by `tools/oss_export.sh`.',
    f'No git history or author metadata is carried; the first commit of the public repository is made by hand.',
    '',
    f'- written: **{len(kept)} files, {mb(written_bytes)} MB**',
    f'- dropped: **{len(dropped)} files, {mb(sum(s for _p, s, _r in dropped))} MB**',
    f'- processed (home path / author e-mail / public .gitignore rules): {len(processed)} files',
    f'- residual home paths or author e-mails in the written tree: {len(residual)}',
    '',
    '| 类别 | 文件数 | MB |',
    '| --- | ---: | ---: |',
    *[f'| {klass} | {by_class[klass]} | {mb(by_class_bytes[klass])} |' for klass in sorted(by_class)],
    '',
    '## Dropped (by reason)',
    '',
    '| reason | files | MB |',
    '| --- | ---: | ---: |',
    *[f'| {reason} | {count} | {mb(drop_bytes[reason])} |' for reason, count in sorted(drop_groups.items(), key=lambda kv: -drop_bytes[kv[0]])],
    '',
    'The per-file list of original-derived files is `content/generated/hsl/original_derived_manifest.json`',
    '(path, SHA-256, generating task); every excluded-directory file is listed below.',
    '',
    *[f'- `{path}`' for path, _size, reason in dropped if reason.startswith('excluded directory')],
    '',
    '## Processed files',
    '',
    *[f'- `{path}`' for path in processed],
    '',
]
if residual:
    lines += ['## Residual (must be fixed before publishing)', '', *[f'- `{path}`' for path in residual], '']
(out / 'OSS_EXPORT_REPORT.md').write_text('\n'.join(lines), encoding='utf-8')
print(f'OSS_EXPORT_{"FAIL" if residual else "PASS"} ref={sha[:8]} written={len(kept)} mb={mb(written_bytes)} '
      f'dropped={len(dropped)} processed={len(processed)} residual={len(residual)} out={out}')
sys.exit(1 if residual else 0)
PY
