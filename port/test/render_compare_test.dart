import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

/// Renders sprite frames with the Flutter engine and compares them with the FFDec reference frames committed in
/// fixtures/ffdec (regenerate/verify them with tools/render/export_fixtures.py). Every frame gets a quantitative row in
/// ../build/render_report.csv; a frame fails when it exceeds the thresholds below unless it is listed in
/// test/render_known_exceptions.json (with the reason).
const double maxMeanDiff = 0.15; // mean per-pixel difference over the overlap, 0..1
const int maxBoxDelta = 2; // bounding-box width / height difference in pixels

class _Img {
  final int w, h;
  final Uint8List rgba;
  _Img(this.w, this.h, this.rgba);

  ({int x0, int y0, int x1, int y1})? bbox() {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (rgba[(y * w + x) * 4 + 3] > 16) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    return x1 < 0 ? null : (x0: x0, y0: y0, x1: x1, y1: y1);
  }
}

Future<_Img> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _Img(img.width, img.height, data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sprite frames match FFDec renderings', () async {
    if (!Directory('../fixtures/ffdec/sprites').existsSync()) {
      markTestSkipped('FFDec reference frames not present (fixtures/ffdec/sprites is generated locally: tools/render/export_fixtures.py)');
      return;
    }
    if (!File('test/render_known_exceptions.json').existsSync()) {
      markTestSkipped('test/render_known_exceptions.json (annotations of known sub-pixel differences) is not distributed; '
          'without it every antialiasing difference would be reported as a failure');
      return;
    }
    final sim = await Sim.create();
    final lib = sim.stage.lib;
    sim.stage.ignoreFrameScripts = true;
    final refRoot = Directory('../fixtures/ffdec/sprites');
    final rows = <String>['sprite,export,frame,mineW,mineH,refW,refH,dW,dH,meanDiff,status'];
    final exceptions = (jsonDecode(File('test/render_known_exceptions.json').readAsStringSync()) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    final failures = <String>[];
    String verdict(String key, bool ok) {
      if (ok) return 'pass';
      if (exceptions.containsKey(key)) return 'known-exception';
      failures.add(key);
      return 'FAIL';
    }

    final worst = <(double, String)>[];
    final dirs = <int, Directory>{};
    for (final d in refRoot.listSync().whereType<Directory>()) {
      final m = RegExp(r'DefineSprite_(\d+)').firstMatch(d.path.split(Platform.pathSeparator).last);
      if (m != null) dirs[int.parse(m.group(1)!)] = d;
    }
    for (final entry in dirs.entries) {
      final def = lib.chars[entry.key];
      if (def is! SpriteDef || def.nframes < 1) continue;
      final name = entry.value.path.split(Platform.pathSeparator).last;
      if (name.contains('__Packages') || name.contains('Defaults')) continue;
      final frames = entry.value
          .listSync()
          .whereType<File>()
          .map((f) => int.tryParse(f.path.split(Platform.pathSeparator).last.replaceAll('.png', '')))
          .whereType<int>()
          .where((f) => f >= 1 && f <= def.nframes)
          .toList()
        ..sort();
      for (final f in frames) {
        final refFile = File('${entry.value.path}/$f.png');
        if (!refFile.existsSync()) continue;
        // Build the clip and play it forward to frame f so nested timelines advance in step.
        final clip = MovieClip(lib, def, stage: sim.stage);
        clip.advanceFrame(); // the first call only clears the just-created flag
        for (var i = 1; i < f; i++) {
          clip.advanceFrame();
        }
        const w = 2400, h = 1800;
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.translate(w / 2, h / 2);
        clip.draw(canvas, ColorTransform());
        final image = await rec.endRecording().toImage(w, h);
        final mineData = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final mine = _Img(w, h, mineData);
        final ref = await _decode(refFile.readAsBytesSync());
        final mb = mine.bbox(), rb = ref.bbox();
        if (mb == null || rb == null) {
          final bothEmpty = mb == null && rb == null;
          rows.add('${entry.key},$name,$f,${mb == null ? 0 : mb.x1 - mb.x0 + 1},${mb == null ? 0 : mb.y1 - mb.y0 + 1},'
              '${rb == null ? 0 : rb.x1 - rb.x0 + 1},${rb == null ? 0 : rb.y1 - rb.y0 + 1},-,-,${bothEmpty ? 0 : 999},'
              '${verdict('${entry.key}:$f', bothEmpty)}');
          if (!(mb == null && rb == null)) worst.add((999, '${entry.key} $name f$f (one side empty)'));
          continue;
        }
        final mw = mb.x1 - mb.x0 + 1, mh = mb.y1 - mb.y0 + 1, rw = rb.x1 - rb.x0 + 1, rh = rb.y1 - rb.y0 + 1;
        // mean absolute difference over the overlap, aligning bounding-box top-left corners
        final cw = mw < rw ? mw : rw, ch = mh < rh ? mh : rh;
        var sum = 0.0;
        for (var y = 0; y < ch; y++) {
          for (var x = 0; x < cw; x++) {
            final mi = ((mb.y0 + y) * w + mb.x0 + x) * 4;
            final ri = ((rb.y0 + y) * ref.w + rb.x0 + x) * 4;
            final ma = mine.rgba[mi + 3], ra = ref.rgba[ri + 3];
            var d = (ma - ra).abs().toDouble();
            if (ma > 16 && ra > 16) {
              d += ((mine.rgba[mi] - ref.rgba[ri]).abs() + (mine.rgba[mi + 1] - ref.rgba[ri + 1]).abs() +
                      (mine.rgba[mi + 2] - ref.rgba[ri + 2]).abs()) /
                  3;
            }
            sum += d;
          }
        }
        final mean = sum / (cw * ch) / 255;
        final score = mean + ((mw - rw).abs() + (mh - rh).abs()) / 100;
        final ok = mean <= maxMeanDiff && (mw - rw).abs() <= maxBoxDelta && (mh - rh).abs() <= maxBoxDelta;
        rows.add('${entry.key},$name,$f,$mw,$mh,$rw,$rh,${mw - rw},${mh - rh},${mean.toStringAsFixed(4)},'
            '${verdict('${entry.key}:$f', ok)}');
        worst.add((score, '${entry.key} $name f$f  mine ${mw}x$mh  ref ${rw}x$rh  diff ${mean.toStringAsFixed(3)}'));
        if (score > 0.05) {
          // save side by side for inspection
          final dir = Directory('../work/compare')..createSync(recursive: true);
          File('${dir.path}/${entry.key}_f$f.mine.png').writeAsBytesSync(await _crop(mine, mb));
          File('${dir.path}/${entry.key}_f$f.ref.png').writeAsBytesSync(await _crop(ref, rb));
        }
      }
    }
    File('../build/render_report.csv')..createSync(recursive: true)..writeAsStringSync('${rows.join('\n')}\n');
    worst.sort((a, b) => b.$1.compareTo(a.$1));
    // ignore: avoid_print
    print('compared ${rows.length - 1} frames; worst 25:\n${worst.take(25).map((e) => e.$2).join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<Uint8List> _crop(_Img img, ({int x0, int y0, int x1, int y1}) b) async {
  final w = b.x1 - b.x0 + 1, h = b.y1 - b.y0 + 1;
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final si = ((b.y0 + y) * img.w + b.x0 + x) * 4;
      final di = (y * w + x) * 4;
      out.setRange(di, di + 4, img.rgba.sublist(si, si + 4));
    }
  }
  final comp = await ui.ImageDescriptor.raw(await ui.ImmutableBuffer.fromUint8List(out),
      width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888)
      .instantiateCodec();
  final frame = await comp.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
