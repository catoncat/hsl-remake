import unittest
from copy import deepcopy
from hsltools.evidence.presentation_reference import validate, validate_recording_duration


class ReferenceCoverageTests(unittest.TestCase):
    def test_early_screen_lock_must_not_pass_as_a_full_recording(self):
        with self.assertRaises(ValueError):
            validate_recording_duration({'format': {'duration': '10'}}, 40)
        validate_recording_duration({'format': {'duration': '40.2'}}, 40)

    def sample(self):
        movie = {'sha256': 'a' * 64, 'precondition': 'one nonlethal sword strike',
                 'duration': 5, 'events': {'swing': 1, 'hurt': 2, 'return': 3}, 'audio_has_signal': True}
        return {'schema': 'hsl_presentation_reference.v1', 'cases': [{
            'id': 'attack', 'required_events': ['swing', 'hurt', 'return'], 'sound_required': True,
            'original': deepcopy(movie), 'remake': deepcopy(movie), 'verdict': 'unreviewed', 'review_notes': ''}]}

    def test_coverage_is_not_approval(self):
        data = self.sample()
        self.assertEqual(validate(data, True), [])
        self.assertEqual(data['cases'][0]['verdict'], 'unreviewed')

    def test_missing_original_never_becomes_match(self):
        data = self.sample()
        del data['cases'][0]['original']
        self.assertTrue(validate(data))
        with self.assertRaises(ValueError): validate(data, True)
        data['cases'][0]['verdict'] = 'matched'
        with self.assertRaises(ValueError): validate(data)

    def test_sound_and_each_required_transition_are_required(self):
        data = self.sample()
        data['cases'][0]['original']['audio_has_signal'] = False
        del data['cases'][0]['remake']['events']['hurt']
        self.assertEqual(len(validate(data)), 2)

    def test_invalid_event_times_and_duplicate_ids_fail(self):
        for number in [-1, 5, float('nan'), 0.5]:
            data = self.sample()
            data['cases'][0]['original']['events']['hurt'] = number
            with self.subTest(number=number), self.assertRaises(ValueError): validate(data)
        data = self.sample()
        data['cases'].append(deepcopy(data['cases'][0]))
        with self.assertRaises(ValueError): validate(data)
