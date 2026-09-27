"""Import current chapter battle attack cut-ins from ANIMAL.TXT and original SHP frames.

Registry task combat_animation (family assets): outputs manifest.json, background.png and the
per-actor frame PNG directories under content/imported/hsl/chapter01/combat_animation/. The
program source ANIMAL.TXT in the same directory is the animal_programs task's import (read here,
never written; a PAK whose member differs from the tracked copy is refused). Bodies moved verbatim
from the former hsl_combat_animation.py.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview

ROOT = Path('content/imported/hsl/chapter01/combat_animation')
ACTORS = ['001', '021', '023', '024', '025', '026', '039', '002', '004', '006', '028', '036', '003', '061', '062',
          '005', '007', '008', '009', '027', '030', '031', '032', '033', '034', '035',
          '037', '038', '041', '043', '044', '045', '048', '049', '050', '051', '052',
          '053', '054', '055', '056', '057', '058', '059', '060', '064', '065',
          # Level-37 guardians 066 (ANIMAL P050 strip) / 067 (P067) and the level-80 怨念體 068.
          '066', '067', '068',
          # Up-title (job-up target) rows SID_PLAYER9-19 -> P010-P020. 018 (SID_PLAYER17) has cut-in
          # frames in ANIMAL.TXT/PAK but no SHAPEDEF walk row (commented out in the original), so a
          # 009->018 member keeps its base 009 presentation; it is deliberately not imported here.
          '010', '011', '012', '013', '014', '015', '016', '017', '019', '020',
          # Winged warriors: 022 (level-44/45 script reinforcement) and 069 (level-52 roster); both
          # ANIMAL blocks declare the P022 strip, PATT022 flash and one strike program.
          '022', '069']
UP_TITLE_ACTORS = ['010', '011', '012', '013', '014', '015', '016', '017', '019', '020']
# Actors whose ANIMAL `s_shape` special (絶技) strip is imported as `special_frames`: every combat
# row whose ANIMAL block declares s_shape／s_number, except 002 (its P002_201 strip is the moon-dance
# import, hsltools.data.moon_dance) and 018 (no combat row, see ACTORS). Base rows 001 (氣刃斬 cast
# panels) and 003 (毒魔箭 portrait/inset panels), the base 3/4-panel strips 004/006/007/009, the
# up-title 3-panel strips and the monsters 053 (declares 009's P009_201 strip, copied like its
# P009_101 magic strip)／054／055／057 are consumed by BattleCombatCutin.special_frames (art row
# first, then base row). Every other actor row carries `special_frames: []` — the declared "no strip
# → the cut-in shows the caster's standing frame" contract: their ANIMAL blocks declare no s_shape
# (056 included: no s_shape／s_action field and no ANIMAL\P056_2xx member in hsl.pak,
# negative-evidence); the runtime reports a row without the key.
SPECIAL_FRAME_ACTORS = ['001', '003', '004', '006', '007', '009', '010', '012', '013', '016', '017', '019', '020',
                        '053', '054', '055', '057']
SPECIAL_FRAMES_POLICY = ('Every actor carries special_frames: the imported ANIMAL s_shape strip (001/003 base panels, '
                         '004/006/007/009 base 3/4-panel strips, 010/012/013/016/017/019/020 up-title 3-panel strips, '
                         '053 (P009_201)/054/055/057 monster strips) or [] meaning no strip in this manifest (the ANIMAL block declares none; 002\'s is the moon-dance import) and '
                         'the 絶技 cut-in shows the standing frame; a row without the key is a data error.')
PROGRAMS = Path('content/generated/hsl/animation/animal_programs.json')
# The ANIMAL `action` opcodes compile_action / compile_mobile_action bind into the manifest
# `dispatch` the cut-in plays (every opcode any live action program uses; an action program
# with another opcode is refused, not skipped). field_coverage cites this set as the consumer
# of the action channel; check() confirms it equals the opcodes the bound dispatches carry.
ACTION_OPCODES = ('aniDelay', 'aniSetShape', 'aniInsertAttackFlash', 'aniSetSubSpeed', 'aniSetAddSpeed',
                  'aniSetStopSpeed', 'aniSetXYDisp', 'aniSetZoom')
# The ANIMAL `s_action` cast lead (the same four opcodes as every live m_action／s_action):
# bind_programs passes the program through as `cast_program` for every actor that declares
# one; game/battle/scene/AnimalCastLead.gd (CAST_OPCODES, the same spelling) plays it
# when the actor's s_shape strip is imported (`special_frames`), else the cut-in keeps the
# standing caster — a per-actor gap of art, listed in `cast_program_policy`.
CAST_OPCODES = ('aniSetXYDisp', 'aniShadowBG', 'aniMoveToCenter', 'aniInsertCastObject')
CAST_PROGRAM_POLICY = ('cast_program = the actor\'s ANIMAL s_action in source order ([] = none declared); AnimalCastLead plays it '
                       'when special_frames is non-empty, else the 絶技 cut-in shows the standing caster for the attack script.')
# Actors whose ANIMAL `m_shape` magic-cast strip (P0xx_101…) is imported as `magic_frames` and
# whose `m_action` is bound as `magic_cast_program`: the 17 of the 18 m_action rows that have a
# combat row here (018 has no SHAPEDEF walk row, see ACTORS). 053 shares 009's P009_101 strip. Every other row carries `magic_frames: []`
# and the map magic presenter keeps its Cast_Star stand-in lead (`magic_cast_program_policy`).
MAGIC_FRAME_ACTORS = ['002', '005', '006', '009', '010', '011', '014', '015', '019', '020', '025', '053', '056', '058', '059', '060', '068']
# The ordinary cut-in's opening shape: obj_Animal_Attack (OBJ-ALL 154) declares MAGIC\BALL001.SHP
# as its default shape and defProcAnimalAttack 0x401c20 phase 100 draws that shape (object +0x86,
# copied from +0x32 at init) zooming additively from 1/16 to 12.25 over 24 ticks, then level-blended
# at 18.0 fading 16 -> 1 over 32 ticks (docs/evidence_packets/static_reverse/original_tick_counts.md §7).
# BattleCombatCutin reads `opening` for the first shot of every exchange.
OPENING_MEMBER = 'MAGIC\\BALL001.SHP'
OPENING_NOTE = ('obj_Animal_Attack default shape; 0x401c20 phase 100 draws it at the screen centre: 24 additive zoom draws '
                '(mode 0xc000000, 0x401060 ramp 0x1000..0xc4000) then 32 level-blend draws (mode 0x28000000, zoom 0x120000, '
                'level 16..1 every 2 ticks). static-derived, docs/evidence_packets/static_reverse/original_tick_counts.md §7.')
MAGIC_FRAMES_POLICY = ('Every actor carries magic_frames: the imported ANIMAL m_shape strip (002/005/006/009/053 base rows, '
                       '010/011/014/015/019/020 up-title rows, 025/056/058/059/060/068 monsters) or [] meaning no strip is imported '
                       '(018 has no combat row, the rest declare no m_action) and the magic cut-in keeps the '
                       'Cast_Star stand-in lead; a row without the key is a data error.')
MAGIC_CAST_PROGRAM_POLICY = ('magic_cast_program = the actor\'s ANIMAL m_action in source order ([] = none declared); AnimalCastLead plays it '
                             'when magic_frames is non-empty, else the map magic presenter rings the caster with Cast_Star for CAST_LEAD_IN.')
# Reviewed decoded standing/strike art. k_action is NOT sprite orientation.
SPRITE_FACING = {'001': 'left', '021': 'right', '023': 'left', '024': 'left', '025': 'right', '026': 'right', '039': 'front', '002':'left', '004':'left', '006':'left', '028':'right', '036':'right', '003':'left', '061':'left', '062':'left',
                 '005': 'front',  # visual review of frames 0-5
                 '007': 'front',  # visual review of frames 0-4
                 '008': 'front',  # visual review of frames 0-4
                 '009': 'front',  # visual review of frames 0-5
                 '027': 'front',  # visual review of frames 0-4
                 '030': 'front',  # visual review of frames 0-4
                 '031': 'right',  # visual review of frames 0-4
                 '032': 'front',  # visual review of frames 0-4
                 '033': 'front',  # visual review of frames 0-4
                 '034': 'left',   # visual review of frames 0-4
                 '035': 'front',  # visual review of frames 0-5
                 '037': 'right',  # visual review of frames 0-4
                 '038': 'right',  # visual review of frames 0-2
                 '041': 'front',  # visual review of frames 0-4
                 '043': 'left',   # visual review of frames 0-2
                 '044': 'right',  # visual review of frames 0-2
                 '045': 'right',  # visual review of frames 0-3
                 '048': 'right',  # visual review of frames 0-4
                 '049': 'front',  # visual review of frames 0-5
                 '050': 'right',  # visual review of frames 0-5
                 '051': 'right',  # visual review of frames 0-4
                 '052': 'left',   # visual review of frames 0-4
                 '053': 'left',   # visual review of frames 0-4
                 '054': 'left',   # visual review of frames 0-4
                 '055': 'front',  # visual review of frames 0-3
                 '056': 'front',  # visual review of frames 0-4
                 '057': 'front',  # visual review of frames 0-4
                 '058': 'front',  # visual review of frames 0-2
                 '059': 'front',  # visual review of frames 0-4
                 '060': 'front',  # visual review of frames 0-4
                 '064': 'right',  # visual review of frames 0-1
                 '065': 'left',   # visual review of frames 0-4
                 # 066 cuts in with 050's P050 strip; 067 (a one-frame gem light) and 068 are unreviewed.
                 '066': 'right', '067': 'front', '068': 'front',
                 # Up-title rows: provisional until the contact sheet is reviewed (ignored/g/).
                 '010': 'left', '011': 'left', '012': 'left', '013': 'left', '014': 'left',
                 '015': 'front', '016': 'left', '017': 'left', '019': 'left', '020': 'left',
                 # P022 strip (022 and 069): head and torso face the viewer in frames 0-4 (reviewed).
                 '022': 'front', '069': 'front',
}


REVIEWED_FACING_EVIDENCE = 'Visual review of decoded original standing/strike artwork; do not interpret k_action as facing.'
# The 32 actors added in the second-chapter/finale batch were classified without a working vision
# tool; sprite_facing is unconsumed metadata for them until reviewed. Keep the claim honest.
PROVISIONAL_FACING_ACTORS = {'005', '007', '008', '009', '027', '030', '031', '032', '033', '034', '035', '037', '038', '041', '043', '044', '045',
                             '048', '049', '050', '051', '052', '053', '054', '055', '056', '057', '058', '059', '060', '064', '065', '066', '067', '068',
                             '010', '011', '012', '013', '014', '015', '016', '017', '019', '020'}
PROVISIONAL_FACING_EVIDENCE = ('provisional: sprite_facing was not confirmed by a visual review (vision CLI unavailable when imported); '
                               'the runtime does not consume sprite_facing. Replacement evidence: a reviewed contact sheet of the decoded frames.')


def facing_evidence(actor):
    return PROVISIONAL_FACING_EVIDENCE if actor in PROVISIONAL_FACING_ACTORS else REVIEWED_FACING_EVIDENCE


PLAYER_ACTOR_TOKENS = {f'{index + 1:03d}': f'SID_PLAYER{index}' for index in range(20)}


def actor_token(actor):
    return PLAYER_ACTOR_TOKENS.get(actor, 'SID_ENEMY' + actor)


def source_timeline(program):
    frame, timeline = 0, []
    for instruction in program:
        if instruction['op'] == 'aniSetShape':
            frame = instruction['args'][0]
        elif instruction['op'] == 'aniDelay':
            timeline.append({'frame': frame, 'ticks': instruction['args'][0]})
    return timeline


def is_receiver_only(program):
    return not any(instruction['op'] == 'aniInsertAttackFlash' for instruction in program)


def derive_hurt_frame(program, frame_count):
    poses = [instruction['args'][0] for instruction in program if instruction['op'] == 'aniSetShape']
    return min((poses[-1] + 1) if poses else frame_count - 1, frame_count - 1)


def hurt_frame_evidence(program, frame_count):
    poses = [instruction['args'][0] for instruction in program if instruction['op'] == 'aniSetShape']
    if poses:
        return 'Derived from the last action aniSetShape reaction slot + 1, clamped to number - 1.'
    return 'No action pose exists; derived from the final source frame number - 1.'


def compile_action(program, frame_count):
    """Bind the three supported ordinary opcodes, preserving dispatch boundaries.

    Delay setup yields, then at least one waiting call yields. SetShape yields;
    InsertAttackFlash continues to the following instruction in the SAME call.
    This models the documented dispatcher front segment, not its common tail,
    native wall-clock frequency, source-loader termination, or receiver process.
    """
    if any(row['op'] in ['aniSetXYDisp','aniSetZoom'] for row in program):
        from hsltools.assets._mobile_animation import compile_mobile_action  # lazy: mobile_animation validates the mobile_motion probe packet on use
        return compile_mobile_action(program,frame_count)
    updates, events, poses, flashes = 0, [], [], []
    for instruction in program:
        op, args = instruction['op'], instruction['args']
        if any(type(value) is not int for value in args):
            raise ValueError('Ordinary opcode parameters must be integers')
        at = updates + 1
        event = {'op': op, 'args': list(args), 'update': at, 'source_line': instruction['source_line']}
        if op == 'aniDelay':
            if len(args) != 1 or not 0 <= args[0] <= 100000:
                raise ValueError('Unsupported ordinary delay')
            updates += 1 + max(1, args[0])
        elif op == 'aniSetShape':
            if len(args) != 1 or not 0 <= args[0] < frame_count:
                raise ValueError('Ordinary pose outside bound source frames')
            poses.append({'frame': args[0], 'update': at})
            updates += 1
        elif op == 'aniInsertAttackFlash':
            if len(args) != 2:
                raise ValueError('Ordinary flash requires two offsets')
            flashes.append(event)
            # 0x402264 -> 0x402278 continues decoding without a new update.
        elif op in ['aniSetSubSpeed','aniSetAddSpeed']:
            if len(args)!=4 or args[0] not in [64,192] or any(v<0 or v%65536 for v in args[1:]):
                raise ValueError('Unproved ordinary movement values')
            updates += 1
        elif op == 'aniSetStopSpeed':
            if args:raise ValueError('Stop-speed takes no arguments')
            updates += 1
        else:
            raise ValueError('Unsupported opcode in live ordinary action: ' + op)
        events.append(event)
    if not poses or len(flashes) != 1 or updates < flashes[0]['update']:
        raise ValueError('Ordinary binding requires poses, one flash and a terminal wait')
    result = {'events': events, 'poses': poses, 'release_update': flashes[0]['update'],
            'complete_updates': updates, 'initial_frame': 0,
            'end_policy': 'Authored end enters existing remake receiver schedule; no implicit native aniOver or common-tail equivalence claim.'}
    if any(e['op'] in ['aniSetSubSpeed','aniSetAddSpeed'] for e in events):
        from hsltools.probes.priest_motion import PACKET, check
        check(json.loads(PACKET.read_text()))
        y=speed=step=limit=direction=mode=0;offsets=[[0,0]]
        for tick in range(1,updates+1):
            for event in events:
                if event['update']!=tick:continue
                if event['op'] in ['aniSetSubSpeed','aniSetAddSpeed']:
                    angle,speed,step,limit=event['args'];direction=-1 if angle==192 else 1
                    mode=-1 if event['op']=='aniSetSubSpeed' else 1
                elif event['op']=='aniSetStopSpeed':mode=0
            if mode:
                y += direction*(speed//65536)
                speed=max(limit,speed-step) if mode<0 else min(limit,speed+step)
            offsets.append([0,y])
        result['motion_offsets']=offsets
        result['motion_source']='original_priest_motion.json: setter yields and integration-before-speed-step'
    return result


def validate_cast_program(program, panel_count, token):
    """The s_action program as the cut-in plays it: only CAST_OPCODES, in source order, one
    aniInsertCastObject whose start panel leaves at least one portrait frame (panels 1 ..
    start-1) and one inset (start .. count-1). [] when the actor declares none."""
    if not program:
        return []
    cast_objects = [instruction for instruction in program if instruction['op'] == 'aniInsertCastObject']
    for instruction in program:
        if instruction['op'] not in CAST_OPCODES:
            raise ValueError(f'Unsupported opcode in live cast program: {token} {instruction["op"]}')
        if any(type(value) is not int for value in instruction['args']):
            raise ValueError('Cast program parameters must be integers: ' + token)
    if len(cast_objects) != 1 or not 2 <= cast_objects[0]['args'][2] < panel_count:
        raise ValueError('Cast program needs one aniInsertCastObject with a start panel inside the strip: ' + token)
    return [{'op': instruction['op'], 'args': list(instruction['args']), 'source_line': instruction['source_line']} for instruction in program]


def bind_programs(manifest):
    data = json.loads(PROGRAMS.read_text())
    if data.get('schema') != 'hsl_animal_programs.v1' or data['sources']['programs']['sha256'] != manifest['source_sha256']:
        raise ValueError('Complete program source does not match the bound ANIMAL artwork')
    records = {row['code']: row for row in data['records']}
    for actor, bound in manifest['actors'].items():
        if actor not in ACTORS:
            raise ValueError('Manifest contains an unsupported combat actor: ' + actor)
        token = actor_token(actor)
        row = records[token]
        bound['sprite_facing'] = SPRITE_FACING[actor]
        bound['facing_evidence'] = facing_evidence(actor)
        if row['fields']['shape']['token'].lower() != bound['frames'][0]['source_member'].lower() or row['fields']['number']['value'] != len(bound['frames']):
            raise ValueError('Ordinary program/artwork identity mismatch: ' + token)
        if is_receiver_only(row['programs']['action']):
            if any(instruction['op'] != 'aniDelay' for instruction in row['programs']['action']):
                raise ValueError('Receiver-only source contains an unsupported action opcode: ' + token)
            bound['receiver_only'] = True
            # These actors have no weapon range or attack program. Keep the
            # actual source poses; never invent a flash/strike to appease a compiler.
            bound['receiver_program'] = row['programs']['action']
        else:
            bound['dispatch'] = compile_action(row['programs']['action'], len(bound['frames']))
            flash = next(event for event in bound['dispatch']['events'] if event['op'] == 'aniInsertAttackFlash')
            if bound['attack_flash_offset'] != flash['args']:
                raise ValueError('Flash offsets differ from the complete source program: ' + token)
        expected_hurt_frame = derive_hurt_frame(row['programs']['action'], len(bound['frames']))
        if bound['hurt_frame'] != expected_hurt_frame:
            raise ValueError('Hurt frame differs from the derived source reaction slot: ' + token)
        bound['cast_program'] = validate_cast_program(row['programs'].get('s_action', []), row['fields'].get('s_number', {}).get('value', 0), token)
        bound['magic_cast_program'] = validate_cast_program(row['programs'].get('m_action', []), row['fields'].get('m_number', {}).get('value', 0), token)
    manifest['cast_program_policy'] = CAST_PROGRAM_POLICY
    manifest['magic_cast_program_policy'] = MAGIC_CAST_PROGRAM_POLICY
    manifest['program_source'] = {'path': str(PROGRAMS), 'sha256': hashlib.sha256(PROGRAMS.read_bytes()).hexdigest()}
    manifest['timing_note'] = 'Ordinary dispatch consumes complete source order and documented setup/wait/yield boundaries; one update per 16 ms original tick (docs/evidence_packets/runtime_observations/original_tick_rate/README.md). PLAYBACK_SPEED is a remake clock parameter in CombatPresentationTiming; legacy timeline is raw resource evidence only.'
    return manifest


def build(pak, selected=None):
    packages = find_decoded_paks_packages(pak)
    def read(name):
        for package in packages:
            record = find_paks_record_by_name(package['records'], '@:\\' + name)
            if record:
                return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        raise ValueError('missing ' + name)
    source = (ROOT / 'ANIMAL.TXT').read_bytes()
    if read('data\\ANIMAL.TXT') != source:
        raise ValueError('Tracked ANIMAL.TXT differs from the archive member; regenerate animal_programs first')
    result = {'schema': 'hsl_combat_animation.v1', 'evidence_tier': 'resource-derived', 'source_sha256': hashlib.sha256(source).hexdigest(), 'timing_note': 'Original delay counts in logic ticks (16 ms, docs/evidence_packets/runtime_observations/original_tick_rate/README.md); modern cut-in layout.', 'actors': {}}
    if selected is not None:
        result=json.loads((ROOT/'manifest.json').read_text())
        if result['source_sha256']!=hashlib.sha256(source).hexdigest():raise ValueError('Cannot append to a different source manifest')
    for actor in ACTORS if selected is None else selected:
        token = actor_token(actor)
        block = next(b for b in source.decode('cp950').split('[animal]') if re.search(r'^code\s*=\s*' + token + r'\s*$', b, re.M))
        fields = dict(re.findall(r'^([a-z_]+)\s*=\s*([^\r\n;]+)', block, re.M))
        actions = ','.join(re.findall(r'^action\s*=\s*([^\r\n;]+)', block, re.M))
        program_data = json.loads(PROGRAMS.read_text())
        source_program = next(record for record in program_data['records'] if record['code'] == token)['programs']['action']
        timeline = source_timeline(source_program)
        frames = []
        # The block's own `shape` strip: ANIMAL\P<row>_001.SHP for every row except 066, whose
        # guardian block declares 050's ANIMAL\P050_001.SHP (it also walks in 050's SHAPE), and
        # 069, whose block declares 022's ANIMAL\P022_001.SHP (no P069 member; walks in SHAPE\022).
        shape_prefix = re.fullmatch(r'(ANIMAL\\P\d{3}_)001\.SHP', fields['shape'].split()[0], re.I).group(1)
        for index in range(int(fields['number'])):
            member = f'{shape_prefix}{index + 1:03d}.SHP'
            data = read(member)
            target = ROOT / actor / f'{index}.png'
            write_shp_preview(data, parse_shp(data), target)
            frames.append({'res_path': 'res://' + target.as_posix(), 'draw_origin': list(struct.unpack_from('<ii', data, 0x1c)), 'source_member': member, 'sha256': hashlib.sha256(data).hexdigest(), 'png_sha256': png_sha256(target)})
        flash = {}
        if 'fh_shape' in fields:
            member = fields['fh_shape'].split()[0]
            data = read(member)
            target = ROOT / actor / 'flash.png'
            write_shp_preview(data, parse_shp(data), target)
            flash = {'res_path': 'res://' + target.as_posix(), 'source_member': member, 'draw_origin': list(struct.unpack_from('<ii', data, 0x1c)), 'png_sha256': png_sha256(target)}
        flash_match = re.search(r'aniInsertAttackFlash,(-?\d+),(-?\d+)', actions)
        if flash_match is None and not is_receiver_only(source_program):raise ValueError('Missing original strike release: '+actor)
        flash_offset = list(map(int,flash_match.groups())) if flash_match else []
        result['actors'][actor] = {'frames': frames, 'timeline': timeline, 'source_k_action': fields['k_action'].strip().split()[0], 'sprite_facing': SPRITE_FACING[actor], 'facing_evidence': facing_evidence(actor), 'flash': flash, 'attack_flash_offset': flash_offset, 'hurt_frame': derive_hurt_frame(source_program, len(frames)), 'hurt_frame_evidence': hurt_frame_evidence(source_program, len(frames))}
        def strip(shape_key, count_key, stem):
            frames = []
            prefix, number = re.fullmatch(r'(.+_)(\d+)\.SHP', fields[shape_key].strip()).groups()
            for index in range(int(fields[count_key])):
                member = prefix + str(int(number) + index).zfill(len(number)) + '.SHP'
                data = read(member)
                target = ROOT / actor / f'{stem}-{index}.png'
                write_shp_preview(data, parse_shp(data), target)
                frames.append({'res_path': 'res://' + target.as_posix(), 'draw_origin': list(struct.unpack_from('<ii', data, 0x1c)), 'source_member': member, 'sha256': hashlib.sha256(data).hexdigest(), 'png_sha256': png_sha256(target)})
            return frames
        result['actors'][actor]['special_frames'] = strip('s_shape', 's_number', 'special') if actor in SPECIAL_FRAME_ACTORS else []
        result['actors'][actor]['magic_frames'] = strip('m_shape', 'm_number', 'magic') if actor in MAGIC_FRAME_ACTORS else []
    result['special_frames_policy'] = SPECIAL_FRAMES_POLICY
    result['magic_frames_policy'] = MAGIC_FRAMES_POLICY
    if selected is None:
        member = 'ANIMAL\\BG051.SHP'
        data = read(member)
        target = ROOT / 'background.png'
        write_shp_preview(data, parse_shp(data), target)
        result['background'] = {'res_path': 'res://' + target.as_posix(), 'source_member': member, 'png_sha256': png_sha256(target)}
        result['opening'] = import_opening(read)
    (ROOT / 'manifest.json').write_text(json.dumps(bind_programs(result), ensure_ascii=False, indent=2) + '\n')


def import_opening(read):
    data = read(OPENING_MEMBER)
    target = ROOT / 'opening_ball.png'
    write_shp_preview(data, parse_shp(data), target)
    return {'res_path': 'res://' + target.as_posix(), 'source_member': OPENING_MEMBER, 'draw_origin': list(struct.unpack_from('<ii', data, 0x1c)),
            'sha256': hashlib.sha256(data).hexdigest(), 'png_sha256': png_sha256(target), 'note': OPENING_NOTE}


def append_opening(pak):
    """Import only the opening shape into the existing manifest; every actor frame stays as verified."""
    packages = find_decoded_paks_packages(pak)
    def read(name):
        for package in packages:
            record = find_paks_record_by_name(package['records'], '@:\\' + name)
            if record:
                return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        raise ValueError('missing ' + name)
    path = ROOT / 'manifest.json'
    result = json.loads(path.read_text())
    result['opening'] = import_opening(read)
    path.write_text(json.dumps(bind_programs(result), ensure_ascii=False, indent=2) + '\n')


def check():
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    expected = bind_programs(json.loads(json.dumps(manifest)))
    assert manifest == expected, 'Complete ordinary program binding is stale'
    assert manifest.get('special_frames_policy') == SPECIAL_FRAMES_POLICY
    assert manifest.get('cast_program_policy') == CAST_PROGRAM_POLICY
    assert manifest.get('magic_frames_policy') == MAGIC_FRAMES_POLICY
    assert manifest.get('magic_cast_program_policy') == MAGIC_CAST_PROGRAM_POLICY
    assert hashlib.sha256((ROOT / 'ANIMAL.TXT').read_bytes()).hexdigest() == manifest['source_sha256']
    background = manifest['background']
    assert png_sha256(Path(background['res_path'].removeprefix('res://'))) == background['png_sha256']
    opening = manifest['opening']
    assert opening['source_member'] == OPENING_MEMBER and opening['note'] == OPENING_NOTE and len(opening['draw_origin']) == 2
    assert png_sha256(Path(opening['res_path'].removeprefix('res://'))) == opening['png_sha256']
    source = (ROOT / 'ANIMAL.TXT').read_bytes().decode('cp950')
    records = {row['code']: row for row in json.loads(PROGRAMS.read_text())['records']}
    bound_opcodes = {event['op'] for item in manifest['actors'].values() for event in item.get('dispatch', {}).get('events', [])}
    bound_opcodes |= {instruction['op'] for item in manifest['actors'].values() for instruction in item.get('receiver_program', [])}
    assert bound_opcodes == set(ACTION_OPCODES), f'ACTION_OPCODES differs from the bound dispatch opcodes: {sorted(bound_opcodes)}'
    for actor, item in manifest['actors'].items():
        token = actor_token(actor)
        row = records[token]
        block = next(b for b in source.split('[animal]') if re.search(r'^code\s*=\s*' + token + r'\s*$', b, re.M))
        assert item['sprite_facing'] == SPRITE_FACING[actor]
        assert item['source_k_action'] == re.search(r'^k_action\s*=\s*(\w+)', block, re.M)[1]
        actions = ','.join(re.findall(r'^action\s*=\s*([^\r\n;]+)', block, re.M))
        match = re.search(r'aniInsertAttackFlash,(-?\d+),(-?\d+)', actions)
        assert item['attack_flash_offset'] == (list(map(int,match.groups())) if match else [])
        assert (match is None) == is_receiver_only(row['programs']['action'])
        assert item['timeline'] == source_timeline(row['programs']['action'])
        assert item['hurt_frame'] == derive_hurt_frame(row['programs']['action'], len(item['frames']))
        assert 'special_frames' in item, f'{actor}: special_frames must be declared ([] = no strip imported)'
        assert item['cast_program'] == validate_cast_program(row['programs'].get('s_action', []), row['fields'].get('s_number', {}).get('value', 0), token)
        if item['special_frames']:
            assert item['cast_program'], f'{actor}: an imported s_shape strip needs its s_action cast program'
        if actor in SPECIAL_FRAME_ACTORS:
            assert len(item['special_frames']) == int(re.search(r'^s_number\s*=\s*(\d+)', block, re.M)[1])
            assert item['special_frames'][0]['source_member'] == re.search(r'^s_shape\s*=\s*(\S+)', block, re.M)[1]
        else:
            assert item['special_frames'] == [], f'{actor}: strip imported but not listed in SPECIAL_FRAME_ACTORS'
        assert 'magic_frames' in item, f'{actor}: magic_frames must be declared ([] = no strip imported)'
        assert item['magic_cast_program'] == validate_cast_program(row['programs'].get('m_action', []), row['fields'].get('m_number', {}).get('value', 0), token)
        if item['magic_frames']:
            assert item['magic_cast_program'], f'{actor}: an imported m_shape strip needs its m_action cast program'
        if actor in MAGIC_FRAME_ACTORS:
            assert len(item['magic_frames']) == int(re.search(r'^m_number\s*=\s*(\d+)', block, re.M)[1])
            assert item['magic_frames'][0]['source_member'] == re.search(r'^m_shape\s*=\s*(\S+)', block, re.M)[1]
        else:
            assert item['magic_frames'] == [], f'{actor}: magic strip imported but not listed in MAGIC_FRAME_ACTORS'
        for frame in item['frames'] + item['special_frames'] + item['magic_frames'] + ([item['flash']] if item['flash'] else []):
            assert png_sha256(Path(frame['res_path'].removeprefix('res://'))) == frame['png_sha256']
    print('COMBAT_ANIMATION_CHECK_PASS')


class CombatAnimationTask(ScriptCheckTask):
    name = 'combat_animation'
    family = 'assets'
    inputs = (PROGRAMS.as_posix(), (ROOT / 'ANIMAL.TXT').as_posix())
    outputs = tuple(path.as_posix() for path in (ROOT / 'manifest.json', ROOT / 'background.png', ROOT / 'opening_ball.png')) + tuple(f'{ROOT.as_posix()}/{actor}/' for actor in ACTORS)
    replaces = ('tools/hsl_combat_animation.py --check',)
    scripts = ('tools/hsltools/assets/combat_animation.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        # Whole rebuild: a different PNG encoder would rewrite every tracked frame; append
        # actors with the script's --actors instead.
        build(original_archive(ctx))


def tasks() -> list[CombatAnimationTask]:
    return [CombatAnimationTask()]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pak', type=Path)
    parser.add_argument('--actors', nargs='+', choices=ACTORS, help='Append only selected source actors; preserve already verified artwork')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--bind-programs', action='store_true', help='Bind validated ordinary program data without reimporting any SHP assets')
    parser.add_argument('--opening', action='store_true', help='Import only the opening shape (MAGIC\\BALL001.SHP) into the existing manifest')
    args = parser.parse_args()
    if args.check: check()
    elif args.opening:
        if not args.pak: parser.error('--opening requires --pak')
        append_opening(args.pak)
        print('COMBAT_OPENING_IMPORT_PASS')
    elif args.bind_programs:
        path = ROOT / 'manifest.json'
        result = bind_programs(json.loads(path.read_text()))
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        print('COMBAT_PROGRAM_BINDING_PASS')
    else: build(args.pak,args.actors)
