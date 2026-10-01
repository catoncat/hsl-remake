#!/usr/bin/env python3
"""Publish the web build to Cloudflare: a private R2 bucket plus a Worker that is the password gate (the twin of web_deploy.py and web_gate.py).

R2 holds the same release layout as the COS bucket (web_release.py): releases/<id>/ for the small files and release.json,
blobs/<sha256 prefix>/ for every .wasm and .pck, latest.json as the only switch. The Worker (tools/web_cf_worker.js) checks the
password, follows latest.json and streams every file straight out of R2, with no redirects and no signed links, so the bytes
stay inside Cloudflare's network and R2 bills nothing for them. Everything here goes through wrangler and its logged-in OAuth
session (`wrangler login` once); no API token or S3 key is needed or stored. wrangler has no list call for R2, so the releases
the bucket holds are tracked in releases.json next to latest.json. The passwords live in the Worker's USERS secret, which
cannot be read back: `users` keeps a 0600 copy in ignored/web/cf-users to edit from.

    python3 tools/web_cf.py init --hostname HOST [--bucket hsl-web] [--worker hsl-web-gate]
    python3 tools/web_cf.py push [--dist DIR] [--keep 3] [--dry-run]
    python3 tools/web_cf.py releases | rollback RELEASE | check | status | deploy
    python3 tools/web_cf.py users list | import --host SSH_ALIAS | add NAME | remove NAME

`push` here and `web_deploy.py push` read the same dist/, so publishing to both stores is one command each. HSL_CF_CHECK_AUTH=user:password
makes `check` (and `push`, after it switched) walk every file of the release through the gate and compare sizes.
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from web_release import (DIST, THREADS, WORK, cache_control, content_type, dist_files, hash_files, is_blob, json_bytes, mb,
                         new_release_id, now_iso, object_keys, orphaned_blobs, release_record, referenced_keys, say)

TOOLS = Path(__file__).resolve().parent
WORKER = TOOLS / 'web_cf_worker.js'
CONFIG = Path(os.environ['HSL_CF_CONFIG']) if os.environ.get('HSL_CF_CONFIG') else WORK / 'cf.json'
CF_DIR = WORK / 'cf'
WRANGLER_TOML = CF_DIR / 'wrangler.toml'
USERS_FILE = WORK / 'cf-users'
AGENT = 'Mozilla/5.0 (compatible; hsl-web-cf)'  # Cloudflare's browser check turns away urllib's own User-Agent with a 403
UPLOADS = 4  # parallel wrangler processes: each is a node start plus an upload, more only fights over the OAuth refresh


def load_config() -> dict:
    if not CONFIG.exists():
        raise SystemExit(f'no {CONFIG}; run: python3 tools/web_cf.py init --hostname HOST')
    return json.loads(CONFIG.read_text(encoding='utf-8'))


def wrangler(*args: str, stdin: bytes | None = None, check: bool = True, timeout: int = 900) -> subprocess.CompletedProcess:
    binary = os.environ.get('HSL_WRANGLER') or shutil.which('wrangler')
    if not binary:
        raise SystemExit('wrangler not found: npm i -g wrangler (or set HSL_WRANGLER), then `wrangler login`')
    env = dict(os.environ, NO_COLOR='1', WRANGLER_SEND_METRICS='false')
    account = json.loads(CONFIG.read_text(encoding='utf-8')).get('account_id') if CONFIG.exists() else ''
    if account:
        env.setdefault('CLOUDFLARE_ACCOUNT_ID', account)
    CF_DIR.mkdir(parents=True, exist_ok=True)  # wrangler leaves a .wrangler/ folder in its working directory: keep it under ignored/
    done = subprocess.run([binary, *args], input=stdin, capture_output=True, env=env, timeout=timeout, cwd=CF_DIR)
    if check and done.returncode != 0:
        tail = (done.stderr + done.stdout).decode('utf-8', 'replace').strip().splitlines()[-6:]
        raise SystemExit(f'wrangler {" ".join(args[:4])} failed ({done.returncode}):\n' + '\n'.join(tail))
    return done


def text_of(done: subprocess.CompletedProcess) -> str:
    return (done.stdout + done.stderr).decode('utf-8', 'replace')


def ensure_login() -> str:
    """The account id of the logged-in wrangler session (a refresh of the OAuth token happens here, before parallel work)."""
    out = text_of(wrangler('whoami', check=False))
    if 'not authenticated' in out.lower() or 'not logged in' in out.lower():
        raise SystemExit('wrangler is not logged in: run `wrangler login` (needs you at the browser)')
    ids = re.findall(r'\b[0-9a-f]{32}\b', out)
    if not ids:
        raise SystemExit('could not read the account id from `wrangler whoami`')
    return ids[0]


def r2_put(cfg: dict, key: str, source: Path | bytes, ctype: str, cache: str) -> None:
    args = ['r2', 'object', 'put', f'{cfg["bucket"]}/{key}', '--content-type', ctype, '--cache-control', cache, '--remote']
    args += ['--file', str(source)] if isinstance(source, Path) else ['--pipe']
    for attempt in range(1, 4):
        done = wrangler(*args, stdin=None if isinstance(source, Path) else source, check=False, timeout=900)
        if done.returncode == 0:
            return
        if attempt == 3:
            raise SystemExit(f'upload of {key} failed 3 times:\n' + '\n'.join(text_of(done).strip().splitlines()[-4:]))
        time.sleep(2 * attempt)


def r2_get(cfg: dict, key: str) -> bytes | None:
    for attempt in range(1, 4):
        done = wrangler('r2', 'object', 'get', f'{cfg["bucket"]}/{key}', '--pipe', '--remote', check=False, timeout=300)
        if done.returncode == 0:
            return done.stdout
        if 'does not exist' in text_of(done) or 'NoSuchKey' in text_of(done):
            return None
        if attempt == 3:  # a dropped connection (wrangler: "a fetch request failed") is the usual cause; three tries ride it out
            raise SystemExit(f'reading {key} failed 3 times:\n' + '\n'.join(text_of(done).strip().splitlines()[-4:]))
        time.sleep(2 * attempt)


def r2_get_json(cfg: dict, key: str):
    data = r2_get(cfg, key)
    return None if data is None else json.loads(data)


def r2_put_json(cfg: dict, key: str, value: dict) -> None:
    r2_put(cfg, key, json_bytes(value), 'application/json', 'no-cache')


def r2_delete(cfg: dict, keys: list[str]) -> None:
    def one(key: str) -> None:
        for attempt in range(1, 4):
            done = wrangler('r2', 'object', 'delete', f'{cfg["bucket"]}/{key}', '--remote', '-y', check=False, timeout=300)
            if done.returncode == 0:
                return
            if attempt == 3:
                raise SystemExit(f'deleting {key} failed 3 times:\n' + '\n'.join(text_of(done).strip().splitlines()[-4:]))
            time.sleep(2 * attempt)
    with concurrent.futures.ThreadPoolExecutor(UPLOADS) as pool:
        list(pool.map(one, keys))


def read_index(cfg: dict) -> list[str]:
    return sorted((r2_get_json(cfg, 'releases.json') or {}).get('releases', []))


def write_index(cfg: dict, ids: list[str]) -> None:
    r2_put_json(cfg, 'releases.json', {'releases': sorted(ids), 'updated': now_iso()})


def read_release(cfg: dict, rid: str) -> dict | None:
    return r2_get_json(cfg, f'releases/{rid}/release.json')


def wrangler_toml(cfg: dict) -> str:
    main = os.path.relpath(WORKER, CF_DIR)
    return f'''# written by web_cf.py (init, deploy); edit the settings in cf.json, not here
name = "{cfg['worker']}"
main = "{main}"
compatibility_date = "2025-09-01"
workers_dev = false
preview_urls = false
routes = [{{ pattern = "{cfg['hostname']}", custom_domain = true }}]

[[r2_buckets]]
binding = "RELEASES"
bucket_name = "{cfg['bucket']}"

[[kv_namespaces]]
binding = "THROTTLE"
id = "{cfg['kv_id']}"

[observability]
enabled = true
'''


def deploy_worker(cfg: dict) -> None:
    CF_DIR.mkdir(parents=True, exist_ok=True)
    WRANGLER_TOML.write_text(wrangler_toml(cfg), encoding='utf-8')
    out = text_of(wrangler('deploy', '--config', str(WRANGLER_TOML)))
    say('  ' + '\n  '.join(line for line in out.strip().splitlines() if line.strip())[-700:])


def json_in(text: str):
    """The first JSON value inside wrangler's output (it prints a banner line or two before it)."""
    decoder = json.JSONDecoder()
    for match in re.finditer(r'[\[{]', text):
        try:
            return decoder.raw_decode(text[match.start():])[0]
        except ValueError:
            continue
    return None


def cmd_init(args: argparse.Namespace) -> int:
    WORK.mkdir(parents=True, exist_ok=True)
    account = ensure_login()
    cfg = {'account_id': account, 'hostname': args.hostname, 'bucket': args.bucket, 'worker': args.worker, 'kv_name': f'{args.worker.removesuffix("-gate")}-throttle'}
    CONFIG.write_text(json.dumps({**cfg, 'kv_id': ''}, indent=1) + '\n', encoding='utf-8')
    made = wrangler('r2', 'bucket', 'create', args.bucket, check=False)
    if made.returncode == 0:
        say(f'created R2 bucket {args.bucket} (private: no r2.dev URL, no custom domain)')
    elif 'already exists' in text_of(made):
        say(f'R2 bucket {args.bucket} already exists; using it')
    else:
        raise SystemExit('creating the bucket failed:\n' + text_of(made)[-400:])
    namespaces = json_in(text_of(wrangler('kv', 'namespace', 'list'))) or []
    found = [n['id'] for n in namespaces if n.get('title') == cfg['kv_name']]
    if found:
        cfg['kv_id'] = found[0]
        say(f'KV namespace {cfg["kv_name"]} already exists; using it')
    else:
        out = text_of(wrangler('kv', 'namespace', 'create', cfg['kv_name']))
        match = re.search(r'"?id"?\s*[:=]\s*"([0-9a-f]{32})"', out)
        if not match:
            raise SystemExit('could not read the new KV namespace id from:\n' + out[-400:])
        cfg['kv_id'] = match.group(1)
        say(f'created KV namespace {cfg["kv_name"]}')
    CONFIG.write_text(json.dumps(cfg, indent=1) + '\n', encoding='utf-8')
    say(f'wrote {CONFIG}; deploying the Worker to {cfg["hostname"]}')
    deploy_worker(cfg)
    say('next: python3 tools/web_cf.py users import --host SSH_ALIAS   (or users add NAME), then push')
    return 0


def cmd_deploy(args: argparse.Namespace) -> int:
    deploy_worker(load_config())
    return 0


def sweep(cfg: dict, release: dict, auth: str) -> list[str]:
    """Walk every file of a release through the gate (HEAD) and name the ones that are missing or have the wrong size."""
    token = base64.b64encode(auth.encode()).decode()

    def head(row: dict) -> str | None:
        request = urllib.request.Request(f'https://{cfg["hostname"]}/{row["path"]}', method='HEAD', headers={'Authorization': f'Basic {token}', 'User-Agent': AGENT})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                size = int(response.headers.get('Content-Length', -1))
        except urllib.error.HTTPError as error:
            return f'{row["path"]}: HTTP {error.code}'
        except OSError as error:
            return f'{row["path"]}: {error}'
        # a compressed answer carries no Content-Length for a text file; only the big ones are compared
        return None if size in (row['size'], -1) else f'{row["path"]}: {size} bytes, expected {row["size"]}'
    with concurrent.futures.ThreadPoolExecutor(THREADS) as pool:
        return [problem for problem in pool.map(head, release['files']) if problem]


def cmd_push(args: argparse.Namespace) -> int:
    cfg = load_config()
    dist = Path(args.dist or DIST).resolve()
    files = dist_files(dist)
    rid, git = new_release_id(dist)
    started = time.time()
    sums = hash_files(files)
    keys = object_keys(files, sums, rid)
    sizes = {rel: files[rel].stat().st_size for rel in files}
    ensure_login()
    index = read_index(cfg)
    previous = (r2_get_json(cfg, 'latest.json') or {}).get('release')
    kept = {i: read_release(cfg, i) for i in index}
    have = referenced_keys([r for r in kept.values() if r])
    plan = {rel: 'reuse' if is_blob(rel) and keys[rel] in have else 'upload' for rel in files}
    count = lambda action: (sum(1 for r in files if plan[r] == action), sum(sizes[r] for r in files if plan[r] == action))  # noqa: E731
    say(f'release {rid}: {len(files)} files {mb(sum(sizes.values()))}; already in the bucket {count("reuse")[0]} ({mb(count("reuse")[1])}), '
        f'to upload {count("upload")[0]} ({mb(count("upload")[1])})')
    if args.dry_run:
        return 0
    todo = [rel for rel in files if plan[rel] == 'upload']
    done_count = 0
    with concurrent.futures.ThreadPoolExecutor(UPLOADS) as pool:
        for start in range(0, len(todo), 40):  # the OAuth token is refreshed between batches, never inside a parallel one
            ensure_login()
            batch = todo[start:start + 40]
            for _ in pool.map(lambda rel: r2_put(cfg, keys[rel], files[rel], content_type(rel), cache_control(rel)), batch):
                done_count += 1
            say(f'  {done_count}/{len(todo)} uploaded  ({time.time() - started:.0f}s)')
    release = release_record(rid, git, files, sums, keys)
    r2_put_json(cfg, f'releases/{rid}/release.json', release)
    write_index(cfg, sorted(set(index) | {rid}))
    r2_put_json(cfg, 'latest.json', {'release': rid, 'updated': release['created']})
    say(f'latest.json -> {rid}  ({time.time() - started:.0f}s)')
    auth = os.environ.get('HSL_CF_CHECK_AUTH')
    if auth:
        time.sleep(6)  # the gate looks at latest.json every few seconds
        problems = sweep(cfg, release, auth)
        if problems:
            if previous:
                r2_put_json(cfg, 'latest.json', {'release': previous, 'updated': now_iso()})
            raise SystemExit(f'verification through the gate failed for {len(problems)} files, e.g. {problems[:3]}; '
                             f'latest.json {"put back to " + previous if previous else "left on the new release"}')
        say(f'verified through the gate: all {len(release["files"])} files present with the right size')
    else:
        say('not walked through the gate (set HSL_CF_CHECK_AUTH=user:password to do that)')
    if args.keep > 0:
        prune(cfg, rid, args.keep)
    return 0


def prune(cfg: dict, current: str, keep: int) -> None:
    index = read_index(cfg)
    others = [i for i in index if i != current]
    doomed = others[:-(keep - 1)] if keep > 1 else others
    if not doomed:
        return
    records = {i: read_release(cfg, i) for i in index}
    remaining = [r for i, r in records.items() if i not in doomed and r]
    removed = [r for i, r in records.items() if i in doomed and r]
    for rid in doomed:
        record = records[rid] or {}
        mine = [row['key'] for row in record.get('files', []) if row.get('key', '').startswith(f'releases/{rid}/')]
        r2_delete(cfg, mine + [f'releases/{rid}/release.json'])
        say(f'pruned {rid} ({len(mine) + 1} objects)')
    stale = sorted(orphaned_blobs(removed, remaining))
    if stale:
        r2_delete(cfg, stale)
        say(f'collected {len(stale)} blobs no remaining release refers to')
    write_index(cfg, [i for i in index if i not in doomed])


def cmd_releases(args: argparse.Namespace) -> int:
    cfg = load_config()
    latest = (r2_get_json(cfg, 'latest.json') or {}).get('release')
    for rid in read_index(cfg):
        row = read_release(cfg, rid) or {}
        say(f'{"*" if rid == latest else " "} {rid}  {mb(row.get("bytes", 0)):>9}  {len(row.get("files", []))} files  {row.get("created", "")}')
    return 0


def cmd_rollback(args: argparse.Namespace) -> int:
    cfg = load_config()
    if read_release(cfg, args.release) is None:
        raise SystemExit(f'no release {args.release}; see: python3 tools/web_cf.py releases')
    r2_put_json(cfg, 'latest.json', {'release': args.release, 'updated': now_iso()})
    say(f'latest.json -> {args.release}')
    return 0


def probe(cfg: dict) -> str:
    try:
        urllib.request.urlopen(urllib.request.Request(f'https://{cfg["hostname"]}/', method='HEAD', headers={'User-Agent': AGENT}), timeout=20)
        return 'ANSWERS WITHOUT A PASSWORD'
    except urllib.error.HTTPError as error:
        return f'HTTP {error.code}' + (' (the password prompt)' if error.code == 401 else '')
    except OSError as error:
        return f'no answer ({error})'


def cmd_check(args: argparse.Namespace) -> int:
    cfg = load_config()
    dev = text_of(wrangler('r2', 'bucket', 'dev-url', 'get', cfg['bucket'], check=False)).lower()
    domains = text_of(wrangler('r2', 'bucket', 'domain', 'list', cfg['bucket'], check=False)).lower()
    public_dev = 'enabled' in dev and 'disabled' not in dev
    public_domain = 'domain:' in domains or 'name:' in domains
    gate = probe(cfg)
    latest = (r2_get_json(cfg, 'latest.json') or {}).get('release')
    say(f'bucket {cfg["bucket"]}: r2.dev {"PUBLIC" if public_dev else "off"}; custom domains {"PRESENT" if public_domain else "none"}; '
        f'gate {cfg["hostname"]}: {gate}; latest release {latest or "none yet"}')
    problems = []
    auth = os.environ.get('HSL_CF_CHECK_AUTH')
    if auth and latest:
        problems = sweep(cfg, read_release(cfg, latest) or {'files': []}, auth)
        say(f'walked every file of {latest} through the gate: ' + ('all present with the right size' if not problems else f'{len(problems)} problems, e.g. {problems[:3]}'))
    return 1 if public_dev or public_domain or gate.startswith('ANSWERS') or problems else 0


def cmd_status(args: argparse.Namespace) -> int:
    cfg = load_config()
    names = [s.get('name') for s in (json_in(text_of(wrangler('secret', 'list', '--config', str(WRANGLER_TOML), check=False))) or [])]
    latest = (r2_get_json(cfg, 'latest.json') or {}).get('release')
    say(f'worker {cfg["worker"]} on {cfg["hostname"]}; bucket {cfg["bucket"]}; KV {cfg["kv_name"]}; secrets {names or "none"}')
    say(f'latest release {latest or "none yet"}; releases {", ".join(read_index(cfg)) or "none"}; gate answers {probe(cfg)}')
    return 0


def read_users() -> list[str]:
    if not USERS_FILE.exists():
        raise SystemExit(f'no {USERS_FILE}: the secret cannot be read back, so run `users import --host SSH_ALIAS` first '
                         '(it copies the list the COS gate uses and keeps a 0600 copy here)')
    return [line.strip() for line in USERS_FILE.read_text(encoding='utf-8').splitlines() if ':' in line and not line.startswith('#')]


def put_users(lines: list[str]) -> None:
    body = '\n'.join(lines) + '\n'
    USERS_FILE.touch(mode=0o600)
    USERS_FILE.chmod(0o600)
    USERS_FILE.write_text(body, encoding='utf-8')
    wrangler('secret', 'put', 'USERS', '--config', str(WRANGLER_TOML), stdin=body.encode('utf-8'))


def cmd_users(args: argparse.Namespace) -> int:
    if args.action == 'import':
        if not args.host:
            raise SystemExit('give --host SSH_ALIAS (or set HSL_WEB_HOST): the server whose /etc/hsl-gate/users to copy')
        out = subprocess.run(['ssh', '-o', 'BatchMode=yes', args.host, 'cat /etc/hsl-gate/users'], capture_output=True, text=True)
        if out.returncode != 0:
            raise SystemExit(f'ssh {args.host} failed: {out.stderr[-300:]}')
        lines = [line.strip() for line in out.stdout.splitlines() if ':' in line and not line.startswith('#')]
        put_users(lines)
        say(f'imported {len(lines)} users into the Worker secret: ' + ', '.join(line.split(':', 1)[0] for line in lines))
        return 0
    lines = read_users()
    names = [line.split(':', 1)[0] for line in lines]
    if args.action == 'list':
        say('users: ' + (', '.join(names) if names else '(none)'))
        return 0
    if not args.name or not re.fullmatch(r'[A-Za-z0-9_.-]+', args.name):
        raise SystemExit('give a NAME of letters, digits, _ . -')
    if args.action == 'add':
        if args.name in names:
            raise SystemExit(f'{args.name} already exists; remove it first to change its password')
        password = secrets.token_urlsafe(9)
        put_users(lines + [f'{args.name}:{password}'])
        say(f'added {args.name}  password: {password}   (shown once; the Worker uses it at once)')
    else:
        put_users([line for line in lines if line.split(':', 1)[0] != args.name])
        say(f'removed {args.name}')
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('init')
    p.add_argument('--hostname', required=True, help='the name the gate answers on, a subdomain of a zone in this Cloudflare account')
    p.add_argument('--bucket', default='hsl-web')
    p.add_argument('--worker', default='hsl-web-gate')
    p.set_defaults(func=cmd_init)
    p = sub.add_parser('push')
    p.add_argument('--dist')
    p.add_argument('--keep', type=int, default=3, help='releases to keep, newest first (0: keep all)')
    p.add_argument('--dry-run', action='store_true')
    p.set_defaults(func=cmd_push)
    sub.add_parser('releases').set_defaults(func=cmd_releases)
    p = sub.add_parser('rollback')
    p.add_argument('release')
    p.set_defaults(func=cmd_rollback)
    sub.add_parser('check').set_defaults(func=cmd_check)
    sub.add_parser('status').set_defaults(func=cmd_status)
    sub.add_parser('deploy').set_defaults(func=cmd_deploy)
    p = sub.add_parser('users')
    p.add_argument('action', choices=['list', 'import', 'add', 'remove'])
    p.add_argument('name', nargs='?')
    p.add_argument('--host', default=os.environ.get('HSL_WEB_HOST'), help='import: ssh alias or user@address of the server holding the COS gate users')
    p.set_defaults(func=cmd_users)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
