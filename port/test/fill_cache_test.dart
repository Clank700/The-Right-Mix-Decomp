import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

/// The cached texture of a big gradient/bitmap fill must look like drawing the fill directly, and must only be used when
/// that is safe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> render(Sim sim, ShapeDef def, {required bool cache, double scale = 1, double dx = 0, double dy = 0,
      double rotate = 0, ColorTransform? cx, int w = 700, int h = 520}) async {
    FillTextureCache.enabled = cache;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    if (rotate != 0) canvas.rotate(rotate);
    paintShape(canvas, def, sim.stage.lib, cx ?? ColorTransform());
    final img = await rec.endRecording().toImage(w, h);
    return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  }

  double meanDiff(Uint8List a, Uint8List b) {
    var d = 0.0;
    for (var i = 0; i < a.length; i++) {
      d += (a[i] - b[i]).abs();
    }
    return d / a.length / 255;
  }

  // the end-card curtain: character 71 (big radial gradients)
  Future<(Sim, ShapeDef)> setup() async {
    final sim = await Sim.create();
    final def = sim.stage.lib.chars[71] as ShapeDef;
    return (sim, def);
  }

  tearDown(() {
    FillTextureCache.enabled = true;
    FillTextureCache.devicePixelRatio = 1;
    FillTextureCache.clear();
  });

  test('a cached big gradient fill looks like the direct drawing (several scales and sub-pixel positions)', () async {
    final (sim, def) = await setup();
    for (final (scale, dx, dy) in [(1.2, 300.0, 200.0), (1.2, 300.37, 200.61), (2.0, 700.0, 500.5), (0.9, 280.0, 220.25)]) {
      final w = (def.bounds.width * scale + 2 * dx).ceil().clamp(300, 1800), h = (def.bounds.height * scale + 2 * dy).ceil().clamp(300, 1400);
      FillTextureCache.clear();
      final direct = await render(sim, def, cache: false, scale: scale, dx: dx, dy: dy, w: w, h: h);
      final cached = await render(sim, def, cache: true, scale: scale, dx: dx, dy: dy, w: w, h: h);
      expect(FillTextureCache.count, greaterThan(0), reason: 'scale $scale should have used the cache');
      expect(meanDiff(direct, cached), lessThan(0.01), reason: 'scale $scale at ($dx, $dy)');
    }
  });

  test('not used when rotated, when the colour is changed, when small, or when switched off', () async {
    final (sim, def) = await setup();
    FillTextureCache.clear();
    await render(sim, def, cache: true, scale: 1.2, dx: 300, dy: 200, rotate: 0.3);
    expect(FillTextureCache.count, 0, reason: 'rotated');
    await render(sim, def, cache: true, scale: 1.2, dx: 300, dy: 200, cx: ColorTransform(0.5, 1, 1, 1, 0, 0, 0, 0));
    expect(FillTextureCache.count, 0, reason: 'tinted');
    await render(sim, def, cache: true, scale: 0.2, dx: 100, dy: 100, w: 300, h: 200);
    expect(FillTextureCache.count, 0, reason: 'too small to pay off');
    await render(sim, def, cache: false, scale: 1.2, dx: 300, dy: 200);
    expect(FillTextureCache.count, 0, reason: 'disabled');
    // alpha alone is fine and matches
    final direct = await render(sim, def, cache: false, scale: 1.2, dx: 300, dy: 200, cx: ColorTransform(1, 1, 1, 0.5, 0, 0, 0, 0), w: 1100, h: 900);
    final cached = await render(sim, def, cache: true, scale: 1.2, dx: 300, dy: 200, cx: ColorTransform(1, 1, 1, 0.5, 0, 0, 0, 0), w: 1100, h: 900);
    expect(FillTextureCache.count, greaterThan(0));
    expect(meanDiff(direct, cached), lessThan(0.01));
  });

  test('texture resolution is capped (phones) and total memory stays bounded', () async {
    final (sim, def) = await setup();
    FillTextureCache.clear();
    FillTextureCache.devicePixelRatio = 2.625;
    await render(sim, def, cache: true, scale: 2.45, dx: 100, dy: 100, w: 400, h: 300); // physical scale 6.4 > cap
    expect(FillTextureCache.count, greaterThan(0));
    final biggest = (def.bounds.width + 3) * FillTextureCache.maxTexelsPerUnit * (def.bounds.height + 3) * FillTextureCache.maxTexelsPerUnit * 4;
    expect(FillTextureCache.bytes, lessThanOrEqualTo(FillTextureCache.maxBytes));
    expect(FillTextureCache.bytes, lessThan(biggest * 6), reason: 'a few capped textures, not full-resolution ones');
  });

  test('a whole game with the cache draws the same pictures as without it', () async {
    final sim = await Sim.create();
    sim.ticks(3);
    (sim.world.introCard.child('startButton') as ButtonNode).onPress!();
    var worst = 0.0;
    for (var i = 0; i < 6; i++) {
      sim.ticks(7);
      FillTextureCache.enabled = false;
      final a = await sim.snapshot(scale: 1.5, blend: 0.5);
      FillTextureCache.enabled = true;
      final b = await sim.snapshot(scale: 1.5, blend: 0.5);
      final ia = await ui.instantiateImageCodec(a), ib = await ui.instantiateImageCodec(b);
      final ra = (await (await ia.getNextFrame()).image.toByteData())!.buffer.asUint8List();
      final rb = (await (await ib.getNextFrame()).image.toByteData())!.buffer.asUint8List();
      worst = worst < meanDiff(ra, rb) ? meanDiff(ra, rb) : worst;
    }
    expect(worst, lessThan(0.01));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
