import unittest
from hsltools.assets.actor_audio import bindings, SOURCE


class ActorAudioTests(unittest.TestCase):
    def test_table_bindings_preserve_distinct_walk_and_attack_resources(self):
        result = bindings(SOURCE.read_bytes())
        self.assertEqual(result['1']['walk'], 'wav/walk0011.wav')
        self.assertEqual(result['24']['walk'], 'wav/walk0012.wav')
        self.assertEqual(result['1']['attack'], 'wav/attack01.wav')
        self.assertEqual(result['25']['attack'], 'wav/attack02.wav')
        self.assertEqual(result['26']['attack'], 'wav/attack05.wav')
        self.assertEqual(set(result['1']), {'walk', 'attack', 'miss', 'dead'})

    def test_missing_character_fails_instead_of_substituting_another_sound(self):
        with self.assertRaises(ValueError):
            bindings(b'[character]\ncode=999\n')
