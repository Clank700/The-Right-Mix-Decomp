// Layering rules for the port, enforced on the import graph so a modification cannot quietly break them.
//
//   lib/game     gameplay (state machine, scoring, ingredients, effects tuning). May use lib/engine and dart:math only.
//   lib/engine   scene runtime (display list, timelines, drawing, input, audio interface). Never imports lib/game.
//   *_io.dart    the only files allowed to touch dart:io / dart:ffi (platform back ends behind conditional imports).
//   main.dart    the only file allowed to import Flutter widgets; the engine may use package:flutter/services.dart
//                (asset bundle, platform channels) but no widgets; lib/game may use no Flutter package at all.
//   game/model, game/config   pure Dart: no engine import at all (unit-testable without a scene).
//
// What this does NOT prove: that game logic is independent of the scene graph. The phases drive clips directly (Miguel's
// frame number is part of the timing, as in the original), so "simulation" here means "runs headless on the scene graph
// without a renderer, audio device or Flutter widgets" - which the differential and golden-trace tests rely on.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'diff_support.dart';
import 'sim_helpers.dart';

List<File> dartFiles(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

List<String> importsOf(File f) => RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true)
    .allMatches(f.readAsStringSync())
    .map((m) => m.group(1)!)
    .toList();

String norm(String p) => p.replaceAll('\\', '/');

void main() {
  final game = dartFiles('lib/game');
  final engine = dartFiles('lib/engine');

  test('lib/game imports only the engine barrel, dart:math and other game files', () {
    final bad = <String>[];
    for (final f in game) {
      for (final i in importsOf(f)) {
        final ok = i == 'dart:math' || i.endsWith('engine/engine.dart') || !i.contains(':') && !i.contains('engine/');
        if (!ok) bad.add('${norm(f.path)} imports $i');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('lib/engine never imports lib/game', () {
    final bad = [
      for (final f in engine)
        for (final i in importsOf(f))
          if (i.contains('/game/') || i.startsWith('../game')) '${norm(f.path)} imports $i'
    ];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('dart:io / dart:ffi appear only in *_io.dart platform back ends', () {
    final bad = <String>[];
    for (final f in [...game, ...engine, File('lib/main.dart')]) {
      final name = norm(f.path);
      for (final i in importsOf(f)) {
        if ((i == 'dart:io' || i == 'dart:ffi') && !name.endsWith('_io.dart')) bad.add('$name imports $i');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no Flutter in lib/game; no Flutter widgets in lib/engine (services only); dart:ui only in the engine', () {
    final bad = <String>[];
    for (final f in game) {
      for (final i in importsOf(f)) {
        if (i.startsWith('package:flutter/')) bad.add('${norm(f.path)} imports $i');
        if (i == 'dart:ui') bad.add('${norm(f.path)} imports dart:ui');
      }
    }
    for (final f in engine) {
      for (final i in importsOf(f)) {
        if (i.startsWith('package:flutter/') && i != 'package:flutter/services.dart') {
          bad.add('${norm(f.path)} imports $i');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('game/model and game/config are pure Dart (no engine import)', () {
    final bad = <String>[];
    for (final f in [...dartFiles('lib/game/model'), ...dartFiles('lib/game/config')]) {
      for (final i in importsOf(f)) {
        if (i.contains('engine') || i.startsWith('package:')) bad.add('${norm(f.path)} imports $i');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('the game runs headless: a full round plays with no renderer, audio device or widgets', () async {
    final sim = await Sim.create(random: ParkMiller(5));
    sim.ticks(5);
    (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
    sim.world.shelf.bottles[14].clip.onPress!();
    sim.ticks(60);
    expect(sim.world.hand.holdingItem, isTrue);
    expect(sim.audio.log, isNotEmpty); // sounds went to the recording back end, nothing was played
  });
}
