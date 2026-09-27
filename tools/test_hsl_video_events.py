import unittest

import hsl_video_events as ve


def block(x, y):
    return y * ve.GRID_W + x


class VideoEventsTest(unittest.TestCase):
    def setUp(self):
        self.pts = [i / 60 for i in range(120)]

    def test_local_change_between_idle_gaps_is_one_event_and_one_track(self):
        active = [[] for _ in self.pts]
        for i in range(10, 20):                     # a cursor moving right one block per frame
            active[i] = [block(10 + i - 10, 5)]
        result = ve.segment(self.pts, active, [0.0] * len(self.pts))
        self.assertEqual([e['kind'] for e in result['events']], ['local'])
        self.assertEqual(result['events'][0]['box'], [80, 40, 80, 8])
        found = ve.tracks(self.pts, active)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]['first_centre'], [84, 44])
        self.assertEqual(found[0]['last_centre'], [156, 44])

    def test_full_and_pan_frames_split_and_close_local_tracks(self):
        full = list(range(ve.GRID_W * ve.GRID_H))
        active = [[] for _ in self.pts]
        shifts = [None] * len(self.pts)
        for i in range(5, 10):
            active[i] = [block(1, 1)]
        for i in range(10, 13):
            active[i] = full
        for i in range(13, 16):
            active[i] = full
            shifts[i] = (2, 0, 0.01)                # explained by a camera shift
        for i in range(16, 20):
            active[i] = [block(1, 1)]
        result = ve.segment(self.pts, active, [0.0] * len(self.pts), shifts)
        self.assertEqual([e['kind'] for e in result['events']], ['local', 'full', 'pan', 'local'])
        self.assertEqual(result['events'][2]['pan_logical'], [12, 0])
        self.assertEqual(len(ve.tracks(self.pts, active, shifts)), 2)

    def test_separate_regions_make_separate_tracks_and_gap_splits_in_time(self):
        active = [[] for _ in self.pts]
        for i in range(10, 14):
            active[i] = [block(2, 2), block(60, 50)]
        for i in range(80, 84):                     # > 0.4 s later: a new track
            active[i] = [block(2, 2)]
        found = ve.tracks(self.pts, active)
        self.assertEqual(sorted(t['box'] for t in found), [[16, 16, 8, 8], [16, 16, 8, 8], [480, 400, 8, 8]])

    def test_camera_runs_tell_a_smooth_scroll_from_a_one_frame_cut(self):
        shifts = [(0, 0, 0.0)] * len(self.pts)
        for i, step in zip(range(10, 16), [16, 12, 6, 3, 1, 1]):   # decelerating scroll
            shifts[i] = (0, step, 0.02)
        shifts[40] = (56, -32, 0.03)                               # one-frame jump to a new spot
        shifts[60] = (5, 5, 0.9)                                   # a big residual is not camera motion
        result = ve.camera_runs(self.pts, shifts)
        self.assertEqual(result['summary'], {'runs': 2, 'single_frame': 1, 'multi_frame': 1, 'median_peak_step': 129})
        self.assertEqual([(r['frames'], r['peak_step'], r['total_step']) for r in result['runs']], [(6, 32, 78), (1, 129, 129)])


if __name__ == '__main__':
    unittest.main()


class RegionTest(unittest.TestCase):
    def test_region_frame_tracks_a_brighter_blob_and_its_rows(self):
        width, height = 8, 8
        ref = [50] * (width * height)
        luma = list(ref)
        for y in range(2, 4):                       # a bright 2x2 blob at (3..4, 2..3)
            for x in range(3, 5):
                luma[y * width + x] = 200
        luma[7 * width + 0] = 10                    # one darker pixel: ignored with brighter=True
        frame = ve.region_frame(luma, None, ref, ref, width, (100, 200), 24, 4, brighter=True, bright=150)
        self.assertEqual(frame['mask_pixels'], 4)
        self.assertEqual(frame['box'], [103, 202, 2, 2])
        self.assertEqual(frame['centroid'], [103.5, 202.5])
        self.assertEqual(frame['band_rows'], [4, 0])
        self.assertEqual(frame['bright_rows'], [4, 0])
        self.assertEqual(frame['mean_excess'], 150.0)
        both = ve.region_frame(luma, None, ref, ref, width, (0, 0), 24, 4)
        self.assertEqual(both['mask_pixels'], 5)

    def test_transition_runs_tell_a_dissolve_from_a_hard_cut(self):
        pts = [i / 60 for i in range(20)]
        steps = [0.0] * 20
        steps[3] = 20.0                             # hard cut: one frame
        for i in range(10, 16):                     # dissolve: six frames of small steps
            steps[i] = 3.0
        runs = ve.transition_runs(pts, steps, 1.5)
        self.assertEqual([r['frames'] for r in runs], [1, 6])

    def test_periodicity_finds_a_pulse_period(self):
        import math
        pts = [i / 60 for i in range(240)]
        pulse = [100 + 20 * math.sin(2 * math.pi * t / 0.5) for t in pts]
        result = ve.periodicity(pts, pulse)
        self.assertAlmostEqual(result['period_seconds'], 0.5, delta=0.02)
        self.assertEqual(ve.periodicity(pts, [80.0] * 240)['period_seconds'], None)

    def test_onsets_find_a_sound_start_over_a_quiet_floor(self):
        levels = [-60.0] * 30 + [-20.0] * 10 + [-60.0] * 10
        found = ve.onsets(levels, 0.01)
        self.assertEqual([o['t'] for o in found], [0.3])


class SpriteTest(unittest.TestCase):
    def test_sprite_runs_bridge_short_misses_and_report_drift(self):
        pts = [i / 60 for i in range(12)]
        hits = [{'score': 99.0, 'centre': [0, 0]} for _ in pts]
        for i, y in zip(range(2, 9), [100, 100, 99, 99, 98, 98, 97]):
            hits[i] = {'score': 5.0, 'centre': [320, y]}
        hits[5] = {'score': 60.0, 'centre': [0, 0]}          # one missed frame inside the run
        runs = ve.sprite_runs(pts, hits, 40.0)
        self.assertEqual(len(runs), 1)
        self.assertEqual((runs[0]['frames'], runs[0]['drift']), (6, [0, -3]))
        self.assertAlmostEqual(runs[0]['duration'], 6 / 60, places=3)
        self.assertEqual(ve.sprite_runs(pts, hits, 1.0), [])

    def test_sprite_match_finds_a_pasted_sprite(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest('numpy not installed (the matcher needs it; run with uv run --with numpy)')
        frame = np.full((40, 60, 3), 30.0, dtype=np.float32)
        sprite = np.zeros((5, 7, 3), dtype=np.float32)
        sprite[:, :, 0] = 250.0
        mask = np.ones((5, 7), dtype=bool)
        mask[0, 0] = False
        frame[12:17, 21:28] = sprite
        self.assertEqual(ve.sprite_match(np, frame, sprite, mask, step=1), (21, 12, 0.0))
