#!/usr/bin/env python3
"""Publish the web build to a private Tencent COS bucket as versioned releases (incremental, with rollback).

COS is the release store, not a public host: the bucket stays private because the build carries
original-derived assets, and a front door with a password serves the current release. The small files of a release
(page, loader script, icons, manifest) sit in releases/<id>/; every .wasm and .pck sits once under blobs/<sha256>/ and is
shared by all releases that carry it, so an unchanged engine, core or pack costs nothing (not uploaded, not stored
twice, and the browser keeps its cached copy because its link does not change). releases/<id>/release.json lists
every file with size, sha256 and object key. latest.json is written last and is the only switch; rollback points it at an
older release; pruning old releases also removes blobs nothing refers to. The credentials file (coscmd format,
secret_id and secret_key) is read, never copied.

    python3 tools/web_deploy.py init --bucket NAME --region ap-shanghai [--credentials ~/.cos.conf|env] [--create]
    python3 tools/web_deploy.py push [--dist DIR] [--keep 3] [--dry-run]
    python3 tools/web_deploy.py releases
    python3 tools/web_deploy.py rollback RELEASE
    python3 tools/web_deploy.py check
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import configparser
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    import boto3
    from boto3.s3.transfer import TransferConfig
    from botocore.config import Config
    from botocore.exceptions import ClientError
except ImportError:
    raise SystemExit('web_deploy.py talks to COS through its S3 API and needs boto3: pip install boto3')

from web_release import (DIST, THREADS, WORK, cache_control, content_type, dist_files, encode_blobs, hash_files, is_blob, json_bytes,
                         mb, new_release_id, now_iso, object_keys, release_record, say, stored_files)

CONFIG = Path(os.environ['HSL_DEPLOY_CONFIG']) if os.environ.get('HSL_DEPLOY_CONFIG') else WORK / 'deploy.json'


def load_config() -> dict:
    if not CONFIG.exists():
        raise SystemExit(f'no {CONFIG}; run: python3 tools/web_deploy.py init --bucket NAME --region REGION')
    return json.loads(CONFIG.read_text(encoding='utf-8'))


def client(cfg: dict):
    if cfg['credentials'] == 'env':  # keys injected by the caller (a secrets manager wrapping this command), never stored here
        key_id, key = os.environ['TENCENTCLOUD_SECRET_ID'], os.environ['TENCENTCLOUD_SECRET_KEY']
    else:
        creds = configparser.ConfigParser()
        creds.read(Path(cfg['credentials']).expanduser())
        section = creds['common'] if 'common' in creds else creds[creds.sections()[0]]
        key_id, key = section['secret_id'], section['secret_key']
    s3 = boto3.client(
        's3', endpoint_url=f'https://cos.{cfg["region"]}.myqcloud.com', region_name=cfg['region'],
        aws_access_key_id=key_id, aws_secret_access_key=key,
        # COS speaks the S3 API but not the newer default checksum headers, and only virtual-hosted addressing
        config=Config(s3={'addressing_style': 'virtual'}, retries={'max_attempts': 5}, max_pool_connections=THREADS * 2,
                      request_checksum_calculation='when_required', response_checksum_validation='when_required'))

    def add_md5(request, **_):  # COS insists on Content-MD5 for multi-object delete (and bucket CORS); the SDK sends a CRC32
        body = request.body.encode() if isinstance(request.body, str) else request.body
        request.headers['Content-MD5'] = base64.b64encode(hashlib.md5(body).digest()).decode()
    s3.meta.events.register('before-sign.s3.DeleteObjects', add_md5)
    return s3


def get_json(s3, bucket: str, key: str):
    try:
        return json.loads(s3.get_object(Bucket=bucket, Key=key)['Body'].read())
    except ClientError as error:
        if error.response['Error']['Code'] in ('NoSuchKey', '404'):
            return None
        raise


def put_json(s3, bucket: str, key: str, value: dict) -> None:
    s3.put_object(Bucket=bucket, Key=key, Body=json_bytes(value), ContentType='application/json', CacheControl='no-cache')


def release_ids(s3, bucket: str) -> list[str]:
    ids: list[str] = []
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix='releases/', Delimiter='/'):
        ids += [p['Prefix'].split('/')[1] for p in page.get('CommonPrefixes', [])]
    return sorted(ids)


def cmd_init(args: argparse.Namespace) -> int:
    WORK.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps({'bucket': args.bucket, 'region': args.region, 'credentials': args.credentials}, indent=1) + '\n', encoding='utf-8')
    say(f'wrote {CONFIG}')
    if args.create:  # a new bucket is private by default; check then proves it
        try:
            client(load_config()).create_bucket(Bucket=args.bucket)
            say(f'created bucket {args.bucket}')
        except ClientError as error:
            if error.response['Error']['Code'] not in ('BucketAlreadyOwnedByYou', 'BucketAlreadyExists'):
                raise
    return cmd_check(args)


def cmd_push(args: argparse.Namespace) -> int:
    cfg = load_config()
    s3, bucket = client(cfg), cfg['bucket']
    dist = Path(args.dist or DIST).resolve()
    files = dist_files(dist)
    rid, git = new_release_id(dist)
    started = time.time()
    sums = hash_files(files)
    encoded = encode_blobs(files, sums)
    stored = stored_files(files, encoded)
    latest = get_json(s3, bucket, 'latest.json')
    previous = (get_json(s3, bucket, f'releases/{latest["release"]}/release.json') if latest else None) or {'files': []}
    # where each content already lives (a blob, or a file of the previous release written before blobs existed), by its
    # encoding: a plain object must not be copied under an encoded key
    known = {(row['sha256'], row.get('encoding', '')): row.get('key') or f'releases/{previous.get("id", "")}/{row["path"]}' for row in previous['files']}
    blobs = {o['Key']: o['Size'] for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix='blobs/') for o in page.get('Contents', [])}
    keys = object_keys(files, sums, rid, encoded)
    size_of = {rel: stored[rel].stat().st_size for rel in files}
    encoding = {rel: 'gzip' if rel in encoded else '' for rel in files}
    plan = {}
    for rel in files:
        if is_blob(rel) and blobs.get(keys[rel]) == size_of[rel]:
            plan[rel] = 'reuse'
        elif is_blob(rel) and (sums[rel], encoding[rel]) in known:
            plan[rel] = 'copy'
        else:
            plan[rel] = 'upload'
    total = lambda action: (sum(1 for r in files if plan[r] == action), sum(size_of[r] for r in files if plan[r] == action))  # noqa: E731
    say(f'release {rid}: {len(files)} files {mb(sum(size_of.values()))}; already in the bucket {total("reuse")[0]} ({mb(total("reuse")[1])}), '
        f'copied from the previous release {total("copy")[0]} ({mb(total("copy")[1])}), uploaded {total("upload")[0]} ({mb(total("upload")[1])})')
    if args.dry_run:
        return 0
    transfer = TransferConfig(multipart_threshold=32 << 20, multipart_chunksize=16 << 20, max_concurrency=4)

    def headers(rel: str) -> dict:
        extra = {'ContentEncoding': 'gzip'} if encoding[rel] else {}
        return {'ContentType': content_type(rel), 'CacheControl': cache_control(rel), 'Metadata': {'sha256': sums[rel]}, **extra}

    def put(rel: str) -> str:
        if plan[rel] == 'copy':
            source = known[(sums[rel], encoding[rel])]
            s3.copy_object(Bucket=bucket, Key=keys[rel], CopySource={'Bucket': bucket, 'Key': source}, MetadataDirective='REPLACE', **headers(rel))
        elif plan[rel] == 'upload':
            s3.upload_file(str(stored[rel]), bucket, keys[rel], Config=transfer, ExtraArgs=headers(rel))
        return rel

    with concurrent.futures.ThreadPoolExecutor(THREADS) as pool:
        for count, _ in enumerate(pool.map(put, files), 1):
            if count % 40 == 0 or count == len(files):
                say(f'  {count}/{len(files)} files')
    remote = {}
    for prefix in (f'releases/{rid}/', 'blobs/'):
        for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=prefix):
            remote.update({o['Key']: o['Size'] for o in page.get('Contents', [])})
    wrong = [rel for rel in files if remote.get(keys[rel]) != size_of[rel]]
    if wrong:
        raise SystemExit(f'verification failed for {len(wrong)} files, e.g. {wrong[:3]}; latest.json left as it was')
    release = release_record(rid, git, files, sums, keys, encoded)
    put_json(s3, bucket, f'releases/{rid}/release.json', release)
    put_json(s3, bucket, 'latest.json', {'release': rid, 'updated': release['created']})
    say(f'latest.json -> {rid}  ({time.time() - started:.0f}s)')
    if args.keep > 0:
        others = [i for i in release_ids(s3, bucket) if i != rid]
        for old in (others[:-(args.keep - 1)] if args.keep > 1 else others):
            old_keys = [{'Key': o['Key']} for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=f'releases/{old}/') for o in page.get('Contents', [])]
            delete_keys(s3, bucket, old_keys)
            say(f'pruned {old} ({len(old_keys)} objects)')
    collect_blobs(s3, bucket)
    return 0


def delete_keys(s3, bucket: str, keys: list[dict]) -> None:
    for start in range(0, len(keys), 1000):
        s3.delete_objects(Bucket=bucket, Delete={'Objects': keys[start:start + 1000], 'Quiet': True})


def collect_blobs(s3, bucket: str) -> None:
    """Delete blobs no remaining release refers to (run after latest.json moved, so a push never loses its own files)."""
    wanted = set()
    for rid in release_ids(s3, bucket):
        wanted |= {row['key'] for row in (get_json(s3, bucket, f'releases/{rid}/release.json') or {}).get('files', []) if row.get('key')}
    stale = [{'Key': o['Key']} for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix='blobs/') for o in page.get('Contents', []) if o['Key'] not in wanted]
    if stale:
        delete_keys(s3, bucket, stale)
        say(f'collected {len(stale)} blobs no release refers to')


def cmd_releases(args: argparse.Namespace) -> int:
    cfg = load_config()
    s3, bucket = client(cfg), cfg['bucket']
    latest = (get_json(s3, bucket, 'latest.json') or {}).get('release')
    for rid in release_ids(s3, bucket):
        row = get_json(s3, bucket, f'releases/{rid}/release.json') or {}
        say(f'{"*" if rid == latest else " "} {rid}  {mb(row.get("bytes", 0)):>9}  {len(row.get("files", []))} files  {row.get("created", "")}')
    return 0


def cmd_rollback(args: argparse.Namespace) -> int:
    cfg = load_config()
    s3, bucket = client(cfg), cfg['bucket']
    if get_json(s3, bucket, f'releases/{args.release}/release.json') is None:
        raise SystemExit(f'no release {args.release}; see: python3 tools/web_deploy.py releases')
    put_json(s3, bucket, 'latest.json', {'release': args.release, 'updated': now_iso()})
    say(f'latest.json -> {args.release}')
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    cfg = load_config()
    s3, bucket = client(cfg), cfg['bucket']
    acl = s3.get_bucket_acl(Bucket=bucket)
    public = [g for g in acl['Grants'] if g['Grantee'].get('URI')]
    request = urllib.request.Request(f'https://{bucket}.cos.{cfg["region"]}.myqcloud.com/latest.json', method='HEAD')
    try:
        urllib.request.urlopen(request, timeout=15)
        anonymous = 'READABLE BY ANYONE'
    except urllib.error.HTTPError as error:
        anonymous = f'refused ({error.code})'
    latest = (get_json(s3, bucket, 'latest.json') or {}).get('release')
    say(f'bucket {bucket} ({cfg["region"]}): public grants {len(public)}; anonymous GET {anonymous}; latest release {latest or "none yet"}')
    return 1 if public or anonymous.startswith('READABLE') else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('init')
    p.add_argument('--bucket', required=True)
    p.add_argument('--region', required=True)
    p.add_argument('--credentials', default='~/.cos.conf', help="a coscmd-format file, or 'env' for TENCENTCLOUD_SECRET_ID/KEY from the environment")
    p.add_argument('--create', action='store_true', help='create the bucket (private) if it does not exist')
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
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
