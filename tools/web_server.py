#!/usr/bin/env python3
"""Install and run the web gate (tools/web_gate.py) behind Caddy on a small Linux server, over ssh.

The server only fronts the game: it checks the password, serves the page and the manifest, and redirects every big
file to COS (see web_gate.py), so its own bandwidth does not matter. Caddy terminates HTTPS for the bare IP with a
Let's Encrypt short-lived IP certificate (renewed automatically; needs TCP 80 and 443 open to the internet). The gate
holds a read-only COS key in /etc/hsl-gate/env (written once, never by this script). Updating the game is
`web_deploy.py push` and needs no server work; this script is for the server itself: first install, a new gate
version (re-run install), people (users), and a look at it (status, logs).

    python3 tools/web_server.py install --host SSH_ALIAS --ip PUBLIC_IP --caddy PATH_TO_LINUX_AMD64_CADDY
    python3 tools/web_server.py users list|add NAME|remove NAME --host SSH_ALIAS
    python3 tools/web_server.py status --host SSH_ALIAS
    python3 tools/web_server.py logs [-n 60] --host SSH_ALIAS

--host is an ssh alias or user@address; HSL_WEB_HOST in the environment stands in for it.
"""
from __future__ import annotations

import argparse
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

GATE_UNIT = """[Unit]
Description=hsl web gate (password, page and manifest here, big files redirect to COS)
After=network-online.target
Wants=network-online.target

[Service]
User=hslgate
Group=hslgate
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/etc/hsl-gate/env
ExecStart=/usr/bin/python3 /opt/hsl-gate/web_gate.py --users-file /etc/hsl-gate/users --bind 127.0.0.1 --port 8088
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
"""

CADDY_UNIT = """[Unit]
Description=Caddy (HTTPS in front of the hsl gate)
After=network-online.target hsl-gate.service
Wants=network-online.target

[Service]
User=caddy
Group=caddy
Environment=HOME=/var/lib/caddy XDG_DATA_HOME=/var/lib/caddy/data XDG_CONFIG_HOME=/var/lib/caddy/config
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576
Restart=on-failure

[Install]
WantedBy=multi-user.target
"""

CADDYFILE = """{{
	# a client that opens https://<ip> sends no SNI and the machine only knows its private address (NAT), so name the certificate
	default_sni {ip}
}}

# the bare IP gets a publicly trusted certificate from Let's Encrypt's short-lived profile (6 days, renewed by Caddy)
http://{ip} {{
	redir https://{ip}{{uri}} permanent
}}

https://{ip} {{
	tls {{
		issuer acme {{
			profile shortlived
		}}
	}}
	encode zstd gzip
	reverse_proxy 127.0.0.1:8088
}}
"""


def say(message: str) -> None:
    print(message, flush=True)


def ssh(host: str, script: str, check: bool = True) -> subprocess.CompletedProcess:
    done = subprocess.run(['ssh', '-o', 'BatchMode=yes', host, 'bash', '-s'], input=script, capture_output=True, text=True)
    if check and done.returncode != 0:
        raise SystemExit(f'ssh {host} failed ({done.returncode}):\n{done.stdout[-1500:]}\n{done.stderr[-1500:]}')
    return done


def scp(host: str, local: Path, remote: str) -> None:
    done = subprocess.run(['scp', '-q', '-o', 'BatchMode=yes', str(local), f'{host}:{remote}'], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f'scp {local} failed: {done.stderr[-500:]}')


def cmd_install(args: argparse.Namespace) -> int:
    caddy = Path(args.caddy).resolve()
    if not caddy.exists():
        raise SystemExit(f'{caddy} not found; pass a linux/amd64 caddy binary (v2.10+ for IP certificates)')
    if ssh(args.host, 'test -s /etc/hsl-gate/env && echo present || echo missing').stdout.strip() != 'present':
        raise SystemExit('/etc/hsl-gate/env is missing: it holds the read-only COS key (HSL_COS_BUCKET, HSL_COS_REGION, '
                         'HSL_COS_SECRET_ID, HSL_COS_SECRET_KEY) and is written once, outside this script')
    ssh(args.host, 'install -d -m 0755 /opt/hsl-gate /etc/caddy')
    say('copying the gate and caddy')
    scp(args.host, ROOT / 'tools' / 'web_gate.py', '/opt/hsl-gate/web_gate.py.new')
    local_sum = subprocess.run(['shasum', '-a', '256', str(caddy)], capture_output=True, text=True).stdout.split()[0]
    remote_sum = ssh(args.host, "sha256sum /usr/local/bin/caddy 2>/dev/null | cut -d' ' -f1", check=False).stdout.strip()
    if local_sum != remote_sum:
        scp(args.host, caddy, '/usr/local/bin/caddy.new')
    say('preparing users and units')
    ssh(args.host, f"""set -euo pipefail
id hslgate >/dev/null 2>&1 || useradd --system --home-dir /opt/hsl-gate --shell /sbin/nologin hslgate
id caddy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/caddy --create-home --shell /sbin/nologin caddy
chown root:hslgate /etc/hsl-gate && chmod 0750 /etc/hsl-gate
chown root:hslgate /etc/hsl-gate/env && chmod 0640 /etc/hsl-gate/env
touch /etc/hsl-gate/users && chown root:hslgate /etc/hsl-gate/users && chmod 0640 /etc/hsl-gate/users
/usr/bin/python3 -m py_compile /opt/hsl-gate/web_gate.py.new || {{ echo 'the new gate does not compile with the server python; nothing was replaced' >&2; rm -f /opt/hsl-gate/web_gate.py.new; exit 1; }}
mv -f /opt/hsl-gate/web_gate.py.new /opt/hsl-gate/web_gate.py
chmod 0755 /opt/hsl-gate/web_gate.py
[ -f /usr/local/bin/caddy.new ] && mv -f /usr/local/bin/caddy.new /usr/local/bin/caddy
chmod 0755 /usr/local/bin/caddy
/usr/bin/python3 --version >/dev/null
cat > /etc/systemd/system/hsl-gate.service <<'UNIT'
{GATE_UNIT}UNIT
cat > /etc/systemd/system/caddy.service <<'UNIT'
{CADDY_UNIT}UNIT
cat > /etc/caddy/Caddyfile <<'CADDY'
{CADDYFILE.format(ip=args.ip)}CADDY
/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl daemon-reload
systemctl enable hsl-gate caddy >/dev/null 2>&1
systemctl restart hsl-gate
sleep 2
systemctl restart caddy
""")
    say('installed; certificate request is in flight (see: status, logs)')
    return 0


def user_names(host: str) -> list[str]:
    out = ssh(host, "cut -d: -f1 /etc/hsl-gate/users").stdout
    return [line for line in out.splitlines() if line.strip()]


def cmd_users(args: argparse.Namespace) -> int:
    if args.action == 'list':
        names = user_names(args.host)
        say('users: ' + (', '.join(names) if names else '(none)'))
        return 0
    if not args.name or not re.fullmatch(r'[A-Za-z0-9_.-]+', args.name):
        raise SystemExit('give a NAME of letters, digits, _ . -')
    if args.action == 'add':
        if args.name in user_names(args.host):
            raise SystemExit(f'{args.name} already exists; remove it first to change its password')
        password = secrets.token_urlsafe(9)
        ssh(args.host, f"umask 027 && echo '{args.name}:{password}' >> /etc/hsl-gate/users && chgrp hslgate /etc/hsl-gate/users")
        say(f'added {args.name}  password: {password}   (shown once; the gate picks it up within seconds)')
    else:
        ssh(args.host, f"sed -i '/^{re.escape(args.name)}:/d' /etc/hsl-gate/users")
        say(f'removed {args.name}')
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    out = ssh(args.host, """for s in hsl-gate caddy; do printf '%-10s %s\\n' $s "$(systemctl is-active $s)"; done
echo "users: $(grep -c : /etc/hsl-gate/users)"
ip=$(grep -m1 '^https://' /etc/caddy/Caddyfile | sed 's#https://##; s# .*##')
echo "gate through caddy on $ip (expect 401): $(curl -sk --connect-to $ip:443:127.0.0.1:443 -o /dev/null -w '%{http_code}' https://$ip/ || echo no-answer)"
cert=$(find /var/lib/caddy/data -name '*.crt' 2>/dev/null | head -1)
if [ -n "$cert" ]; then echo "certificate: $cert"; openssl x509 -in "$cert" -noout -issuer -subject -enddate 2>/dev/null; else echo "certificate: none yet"; fi
""", check=False).stdout
    say(out.rstrip())
    return 0


def cmd_logs(args: argparse.Namespace) -> int:
    say(ssh(args.host, f'journalctl -u hsl-gate -u caddy -n {int(args.n)} --no-pager -o short-iso', check=False).stdout.rstrip())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('install')
    p.add_argument('--host', default=os.environ.get('HSL_WEB_HOST'), help='ssh alias or user@address of the server')
    p.add_argument('--ip', required=True, help='the public IP the gate answers on (also the certificate name)')
    p.add_argument('--caddy', required=True, help='a linux/amd64 caddy binary')
    p.set_defaults(func=cmd_install)
    p = sub.add_parser('users')
    p.add_argument('action', choices=['list', 'add', 'remove'])
    p.add_argument('name', nargs='?')
    p.add_argument('--host', default=os.environ.get('HSL_WEB_HOST'), help='ssh alias or user@address of the server')
    p.set_defaults(func=cmd_users)
    p = sub.add_parser('status')
    p.add_argument('--host', default=os.environ.get('HSL_WEB_HOST'), help='ssh alias or user@address of the server')
    p.set_defaults(func=cmd_status)
    p = sub.add_parser('logs')
    p.add_argument('-n', default='60')
    p.add_argument('--host', default=os.environ.get('HSL_WEB_HOST'), help='ssh alias or user@address of the server')
    p.set_defaults(func=cmd_logs)
    args = parser.parse_args(argv)
    if not args.host:
        raise SystemExit('give --host (an ssh alias or user@address) or set HSL_WEB_HOST')
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
