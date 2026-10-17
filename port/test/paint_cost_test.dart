import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';
import 'sim_helpers.dart';

/// Rough CPU cost of recording one frame (the scene walk and drawing commands, not GPU rasterising). With smooth
/// motion the scene is painted at the display rate, so this has to stay well under a 120 Hz frame (8.3 ms).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('recording a frame is cheap, also mid-game with particles', () async {
    final sim = await Sim.create();
    sim.ticks(3);
    (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
    sim.world.shelf.bottles[14].clip.onPress!();
    sim.ticks(60);
    sim.world.hud.pourButton.onPress!();
    sim.world.mouseDown = true;
    sim.ticks(40); // pouring: stream + droplets + splashes alive
    final times = <double>[];
    for (var i = 0; i < 120; i++) {
      final sw = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      sim.stage.paint(ui.Canvas(rec), const ui.Size(1920, 1080), blend: (i % 4) / 4);
      rec.endRecording();
      times.add(sw.elapsedMicroseconds / 1000);
      if (i % 4 == 3) sim.ticks(1);
    }
    times.sort();
    // ignore: avoid_print
    print('frame record time ms: median ${times[60].toStringAsFixed(2)}, p95 ${times[113].toStringAsFixed(2)}, max ${times.last.toStringAsFixed(2)}; live particles ${sim.world.effects.liveParticles}');
    expect(times[113], lessThan(8.0));
  });
}
