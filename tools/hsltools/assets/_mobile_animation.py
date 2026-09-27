"""Source004/006 mobile action programs (aniSetXYDisp / aniSetZoom / the speed setters) compiled
into the combat-animation manifest shape: pose schedule, release update and the per-update
displacement / scale states. The dispatcher ticks follow the mobile_motion probe packet, which
compile_mobile_action re-validates before compiling; rendering clock and afterimages stay
independent (hsltools.assets.combat_animation binds the result; `_`: a helper of that task module,
not a task). Body moved verbatim from the
former tools/hsl_mobile_animation.py.
"""
from __future__ import annotations

import json

from hsltools.probes.mobile_motion import PACKET, check


def compile_mobile_action(program,frame_count):
    check(json.loads(PACKET.read_text()))
    events=[];poses=[];flashes=[];updates=0
    for row in program:
        op,args=row['op'],row['args'];at=updates+1
        if any(type(v) is not int for v in args):raise ValueError('Nonintegral source animation argument')
        event=dict(op=op,args=list(args),update=at,source_line=row['source_line'])
        if op=='aniDelay':
            if len(args)!=1 or not 0<=args[0]<=100000:raise ValueError('Invalid animation delay')
            updates+=1+max(1,args[0])
        elif op=='aniSetShape':
            if len(args)!=1 or not 0<=args[0]<frame_count:raise ValueError('Invalid source pose')
            poses.append(dict(frame=args[0],update=at));updates+=1
        elif op=='aniInsertAttackFlash':
            if len(args)!=2:raise ValueError('Invalid flash offset')
            flashes.append(event)
        elif op in ['aniSetSubSpeed','aniSetAddSpeed']:
            if len(args)!=4 or args[0] not in [0,64,128,192] or any(v<0 or v%32768 for v in args[1:]):raise ValueError('Unproved source speed domain')
            updates+=1
        elif op=='aniSetStopSpeed':
            if args:raise ValueError('Invalid speed stop')
            updates+=1
        elif op=='aniSetXYDisp':
            if len(args)!=2:raise ValueError('Invalid relative XY command')
            # This command drains the next opcode; no extra dispatcher tick.
        elif op=='aniSetZoom':
            if len(args)!=1 or not 0<args[0]<=0x40000:raise ValueError('Invalid source zoom')
            updates+=1
        else:raise ValueError('Unproved mobile actor animation opcode: '+op)
        events.append(event)
    if len(flashes)!=1 or not poses:raise ValueError('Missing source strike schedule')
    x=y=speed=step=limit=direction=mode=0;zoom=65536;states=[dict(offset=[0,0],zoom=zoom)]
    vectors={0:(1,0),64:(0,1),128:(-1,0),192:(0,-1)}
    for tick in range(1,updates+1):
        for event in events:
            if event['update']!=tick:continue
            op,args=event['op'],event['args']
            if op in ['aniSetSubSpeed','aniSetAddSpeed']:
                direction,speed,step,limit=args;mode=-1 if op=='aniSetSubSpeed' else 1
            elif op=='aniSetStopSpeed':mode=0
            elif op=='aniSetXYDisp':x+=args[0];y+=args[1]
            elif op=='aniSetZoom':zoom=args[0]
        states.append(dict(offset=[x,y],zoom=zoom))
        if mode:
            dx,dy=vectors[direction];x+=dx*speed//65536;y+=dy*speed//65536
            speed=max(limit,speed-step) if mode<0 else min(limit,speed+step)
    return dict(events=events,poses=poses,release_update=flashes[0]['update'],complete_updates=updates,initial_frame=0,
                presentation_transform_states=states,transform_source='original_mobile_motion.json and animal_program_execution.json',
                end_policy='Source displacement/scale and pose order, drawn before movement tail; afterimage creation and wall-clock are separate remake choices.')
