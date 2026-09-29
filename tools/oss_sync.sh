#!/bin/sh
# Sync the public tree: export REF (default main) with tools/oss_export.sh into the public checkout,
# rescan for personal paths and stray media, commit and push. Used by lane_merge.sh publish
# (user 2026-09-27: push as we commit — the public repo must follow main without a manual step).
#   HSL_OSS_PUBLIC_DIR   git checkout of the public repo (default ~/.pi-worktrees/hsl-remake)
#   HSL_OSS_AUTHOR_NAME / HSL_OSS_AUTHOR_EMAIL   commit identity in the public repo
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-main}"
PUB="${HSL_OSS_PUBLIC_DIR:-${HOME}/.pi-worktrees/hsl-remake}"
NAME="${HSL_OSS_AUTHOR_NAME:-cat}"; EMAIL="${HSL_OSS_AUTHOR_EMAIL:<author e-mail>}"
[ -d "${PUB}/.git" ] || { echo "OSS_SYNC_SKIP no public checkout at ${PUB}"; exit 0; }
head="$(git -C "${ROOT}" rev-parse --short "${REF}")"
NEW="${PUB}.new"
python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "${NEW}"
if ! out="$("${ROOT}/tools/oss_export.sh" "${NEW}" "${REF}" 2>&1)"; then
  printf '%s\n' "${out}" | tail -5; echo "OSS_SYNC_FAIL export ref=${head}"; exit 1
fi
personal="$(grep -rIl "$(id -un)" "${NEW}" --exclude-dir=.git | wc -l | tr -d ' ')"
media="$(find "${NEW}" -type f \( -iname '*.png' -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.webp' -o -iname '*.sav' -o -iname '*.bin' -o -iname '*.shp' -o -iname '*.pak' -o -iname '*.exe' \) -not -path "${NEW}/docs/screenshots/remake/*" -not -path "${NEW}/content/authored/music/*" -not -path "${NEW}/content/authored/actors/*/sounds/*" -not -path "${NEW}/content/authored/ui/*" -not -path "${NEW}/content/authored/*/ui/*" | wc -l | tr -d ' ')"
# Mod audio (content/authored/music/, actors/*/sounds/) ships only when self-made: no file may match an
# original audio sha256 recorded in original_derived_manifest.json.
original_audio="$(python3 - "${NEW}" <<'PY'
import hashlib, json, sys
from pathlib import Path
out = Path(sys.argv[1])
known = {v['sha256'] for v in json.loads((out / 'content/generated/hsl/original_derived_manifest.json').read_text())['files'].values() if 'sha256' in v}
files = [*out.glob('content/authored/music/*'), *out.glob('content/authored/actors/*/sounds/*')]
print(sum(hashlib.sha256(f.read_bytes()).hexdigest() in known for f in files if f.is_file()))
PY
)"
# Hand-drawn interface art (content/authored/ui/, and the ui/ folder beside a campaign.json under
# content/authored/, the only campaigns game/common/InterfaceArt.gd reads one for) ships only when
# self-made: no file may match an original sha256, nor a PNG an original rgba_sha256.
original_ui="$(python3 - "${NEW}" "${ROOT}" <<'PY'
import fnmatch, hashlib, json, sys
from pathlib import Path
out, root = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(root / 'tools'))
from hsltools.sources.shp import png_sha256
entries = json.loads((out / 'content/generated/hsl/original_derived_manifest.json').read_text())['files'].values()
known = {v[key] for v in entries for key in ('sha256', 'rgba_sha256') if key in v}
patterns = ('content/authored/ui/*', 'content/authored/*/ui/*')
files = [f for f in out.glob('content/authored/**/*') if f.is_file() and any(fnmatch.fnmatch(f.relative_to(out).as_posix(), p) for p in patterns)]
print(sum(hashlib.sha256(f.read_bytes()).hexdigest() in known or (f.suffix.lower() == '.png' and png_sha256(f) in known) for f in files))
PY
)"
if [ "${personal}" != 0 ] || [ "${media}" != 0 ] || [ "${original_audio}" != 0 ] || [ "${original_ui}" != 0 ]; then
  echo "OSS_SYNC_FAIL rescan personal_hits=${personal} media_outside=${media} original_audio=${original_audio} original_ui=${original_ui} out=${NEW}"; exit 1
fi
find "${PUB}" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
(cd "${NEW}" && tar cf - .) | (cd "${PUB}" && tar xf -)
python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "${NEW}"
git -C "${PUB}" add -A
if git -C "${PUB}" diff --cached --quiet; then echo "OSS_SYNC_OK ref=${head} (public tree unchanged)"; exit 0; fi
# Public commit message: every source commit since the previously synced source commit (read back from
# the public HEAD's trailer), bookkeeping commits dropped, so the public history says what changed.
# The previous source commit: the `Source:` trailer, else the older `sync: hsl-fork main <sha>` subject,
# else HSL_OSS_SYNC_PREV (manual override for a one-off catch-up).
prev="$(git -C "${PUB}" log -1 --format=%B 2>/dev/null | sed -n -e 's/^Source: hsl-fork \([0-9a-f]*\).*/\1/p' -e 's/^sync: hsl-fork main \([0-9a-f]*\).*/\1/p' | head -1)"
prev="${HSL_OSS_SYNC_PREV:-${prev}}"
msgfile="$(mktemp /tmp/oss-sync-msg.XXXXXX)"
python3 - "${ROOT}" "${REF}" "${prev}" "${head}" >"${msgfile}" <<'PY'
import subprocess, sys, re
root, ref, prev, head = sys.argv[1:5]
rng = f"{prev}..{ref}" if prev and subprocess.run(["git","-C",root,"cat-file","-e",prev],capture_output=True).returncode == 0 else "-1 " + ref
raw = subprocess.run(["git","-C",root,"log","--format=%x1e%s%x1f%b", *rng.split()],capture_output=True,text=True).stdout
entries = []
for chunk in raw.split("\x1e"):
    if not chunk.strip(): continue
    subject, _, body = chunk.partition("\x1f")
    subject = subject.strip()
    if re.match(r"^(docs\(时间账\)|docs\(PROJECT\)|chore\(卫生\))", subject): continue
    body = "\n".join(l for l in body.strip().splitlines() if not l.startswith("Co-Authored-By") and l.strip())
    entries.append((subject, body))
if not entries:
    entries = [(subprocess.run(["git","-C",root,"log","-1","--format=%s",ref],capture_output=True,text=True).stdout.strip(), "")]
first = entries[0][0]
title = re.split(r"——|：|:", first, 1)[0].strip()
if len(title) > 72: title = title[:69] + "…"
if len(entries) > 1: title += f" 等 {len(entries)} 项"
print(title); print()
for subject, body in entries:
    print("- " + subject)
    if body:
        for l in body.splitlines(): print("  " + l)
print(); print(f"Source: hsl-fork {head}")
PY
git -C "${PUB}" -c user.name="${NAME}" -c user.email="${EMAIL}" commit -q -F "${msgfile}"
rm -f "${msgfile}"
git -C "${PUB}" push -q origin main
echo "OSS_SYNC_OK ref=${head} public=$(git -C "${PUB}" rev-parse --short HEAD) files=$(git -C "${PUB}" diff --stat HEAD~1 | tail -1 | awk '{print $1}')"
