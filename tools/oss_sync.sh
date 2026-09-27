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
media="$(find "${NEW}" -type f \( -iname '*.png' -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.webp' -o -iname '*.sav' -o -iname '*.bin' -o -iname '*.shp' -o -iname '*.pak' -o -iname '*.exe' \) -not -path "${NEW}/docs/screenshots/remake/*" | wc -l | tr -d ' ')"
if [ "${personal}" != 0 ] || [ "${media}" != 0 ]; then
  echo "OSS_SYNC_FAIL rescan personal_hits=${personal} media_outside=${media} out=${NEW}"; exit 1
fi
find "${PUB}" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
(cd "${NEW}" && tar cf - .) | (cd "${PUB}" && tar xf -)
python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "${NEW}"
git -C "${PUB}" add -A
if git -C "${PUB}" diff --cached --quiet; then echo "OSS_SYNC_OK ref=${head} (public tree unchanged)"; exit 0; fi
# Public commit message: every source commit since the previously synced source commit (read back from
# the public HEAD's trailer), bookkeeping commits dropped, so the public history says what changed.
prev="$(git -C "${PUB}" log -1 --format=%B 2>/dev/null | sed -n 's/^Source: hsl-fork \([0-9a-f]*\).*/\1/p' | head -1)"
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
