"""Import the original title-screen shapes (@:\\shape\\TitleNNN.SHP) and record the
title layout the remake draws.

Assets are resource-derived (decoded from the PAK, draw origins from the SHP header).
The screen layout is runtime-measured from the original gameplay reference frame
01_title_and_opening/frame_001.png (a 638x480 recording of the title): each shape was
template-matched against that frame by tools/hsl_title_layout_probe.py, and the item
highlight offsets were matched against the ring shape itself. Menu labels transcribe the
glyphs baked into Title021/024-026 (the shapes carry simplified-Chinese art; the remake
keeps the traditional spelling of RESOURCE.TXT for its own text). Menu semantics
(what each item does) are the remake's reading of the labels — provisional until the
title handler is located in the EXE.

Registry task title_assets (family assets): output content/imported/hsl/global/title/. Bodies
moved verbatim from the former hsl_title_assets.py (ROOT resolved from this file's depth).
"""
import hashlib
import json
import struct
import tempfile
from pathlib import Path

from hsltools.paths import ORIGINAL_PAK
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import (decoded_xor_a8_wave_bytes, find_decoded_paks_packages, find_paks_record_by_name,
                                  parse_xor_a8_wave_candidate, read_paks_record_bytes)
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import resource_names

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'content/imported/hsl/global/title'
DEFAULT_PAK = ORIGINAL_PAK
SCHEMA = 'hsl_title_assets.v1'
REFERENCE_FRAME = 'docs/evidence_packets/runtime_observations/original_gameplay_reference/01_title_and_opening/frame_001.png'

# role -> shape number. 024-026 are the red "lit" versions of the three ring items,
# 027/028 the gem and book beside item 1 (they bob; they do not follow the selection).
SHAPES = {
    'background': 1,
    'logo': 2,
    'ring': 21,
    'statue_left': 22,
    'statue_right': 23,
    'item_lit_new_story': 24,
    'item_lit_battle_record': 25,
    'item_lit_quit': 26,
    'cursor_gem': 27,
    'cursor_hand': 28,
    'game_over_background': 11,
    'game_over_text': 12,
    'system_panel': 41,
    'system_lit_mission': 42,
    'system_lit_save_record': 43,
    'system_lit_load_memoir': 44,
    'system_lit_load_record': 45,
    'system_lit_options': 46,
    'system_lit_main_menu': 47,
    'confirm_buttons': 61,
    'confirm_lit_ok': 62,
    'confirm_lit_cancel': 63,
    'world_panel': 51,
    'world_lit_arrange_equipment': 52,
    'world_lit_save_memoir': 53,
    'world_lit_load_memoir': 54,
    'world_lit_load_record': 55,
    'world_lit_options': 56,
    'world_lit_main_menu': 57,
    'memoir_list': 31,
    'memoir_heading_load': 32,
    'memoir_heading_save': 33,
    'options_panel': 39,
}
SYSTEM_REFERENCE_FRAME = 'docs/evidence_packets/runtime_observations/original_gameplay_reference/05_system_scroll_menu/frame_003.png'

# Screen top-left of each shape's decoded PNG in the 640x480 logical viewport
# (runtime-measured: best template match against the reference frame; mean abs RGB
# difference of the match in parentheses, the recording is lossy).
REFERENCE_LAYOUT = {
    'background': {'top_left': [0, 0], 'note': '640x480 full-frame backdrop; drawn at the origin'},
    'logo': {'top_left': [99, 12], 'match_diff': 21.6},
    'ring': {'top_left': [197, 161], 'match_diff': 16.4},
    'statue_left': {'top_left': [117, 227], 'match_diff': 13.0},
    'statue_right': {'top_left': [405, 227], 'match_diff': 11.7},
    'cursor_gem': {'top_left': [216, 257], 'match_diff': 16.6, 'note': 'beside item 1 (開始新故事) in the frame; it bobs vertically and does not follow the selection (original_title_ornaments)'},
    'cursor_hand': {'top_left': [386, 243], 'match_diff': 10.0, 'note': 'the book beside item 1 on the right; it bobs vertically and does not follow the selection (original_title_ornaments)'},
    'game_over_background': {'top_left': [0, 0], 'note': '640x480 sunset backdrop of the GAME OVER screen; drawn at the origin'},
    'game_over_text': {'top_left': [55, 211], 'evidence_tier': 'provisional',
                       'note': 'Title012 (531x58) has its draw origin at its centre (265,29); no recording shows the GAME OVER screen, so the text is centred on the 640x480 frame'},
    'system_panel': {'top_left': [190, 67], 'match_diff': 10.6, 'reference_frame': SYSTEM_REFERENCE_FRAME,
                     'note': 'Title041 (257x345) fully open in the in-battle recording: centred on the 640x480 frame; frames 001/002 and 004/005 show it scrolling in from and out to the bottom edge'},
    'confirm_buttons': {'top_left': [256, 217], 'evidence_tier': 'runtime-measured',
                        'note': 'Title061 (128x47, 確定|取消) over the centre of the open system scroll with no question text: template match on the 2026-09-24 recording at 582.0 s (儲存戰場記錄, mean diff 17.1) and 592.5 s (回主選單, 9.5), docs/evidence_packets/runtime_observations/menus_ui/README.md'},
    'world_panel': {'top_left': [190, 67], 'evidence_tier': 'provisional',
                    'note': 'Title051 (257x345, the between-battle variant: 整理裝備／儲存回憶錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單) is not shown in any recording; the remake reuses the in-battle scroll position'},
    'memoir_list': {'top_left': [87, 44], 'evidence_tier': 'static-derived',
                    'note': 'Title031 (466x392, 回憶錄 with eight slot bands): defProcMemoir 0x424a60 centres it on the 640x480 frame and starts it at x + 640, stepping it in with 0x45e882 (each tick min(40, distance >> 3) px, at least 2) and back out to the right at 40 px per tick (0x45e91e); docs/evidence_packets/runtime_observations/menus_ui/README.md §3'},
    'options_panel': {'top_left': [142, 90], 'evidence_tier': 'runtime-measured',
                      'note': 'Title039 (355x299, 設定選項: 場景效果 off/on, 預備動作 off/on, 音效音量 min/max, 音樂音量 min/max) centred on the 640x480 frame: template match on the 2026-09-24 recording at 588.0 s (mean diff 21.4), docs/evidence_packets/runtime_observations/menus_ui/README.md'},
}

# 設定選項 rows inside Title039 (resource-derived geometry: the four label glyph rows at
# y 94-119, 137-162, 194-218, 237-261 and the recessed grooves at x 162-330 right of them;
# off/on and min/max are baked above the first and third rows). The gem cursor Title027
# stands in for the indicator/knob (no knob shape exists in the family: provisional).
OPTIONS_ROWS = [
    {'id': 'scene_effects', 'label': '場景效果', 'glyphs_in_shape': '场景效果', 'kind': 'toggle', 'center_y_in_panel': 106},
    {'id': 'ready_action', 'label': '預備動作', 'glyphs_in_shape': '预备动作', 'kind': 'toggle', 'center_y_in_panel': 149},
    {'id': 'sfx_volume', 'label': '音效音量', 'glyphs_in_shape': '音效音量', 'kind': 'slider', 'center_y_in_panel': 206},
    {'id': 'music_volume', 'label': '音樂音量', 'glyphs_in_shape': '音乐音量', 'kind': 'slider', 'center_y_in_panel': 249},
]
OPTIONS_GROOVE = {'x': [162, 330], 'knob_margin': 18, 'knob': 'cursor_gem'}

# Between-battle scroll (Title051) items (resource-derived rows at y 44-69, 90-114, 136-159,
# 181-205, 228-252, 274-299; x centre 128). Every lit offset in WORLD_ITEMS, SYSTEM_ITEMS and
# CONFIRM_ITEMS is the glyph registration LIT_GLYPH_REGISTRATION describes: the position where
# the lit shape's red glyphs cover the most of the panel's baked dark glyphs. The same rule
# reproduces all three recording-measured title ring offsets (ITEMS) exactly, which is why it
# replaces the earlier glyph-box centring (off by 1-2 px, lane R5-L5).
LIT_GLYPH_REGISTRATION = {
    'panel_glyph_max_channel': 50,
    'lit_glyph_red_margin': 60,
    'rule': 'panel glyph = opaque pixel with max(r, g, b) < panel_glyph_max_channel; lit glyph = opaque pixel with r exceeding g and b by more than lit_glyph_red_margin; the offset maximises the count of lit glyph pixels over panel glyph pixels',
    'check': 'tests/run_ui_class_contract_tests.gd lit_registration_contracts',
}
WORLD_ITEMS = [
    {'id': 'arrange_equipment', 'label': '整理裝備', 'glyphs_in_shape': '整理装备', 'lit': 'world_lit_arrange_equipment', 'lit_offset_in_panel': [54, 38], 'text_center_y_in_panel': 56},
    {'id': 'save_memoir', 'label': '儲存回憶錄', 'glyphs_in_shape': '储存回忆录', 'lit': 'world_lit_save_memoir', 'lit_offset_in_panel': [34, 81], 'text_center_y_in_panel': 102},
    {'id': 'load_memoir', 'label': '讀取回憶錄', 'glyphs_in_shape': '读取回忆录', 'lit': 'world_lit_load_memoir', 'lit_offset_in_panel': [35, 129], 'text_center_y_in_panel': 147},
    {'id': 'load_record', 'label': '讀取戰場記錄', 'glyphs_in_shape': '读取战场记录', 'lit': 'world_lit_load_record', 'lit_offset_in_panel': [19, 174], 'text_center_y_in_panel': 193},
    {'id': 'options', 'label': '設定選項', 'glyphs_in_shape': '设定选项', 'lit': 'world_lit_options', 'lit_offset_in_panel': [54, 222], 'text_center_y_in_panel': 240},
    {'id': 'main_menu', 'label': '回主選單', 'glyphs_in_shape': '回主选单', 'lit': 'world_lit_main_menu', 'lit_offset_in_panel': [53, 268], 'text_center_y_in_panel': 286},
]
# 回憶錄 list geometry inside Title031 (static-derived, defProcMemoir 0x424a60): slot row i is an
# object 791 at (37, 82 + 33 i), 390x26, its text drawn at the row origin in FONT.24 (0x425140);
# the mode heading (Title032 讀取回憶錄 / Title033 儲存回憶錄) sits at (148, 29) over the baked
# 回憶錄 title. Row text (0x424f00): the header's point name padded with spaces to 18 Big5 bytes,
# ' 等級', the level as two digits, ' ', the play clock (0x42d090 mode 1: hours right-aligned in
# three columns, ':', minutes as two digits); an empty or unreadable slot shows empty_text centred.
MEMOIR_LIST = {
    'slots': 8,
    'row_origin': [37, 82],
    'row_size': [390, 26],
    'slot_pitch': 33,
    'heading_offset': [148, 29],
    'name_bytes': 18,
    'empty_text': '\u25ba 無記錄 \u25c4',
}

# System-menu items: lit shapes Title042-047 registered on the baked glyph rows of Title041
# (resource-derived: dark glyph rows at y 44-69, 91-116, 141-164, 188-212, 236-260, 285-309).
SYSTEM_ITEMS = [
    {'id': 'mission', 'label': '任務說明', 'glyphs_in_shape': '任务说明', 'lit': 'system_lit_mission', 'lit_offset_in_panel': [50, 35], 'text_center_y_in_panel': 56},
    {'id': 'save_record', 'label': '儲存戰場記錄', 'glyphs_in_shape': '储存战场记录', 'lit': 'system_lit_save_record', 'lit_offset_in_panel': [17, 83], 'text_center_y_in_panel': 103},
    {'id': 'load_memoir', 'label': '讀取回憶錄', 'glyphs_in_shape': '读取回忆录', 'lit': 'system_lit_load_memoir', 'lit_offset_in_panel': [34, 132], 'text_center_y_in_panel': 152},
    {'id': 'load_record', 'label': '讀取戰場記錄', 'glyphs_in_shape': '读取战场记录', 'lit': 'system_lit_load_record', 'lit_offset_in_panel': [16, 179], 'text_center_y_in_panel': 200},
    {'id': 'options', 'label': '設定選項', 'glyphs_in_shape': '设定选项', 'lit': 'system_lit_options', 'lit_offset_in_panel': [51, 228], 'text_center_y_in_panel': 248},
    {'id': 'main_menu', 'label': '回主選單', 'glyphs_in_shape': '回主选单', 'lit': 'system_lit_main_menu', 'lit_offset_in_panel': [53, 277], 'text_center_y_in_panel': 297},
]
# 確定 / 取消 lit glyphs registered on the two button faces of Title061 (glyph columns 7-59 and 69-121).
CONFIRM_ITEMS = [
    {'id': 'ok', 'label': '確定', 'glyphs_in_shape': '确定', 'lit': 'confirm_lit_ok', 'lit_offset_in_buttons': [7, 14]},
    {'id': 'cancel', 'label': '取消', 'glyphs_in_shape': '取消', 'lit': 'confirm_lit_cancel', 'lit_offset_in_buttons': [69, 15]},
]

# The title track: EnterLevel plays level 0's table track 03 after the vendor logos (static-derived,
# docs/evidence_packets/static_reverse/original_music.md §3.1); the stream is the imported music\03.wav.
MUSIC = {
    'track': 3,
    'stream': 'res://content/imported/hsl/music/03.ogg',
    'evidence_tier': 'static-derived',
    'note': 'level 0 plays its table track 03 after the vendor logos (original_music.md §3.1); the remake has no logo stage, so 03 starts with the title',
}

# Item lit shapes matched against the ring shape (resource-derived, offsets inside Title021).
ITEMS = [
    {'id': 'new_story', 'label': '開始新故事', 'glyphs_in_shape': '开始新故事', 'lit': 'item_lit_new_story',
     'lit_offset_in_ring': [44, 58], 'text_center_y_in_ring': 91},
    {'id': 'battle_record', 'label': '戰場記錄', 'glyphs_in_shape': '战场记录', 'lit': 'item_lit_battle_record',
     'lit_offset_in_ring': [50, 113], 'text_center_y_in_ring': 133},
    {'id': 'quit', 'label': '離開遊戲', 'glyphs_in_shape': '离开游戏', 'lit': 'item_lit_quit',
     'lit_offset_in_ring': [46, 161], 'text_center_y_in_ring': 180},
]


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_member(pkgs, member: str) -> bytes:
    matches = [(p, r) for p in pkgs if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous resource: ' + member)
    p, r = matches[0]
    return read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))


# GameClear (level 998) shapes: obj-998.obs names them for defProcClearBOSS
# (OVERBG01, shape number 2 = OverBG01/02), defProcClearShowPlayer (TITLE011, one per
# party slot) and defProcClearShowWorkTeam (workteam / OVER001 / OVER002). OVER001/002
# are the ending narration in white glyphs (simplified-Chinese build like the title
# art); workteam is the 640x1440 credits scroll ending in 劇終.
GAME_CLEAR_SHAPES = {
    'clear_background_1': 'OverBG01',
    'clear_background_2': 'OverBG02',
    'clear_text_1': 'Over001',
    'clear_text_2': 'Over002',
    'clear_credits': 'workteam',
}
# The GameClear sequence as the four obj-998 processes run it, in original 16 ms ticks
# (docs/evidence_packets/static_reverse/original_game_clear.md): defProcClearBOSS 0x42b6b0
# orders the states, defProcClearShowWorkTeam 0x42bc20 scrolls Over001 / Over002 / workteam
# from y 500 at 0.5 px/tick (angle 0xC0, speed 0x8000), defProcClearShowPlayer 0x42ba10 rolls
# the nine party slots at 1 px/tick with the 0x42b2b0 status sheet (RESOURCE strings, FONT.24).
# The work-team credits are the workteam shape itself: no runtime credit strings exist.
def _SHEET_ITEM(resource: int, label: str, key: str, width: int, percent: bool = False) -> dict:
    return {'resource': resource, 'label': label, 'key': key, 'width': width, 'percent': percent}


GAME_CLEAR = {
    'backgrounds': ['clear_background_1', 'clear_background_2'],
    'fade_in_ticks_per_level': 6,
    'exit_fade_ticks_per_level': 2,
    'fade_levels': 16,
    'dark_screen_ticks_per_level': 6,
    'waits': {'opening': 40, 'before_story': 40, 'backdrop_swap': 120, 'after_story': 40, 'before_players': 40, 'before_credits': 240},
    'scroll_start_y': 500,
    'scroll_px_per_tick': 0.5,
    'scrolls': {
        'epilogue_1': {'shape': 'clear_text_1', 'past_top': 80, 'removed': True},
        'epilogue_2': {'shape': 'clear_text_2', 'past_top': 80, 'removed': True},
        'credits': {'shape': 'clear_credits', 'rest_bottom': 480, 'removed': False},
    },
    'showcase': {
        'slots': ['001', '002', '003', '004', '005', '006', '007', '008', '009'],
        'anchor_x': 320, 'start_y': 500, 'release_y': 100, 'remove_y': -250, 'px_per_tick': 1,
        'sheet_offset': [-252, 6], 'line_pitch': 26, 'byte_px': 12,
        'rows': [
            {'indent': 0, 'items': [_SHEET_ITEM(37, '姓名', 'name', 16), _SHEET_ITEM(41, '力量', 'str', 12), _SHEET_ITEM(54, '攻擊力', 'attack', 14)]},
            {'indent': 0, 'items': [_SHEET_ITEM(38, '稱號', 'title', 16), _SHEET_ITEM(42, '反應', 'dex', 12), _SHEET_ITEM(56, '防禦力', 'defense', 14)]},
            {'indent': 0, 'items': [_SHEET_ITEM(39, '種族', 'race', 16), _SHEET_ITEM(43, '精神', 'mind', 12), _SHEET_ITEM(131, '魔擊力', 'magic', 14, True)]},
            {'indent': 0, 'items': [_SHEET_ITEM(70, '移動力', 'move', 16), _SHEET_ITEM(44, '體質', 'con', 12), _SHEET_ITEM(132, '敏捷度', 'speed', 14)]},
            {'indent': 0, 'items': []},
            {'indent': 6, 'items': [_SHEET_ITEM(15, '等級', 'level', 14)]},
            {'indent': 6, 'items': [_SHEET_ITEM(57, '生命力', 'max_hp', 14), _SHEET_ITEM(48, '殺敵總數', 'kills', 16)]},
            {'indent': 6, 'items': [_SHEET_ITEM(58, '魔法力', 'max_mp', 14), _SHEET_ITEM(50, '復活次數', 'revives', 16)]},
        ],
        'not_joined': {'resource': 2568, 'text': '此角色未加入隊伍', 'row': 3, 'width': 42},
    },
    # Music cue per stretch, each played from the start (original_music.md §3.5): 07 on the first
    # frame, 04 when state 11 starts the players, 02 when state 17 inserts the work team.
    'music': {
        'epilogue_1': {'track': 7, 'stream': 'res://content/imported/hsl/music/07.ogg'},
        'showcase': {'track': 4, 'stream': 'res://content/imported/hsl/music/04.ogg'},
        'credits': {'track': 2, 'stream': 'res://content/imported/hsl/music/02.ogg'},
    },
    'evidence_tier': 'static-derived',
    'claim_limit': 'tick counts, start positions, scroll speeds and distances, the showcase release / removal lines, the status-sheet rows (RESOURCE ids) and the single exit input after the credits are static-derived from defProcClearBOSS / ShowWorkTeam / ShowPlayer (original_game_clear.md); no recording of the original GameClear exists, the sheet line pitch 26 is read from the 0x4123b0 argument, and revive counts are not tracked by the remake',
}

# The GameClear epilogue dialogue: DATA\STORYOVER.TXT is loaded by defProcClearBOSS
# (PROCESS.DEF 74; handler table @ 0x477c2c entry 74 -> 0x42b6b0, state 3 pushes the member
# name into the script loader) — static-derived, see
# docs/evidence_packets/static_reverse/original_game_clear_epilogue.md. Its ten 緹娜／漢克斯
# lines, delays and the WALKSOUND cue are read from the tracked story corpus; the script
# ends with actDeleteDarkScreen. The states run Over001 (1), STORYOVER (3), Over002 (9)
# (original_music.md §3.5), so the remake plays it on black between the two narration phases.
EPILOGUE_SCRIPT = ROOT / 'content/imported/hsl/story_corpus/scripts/STORYOVER.json'
PORTRAITS = ROOT / 'content/imported/hsl/chapter01/portraits/manifest.json'
EPILOGUE_SOUND_OUT = OUT / 'walksound.wav'
# Remake pacing for actDelay units (the opening coordinator's delay_token_seconds).
EPILOGUE_DELAY_UNIT_SECONDS = 0.025


def epilogue_steps() -> list[dict]:
    script = json.loads(EPILOGUE_SCRIPT.read_text(encoding='utf-8'))
    texts = {str(m['id']): m for m in script['messages']}
    actors = json.loads(PORTRAITS.read_text(encoding='utf-8'))['actors']
    # First row per name wins: job-up rows (020 公主 repeats 緹娜's name) follow the base
    # rows in the portrait manifest, and the epilogue draws the base portrait.
    by_name: dict[str, str] = {}
    for actor_id, entry in actors.items():
        by_name.setdefault(str(entry.get('name', '')), actor_id)
    steps: list[dict] = []
    for section in script['sections']:
        if section.get('name') != 'story':
            continue
        for action in section['actions']:
            for command in action['chain']:
                name, args = command['name'], [str(a) for a in command.get('args', [])]
                if name == 'actDelay':
                    steps.append({'kind': 'delay', 'units': int(args[0]), 'seconds': round(int(args[0]) * EPILOGUE_DELAY_UNIT_SECONDS, 3)})
                elif name == 'actMessage':
                    token, message_id = args[0], args[2]
                    speaker = token.removeprefix('SID_')
                    if speaker not in by_name:
                        raise ValueError('epilogue speaker has no portrait: ' + token)
                    steps.append({'kind': 'message', 'speaker_token': token, 'speaker': speaker, 'actor_id': by_name[speaker],
                                  'message_id': message_id, 'text': texts[message_id]['text']})
                elif name == 'actPlaySound':
                    steps.append({'kind': 'sound', 'ref': args[0], 'res_path': 'res://' + EPILOGUE_SOUND_OUT.relative_to(ROOT).as_posix()})
                elif name == 'actDeleteDarkScreen':
                    steps.append({'kind': 'reveal'})
                else:
                    raise ValueError('unexpected STORYOVER token: ' + name)
    return steps


def epilogue_block(sound_source_sha: str, sound_sha: str) -> dict:
    return {
        'source_member': '@:\\data\\STORYOVER.TXT',
        'loader': 'defProcClearBOSS (PROCESS.DEF 74 -> 0x42b6b0, state 3)',
        'evidence_tier': 'static-derived',
        'delay_unit_seconds': EPILOGUE_DELAY_UNIT_SECONDS,
        'steps': epilogue_steps(),
        'sound': {'ref': 'WAV\\WALKSOUND.WAV', 'source_member': '@:\\wav\\WALKSOUND.WAV', 'source_sha256': sound_source_sha, 'sha256': sound_sha,
                  'res_path': 'res://' + EPILOGUE_SOUND_OUT.relative_to(ROOT).as_posix()},
        'claim_limit': 'the loader, the lines, their order, the delays (in script units), the footstep cue and the place between Over001 and Over002 (defProcClearBOSS states 1 / 3 / 9, original_music.md §3.5) are static/resource-derived; the delay unit, the dialogue board, portraits, click-to-continue and the black screen behind the lines are remake readings — the original GameClear is not recorded',
    }


def decode_sound(pkgs, member: str) -> tuple[bytes, bytes]:
    raw = read_member(pkgs, member)
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / 'source.wav'
        source.write_bytes(raw)
        candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
        if candidate is None:
            raise ValueError('unsupported sound format: ' + member)
        return raw, decoded_xor_a8_wave_bytes(source, candidate)


def build(pak: Path) -> dict:
    pkgs = find_decoded_paks_packages(pak)
    raw_sound, sound = decode_sound(pkgs, '@:\\wav\\WALKSOUND.WAV')
    EPILOGUE_SOUND_OUT.write_bytes(sound)
    (OUT / 'previews').mkdir(parents=True, exist_ok=True)
    shapes = {}
    members = {role: f'@:\\shape\\Title{number:03d}.SHP' for role, number in SHAPES.items()}
    members.update({role: f'@:\\shape\\{name}.SHP' for role, name in GAME_CLEAR_SHAPES.items()})
    for role, member in members.items():
        raw = read_member(pkgs, member)
        info = parse_shp(raw)
        target = OUT / 'previews' / (member.split('\\')[-1] + '.png')
        write_shp_preview(raw, info, target)
        shapes[role] = {
            'source_member': member,
            'source_sha256': _sha(raw),
            'size': [int(info['width']), int(info['height'])],
            'draw_origin': list(struct.unpack_from('<ii', raw, 28)),
            'texture': 'res://' + target.relative_to(ROOT).as_posix(),
            'png_sha256': png_sha256(target),
            'evidence_tier': 'resource-derived',
        }
    manifest = {
        'schema': SCHEMA,
        'claim': 'Original title-screen shapes decoded from the PAK plus the screen layout measured from the reference recording; the remake draws them 1:1 in the 640x480 logical viewport.',
        'evidence_tier': 'resource-derived',
        'reference_frame': REFERENCE_FRAME,
        'shapes': shapes,
        'layout': REFERENCE_LAYOUT,
        'items': ITEMS,
        'system_items': SYSTEM_ITEMS,
        'world_items': WORLD_ITEMS,
        'memoir_list': MEMOIR_LIST,
        'options_rows': OPTIONS_ROWS,
        'options_groove': OPTIONS_GROOVE,
        'confirm_items': CONFIRM_ITEMS,
        'lit_glyph_registration': LIT_GLYPH_REGISTRATION,
        'music': MUSIC,
        'game_clear': GAME_CLEAR,
        'game_clear_epilogue': epilogue_block(_sha(raw_sound), _sha(sound)),
        'unresolved_semantics': [
            'the title handler sits at 0x423f00 (state table 0x424158; every item waits out the hold timer in state 3 0x424004, then code 0 開始新故事, 1 戰場記錄 0x42404c, 2 離開遊戲 0x4240b2 fading via 0x42cb60／0x42dc90(2); static-derived, docs/audits/STATE_COVERAGE_2026-09-28.md); on the 2026-09-24 recording the hovered item only sparkles and the red lit shape appears on the click (13.52 s), holds 0.75 s and the screen fades to black in 0.55 s (runtime-measured, docs/evidence_packets/runtime_observations/menus_ui/README.md) — the remake lights nothing on hover (the sparkle shape is not identified and not drawn), lights the hovered item only under OPT-GUIDE＝提示, lights the keyboard-selected item after an arrow key (remake), and adopts the hold and fade for all three items',
            'the gem (Title027) and book (Title028) stay beside item 1 whatever is selected and only bob vertically: defProcMainMenu 0x423cd0 spawns them at the ring top-left + (33,112)／(207,107), and defProcMainMenuItem 0x424360 sets y = spawn y + trunc(6·sin(angle·2π/256)) each tick, the byte angle stepping by 3 from its own rand() % 255 start (static-derived, docs/evidence_packets/runtime_observations/original_title_ornaments/README.md; the 1.65 s, ~5 px bob with no fixed phase relation on the original at 4-5 fps agrees, runtime-measured); clicking an item plays ACCEPT01 (RESOURCE 398, defProcMainMenuString 0x4242d6)',
            'the title music is located: level 0 plays table track 03 after the vendor logos (static-derived, original_music.md §3.1; manifest.music) and every level exit stops it at once; the remake has no vendor-logo stage, so 03 starts with the title and stops on the scene change or the intro movie',
            'item semantics are the remake reading of the labels: 開始新故事 = new campaign, 戰場記錄 = continue the saved campaign position, 離開遊戲 = quit',
            'the GAME OVER screen (Title011/012) is drawn on defeat when the player leaves for the title: no recording shows it, so its text position, fade timing and dismissal input are remake readings (provisional); its GAMEOVER.WAV cue (interface_audio sfxGameOver, resource 628) is static-derived: defProcGameOverBOSS 0x42aea0 plays it on its first frame',
            'the in-battle system menu (Title041-047) opens on Esc during the player action phase and scrolls in from the bottom edge (remake timing); its handler and the exact scroll speed are not located in the EXE (provisional); 讀取回憶錄 is read as "resume the saved campaign position" and 設定選項 is not remade yet',
            'the between-battle scroll (Title051-057) is not shown in any recording: its position is a remake reading (provisional); the 回憶錄 list (Title031-033) position, row geometry, row text and empty-slot text are static-derived (defProcMemoir 0x424a60, rows 0x424f00／0x425140, menus_ui README §3); the memoir files (user://memoir_N.json) are the remake store; 整理裝備 and the world variant of 讀取戰場記錄 are not remade yet',
            'the GameClear sequence (level 998) runs as defProcClearBOSS orders it, in 16 ms ticks: a 96-tick fade-in, Over001 / Over002 / workteam scrolled from y 500 at 0.5 px/tick, the nine party slots at 1 px/tick with their status sheets, 240 ticks before the credits, and input only once the credits rest (static-derived, docs/evidence_packets/static_reverse/original_game_clear.md; manifest.game_clear); the credits are the workteam shape itself, no runtime credit strings exist; no recording of the original GameClear exists',
            'the 設定選項 panel (Title039) sits at (142,90) on the 2026-09-24 recording (588.0 s, runtime-measured); the gem knob, the row semantics (場景效果 = story effect objects such as rain/lightning/fire; 音效／音樂音量 = SFX/music buses) and the key bindings are remake readings (provisional); 預備動作 is the original cast-lead switch (READYACTION 2026-09-27: GameSettings.ready_action, 0x477c14 bit 1)',
        ],
    }
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest


def check() -> None:
    manifest = json.loads((OUT / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('schema') != SCHEMA:
        raise SystemExit('title manifest uses an unexpected schema')
    if set(manifest['shapes']) != set(SHAPES) | set(GAME_CLEAR_SHAPES):
        raise SystemExit('title manifest roles differ from the tool')
    for role, entry in manifest['shapes'].items():
        path = ROOT / entry['texture'].removeprefix('res://')
        if not path.is_file() or png_sha256(path) != entry['png_sha256']:
            raise SystemExit(f'title preview mismatch for {role}: {path}')
        if len(entry['draw_origin']) != 2 or len(entry['size']) != 2:
            raise SystemExit(f'title shape entry malformed for {role}')
    if manifest['layout'] != REFERENCE_LAYOUT or manifest['items'] != ITEMS or manifest.get('music') != MUSIC or manifest.get('game_clear') != GAME_CLEAR:
        raise SystemExit('title layout/items/music/game_clear differ from the tool constants')
    if (manifest.get('system_items') != SYSTEM_ITEMS or manifest.get('world_items') != WORLD_ITEMS
            or manifest.get('confirm_items') != CONFIRM_ITEMS or manifest.get('lit_glyph_registration') != LIT_GLYPH_REGISTRATION):
        raise SystemExit('title scroll/confirm lit offsets differ from the tool constants')
    phase_ids = set(GAME_CLEAR['scrolls']) | {'showcase'}
    names = resource_names()
    for row in GAME_CLEAR['showcase']['rows']:
        for item in row['items']:
            if names.get(str(item['resource'])) != item['label']:
                raise SystemExit(f'game clear sheet label differs from RESOURCE.TXT: {item}')
    not_joined = GAME_CLEAR['showcase']['not_joined']
    if names.get(str(not_joined['resource'])) != not_joined['text']:
        raise SystemExit('game clear not-joined line differs from RESOURCE.TXT')
    for phase_id, cue in GAME_CLEAR['music'].items():
        if phase_id not in phase_ids or cue['stream'] != f'res://content/imported/hsl/music/{cue["track"]:02d}.ogg':
            raise SystemExit(f'game clear music cue malformed: {phase_id} {cue}')
        if not (ROOT / cue['stream'].removeprefix('res://')).is_file():
            raise SystemExit('game clear music stream missing: ' + cue['stream'])
    epilogue = manifest.get('game_clear_epilogue', {})
    sound = epilogue.get('sound', {})
    if not EPILOGUE_SOUND_OUT.is_file() or _sha(EPILOGUE_SOUND_OUT.read_bytes()) != sound.get('sha256'):
        raise SystemExit('game clear epilogue sound missing or changed: ' + str(EPILOGUE_SOUND_OUT))
    if epilogue != epilogue_block(str(sound.get('source_sha256', '')), str(sound.get('sha256', ''))):
        raise SystemExit('game clear epilogue differs from the tracked STORYOVER corpus')

    if MUSIC['stream'] != f'res://content/imported/hsl/music/{MUSIC["track"]:02d}.ogg' \
            or not (ROOT / MUSIC['stream'].removeprefix('res://')).is_file():
        raise SystemExit('title music stream missing or not its track: ' + MUSIC['stream'])
    if not (ROOT / manifest['reference_frame']).is_file():
        raise SystemExit('title reference frame missing: ' + manifest['reference_frame'])
    print(f'TITLE_ASSETS_CHECK_PASS shapes={len(manifest["shapes"])} items={len(manifest["items"])}')


class TitleAssetsTask(ScriptCheckTask):
    name = 'title_assets'
    family = 'assets'
    inputs = ('content/imported/hsl/story_corpus/scripts/STORYOVER.json', 'content/imported/hsl/chapter01/portraits/manifest.json',
              REFERENCE_FRAME, SYSTEM_REFERENCE_FRAME)
    outputs = ('content/imported/hsl/global/title/',)
    replaces = ('tools/hsl_title_assets.py --check',)
    scripts = ('tools/hsltools/assets/title_assets.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        manifest = build(original_archive(ctx))
        print(f'TITLE_ASSETS_BUILD_PASS shapes={len(manifest["shapes"])} output={OUT.relative_to(ROOT)}')


def tasks() -> list[TitleAssetsTask]:
    return [TitleAssetsTask()]
