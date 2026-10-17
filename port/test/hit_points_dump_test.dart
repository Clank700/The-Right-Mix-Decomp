// Prints stage coordinates of the controls so device tests can tap them (tools/android/verify_device.py reads this).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dump control hit points', () async {
    final sim = await Sim.create();
    sim.ticks(3);
    final w = sim.world;
    final out = <String, List<double>>{};
    void rec(String name, Object target) {
      final p = sim.findHit(target);
      if (p != null) out[name] = [p.dx, p.dy];
    }

    rec('start', w.introCard.child('startButton')!);
    (w.introCard.child('startButton') as ButtonNode).onPress!();
    sim.ticks(30);
    rec('bottle14', w.shelf.bottles[14].clip);
    rec('bottle17', w.shelf.bottles[17].clip);
    rec('ice', w.shelf.ice.mask);
    rec('pour', w.hud.pourButton);
    rec('shake', w.hud.shakeButton);
    rec('serve', w.hud.serveButton);
    Directory('../build').createSync(recursive: true);
    File('../build/hit_points.json').writeAsStringSync(jsonEncode(out));
    // ignore: avoid_print
    print(out);
    expect(out.length, 7);
    ui.Offset.zero;
  });
}
