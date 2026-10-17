// Differential harness, Dart side.
//
// Replays the scenarios in tools/diff/scenarios*.json against the Dart port using the same deterministic RNG and the
// same input vocabulary as the instrumented ORIGINAL SWF (tools/diff/make_probe.py), and writes one state line per
// frame to ../build/diff/dart_<scenario>.txt in exactly the format the original prints with trace().
// tools/diff/run_diff.py then compares the two traces. This test only produces the Dart trace; the comparison is
// done by the runner so that a divergence is reported as data, not as a Dart assertion.
//
// Frame semantics (matches the original, where the game's loop runs on _root.onEnterFrame and the probe clip runs
// after it): for frame n, tick the engine once, apply the inputs scheduled for n, then record the state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'diff_support.dart';
import 'sim_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final file = Platform.environment['DIFF_SCENARIOS'] ?? '../tools/diff/scenarios.json';

  test('write Dart traces for the differential scenarios', () async {
    final scenarios = (jsonDecode(File(file).readAsStringSync())['scenarios'] as List).cast<Map<String, dynamic>>();
    Directory('../build/diff').createSync(recursive: true);
    for (final sc in scenarios) {
      final rng = ParkMiller(sc['seed'] as int);
      final sim = await Sim.create(random: rng);
      final ops = <int, List<Object>>{};
      for (final e in sc['ops'] as List) {
        ops.putIfAbsent(e[0] as int, () => []).add(e[1] as Object);
      }
      final out = StringBuffer();
      for (var n = 1; n <= (sc['frames'] as int); n++) {
        sim.stage.tick();
        for (final op in ops[n] ?? const []) {
          applyOp(sim, op);
        }
        out.writeln(stateLine(sim, n, rng));
      }
      File('../build/diff/dart_${sc['name']}.txt').writeAsStringSync(out.toString());
    }
  });
}
