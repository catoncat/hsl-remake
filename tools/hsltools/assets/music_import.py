"""Import the 18 original music tracks (music\\02.wav–19.wav of the user-owned Steam 經典版) as
tracked, seamlessly looping Ogg Vorbis files.

The Steam folder stays outside the repository and is only read (hsltools.paths.STEAM_CLASSIC_ROOT,
env HSL_STEAM_CLASSIC). Every music\\NN.wav must match the size and sha1 pinned in
docs/evidence_packets/resource_inventory/steam_classic_files.json. The pinned music\\null.wav is not
a track: PlayMusic 0x42c250 only opens music\\%02d.wav, and the original plays null.wav once at
audio initialisation as a warm-up. The manifest records it as an exclusion.

Remake-side decisions (this tool's own, not original facts):

* Ogg Vorbis through libsndfile (python-soundfile), compression level 0.4 (about Vorbis quality 6,
  ~105 kbps nominal at 22050 Hz stereo). Nothing is resampled, gained or trimmed: each Ogg holds
  exactly the source's sample frames (last granule position == WAV frames). A whole-track loop
  from frame 0 therefore repeats the original gapless loop: the original stream player 0x45a0b0
  seeks back to the data start (refill 0x459ec0) and has no loop point.
* libsndfile draws a random Ogg stream serial. The tool rewrites every page's serial to
  0x48534C00 + track and recomputes the page CRCs, so the same input and settings give the same
  bytes. generate also keeps a track untouched (no re-encode, no rewrite) when its pinned source,
  the encoding settings and the tracked Ogg's sha1 all equal the manifest.
* Playback loops the whole track from offset 0. Godot import sidecars are not tracked (AGENTS.md),
  so project.godot [importer_defaults] oggvorbisstr sets loop=true for every Ogg on first import.

Outputs: content/imported/hsl/music/NN.ogg (NN = original track number) and manifest.json
(hsl_music_import.v1).

Registry task music_import (family assets). check never reads the Steam folder. It checks:
* the manifest against the pinned list and this tool's settings;
* the tracked Ogg sizes and sha1s;
* every Ogg page: one serial, contiguous sequence, BOS/EOS, CRC, and a Vorbis identification
  header of 22050 Hz stereo;
* that the last granule position equals the source frames, for exactly tracks 02–19.

generate needs the Steam folder (NotGeneratable when it is absent or differs from the pinned list).
To (re)encode it also needs soundfile:

    uv run --no-project --with soundfile --with pillow python3 tools/hsl.py generate music_import

This is a plain Task, not a ScriptCheckTask: its source is the Steam folder, not a PAK next to the
documented EXE (compare hsltools.data.OriginalArchiveTask).
"""
from __future__ import annotations

import hashlib
import io
import json
import struct
import zlib
from pathlib import Path
from typing import Any, Iterator

from hsltools.paths import STEAM_CLASSIC_ROOT
from hsltools.registry import CheckFailed, Context, NotGeneratable, Task

SCHEMA = 'hsl_music_import.v1'
OUT_DIR = 'content/imported/hsl/music'
MANIFEST = f'{OUT_DIR}/manifest.json'
PINNED = 'docs/evidence_packets/resource_inventory/steam_classic_files.json'
TRACKS = tuple(range(2, 20))
RATE, CHANNELS, BITS = 22050, 2, 16
COMPRESSION_LEVEL = 0.4
# Frames per libsndfile write. libvorbis' _preextrapolate_helper allocas one float per frame of
# the first write, so one whole-track write over ~2M frames (track 12 onwards) overflows the
# 8 MB main-thread stack. The block size shapes that start-of-stream extrapolation, so it is
# an encoding setting.
WRITE_BLOCK_FRAMES = 65536
SERIAL_BASE = 0x48534C00
GENERATE_COMMAND = 'uv run --no-project --with soundfile --with pillow python3 tools/hsl.py generate music_import'

# Recorded in the manifest; check requires equality, so changing a setting here fails check until
# generate re-encodes every track.
ENCODING = {
    'container': 'ogg',
    'codec': 'vorbis',
    'encoder': 'libsndfile via python-soundfile',
    'compression_level': COMPRESSION_LEVEL,
    'write_block_frames': WRITE_BLOCK_FRAMES,
    'resampled': False,
    'gain_changed': False,
    'trimmed': False,
    'ogg_serial': '0x48534C00 + track (random libsndfile serial rewritten, page CRCs recomputed)',
}
LOOP = {'whole_track': True, 'offset_frames': 0}
LOOP_SOURCE = ('static-derived: PlayMusic 0x42c250 opens music\\%02d.wav through the stream player 0x45a0b0, '
               'whose refill 0x459ec0 seeks back to the data start at the end of data: every track loops whole, '
               'with no loop point')
EXCLUDED = {
    'music/null.wav': 'not a track: PlayMusic 0x42c250 only opens music\\%02d.wav; the original plays null.wav '
                      'once at audio initialisation as a warm-up',
}


def original_path(name: str) -> str:
    """'music/02.wav' (pinned list spelling) -> 'music\\02.wav' (the original's path)."""
    return name.replace('/', '\\')


def track_name(track: int) -> str:
    return f'music/{track:02d}.wav'


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def pinned_files(root: Path) -> dict[str, dict[str, Any]]:
    """{pinned path: {path, size, sha1}} for the 18 tracks and the exclusions."""
    files = {entry['path']: entry for entry in json.loads((root / PINNED).read_text(encoding='utf-8'))['files']}
    wanted = [track_name(track) for track in TRACKS] + list(EXCLUDED)
    missing = [name for name in wanted if name not in files]
    if missing:
        raise CheckFailed(f'music_import: {PINNED} does not pin {missing}')
    return {name: files[name] for name in wanted}


# --- WAV -------------------------------------------------------------------------------------

def wav_layout(data: bytes, name: str) -> dict[str, int]:
    """fmt and data chunk of a RIFF WAVE file; the tracks must be PCM 22050 Hz stereo 16-bit."""
    if data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise ValueError(f'{name}: not a RIFF WAVE file')
    fmt = None
    data_offset = data_bytes = None
    pos = 12
    while pos + 8 <= len(data):
        chunk, size = data[pos:pos + 4], struct.unpack_from('<I', data, pos + 4)[0]
        if chunk == b'fmt ':
            fmt = struct.unpack_from('<HHIIHH', data, pos + 8)
        elif chunk == b'data':
            data_offset, data_bytes = pos + 8, size
        pos += 8 + size + (size & 1)
    block_align = CHANNELS * BITS // 8
    if fmt != (1, CHANNELS, RATE, RATE * block_align, block_align, BITS):
        raise ValueError(f'{name}: fmt {fmt} is not PCM {RATE} Hz, {CHANNELS} channels, {BITS}-bit')
    if data_offset is None or data_offset + data_bytes > len(data) or data_bytes % block_align:
        raise ValueError(f'{name}: data chunk missing, truncated or not whole frames')
    return {'data_offset': data_offset, 'data_bytes': data_bytes, 'frames': data_bytes // block_align}


def source_entry(pin: dict[str, Any], layout: dict[str, int]) -> dict[str, Any]:
    return {
        'size': pin['size'],
        'sha1': pin['sha1'],
        'data_offset': layout['data_offset'],
        'data_bytes': layout['data_bytes'],
        'rate': RATE,
        'channels': CHANNELS,
        'bits': BITS,
        'frames': layout['frames'],
        'seconds': round(layout['frames'] / RATE, 3),
    }


# --- Ogg -------------------------------------------------------------------------------------

_BITREV = bytes(int(f'{value:08b}'[::-1], 2) for value in range(256))


def ogg_crc(page: bytes) -> int:
    """The Ogg page CRC (polynomial 0x04C11DB7, MSB first, init 0, no final xor), computed through
    zlib's reflected CRC-32: bit-reverse every byte, undo zlib's init and final inversion, then
    bit-reverse the 32-bit result."""
    raw = zlib.crc32(page.translate(_BITREV), 0xFFFFFFFF) ^ 0xFFFFFFFF
    return int(f'{raw:032b}'[::-1], 2)


def ogg_pages(data: bytes) -> Iterator[dict[str, int]]:
    """Every page: start, end (exclusive), body start, header type, granule, serial, sequence, crc."""
    pos = 0
    while pos < len(data):
        if data[pos:pos + 4] != b'OggS' or pos + 27 > len(data):
            raise ValueError(f'no Ogg page header at byte {pos}')
        version, header_type, granule, serial, sequence, crc, segments = struct.unpack_from('<BBqIIIB', data, pos + 4)
        body = pos + 27 + segments
        end = body + sum(data[pos + 27:body])
        if version != 0 or end > len(data):
            raise ValueError(f'Ogg page at byte {pos}: version {version} or truncated')
        yield {'start': pos, 'end': end, 'body': body, 'header_type': header_type, 'granule': granule,
               'serial': serial, 'sequence': sequence, 'crc': crc}
        pos = end


def page_crc(data: bytes | bytearray, page: dict[str, int]) -> int:
    start, end = page['start'], page['end']
    return ogg_crc(bytes(data[start:start + 22]) + b'\0\0\0\0' + bytes(data[start + 26:end]))


def normalise_serial(data: bytes, serial: int) -> bytes:
    """Rewrite every page's stream serial and recompute its CRC (the encoder's serial is random)."""
    out = bytearray(data)
    for page in list(ogg_pages(data)):
        struct.pack_into('<I', out, page['start'] + 14, serial)
        struct.pack_into('<I', out, page['start'] + 22, page_crc(out, page))
    return bytes(out)


def ogg_stream(data: bytes) -> dict[str, int]:
    """Validate one logical Vorbis stream page by page; its serial, channels, rate and frames (the
    last page's granule position = decoded sample frames)."""
    pages = list(ogg_pages(data))
    if len(pages) < 3:
        raise ValueError(f'{len(pages)} Ogg pages (a Vorbis stream needs at least three)')
    serials = {page['serial'] for page in pages}
    if len(serials) != 1:
        raise ValueError(f'{len(serials)} stream serials')
    for index, page in enumerate(pages):
        if page['sequence'] != index:
            raise ValueError(f'page {index} has sequence number {page["sequence"]}')
        if page_crc(data, page) != page['crc']:
            raise ValueError(f'page {index} CRC mismatch')
        bos, eos = bool(page['header_type'] & 2), bool(page['header_type'] & 4)
        if bos != (index == 0) or eos != (index == len(pages) - 1):
            raise ValueError(f'page {index}: BOS {bos} / EOS {eos} out of place')
    granules = [page['granule'] for page in pages if page['granule'] != -1]
    if granules != sorted(granules):
        raise ValueError('granule positions decrease')
    ident = data[pages[0]['body']:pages[0]['end']]
    magic, version, channels, rate = struct.unpack_from('<7sIBI', ident)
    if magic != b'\x01vorbis' or version != 0:
        raise ValueError('first packet is not a Vorbis I identification header')
    return {'serial': serials.pop(), 'channels': channels, 'rate': rate, 'frames': pages[-1]['granule'],
            'pages': len(pages)}


def encode(pcm: bytes, track: int) -> bytes:
    """16-bit PCM -> deterministic Ogg Vorbis bytes (libsndfile encode, serial normalised)."""
    try:
        import numpy
        import soundfile
    except ImportError as error:
        raise NotGeneratable(f'music_import: encoding needs soundfile ({error}); run `{GENERATE_COMMAND}`') from error
    samples = numpy.frombuffer(pcm, dtype='<i2').reshape(-1, CHANNELS)
    buffer = io.BytesIO()
    with soundfile.SoundFile(buffer, 'w', RATE, CHANNELS, format='OGG', subtype='VORBIS',
                             compression_level=COMPRESSION_LEVEL) as out:
        for start in range(0, len(samples), WRITE_BLOCK_FRAMES):
            out.write(samples[start:start + WRITE_BLOCK_FRAMES])
    return normalise_serial(buffer.getvalue(), SERIAL_BASE + track)


# --- manifest --------------------------------------------------------------------------------

def track_entry(track: int, source: dict[str, Any], ogg: bytes, ogg_frames: int) -> dict[str, Any]:
    return {
        'track': track,
        'original_path': original_path(track_name(track)),
        'source': source,
        'ogg': {'path': f'{OUT_DIR}/{track:02d}.ogg', 'size': len(ogg), 'sha1': sha1(ogg), 'frames': ogg_frames},
        'loop': dict(LOOP),
    }


def totals(tracks: list[dict[str, Any]]) -> dict[str, Any]:
    frames = sum(entry['source']['frames'] for entry in tracks)
    return {'tracks': len(tracks), 'frames': frames, 'seconds': round(frames / RATE, 3),
            'ogg_bytes': sum(entry['ogg']['size'] for entry in tracks)}


def manifest_document(tracks: list[dict[str, Any]], pins: dict[str, dict[str, Any]]) -> dict[str, Any]:
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'claim_limit': ('Transcodes of the Steam 經典版 music\\NN.wav files, frame-exact. Which level or scene plays '
                        'which track is not recorded here.'),
        'source_folder': 'Steam 經典版 GAME-PAK (user-owned, outside the repository, read only; HSL_STEAM_CLASSIC)',
        'pinned_list': PINNED,
        'encoding': dict(ENCODING),
        'loop_source': LOOP_SOURCE,
        'totals': totals(tracks),
        'tracks': tracks,
        'excluded': [{'original_path': original_path(name), 'size': pins[name]['size'], 'sha1': pins[name]['sha1'],
                      'reason': reason} for name, reason in EXCLUDED.items()],
    }


def render_manifest(manifest: dict[str, Any]) -> str:
    return json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'


def write_if_changed(path: Path, data: bytes) -> bool:
    if path.exists() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def build(root: Path, steam_root: Path) -> str:
    """Verify the 18 sources against the pinned list, (re)encode what changed, write the manifest."""
    music = steam_root / 'music'
    if not music.is_dir():
        raise NotGeneratable(f'music_import: Steam 經典版 music folder not found at {music} (set HSL_STEAM_CLASSIC; '
                             'tools/hsl_steam_classic.py fetch / verify)')
    pins = pinned_files(root)
    previous: dict[int, dict[str, Any]] = {}
    manifest_path = root / MANIFEST
    if manifest_path.exists():
        old = json.loads(manifest_path.read_text(encoding='utf-8'))
        if old.get('schema') == SCHEMA and old.get('encoding') == ENCODING:
            previous = {entry['track']: entry for entry in old.get('tracks', [])}
    tracks: list[dict[str, Any]] = []
    encoded = kept = written = 0
    for track in TRACKS:
        name = track_name(track)
        pin = pins[name]
        path = music / f'{track:02d}.wav'
        data = path.read_bytes() if path.is_file() else b''
        if len(data) != pin['size'] or sha1(data) != pin['sha1']:
            raise NotGeneratable(f'music_import: {path} is missing or differs from the pinned size/sha1 in {PINNED} '
                                 '(tools/hsl_steam_classic.py verify)')
        layout = wav_layout(data, name)
        source = source_entry(pin, layout)
        target = root / OUT_DIR / f'{track:02d}.ogg'
        old_entry = previous.get(track)
        if (old_entry is not None and old_entry.get('source') == source and target.is_file()
                and sha1(target.read_bytes()) == old_entry['ogg']['sha1']):
            ogg = target.read_bytes()
            kept += 1
        else:
            ogg = encode(data[layout['data_offset']:layout['data_offset'] + layout['data_bytes']], track)
            encoded += 1
            written += write_if_changed(target, ogg)
        tracks.append(track_entry(track, source, ogg, ogg_stream(ogg)['frames']))
    written += write_if_changed(manifest_path, render_manifest(manifest_document(tracks, pins)).encode('utf-8'))
    return f'MUSIC_IMPORT_BUILD_PASS tracks={len(tracks)} encoded={encoded} kept={kept} files_written={written}'


def check(root: Path) -> dict[str, Any]:
    """Validate the tracked outputs without the Steam folder; the totals for the PASS line."""
    if not (root / MANIFEST).is_file():
        raise CheckFailed(f'music_import: {MANIFEST} not generated yet — run `{GENERATE_COMMAND}`')
    manifest = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
    pins = pinned_files(root)
    problems: list[str] = []
    tracks = manifest.get('tracks', [])
    if [entry.get('track') for entry in tracks] != list(TRACKS):
        problems.append(f'tracks {[entry.get("track") for entry in tracks]} != 02..19')
    expected_files = {f'{track:02d}.ogg' for track in TRACKS}
    present = {path.name for path in (root / OUT_DIR).glob('*.ogg')}
    if present != expected_files:
        problems.append(f'Ogg files in {OUT_DIR}: extra {sorted(present - expected_files)}, '
                        f'missing {sorted(expected_files - present)}')
    for entry in tracks if not problems else []:
        track = entry['track']
        pin = pins[track_name(track)]
        source = entry.get('source', {})
        layout = {key: source.get(key, -1) for key in ('data_offset', 'data_bytes', 'frames')}
        if (layout['data_offset'] + layout['data_bytes'] != pin['size']
                or layout['data_bytes'] != layout['frames'] * CHANNELS * BITS // 8):
            problems.append(f'track {track:02d}: source data chunk {layout} does not fill the pinned {pin["size"]} bytes')
            continue
        ogg = (root / OUT_DIR / f'{track:02d}.ogg').read_bytes()
        try:
            stream = ogg_stream(ogg)
        except ValueError as error:
            problems.append(f'track {track:02d}: {error}')
            continue
        if (stream['serial'], stream['channels'], stream['rate']) != (SERIAL_BASE + track, CHANNELS, RATE):
            problems.append(f'track {track:02d}: serial/channels/rate '
                            f'{stream["serial"]:#x}/{stream["channels"]}/{stream["rate"]}')
        if stream['frames'] != layout['frames']:
            problems.append(f'track {track:02d}: Ogg frames {stream["frames"]} != source frames {layout["frames"]}')
        # Everything else (paths, pinned size/sha1, format, seconds, Ogg size/sha1, loop) by re-rendering.
        expected = track_entry(track, source_entry(pin, layout), ogg, stream['frames'])
        differing = sorted(key for key in expected.keys() | entry.keys() if entry.get(key) != expected.get(key))
        if differing:
            problems.append(f'track {track:02d}: manifest fields {differing} differ from the pinned source / tracked Ogg')
    if not problems:
        expected_manifest = manifest_document(tracks, pins)
        differing = sorted(key for key in expected_manifest.keys() | manifest.keys()
                           if manifest.get(key) != expected_manifest.get(key))
        if differing:
            problems.append(f'manifest fields {differing} differ from this tool (settings, totals or exclusions)')
    if problems:
        raise CheckFailed('music_import: ' + '; '.join(problems)
                          + f' — `{GENERATE_COMMAND}` rewrites the outputs from the Steam folder')
    return manifest['totals']


class MusicImportTask(Task):
    name = 'music_import'
    family = 'assets'
    inputs = (PINNED,)
    outputs = (f'{OUT_DIR}/',)
    replaces = ()  # born as a registry task: no legacy command to replace
    scripts = ('tools/hsltools/assets/music_import.py',)

    def check(self, ctx: Context) -> str:
        summary = check(ctx.root)
        return ('MUSIC_IMPORT_CHECK_PASS tracks={tracks} frames={frames} seconds={seconds} ogg_bytes={ogg_bytes} '
                'excluded=null.wav'.format(**summary))

    def generate(self, ctx: Context) -> str:
        print(build(ctx.root, STEAM_CLASSIC_ROOT))
        return self.check(ctx)


def tasks() -> list[Task]:
    return [MusicImportTask()]
