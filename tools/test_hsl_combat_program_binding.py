import unittest

from hsltools.assets.combat_animation import ACTION_OPCODES, CAST_OPCODES, compile_action, validate_cast_program


def op(name, *args):
    return {'op': name, 'args': list(args), 'source_line': 1}


class OrdinaryProgramBindingTests(unittest.TestCase):
    def test_delay_setup_and_zero_exit_are_separate_from_next_opcode(self):
        # Native dispatcher front-segment probe: delay D's successor is first
        # visible at result index max(D,1)+2, unlike the SHP frame helper.
        for delay in (0, 1, 2, 12, 30):
            program = [op('aniDelay', delay), op('aniInsertAttackFlash', -90, -120),
                       op('aniSetShape', 1), op('aniDelay', 3)]
            result = compile_action(program, 5)
            self.assertEqual(result['release_update'], max(delay, 1) + 2)
            self.assertEqual(result['poses'][0]['update'], result['release_update'])
            self.assertEqual(result['events'][1]['op'], 'aniInsertAttackFlash')
            self.assertEqual(result['events'][2]['op'], 'aniSetShape')

    def test_leonard_complete_order_keeps_final_wait(self):
        result = compile_action([op('aniDelay', 12), op('aniSetShape', 1),
                                 op('aniDelay', 8), op('aniSetShape', 2), op('aniDelay', 3),
                                 op('aniInsertAttackFlash', -90, -120), op('aniSetShape', 3),
                                 op('aniDelay', 30)], 5)
        self.assertEqual(result['poses'], [{'frame': 1, 'update': 14}, {'frame': 2, 'update': 24}, {'frame': 3, 'update': 29}])
        self.assertEqual(result['complete_updates'], 60)
        self.assertEqual(result['release_update'], 29)

    def test_unsupported_opcode_is_not_silently_ignored(self):
        for bad in [op('aniSetZoom', 0x11000), op('aniSetShape', 5), op('aniDelay', -1), op('aniInsertAttackFlash', 3)]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                compile_action([bad], 5)

    def test_cast_program_passes_through_in_source_order_or_is_refused(self):
        # 001's s_action (ANIMAL.TXT lines 14-15): the four cast opcodes, start panel 2 of 7.
        program = [op('aniSetXYDisp', -640, 0), op('aniShadowBG'), op('aniMoveToCenter'), op('aniInsertCastObject', -160, -150, 2, 6, 6)]
        self.assertEqual(validate_cast_program(program, 7, 'SID_PLAYER0'), program)
        self.assertEqual(validate_cast_program([], 0, 'SID_ENEMY021'), [])
        self.assertEqual(set(CAST_OPCODES), {'aniSetXYDisp', 'aniShadowBG', 'aniMoveToCenter', 'aniInsertCastObject'})
        self.assertFalse(set(CAST_OPCODES) - {'aniSetXYDisp'} & set(ACTION_OPCODES))
        for bad_program, panels in [(program[:3], 7), (program + [op('aniInsertCastObject', -160, -150, 2, 6, 6)], 7),
                                    (program, 2), ([op('aniDelay', 3)] + program, 7),
                                    (program[:3] + [op('aniInsertCastObject', -160, -150, 1, 6, 6)], 7)]:
            with self.subTest(bad=bad_program, panels=panels), self.assertRaises(ValueError):
                validate_cast_program(bad_program, panels, 'SID_PLAYER0')


if __name__ == '__main__':
    unittest.main()
