import io
import random
import struct
import unittest

from PIL import Image

import hsltools.assets.movie_import as mi


def _chunk(kind: int, payload: bytes) -> bytes:
    return struct.pack('<IH', 6 + len(payload), kind) + payload


def _frame(chunks: list[bytes]) -> bytes:
    body = b''.join(chunks)
    return struct.pack('<IHH', 16 + len(body), mi.FRAME_MAGIC, len(chunks)) + bytes(8) + body


def _fli(frames: list[bytes], width: int, height: int, declared_frames: int, speed: int = 4) -> bytes:
    body = b''.join(frames)
    header = struct.pack('<IHHHHHHI', 128 + len(body), mi.FLI_MAGIC, declared_frames, width, height, 8, 0, speed)
    return header + bytes(128 - len(header)) + body


def _palette_chunk(colors: bytes) -> bytes:
    return _chunk(mi.CHUNK_COLOR256, struct.pack('<H', 1) + bytes((0, 0)) + colors)


def _brun_line(*packets: tuple[int, bytes]) -> bytes:
    # (count, data): count > 0 replicates data[0]; count < 0 copies -count literal bytes
    out = bytes((len(packets),))
    for count, data in packets:
        out += struct.pack('<b', count) + data
    return out


class SndDecodeTest(unittest.TestCase):
    def _snd(self, fmt_size: int, sample_rate: int, bits: int, samples: bytes) -> bytes:
        block_align = bits // 8
        fmt = struct.pack('<HHIIHH', 1, 1, sample_rate, sample_rate * block_align, block_align, bits)
        fmt += bytes(fmt_size - 16)
        data = b'data' + struct.pack('<I', len(samples)) + samples + (b'\0' if len(samples) & 1 else b'')
        body = b'WAVEfmt ' + struct.pack('<I', fmt_size) + fmt + data
        wav = bytearray(b'RIFF' + struct.pack('<I', len(body)) + body)
        for index in range(mi.SND_OBFUSCATED_PREFIX):
            wav[index] ^= mi.SND_XOR_KEY
        return bytes(wav)

    def test_decodes_18_byte_fmt_with_plain_data_marker(self):
        samples = struct.pack('<8h', *range(8))
        decoded = mi.decode_snd(self._snd(18, 16000, 16, samples))
        self.assertEqual(decoded['wav'][:4], b'RIFF')
        self.assertEqual(decoded['wav'][38:42], b'data')
        self.assertEqual(decoded['wav'][-16:], samples)
        self.assertEqual((decoded['sample_rate'], decoded['bits_per_sample'], decoded['data_bytes']), (16000, 16, 16))
        self.assertEqual(decoded['duration_s'], round(16 / 32000, 3))
        self.assertEqual(mi.describe_wav(decoded['wav']), {k: decoded[k] for k in mi.describe_wav(decoded['wav'])})

    def test_decodes_16_byte_fmt_with_half_obfuscated_marker_and_pad_byte(self):
        samples = bytes(range(7))  # odd length -> RIFF pad byte
        raw = self._snd(16, 11025, 8, samples)
        self.assertEqual(raw[36:40], bytes((ord('d') ^ 0xA8, ord('a') ^ 0xA8)) + b'ta')
        decoded = mi.decode_snd(raw)
        self.assertEqual(decoded['wav'][36:40], b'data')
        self.assertEqual(decoded['wav'][44:51], samples)
        self.assertEqual((decoded['sample_rate'], decoded['bits_per_sample'], decoded['data_bytes']), (11025, 8, 7))

    def test_rejects_non_wave(self):
        with self.assertRaises(ValueError):
            mi.decode_snd(bytes(64))


class FliDecodeTest(unittest.TestCase):
    WIDTH, HEIGHT = 4, 3

    def _palette(self) -> bytes:
        colors = bytearray(768)
        colors[3:6] = (255, 0, 0)
        colors[6:9] = (0, 255, 0)
        return bytes(colors)

    def _first_frame(self) -> bytes:
        brun = b''.join([
            _brun_line((4, b'\x01')),                     # 1 1 1 1
            _brun_line((-2, b'\x02\x01'), (2, b'\x00')),  # 2 1 0 0
            _brun_line((1, b'\x02'), (3, b'\x01')),       # 2 1 1 1
        ])
        return _frame([_palette_chunk(self._palette()), _chunk(mi.CHUNK_BRUN, brun)])

    def test_header_and_frames(self):
        data = _fli([self._first_frame()], self.WIDTH, self.HEIGHT, 1)
        header = mi.parse_fli_header(data)
        self.assertEqual((header['frames'], header['width'], header['height'], header['speed']), (1, 4, 3, 4))
        frames = list(mi.decode_fli(data))
        self.assertEqual(len(frames), 1)
        pixels, palette = frames[0]
        self.assertEqual(pixels, bytes([1, 1, 1, 1, 2, 1, 0, 0, 2, 1, 1, 1]))
        self.assertEqual(palette[3:9], bytes((255, 0, 0, 0, 255, 0)))

    def test_lc_copy_and_empty_frames(self):
        # LC: start at line 1, 1 line: skip 1, copy 2 literal (5 6); skip 0, run of 1 byte 7
        lc = struct.pack('<HH', 1, 1) + bytes((2,)) + bytes((1, 2)) + b'\x05\x06' + bytes((0, 0xFF)) + b'\x07'
        copy = bytes(range(12))
        frames = [
            self._first_frame(),
            _frame([_chunk(mi.CHUNK_LC, lc)]),
            _frame([]),
            _frame([_chunk(mi.CHUNK_COPY, copy)]),
            _frame([_chunk(mi.CHUNK_BLACK, b'')]),
        ]
        decoded = list(mi.decode_fli(_fli(frames, self.WIDTH, self.HEIGHT, 4)))
        self.assertEqual(decoded[1][0], bytes([1, 1, 1, 1, 2, 5, 6, 7, 2, 1, 1, 1]))
        self.assertEqual(decoded[2][0], decoded[1][0])
        self.assertEqual(decoded[3][0], copy)
        self.assertEqual(decoded[4][0], bytes(12))
        self.assertEqual(decoded[4][1], decoded[0][1])

    def test_rejects_bad_magic_unknown_chunk_and_overrun(self):
        data = bytearray(_fli([self._first_frame()], self.WIDTH, self.HEIGHT, 1))
        struct.pack_into('<H', data, 4, 0xAF12)
        with self.assertRaises(ValueError):
            mi.parse_fli_header(bytes(data))
        with self.assertRaises(ValueError):
            list(mi.decode_fli(_fli([self._first_frame(), _frame([_chunk(7, b'\0\0')])], self.WIDTH, self.HEIGHT, 2)))
        overrun = _frame([_chunk(mi.CHUNK_BRUN, _brun_line((5, b'\x01')) * 3)])
        with self.assertRaises(ValueError):
            list(mi.decode_fli(_fli([overrun], self.WIDTH, self.HEIGHT, 1)))

    def test_frame_image_uses_palette(self):
        image = mi.frame_image(bytes([0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]), self._palette(), self.WIDTH, self.HEIGHT)
        self.assertEqual(image.convert('RGB').getpixel((1, 0)), (255, 0, 0))
        self.assertEqual(image.convert('RGB').getpixel((3, 2)), (0, 255, 0))


class SheetLayoutTest(unittest.TestCase):
    def test_layout_splits_rows_and_sheets(self):
        layout = mi.sheet_layout(742)
        self.assertEqual([s['frame_start'] for s in layout], [0, 204, 408, 612])
        self.assertEqual([s['frame_count'] for s in layout], [204, 204, 204, 130])
        self.assertEqual([s['rows'] for s in layout], [17, 17, 17, 11])
        self.assertTrue(all(s['columns'] * mi.FRAME_WIDTH <= mi.SHEET_MAX_SIDE and s['rows'] * mi.FRAME_HEIGHT <= mi.SHEET_MAX_SIDE for s in layout))
        self.assertEqual(mi.sheet_layout(5, columns=2, rows=2), [
            {'frame_start': 0, 'frame_count': 4, 'columns': 2, 'rows': 2},
            {'frame_start': 4, 'frame_count': 1, 'columns': 2, 'rows': 1},
        ])

    def test_render_and_encode_sheet(self):
        frames = [Image.new('P', (mi.FRAME_WIDTH, mi.FRAME_HEIGHT), index) for index in range(3)]
        for frame in frames:
            frame.putpalette(bytes((0, 0, 0, 255, 0, 0, 0, 0, 255)) + bytes(768 - 9))
        layout = mi.sheet_layout(3, columns=2, rows=2)
        sheets = mi.render_sheets(frames, layout)
        self.assertEqual(sheets[0].size, (2 * mi.FRAME_WIDTH, 2 * mi.FRAME_HEIGHT))
        self.assertEqual(sheets[0].getpixel((mi.FRAME_WIDTH + 1, 1)), (255, 0, 0))
        self.assertEqual(sheets[0].getpixel((1, mi.FRAME_HEIGHT + 1)), (0, 0, 255))
        encoded, quality = mi.encode_sheets_within_budget(sheets, budget=10 ** 9)
        self.assertEqual(quality, mi.WEBP_QUALITY)
        with Image.open(io.BytesIO(encoded[0])) as image:
            self.assertEqual((image.format, image.size), ('WEBP', sheets[0].size))
        with self.assertRaises(ValueError):
            mi.encode_sheets_within_budget(sheets, budget=1)
        rng = random.Random(7)
        noise = Image.frombytes('RGB', (64, 64), bytes(rng.getrandbits(8) for _ in range(64 * 64 * 3)))
        full = len(mi.encode_webp(noise, mi.WEBP_QUALITY))
        _, lowered = mi.encode_sheets_within_budget([noise], budget=full - 1)
        self.assertLess(lowered, mi.WEBP_QUALITY)
        counts: dict[str, int] = {}
        list(mi.decode_fli(_fli([_frame([_palette_chunk(bytes(768)), _chunk(mi.CHUNK_BRUN, _brun_line((2, b'\x00')) * 2)]), _frame([])], 2, 2, 1), counts))
        self.assertEqual(counts, {'COLOR256': 1, 'BRUN': 1})


if __name__ == '__main__':
    unittest.main()
