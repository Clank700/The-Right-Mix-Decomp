import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

/// Renders the bar scene at 8x for tools/make_icons.py (which crops the app icon out of it). Skipped unless ICON=true:
///   flutter test test/icon_render_test.dart --dart-define=ICON=true
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render the bar for the app icon', () async {
    if (!const bool.fromEnvironment('ICON')) return;
    final sim = await Sim.create();
    sim.ticks(3);
    (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
    sim.ticks(40);
    Directory('../build/icon').createSync(recursive: true);
    File('../build/icon/bar_8x.png').writeAsBytesSync(await sim.snapshot(scale: 8));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
