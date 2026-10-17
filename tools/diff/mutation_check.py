#!/usr/bin/env python
"""mutation_check.py - is the differential harness sensitive? Break the Dart port on purpose and require a divergence.

For each mutation the source line is edited, the Dart traces of a few relevant scenarios are regenerated, and they are
compared with the stored traces of the ORIGINAL (build/diff/orig_*.txt, produced by run_diff.py). The harness passes
only if every mutation makes at least one scenario diverge. Sources are always restored.

  python tools/diff/mutation_check.py      -> docs/verification/differential_mutations.json
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from run_diff import compare  # noqa: E402

LIB = os.path.join(ROOT, 'port', 'lib', 'game')
MUTATIONS = [
    ('scoring: each poured unit worth +1', 'model/shaker.dart', 'points += ingredientScore;',
     'points += ingredientScore + 1;', ['score_edge_3000_exact']),
    ('capacity 180 -> 181', 'model/shaker.dart', 'static const double capacity = 180;',
     'static const double capacity = 181;', ['cap_179_to_full']),
    ('verdict bin edge 3000 -> 2999', 'config/verdicts.dart', '(3000, Verdict(4,', '(2999, Verdict(4,',
     ['score_edge_3000_exact']),
    ('variety penalty above 8 -> above 9', 'config/verdicts.dart', 'variety > 8)', 'variety > 9)', ['variety_9']),
    ('milkshake after 6 shakes instead of 5', 'phases/shake_phases.dart', 'static const int maxShakes = 5;',
     'static const int maxShakes = 6;', ['shake_5_milkshake']),
    ('shake bonus 10 -> 11 per cycle', 'phases/shake_phases.dart', 'w.shaker.points += 10 * w.shaker.shakeCycles;',
     'w.shaker.points += 11 * w.shaker.shakeCycles;', ['shake_2_cycles']),
    ('random effects: drop the rotation draw', 'effects/particle_spawner.dart',
     'rotationStep = random.nextDouble() * maxRotationStep', 'rotationStep = 0.5 * maxRotationStep',
     ['garnish_basic']),
    ('hand easing 0.65 -> 0.66', 'props/barman_hand.dart', '_easeTo(_targetX, _targetY, 0.65, 8)',
     '_easeTo(_targetX, _targetY, 0.66, 8)', ['variety_1']),
    ('restart forgets to reset the shaker', 'world.dart', '    shaker.reset();\n    verdict', '    verdict',
     ['restart_after_end']),
]


def main():
    plans = json.load(open(os.path.join(HERE, 'scenarios.json')))['scenarios']
    by_name = {s['name']: s for s in plans}
    results = []
    env = dict(os.environ, PATH=os.path.join(ROOT, 'tools', 'flutter', 'bin') + os.pathsep + os.environ['PATH'])
    for title, rel, old, new, names in MUTATIONS:
        path = os.path.join(LIB, rel)
        text = open(path, encoding='utf-8').read()
        if old not in text:
            results.append({'mutation': title, 'error': 'pattern not found'})
            print('%-46s PATTERN NOT FOUND' % title)
            continue
        sub = os.path.join(ROOT, 'build', 'diff', 'mutation_scenarios.json')
        json.dump({'scenarios': [by_name[n] for n in names]}, open(sub, 'w'))
        try:
            open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new, 1))
            subprocess.run(['flutter', 'test', 'test/differential_dump_test.dart'], cwd=os.path.join(ROOT, 'port'),
                           env=dict(env, DIFF_SCENARIOS='../build/diff/mutation_scenarios.json'), shell=True,
                           capture_output=True)
        finally:
            open(path, 'w', encoding='utf-8', newline='').write(text)
        detected = []
        for n in names:
            a = open(os.path.join(ROOT, 'build', 'diff', 'orig_%s.txt' % n), encoding='utf-8').read().splitlines()
            b = open(os.path.join(ROOT, 'build', 'diff', 'dart_%s.txt' % n), encoding='utf-8').read().splitlines()
            r = compare(a, b)
            if r['bad_frames'] or r['len_orig'] != r['len_dart']:
                detected.append({'scenario': n, 'differing_frames': r['bad_frames'], 'fields': sorted(r['count'])})
        results.append({'mutation': title, 'detected': bool(detected), 'by': detected})
        print('%-46s %s' % (title, 'DETECTED by ' + ', '.join(d['scenario'] for d in detected) if detected else 'MISSED'))
    os.makedirs(os.path.join(ROOT, 'docs', 'verification'), exist_ok=True)
    json.dump(results, open(os.path.join(ROOT, 'docs', 'verification', 'differential_mutations.json'), 'w'), indent=1)
    return 0 if all(r.get('detected') for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
