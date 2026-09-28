import struct
import unittest

import hsltools.data.world_map as wm


def _point(field0, flags, point_id, name_id, x, y, tracks=(0, 0, 0)):
    return struct.pack("<10i", field0, struct.unpack("<i", struct.pack("<I", flags))[0], point_id, name_id, x, y, *tracks, 0)


def _track(field0, field1, src, dst):
    return struct.pack("<4i", field0, struct.unpack("<i", struct.pack("<I", field1))[0], src, dst)


def synthetic_bigmap() -> bytes:
    points = bytearray(wm.TRACK_TABLE_OFFSET)
    records = [
        (1, _point(2, 0x20000000, 1, 315, 10, 20, (1, 0, 0))),
        (2, _point(0, 0x40000000, 2, 316, 30, 40, (1, 2, 0))),
        (3, _point(0, 0x80000000 | 0x08000000, 3, 317, 50, 60, (2, 0, 0))),
    ]
    for slot, record in records:
        points[slot * wm.POINT_RECORD_SIZE: (slot + 1) * wm.POINT_RECORD_SIZE] = record
    tracks = bytearray(wm.TRACK_SLOT_COUNT * wm.TRACK_RECORD_SIZE)
    for slot, record in [(1, _track(0, 0, 1, 2)), (2, _track(0, 0x08000000, 2, 3))]:
        tracks[slot * wm.TRACK_RECORD_SIZE: (slot + 1) * wm.TRACK_RECORD_SIZE] = record
    return bytes(points + tracks)


TRACK_TXT = """#include TRACK.H

[track]
code = bmTrack01
data = 10,20, 15,25, 30,40

[track]   ; comment
code = bmTrack02
data = 30,40, 50,60
"""

TOWNDEF_TXT = r"""#include TOWNDEF.H
; ------------ Shop Item List Table --------------
;[item]
;code = 99
;item_id = 1,2,3

[item]							; 歐姆村
code = 1
item_id = 1,81
item_id = 101

[item]
code = 2
item_id = 121

[town_event]						; 歐姆村武器店
code = 1							; from 1 start
show_name = 32						; 老闆
item_code = 1						; map to shop item list table above
event = teShapeMessage,SHAPE\FACE0073.SHP,876,869,0
event = teCreateShop,32

[town_event]
code = 2
show_name = 30
event = tePlayerMessage,SID_雷歐納德,1203,0,
event = teDeleteSelfTE,7,1,14,teAddSelfTE,7,1,15
event = teSelectInsertEvent,SID_雷歐納德,2,1186,108,1187,109
event = teBogusToken,1
"""

TOWNDEF_H = """
#define teAddSelfTE  			1		// [parent][num][child1][...]
#define teDeleteSelfTE  		2		// [parent][num][child1][...]
#define tePlayerMessage			5		// [player id][message id][if_wait]
#define teShapeMessage			7		// [shape file][name][message id][if_wait]
#define teCreateShop			9		// [shop' name]
#define teSelectInsertEvent		15		// [player id][num, max = 8][msg id 1][event 1][msg id 2][event 2][....]
#define teCheckMoney2			101
"""


class WorldMapParsingTests(unittest.TestCase):
    def test_parse_bigmap_records_and_flags(self):
        parsed = wm.parse_bigmap(synthetic_bigmap())
        points, tracks = parsed["points"], parsed["tracks"]
        self.assertEqual([p["id"] for p in points], [1, 2, 3])
        self.assertEqual(points[0]["raw_field0"], 2)
        self.assertEqual(points[0]["flag_names"], ["bmpmTown"])
        self.assertEqual(points[0]["flags_raw"], "0x20000000")
        self.assertEqual(points[1]["track_ids"], [1, 2])
        self.assertEqual(points[2]["flag_names"], ["bmpmBattle", "bmpmHidden"])
        self.assertIsNone(points[2]["flags_undecoded_bits"])
        self.assertEqual([t["id"] for t in tracks], [1, 2])
        self.assertEqual((tracks[0]["from_point"], tracks[0]["to_point"]), (1, 2))
        self.assertEqual(tracks[1]["raw_field1"], "0x08000000")
        self.assertEqual(tracks[1]["field1_flag_names"], ["bmpmHidden"])
        self.assertEqual(tracks[1]["field0_flag_names"], [])

    def test_parse_bigmap_rejects_wrong_size(self):
        with self.assertRaises(ValueError):
            wm.parse_bigmap(b"\0" * 100)

    def test_undecoded_flag_bits_are_reported(self):
        self.assertEqual(wm.undecoded_bits(0x20000001, wm.BMPM_FLAGS), "0x00000001")
        self.assertEqual(wm.decode_flag_names(0x20000001, wm.BMPM_FLAGS), ["bmpmTown"])

    def test_parse_defines_and_track_txt(self):
        defines = wm.parse_defines("#define bmTrack01               1\n#define bmTrack02 2\n#define bmpmHidden 0x08000000\n")
        self.assertEqual(defines, {"bmTrack01": 1, "bmTrack02": 2, "bmpmHidden": 0x08000000})
        tracks = wm.parse_track_txt(TRACK_TXT, defines)
        self.assertEqual([t["id"] for t in tracks], [1, 2])
        self.assertEqual(tracks[0]["code"], "bmTrack01")
        self.assertEqual(tracks[0]["polyline"], [[10, 20], [15, 25], [30, 40]])
        self.assertEqual(tracks[1]["polyline"], [[30, 40], [50, 60]])

    def test_self_check_matches_synthetic_data_and_flags_mismatch(self):
        parsed = wm.parse_bigmap(synthetic_bigmap())
        polylines = {t["id"]: t for t in wm.parse_track_txt(TRACK_TXT, {"bmTrack01": 1, "bmTrack02": 2})}
        self.assertEqual(wm.world_map_self_check(parsed["points"], parsed["tracks"], polylines), [])
        polylines[2]["polyline"][-1] = [51, 60]
        issues = wm.world_map_self_check(parsed["points"], parsed["tracks"], polylines)
        self.assertEqual(len(issues), 1)
        self.assertIn("track 2: polyline ends at [51, 60]", issues[0])
        parsed["points"][0]["track_ids"] = [9]
        self.assertIn("point 1: track id 9 has no track record", wm.world_map_self_check(parsed["points"], parsed["tracks"], polylines))


class TowndefParsingTests(unittest.TestCase):
    def test_split_events_chains_and_trailing_comma(self):
        self.assertEqual(
            wm.split_events("teDeleteSelfTE,7,1,14,teAddSelfTE,7,1,15"),
            [{"token": "teDeleteSelfTE", "args": ["7", "1", "14"]}, {"token": "teAddSelfTE", "args": ["7", "1", "15"]}],
        )
        self.assertEqual(wm.split_events("tePlayerMessage,SID_琥,1203,0,"), [{"token": "tePlayerMessage", "args": ["SID_琥", "1203", "0"]}])

    def test_parse_towndef_sections(self):
        parsed = wm.parse_towndef(TOWNDEF_TXT)
        self.assertEqual(parsed["includes"], ["TOWNDEF.H"])
        self.assertEqual(parsed["items"], [{"code": 1, "comment": "歐姆村", "item_ids": [1, 81, 101]}, {"code": 2, "comment": None, "item_ids": [121]}])
        self.assertEqual(len(parsed["town_events"]), 2)
        first = parsed["town_events"][0]
        self.assertEqual((first["code"], first["comment"], first["item_code"]), (1, "歐姆村武器店", 1))
        self.assertEqual(first["show_name"], {"resource_id": 32, "text": None})
        self.assertEqual([e["token"] for e in first["events"]], ["teShapeMessage", "teCreateShop"])
        second = parsed["town_events"][1]
        self.assertIsNone(second["item_code"])
        self.assertEqual([e["token"] for e in second["events"]], ["tePlayerMessage", "teDeleteSelfTE", "teAddSelfTE", "teSelectInsertEvent", "teBogusToken"])
        self.assertEqual(parsed["other_sections"], {})

    def test_annotate_resolves_tokens_names_and_message_ids(self):
        parsed = wm.parse_towndef(TOWNDEF_TXT)
        token_defs = wm.parse_defines_with_comments(TOWNDEF_H)
        self.assertEqual(token_defs["tePlayerMessage"], {"value": 5, "signature_comment": "[player id][message id][if_wait]"})
        self.assertEqual(token_defs["teCheckMoney2"], {"value": 101, "signature_comment": None})
        wm.annotate_town_events(parsed, token_defs, {"32": "武器店", "30": "老闆"})
        events = parsed["town_events"]
        self.assertEqual(events[0]["show_name"]["text"], "武器店")
        self.assertEqual(events[0]["events"][0]["token_id"], 7)
        self.assertEqual(events[1]["events"][-1], {"token": "teBogusToken", "args": ["1"], "token_id": None, "unknown": True})
        stats = parsed["statistics"]
        self.assertEqual(stats["token_usage"]["teShapeMessage"], 1)
        self.assertEqual(stats["token_usage"]["teCheckMoney2"], 0)
        self.assertEqual(stats["unknown_tokens"], {"teBogusToken": 1})
        self.assertEqual(stats["message_ids"]["ids"], ["869", "1186", "1187", "1203"])
        self.assertEqual(stats["message_ids"]["by_token"], {"tePlayerMessage": 1, "teSelectInsertEvent": 2, "teShapeMessage": 1})
        self.assertEqual(stats["shape_name_resource_ids"], ["876"])
        self.assertEqual(parsed["symbols_used"], ["SID_雷歐納德"])
        self.assertEqual(wm.towndef_self_check(parsed), [])
        parsed["town_events"][0]["item_code"] = 7
        self.assertEqual(wm.towndef_self_check(parsed), ["town_event 1: item_code 7 has no [item] record"])


if __name__ == "__main__":
    unittest.main()
