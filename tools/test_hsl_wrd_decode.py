import struct
import unittest

from hsltools.sources import wrd


class WrdDecodeTests(unittest.TestCase):
    def test_decodes_dimensions_tile_ids_and_blocking(self):
        header = struct.pack("<4s5I", b"WORL", 3, 0, 2, 2, 4)
        cells = [0x00000001, 0xFF000002, 0x00000003, 0xFF000004]
        result = wrd.decode_wrd(
            header + b"".join(struct.pack("<I", value) for value in cells)
        )

        self.assertEqual(result["source_format"]["width"], 2)
        self.assertEqual(result["source_format"]["height"], 2)
        self.assertEqual(result["stats"]["blocking_count"], 2)
        self.assertEqual(result["grid"][0][1], {"t": 2, "b": 1, "h": 255})

    def test_preserves_all_height_bytes_without_converting_them_to_cliffs(self):
        header = struct.pack("<4s5I", b"WORL", 3, 0, 5, 1, 4)
        heights = [0, 1, 2, 128, 255]
        result = wrd.decode_wrd(header + b"".join(struct.pack("<I", (value << 24) | index) for index, value in enumerate(heights)))
        self.assertEqual([cell['h'] for cell in result['grid'][0]], heights)
        self.assertEqual([cell['b'] for cell in result['grid'][0]], [0, 0, 0, 0, 1])

    def test_rejects_invalid_magic(self):
        data = struct.pack("<4s5I", b"NOPE", 3, 0, 1, 1, 4) + struct.pack("<I", 0)
        with self.assertRaisesRegex(ValueError, "bad magic"):
            wrd.decode_wrd(data)


if __name__ == "__main__":
    unittest.main()
