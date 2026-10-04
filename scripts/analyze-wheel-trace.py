#!/usr/bin/env python3
"""[DEBUG-char-wheel-deep] Geometry trace checker; no onscreen pixel claim."""
import argparse, json, math, statistics, sys
PREFIX = '[DEBUG-char-wheel-deep] '
def angle(p,c): return math.atan2(p[1]-c[1],p[0]-c[0])
def wrap(x): return (x+math.pi)%(2*math.pi)-math.pi
def analyze(records):
    inputs={r['sequence']:r for r in records if r['kind']=='input'}
    accepts=[r for r in records if r['kind']=='accepted']
    results=[]
    for a in accepts:
        seq=a['sequence']; inp=inputs.get(seq,{}); faults=[]
        delta=inp.get('dx',0)+inp.get('dy',0)
        if delta*a['step']<0: faults.append('policy_direction')
        center=a.get('center'); before=a.get('before'); target=a.get('model')
        samples=[r for r in records if r['kind']=='sample' and r['sequence']==seq and len(r.get('presentation',[]))==2]
        onset=None; arrival=None; wrong=[]
        target_delta=wrap(angle(target,center)-angle(before,center)) if center and before and target else 0
        next_accept=next((b['now'] for b in accepts if b['now']>a['now']),float('inf'))
        complete=next_accept-a['now']>=.24
        for s in samples:
            dt=s['now']-a['now']; p=s['presentation']
            movement=wrap(angle(p,center)-angle(before,center)) if center and before else 0
            if abs(movement)>.02 and onset is None: onset=dt*1000
            if dt>.015 and movement*target_delta<0 and abs(movement)>.02: wrong.append(round(dt*1000,2))
            if math.dist(p,target)<1 and arrival is None: arrival=dt*1000
        if wrong: faults.append('presentation_wrong_direction')
        if onset is not None and onset>75: faults.append('late_motion_onset')
        if complete and samples and samples[-1]['now']-a['now']>=.22:
            if onset is None and abs(target_delta)>.03: faults.append('no_motion')
            if arrival is None: faults.append('no_arrival_by_220ms')
        results.append(dict(sequence=seq,step=a['step'],offset=a['offset'],delivery_ms=round((inp.get('now',0)-inp.get('eventTime',0))*1000,2),
            motion_onset_ms=None if onset is None else round(onset,2),arrival_ms=None if arrival is None else round(arrival,2),
            expected_angle=round(target_delta,4),wrong_direction_samples_ms=wrong,retargeted=not complete,samples=len(samples),faults=faults))
    delivery=[(r['now']-r['eventTime'])*1000 for r in inputs.values()]
    return dict(input_events=len(inputs),accepted_steps=len(accepts),delivery_mean_ms=round(statistics.mean(delivery),2) if delivery else None,
        delivery_max_ms=round(max(delivery),2) if delivery else None,steps=results,
        verdict='RED' if any(r['faults'] for r in results) else 'INCOMPLETE' if not results or not any(r['samples'] for r in results) else 'LAYER_TRACE_CLEAR',
        scope='Input and CALayer presentation only; physical screen delay requires user/pixel evidence.')
def main():
    parser=argparse.ArgumentParser();parser.add_argument('trace');args=parser.parse_args()
    records=[]
    for line in open(args.trace):
        if PREFIX in line: records.append(json.loads(line.split(PREFIX,1)[1]))
    report=analyze(records);print(json.dumps(report,indent=2))
    return 1 if report['verdict']=='RED' else 2 if report['verdict']=='INCOMPLETE' else 0
if __name__=='__main__':sys.exit(main())
