#!/usr/bin/env python
"""coverage.py - what did the differential scenarios actually exercise? (computed from the ORIGINAL's traces)

  python tools/diff/coverage.py   -> prints a summary and writes build/diff/coverage.json
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from run_diff import parse  # noqa: E402

ALL_STATES = ['preGame', 'getBottle', 'pour', 'rest', 'returnTweenHand', 'shake', 'shakeRest', 'serve', 'serveRest',
              'serveLemon', 'finaleInit', 'finale', 'endGame', 'waitInput']


def main():
    out = os.path.join(ROOT, 'build', 'diff')
    states, endings, transitions = set(), {}, set()
    flags = {'full_seen': 0, 'garnished_seen': 0, 'max_shake_cycles': 0, 'max_variety': 0, 'max_volume': 0,
             'restarts_after_end': 0, 'rng_draw_runs': 0, 'frames': 0, 'scenarios': 0}
    for path in sorted(glob.glob(os.path.join(out, 'orig_*.txt'))):
        name = os.path.basename(path)[5:-4]
        lines = open(path, encoding='utf-8').read().splitlines()
        flags['scenarios'] += 1
        flags['frames'] += len(lines)
        prev, ended = None, False
        for ln in lines:
            _, d = parse(ln)
            st = d['state']
            states.add(st)
            if prev and prev != st:
                transitions.add((prev, st))
            if st == 'waitInput':
                ended = True
                m = re.match(r'\[Your score: (\d+)\]', d['ys'])
                if m:
                    endings.setdefault(int(d['fa']), set()).add(name)
            if ended and st in ('rest', 'getBottle') and prev == 'waitInput':
                flags['restarts_after_end'] += 1
            if d['full'] == 'true':
                flags['full_seen'] += 1
            if d['g'] == 'true':
                flags['garnished_seen'] += 1
            flags['max_shake_cycles'] = max(flags['max_shake_cycles'], int(d['cyc']))
            flags['max_variety'] = max(flags['max_variety'], int(d['var']))
            flags['max_volume'] = max(flags['max_volume'], int(d['v']) / 100)
            prev = st
        if lines and parse(lines[-1])[1]['rs'] != parse(lines[0])[1]['rs']:
            flags['rng_draw_runs'] += 1
    report = {
        'states_visited': sorted(states),
        'states_not_visited': [s for s in ALL_STATES if s not in states],
        'endings_reached': {str(k): sorted(v) for k, v in sorted(endings.items())},
        'endings_missing': [k for k in range(1, 11) if k not in endings],
        'distinct_state_transitions': len(transitions),
        'transitions': sorted('%s>%s' % t for t in transitions),
        **flags,
    }
    json.dump(report, open(os.path.join(out, 'coverage.json'), 'w'), indent=1)
    print('scenarios', flags['scenarios'], 'frames', flags['frames'])
    print('states visited %d/14, missing: %s' % (len(states & set(ALL_STATES)), report['states_not_visited']))
    print('endings reached:', {k: len(v) for k, v in sorted(endings.items())}, 'missing:', report['endings_missing'])
    print('state transitions seen:', len(transitions))
    print({k: v for k, v in flags.items()})


if __name__ == '__main__':
    main()
