import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'sim_helpers.dart';

/// Regression guard: a scripted playthrough with a seeded RNG must produce exactly the recorded
/// per-tick trace (when a local test/golden/trace.txt exists; see below).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> playthrough() async {
    final sim = await Sim.create(random: math.Random(7));
    final trace = <String>[];

    void record(String label) {
      final w = sim.world;
      trace.add('$label ${w.phase.name} vol=${w.shaker.fluidVolume.toStringAsFixed(1)} '
          'pts=${w.shaker.points.toStringAsFixed(1)} var=${w.shaker.variety} '
          'hand=${w.hand.x.toStringAsFixed(2)},${w.hand.y.toStringAsFixed(2)} '
          'miguel=${w.miguel.frame} parts=${w.effects.liveParticles} drink=${w.shaker.drinkColour} info="${w.hud.idleText}"');
    }

    void run(String label, int n) {
      for (var i = 0; i < n; i++) {
        sim.ticks(1);
        record(label);
      }
    }

    sim.click(300, 400);
    run('start', 30);
    for (final idx in [14, 8]) {
      // vodka, then tequila
      final p = sim.findHit(sim.world.shelf.bottles[idx].clip)!;
      sim.click(p.dx, p.dy);
      run('fetch$idx', 50);
      final pb = sim.findHit(sim.world.hud.pourButton)!;
      sim.move(pb.dx, pb.dy);
      sim.press(pb.dx, pb.dy);
      run('pour$idx', 60);
      sim.release(pb.dx, pb.dy);
      run('rest$idx', 30);
    }
    // ice
    final ice = sim.findHit(sim.world.shelf.ice.mask)!;
    sim.click(ice.dx, ice.dy);
    run('ice', 50);
    final pb = sim.findHit(sim.world.hud.pourButton)!;
    sim.move(pb.dx, pb.dy);
    sim.press(pb.dx, pb.dy);
    run('iceDrop', 40);
    sim.release(pb.dx, pb.dy);
    run('iceRest', 30);
    final sb = sim.findHit(sim.world.hud.shakeButton)!;
    sim.move(sb.dx, sb.dy);
    sim.press(sb.dx, sb.dy);
    run('shake', 70);
    sim.release(sb.dx, sb.dy);
    run('shakeRest', 20);
    // lemon garnish while the drink rests
    final lemon = sim.findHit(sim.world.shelf.lemon.mask)!;
    sim.click(lemon.dx, lemon.dy);
    run('lemon', 120);
    run('serve', 450);

    return trace;
  }

  // Recorded traces contain game state and are not distributed with the source. Without one, the test still checks that the
  // playthrough is deterministic (two runs with the same seed give the same trace) and says so. To record a golden trace
  // locally after an intentional behaviour change:  RIGHTMIX_RECORD_GOLDEN=1 flutter test test/trace_test.dart
  test('scripted playthrough matches the golden trace (or is at least deterministic)', () async {
    final trace = await playthrough();
    final text = '${trace.join('\n')}\n';
    final file = File('test/golden/trace.txt');
    if (Platform.environment['RIGHTMIX_RECORD_GOLDEN'] == '1') {
      file.createSync(recursive: true);
      file.writeAsStringSync(text);
      // ignore: avoid_print
      print('recorded golden trace (${trace.length} ticks) to ${file.path}');
    } else if (file.existsSync()) {
      final expected = file.readAsStringSync().split('\n');
      final actual = text.split('\n');
      for (var i = 0; i < expected.length && i < actual.length; i++) {
        if (expected[i] != actual[i]) {
          fail('trace differs at tick $i\n expected: ${expected[i]}\n   actual: ${actual[i]}');
        }
      }
      expect(actual.length, expected.length);
    } else {
      // ignore: avoid_print
      print('NOTE: no recorded golden trace (test/golden/trace.txt is not distributed); checking determinism only. '
          'Record one with RIGHTMIX_RECORD_GOLDEN=1.');
      expect((await playthrough()).join('\n'), trace.join('\n'), reason: 'same seed must give the same trace');
    }
    // ignore: avoid_print
    print('final: ${trace.last}');
  });
}
