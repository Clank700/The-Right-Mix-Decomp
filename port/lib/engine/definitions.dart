import 'dart:ui' as ui;

import 'color_transform.dart';
import 'geometry.dart';

enum FillKind { solid, linear, radial, bitmap }

class FillSpec {
  final FillKind kind;
  final List<int>? color; // solid
  final Matrix2D? matrix; // gradient / bitmap (maps style space -> shape px)
  final List<List<num>>? stops; // [ratio, r, g, b, a]
  final double focal;
  final int bitmapId;
  final bool smooth;
  final bool repeat;
  ui.Shader? _shader;

  FillSpec.solid(this.color)
      : kind = FillKind.solid,
        matrix = null,
        stops = null,
        focal = 0,
        bitmapId = 0,
        smooth = false,
        repeat = false;

  FillSpec.gradient(this.kind, this.matrix, this.stops, this.focal)
      : color = null,
        bitmapId = 0,
        smooth = false,
        repeat = false;

  FillSpec.bitmap(this.bitmapId, this.matrix, this.smooth, this.repeat)
      : kind = FillKind.bitmap,
        color = null,
        stops = null,
        focal = 0;

  factory FillSpec.fromJson(Map<String, dynamic> j) {
    switch (j['t']) {
      case 's':
        return FillSpec.solid((j['c'] as List).cast<int>());
      case 'lg':
        return FillSpec.gradient(FillKind.linear, Matrix2D.fromJson(j['m']), _stops(j['stops']), 0);
      case 'rg':
        return FillSpec.gradient(
            FillKind.radial, Matrix2D.fromJson(j['m']), _stops(j['stops']), ((j['focal'] ?? 0) as num).toDouble());
      default:
        return FillSpec.bitmap(j['id'] as int, Matrix2D.fromJson(j['m']), j['smooth'] as bool, j['repeat'] as bool);
    }
  }

  static List<List<num>> _stops(List<dynamic> s) => s.map((e) => (e as List).cast<num>()).toList();

  /// Shader for gradients / bitmaps (colour transforms are applied through a ColorFilter by the caller).
  ui.Shader? shader(Map<int, ui.Image> images) {
    if (_shader != null) return _shader;
    switch (kind) {
      case FillKind.solid:
        return null;
      case FillKind.linear:
      case FillKind.radial:
        final colors = <ui.Color>[];
        final pos = <double>[];
        for (final s in stops!) {
          pos.add(s[0] / 255.0);
          colors.add(ui.Color.fromARGB(s[4].toInt(), s[1].toInt(), s[2].toInt(), s[3].toInt()));
        }
        if (kind == FillKind.linear) {
          _shader = ui.Gradient.linear(const ui.Offset(-16384, 0), const ui.Offset(16384, 0), colors, pos,
              ui.TileMode.clamp, matrix!.toMatrix4());
        } else {
          _shader = ui.Gradient.radial(ui.Offset.zero, 16384, colors, pos, ui.TileMode.clamp, matrix!.toMatrix4(),
              focal == 0 ? null : ui.Offset(focal * 16384, 0), 0);
        }
        return _shader;
      case FillKind.bitmap:
        final img = images[bitmapId];
        if (img == null) return null;
        final tile = repeat ? ui.TileMode.repeated : ui.TileMode.clamp;
        _shader = ui.ImageShader(img, tile, tile, matrix!.toMatrix4(),
            filterQuality: smooth ? ui.FilterQuality.high : ui.FilterQuality.none);
        return _shader;
    }
  }
}

class StrokeSpec {
  final double width;
  final List<int> color;
  StrokeSpec(this.width, this.color);
}

class ShapeOp {
  final ui.Path path;
  final FillSpec? fill;
  final StrokeSpec? stroke;
  ShapeOp(this.path, this.fill, this.stroke);
}

ui.Path pathFromCmds(List<dynamic> c) {
  final p = ui.Path();
  var i = 0;
  while (i < c.length) {
    final op = c[i] as int;
    switch (op) {
      case 0:
        p.moveTo((c[i + 1] as num).toDouble(), (c[i + 2] as num).toDouble());
        i += 3;
        break;
      case 1:
        p.lineTo((c[i + 1] as num).toDouble(), (c[i + 2] as num).toDouble());
        i += 3;
        break;
      case 2:
        p.quadraticBezierTo((c[i + 1] as num).toDouble(), (c[i + 2] as num).toDouble(),
            (c[i + 3] as num).toDouble(), (c[i + 4] as num).toDouble());
        i += 5;
        break;
      default:
        p.close();
        i += 1;
    }
  }
  return p;
}

abstract class CharDef {}

class ShapeDef extends CharDef {
  final List<ShapeOp> ops;
  final ui.Rect bounds;
  final bool isText;
  ShapeDef(this.ops, this.bounds, this.isText);

  /// True when [p] (shape-local px) lies inside any filled area.
  bool hit(ui.Offset p) {
    // Static text is hit-tested by its bounding box, which makes text buttons much easier to tap.
    if (isText) return bounds.contains(p);
    for (final op in ops) {
      if (op.fill != null && op.path.contains(p)) return true;
    }
    return false;
  }
}

class PlaceCmd {
  final int depth;
  final int? charId;
  final Matrix2D? matrix;
  final ColorTransform? colorTransform;
  final int? ratio;
  final String? name;
  final int? clipDepth;
  final bool move;
  final bool hasClipActions;
  final int? remove;
  PlaceCmd(this.depth, this.charId, this.matrix, this.colorTransform, this.ratio, this.name, this.clipDepth, this.move,
      this.hasClipActions, this.remove);

  factory PlaceCmd.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('rm')) {
      return PlaceCmd(j['rm'] as int, null, null, null, null, null, null, false, false, j['rm'] as int);
    }
    return PlaceCmd(
      j['d'] as int,
      j['c'] as int?,
      j['m'] == null ? null : Matrix2D.fromJson(j['m']),
      j['x'] == null ? null : ColorTransform.fromJson(j['x']),
      j['r'] as int?,
      j['n'] as String?,
      j['cd'] as int?,
      j['mv'] != null,
      j['clip'] != null,
      null,
    );
  }
}

class SoundCue {
  final int soundId;
  final bool stop;
  final int loops;

  /// Asset to play instead of the sound's own file: a variant with the cue's volume envelope baked in.
  final String? file;
  SoundCue(this.soundId, this.stop, this.loops, [this.file]);
}

class FrameDef {
  final List<PlaceCmd> cmds;

  /// null, 'stop' (a bare stop();), 'nop', or 'script' (needs a registered handler).
  final String? scriptKind;
  final List<SoundCue> sounds;
  FrameDef(this.cmds, this.scriptKind, this.sounds);

  factory FrameDef.fromJson(Map<String, dynamic> j) => FrameDef(
        ((j['cmds'] ?? const []) as List).map((e) => PlaceCmd.fromJson(e as Map<String, dynamic>)).toList(),
        j['a'] as String?,
        ((j['snd'] ?? const []) as List)
            .map((e) => SoundCue(e['id'] as int, e['stop'] as bool, e['loops'] as int, e['f'] as String?))
            .toList(),
      );
}

class SpriteDef extends CharDef {
  final int id;
  final int nframes;
  final List<FrameDef> frames;
  final Map<String, int> labels;
  SpriteDef(this.id, this.nframes, this.frames, this.labels);
}

class ButtonRec {
  final int charId;
  final int depth;
  final Matrix2D matrix;
  final ColorTransform colorTransform;
  ButtonRec(this.charId, this.depth, this.matrix, this.colorTransform);
}

class ButtonDef extends CharDef {
  final int id;
  final Map<String, List<ButtonRec>> states;
  ButtonDef(this.id, this.states);
}

class FontDef extends CharDef {
  final String name;
  final int em;
  final Map<int, int> codeToGlyph;
  final List<ui.Path> glyphs;
  final List<int> adv;
  final int ascent, descent, leading;
  FontDef(this.name, this.em, this.codeToGlyph, this.glyphs, this.adv, this.ascent, this.descent, this.leading);
}

class EditDef extends CharDef {
  final ui.Rect bounds;
  final bool wrap, multiline, readonly;
  final int? fontId;
  final double height;
  final List<int> color;
  final int align; // 0 left, 1 right, 2 centre, 3 justify
  final double leftMargin, rightMargin, indent, leading;
  final String initialText;
  EditDef(this.bounds, this.wrap, this.multiline, this.readonly, this.fontId, this.height, this.color, this.align,
      this.leftMargin, this.rightMargin, this.indent, this.leading, this.initialText);
}

class BitmapDef extends CharDef {}

class SoundDef extends CharDef {
  final String file;
  SoundDef(this.file);
}
