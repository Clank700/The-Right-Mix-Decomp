import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'definitions.dart';
import 'geometry.dart';
import 'color_transform.dart';

class Library {
  final Map<int, CharDef> chars = {};
  final Map<String, int> exports = {};
  final Map<int, ui.Image> images = {};
  late final SpriteDef main;

  int get stageW => 600;
  int get stageH => 440;
  static const double fps = 18;

  /// Case-sensitive in SWF 7, but Flash resolves linkage identifiers case-insensitively.
  late final Map<String, int> _exportsLower = {for (final e in exports.entries) e.key.toLowerCase(): e.value};

  CharDef? byLinkage(String name) {
    final id = exports[name] ?? _exportsLower[name.toLowerCase()];
    return id == null ? null : chars[id];
  }

  int? idByLinkage(String name) => exports[name] ?? _exportsLower[name.toLowerCase()];

  static Future<Library> load(AssetBundle bundle) async {
    final text = await bundle.loadString('assets/game.json');
    final doc = jsonDecode(text) as Map<String, dynamic>;
    final lib = Library();
    (doc['exports'] as Map<String, dynamic>).forEach((k, v) => lib.exports[k] = v as int);
    final chars = doc['chars'] as Map<String, dynamic>;
    final imageLoads = <Future<void>>[];
    chars.forEach((k, v) {
      final id = int.parse(k);
      final j = v as Map<String, dynamic>;
      switch (j['k']) {
        case 'shape':
          lib.chars[id] = _shape(j);
          break;
        case 'sprite':
          lib.chars[id] = _sprite(id, j);
          break;
        case 'button':
          lib.chars[id] = _button(id, j);
          break;
        case 'font':
          lib.chars[id] = _font(j);
          break;
        case 'edit':
          lib.chars[id] = _edit(j);
          break;
        case 'bitmap':
          lib.chars[id] = BitmapDef();
          final file = j['file'] as String;
          imageLoads.add(() async {
            final data = await bundle.load('assets/$file');
            final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
            lib.images[id] = (await codec.getNextFrame()).image;
          }());
          break;
        case 'sound':
          lib.chars[id] = SoundDef(j['file'] as String);
          break;
      }
    });
    await Future.wait(imageLoads);
    lib.main = SpriteDef(
      0,
      (doc['main'] as List).length,
      (doc['main'] as List).map((e) => FrameDef.fromJson(e as Map<String, dynamic>)).toList(),
      const {},
    );
    return lib;
  }

  static ShapeDef _shape(Map<String, dynamic> j) {
    final ops = <ShapeOp>[];
    for (final o in (j['ops'] as List)) {
      final m = o as Map<String, dynamic>;
      final path = pathFromCmds(m['path'] as List);
      if (m.containsKey('fill')) {
        ops.add(ShapeOp(path, FillSpec.fromJson(m['fill'] as Map<String, dynamic>), null));
      } else {
        final s = m['stroke'] as Map<String, dynamic>;
        ops.add(ShapeOp(path, null, StrokeSpec((s['w'] as num).toDouble(), (s['c'] as List).cast<int>())));
      }
    }
    final b = (j['bounds'] as List).cast<num>();
    return ShapeDef(ops, ui.Rect.fromLTRB(b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble()),
        j['text'] == true);
  }

  static SpriteDef _sprite(int id, Map<String, dynamic> j) {
    final labels = <String, int>{};
    (j['labels'] as Map<String, dynamic>?)?.forEach((k, v) => labels[k] = v as int);
    return SpriteDef(id, j['nframes'] as int,
        (j['frames'] as List).map((e) => FrameDef.fromJson(e as Map<String, dynamic>)).toList(), labels);
  }

  static ButtonDef _button(int id, Map<String, dynamic> j) {
    final states = <String, List<ButtonRec>>{};
    (j['states'] as Map<String, dynamic>).forEach((k, v) {
      states[k] = (v as List)
          .map((r) => ButtonRec(r['c'] as int, r['d'] as int, Matrix2D.fromJson(r['m']), ColorTransform.fromJson(r['x'])))
          .toList();
    });
    return ButtonDef(id, states);
  }

  static FontDef _font(Map<String, dynamic> j) {
    final codes = (j['codes'] as List).cast<int>();
    final map = <int, int>{};
    for (var i = 0; i < codes.length; i++) {
      map[codes[i]] = i;
    }
    final glyphs = (j['glyphs'] as List).map((g) => _glyphPath(g as List)).toList();
    return FontDef(
      j['name'] as String,
      j['em'] as int,
      map,
      glyphs,
      ((j['adv'] ?? const []) as List).cast<int>(),
      (j['ascent'] ?? 0) as int,
      (j['descent'] ?? 0) as int,
      (j['leading'] ?? 0) as int,
    );
  }

  /// Glyph coordinates were written /20 by the converter; restore EM units.
  static ui.Path _glyphPath(List<dynamic> c) {
    final scaled = c.map<dynamic>((e) => e).toList();
    var i = 0;
    while (i < scaled.length) {
      final op = scaled[i] as int;
      final n = op == 3 ? 0 : (op == 2 ? 4 : 2);
      for (var k = 1; k <= n; k++) {
        scaled[i + k] = (scaled[i + k] as num).toDouble() * 20.0;
      }
      i += 1 + n;
    }
    return pathFromCmds(scaled);
  }

  static EditDef _edit(Map<String, dynamic> j) {
    final b = (j['bounds'] as List).cast<num>();
    return EditDef(
      ui.Rect.fromLTRB(b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble()),
      j['wrap'] as bool,
      j['multiline'] as bool,
      j['readonly'] as bool,
      j['font'] as int?,
      ((j['height'] ?? 12) as num).toDouble(),
      (j['color'] as List).cast<int>(),
      (j['align'] ?? 0) as int,
      ((j['lmargin'] ?? 0) as num).toDouble(),
      ((j['rmargin'] ?? 0) as num).toDouble(),
      ((j['indent'] ?? 0) as num).toDouble(),
      ((j['leading'] ?? 0) as num).toDouble(),
      (j['text'] ?? '') as String,
    );
  }
}
