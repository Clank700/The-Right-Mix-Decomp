import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';
import 'package:the_right_mix/game/world.dart';

import 'diff_support.dart';
import 'sim_helpers.dart';

/// Smooth motion must never draw an object sliding across a jump (a cut, a snap, a reset, a new or removed object, or
/// a gap in time), and must never change what the 18 Hz simulation does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Node> allNodes(Node root) {
    final out = <Node>[root];
    if (root is MovieClip) {
      for (final c in root.children.values) {
        out.addAll(allNodes(c));
      }
    }
    return out;
  }

  double travel(Node n) {
    final p = n.blendStart;
    return p == null ? 0 : math.sqrt(math.pow(n.matrix.tx - p.tx, 2) + math.pow(n.matrix.ty - p.ty, 2));
  }

  List<Map<String, dynamic>> scenarios(List<String> names) {
    final all = (jsonDecode(File('../tools/diff/scenarios.json').readAsStringSync())['scenarios'] as List)
        .cast<Map<String, dynamic>>();
    return [for (final n in names) all.firstWhere((s) => s['name'] == n)];
  }

  /// Replays a differential scenario; [afterTick] runs after each tick and its inputs (like a paint between ticks would).
  Future<Sim> replay(Map<String, dynamic> sc, void Function(Sim sim, int frame) afterTick) async {
    final sim = await Sim.create(random: ParkMiller(sc['seed'] as int));
    final ops = <int, List<Object>>{};
    for (final e in sc['ops'] as List) {
      ops.putIfAbsent(e[0] as int, () => []).add(e[1] as Object);
    }
    for (var n = 1; n <= (sc['frames'] as int); n++) {
      sim.stage.tick();
      for (final op in ops[n] ?? const []) {
        applyOp(sim, op);
      }
      afterTick(sim, n);
    }
    return sim;
  }

  Future<Sim> started() async {
    final sim = await Sim.create();
    sim.ticks(3);
    (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
    sim.ticks(10);
    return sim;
  }

  group('no blending across cuts (whole games replayed)', () {
    const names = [
      'restart_after_end', 'garnish_then_restart', 'pick_spam', 'shake_hold_sweep', 'score_top_8300',
      'restart_after_milkshake', 'ice_twice', 'fuzz_03', 'fuzz_07', 'fuzz_12', 'shake_5_milkshake', 'cap_full_pick_other',
      'restart_mid_shake', 'restart_midway'
    ];

    test('timeline-driven objects never blend over more than a tween step; free bottles never over a jump', () async {
      final bad = <String>[];
      var blended = 0, ticks = 0;
      for (final sc in scenarios(names)) {
        await replay(sc, (sim, n) {
          ticks++;
          final bottles = {for (final b in sim.world.shelf.bottles) b.clip: b};
          for (final node in allNodes(sim.stage.root)) {
            if (!node.visible) continue;
            final d = travel(node);
            if (d > 0) blended++;
            if (node.timelineOwned && d > 100) bad.add('${sc['name']}@$n timeline node ${node.name}: ${d.toStringAsFixed(0)} px');
            final b = bottles[node];
            if (b != null && !b.inHand && d > 60) bad.add('${sc['name']}@$n free bottle ${node.name}: ${d.toStringAsFixed(0)} px');
            if (d > 400) bad.add('${sc['name']}@$n ${node.name}: ${d.toStringAsFixed(0)} px');
          }
        });
      }
      expect(bad, isEmpty, reason: bad.take(20).join('\n'));
      expect(blended, greaterThan(ticks), reason: 'blending must still happen for ordinary motion');
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  group('frame-by-frame art (a different drawing each frame) is never blended', () {
    test('no object blends from a different drawing; a clip whose drawings changed is held whole', () async {
      final bad = <String>[];
      var swaps = 0, heldClips = 0;
      for (final sc in scenarios(['restart_after_end', 'score_low', 'score_edge_2000_exact', 'score_top_8300', 'shake_5_milkshake',
          'garnish_then_restart', 'score_edge_5000_exact'])) {
        late Map<MovieClip, Map<int, Node>> before;
        Map<MovieClip, Map<int, Node>> snapshot(Node root) {
          final out = <MovieClip, Map<int, Node>>{};
          for (final n in allNodes(root)) {
            if (n is MovieClip) out[n] = {for (final e in n.children.entries) e.key: e.value};
          }
          return out;
        }

        final sim = await Sim.create(random: ParkMiller(sc['seed'] as int));
        final ops = <int, List<Object>>{};
        for (final e in sc['ops'] as List) {
          ops.putIfAbsent(e[0] as int, () => []).add(e[1] as Object);
        }
        for (var n = 1; n <= (sc['frames'] as int); n++) {
          before = snapshot(sim.stage.root);
          sim.stage.tick();
          for (final clip in allNodes(sim.stage.root).whereType<MovieClip>()) {
            final was = before[clip];
            if (was == null) continue;
            var drawingsChanged = false;
            for (final e in clip.children.entries) {
              final old = was[e.key];
              if (e.value.timelineOwned && (old == null || old.charId != e.value.charId)) {
                drawingsChanged = true;
                swaps++;
                // a node that is not the same drawing as before must have no previous state
                if (e.value.blendStart != null) bad.add('${sc['name']}@$n ${clip.name}: depth ${e.key} blends from another drawing');
              }
            }
            for (final key in was.keys) {
              if (!clip.children.containsKey(key) && was[key]!.timelineOwned) drawingsChanged = true; // removed
            }
            if (drawingsChanged) {
              heldClips++;
              // the whole animation this clip belongs to is held (Miguel, a finale, the hand...), not just the clip
              var top = clip;
              while (top.parent != null && top.parent!.def != null && !identical(top.parent, sim.stage.root)) {
                top = top.parent!;
              }
              for (final d in allNodes(top)) {
                if (d == top) continue;
                if (d == clip) continue;
                if ((d.renderMatrix(0.5).tx - d.matrix.tx).abs() > 1e-9 || (d.renderMatrix(0.5).ty - d.matrix.ty).abs() > 1e-9) {
                  bad.add('${sc['name']}@$n ${top.name}: ${d.name}${d.runtimeType} still blends inside an animation whose drawings changed');
                }
              }
            }
          }
          for (final op in ops[n] ?? const []) {
            applyOp(sim, op);
          }
        }
      }
      expect(bad, isEmpty, reason: bad.take(15).join('\n'));
      // ignore: avoid_print
      print('frame-by-frame audit: $swaps drawings swapped/created, $heldClips clip-ticks held whole');
      expect(swaps, greaterThan(500), reason: 'the scenarios must contain frame-by-frame animation');
      expect(heldClips, greaterThan(100));
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  group('discrete transforms', () {
    test('bottle put back on its shelf: drawn at home from the first paint, not sliding there', () async {
      final sim = await started();
      final a = sim.world.shelf.bottles[14], b = sim.world.shelf.bottles[3];
      a.clip.onPress!();
      for (var i = 0; i < 80 && !(sim.world.phase == GamePhase.rest && sim.world.hand.holdingItem); i++) {
        sim.ticks(1);
      }
      expect(a.inHand, isTrue);
      b.clip.onPress!(); // the hand brings the vodka back and fetches the other bottle
      var snapped = false;
      for (var i = 0; i < 80 && !snapped; i++) {
        final was = a.inHand;
        sim.ticks(1);
        if (was && !a.inHand) {
          snapped = true;
          for (final t in [0.0, 0.25, 0.5, 0.9]) {
            expect(a.clip.renderMatrix(t).tx, closeTo(a.homeX, 1e-6), reason: 'blend $t');
            expect(a.clip.renderMatrix(t).ty, closeTo(a.homeY, 1e-6), reason: 'blend $t');
          }
        }
      }
      expect(snapped, isTrue);
    });

    test('ice dropped into the shaker is drawn back on its shelf at once', () async {
      final sim = await started();
      final ice = sim.world.shelf.ice;
      ice.mask.onPress!();
      for (var i = 0; i < 80 && !(sim.world.phase == GamePhase.rest && sim.world.hand.holdingItem); i++) {
        sim.ticks(1);
      }
      sim.world.hud.pourButton.onPress!(); // hold pour: the ice goes into the shaker
      sim.world.mouseDown = true;
      var dropped = false;
      for (var i = 0; i < 300 && !dropped; i++) {
        final was = ice.inHand;
        sim.ticks(1);
        if (was && !ice.inHand) {
          dropped = true;
          expect(ice.clip.renderMatrix(0.5).tx, closeTo(ice.homeX, 1e-6));
          expect(ice.clip.renderMatrix(0.5).ty, closeTo(ice.homeY, 1e-6));
        }
      }
      expect(dropped, isTrue);
    });

    test('a bottle that reappears at the hand (the original\'s dropped-bottle quirk) is not slid there', () async {
      final sim = await started();
      final bottle = sim.world.shelf.bottles[5];
      // move a free bottle far in one go, the way the pour code does when it still points at a released bottle
      sim.ticks(1);
      bottle.x = bottle.homeX + 300;
      bottle.y = bottle.homeY - 120;
      sim.ticks(1);
      expect(bottle.inHand, isFalse);
      expect(bottle.clip.renderMatrix(0.5).tx, closeTo(bottle.clip.x, 1e-6));
    });

    test('objects created by script or timeline are drawn where they are', () async {
      final sim = await started();
      sim.world.phase = GamePhase.finaleInit;
      sim.ticks(1);
      final finale = sim.world.finaleClip;
      expect(finale, isNotNull);
      for (final n in allNodes(finale!)) {
        expect(n.renderMatrix(0.5), same(n.matrix), reason: 'new node ${n.name} must not blend');
      }
    });

    test('particles are drawn where they spawn; removed ones are simply gone', () async {
      final sim = await started();
      sim.world.shelf.bottles[14].clip.onPress!();
      for (var i = 0; i < 70; i++) {
        sim.ticks(1);
      }
      sim.world.hud.pourButton.onPress!();
      sim.world.mouseDown = true;
      final seen = <Node>{};
      var born = 0;
      for (var i = 0; i < 90; i++) {
        final before = allNodes(sim.stage.root).toSet();
        sim.ticks(1);
        for (final n in allNodes(sim.stage.root)) {
          if (!before.contains(n)) {
            born++;
            expect(n.renderMatrix(0.3), same(n.matrix), reason: 'new ${n.name} ${n.runtimeType}');
          }
          seen.add(n);
        }
        // everything that existed and was removed is no longer in the tree (nothing keeps drawing a ghost)
        for (final gone in before.difference(allNodes(sim.stage.root).toSet())) {
          expect(gone.parent, isNull);
        }
      }
      expect(born, greaterThan(20));
    });

    test('timeline jumps and rewinds are drawn at their destination; ordinary playback still blends', () async {
      final sim = await started();
      final miguel = sim.world.miguel;
      miguel.gotoAndStop(26);
      sim.ticks(1);
      var blendedSomething = false;
      for (var f = 27; f <= 40; f++) {
        sim.stage.root.snapshotForBlend();
        miguel.gotoAndStop(f);
        for (final n in allNodes(miguel)) {
          if (n != miguel && (n.renderMatrix(0.5).tx - n.matrix.tx).abs() > 1e-6) blendedSomething = true;
        }
      }
      expect(blendedSomething, isTrue, reason: 'one frame at a time still blends');
      for (final target in [100, 64, 25, 300, 41, 2, 200]) {
        sim.stage.root.snapshotForBlend();
        miguel.gotoAndStop(target);
        for (final n in allNodes(miguel)) {
          if (n == miguel) continue;
          expect(n.renderMatrix(0.5).tx, closeTo(n.matrix.tx, 1e-9), reason: 'goto $target: ${n.name} ${n.runtimeType}');
          expect(n.renderMatrix(0.5).ty, closeTo(n.matrix.ty, 1e-9), reason: 'goto $target: ${n.name} ${n.runtimeType}');
        }
      }
    });

    test('a timeline cut (a big move between two consecutive frames) is not blended', () {
      expect(Matrix2D(1, 0, 0, 1, 0, 0).isJumpTo(Matrix2D(1, 0, 0, 1, 940, 0)), isTrue);
      expect(Matrix2D(1, 0, 0, 1, 0, 0).isJumpTo(Matrix2D(1, 0, 0, 1, 30, 20)), isFalse);
      expect(Matrix2D(1, 0, 0, 1, 0, 0).isJumpTo(Matrix2D(-1, 0, 0, -1, 0, 0)), isTrue); // a 180 degree flip
    });

    test('looping a clip back to frame 1 does not slide its parts back', () async {
      final sim = await started();
      final clip = sim.world.endCard; // a multi-frame clip
      clip.visible = true;
      var wrapped = false;
      for (var i = 0; i < 100 && !wrapped; i++) {
        final f = clip.frame;
        sim.stage.root.snapshotForBlend();
        clip.gotoAndStop(f >= clip.totalFrames ? 1 : f + 1);
        if (clip.frame < f) {
          wrapped = true;
          for (final n in allNodes(clip)) {
            if (n == clip) continue;
            expect(n.renderMatrix(0.5).tx, closeTo(n.matrix.tx, 1e-9), reason: '${n.name} after rewind');
            expect(n.renderMatrix(0.5).ty, closeTo(n.matrix.ty, 1e-9), reason: '${n.name} after rewind');
          }
        }
      }
      expect(wrapped, isTrue);
    });
  });

  group('time gaps', () {
    Future<(Sim, FrameDriver, double)> warmedUp() async {
      final sim = await Sim.create();
      final driver = FrameDriver(sim.stage, 1 / 18);
      sim.ticks(3);
      (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
      sim.world.shelf.bottles[14].clip.onPress!();
      var t = 0.0;
      for (var i = 0; i < 40; i++) {
        t += 1 / 60;
        driver.frame(Duration(microseconds: (t * 1e6).round()));
      }
      return (sim, driver, t);
    }

    Duration at(double t) => Duration(microseconds: (t * 1e6).round());

    test('pause/resume: nothing is blended across the pause', () async {
      final (sim, driver, t0) = await warmedUp();
      var t = t0;
      driver.suspend();
      t += 600;
      final steps = driver.frame(at(t));
      expect(steps, 0, reason: 'the first frame after a resume only records the time');
      expect(driver.stepper.alpha, 0);
      for (final n in allNodes(sim.stage.root)) {
        expect(n.renderMatrix(driver.blend(true)), same(n.matrix), reason: '${n.name} blended across the pause');
      }
      var ran = 0;
      for (var i = 0; i < 12; i++) {
        t += 1 / 60;
        ran += driver.frame(at(t));
      }
      expect(ran, inInclusiveRange(2, 5), reason: 'ticking resumes at 18 per second');
    });

    test('a long stall (window drag, sleep) is dropped, not replayed or blended', () async {
      final (sim, driver, t0) = await warmedUp();
      final handBefore = sim.world.hand.x;
      final ran = driver.frame(at(t0 + 8)); // eight seconds without a frame
      expect(ran, 0);
      expect(sim.world.hand.x, handBefore, reason: 'no catch-up');
      for (final n in allNodes(sim.stage.root)) {
        expect(n.renderMatrix(driver.blend(true)), same(n.matrix));
      }
    });

    test('a slow frame inside the limit runs its ticks but blends only across the last one', () async {
      final (sim, driver, t0) = await warmedUp();
      final steps = driver.frame(at(t0 + 0.2)); // 200 ms hitch: 3-4 ticks at once
      expect(steps, inInclusiveRange(3, 4));
      for (final n in allNodes(sim.stage.root)) {
        expect(travel(n), lessThanOrEqualTo(400), reason: n.name); // one tick apart, never the whole hitch
      }
    });

    test('suspend while the pointer is down in a held state does not leave a stale blend', () async {
      final (sim, driver, _) = await warmedUp();
      driver.suspend();
      for (final n in allNodes(sim.stage.root)) {
        expect(n.blendStart, isNull, reason: n.name);
      }
    });
  });

  group('window resizing', () {
    test('painting at any size leaves the blended positions and the game untouched', () async {
      final sim = await started();
      sim.world.shelf.bottles[14].clip.onPress!();
      sim.ticks(4); // mid sweep
      List<double> positions() => [
            for (final n in allNodes(sim.stage.root)) ...[n.renderMatrix(0.4).tx, n.renderMatrix(0.4).ty]
          ];
      final before = positions();
      final handBefore = sim.world.hand.x;
      for (final size in const [ui.Size(300, 200), ui.Size(1920, 1080), ui.Size(641, 477), ui.Size(1080, 2400), ui.Size(2560, 600)]) {
        sim.stage.viewOptions.integerScale = size.width > 1000;
        final rec = ui.PictureRecorder();
        sim.stage.paint(ui.Canvas(rec), size, blend: 0.4);
        rec.endRecording();
        expect(Node.blend, 1, reason: 'paint must restore the global blend');
      }
      expect(positions(), before);
      expect(sim.world.hand.x, handBefore);
    });

    test('the same blended picture at two sizes is the same picture (scaled)', () async {
      final sim = await started();
      sim.world.shelf.bottles[14].clip.onPress!();
      sim.ticks(4);
      final small = await sim.snapshot(scale: 1, blend: 0.5);
      final big = await sim.snapshot(scale: 2, blend: 0.5);
      Future<List<int>> decode(Uint8List png, {int shrink = 1}) async {
        final codec = await ui.instantiateImageCodec(png);
        final img = (await codec.getNextFrame()).image;
        final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final w = img.width;
        final ow = w ~/ shrink, oh = img.height ~/ shrink;
        final out = <int>[];
        for (var y = 0; y < oh; y++) {
          for (var x = 0; x < ow; x++) {
            for (var c = 0; c < 3; c++) {
              var sum = 0;
              for (var dy = 0; dy < shrink; dy++) {
                for (var dx = 0; dx < shrink; dx++) {
                  sum += data[(((y * shrink + dy) * w) + x * shrink + dx) * 4 + c];
                }
              }
              out.add(sum ~/ (shrink * shrink));
            }
          }
        }
        return out;
      }

      final a = await decode(small), b = await decode(big, shrink: 2);
      expect(a.length, b.length);
      var diff = 0.0;
      for (var i = 0; i < a.length; i++) {
        diff += (a[i] - b[i]).abs();
      }
      expect(diff / a.length / 255, lessThan(0.03));
    });
  });

  group('the 18 Hz simulation is untouched', () {
    test('painting at random blends and sizes, clearing blends and suspending between ticks changes no game state',
        () async {
      final rnd = math.Random(7);
      final plain = <String>[], busy = <String>[];
      for (final sc in scenarios(['restart_after_end', 'garnish_then_restart', 'shake_5_milkshake'])) {
        await replayTrace(sc, ParkMiller(sc['seed'] as int), plain, null);
        await replayTrace(sc, ParkMiller(sc['seed'] as int), busy, rnd);
      }
      expect(busy.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        if (busy[i] != plain[i]) fail('state diverged at line $i:\nplain ${plain[i]}\nbusy  ${busy[i]}');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

/// Full per-frame state trace (same format as the differential harness) of a scenario; with [rnd] set, every frame is
/// also painted at random blends and sizes and blends are randomly cleared, as an app on a 144 Hz screen with stalls would.
Future<void> replayTrace(Map<String, dynamic> sc, ParkMiller rng, List<String> out, math.Random? rnd) async {
  final sim = await Sim.create(random: rng);
  final ops = <int, List<Object>>{};
  for (final e in sc['ops'] as List) {
    ops.putIfAbsent(e[0] as int, () => []).add(e[1] as Object);
  }
  for (var n = 1; n <= (sc['frames'] as int); n++) {
    sim.stage.tick();
    for (final op in ops[n] ?? const []) {
      applyOp(sim, op);
    }
    if (rnd != null) {
      for (var k = 0; k < 3; k++) {
        final rec = ui.PictureRecorder();
        sim.stage.paint(ui.Canvas(rec), ui.Size(300 + rnd.nextInt(2000).toDouble(), 200 + rnd.nextInt(1200).toDouble()),
            blend: rnd.nextDouble());
        rec.endRecording();
      }
      if (rnd.nextInt(20) == 0) sim.stage.clearBlend();
    }
    out.add(stateLine(sim, n, rng));
  }
}
