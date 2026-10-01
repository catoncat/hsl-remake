#!/usr/bin/env python3
"""Front door for the private COS release: password in front, big files straight from COS.

The page, the small loader files and the pack manifest come from here (with ETags, so an unchanged file costs a 304);
every large file is answered with a 302 to a COS URL signed with the gate's read-only key, so the bytes travel from COS
at its own speed and this machine's bandwidth does not matter. The bucket stays private: without the password there is
no link. Two kinds of link:

  boot files (engine .wasm, core .pck): one link per fixed time window (the same string for every visitor all window
      long), valid for two windows, and the object carries `immutable`, so a returning browser reuses its cached copy
      and downloads nothing until the file really changes (blobs are keyed by content, so an unchanged engine keeps
      its link across releases too);
  packs (packs/*.pck): a fresh one-hour link per request; the game keeps them in the browser's storage itself.

The gate follows latest.json, so `web_deploy.py push` (or `rollback`) changes what is served within a few seconds.
It needs nothing beyond Python's standard library.

    python3 tools/web_gate.py [--auth USER:PASSWORD ...] [--users-file PATH] [--port 8088] [--bind 127.0.0.1]
    python3 tools/web_gate.py cors --origin https://…        # allow the page's origin on the bucket (needs boto3, run it on a workstation)

Credentials come from the config web_deploy.py wrote (ignored/web/deploy.json) or the same keys in the environment
(HSL_COS_BUCKET, HSL_COS_REGION, HSL_COS_SECRET_ID, HSL_COS_SECRET_KEY): on a server give it a read-only key, not the
account key.
"""
from __future__ import annotations

import argparse
import base64
import configparser
import hashlib
import hmac
import http.server
import json
import os
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = Path(os.environ['HSL_DEPLOY_CONFIG']) if os.environ.get('HSL_DEPLOY_CONFIG') else ROOT / 'ignored' / 'web' / 'deploy.json'
LOCAL = {'.html', '.js', '.json', '.png'}  # served here (all small): page, loader script, manifest, icons
TYPES = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png',
         '.wasm': 'application/wasm', '.pck': 'application/octet-stream'}
BOOT_WINDOW = 14 * 86400  # boot-file links change every two weeks and stay valid for four
PACK_EXPIRES = 3600


def settings() -> dict:
    if os.environ.get('HSL_COS_BUCKET'):
        return {'bucket': os.environ['HSL_COS_BUCKET'], 'region': os.environ['HSL_COS_REGION'],
                'id': os.environ['HSL_COS_SECRET_ID'], 'key': os.environ['HSL_COS_SECRET_KEY']}
    cfg = json.loads(CONFIG.read_text(encoding='utf-8'))
    if cfg['credentials'] == 'env':
        return {'bucket': cfg['bucket'], 'region': cfg['region'], 'id': os.environ['TENCENTCLOUD_SECRET_ID'], 'key': os.environ['TENCENTCLOUD_SECRET_KEY']}
    creds = configparser.ConfigParser()
    creds.read(Path(cfg['credentials']).expanduser())
    section = creds['common'] if 'common' in creds else creds[creds.sections()[0]]
    return {'bucket': cfg['bucket'], 'region': cfg['region'], 'id': section['secret_id'], 'key': section['secret_key']}


def cos_url(conf: dict, key: str, start: int, end: int) -> str:
    """A COS presigned GET URL valid from start to end (unix seconds); the same inputs always give the same string."""
    key_time = f'{start};{end}'
    sign_key = hmac.new(conf['key'].encode(), key_time.encode(), hashlib.sha1).hexdigest()
    path = '/' + urllib.parse.quote(key, safe='/~')
    http_string = f'get\n{path}\n\n\n'  # kept out of the f-string below: Python 3.11 allows no backslash inside an expression
    to_sign = f'sha1\n{key_time}\n{hashlib.sha1(http_string.encode()).hexdigest()}\n'
    signature = hmac.new(sign_key.encode(), to_sign.encode(), hashlib.sha1).hexdigest()
    return (f'https://{conf["bucket"]}.cos.{conf["region"]}.myqcloud.com{path}?q-sign-algorithm=sha1&q-ak={conf["id"]}'
            f'&q-sign-time={key_time}&q-key-time={key_time}&q-header-list=&q-url-param-list=&q-signature={signature}')


def cos_get(conf: dict, key: str) -> bytes:
    now = int(time.time())
    with urllib.request.urlopen(cos_url(conf, key, now - 60, now + 300), timeout=30) as response:
        return response.read()


class Release:
    """latest.json -> release id -> file table (size, sha256 and object key per path), refreshed at most every few seconds."""

    def __init__(self, conf: dict) -> None:
        self.conf = conf
        self.lock = threading.Lock()
        self.checked = 0.0
        self.id = ''
        self.files: dict[str, dict] = {}
        self.small: dict[str, bytes] = {}

    def current(self) -> str:
        with self.lock:
            if time.time() - self.checked > 5:
                self.checked = time.time()
                latest = json.loads(cos_get(self.conf, 'latest.json'))['release']
                if latest != self.id:
                    info = json.loads(cos_get(self.conf, f'releases/{latest}/release.json'))
                    # older releases have no per-file key: their objects sit under releases/<id>/
                    self.files = {row['path']: {'size': row['size'], 'sha256': row.get('sha256', ''), 'key': row.get('key') or f'releases/{latest}/{row["path"]}'}
                                  for row in info['files']}
                    self.small = {}
                    self.id = latest
            return self.id

    def body(self, path: str) -> bytes:
        with self.lock:
            if path not in self.small:
                self.small[path] = cos_get(self.conf, self.files[path]['key'])
            return self.small[path]


class Auth:
    """HTTP Basic against `user:password` pairs given on the command line and/or in a users file (re-read when it changes,
    so adding or removing someone needs no restart). Five wrong passwords from one address block it for five minutes."""

    LIMIT, WINDOW = 5, 300

    def __init__(self, pairs: list[str], users_file: str | None) -> None:
        self.static = pairs
        self.file = Path(users_file) if users_file else None
        self.mtime = -1.0
        self.from_file: list[str] = []
        self.failures: dict[str, list[float]] = {}
        self.lock = threading.Lock()

    def pairs(self) -> list[str]:
        if self.file:
            try:
                mtime = self.file.stat().st_mtime
                if mtime != self.mtime:
                    lines = [line.strip() for line in self.file.read_text(encoding='utf-8').splitlines()]
                    self.from_file = [line for line in lines if ':' in line and not line.startswith('#')]
                    self.mtime = mtime
            except OSError:
                pass
        return self.static + self.from_file

    def user(self, header: str) -> str | None:
        if not header.startswith('Basic '):
            return None
        try:
            given = base64.b64decode(header[6:]).decode('utf-8', 'replace')
        except ValueError:
            return None
        found = None
        for pair in self.pairs():
            if hmac.compare_digest(given, pair):
                found = pair.split(':', 1)[0]
        return found

    def blocked(self, ip: str) -> bool:
        with self.lock:
            recent = [t for t in self.failures.get(ip, []) if time.time() - t < self.WINDOW]
            self.failures[ip] = recent
            return len(recent) >= self.LIMIT

    def failed(self, ip: str) -> None:
        with self.lock:
            self.failures.setdefault(ip, []).append(time.time())


def make_handler(release: Release, conf: dict, auth: Auth, open_for_testing: bool = False):
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = 'hsl-gate'
        protocol_version = 'HTTP/1.1'

        def log_message(self, fmt: str, *a) -> None:
            if os.environ.get('HSL_WEB_VERBOSE'):
                super().log_message(fmt, *a)

        def client_ip(self) -> str:
            peer = self.client_address[0]
            forwarded = self.headers.get('X-Forwarded-For', '')
            return forwarded.split(',')[0].strip() if peer in ('127.0.0.1', '::1') and forwarded else peer

        def reply(self, code: int, body: bytes = b'', ctype: str = 'text/plain', extra: dict[str, str] | None = None) -> None:
            headers = {'Content-Type': ctype, 'Content-Length': str(len(body)), 'Cache-Control': 'no-store'}
            headers.update(extra or {})
            self.send_response(code)
            for name, value in headers.items():
                self.send_header(name, value)
            self.end_headers()
            if self.command != 'HEAD' and code != 304:
                self.wfile.write(body)

        def serve(self) -> None:
            ip = self.client_ip()
            if auth.blocked(ip):
                return self.reply(429, b'too many wrong passwords, try again in a few minutes', extra={'Retry-After': '300'})
            header = self.headers.get('Authorization', '')
            user = 'test' if open_for_testing else auth.user(header)
            if user is None:
                if header:
                    auth.failed(ip)
                    print(f'denied ip={ip}', flush=True)
                return self.reply(401, extra={'WWW-Authenticate': 'Basic realm="hsl"'})
            path = urllib.parse.urlsplit(self.path).path.lstrip('/') or 'index.html'
            try:
                release.current()
            except Exception as error:  # COS or latest.json unreachable
                return self.reply(502, f'release unavailable: {error}'.encode())
            if path == 'index.html':
                print(f'login user={user} ip={ip}', flush=True)
            entry = release.files.get(path)
            if entry is None:
                return self.reply(404)
            suffix = Path(path).suffix.lower()
            if suffix in LOCAL:
                etag = f'"{entry["sha256"][:32]}"' if entry['sha256'] else ''
                extra = {'Cache-Control': 'no-cache', **({'ETag': etag} if etag else {})}
                seen = [tag.strip().removeprefix('W/') for tag in self.headers.get('If-None-Match', '').split(',')]
                if etag and etag in seen:
                    return self.reply(304, extra=extra)
                return self.reply(200, release.body(path), TYPES[suffix], extra)
            now = int(time.time())
            if path.startswith('packs/'):
                start, end = now - 60, now + PACK_EXPIRES
            else:
                start = now // BOOT_WINDOW * BOOT_WINDOW
                end = start + 2 * BOOT_WINDOW
            return self.reply(302, extra={'Location': cos_url(conf, entry['key'], start, end)})

        do_GET = serve
        do_HEAD = serve

    return Handler


def cmd_cors(args: argparse.Namespace) -> int:
    import boto3
    from botocore.config import Config
    conf = settings()
    s3 = boto3.client('s3', endpoint_url=f'https://cos.{conf["region"]}.myqcloud.com', region_name=conf['region'],
                      aws_access_key_id=conf['id'], aws_secret_access_key=conf['key'],
                      config=Config(s3={'addressing_style': 'virtual'}, request_checksum_calculation='when_required', response_checksum_validation='when_required'))

    def add_md5(request, **_):  # COS insists on Content-MD5 for this call; the SDK sends a CRC32 instead
        body = request.body.encode() if isinstance(request.body, str) else request.body
        request.headers['Content-MD5'] = base64.b64encode(hashlib.md5(body).digest()).decode()
    s3.meta.events.register('before-sign.s3.PutBucketCors', add_md5)
    s3.put_bucket_cors(Bucket=conf['bucket'], CORSConfiguration={'CORSRules': [{
        'AllowedOrigins': args.origin, 'AllowedMethods': ['GET', 'HEAD'], 'AllowedHeaders': ['*'],
        'ExposeHeaders': ['Content-Length', 'Content-Range', 'ETag'], 'MaxAgeSeconds': 3600}]})
    print(f'CORS on {conf["bucket"]}: GET/HEAD from {", ".join(args.origin)}')
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    conf = settings()
    release = Release(conf)
    release.current()
    pairs = list(args.auth or []) + ([os.environ['HSL_GATE_AUTH']] if os.environ.get('HSL_GATE_AUTH') else [])
    server = http.server.ThreadingHTTPServer((args.bind, args.port), make_handler(release, conf, Auth(pairs, args.users_file), args.no_auth_for_testing))
    print(f'gate on http://{args.bind}:{args.port}/  release {release.id}  (password protected; big files redirect to COS)', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--auth', metavar='USER:PASSWORD', action='append', help='repeatable; or use --users-file')
    parser.add_argument('--users-file', metavar='PATH', help='lines of user:password, re-read when the file changes')
    parser.add_argument('--port', type=int, default=8088)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--no-auth-for-testing', action='store_true', help='skip the password; only accepted on 127.0.0.1 (browser tests that must not use request interception)')
    sub = parser.add_subparsers(dest='command')
    cors = sub.add_parser('cors', help='allow GET/HEAD from the given page origins on the bucket')
    cors.add_argument('--origin', action='append', required=True)
    cors.set_defaults(func=cmd_cors)
    args = parser.parse_args(argv)
    if args.command == 'cors':
        return args.func(args)
    if args.no_auth_for_testing:
        if args.bind != '127.0.0.1':
            parser.error('--no-auth-for-testing is only allowed with --bind 127.0.0.1')
    elif not (args.auth or args.users_file or os.environ.get('HSL_GATE_AUTH')):
        parser.error('give --auth USER:PASSWORD and/or --users-file PATH to serve')
    return cmd_serve(args)


if __name__ == '__main__':
    sys.exit(main())
