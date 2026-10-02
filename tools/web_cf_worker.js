// Cloudflare Worker: the password gate in front of a private R2 release store (the twin of web_gate.py).
//
// Bindings (web_cf.py writes the wrangler config that declares them):
//   RELEASES  R2 bucket  latest.json, releases/<id>/release.json and every object a release table names
//   THROTTLE  KV         wrong-password counters, one key per address
//   USERS     secret     one `name:password` per line
//
// Every file comes straight out of R2 and is streamed back (no redirects, no signed links), so the bytes stay inside
// Cloudflare's network. The release table (path -> size, sha256, object key) is read from R2 and refreshed every few seconds,
// so `web_cf.py push` and `rollback` change what is served almost at once. Only paths in the table are served: there is no
// directory listing and nothing to traverse.

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png',
  '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
};
const LIMIT = 5; // wrong passwords from one address ...
const WINDOW = 300; // ... within this many seconds block it
const REFRESH_MS = 5000; // how often latest.json is looked at
const CLEAR_MS = 120000; // how long "this address is not blocked" is trusted without asking KV again

const release = { checked: 0, id: '', files: new Map(), pending: null };
const recent = new Map(); // address -> { blocked, until }

function extension(path) {
  const dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.slice(dot).toLowerCase();
}

// Packs never (the game keeps them in IndexedDB itself); everything else is revalidated on every visit and answered with a
// 304 while the ETag still matches. Not `immutable` for the engine and the core as web_release.cache_control does for COS:
// there their link names the content, here /index.pck is the same URL in every release, so a year-long cache would pin a
// returning visitor to the first core they ever downloaded.
function cacheControl(path) {
  return path.startsWith('packs/') && extension(path) === '.pck' ? 'no-store' : 'no-cache';
}

function reply(status, body = '', extra = {}) {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store', ...extra } });
}

async function digest(text) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
}

// HTTP Basic against the USERS secret; every line is compared (as equal-length digests, in constant time) so the work does
// not depend on which user matched
async function userOf(header, users) {
  if (!header.startsWith('Basic ')) return null;
  let given;
  try {
    given = new TextDecoder().decode(Uint8Array.from(atob(header.slice(6)), (c) => c.charCodeAt(0)));
  } catch {
    return null;
  }
  const want = await digest(given);
  let found = null;
  for (const line of users.split('\n')) {
    const pair = line.trim();
    if (!pair.includes(':') || pair.startsWith('#')) continue;
    if (crypto.subtle.timingSafeEqual(want, await digest(pair))) found = pair.slice(0, pair.indexOf(':'));
  }
  return found;
}

// Five wrong passwords from one address block it for five minutes. The block is checked before the password, as in
// web_gate.py, so a blocked address learns nothing about a guess. KV is eventually consistent and a failed read or write
// is ignored: this is a brake on guessing, the passwords themselves are long random strings.
async function isBlocked(env, ip) {
  const now = Date.now();
  const known = recent.get(ip);
  if (known && known.until > now) return known.blocked;
  let record = null;
  try {
    record = await env.THROTTLE.get(`fail:${ip}`, 'json');
  } catch {
    // not blocked if KV cannot be read
  }
  const blocked = !!record && record.n >= LIMIT;
  recent.set(ip, { blocked, until: now + (blocked ? 30000 : CLEAR_MS) });
  return blocked;
}

async function noteFailure(env, ip) {
  const key = `fail:${ip}`;
  let record = null;
  try {
    record = await env.THROTTLE.get(key, 'json');
  } catch {
    // start counting again
  }
  record = record || { n: 0, t: Date.now() };
  record.n += 1;
  try {
    await env.THROTTLE.put(key, JSON.stringify(record), { expirationTtl: WINDOW });
  } catch {
    // the in-memory count below still holds for this isolate
  }
  const blocked = record.n >= LIMIT;
  recent.set(ip, { blocked, until: Date.now() + (blocked ? WINDOW * 1000 : CLEAR_MS) });
}

async function currentRelease(env) {
  if (release.files.size && Date.now() - release.checked < REFRESH_MS) return release;
  release.pending ??= (async () => {
    const latestObject = await env.RELEASES.get('latest.json');
    if (!latestObject) throw new Error('no latest.json in the bucket');
    const latest = await latestObject.json();
    if (latest.release !== release.id) {
      const tableObject = await env.RELEASES.get(`releases/${latest.release}/release.json`);
      if (!tableObject) throw new Error(`no release.json for ${latest.release}`);
      const info = await tableObject.json();
      // older releases may carry no per-file key: their objects sit under releases/<id>/
      release.files = new Map(info.files.map((row) => [row.path, {
        size: row.size, sha256: row.sha256 || '', key: row.key || `releases/${latest.release}/${row.path}`, encoding: row.encoding || '',
      }]));
      release.id = latest.release;
    }
    release.checked = Date.now();
  })().finally(() => { release.pending = null; });
  await release.pending;
  return release;
}

// A single `bytes=a-b`, `bytes=a-` or `bytes=-n` range against a file of `size` bytes: { offset, length }, 'unsatisfiable',
// or null for anything else (no header, malformed, several ranges), which is answered with the whole file as the spec allows.
function parseRange(header, size) {
  const match = /^bytes=(\d*)-(\d*)$/.exec((header || '').trim());
  if (!match || (match[1] === '' && match[2] === '')) return null;
  if (match[1] === '') {
    const last = Number(match[2]);
    return last === 0 || size === 0 ? 'unsatisfiable' : { offset: Math.max(0, size - last), length: Math.min(last, size) };
  }
  const first = Number(match[1]);
  if (match[2] !== '' && Number(match[2]) < first) return null;
  if (first >= size) return 'unsatisfiable';
  const end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
  return { offset: first, length: end - first + 1 };
}

// An encoded blob (web_release.py: stored gzip-encoded, the table says `encoding`) goes out as stored with Content-Encoding and
// encodeBody 'manual', so the runtime neither compresses it again nor inflates it; the browser does. No ranges on those.
async function serve(request, env, path, entry) {
  const policy = cacheControl(path);
  const etag = policy === 'no-store' || !entry.sha256 ? '' : `"${entry.sha256.slice(0, 32)}"`;
  const headers = new Headers({ 'Cache-Control': policy, 'Content-Type': TYPES[extension(path)] || 'application/octet-stream' });
  if (entry.encoding) headers.set('Content-Encoding', entry.encoding);
  else headers.set('Accept-Ranges', 'bytes');
  if (etag) headers.set('ETag', etag);
  const seen = (request.headers.get('If-None-Match') || '').split(',').map((tag) => tag.trim().replace(/^W\//, ''));
  if (etag && seen.includes(etag)) {
    headers.delete('Content-Type');
    return new Response(null, { status: 304, headers });
  }
  if (request.method === 'HEAD') {
    const head = await env.RELEASES.head(entry.key);
    if (!head) return reply(404, 'object missing');
    headers.set('Content-Length', String(head.size));
    return new Response(null, { status: 200, headers });
  }
  const wanted = entry.encoding ? null : parseRange(request.headers.get('Range'), entry.size);
  if (wanted === 'unsatisfiable') return reply(416, 'range not satisfiable', { 'Content-Range': `bytes */${entry.size}` });
  const object = await env.RELEASES.get(entry.key, wanted ? { range: wanted } : {});
  if (!object) return reply(404, 'object missing');
  if (wanted) {
    headers.set('Content-Range', `bytes ${wanted.offset}-${wanted.offset + wanted.length - 1}/${object.size}`);
    headers.set('Content-Length', String(wanted.length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set('Content-Length', String(object.size));
  return new Response(object.body, entry.encoding ? { status: 200, headers, encodeBody: 'manual' } : { status: 200, headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // a password must never travel over plain http: send every http visitor to https before anything is checked
    if (url.protocol === 'http:' && url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 308);
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') return reply(405, 'method not allowed', { Allow: 'GET, HEAD' });
    if (!env.USERS) return reply(500, 'the gate is not configured: no USERS secret');
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    if (await isBlocked(env, ip)) return reply(429, 'too many wrong passwords, try again in a few minutes', { 'Retry-After': String(WINDOW) });
    const header = request.headers.get('Authorization') || '';
    const user = await userOf(header, env.USERS);
    if (user === null) {
      if (header) {
        await noteFailure(env, ip);
        console.log(`denied ip=${ip}`);
      }
      return reply(401, '', { 'WWW-Authenticate': 'Basic realm="hsl"' });
    }
    let path;
    try {
      path = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    } catch {
      return reply(404, 'not found');
    }
    if (path === '') path = 'index.html';
    let table;
    try {
      table = await currentRelease(env);
    } catch (error) {
      return reply(502, `release unavailable: ${error.message}`);
    }
    if (path === 'index.html') console.log(`login user=${user} ip=${ip}`);
    const entry = table.files.get(path);
    if (!entry) return reply(404, 'not found');
    return serve(request, env, path, entry);
  },
};
