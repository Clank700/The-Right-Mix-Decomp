#!/usr/bin/env python
"""gen_scenarios.py - writes tools/diff/plans.json, the scenario PROGRAMS for the differential test.

A program is a list of steps ("pick bottle 14", "pour until the shaker holds 179 units", "shake until 4 cycles done",
...). port/test/plan_scenarios_test.dart resolves each program into frame-accurate inputs (scenarios.json) by running
the Dart port with the shared deterministic RNG; the ORIGINAL SWF is then given exactly those inputs
(tools/diff/run_diff.py). Programs only decide *when to press what*; no expected value is ever recorded, so the port
cannot grade itself.

Bottle indices (shelf order): 0 Kahlua 1 Triple Sec 2 Creme de Cacao 3 Creme de Menthe 4 Absinthe 5 Vermouth
6 Calvados 7 Gin 8 Tequila 9/10 Champagne 11 Whisky 12 Cognac 13 Cointreau(amaretto art) 14 Vodka 15 Sambuca
16 Orange 17 Cranberry 18 Lime 19 Passion Fruit 20 Tonic.
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
VODKA, CRAN, LIME, GIN, TONIC = 14, 17, 18, 7, 20


def mix(target, shakes=1):
    """Vodka + cranberry + lime, then Gin/Tonic creep so that points are exactly `target` before shaking."""
    return [['pick', VODKA], ['pourToPoints', int(target * 0.62)],
            ['pick', CRAN], ['pourToPoints', int(target * 0.86)],
            ['pick', LIME], ['pourToPoints', target - 90],
            ['creepTo', target], ['shakeCycles', shakes], ['serve']]


def mix_nocreep(target, shakes=1):
    """Like mix() but without the Gin/Tonic creep (needed near the capacity limit: 8000 points use ~170 of 180 units)."""
    return [['pick', VODKA], ['pourToPoints', int(target * 0.70)],
            ['pick', CRAN], ['pourToPoints', int(target * 0.92)],
            ['pick', LIME], ['pourToPoints', target], ['shakeCycles', shakes], ['serve']]


def prog(name, seed, note, steps, tail=20):
    return {'name': name, 'seed': seed, 'note': note, 'program': [['start'], ['wait', 8]] + steps, 'tail': tail}


def build():
    out = []
    seed = 100

    def add(*a, **k):
        nonlocal seed
        seed += 1
        out.append(prog(a[0], seed, *a[1:], **k))

    # ---- scoring: each verdict bin edge, exactly on it and one point above (final = points + 10 per shake cycle) ----
    for e in range(1000, 8000, 1000):
        add('score_edge_%d_exact' % e, 'final score exactly %d (belongs to the lower bin)' % e, mix(e - 10))
        add('score_edge_%d_plus1' % e, 'final score %d' % (e + 1), mix(e - 9))
    for t in (7990, 8000, 8300, 8600):
        add('score_top_%d' % t, 'about %d points, no creep (capacity limits the mix near the top bin)' % t, mix_nocreep(t))
    add('score_low', 'tiny drink', [['pick', TONIC], ['pourVolume', 3], ['pick', GIN], ['pourVolume', 3],
                                    ['pick', 5], ['pourVolume', 3], ['shakeCycles', 1], ['serve']])
    # ---- variety rule: <=2 and >8 distinct ingredients halve the score -------------------------------------------
    add('variety_1', 'one ingredient', [['pick', VODKA], ['pourVolume', 40], ['shakeCycles', 1], ['serve']])
    add('variety_2', 'two ingredients', [['pick', VODKA], ['pourVolume', 30], ['pick', CRAN], ['pourVolume', 30],
                                         ['shakeCycles', 1], ['serve']])
    add('variety_3', 'three ingredients', [['pick', VODKA], ['pourVolume', 25], ['pick', CRAN], ['pourVolume', 25],
                                           ['pick', LIME], ['pourVolume', 25], ['shakeCycles', 1], ['serve']])
    for n in (8, 9, 10):
        bottles = [VODKA, CRAN, LIME, 1, 12, 0, 3, 6, 9, 19][:n]
        steps = []
        for b in bottles:
            steps += [['pick', b], ['pourVolume', 8]]
        add('variety_%d' % n, '%d distinct ingredients' % n, steps + [['shakeCycles', 1], ['serve']])
    add('variety_flip', 'alternating two bottles A B A B A: each change counts as a new ingredient',
        [['pick', VODKA], ['pourVolume', 10], ['pick', CRAN], ['pourVolume', 10], ['pick', VODKA], ['pourVolume', 10],
         ['pick', CRAN], ['pourVolume', 10], ['pick', VODKA], ['pourVolume', 10], ['shakeCycles', 1], ['serve']])
    # ---- ingredient capacity -------------------------------------------------------------------------------------
    add('cap_179_to_full', 'fill to 179, then 180, then keep pouring while full, change bottle while full',
        [['pick', VODKA], ['pourToVolume', 179], ['pourFrames', 3], ['pourFrames', 25], ['pick', CRAN],
         ['pourFrames', 40], ['pick', TONIC], ['pourFrames', 20], ['shakeCycles', 1], ['serve']])
    add('cap_overpour_one_hold', 'hold pour for 400 frames', [['pick', VODKA], ['pourFrames', 400], ['shakeCycles', 1], ['serve']])
    add('cap_short_taps', 'many short pours across the capacity boundary',
        [['pick', VODKA]] + [['pourFrames', 14] for _ in range(16)] + [['shakeCycles', 1], ['serve']])
    add('cap_full_pick_other', 'full shaker: info text, fetching other bottles, ice, lemon',
        [['pick', VODKA], ['pourFrames', 240], ['pick', CRAN], ['ice'], ['lemon'], ['pourFrames', 20],
         ['shakeCycles', 2], ['serve']])
    # ---- shake timing --------------------------------------------------------------------------------------------
    for k in (1, 2, 3, 4):
        add('shake_%d_cycles' % k, '%d shake cycle(s), then serve' % k,
            [['pick', VODKA], ['pourVolume', 30], ['pick', CRAN], ['pourVolume', 30], ['pick', LIME], ['pourVolume', 30],
             ['shakeCycles', k], ['serve']])
    add('shake_5_milkshake', 'five cycles: the milkshake ending',
        [['pick', VODKA], ['pourVolume', 40], ['pick', CRAN], ['pourVolume', 40], ['shakeCycles', 5], ['wait', 600]], tail=40)
    add('shake_hold_sweep', 'shake held for many different lengths (partial cycles)',
        [['pick', VODKA], ['pourVolume', 30], ['pick', CRAN], ['pourVolume', 30]] +
        [['shakeFrames', n, 10] for n in (3, 10, 17, 18, 19, 22, 25, 30, 38, 39, 40, 41, 42, 44, 60, 61, 62, 63, 64, 70)] +
        [['serve']])
    add('shake_taps', 'rapid shake taps',
        [['pick', VODKA], ['pourVolume', 40], ['pick', CRAN], ['pourVolume', 30]] +
        [['shakeFrames', 14, 10] for _ in range(8)] + [['wait', 400]])
    add('shake_with_bottle_in_hand', 'shake held while still holding a bottle',
        [['pick', VODKA], ['pourVolume', 30], ['shakeDown'], ['wait', 120], ['shakeUp'], ['wait', 60],
         ['shakeCycles', 1], ['serve']])
    # ---- additives -----------------------------------------------------------------------------------------------
    add('ice_first', 'ice before anything else', [['ice'], ['pick', VODKA], ['pourVolume', 30], ['pick', CRAN],
                                                  ['pourVolume', 30], ['shakeCycles', 2], ['serve']])
    add('ice_twice', 'ice, bottle, ice again', [['ice'], ['pick', VODKA], ['pourVolume', 30], ['ice'],
                                                ['pick', CRAN], ['pourVolume', 30], ['shakeCycles', 1], ['serve']])
    add('ice_after_pour', 'ice after the bottles', [['pick', VODKA], ['pourVolume', 30], ['pick', LIME],
                                                    ['pourVolume', 30], ['ice'], ['shakeCycles', 1], ['serve']])
    add('lemon_before_shake', 'lemon into the shaker (not a garnish)', [['pick', VODKA], ['pourVolume', 30],
                                                                          ['lemon'], ['shakeCycles', 1], ['serve']])
    add('garnish_basic', 'lemon garnish after the shake', [['pick', VODKA], ['pourVolume', 40], ['pick', CRAN],
                                                           ['pourVolume', 40], ['shakeCycles', 1], ['garnish'],
                                                           ['serveNow', 700]])
    add('garnish_two_shakes_ice', 'ice, two shakes, garnish', [['ice'], ['pick', VODKA], ['pourVolume', 40],
                                                               ['pick', LIME], ['pourVolume', 40], ['shakeCycles', 2],
                                                               ['garnish'], ['serveNow', 700]])
    add('garnish_then_restart', 'garnish, serve, restart, second drink with garnish',
        [['pick', VODKA], ['pourVolume', 40], ['pick', CRAN], ['pourVolume', 30], ['shakeCycles', 1], ['garnish'],
         ['serveNow', 700], ['restart'], ['pick', LIME], ['pourVolume', 40], ['pick', 1], ['pourVolume', 30],
         ['shakeCycles', 1], ['garnish'], ['serveNow', 700]])
    # ---- odd input / transitions ---------------------------------------------------------------------------------
    add('shake_empty', 'shake and serve with nothing in the shaker', [['shakeFrames', 60, 10], ['serveNow', 40],
                                                                        ['pick', VODKA], ['pourVolume', 30],
                                                                        ['shakeCycles', 1], ['serve']])
    add('serve_before_shake', 'serve while still pouring/resting', [['pick', VODKA], ['pourVolume', 30],
                                                                      ['serveNow', 60], ['shakeCycles', 1], ['serve']])
    add('pour_no_bottle', 'pour pressed with an empty hand', [['pourDown'], ['wait', 60], ['pourUp'], ['wait', 20],
                                                              ['pick', VODKA], ['pourVolume', 30], ['shakeCycles', 1],
                                                              ['serve']])
    add('pick_while_pouring', 'another bottle clicked while pour is held',
        [['pick', VODKA], ['pourDown'], ['wait', 30], ['op', ['pick', CRAN]], ['wait', 90], ['pourUp'], ['wait', 20],
         ['pourFrames', 40], ['shakeCycles', 1], ['serve']])
    add('pick_spam', 'bottle clicked three times in a row, then ice and lemon at once',
        [['op', ['pick', VODKA]], ['wait', 6], ['op', ['pick', CRAN]], ['wait', 6], ['op', ['pick', GIN]], ['wait', 90],
         ['op', 'ice'], ['op', 'lemon'], ['wait', 90], ['pourFrames', 40], ['shakeCycles', 1], ['serve']])
    add('restart_midway', 'restart while holding a bottle with a partly full shaker',
        [['pick', VODKA], ['pourVolume', 40], ['restart', 60], ['pick', CRAN], ['pourVolume', 30], ['shakeCycles', 1],
         ['serve']])
    add('restart_after_end', 'full drink, restart on the end screen, second full drink',
        [['pick', VODKA], ['pourVolume', 40], ['pick', CRAN], ['pourVolume', 30], ['shakeCycles', 1], ['serve'],
         ['restart'], ['pick', LIME], ['pourVolume', 40], ['pick', 1], ['pourVolume', 30], ['shakeCycles', 2], ['serve']])
    add('restart_after_milkshake', 'milkshake, restart, normal drink',
        [['pick', VODKA], ['pourVolume', 40], ['shakeCycles', 5], ['wait', 600], ['restart'], ['pick', CRAN],
         ['pourVolume', 40], ['pick', LIME], ['pourVolume', 40], ['shakeCycles', 1], ['serve']])
    add('restart_mid_shake', 'restart while shaking',
        [['pick', VODKA], ['pourVolume', 40], ['shakeDown'], ['wait', 50], ['restart', 80], ['shakeUp'], ['pick', CRAN],
         ['pourVolume', 40], ['shakeCycles', 1], ['serve']])
    # ---- seeded random input soups (explicit inputs) ---------------------------------------------------------------
    rng = random.Random(2026)
    for k in range(40):
        ops, t = [[3, 'start']], 12
        while t < 1500:
            t += rng.choice([3, 5, 8, 12, 20, 35, 60])
            r = rng.random()
            if r < 0.30:
                ops.append([t, ['pick', rng.randrange(21)]])
            elif r < 0.55:
                ops.append([t, 'pourDown'])
                t += rng.choice([6, 15, 40, 90])
                ops.append([t, 'pourUp'])
            elif r < 0.70:
                ops.append([t, 'shakeDown'])
                t += rng.choice([10, 25, 45, 70])
                ops.append([t, 'shakeUp'])
            elif r < 0.78:
                ops.append([t, 'ice'])
            elif r < 0.85:
                ops.append([t, 'lemon'])
            elif r < 0.95:
                ops.append([t, 'serve'])
            else:
                ops.append([t, 'restart'])
        out.append({'name': 'fuzz_%02d' % k, 'seed': 1000 + k, 'frames': t + 700, 'note': 'random input soup',
                    'ops': sorted(ops, key=lambda o: o[0])})
    return out


if __name__ == '__main__':
    plans = build()
    with open(os.path.join(HERE, 'plans.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': 'scenario programs; resolved to inputs by port/test/plan_scenarios_test.dart', 'scenarios': plans},
                  f, indent=0)
    print(len(plans), 'programs')
