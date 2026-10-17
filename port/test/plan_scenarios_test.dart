// Scenario planner for the differential harness.
//
// Reads tools/diff/plans.json - small programs such as "pour until the shaker holds 179 units" - and works out the
// frame at which each input has to be applied, by running the Dart port with the same deterministic RNG. The output
// (tools/diff/scenarios.json) is a plain list of [frame, input] pairs: INPUTS ONLY. Nothing the port computed is
// stored as an expectation; the original SWF is the oracle (tools/diff/run_diff.py replays the same inputs in it).
// The planner exists so that scenarios land on interesting states (capacity edge, score-bin edge, 4th vs 5th shake
// cycle, ...) instead of relying on hand-tuned waits.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/game/world.dart';

import 'diff_support.dart';
import 'sim_helpers.dart';

class Planner {
  final Sim sim;
  final List<List<Object>> ops = [];
  int frame = 0;
  Planner(this.sim);

  GameWorld get w => sim.world;

  void tick() {
    frame++;
    sim.stage.tick();
  }

  /// Apply [op] now (after the tick of the current frame), recording it.
  void emit(Object op) {
    ops.add([frame, op]);
    applyOp(sim, op);
  }

  void run(int n) {
    for (var i = 0; i < n; i++) {
      tick();
    }
  }

  /// Tick until [cond] holds (checked after each tick) or [max] frames passed. Returns whether it held.
  bool until(bool Function() cond, {int max = 600}) {
    for (var i = 0; i < max; i++) {
      if (cond()) return true;
      tick();
    }
    return cond();
  }

  bool get settled => w.phase == GamePhase.rest || w.phase == GamePhase.shakeRest;

  /// Programs ---------------------------------------------------------------------------------------------------
  void step(List<dynamic> s) {
    switch (s[0] as String) {
      case 'start':
        tick();
        emit('start');
      case 'wait':
        run(s[1] as int);
      case 'pick':
        emit(['pick', s[1]]);
        until(() => w.phase == GamePhase.rest && w.hand.holdingItem, max: 250);
      case 'pourFrames':
        emit('pourDown');
        run(s[1] as int);
        emit('pourUp');
        run(2);
      case 'pourToVolume': // hold pour until the shaker holds at least this much, release in the same frame
        emit('pourDown');
        until(() => w.shaker.fluidVolume >= (s[1] as num), max: 500);
        emit('pourUp');
        run(2);
      case 'pourVolume': // pour this much more
        final target = w.shaker.fluidVolume + (s[1] as num);
        emit('pourDown');
        until(() => w.shaker.fluidVolume >= target, max: 500);
        emit('pourUp');
        run(2);
      case 'pourToPoints': // pour until points would exceed the target on the next frame (stops at or below it)
        final target = s[1] as num;
        final per = _heldScore();
        emit('pourDown');
        until(() => w.shaker.points + 2 * per > target, max: 600); // one more pour frame runs after release
        emit('pourUp');
        run(2);
      case 'creepTo':
        // Reach exactly this many points using Gin (3) then Tonic (2). One more pour frame always runs after the
        // release, so release when the remaining amount is 3, 5 or 7 (gin) and then 2 (tonic).
        final target = s[1] as num;
        if (target - w.shaker.points < 8) return; // too close to creep; leave as is
        step(['pick', 7]);
        emit('pourDown');
        until(() {
          final r = target - w.shaker.points;
          return r == 3 || r == 5 || r == 7;
        }, max: 500);
        emit('pourUp');
        run(2);
        if (target - w.shaker.points > 0) {
          step(['pick', 20]);
          emit('pourDown');
          tick();
          until(() => target - w.shaker.points <= 2, max: 200);
          emit('pourUp');
          run(2);
        }
      case 'ice':
        emit('ice');
        until(() => w.phase == GamePhase.rest && w.hand.holdingItem, max: 250);
      case 'lemon':
        emit('lemon');
        until(() => w.phase == GamePhase.rest && w.hand.holdingItem || w.phase == GamePhase.serveRest, max: 250);
      case 'shakeCycles':
        // hold shake until this many full cycles completed, then release in the same frame
        emit('shakeDown');
        until(() => w.shaker.shakeCycles >= (s[1] as int) || w.phase == GamePhase.finaleInit, max: 900);
        emit('shakeUp');
        run(2);
        until(() => w.phase == GamePhase.shakeRest || w.phase == GamePhase.finaleInit, max: 200);
      case 'shakeFrames':
        emit('shakeDown');
        run(s[1] as int);
        emit('shakeUp');
        run(s.length > 2 ? s[2] as int : 8);
      case 'serve':
        // wait for the shaker to settle, then serve and wait for the whole sequence to end
        until(() => w.phase == GamePhase.shakeRest, max: 300);
        emit('serve');
        until(() => w.phase == GamePhase.waitInput, max: 2000);
        run(40);
      case 'serveNow': // serve whatever the phase is
        emit('serve');
        run(s.length > 1 ? s[1] as int : 30);
      case 'garnish':
        until(() => w.phase == GamePhase.shakeRest, max: 300);
        emit('lemon');
        until(() => w.phase == GamePhase.serveRest || w.phase == GamePhase.getBottle, max: 200);
        until(() => w.phase == GamePhase.rest || w.phase == GamePhase.returnTweenHand, max: 400);
      case 'restart':
        emit('restart');
        run(s.length > 1 ? s[1] as int : 60);
      case 'op': // literal input
        emit(s[1] as Object);
      case 'pourDown':
        emit('pourDown');
      case 'pourUp':
        emit('pourUp');
      case 'shakeDown':
        emit('shakeDown');
      case 'shakeUp':
        emit('shakeUp');
      default:
        fail('unknown plan step $s');
    }
  }

  double _heldScore() => w.hand.held?.score ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolve tools/diff/plans.json into scenarios.json', () async {
    final plans = jsonDecode(File('../tools/diff/plans.json').readAsStringSync()) as Map<String, dynamic>;
    final out = <Map<String, dynamic>>[];
    for (final p in (plans['scenarios'] as List).cast<Map<String, dynamic>>()) {
      if (p.containsKey('ops')) {
        out.add(p); // explicit (fuzz) scenarios pass through
        continue;
      }
      final sim = await Sim.create(random: ParkMiller(p['seed'] as int));
      final pl = Planner(sim);
      for (final s in (p['program'] as List)) {
        pl.step(s as List);
      }
      pl.run((p['tail'] ?? 20) as int);
      out.add({'name': p['name'], 'seed': p['seed'], 'note': p['note'], 'frames': pl.frame, 'ops': pl.ops});
    }
    File('../tools/diff/scenarios.json').writeAsStringSync(
        const JsonEncoder.withIndent(null).convert({'_note': 'resolved by port/test/plan_scenarios_test.dart; inputs only', 'scenarios': out}));
    // ignore: avoid_print
    print('planned ${out.length} scenarios');
  });
}
