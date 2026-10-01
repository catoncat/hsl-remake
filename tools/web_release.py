#!/usr/bin/env python3
"""What a web release is, independent of where it is stored (shared by web_deploy.py for COS and web_cf.py for Cloudflare R2).

A release is the dist/ tree of web_build.py. Its small files (page, loader script, icons, pack manifest) sit under
releases/<id>/<path>; every .wasm and .pck sits once under blobs/<sha256 prefix>/<name> and is shared by all releases that
carry it. releases/<id>/release.json lists every file {path, size, sha256, key}; latest.json {release, updated} is written
last and is the only switch. This module holds the parts that must not differ between stores: file discovery, hashing, keys,
the cache policy, the release record and which blobs a pruned release leaves behind. It has no side effects of its own.
"""
from __future__ import annotations

import concurrent.futures
import datetime
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / 'ignored' / 'web'
DIST = WORK / 'dist'
BLOB_SUFFIXES = ('.wasm', '.pck')
REQUIRED = ('index.html', 'index.pck', 'packs/manifest.json')
TYPES = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm',
         '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json'}
THREADS = 8


def say(message: str) -> None:
    print(message, flush=True)


def mb(count: int | float) -> str:
    return f'{count / 1048576:.1f} MB'


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')


def json_bytes(value: dict) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=1) + '\n').encode('utf-8')


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def is_blob(rel: str) -> bool:
    return rel.endswith(BLOB_SUFFIXES)


def blob_key(sha: str, rel: str) -> str:
    """Big files live under their content hash, shared by every release that carries them."""
    return f'blobs/{sha[:20]}/{Path(rel).name}'


def cache_control(rel: str) -> str:
    if is_blob(rel):
        # engine and core: the browser may keep them for good (the key names the content); packs: the game stores them
        # itself in IndexedDB, so keep them out of the HTTP cache
        return 'no-store' if rel.startswith('packs/') else 'public, max-age=31536000, immutable'
    return 'no-cache'


def content_type(rel: str) -> str:
    return TYPES.get(Path(rel).suffix.lower(), 'application/octet-stream')


def dist_files(dist: Path) -> dict[str, Path]:
    """Every publishable file of a dist tree by its path inside it; refuses a tree that is not a finished web build."""
    files = {p.relative_to(dist).as_posix(): p for p in sorted(dist.rglob('*')) if p.is_file() and not p.name.startswith('.')}
    for need in REQUIRED:
        if need not in files:
            raise SystemExit(f'{dist} has no {need}; run: python3 tools/web_build.py build')
    return files


def hash_files(files: dict[str, Path]) -> dict[str, str]:
    with concurrent.futures.ThreadPoolExecutor(THREADS) as pool:
        return dict(zip(files, pool.map(lambda rel: sha256_file(files[rel]), files)))


def new_release_id(dist: Path) -> tuple[str, str]:
    """(release id, source commit): the minute of publication plus the commit the build recorded."""
    info = json.loads((dist / 'build.json').read_text(encoding='utf-8')) if (dist / 'build.json').exists() else {}
    git = info.get('git') or subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M') + '-' + git, git


def object_keys(files: dict[str, Path], sums: dict[str, str], rid: str) -> dict[str, str]:
    return {rel: blob_key(sums[rel], rel) if is_blob(rel) else f'releases/{rid}/{rel}' for rel in files}


def release_record(rid: str, git: str, files: dict[str, Path], sums: dict[str, str], keys: dict[str, str]) -> dict:
    sizes = {rel: files[rel].stat().st_size for rel in files}
    return {'id': rid, 'git': git, 'created': now_iso(), 'bytes': sum(sizes.values()),
            'files': [{'path': rel, 'size': sizes[rel], 'sha256': sums[rel], 'key': keys[rel]} for rel in files]}


def referenced_keys(releases: list[dict]) -> set[str]:
    return {row['key'] for release in releases for row in release.get('files', []) if row.get('key')}


def orphaned_blobs(removed: list[dict], remaining: list[dict]) -> set[str]:
    """Blobs only the removed releases referred to: what pruning may delete without touching a release that stays."""
    return {key for key in referenced_keys(removed) - referenced_keys(remaining) if key.startswith('blobs/')}
