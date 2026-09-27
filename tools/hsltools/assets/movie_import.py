"""Import the original opening / ending movies from movie.pak into tracked, Godot-playable
assets.

movie.pak is a PAKS container with four records: start/end .snd (RIFF WAVE whose first
38 bytes are XOR 0xA8 obfuscated) and start/end .ani (Autodesk Animator FLI, magic 0xAF11,
320x240 8-bit, chunk types COLOR256 / BRUN / LC / COPY). The PAK stays outside the repository
and is only read; this tool writes:

* content/imported/hsl/movie/<name>.wav            de-obfuscated standard WAV (samples verbatim)
* content/imported/hsl/movie/<name>_sheet_NN.webp  lossy sprite sheets of 320x240 frames
* content/imported/hsl/movie/manifest.json         frame count / rate / sheet layout / hashes
* ignored/movie/<name>/frame_NNNN.png              full PNG frame sequence (not tracked)
* one PNG thumbnail per movie next to the evidence packet

--check never opens the PAK: it re-hashes the tracked outputs and validates the manifest.

Registry task movie_import (family assets): output content/imported/hsl/movie/ (checked
without the PAK); generate reads movie.pak next to the documented EXE. Bodies moved verbatim
from the former hsl_movie_import.py (ROOT resolved from this file's depth; the two lazy PAK-reader
imports point at hsltools.sources.pak).
"""
from __future__ import annotations

import hashlib
import io
import json
import struct
from pathlib import Path
from typing import Any, Iterator

from PIL import Image

from hsltools.paths import ORIGINAL_MOVIE_PAK
from hsltools.registry import Context, ScriptCheckTask, original_archive

ROOT = Path(__file__).resolve().parents[3]

DEFAULT_PAK = ORIGINAL_MOVIE_PAK
OUT_DIR = ROOT / 'content/imported/hsl/movie'
FRAMES_DIR = ROOT / 'ignored/movie'
EVIDENCE_DIR = ROOT / 'docs/evidence_packets/resource_inventory'
SCHEMA = 'hsl_movie_import.v1'

MOVIES: dict[str, dict[str, Any]] = {
    'start': {'ani': '?:\\movie\\start.ani', 'snd': '?:\\movie\\start.snd', 'thumbnail_frame': 500},
    'end': {'ani': '?:\\movie\\end.ani', 'snd': '?:\\movie\\End.snd', 'thumbnail_frame': 120},
}

# .snd: the engine XORs a fixed 38-byte prefix (RIFF + WAVE + 'fmt ' chunk of 18 bytes); a
# 16-byte fmt chunk therefore leaves 'da' of the data marker obfuscated and 'ta' in clear.
SND_XOR_KEY = 0xA8
SND_OBFUSCATED_PREFIX = 38

# Autodesk FLI (Animator 1.x) layout: 128-byte file header, then frames of a 16-byte header
# (u32 size, u16 0xF1FA, u16 chunk count, 8 reserved) followed by chunks (u32 size, u16 type).
FLI_HEADER_SIZE = 128
FLI_MAGIC = 0xAF11
FRAME_MAGIC = 0xF1FA
FRAME_HEADER_SIZE = 16
CHUNK_HEADER_SIZE = 6
CHUNK_COLOR256 = 4
CHUNK_COLOR64 = 11
CHUNK_LC = 12
CHUNK_BLACK = 13
CHUNK_BRUN = 15
CHUNK_COPY = 16
CHUNK_NAMES = {CHUNK_COLOR256: 'COLOR256', CHUNK_COLOR64: 'COLOR64', CHUNK_LC: 'LC',
               CHUNK_BLACK: 'BLACK', CHUNK_BRUN: 'BRUN', CHUNK_COPY: 'COPY'}

# Playback rate written to the manifest. The FLI header stores speed=4 (17.5 fps as jiffies),
# but the original player (hsl01.exe 0x45c5f0) schedules frame i at i / fps seconds with the
# float global 0x4a1920, initialised to 15.0 in .data and only rewritten (70 / speed) when it is
# zero, which no code path does. 15 fps also ends both films together with their .snd tracks
# (start 742 frames / 49.64 s, end 501 / 33.67 s).
FRAME_RATE = 15
FRAME_RATE_SOURCE = ('static-derived: hsl01.exe movie player 0x45c5f0 paces frame i at i / [0x4a1920] s, the '
                     'float global is 15.0 in .data and only written when zero; the FLI header speed=4 is '
                     'unused there. Cross-checked by the .snd durations of both films.')

FRAME_WIDTH = 320
FRAME_HEIGHT = 240
SHEET_COLUMNS = 12
SHEET_ROWS = 17  # 3840x4080, the largest 320x240 grid inside 4096x4096
SHEET_MAX_SIDE = 4096
WEBP_QUALITY = 85
WEBP_QUALITY_FLOOR = 60
SIZE_BUDGET_BYTES = 12 * 1024 * 1024
THUMBNAIL_MAX_BYTES = 200 * 1024


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# --- .snd -------------------------------------------------------------------------------

def decode_snd(raw: bytes) -> dict[str, Any]:
    """De-obfuscate one movie .snd record into a standard RIFF WAVE and describe it."""
    if len(raw) < SND_OBFUSCATED_PREFIX + 8:
        raise ValueError('snd record too short')
    wav = bytearray(raw)
    for index in range(SND_OBFUSCATED_PREFIX):
        wav[index] ^= SND_XOR_KEY
    if wav[0:4] != b'RIFF' or wav[8:12] != b'WAVE' or wav[12:16] != b'fmt ':
        raise ValueError('snd record is not an XOR 0xA8 RIFF WAVE')
    fmt_size = struct.unpack_from('<I', wav, 16)[0]
    if fmt_size < 16:
        raise ValueError(f'unsupported fmt chunk size {fmt_size}')
    # The fixed 38-byte XOR may have covered part of the data marker (16-byte fmt); restore it.
    # The original loader (0x45a6d0) never checks the marker either, it reads size and samples
    # at 20 + fmt_size + 4 / + 8.
    wav[20 + fmt_size:24 + fmt_size] = b'data'
    return {'wav': bytes(wav), **describe_wav(bytes(wav))}


def describe_wav(wav: bytes) -> dict[str, Any]:
    """Validate a standard mono/stereo PCM RIFF WAVE and report its format and duration."""
    if wav[0:4] != b'RIFF' or wav[8:12] != b'WAVE' or wav[12:16] != b'fmt ':
        raise ValueError('not a RIFF WAVE')
    riff_size = struct.unpack_from('<I', wav, 4)[0]
    if riff_size + 8 != len(wav):
        raise ValueError(f'RIFF size {riff_size} does not match length {len(wav)}')
    fmt_size = struct.unpack_from('<I', wav, 16)[0]
    audio_format, channels, sample_rate, byte_rate, block_align, bits = struct.unpack_from('<HHIIHH', wav, 20)
    if audio_format != 1:
        raise ValueError(f'unsupported WAVE format tag {audio_format}')
    if byte_rate != sample_rate * block_align or block_align != channels * bits // 8:
        raise ValueError('inconsistent PCM fmt chunk')
    data_offset = 20 + fmt_size
    if wav[data_offset:data_offset + 4] != b'data':
        raise ValueError('data chunk not at the expected offset')
    data_size = struct.unpack_from('<I', wav, data_offset + 4)[0]
    # RIFF chunks are word aligned: an odd data size is followed by one pad byte (End.snd).
    if data_offset + 8 + data_size + (data_size & 1) != len(wav):
        raise ValueError(f'data chunk size {data_size} does not end the file')
    return {'sample_rate': sample_rate, 'channels': channels, 'bits_per_sample': bits,
            'data_bytes': data_size, 'duration_s': round(data_size / byte_rate, 3)}


# --- .ani (FLI) ---------------------------------------------------------------------------

def parse_fli_header(data: bytes) -> dict[str, int]:
    if len(data) < FLI_HEADER_SIZE:
        raise ValueError('FLI header truncated')
    size, magic, frames, width, height, depth, flags, speed = struct.unpack_from('<IHHHHHHI', data, 0)
    if magic != FLI_MAGIC:
        raise ValueError(f'not an Autodesk FLI (magic 0x{magic:04x})')
    if size != len(data):
        raise ValueError(f'FLI size field {size} does not match record length {len(data)}')
    if depth != 8:
        raise ValueError(f'unsupported FLI depth {depth}')
    if any(data[20:FLI_HEADER_SIZE]):
        raise ValueError('FLI header reserved bytes are not zero')
    return {'size': size, 'magic': magic, 'frames': frames, 'width': width, 'height': height,
            'depth': depth, 'flags': flags, 'speed': speed}


def iter_fli_frames(data: bytes) -> Iterator[list[tuple[int, memoryview]]]:
    """Yield each frame as a list of (chunk type, payload) without decoding pixels."""
    view = memoryview(data)
    pos = FLI_HEADER_SIZE
    while pos < len(data):
        if pos + FRAME_HEADER_SIZE > len(data):
            raise ValueError(f'truncated frame header at 0x{pos:x}')
        size, magic, chunk_count = struct.unpack_from('<IHH', data, pos)
        if magic != FRAME_MAGIC:
            raise ValueError(f'bad frame magic 0x{magic:04x} at 0x{pos:x}')
        if size < FRAME_HEADER_SIZE or pos + size > len(data):
            raise ValueError(f'bad frame size {size} at 0x{pos:x}')
        if any(data[pos + 8:pos + FRAME_HEADER_SIZE]):
            raise ValueError(f'frame header reserved bytes are not zero at 0x{pos:x}')
        end = pos + size
        cursor = pos + FRAME_HEADER_SIZE
        chunks: list[tuple[int, memoryview]] = []
        while cursor < end:
            chunk_size, chunk_type = struct.unpack_from('<IH', data, cursor)
            if chunk_size < CHUNK_HEADER_SIZE or cursor + chunk_size > end:
                raise ValueError(f'bad chunk size {chunk_size} at 0x{cursor:x}')
            chunks.append((chunk_type, view[cursor + CHUNK_HEADER_SIZE:cursor + chunk_size]))
            cursor += chunk_size
        if len(chunks) != chunk_count:
            raise ValueError(f'frame at 0x{pos:x} declares {chunk_count} chunks, found {len(chunks)}')
        yield chunks
        pos = end


def apply_palette_chunk(payload: memoryview, palette: bytearray, shift: int) -> None:
    packets = struct.unpack_from('<H', payload, 0)[0]
    cursor = 2
    index = 0
    for _ in range(packets):
        skip, count = payload[cursor], payload[cursor + 1]
        cursor += 2
        count = count or 256
        index += skip
        if index + count > 256 or cursor + count * 3 > len(payload):
            raise ValueError('palette packet out of range')
        colors = bytes(payload[cursor:cursor + count * 3])
        if shift:
            colors = bytes((value << shift) & 0xFF for value in colors)
        palette[index * 3:(index + count) * 3] = colors
        cursor += count * 3
        index += count


def apply_brun_chunk(payload: memoryview, pixels: bytearray, width: int, height: int) -> None:
    """FLI_BRUN: every line, packets of i8 count (>0 replicate next byte, <0 copy -count bytes).
    The per-line packet count byte is unreliable for widths over 255 and is skipped."""
    cursor = 0
    for line in range(height):
        cursor += 1
        x = 0
        row = line * width
        while x < width:
            count = payload[cursor]
            cursor += 1
            if count < 128:
                pixels[row + x:row + x + count] = bytes((payload[cursor],)) * count
                cursor += 1
            else:
                count = 256 - count
                pixels[row + x:row + x + count] = payload[cursor:cursor + count]
                cursor += count
            x += count
        if x != width:
            raise ValueError(f'BRUN line {line} overran the frame width')
    if cursor != len(payload):
        raise ValueError('BRUN chunk has trailing bytes')


def apply_lc_chunk(payload: memoryview, pixels: bytearray, width: int, height: int) -> None:
    """FLI_LC: u16 first line, u16 line count; per line u8 packets of (u8 skip, i8 count) where
    count>0 copies count bytes and count<0 replicates the next byte -count times."""
    first_line, line_count = struct.unpack_from('<HH', payload, 0)
    if first_line + line_count > height:
        raise ValueError('LC chunk addresses lines outside the frame')
    cursor = 4
    for line in range(first_line, first_line + line_count):
        packets = payload[cursor]
        cursor += 1
        x = 0
        row = line * width
        for _ in range(packets):
            x += payload[cursor]
            count = payload[cursor + 1]
            cursor += 2
            if count < 128:
                pixels[row + x:row + x + count] = payload[cursor:cursor + count]
                cursor += count
            else:
                count = 256 - count
                pixels[row + x:row + x + count] = bytes((payload[cursor],)) * count
                cursor += 1
            x += count
            if x > width:
                raise ValueError(f'LC line {line} overran the frame width')
    if cursor > len(payload):
        raise ValueError('LC chunk truncated')


def apply_chunk(chunk_type: int, payload: memoryview, pixels: bytearray, palette: bytearray,
                width: int, height: int) -> None:
    if chunk_type == CHUNK_COLOR256:
        apply_palette_chunk(payload, palette, 0)
    elif chunk_type == CHUNK_COLOR64:
        apply_palette_chunk(payload, palette, 2)
    elif chunk_type == CHUNK_LC:
        apply_lc_chunk(payload, pixels, width, height)
    elif chunk_type == CHUNK_BLACK:
        pixels[:] = bytes(width * height)
    elif chunk_type == CHUNK_BRUN:
        apply_brun_chunk(payload, pixels, width, height)
    elif chunk_type == CHUNK_COPY:
        if len(payload) != width * height:
            raise ValueError('COPY chunk size does not match the frame')
        pixels[:] = payload
    else:
        raise ValueError(f'unsupported FLI chunk type {chunk_type}')


def decode_fli(data: bytes, chunk_counts: dict[str, int] | None = None) -> Iterator[tuple[bytes, bytes]]:
    """Yield (pixels, palette) after every frame of the FLI, including the ring frame; count
    chunk types by name into chunk_counts when given."""
    header = parse_fli_header(data)
    width, height = header['width'], header['height']
    pixels = bytearray(width * height)
    palette = bytearray(768)
    for chunks in iter_fli_frames(data):
        for chunk_type, payload in chunks:
            if chunk_counts is not None:
                key = CHUNK_NAMES.get(chunk_type, str(chunk_type))
                chunk_counts[key] = chunk_counts.get(key, 0) + 1
            apply_chunk(chunk_type, payload, pixels, palette, width, height)
        yield bytes(pixels), bytes(palette)


def frame_image(pixels: bytes, palette: bytes, width: int, height: int) -> Image.Image:
    image = Image.frombytes('P', (width, height), pixels)
    image.putpalette(palette)
    return image


def sheet_layout(frame_count: int, columns: int = SHEET_COLUMNS, rows: int = SHEET_ROWS) -> list[dict[str, int]]:
    per_sheet = columns * rows
    sheets = []
    start = 0
    while start < frame_count:
        count = min(per_sheet, frame_count - start)
        sheets.append({'frame_start': start, 'frame_count': count, 'columns': columns,
                       'rows': -(-count // columns)})
        start += count
    return sheets


def render_sheets(frames: list[Image.Image], layout: list[dict[str, int]]) -> list[Image.Image]:
    images = []
    for sheet in layout:
        canvas = Image.new('RGB', (sheet['columns'] * FRAME_WIDTH, sheet['rows'] * FRAME_HEIGHT))
        for offset in range(sheet['frame_count']):
            frame = frames[sheet['frame_start'] + offset].convert('RGB')
            canvas.paste(frame, ((offset % sheet['columns']) * FRAME_WIDTH,
                                 (offset // sheet['columns']) * FRAME_HEIGHT))
        images.append(canvas)
    return images


def encode_webp(image: Image.Image, quality: int) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, 'WEBP', quality=quality, method=6)
    return buffer.getvalue()


def encode_sheets_within_budget(sheets: list[Image.Image], budget: int = SIZE_BUDGET_BYTES) -> tuple[list[bytes], int]:
    """Encode at WEBP_QUALITY, stepping down by 5 until the movie fits the budget; below the
    quality floor the caller must decide (e.g. halve the frame rate), so fail instead."""
    quality = WEBP_QUALITY
    while True:
        encoded = [encode_webp(sheet, quality) for sheet in sheets]
        if sum(len(item) for item in encoded) <= budget:
            return encoded, quality
        if quality <= WEBP_QUALITY_FLOOR:
            raise ValueError(f'sheets exceed {budget} bytes even at quality {quality}')
        quality -= 5


# --- build / check --------------------------------------------------------------------------

def _read_record(packages: list[dict[str, Any]], member: str) -> bytes:
    from hsltools.sources.pak import find_paks_record_by_name, read_paks_record_bytes
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous movie record: ' + member)
    package, record = matches[0]
    return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))


def _thumbnail_path(name: str, frame: int) -> Path:
    return EVIDENCE_DIR / f'original_movies_{name}_frame_{frame:04d}.png'


def build_movie(name: str, spec: dict[str, Any], packages: list[dict[str, Any]], frames_dir: Path,
                out_dir: Path) -> dict[str, Any]:
    ani = _read_record(packages, spec['ani'])
    snd = _read_record(packages, spec['snd'])
    header = parse_fli_header(ani)
    if (header['width'], header['height']) != (FRAME_WIDTH, FRAME_HEIGHT):
        raise ValueError(f'{name}: unexpected FLI dimensions {header["width"]}x{header["height"]}')
    audio = decode_snd(snd)
    wav_path = out_dir / f'{name}.wav'
    wav_path.write_bytes(audio['wav'])

    frame_dir = frames_dir / name
    frame_dir.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    chunk_counts: dict[str, int] = {}
    digest = hashlib.sha256()
    first: tuple[bytes, bytes] | None = None
    last: tuple[bytes, bytes] | None = None
    decoded_frames = 0
    for index, (pixels, palette) in enumerate(decode_fli(ani, chunk_counts)):
        decoded_frames = index + 1
        last = (pixels, palette)
        if first is None:
            first = last
        if index >= header['frames']:
            continue  # the trailing ring frame loops back to frame 0; not part of the film
        digest.update(pixels)
        digest.update(palette)
        image = frame_image(pixels, palette, header['width'], header['height'])
        image.save(frame_dir / f'frame_{index:04d}.png', 'PNG', optimize=True)
        frames.append(image)
    if len(frames) != header['frames']:
        raise ValueError(f'{name}: header declares {header["frames"]} frames, decoded {len(frames)}')

    thumbnail_frame = spec['thumbnail_frame']
    thumbnail_path = _thumbnail_path(name, thumbnail_frame)
    thumbnail_path.parent.mkdir(parents=True, exist_ok=True)
    frames[thumbnail_frame].save(thumbnail_path, 'PNG', optimize=True)
    if thumbnail_path.stat().st_size > THUMBNAIL_MAX_BYTES:
        raise ValueError(f'{name}: thumbnail exceeds {THUMBNAIL_MAX_BYTES} bytes')

    layout = sheet_layout(len(frames))
    encoded, quality = encode_sheets_within_budget(render_sheets(frames, layout))
    sheets = []
    for sheet, data in zip(layout, encoded):
        path = out_dir / f'{name}_sheet_{len(sheets):02d}.webp'
        path.write_bytes(data)
        sheets.append({**sheet, 'file': path.name, 'sha256': _sha(data), 'bytes': len(data),
                       'width': sheet['columns'] * FRAME_WIDTH, 'height': sheet['rows'] * FRAME_HEIGHT})
    video_duration = round(len(frames) / FRAME_RATE, 3)
    return {
        'source': {
            'ani_member': spec['ani'], 'ani_sha256': _sha(ani), 'ani_bytes': len(ani),
            'snd_member': spec['snd'], 'snd_sha256': _sha(snd), 'snd_bytes': len(snd),
        },
        'fli_header': header,
        'fli_chunk_counts': dict(sorted(chunk_counts.items())),
        'frame_width': FRAME_WIDTH,
        'frame_height': FRAME_HEIGHT,
        'frame_count': len(frames),
        'decoded_frames_including_ring': decoded_frames,
        'ring_frame_matches_first_frame': first == last,
        'decoded_frames_sha256': digest.hexdigest(),
        'frame_rate': FRAME_RATE,
        'frame_rate_source': FRAME_RATE_SOURCE,
        'video_duration_s': video_duration,
        'audio': {
            'file': wav_path.name, 'sha256': _sha(audio['wav']), 'bytes': len(audio['wav']),
            'sample_rate': audio['sample_rate'], 'channels': audio['channels'],
            'bits_per_sample': audio['bits_per_sample'], 'data_bytes': audio['data_bytes'],
            'duration_s': audio['duration_s'],
        },
        'audio_video_duration_delta_s': round(audio['duration_s'] - video_duration, 3),
        'sheets': sheets,
        'sheet_format': 'webp', 'sheet_quality': quality, 'sheet_frame_order': 'row-major, frame 0 at top-left',
        'sheet_total_bytes': sum(sheet['bytes'] for sheet in sheets),
        'thumbnail': {'file': thumbnail_path.relative_to(ROOT).as_posix(), 'frame': thumbnail_frame,
                      'sha256': _sha(thumbnail_path.read_bytes())},
    }


def build(pak: Path, out_dir: Path = OUT_DIR, frames_dir: Path = FRAMES_DIR) -> dict[str, Any]:
    from hsltools.sources.pak import ensure_safe_extract_output, find_decoded_paks_packages
    ensure_safe_extract_output(frames_dir, ROOT)
    packages = find_decoded_paks_packages(pak)
    if not packages:
        raise ValueError(f'no PAKS container at {pak}')
    out_dir.mkdir(parents=True, exist_ok=True)
    movies = {name: build_movie(name, spec, packages, frames_dir, out_dir) for name, spec in MOVIES.items()}
    manifest = {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'source_package': 'movie.pak (PAKS container, read only, outside the repository)',
        'movies': movies,
        'claim_limit': [
            'Frames and audio are decoded from the original records; the sprite sheets are lossy WebP '
            'and not pixel-identical to the PNG frames.',
            'The original player starts the .snd once and paces frames from the same start tick '
            '(frames may be drawn up to 0.1 s early and are skipped when more than 0.25 s late); the '
            'remake reproduces the 15 fps rate, not that scheduler; the original display path (surface set-up '
            '0x45c570, frame callback 0x42deb0) was not analysed.',
            'start.ani is played by the level-entry routine 0x42da60 when the level is 51 and the global '
            '0x4c1ae4 is zero; the exact meaning of that global (set to 1 on a reload path) is provisional. '
            'end.ani is played by the actPlayMovie opcode handler at 0x451b1c (winfail059).',
        ],
    }
    (out_dir / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest


def check(out_dir: Path = OUT_DIR) -> dict[str, int]:
    manifest = json.loads((out_dir / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('schema') != SCHEMA or set(manifest.get('movies', {})) != set(MOVIES):
        raise SystemExit('movie manifest schema or movie set differs from the tool')
    totals = {'movies': 0, 'sheets': 0, 'frames': 0}
    for name, movie in manifest['movies'].items():
        audio = movie['audio']
        wav = (out_dir / audio['file']).read_bytes()
        if _sha(wav) != audio['sha256'] or len(wav) != audio['bytes']:
            raise SystemExit(f'{name}: audio differs from manifest')
        described = describe_wav(wav)
        if any(described[key] != audio[key] for key in described):
            raise SystemExit(f'{name}: WAV header differs from manifest')
        if movie['frame_count'] != movie['fli_header']['frames'] or movie['frame_rate'] != FRAME_RATE:
            raise SystemExit(f'{name}: frame count or rate differs from the tool')
        if round(movie['frame_count'] / FRAME_RATE, 3) != movie['video_duration_s']:
            raise SystemExit(f'{name}: video duration differs from frame_count / frame_rate')
        expected_layout = sheet_layout(movie['frame_count'])
        if [{k: s[k] for k in expected_layout[0]} for s in movie['sheets']] != expected_layout:
            raise SystemExit(f'{name}: sheet layout differs from the tool')
        total = 0
        for sheet in movie['sheets']:
            data = (out_dir / sheet['file']).read_bytes()
            total += len(data)
            if _sha(data) != sheet['sha256'] or len(data) != sheet['bytes']:
                raise SystemExit(f'{name}: sheet {sheet["file"]} differs from manifest')
            with Image.open(io.BytesIO(data)) as image:
                if image.format != 'WEBP' or image.size != (sheet['width'], sheet['height']):
                    raise SystemExit(f'{name}: sheet {sheet["file"]} format or size differs from manifest')
            if sheet['width'] != sheet['columns'] * FRAME_WIDTH or sheet['height'] != sheet['rows'] * FRAME_HEIGHT:
                raise SystemExit(f'{name}: sheet {sheet["file"]} grid does not match its size')
            if max(sheet['width'], sheet['height']) > SHEET_MAX_SIDE:
                raise SystemExit(f'{name}: sheet {sheet["file"]} exceeds {SHEET_MAX_SIDE}')
            totals['sheets'] += 1
        if total != movie['sheet_total_bytes'] or total > SIZE_BUDGET_BYTES:
            raise SystemExit(f'{name}: sheet total size differs or exceeds the budget')
        thumbnail = ROOT / movie['thumbnail']['file']
        thumb = thumbnail.read_bytes()
        if _sha(thumb) != movie['thumbnail']['sha256'] or len(thumb) > THUMBNAIL_MAX_BYTES:
            raise SystemExit(f'{name}: thumbnail differs from manifest or is too large')
        if movie['thumbnail']['frame'] != MOVIES[name]['thumbnail_frame']:
            raise SystemExit(f'{name}: thumbnail frame differs from the tool')
        totals['movies'] += 1
        totals['frames'] += movie['frame_count']
    return totals


class MovieImportTask(ScriptCheckTask):
    name = 'movie_import'
    family = 'assets'
    inputs = ()
    outputs = ('content/imported/hsl/movie/',) + tuple(
        _thumbnail_path(name, spec['thumbnail_frame']).relative_to(ROOT).as_posix() for name, spec in MOVIES.items())
    replaces = ('tools/hsl_movie_import.py --check',)
    scripts = ('tools/hsltools/assets/movie_import.py',)

    def verify(self, ctx: Context) -> None:
        totals = check()
        print('MOVIE_IMPORT_CHECK_PASS movies={movies} sheets={sheets} frames={frames}'.format(**totals))

    def build(self, ctx: Context) -> None:
        manifest = build(original_archive(ctx, 'movie.pak'))
        for name, movie in manifest['movies'].items():
            print(f"MOVIE_IMPORT_BUILD_PASS movie={name} frames={movie['frame_count']} fps={movie['frame_rate']} "
                  f"video_s={movie['video_duration_s']} audio_s={movie['audio']['duration_s']} "
                  f"sheets={len(movie['sheets'])} sheet_bytes={movie['sheet_total_bytes']} quality={movie['sheet_quality']}")


def tasks() -> list[MovieImportTask]:
    return [MovieImportTask()]
