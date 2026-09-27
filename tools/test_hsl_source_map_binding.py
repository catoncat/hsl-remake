import copy
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.levels import seed as Seed  # the promoter's module (patch.object targets its globals)
from hsltools.sources.scripts import parse_text_metadata
from hsltools.probes.map_binding import PACKET, check as check_native
from hsltools.checks.source_map_binding import (
    archive_member,
    source_map_member,
    check_seed_binding,
    reviewed_bindings)


class SourceMapBindingTests(unittest.TestCase):
    def test_actual_source_records_use_full_declared_path(self):
        packet = json.loads(PACKET.read_text())
        check_native(packet)
        for row in packet['sources']['bindings']:
            with self.subTest(level=row['level']):
                raw = '[Object]\r\n' + '\r\n'.join(f'{key} = {value}' for key, value in row['object'].items())
                parsed = parse_text_metadata(raw.encode('cp950'))
                if row['level'] == 49:
                    self.assertEqual(row['object']['obj_Shape_Name'], 'SHAPE\\ICONRECT.SHP')
                    with self.assertRaisesRegex(ValueError, 'unsupported_source_map_callback'):
                        source_map_member(parsed)
                    continue
                self.assertEqual(source_map_member(parsed).casefold(), row['shape_member'].casefold())
                # A translated object label cannot be mistaken for source authority.
                parsed['objects'][0]['obj_name'] = 'not a map by name'
                self.assertEqual(source_map_member(parsed).casefold(), row['shape_member'].casefold())
        self.assertEqual([row['level'] for row in packet['sources']['without_map_manager']], [0, 998, 999])

    def test_missing_duplicate_wrong_branch_and_bad_paths_fail(self):
        row = {'obj_process_code':'defProcIconBG', 'obj_shape_name':'SHAPE41\\LEVEL55.SHP', 'obj_data_fields':{'obj_Data9':'1'}}
        for rows in [[], [row, copy.deepcopy(row)]]:
            with self.assertRaisesRegex(ValueError, 'expected_one_source_map_manager'):
                source_map_member({'objects':rows})
        with self.assertRaisesRegex(ValueError, 'unsupported_source_map_callback'):
            source_map_member({'objects':[dict(row, obj_data_fields={'obj_Data9':'0'})]})
        for name in ['', '../level55.shp', 'SHAPE41\\..\\level55.shp', 'C:\\level55.shp', 'SHAPE41\\level55.wav', None]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                source_map_member({'objects':[dict(row, obj_shape_name=name)]})
        self.assertEqual(archive_member('shape41\\level55.shp'), '@:\\shape41\\level55.shp')

    def test_existing_seed_checks_reject_wrong_folder_even_with_same_basename(self):
        seed = json.loads(Path('content/generated/hsl/chapter01/battle061_seed.json').read_text())
        bindings = reviewed_bindings()
        check_seed_binding(seed, bindings)
        wrong = copy.deepcopy(seed)
        wrong['sources']['map']['member'] = '@:\\shape01\\level55.SHP'
        with self.assertRaisesRegex(ValueError, 'seed_source_map_binding_mismatch'):
            check_seed_binding(wrong, bindings)
        wrong = copy.deepcopy(seed)
        wrong['sources']['map']['sha256'] = bindings[56]['shape_sha256']
        with self.assertRaisesRegex(ValueError, 'seed_source_map_binding_mismatch'):
            check_seed_binding(wrong, bindings)

    @staticmethod
    def image_bytes(color):
        width = height = 64
        first = 0x24 + 4*height
        row = struct.pack('<2H', 0, width) + struct.pack('<H', color)*width + struct.pack('<H', 0xffff)
        return (b'TLHS' + struct.pack('<8I', 0, 2, 0, 0x1234, width, height, 0, 0)
                + b''.join(struct.pack('<I', first + len(row)*y) for y in range(height)) + row*height)

    def generated_fixture(self, level, missing=False):
        # Only archive IO is substituted. Real OBS parser, build, WRD/SHP decoders
        # and PNG writer must select the green declared file, not the red decoy.
        raw = b'[Object]\r\nobj_Code = 1\r\nobj_Name = map\r\nobj_Process_Code = defProcIconBG\r\nobj_Data9 = 1\r\nobj_Shape_Name = SHAPE41\\LEVEL55.SHP\r\n'
        reads = []
        shapes = {'@:\\shape01\\level55.shp':self.image_bytes(0xf800), '@:\\shape41\\level55.shp':self.image_bytes(0x07e0)}
        if missing: shapes.pop('@:\\shape41\\level55.shp')
        data = {'objects':raw, 'story':b'[story]\naction = actDelay,0\n', 'object_header':b'',
                'level':b'EVEF'+struct.pack('<3I', 0, 0, 16),
                'terrain':struct.pack('<4s5I', b'WORL', 3, 0, 2, 2, 4)+bytes(16)}
        def archive(_pak, requested):
            result = {}
            for key, value in requested.items():
                candidates = [value] if isinstance(value, str) else value
                if key == 'map':
                    matches = [name for name in candidates if name.lower() in shapes]
                    if not matches: raise ValueError('missing declared map in fixture archive')
                    member = matches[0];payload = shapes[member.lower()]
                    reads.append(member)
                elif key in data:
                    member = candidates[0];payload = data[key]
                else:
                    continue
                result[key] = {'data':payload,'member':member,'length':len(payload),'sha256':Seed._sha(payload),'package':'synthetic.pak'}
            return result
        from PIL import Image
        with tempfile.TemporaryDirectory() as temp, patch.object(Seed, '_read_records', side_effect=archive):
            root = Path(temp)
            result = Seed.build(level, root/'synthetic.pak', root/'seed.json', root/'terrain.json', root/'map.png')
            with Image.open(root/'map.png') as image: pixel = image.convert('RGB').getpixel((32,32))
            self.assertEqual(pixel, (0,255,0), 'decoded product pixels must come from the exact source folder')
            self.assertEqual([name.casefold() for name in reads], ['@:\\shape41\\level55.shp'])
            self.assertEqual(result['map']['alias_of_level'], 55 if level != 55 else None)
            return result

    def test_full_generator_ignores_matching_basename_in_wrong_folder(self):
        self.generated_fixture(55)

    def test_full_generator_rejects_missing_declared_map_instead_of_decoy(self):
        with self.assertRaisesRegex(ValueError, 'missing declared map'):
            self.generated_fixture(55, missing=True)

    def test_wrong_legacy_alias_cannot_override_source_or_provenance(self):
        with patch.dict(Seed.MAP_ALIASES, {61:{'map_level':56,'evidence':'wrong synthetic hint'}}):
            result = self.generated_fixture(61)
            self.assertNotEqual(result['map']['alias_evidence'], 'wrong synthetic hint')

    def test_evidence_checker_rejects_changed_stop_or_source(self):
        packet = json.loads(PACKET.read_text())
        for kind in ['stop', 'source']:
            bad = copy.deepcopy(packet)
            if kind == 'stop': bad['prefixes'][0]['proof']['normal_return'] = True
            else: bad['sources']['bindings'][0]['shape_sha256'] = '0'*64
            with self.assertRaises(ValueError): check_native(bad)


if __name__ == '__main__':
    unittest.main()
