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
subject="$(git -C "${ROOT}" log -1 --format=%s "${REF}" | cut -c1-160)"
git -C "${PUB}" -c user.name="${NAME}" -c user.email="${EMAIL}" commit -q -m "sync: hsl-fork main ${head} —— ${subject}"
git -C "${PUB}" push -q origin main
echo "OSS_SYNC_OK ref=${head} public=$(git -C "${PUB}" rev-parse --short HEAD) files=$(git -C "${PUB}" diff --stat HEAD~1 | tail -1 | awk '{print $1}')"
