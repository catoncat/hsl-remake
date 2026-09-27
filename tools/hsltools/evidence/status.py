"""Check tracked status-source joins and a reviewed static contract, without executing an EXE.

Registry task status_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_status_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from hsltools.registry import Context, ScriptCheckTask
from hsltools.sources.tables import blocks

ROOT = Path(__file__).resolve().parents[3]
TABLES = ROOT / 'content/imported/hsl/global/tables'
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_status_effects.json'
FUNCTION_BITS = {'magicFun_Poison': 8, 'magicFun_NoMagic': 16, 'magicFun_Paralysis': 4}
ACTORS = ('1', '21', '23', '24', '25', '26')


def source_join(sources: dict[str, bytes]) -> dict:
    text = sources['TYPE.H'].decode('cp950')
    for name, expected in FUNCTION_BITS.items():
        match = re.search(r'^#define\s+' + name + r'\s+(0x[0-9a-fA-F]+|\d+)\b', text, re.M)
        if not match or int(match[1], 0) != expected:
            raise ValueError('Status function definition differs: ' + name)
    players = {r['code']: r for r in blocks(sources['PLAYERS.TXT'], 'character') if 'code' in r}
    for actor in ACTORS:
        if players[actor].get('status') != '0':
            raise ValueError('Initial nonzero/missing status needs counter evidence: ' + actor)
    items = {r['code']: r for r in blocks(sources['ITEM.TXT'], 'item') if 'code' in r}
    if items['246'].get('cure_poison') != '1' or items['246'].get('type') != 'itemTypeUse':
        raise ValueError('Initial antidote source differs')
    return {'functions': FUNCTION_BITS, 'initial_flags': {actor: 0 for actor in ACTORS},
            'antidote': {'code': 246, 'source_field': 'cure_poison', 'value': 1}}


def expected_packet() -> dict:
    sources = {name: (TABLES / name).read_bytes() for name in ['TYPE.H', 'ITEM.TXT', 'PLAYERS.TXT']}
    return {
        'schema': 'hsl_status_effects_static.v1', 'evidence_tier': 'static-derived',
        'source_sha256': {name: hashlib.sha256(raw).hexdigest() for name, raw in sources.items()},
        'source_join': source_join(sources),
        'expected_original_exe_sha256': 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7',
        'verification': {'native_execution': False, 'new_exe_byte_check': False,
                         'source_archive_check': False, 'tracked_tables_checked': True,
                         'note': 'Reviewed local r2 disassembly. A later byte-sampling request was refused twice; no probe or alternate byte read was run.'},
        'states': {
            'poison': {'function_bit': 8, 'actor_flag': 1, 'counter_offset': '0x30', 'power_offset': '0x32',
                       'apply_flag': '0x40ad49', 'apply_duration': '0x40ad71', 'apply_power': '0x40ae1c'},
            'no_magic': {'function_bit': 16, 'actor_flag': 2, 'counter_offset': '0x34',
                         'apply_flag': '0x40ae82', 'apply_duration': '0x40aeaa',
                         'player_menu_gate': '0x43eaf0', 'ai_gates': ['0x40c5bc', '0x40c5d9']},
            'paralysis': {'function_bit': 4, 'actor_flag': 4, 'counter_offset': '0x3c',
                          'apply_flag': '0x40ac97', 'apply_duration': '0x40acc0', 'live_scope': 'Existing counterattack rejection only; whole wake/skip lifecycle pending.'},
        },
        'antidote': {'loader': '0x447f70', 'loader_flag': '0x447f85', 'item_flag_offset': '0xa0',
                     'item_flag': '0x80000000', 'effect_branch': '0x40a2e6', 'zero_counter_word': '0x40a2f0',
                     'clear_poison_flag': '0x40a2f3', 'effect': 'clear flag1 and the entire packed poison duration/power DWORD'},
        'post_action': {'player_damage': '0x443ade..0x443b02', 'ai_damage': '0x441f69..0x441f8d',
                        'damage': 'HP := max(1, HP - unsigned_high16(poison_word)) for living coherent poisoned actors',
                        'tick': '0x40b910', 'queue_after_tick': ['0x443c1a->0x443c22', '0x443c38->0x443c40'],
                        'duration': 'If the packed DWORD is nonzero, decrement its low16. Signed low16 <= 0 clears the entire DWORD and the corresponding actor flag.',
                        'valid_live_domain': 'poison/no_magic low16 1..9 when active; initial status0 uses both words0',
                        'raw_difference': 'AI tests poison flag1 as well as nonzero word; the player damage block checks the word. The live model rejects inconsistent inputs.'},
        'limits': ['No new original function execution or EXE byte-identity test is claimed.',
                   'PLAYERS archival mismatch inherited from shared_skill_resolution.md remains unresolved.',
                   'Status infliction probability, immunity, duration RNG and potency creation are not enabled.',
                   'Paralysis wake/skip, weaken/buffs and their stat refresh are not implemented by this slice.',
                   'No-effect antidote refusal, adjacency and confirmation instead of native drag input are remake policies.',
                   'Post-action animation delays, HP/MP regeneration and death/terminal ordering remain separate.'],
    }


class StatusEvidenceTask(ScriptCheckTask):
    name = 'status_evidence'
    family = 'evidence'
    inputs = ('content/imported/hsl/global/tables/',)
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_status_evidence.py',)
    scripts = ('tools/hsltools/evidence/status.py',)

    def verify(self, ctx: Context) -> None:
        packet = expected_packet()
        if json.loads(PACKET.read_text()) != packet:
            raise ValueError('Status evidence or tracked sources differ')
        print('STATUS_SOURCE_EVIDENCE_PASS native_execution=False new_exe_byte_check=False')


def tasks() -> list[StatusEvidenceTask]:
    return [StatusEvidenceTask()]
