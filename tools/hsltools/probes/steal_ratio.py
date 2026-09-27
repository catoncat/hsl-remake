"""Bounded original execution of the steal bonus word +0x196 and the StealItem slot loop.

Three groups, no callee stubbed or patched:

  refresh   0x448840 on a full PLAYERS record: +0x196 = PLAYERS steal_ratio word (+0x194, 12 when 0)
            plus every equipped ITEM add_steal_ratio (+0x40, added by 0x448420); run twice so the
            work value is recomputed, not accumulated
  job_up    0x4348f0(slot, flag) with a PLAYERS template as the up-tier row: +0x194 adds the two
            words (0x434aa6), the inner 0x448840 rewrites +0x196 from the summed word
  steal     0x40b8f0 -> 0x40aa80 with the 金之手 SPECIAL row (function 0x40000): after the channel-1
            hit roll the eight target slots are walked in order; an empty slot ends the walk (break,
            not continue); rand100+1 < get_ratio + 10 + caster+0x196 steals the first passing item
            into the pending queue (0x44f2d0), shifts the target inventory (0x436e80), adds the
            proc0 value to the tail contribution and converts rand(level)+1 at once (0x40a5d0)

Registry task steal_ratio (family probe, hsltools.probes._base.ProbeTask): check validates the tracked
packet against the independent models (hsltools.model.jobs, special_damage.expected,
experience.expected); generate executes the original instructions (needs the documented hsl01.exe
and unicorn). Added after the ledger migration: replaces=().
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import struct

from hsltools.model.jobs import SLOTS, source_profile
from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.experience import expected as experience_expected
from hsltools.probes.special_damage import expected as damage_expected
from hsltools.probes.stat_magic import machine as gear_machine, put_actor
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_steal_ratio.json'
SOURCES = ['PLAYERS.TXT', 'ITEM.TXT', 'SPECIAL.TXT', 'TYPE.H']
STEAL_ITEM = 0x40000
ANCHORS = [
    (0x4489bd, 31, '0x448840: +0x196 = word +0x194, or 12 when that word is 0 (same default block as +0x19e 12 / +0x1a2 8).'),
    (0x4486dd, 11, '0x448420: word +0x196 += item +0x40 (add_steal_ratio) for every equipped item.'),
    (0x434a9f, 56, '0x4348f0: the four low words +0x194/+0x198/+0x19c/+0x1a0 add the up-tier template words; +0x196 is left to the refresh.'),
    (0x447ad6, 35, 'ITEM loader stores add_steal_ratio into item +0x40.'),
    (0x40b59a, 138, 'StealItem: after the hit roll walk the eight slots; an empty slot ends the walk; rand100+1 < get_ratio+10+caster+0x196 steals the first passing item.'),
    (0x40b626, 111, 'A stolen item enters the pending queue, the slot shifts left, the proc0 value joins the contribution and rand(level)+1 converts at once.'),
    (0x40e6c0, 26, 'get_ratio getter reads item +0xac.'),
    (0x436e80, 74, 'Target slot removal shifts the following slots left and clears the eighth.'),
]
ANCHOR_SHA = 'e674d0c10c1c351a75b550e5b1404588ddc58e6927b3273e6ac9daa678ad75b3'


def steal_row():
    return next(r for r in blocks((TABLES / 'SPECIAL.TXT').read_bytes(), 'special')
                if r['type'] == 'magicOTHER' and r['code'] == 'magicCode12')


def add_steal(items, code):
    return int(items[code].get('add_steal_ratio', 0)) if code else 0


def work_value(word, gear, items):
    return ((word & 0xffff) or 12) + sum(add_steal(items, code) for code in gear)


# --- 0x448840 --------------------------------------------------------------------------------

def refresh_cases():
    rows = []
    for actor in ['001', '004', '013']:
        for gear in [None, [0, 0, 131, 0, 0, 0], [0, 0, 131, 0, 131, 0]]:
            rows.append(dict(actor=actor, level=5, word=None, gear=gear))
    # synthetic PLAYERS words on the 001 record: the 0 -> 12 default and a nonzero word kept as is
    rows += [dict(actor='001', level=5, word=word, gear=gear) for word in [0, 1, 12, 30, 50, 200]
             for gear in [None, [0, 0, 131, 0, 0, 0]]]
    return rows


def refresh_inputs(case):
    players, items, _ = sources(); row = players[case['actor']]
    gear = case['gear'] if case['gear'] is not None else [int(row.get(k, 0)) for k in SLOTS]
    word = case['word'] if case['word'] is not None else int(row.get('steal_ratio', 0))
    return word, gear


def refresh_expected(case):
    _, items, _ = sources(); word, gear = refresh_inputs(case)
    return dict(word=word, work=work_value(word, gear, items) & 0xffff)


def put_gear_steal(put, items, gear):
    for code in gear:
        if code:
            put(0x20000000 + 176 * code + 0x40, add_steal(items, code))


def execute_refresh(base, mapped, case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
    m = gear_machine(base, mapped); actor, stack, stop = 0x10004000, 0x1001ff00, 0x10000000
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get16(at): return struct.unpack('<H', m.mem_read(at, 2))[0]
    _, items, _ = sources(); word, gear = refresh_inputs(case)
    put_actor(m, actor, case['actor'], case['level'], 1, 0, gear, {})
    put_gear_steal(put, items, gear)
    m.mem_write(actor + 0x194, struct.pack('<H', word & 0xffff))
    steps = 0
    def guard(_m, at, _size, _data):
        nonlocal steps
        steps += 1
        if not 0x448370 <= at < 0x44b820: raise ValueError(f'Unreviewed steal refresh callee {at:#x}')
    m.hook_add(UC_HOOK_CODE, guard); results = []; wanted = refresh_expected(case)
    for _ in range(2):
        m.mem_write(actor + 0x196, struct.pack('<H', 0x7777)); prior = steps
        m.mem_write(stack, struct.pack('<2I', stop, actor)); m.reg_write(UC_X86_REG_ESP, stack)
        m.emu_start(0x448840, stop, count=12000)
        actual = dict(word=get16(actor + 0x194), work=get16(actor + 0x196))
        if m.reg_read(UC_X86_REG_EIP) != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4 or actual != wanted:
            raise ValueError(f'Steal refresh differs {case}: {actual} != {wanted}')
        results.append(dict(values=actual, normal_return=True, instructions=steps - prior))
    return dict(input=case, gear=gear, native=results)


# --- 0x4348f0 --------------------------------------------------------------------------------

def job_up_cases():
    rows = [dict(record='004', template='013', gear=None, flag=0x80000000), dict(record='001', template='010', gear=None, flag=0x80000000),
            dict(record='010', template='019', gear=None, flag=0x40000000), dict(record='004', template='013', gear=[0, 0, 131, 0, 0, 0], flag=0x80000000),
            dict(record='013', template='004', gear=None, flag=0x80000000)]
    return rows


def job_up_expected(case):
    players, items, _ = sources(); record, template = players[case['record']], players[case['template']]
    gear = case['gear'] if case['gear'] is not None else [int(record.get(k, 0)) for k in SLOTS]
    if int(template.get('weapon_equip', 0)): gear = [int(template['weapon_equip']), *gear[1:]]
    word = (int(record.get('steal_ratio', 0)) + int(template.get('steal_ratio', 0))) & 0xffff
    return dict(word=word, work=work_value(word, gear, items) & 0xffff, job=source_profile(template, sources()[2])['job_code'])


def execute_job_up(base, mapped, case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = gear_machine(base, mapped)
    roster, templates, descriptor, stack, stop = 0x10004000, 0x10008000, 0x10003000, 0x1001ff00, 0x10000000
    slot, up_code, template_index, current_code = 3, 809, 2, 803
    record, template = roster + (slot + 1) * 0x1fc, templates + template_index * 0x1fc
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    def get16(at): return struct.unpack('<H', m.mem_read(at, 2))[0]
    players, items, defines = sources(); source = players[case['record']]; target = players[case['template']]
    gear = case['gear'] if case['gear'] is not None else [int(source.get(k, 0)) for k in SLOTS]
    put_actor(m, record, case['record'], 5, 1, 0, gear, {})
    put_actor(m, template, case['template'], 1, 1, 0, [int(target.get(k, 0)) for k in SLOTS], {})
    put_gear_steal(put, items, gear + [int(target.get(k, 0)) for k in SLOTS])
    for at, row in [(record, source), (template, target)]:
        m.mem_write(at + 0x194, struct.pack('<H', int(row.get('steal_ratio', 0))))
    m.mem_write(record + 0x196, struct.pack('<H', 0x7777)); m.mem_write(template + 0x196, struct.pack('<H', 0x6666))
    put(record + 0x60, up_code); put(0x4c1bc8, roster); put(0x4c1afc, templates)
    put(0x4c4360 + slot * 4, current_code); put(0x4a2728 + up_code * 4, descriptor); m.mem_write(descriptor + 0xa4, struct.pack('<H', template_index))
    steps = 0
    allowed = [(0x4348f0, 0x434b5d), (0x42caa0, 0x42cab5), (0x45dbe1, 0x45dbf1), (0x42c700, 0x42c715), (0x448370, 0x44b820)]
    def guard(_m, at, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= at < hi for lo, hi in allowed): raise ValueError(f'Unreviewed job-up callee {at:#x}')
    m.hook_add(UC_HOOK_CODE, guard)
    before = {off: bytes(m.mem_read(record + off, size)) for off, size in [(0x64, 16), (0x88, 4), (0x9c, 4), (0x138, 32)]}
    m.mem_write(stack, struct.pack('<3I', stop, slot, case['flag'])); m.reg_write(UC_X86_REG_ESP, stack)
    m.emu_start(0x4348f0, stop, count=16000)
    if m.reg_read(UC_X86_REG_EIP) != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4 or m.reg_read(UC_X86_REG_EAX) != 0:
        raise ValueError('Job-up exchange boundary differs')
    if any(bytes(m.mem_read(record + off, len(value))) != value for off, value in before.items()):
        raise ValueError('Job-up exchange changed attributes, EXP, level or inventory')
    actual = dict(word=get16(record + 0x194), work=get16(record + 0x196), job=get(record + 0x18))
    wanted = job_up_expected(case)
    if actual != wanted or get(0x4c4360 + slot * 4) != up_code or get(record + 0x134) != case['flag']:
        raise ValueError(f'Job-up steal word differs {case}: {actual} != {wanted}')
    return dict(input=case, native=dict(actual, slot_code=get(0x4c4360 + slot * 4), job_up_flags=hex(get(record + 0x134))),
                template_word=int(target.get('steal_ratio', 0)), record_word=int(source.get('steal_ratio', 0)),
                normal_return=True, instructions=steps)


# --- 0x40b8f0 -> 0x40aa80 StealItem -------------------------------------------------------------

def steal_cases():
    base = dict(level=5, dex=15, mind=15, con=15, hit=100, caster_word=12, target_level=3, target_hp=100, seed=1,
                inventory=[210, 246, 241, 0, 0, 0, 0, 0])
    rows = [dict(base, seed=seed, caster_word=word) for seed in [1, 7, 19, 23, 40, 62] for word in [12, 30, 50, 0]]
    # left-packed vs holes: the native walk ends at the first empty slot
    for inventory in [[0, 210, 246, 241, 0, 0, 0, 0], [210, 0, 246, 241, 0, 0, 0, 0], [246, 246, 0, 210, 0, 0, 0, 0],
                      [0] * 8, [210] * 8, [244, 244, 254, 202, 241, 246, 248, 210]]:
        rows += [dict(base, seed=seed, inventory=inventory) for seed in [1, 7, 19, 40]]
    # get_ratio 0 weapons with the bare word 0: threshold 10, so a full eight-slot walk without a steal and
    # a failed first slot followed by the empty-slot stop are both reachable
    rows += [dict(base, seed=seed, caster_word=0, inventory=[32, 33, 34, 35, 36, 37, 38, 39]) for seed in [1, 7, 19, 40, 62, 99]]
    rows += [dict(base, seed=seed, caster_word=0, inventory=[32, 0, 210, 246, 0, 0, 0, 0]) for seed in [1, 7, 19, 40]]
    # the hit roll itself can miss (row hit_ratio 90) and the caster level changes the immediate conversion
    rows += [dict(base, hit=90, seed=seed) for seed in [1, 7, 11, 12, 35, 40]]
    rows += [dict(base, level=level, seed=7) for level in [1, 20, 120]]
    return rows


def steal_expected(case, draws):
    """Independent model: the channel-1 hit roll (special_damage.expected), the slot walk on the
    recorded rand100 draws, the immediate rand(level)+1 conversion and the tail conversion
    (experience.expected)."""
    _, items, _ = sources(); row = steal_row(); low, high = map(int, row['damage'].split(','))
    hit = damage_expected(dict(low=low, high=high, hit_ratio=case['hit'], attackpow_ratio=int(row['attackpow_ratio']), hit_bonus=0,
                               magic_hit_bonus=0, level=case['level'], dex=case['dex'], mind=case['mind'], con=case['con'],
                               no_attack=False, defense=0, resistance=0, element=5), [d for d in draws if d['stage'] == 'hit'])
    value = hit['value']; inventory = list(case['inventory']); stolen = None; rolls = []; immediate = 0; tail = 0
    steal_draws = [d for d in draws if d['stage'] == 'steal']
    if value:
        for slot, code in enumerate(case['inventory']):
            if code == 0: break
            if not steal_draws or steal_draws[0]['bound'] != 100: raise ValueError('Steal walk random-call order differs')
            roll = steal_draws.pop(0)['value'] + 1; rolls.append(roll)
            if roll < int(items[code]['get_ratio']) + 10 + case['caster_word']:
                stolen = dict(slot=slot, code=code); inventory = inventory[:slot] + inventory[slot + 1:] + [0]
                break
    if steal_draws: raise ValueError('Unexpected trailing steal draw')
    immediate_draws = [d for d in draws if d['stage'] == 'immediate']
    conversions = {stage: [d for d in draws if d['stage'] == stage] for stage in ['experience_immediate', 'experience_tail', 'experience_direct']}
    exp_case = dict(attacker_level=case['level'], target_level=case['target_level'], target_hp=case['target_hp'], kill_exp=0, kill_word=0)
    if stolen:
        # 0x40b663..0x40b68b: rand(level)+1 replaces the running contribution for one 0x40a5d0 call, then the
        # proc0 value (restored) converts once more at 0x40b866.
        if len(immediate_draws) != 1 or immediate_draws[0]['bound'] != case['level'] or conversions['experience_direct']: raise ValueError('Immediate conversion draw differs')
        immediate = experience_expected(dict(exp_case, contribution=immediate_draws[0]['value'] + 1), conversions['experience_immediate'])
        tail = experience_expected(dict(exp_case, contribution=value), conversions['experience_tail'])
    else:
        # 0x40b8b5: no immediate conversion -> one direct conversion of the (zero) running contribution.
        if immediate_draws or conversions['experience_immediate'] or conversions['experience_tail']: raise ValueError('Conversion without a stolen item')
        tail = experience_expected(dict(exp_case, contribution=0), conversions['experience_direct'])
    return dict(hit=value != 0, value=value, hit_bonus=hit['hit_bonus_after'], rolls=rolls, stolen=stolen, inventory=inventory,
                queue=[[stolen['code'], 1]] if stolen else [], contribution=value if stolen else 0, immediate_experience=immediate,
                tail_experience=tail, experience=immediate + tail)



def execute_steal(base, mapped, case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    owner, target, actors, record, table, queue, items_at = [0x10001000 + i * 0x1000 for i in range(7)]
    stack, stop = 0x1001ff00, 0x10000000; victim = actors + 0x1fc
    _, items, _ = sources(); row = steal_row(); low, high = map(int, row['damage'].split(','))
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, actors); put(owner + 0xa4, 0); put(target + 0xa4, 1)
    for off, key in [(0x9c, 'level'), (0x50, 'dex'), (0x54, 'mind'), (0x58, 'con')]: put(actors + off, case[key])
    m.mem_write(actors + 0x196, struct.pack('<H', case['caster_word']))
    put(victim + 0xd8, case['target_hp']); put(victim + 0x9c, case['target_level'])
    for slot, code in enumerate(case['inventory']): put(victim + 0x138 + slot * 4, code)
    put(0x4c1b40, items_at)
    for code in set(case['inventory']):
        if code: put(items_at + 176 * code + 8, 1); put(items_at + 176 * code + 0xac, int(items[code]['get_ratio']))
    put(0x4c1d28, queue); put(0x4c1d2c, 0); put(0x4c1d30, 32)
    put(record + 4, 5); put(record + 0x28, STEAL_ITEM)
    for off, value in [(0x14, low), (0x18, high), (0x1c, case['hit']), (0x2c, int(row['attackpow_ratio']))]: put(record + off, value)
    put(0x4c3920 + 5 * 4, table); put(table + 5 * 4, record)
    put(0x4c1e8c, 1); put(0x4c3044, case['seed']); put(0x4c3040, 0x87654321)
    allowed = [(0x40b8f0, 0x40b90f), (0x40aa80, 0x40b8c4), (0x409870, 0x409890), (0x40a7b0, 0x40aa6b), (0x40a5d0, 0x40a78d),
               (0x40e6c0, 0x40e6da), (0x44f290, 0x44f3ac), (0x436e80, 0x436eca), (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]
    pending = []; draws = []; steps = 0; calls = []; conversion = ['experience_direct']
    def stage_of(caller):
        if 0x40a7b0 <= caller < 0x40aa6b: return 'hit'
        if 0x40a5d0 <= caller < 0x40a78d: return conversion[0]
        return {0x40b5f2: 'steal', 0x40b668: 'immediate'}[caller]
    def guard(_m, at, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= at < hi for lo, hi in allowed): raise ValueError(f'Unreviewed steal callee {at:#x}')
        if pending and pending[-1][0] == at:
            caller, bound = pending.pop(); draws.append(dict(bound=bound, value=m.reg_read(UC_X86_REG_EAX), stage=stage_of(caller)))
        if at == 0x40a5d0:
            # the three 0x40a5d0 call sites: immediate (0x40b674), tail (0x40b866), direct (0x40b8b5)
            conversion[0] = {0x40b679: 'experience_immediate', 0x40b86b: 'experience_tail', 0x40b8ba: 'experience_direct'}[get(m.reg_read(UC_X86_REG_ESP))]
        if at in [0x44f2d0, 0x436e80, 0x40a5d0, 0x40e6c0]: calls.append(hex(at))
        if at == 0x42c780:
            sp = m.reg_read(UC_X86_REG_ESP); pending.append((get(sp), get(sp + 4)))
    m.hook_add(UC_HOOK_CODE, guard)
    m.mem_write(stack, struct.pack('<5I', stop, owner, target, 5, 5)); m.reg_write(UC_X86_REG_ESP, stack)
    m.emu_start(0x40b8f0, stop, count=8192)
    if m.reg_read(UC_X86_REG_EIP) != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4 or pending: raise ValueError('Steal applicator boundary differs')
    inventory = [get(victim + 0x138 + slot * 4) for slot in range(8)]
    queue_rows = [[get(queue + 8 * i), get(queue + 8 * i + 4)] for i in range(get(0x4c1d2c))]
    wanted = steal_expected(case, draws)
    actual = dict(hit_bonus=get(actors + 0xb0), inventory=inventory, queue=queue_rows, contribution=get(0x4c13fc), experience=m.reg_read(UC_X86_REG_EAX))
    if actual != {key: wanted[key] for key in actual}: raise ValueError(f'Steal model differs {case}: {actual} != {wanted}')
    if get(victim + 0xd8) != case['target_hp'] or get(actors + 0x196) & 0xffff != case['caster_word']: raise ValueError('StealItem changed target HP or the caster word')
    return dict(input=case, native=dict(actual, hit=wanted['hit'], value=wanted['value'], rolls=wanted['rolls'], stolen=wanted['stolen'],
                                        immediate_experience=wanted['immediate_experience'], tail_experience=wanted['tail_experience']),
                draws=draws, calls=calls, entry='0x40b8f0', stop_address=hex(stop), normal_return=True, instructions=steps)


# --- packet ---------------------------------------------------------------------------------

def check(packet):
    if packet.get('schema') != 'hsl_native_steal_ratio.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Steal proof identity differs')
    if packet['sources'] != {n: digest((TABLES / n).read_bytes()) for n in SOURCES}: raise ValueError('Steal source bytes differ')
    for key, wanted in [('refresh', refresh_cases()), ('job_up', job_up_cases()), ('steal', steal_cases())]:
        if [row['input'] for row in packet[key]] != wanted: raise ValueError('Steal fixture coverage differs')
    for row in packet['refresh']:
        wanted = refresh_expected(row['input'])
        if len(row['native']) != 2 or any(not r['normal_return'] or r['values'] != wanted or not 0 < r['instructions'] < 12000 for r in row['native']):
            raise ValueError('Steal refresh proof differs')
    for row in packet['job_up']:
        wanted = job_up_expected(row['input'])
        if {k: row['native'][k] for k in wanted} != wanted or row['native']['slot_code'] != 809 or row['native']['job_up_flags'] != hex(row['input']['flag']) or not row['normal_return'] or not 0 < row['instructions'] < 16000:
            raise ValueError('Steal job-up proof differs')
    walked_hole = walked_full = stole = missed = False
    for row in packet['steal']:
        case = row['input']; wanted = steal_expected(case, row['draws']); native = row['native']
        if any(native[k] != wanted[k] for k in ['hit_bonus', 'inventory', 'queue', 'contribution', 'experience', 'hit', 'value', 'rolls', 'stolen', 'immediate_experience', 'tail_experience']):
            raise ValueError('Steal walk native output differs')
        if not row['normal_return'] or row['entry'] != '0x40b8f0' or row['stop_address'] != '0x10000000' or not 0 < row['instructions'] < 8192: raise ValueError('Steal walk boundary differs')
        first_hole = case['inventory'].index(0) if 0 in case['inventory'] else 8
        if wanted['hit'] and len(wanted['rolls']) == first_hole and wanted['stolen'] is None and first_hole < 8 and any(case['inventory'][first_hole:]): walked_hole = True
        if wanted['hit'] and len(wanted['rolls']) == 8: walked_full = True
        stole |= wanted['stolen'] is not None; missed |= not wanted['hit']
    if not (walked_hole and walked_full and stole and missed): raise ValueError('Steal walk coverage differs (hole stop, full walk, success, miss)')
    if [(int(a['address'], 16), len(bytes.fromhex(a['bytes'])), a['meaning']) for a in packet['anchors']] != ANCHORS: raise ValueError('Steal anchors differ')
    actual = hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()
    if ANCHOR_SHA and actual != ANCHOR_SHA: raise ValueError('Steal instruction bytes changed')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    return dict(schema='hsl_native_steal_ratio.v1', exe_sha256=EXE_SHA, native_execution=True, evidence_tier='static-derived',
                sources={n: digest((TABLES / n).read_bytes()) for n in SOURCES},
                refresh=[execute_refresh(base, mapped, c) for c in refresh_cases()],
                job_up=[execute_job_up(base, mapped, c) for c in job_up_cases()],
                steal=[execute_steal(base, mapped, c) for c in steal_cases()],
                anchors=[dict(address=hex(at), bytes=bytes(mapped[at - base:at - base + length]).hex(), meaning=meaning) for at, length, meaning in ANCHORS],
                limits=['Refresh and job-up records are PLAYERS/ITEM-sourced fixtures; the doubled 131 slot and the synthetic 001 words are marked inputs, not source combinations.',
                        'The job-up exchange is checked on +0x194/+0x196, job, slot code and flags only; its other copied fields have their own packet (original_town_job_up.md).',
                        'StealItem runs the whole 0x40aa80 through the 0x40b8f0 wrapper with a preallocated pending queue; the caster is a bare record with the +0x196 word supplied directly.',
                        'Fixed RNG seeds and synthetic inventories; no whole-battle or dispatcher parity.'])


def summary_line(packet: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('STEAL_RATIO_NATIVE_PASS', {k: len(packet[k]) for k in ['refresh', 'job_up', 'steal']}, 'executed_now=', executed_now,
                                           'anchors_sha=', hashlib.sha256(bytes.fromhex(''.join(x['bytes'] for x in packet['anchors']))).hexdigest()))


TASK = ProbeTask('steal_ratio', PACKET, check, execute_packet, summary_line, replaces=())


def tasks() -> list[ProbeTask]:
    return [TASK]
