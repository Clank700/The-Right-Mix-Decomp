import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Matrix2D.lerp', () {
    test('translation is linear; endpoints are exact', () {
      final a = Matrix2D(1, 0, 0, 1, 0, 0), b = Matrix2D(1, 0, 0, 1, 10, -4);
      final m = Matrix2D.lerp(a, b, 0.25);
      expect(m.tx, closeTo(2.5, 1e-9));
      expect(m.ty, closeTo(-1, 1e-9));
      expect(identical(Matrix2D.lerp(a, b, 0), a), isTrue);
      expect(identical(Matrix2D.lerp(a, b, 1), b), isTrue);
    });

    test('rotation keeps its size and takes the short way round', () {
      Matrix2D rot(double deg, double scale) {
        final r = deg * math.pi / 180;
        return Matrix2D(scale * math.cos(r), scale * math.sin(r), -scale * math.sin(r), scale * math.cos(r));
      }

      final mid = Matrix2D.lerp(rot(0, 2), rot(90, 2), 0.5);
      expect(math.sqrt(mid.a * mid.a + mid.b * mid.b), closeTo(2, 1e-9)); // no shrinking mid-way
      expect(math.atan2(mid.b, mid.a) * 180 / math.pi, closeTo(45, 1e-9));
      final wrap = Matrix2D.lerp(rot(170, 1), rot(-170, 1), 0.5); // 20 degrees apart through 180, not 340
      expect(math.atan2(wrap.b, wrap.a).abs() * 180 / math.pi, closeTo(180, 1e-9));
    });

    test('a collapsed axis falls back to a linear blend', () {
      final m = Matrix2D.lerp(Matrix2D(1, 0, 0, 0, 0, 0), Matrix2D(1, 0, 0, 1, 0, 0), 0.5);
      expect(m.d, closeTo(0.5, 1e-9));
    });
  });

  group('frame blending in the scene', () {
    test('blend 0 shows the previous tick exactly, blend 1 the current one, 0.5 something in between', () async {
      final sim = await Sim.create();
      sim.ticks(3);
      (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
      sim.ticks(20);
      sim.world.shelf.bottles[14].clip.onPress!(); // the arm starts sweeping towards the bottle
      sim.ticks(2);
      final before = await sim.snapshot(blend: 1);
      sim.ticks(1);
      final prevAgain = await sim.snapshot(blend: 0);
      final half = await sim.snapshot(blend: 0.5);
      final cur = await sim.snapshot(blend: 1);
      expect(prevAgain, equals(before), reason: 'blend 0 must reproduce the last tick pixel for pixel');
      expect(half, isNot(equals(before)));
      expect(half, isNot(equals(cur)));
      expect(cur, isNot(equals(before)));
    });

    test('game logic is not affected by painting at any blend', () async {
      final a = await Sim.create(), b = await Sim.create();
      for (var i = 0; i < 60; i++) {
        a.stage.tick();
        b.stage.tick();
        await b.snapshot(blend: (i % 10) / 10);
      }
      expect(b.world.phase, a.world.phase);
      expect(b.world.hand.x, a.world.hand.x);
    });
  });

  group('view layout', () {
    ViewOptions opts({bool integer = false, double dpr = 1, SafeInsets safe = SafeInsets.none}) =>
        ViewOptions(integerScale: integer, devicePixelRatio: dpr, safe: safe);
    const w = 600.0, h = 440.0;

    test('fit keeps the aspect ratio and centres (16:9, 21:9, 4:3, portrait)', () {
      for (final size in [ui.Size(1920, 1080), ui.Size(2520, 1080), ui.Size(1600, 1200), ui.Size(1080, 2400)]) {
        final v = computeViewTransform(size, w, h, opts());
        expect(w * v.scale, lessThanOrEqualTo(size.width + 1e-6));
        expect(h * v.scale, lessThanOrEqualTo(size.height + 1e-6));
        expect(v.offset.dx + w * v.scale / 2, closeTo(size.width / 2, 1e-6));
        expect(v.offset.dy + h * v.scale / 2, closeTo(size.height / 2, 1e-6));
        final limit = math.min(size.width / w, size.height / h);
        expect(v.scale, closeTo(limit, 1e-9)); // as large as possible
      }
    });

    test('integer scaling uses whole physical pixels (dpr 2.625: 1080 px tall -> 2x)', () {
      final v = computeViewTransform(const ui.Size(2400 / 2.625, 1080 / 2.625), w, h, opts(integer: true, dpr: 2.625));
      expect(v.scale * 2.625, 2.0);
      expect(v.offset.dx * 2.625, closeTo((v.offset.dx * 2.625).roundToDouble(), 1e-9));
    });

    test('integer scaling falls back to fit when less than 1x fits', () {
      final v = computeViewTransform(const ui.Size(400, 300), w, h, opts(integer: true));
      expect(v.scale, closeTo(math.min(400 / w, 300 / h), 1e-9));
    });

    test('safe insets: the picture stays inside them and slides only as far as needed', () {
      const safe = SafeInsets(120, 0, 0, 0); // a cutout on the left
      final v = computeViewTransform(const ui.Size(2400, 1080), w, h, opts(safe: safe));
      expect(v.offset.dx, greaterThanOrEqualTo(120));
      // plenty of room: still centred, so the cutout changes nothing
      final plain = computeViewTransform(const ui.Size(2400, 1080), w, h, opts());
      expect(v.offset.dx, closeTo(plain.offset.dx, 1e-9));
      // tight fit: pushed right and shrunk to fit the remaining width
      final tight = computeViewTransform(const ui.Size(1000, 800), w, h, opts(safe: const SafeInsets(300, 0, 0, 0)));
      expect(tight.offset.dx, greaterThanOrEqualTo(300));
      expect(tight.offset.dx + w * tight.scale, lessThanOrEqualTo(1000 + 1e-6));
    });

    test('pointer coordinates round-trip through the view transform', () async {
      final sim = await Sim.create();
      sim.stage.viewOptions = opts(integer: true, dpr: 2);
      const size = ui.Size(1000, 700);
      final p = sim.stage.toStage(const ui.Offset(500, 350), size);
      expect(p.dx, closeTo(300, 1e-6));
      expect(p.dy, closeTo(220, 1e-6));
    });
  });
}
