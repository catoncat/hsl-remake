"""Bounded original world-map and town instructions for collaboration P-027.

No renderer, allocator, file IO, or model-generated substitute is executed.
Ordinary helpers and the supplied-program town VM return normally. UI-bound
branches stop before their first UI call, with the boundary recorded explicitly.

Registry task world_town (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_world_town_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_world_town.json'

ANCHOR_SHA = '5d87afa829113db2ed880acf894cb9343e26240ccd9ace3e18dbd5df96951042'
STOP, STACK = 0x10000000, 0x1001ee00
TOWNS, PROGRAM, EVENT_TABLE = 0x20000000, 0x10001000, 0x10002000
PHASE, PC, DIALOG, SHAPE = 0x10003000, 0x10003004, 0x10003008, 0x1000300c
POINTS, TRACKS = 0x4c4a20, 0x4c43c0
HIDDEN, VISIT, TOWN, GENERAL, BATTLE = 0x08000000, 0x10000000, 0x20000000, 0x40000000, 0x80000000
INITIAL_TREES = {'1': {'0': [1, 2, 3]}, '4': {'0': [4, 5, 6, 7], '7': [8, 12, 13, 14]},
                 '6': {'0': [16, 17, 18, 20], '20': [21, 22, 23]}}
TOWN_QUERIES = [(1,0,0,1), (1,2,0,3), (1,3,0,0), (4,3,0,7), (4,3,1,8),
                (4,3,4,14), (6,3,0,20), (6,3,3,23), (9,0,0,0),
                (99,7,7,0), (4,8,0,0), (4,0,8,0)]
HIDDEN_POINTS = [11, 12, 13, 14, 15, 16, 22, 25, 26, 27, 28, 31, 32, 33, 34, 38, 43]
HIDDEN_TRACKS = [10, 11, 12, 13, 14, 20, 23, 24, 25, 26, 29, 30, 31, 32, 33, 34, 37, 43]
ANCHORS = [
    (0x42c86e, 444, 'New game sets point1 to mode2 and explicit point/track hidden flags after loading the two raw tables.'),
    (0x454ae0, 27, 'Town reset clears100 records of264 bytes then calls the explicit tree initializer.'),
    (0x454a20, 186, 'Initial roots/children are executable town-id/event-id calls, not ownership inferred from TOWNDEF comments.'),
    (0x426c70, 111, 'Point event replacement writes+8; type flags replace other types and clear visited.'),
    (0x4555a5, 149, 'Money check subtracts on success; insufficient branch reaches dialogue before returning the failure phase.'),
    (0x455eb6, 48, 'Completed insufficient-money dialogue returns1 and clears the VM phase.'),
    (0x454dec, 44, 'Secret-man slot index selects a signed16-bit event from the literal source table.'),
    (0x4277ed, 46, 'Starting a route sets walker speed to16.16 value0x20000 before the animation tick.'),
    (0x427ab3, 131, 'Arrival reads mutable point event/type; previously visited battle selects a0..2 level offset.'),
    (0x427b38, 93, 'Arrival either requests an event/level or enters the selected town, then marks visited.'),
    (0x427f0d, 63, 'Point initialization applies the separate OBS visual type to the base frame and sets32-pixel hit bounds.'),
    (0x42c1c0, 32, 'Music getter uses signed track table and current level for argument-1.'),
]


class Native:
    def __init__(self, base: int, mapped: bytearray):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
        self.m = Uc(UC_ARCH_X86, UC_MODE_32)
        self.m.mem_map(base, len(mapped)); self.m.mem_write(base, bytes(mapped))
        self.m.mem_map(0x10000000, 0x20000)
        self.m.mem_map(TOWNS, 0x10000)
        self.put(0x4c1d74, TOWNS)

    def put(self, at: int, value: int) -> None:
        self.m.mem_write(at, struct.pack('<I', value & 0xffffffff))

    def get(self, at: int) -> int:
        return struct.unpack('<I', self.m.mem_read(at, 4))[0]

    def run(self, entry: int, args: list[int], allowed: list[tuple[int, int]],
            stops: tuple[int, ...] = (), count: int = 60000) -> dict:
        from unicorn import UC_HOOK_CODE
        from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX
        steps = 0
        def guard(_m, at, _size, _data):
            nonlocal steps
            if at in stops: self.m.emu_stop(); return
            if not any(lo <= at < hi for lo, hi in allowed):
                raise ValueError(f'Unreviewed world/town instruction {at:#x}, entry={entry:#x}')
            steps += 1
        hook = self.m.hook_add(UC_HOOK_CODE, guard)
        values = [STOP, *args]
        self.m.mem_write(STACK, struct.pack('<' + 'I' * len(values), *[v & 0xffffffff for v in values]))
        self.m.reg_write(UC_X86_REG_ESP, STACK)
        try: self.m.emu_start(entry, STOP, count=count)
        finally: self.m.hook_del(hook)
        end = self.m.reg_read(UC_X86_REG_EIP)
        if end not in (STOP, *stops): raise ValueError(f'Instruction budget exhausted at{end:#x}')
        normal = end == STOP
        if normal and self.m.reg_read(UC_X86_REG_ESP) != STACK + 4:
            raise ValueError('Original helper did not restore its caller stack')
        return dict(entry=hex(entry), stop=hex(end), normal_return=normal, instructions=steps,
                    value=self.m.reg_read(UC_X86_REG_EAX))

    def trees(self) -> dict:
        result = {}
        for town in range(100):
            tree = {'0': []}
            for index in range(8):
                row = struct.unpack('<8I', self.m.mem_read(TOWNS + town * 264 + index * 32, 32))
                if not row[0]: continue
                tree['0'].append(row[0])
                children = [v for v in row[1:] if v]
                if children: tree[str(row[0])] = children
            if tree['0']: result[str(town)] = tree
        return result


def town_initial(base, mapped) -> dict:
    n = Native(base, mapped)
    n.m.mem_write(TOWNS, bytes([0xa5]) * 26400)
    proof = n.run(0x454ae0, [], [(0x454650, 0x454afb)])
    if n.trees() != INITIAL_TREES: raise ValueError('Original initial town trees differ')
    for town in range(100):
        if bytes(n.m.mem_read(TOWNS + town * 264 + 256, 8)) != bytes(8):
            raise ValueError('Town reset leaves entry/exit overrides')
    second = n.run(0x454ae0, [], [(0x454650, 0x454afb)])
    if n.trees() != INITIAL_TREES: raise ValueError('Repeated new-game reset accumulated menus')
    queries = []
    before = bytes(n.m.mem_read(TOWNS,26400))
    for town,root,child,value in TOWN_QUERIES:
        result = n.run(0x454650,[town,root,child],[(0x454650,0x454690)])
        if result['value'] != value or before != bytes(n.m.mem_read(TOWNS,26400)):
            raise ValueError('Town root/child getter changed ownership or memory')
        queries.append(dict(town=town,root=root,child=child,proof=result))
    return dict(trees=n.trees(), empty_towns=[i for i in range(100) if str(i) not in INITIAL_TREES],
                record_bytes=264, root_slots=8, children_per_root=7, entry_exit_zero=True,
                calls=[proof, second], queries=queries)


def map_cases() -> list[dict]:
    rows = [dict(kind=kind, mode=mode, hidden=hidden, requested=requested)
            for kind in ['point_mode', 'track_mode', 'track_force']
            for mode in [0, 1, 2] for hidden in [False, True] for requested in [0, 1, 2]]
    rows += [dict(kind='point_event', previous=previous, event=event, flags=flags)
             for previous in [TOWN | VISIT, GENERAL | HIDDEN | VISIT]
             for event in [-1, 91] for flags in [0, HIDDEN, BATTLE, GENERAL, TOWN]]
    return rows


def map_expected(case) -> dict:
    if case['kind'] != 'point_event':
        value = case['mode']
        if not case['hidden'] and (case['kind'] == 'track_force' or value != 2): value = case['requested']
        return dict(mode=value, flags=HIDDEN if case['hidden'] else 0, event=7)
    flags = case['previous']
    if case['flags']:
        flags &= ~VISIT
        if case['flags'] & (TOWN | GENERAL | BATTLE): flags &= ~(TOWN | GENERAL | BATTLE)
        flags |= case['flags']
    return dict(mode=0, flags=flags, event=7 if case['event'] == -1 else case['event'])


def map_case(base, mapped, case) -> dict:
    n = Native(base, mapped); point = case['kind'].startswith('point')
    record = (POINTS + 7 * 40) if point else (TRACKS + 7 * 16)
    n.put(record, case.get('mode', 0)); n.put(record + 8, 7)
    n.put(record + 4, case.get('previous', HIDDEN if case.get('hidden') else 0))
    entry = dict(point_mode=0x426b70, track_mode=0x426bb0, track_force=0x426bf0, point_event=0x426c70)[case['kind']]
    args = [7, case['event'], case['flags']] if case['kind'] == 'point_event' else [7, case['requested']]
    proof = n.run(entry, args, [(0x426b70, 0x426e40)])
    actual = dict(mode=n.get(record), flags=n.get(record + 4), event=n.get(record + 8))
    if actual != map_expected(case): raise ValueError(f'Map record mismatch {case}: {actual}')
    return dict(input=case, native=actual, proof=proof)


def world_initial(base, mapped, raw) -> dict:
    if len(raw) != 5600: raise ValueError('Unexpected bigmap record bytes')
    n = Native(base, mapped); n.m.mem_write(POINTS, raw[:4000]); n.m.mem_write(TRACKS, raw[4000:])
    proof = n.run(0x42c86e, [], [(0x42c86e, 0x42ca2a), (0x426b70, 0x426e40)], (0x42ca2a,))
    before_points = [list(struct.unpack_from('<10I', raw, i * 40)) for i in range(100)]
    before_tracks = [list(struct.unpack_from('<4I', raw, 4000 + i * 16)) for i in range(100)]
    expected_points = [r[:] for r in before_points]; expected_tracks = [r[:] for r in before_tracks]
    expected_points[1][0] = 2
    for i in HIDDEN_POINTS: expected_points[i][1] |= HIDDEN
    for i in HIDDEN_TRACKS: expected_tracks[i][1] |= HIDDEN
    points = [list(struct.unpack('<10I', n.m.mem_read(POINTS + i * 40, 40))) for i in range(100)]
    tracks = [list(struct.unpack('<4I', n.m.mem_read(TRACKS + i * 16, 16))) for i in range(100)]
    if points != expected_points or tracks != expected_tracks: raise ValueError('Initial map mutation differs')
    return dict(source_sha256=hashlib.sha256(raw).hexdigest(),
                points=[dict(slot=i, source=r, native=points[i]) for i,r in enumerate(before_points) if any(r)],
                tracks=[dict(slot=i, source=r, native=tracks[i]) for i,r in enumerate(before_tracks) if any(r)], proof=proof)


def vm_cases() -> list[dict]:
    rows = [dict(kind='money', code=16, gold=gold, cost=500, phase=0) for gold in [0, 499, 500, 501, 999999999]]
    rows += [dict(kind='money_resume', code=0, gold=499, phase=16 << 16, waiting=waiting) for waiting in [0, 1]]
    rows += [dict(kind='reserved_check', code=code, gold=0, phase=0) for code in [18, 19]]
    rows += [dict(kind='menu', code=10, gold=0, phase=0)]
    rows += [dict(kind='te_exists', code=33, gold=0, phase=0, child=child, event=event)
             for child in [8, 999] for event in [0, 123]]
    rows += [dict(kind='job_deny_resume', code=0, gold=0, phase=100 << 16, event=event, waiting=wait)
             for event in [-1, 123] for wait in [0, 1]]
    rows += [dict(kind='job_deny_start', code=code, gold=0, phase=0, event=event)
             for code in [31,32] for event in [-1,123]]
    return rows


def vm_expected(case) -> dict:
    kind = case['kind']
    if kind == 'money':
        if case['gold'] < case['cost']:
            return dict(gold=case['gold'], cursor=5, phase=0, result=None, dialogue_requested=True)
        return dict(gold=case['gold']-case['cost'], cursor=5, phase=0, result=0, dialogue_requested=False)
    if kind == 'money_resume':
        return dict(gold=case['gold'], cursor=0, phase=case['phase'] if case['waiting'] else 0,
                    result=0 if case['waiting'] else 1, dialogue_requested=bool(case['waiting']))
    if kind in ['reserved_check', 'menu']:
        return dict(gold=0, cursor=1, phase=0, result=2 if kind=='menu' else 0, dialogue_requested=False)
    if kind == 'te_exists':
        found = case['child'] == 8
        return dict(gold=0, cursor=1026 if found and case['event'] else 5, phase=0,
                    result=1 if found and not case['event'] else 0, dialogue_requested=False)
    if kind == 'job_deny_start':
        return dict(gold=0,cursor=0,phase=0,result=None,dialogue_requested=False)
    waiting = case['waiting'] not in [0, 0xffffffff]
    return dict(gold=0, cursor=0 if waiting or case['event'] == -1 else 1026,
                phase=case['phase'] if waiting else 0, result=1 if not waiting and case['event']==-1 else 0,
                dialogue_requested=False)


def vm_case(base, mapped, case) -> dict:
    from unicorn.x86_const import UC_X86_REG_EBP
    n = Native(base, mapped)
    n.run(0x454ae0, [], [(0x454650, 0x454afb)])
    n.put(0x4c1bcc, case['gold']); n.put(PHASE, case['phase']); n.put(PC, PROGRAM)
    n.put(0x4c1d5c, EVENT_TABLE); n.put(EVENT_TABLE + 123 * 4, PROGRAM + 4096)
    n.put(0x4c1d54, case.get('waiting', case.get('event', 0)))
    if case['kind'] == 'job_deny_resume':
        n.put(0x4c1d54, case['event']); n.put(DIALOG, case['waiting'])
    words = [case['code'], 999, 0]
    if case['kind'] == 'money': words = [16, case['cost'], 0xffffffff, 0, 1240, 0]
    elif case['kind'] == 'te_exists': words = [33, 4, 7, case['child'], case['event'], 0]
    elif case['kind'] == 'job_deny_start': words=[case['code'],0,1240,case['event']&0xffffffff,0]
    n.m.mem_write(PROGRAM, struct.pack('<'+'I'*len(words), *words))
    proof = n.run(0x454e20, [4, 0, 0, PHASE, PC, DIALOG, SHAPE],
                  [(0x454e20,0x455ff8), (0x454650,0x454afb), (0x44e0e0,0x44e100),
                   (0x434770,0x4347f0),(0x42caa0,0x42cab5)], (0x4555f4,0x455d39))
    cursor = n.get(PC) if proof['normal_return'] or case['kind']=='job_deny_start' else n.m.reg_read(UC_X86_REG_EBP)
    actual = dict(gold=n.get(0x4c1bcc), cursor=(cursor-PROGRAM)//4, phase=n.get(PHASE),
                  result=proof['value'] if proof['normal_return'] else None, dialogue_requested=n.get(0x4c1d54)==1)
    if actual != vm_expected(case): raise ValueError(f'Town VM mismatch {case}: {actual} != {vm_expected(case)}')
    if case['kind']=='job_deny_start':
        from unicorn.x86_const import UC_X86_REG_ESP
        if n.get(n.m.reg_read(UC_X86_REG_ESP)+0x24)!=100<<16 or n.get(DIALOG)!=1:
            raise ValueError('Ineligible job-up did not request its documented failure phase')
    return dict(input=case, native=actual, proof=proof)


def source_objects(reader, base, mapped) -> dict:
    from hsltools.data.first_skill import blocks
    from hsltools.sources.scripts import parse_evef
    from hsltools.sources.shp import parse_shp
    names = ['obj-049.OBS', 'POINT.H', 'PROCESS.DEF', 'level049.BIN']
    sources = {name: reader.read('@:\\data\\'+name) for name in names}
    rows = blocks(sources['obj-049.OBS'], 'Object')
    source_points, source_tracks = [], []
    placements = {int(r['field_0x04_code_candidate']):
                  [int(r['placement_x_candidate_0x08']), int(r['placement_y_candidate_0x0c'])]
                  for r in parse_evef(sources['level049.BIN'], None)['record_summaries']}
    for row in rows:
        process = row.get('obj_Process_Code')
        if process not in ['defProcBigMapPoint', 'defProcBigMapTrack', 'defProcBigMapStatusBar']: continue
        code = int(row['obj_code'])
        item = dict(object_code=code, process=process, shape=row['obj_Shape_Name'],
                    position=placements.get(code), source_fields=row)
        if process == 'defProcBigMapPoint':
            item['point_id'] = int(row['obj_Data9'].removeprefix('bmPoint'))
            item['visual_type'] = dict(bmPointBattle=0, bmPointGeneral=1, bmPointTown=2)[row['obj_Data4']]
            source_points.append(item)
        elif process == 'defProcBigMapTrack':
            raw = reader.read('@:\\'+row['obj_Shape_Name'])
            shp = parse_shp(raw)
            item.update(track_id=int(row['obj_Data9'].removeprefix('bmTrack')),
                        width=shp['width'], height=shp['height'],
                        draw_origin=list(struct.unpack_from('<ii',raw,28)), shape_sha256=hashlib.sha256(raw).hexdigest())
            source_tracks.append(item)
        else: status_bar = item
    definitions = {name:int(value) for name,value in re.findall(r'^(\w+)\s*=\s*(\d+)',sources['PROCESS.DEF'].decode('cp950'),re.M)}
    callbacks = {name:dict(index=definitions[name], address=hex(struct.unpack_from('<I',mapped,0x477c2c-base+definitions[name]*4)[0]))
                 for name in ['defProcBigMapPoint','defProcBigMapTrack','defProcBigMapWalker','defProcBigMapStatusBar']}
    from hsltools.sources.tables import parse_table
    text_source = reader.read('@:\\data\\RESOURCE.TXT')
    label = parse_table(text_source)['360']
    if label != '完成度：': raise ValueError('Status-bar source label differs')
    return dict(sources={k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},
                callbacks=callbacks, points=source_points, tracks=source_tracks, status_bar=status_bar,
                status_label=dict(resource_id=360, text=label, source_sha256=hashlib.sha256(text_source).hexdigest()),
                evidence_tier='resource-derived', native_execution=False)


def visual_cases() -> list[dict]:
    return ([dict(kind='point', visual=visual, mode=mode) for visual in [0,1,2] for mode in [0,1,2]] +
            [dict(kind='track', mode=mode) for mode in [0,1,2]] +
            [dict(kind='status_bar', camera=xy) for xy in [[0,0],[120,80],[-30,-20]]] +
            [dict(kind='progress', visible=visible, hidden=hidden) for visible,hidden in [(0,0),(1,0),(1,1),(5,1),(8,0)]] +
            [dict(kind='music', level=level) for level in [-1,1,49,50,100]] +
            [dict(kind='play_time', seconds=seconds) for seconds in [0,59,60,3601,7234]] +
            [dict(kind='speed'), dict(kind='status_text')])


def visual_case(base, mapped, case) -> dict:
    from unicorn.x86_const import UC_X86_REG_ESI
    n=Native(base,mapped);obj=0x10004000;proofs=[];kind=case['kind']
    def word(at): return struct.unpack('<H',n.m.mem_read(at,2))[0]
    if kind=='point':
        n.put(obj+0xac,2); n.put(obj+0x98,case['visual']);n.put(obj+0x32,500)
        n.put(POINTS+80,case['mode']);n.put(0x4c1ab8,999)
        proofs.append(n.run(0x427df0,[obj,0x20000000],[(0x427df0,0x4280c4),(0x426b70,0x426e40)]))
        bounds=[struct.unpack('<i',n.m.mem_read(obj+off,4))[0] for off in [0x68,0x6c,0x70,0x74]]
        proofs.append(n.run(0x427df0,[obj,0],[(0x427df0,0x4280c4),(0x426b70,0x426e40)]))
        actual=dict(bounds=bounds, frame=word(obj+0x30), base_frame=word(obj+0x32), point_mode=n.get(POINTS+80))
        expected=dict(bounds=[-16,-16,16,16],frame=65535 if case['mode']==0 else 500+case['visual'],
                      base_frame=500+case['visual'],point_mode=0 if case['mode']==0 else 2)
    elif kind=='track':
        n.put(obj+0xac,7);n.put(obj+0x32,500);n.put(obj+4,200);n.put(obj+8,100)
        n.put(TRACKS+7*16,case['mode']);n.put(TRACKS+7*16+8,2);n.put(TRACKS+7*16+12,3)
        header=0x10006000;n.put(0x4abf28+500*4,header)
        for offset,value in [(4,9),(8,12),(12,-3),(16,-4)]:n.put(header+offset,value)
        owner=0x10007000;n.put(0x4c1abc,owner);n.put(owner+0x88,1)
        for _ in range(17 if case['mode']==1 else 1):
            proofs.append(n.run(0x4280d0,[obj,0],[(0x4280d0,0x4282c0),(0x426b70,0x426e40),(0x4606a9,0x4606f3)]))
        actual=dict(frame=word(obj+0x30), mode=n.get(TRACKS+7*16), phase=n.get(obj+0x8c),
                    endpoint_modes=[n.get(POINTS+80),n.get(POINTS+120)], pending=n.get(owner+0x88),
                    rectangle=[n.get(obj+off) for off in [0x10,0x14,0x18,0x1c]])
        expected=dict(frame=65535 if case['mode']==0 else 500,mode=0 if case['mode']==0 else 2,phase=0,
                      endpoint_modes=[1,1] if case['mode']==1 else [0,0],pending=0 if case['mode']==1 else 1,
                      rectangle=[185,85,215,115] if case['mode']==1 else [0,0,0,0])
    elif kind=='status_bar':
        x,y=case['camera'];n.put(0x4c091c,x);n.put(0x4c0920,y)
        proofs.append(n.run(0x427230,[obj,0x20000000],[(0x427230,0x42741d)]))
        actual=dict(position=[struct.unpack('<i',n.m.mem_read(obj+off,4))[0] for off in [4,8]])
        expected=dict(position=[x,y+412])
    elif kind=='progress':
        # Denominator is all named points minus one; hidden points still count.
        for i in range(1,9):n.put(POINTS+i*40+12,300+i)
        for i in range(1,case['visible']+1):n.put(POINTS+i*40,2)
        for i in range(1,case['hidden']+1):n.put(POINTS+i*40+4,HIDDEN)
        proof=n.run(0x427200,[],[(0x427200,0x42722e),(0x426d00,0x426e40)]);proofs.append(proof)
        actual=dict(percent=proof['value']);expected=dict(percent=min(100,(case['visible']-case['hidden'])*100//7))
    elif kind=='music':
        n.put(0x4c1bb8,49)
        proof=n.run(0x42c1c0,[case['level']],[(0x42c1c0,0x42c1e0)]);proofs.append(proof)
        index=49 if case['level']==-1 else case['level']
        expected=dict(track=struct.unpack_from('<h',mapped,0x477b44-base+index*2)[0] if index<100 else -1)
        value=proof['value'];actual=dict(track=value if value<0x80000000 else value-0x100000000)
    elif kind=='play_time':
        n.put(0x4c1bc0,case['seconds'])
        proofs.append(n.run(0x42d090,[obj,0],[(0x42d090,0x42d320),(0x45b6de,0x45b795)]))
        actual=dict(text=bytes(n.m.mem_read(obj,60)).split(b'\0')[0].decode('ascii'))
        s=case['seconds'];expected=dict(text=f'{s//3600}:{s//60%60:02}:{s%60:02}')
    elif kind=='status_text':
        # Build the original completion label and percentage up to the first
        # text renderer. Do not stub rendering or claim a completed draw call.
        table, label = 0x10008000, 0x10009000
        n.put(0x4c1b3c,table);n.put(table+360*4,label)
        n.m.mem_write(label,'完成度：'.encode('cp950')+b'\0')
        for i in range(1,9): n.put(POINTS+i*40+12,300+i)
        for i in range(1,4): n.put(POINTS+i*40,2)
        proofs.append(n.run(0x427230,[obj,0xffffffff],[(0x427230,0x427309),(0x4477b0,0x4477be),
                             (0x427200,0x42722e),(0x426b70,0x426e40),(0x45b6de,0x45b795)],(0x427309,)))
        actual=dict(text=bytes(n.m.mem_read(0x4c1e98,80)).split(b'\0')[0].decode('cp950'))
        expected=dict(text='完成度： 42%')
    else:
        n.m.reg_write(UC_X86_REG_ESI,obj)
        proofs.append(n.run(0x4277ed,[],[(0x4277ed,0x427816)],(0x427816,)))
        actual=dict(speed_fixed=n.get(obj+0x88), phase=word(obj+0x8c));expected=dict(speed_fixed=0x20000,phase=1)
    if actual!=expected:raise ValueError(f'Native visual contract differs {case}: {actual} != {expected}')
    return dict(input=case,native=actual,proofs=proofs)


def arrival_cases() -> list[dict]:
    return [dict(event=event,flags=flags,selected=selected,ratio=ratio,seed=seed)
            for event,flags,selected,ratio in [(0,BATTLE,True,10),(51,BATTLE,True,10),(501,BATTLE|VISIT,True,10),
             (61,GENERAL,False,10),(501,GENERAL|VISIT,True,0),(501,GENERAL|VISIT,True,100),
             (4,TOWN,True,10),(4,TOWN,False,10),(61,GENERAL|BATTLE,True,10)] for seed in [1,7,29]]


def arrival_case(base,mapped,case) -> dict:
    from unicorn.x86_const import UC_X86_REG_EDX,UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_ESP
    n=Native(base,mapped);obj=0x10004000;dest=4
    n.put(POINTS+dest*40+8,case['event']);n.put(POINTS+dest*40+4,case['flags'])
    n.put(0x4c1ab8,dest if case['selected'] else 9);n.put(0x4c27e0+dest*2,case['ratio'])
    n.put(0x4c1e8c,1);n.put(0x4795d4,case['seed']);n.put(0x4795d8,0x87654321)
    n.put(obj+0x8c,6);n.put(STACK+0x18,dest)
    n.m.reg_write(UC_X86_REG_EDX,dest);n.m.reg_write(UC_X86_REG_ESI,obj);n.m.reg_write(UC_X86_REG_EDI,0)
    proof=n.run(0x427ab3,[],[(0x427ab3,0x427b95),(0x426b70,0x426e40),(0x4545a0,0x4545c0),(0x458c10,0x458cb3)],(0x427b3e,0x427b95))
    event=None
    if proof['stop']=='0x427b3e':event=n.get(n.m.reg_read(UC_X86_REG_ESP)+4)
    actual=dict(requested_level=event,town=n.get(0x4c59c4),phase=n.get(obj+0x8c)&65535,flags=n.get(POINTS+dest*40+4))
    validate_arrival(case,actual)
    return dict(input=case,native=actual,proof=proof)


def validate_arrival(case,actual):
    flags=case['flags'];event=case['event']
    if not event or flags==GENERAL|VISIT and case['ratio']==0 or flags==TOWN and not case['selected']:
        expected=dict(requested_level=None,town=0,phase=6,flags=flags)
    elif flags==TOWN:
        expected=dict(requested_level=None,town=event,phase=15,flags=flags|VISIT)
    else:
        chosen=actual['requested_level']
        if chosen not in range(event,event+(3 if flags&VISIT else 1)):raise ValueError('Arrival level offset differs')
        expected=dict(requested_level=chosen,town=0,phase=6,flags=flags)
    if actual!=expected:raise ValueError(f'Arrival branch differs {case}: {actual}')


def secret_cases() -> list[dict]:
    return [dict(index=index,force=force,cache=cache,ratio=ratio) for index in [0,3,8]
            for force,cache,ratio in [(0,0,1),(0,0,100),(0,-1,100),(0,113,100),(1,-1,1),(1,0,100),(0,0,'equal_draw')]]


def secret_case(base,mapped,case) -> dict:
    n=Native(base,mapped);n.run(0x454ae0,[],[(0x454650,0x454afb)])
    n.put(0x4c1d70,case['cache']);n.put(0x4c1bd4,case['index'])
    n.put(0x4c1e8c,1);n.put(0x4795d4,7);n.put(0x4795d8,0x87654321)
    draw=n.run(0x458c80,[100],[(0x458c10,0x458cb3)])
    n.put(0x4795d4,7);n.put(0x4795d8,0x87654321)
    n.put(0x4c1bd0,draw['value']+1 if case['ratio']=='equal_draw' else case['ratio'])
    proof=n.run(0x454db0,[4,7,case['force']],[(0x454db0,0x454e19),(0x454650,0x454afb),(0x458c10,0x458cb3)])
    value=n.get(0x4c1d70);value=value if value<0x80000000 else value-0x100000000
    actual=dict(cache=value,children=n.trees()['4']['7'])
    expected=secret_expected(case)
    if actual!=expected:raise ValueError(f'Secret man state differs {case}: {actual}')
    return dict(input=case,native=actual,proof=proof,first_draw=draw)


def secret_expected(case) -> dict:
    event=[123,113,114,115,116,117,118,119,120][case['index']]
    success=bool(case['force']) or case['cache']==0 and case['ratio']==100
    cache=event if success else -1 if case['cache']==0 else case['cache']
    return dict(cache=cache,children=[8,12,13,14]+([event] if success else []))


def item_cases() -> list[dict]:
    return [dict(location=location,remove=remove,event=event) for location in ['absent','store1','store2','actor']
            for remove in [0,1] for event in [0,123]]


def item_case(base,mapped,case) -> dict:
    n=Native(base,mapped);item=241;actor_table=0x10008000
    n.put(0x4c1bc8,actor_table)
    for pointer,count,capacity,store in [(0x4c1d10,0x4c1d14,0x4c1d18,0x10005000),(0x4c1d1c,0x4c1d20,0x4c1d24,0x10006000)]:
        n.put(pointer,store);n.put(capacity,8)
        if case['location']==('store1' if pointer==0x4c1d10 else 'store2'):
            n.put(count,1);n.put(store,item);n.put(store+4,2)
    if case['location']=='actor':
        n.put(0x4c4360,1);n.put(actor_table+0x1fc+0x138,item);n.put(actor_table+0x1fc+0x13c,211)
    n.put(PHASE,0);n.put(PC,PROGRAM);n.put(0x4c1d5c,EVENT_TABLE);n.put(EVENT_TABLE+123*4,PROGRAM+4096)
    n.m.mem_write(PROGRAM,struct.pack('<5I',29,item,case['event'],case['remove'],0))
    proof=n.run(0x454e20,[4,0,0,PHASE,PC,DIALOG,SHAPE],
                [(0x454e20,0x455ff8),(0x454cd0,0x454db0),(0x44eef0,0x44f210),
                 (0x42caa0,0x42cab5),(0x436ef0,0x436f50),(0x44e0e0,0x44e100)])
    actual=dict(cursor=(n.get(PC)-PROGRAM)//4,result=proof['value'],
                store_counts=[n.get(0x10005004),n.get(0x10006004)],
                inventory=[n.get(actor_table+0x1fc+0x138+i*4) for i in range(2)])
    if actual!=item_expected(case):raise ValueError(f'Item predicate mismatch {case}: {actual}')
    return dict(input=case,native=actual,proof=proof)


def item_expected(case) -> dict:
    found=case['location']!='absent'
    return dict(cursor=1026 if found and case['event'] else 4,result=0,
                store_counts=[2-case['remove'] if case['location']==loc else 0 for loc in ['store1','store2']],
                inventory=([211,0] if case['remove'] else [241,211]) if case['location']=='actor' else [0,0])


def visual_expected(case) -> dict:
    kind=case['kind']
    if kind=='point':
        return dict(bounds=[-16,-16,16,16],frame=65535 if case['mode']==0 else 500+case['visual'],
                    base_frame=500+case['visual'],point_mode=0 if case['mode']==0 else 2)
    if kind=='track':
        return dict(frame=65535 if case['mode']==0 else 500,mode=0 if case['mode']==0 else 2,phase=0,
                    endpoint_modes=[1,1] if case['mode']==1 else [0,0],pending=0 if case['mode']==1 else 1,
                    rectangle=[185,85,215,115] if case['mode']==1 else [0,0,0,0])
    if kind=='status_bar':return dict(position=[case['camera'][0],case['camera'][1]+412])
    if kind=='progress':return dict(percent=min(100,(case['visible']-case['hidden'])*100//7))
    if kind=='music':return dict(track={-1:6,1:13,49:6,50:2,100:-1}[case['level']])
    if kind=='play_time':
        s=case['seconds'];return dict(text=f'{s//3600}:{s//60%60:02}:{s%60:02}')
    if kind=='status_text':return dict(text='完成度： 42%')
    return dict(speed_fixed=0x20000,phase=1)


def validate(packet: dict) -> None:
    if packet.get('schema') != 'hsl_world_town_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing original world/town identity')
    if packet['initial_towns']['trees'] != INITIAL_TREES or not packet['initial_towns']['entry_exit_zero']:
        raise ValueError('Town initialization coverage differs')
    queries = packet['initial_towns']['queries']
    if [(r['town'],r['root'],r['child'],r['proof']['value']) for r in queries] != TOWN_QUERIES:
        raise ValueError('Town root/child selection differs')
    if any(r['proof']['entry']!='0x454650' or not r['proof']['normal_return'] for r in queries):
        raise ValueError('Town getter did not return normally')
    if [r['input'] for r in packet['map_cases']] != map_cases() or [r['input'] for r in packet['vm_cases']] != vm_cases():
        raise ValueError('World/town case coverage differs')
    for row in packet['map_cases']:
        if row['native'] != map_expected(row['input']): raise ValueError('Map result differs')
    for row in packet['vm_cases']:
        if row['native'] != vm_expected(row['input']): raise ValueError('VM result differs')
    for row in packet['initial_map']['points']:
        wanted = row['source'][:]
        if row['slot'] == 1: wanted[0] = 2
        if row['slot'] in HIDDEN_POINTS: wanted[1] |= HIDDEN
        if row['native'] != wanted: raise ValueError('New-game point flags differ')
    for row in packet['initial_map']['tracks']:
        wanted = row['source'][:]
        if row['slot'] in HIDDEN_TRACKS: wanted[1] |= HIDDEN
        if row['native'] != wanted: raise ValueError('New-game track flags differ')
    proofs = [*packet['initial_towns']['calls'], *[r['proof'] for r in queries], packet['initial_map']['proof'],
              *[r['proof'] for r in packet['map_cases']], *[r['proof'] for r in packet['vm_cases']]]
    for proof in proofs:
        if not 0 < proof['instructions'] < 60000 or proof['normal_return'] != (proof['stop'] == hex(STOP)):
            raise ValueError('Native return/budget differs')
        if proof['stop'] not in [hex(STOP), '0x42ca2a', '0x4555f4','0x455d39']: raise ValueError('Undeclared native stop')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']] != ANCHORS:
        raise ValueError('World/town instruction anchor coverage differs')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!=ANCHOR_SHA:
        raise ValueError('World/town original instruction bytes differ')
    if [r['input'] for r in packet['visual_cases']] != visual_cases() or [r['input'] for r in packet['arrival_cases']] != arrival_cases() or [r['input'] for r in packet['secret_cases']] != secret_cases():
        raise ValueError('World visual/arrival/secret coverage differs')
    for row in packet['visual_cases']:
        if row['native']!=visual_expected(row['input']):raise ValueError('World presentation result differs')
    for row in packet['arrival_cases']: validate_arrival(row['input'],row['native'])
    for row in packet['secret_cases']:
        if row['native']!=secret_expected(row['input']):raise ValueError('Secret-man result differs')
        if not row['first_draw']['normal_return'] or not 0<=row['first_draw']['value']<100:
            raise ValueError('Missing original secret-man boundary draw')
    if [r['input'] for r in packet['item_cases']]!=item_cases():raise ValueError('Item predicate coverage differs')
    for row in packet['item_cases']:
        if row['native']!=item_expected(row['input']):raise ValueError('Item predicate result differs')
    proofs=[*[p for r in packet['visual_cases'] for p in r['proofs']],
            *[r['proof'] for section in ['item_cases','arrival_cases','secret_cases'] for r in packet[section]]]
    for proof in proofs:
        if not 0 < proof['instructions'] < 60000 or proof['normal_return'] != (proof['stop']==hex(STOP)):
            raise ValueError('Presentation/predicate return boundary differs')
        if proof['stop'] not in [hex(STOP),'0x427816','0x427b3e','0x427b95','0x427309']:raise ValueError('Undeclared presentation stop')
    objects=packet['object_sources']
    if objects['status_label']['resource_id']!=360 or objects['status_label']['text']!='完成度：':
        raise ValueError('Original status-bar label differs')
    if objects['sources']!={'obj-049.OBS':'e18221a22f8478d1ceeedd17be0c1c7f3154f8cefd50bf210a5591b7e31c5d12',
       'POINT.H':'0ea98ce4a51129602556ad657d085b808091053a0972cbfe741c94e5dda50993',
       'PROCESS.DEF':'e0d295d2c1fd7c0781f1e9dd7d3b42127e192d479918b392e1d067aa9765c8fa',
       'level049.BIN':'720dd7a0ec9c92ea43b2c8e40b54f293a1176d739b4b567682fe7c1da02cb6b4'}:
        raise ValueError('World object source identity differs')
    if [r['point_id'] for r in objects['points']]!=list(range(1,46)) or [r['track_id'] for r in objects['tracks']]!=list(range(1,45)):
        raise ValueError('World object source coverage differs')
    if packet['initial_map']['source_sha256']!='6d9957c01fee5d9c48482c0f98d8dfded23d647c75b5d483fe37bf62c0a3a75b':
        raise ValueError('Bigmap source identity differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    sys.path.insert(0, str(ROOT))
    from hsltools.data.world_map import PakReader
    reader=PakReader(exe.parent)
    raw=reader.read('@:\\data\\bigmap.dat')
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_world_town_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                initial_towns=town_initial(base,mapped), initial_map=world_initial(base,mapped,raw),
                map_cases=[map_case(base,mapped,c) for c in map_cases()],
                vm_cases=[vm_case(base,mapped,c) for c in vm_cases()],
                object_sources=source_objects(reader,base,mapped),
                visual_cases=[visual_case(base,mapped,c) for c in visual_cases()],
                arrival_cases=[arrival_case(base,mapped,c) for c in arrival_cases()],
                secret_cases=[secret_case(base,mapped,c) for c in secret_cases()],
                item_cases=[item_case(base,mapped,c) for c in item_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Original instruction execution with synthetic pointer/phase inputs, not a Wine gameplay run.',
                        'Insufficient money stops before creating dialogue; its completed phase is checked separately.',
                        'Default menu initialization does not infer later script-modified menus or full world presentation.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'WORLD_TOWN_NATIVE_PASS maps={len(packet["map_cases"])} vm={len(packet["vm_cases"])} visuals={len(packet["visual_cases"])} arrivals={len(packet["arrival_cases"])} secrets={len(packet["secret_cases"])} items={len(packet["item_cases"])} initialized_towns=100 executed_now={executed_now}'


TASK = ProbeTask('world_town', PACKET, validate, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
