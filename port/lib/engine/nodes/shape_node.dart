import 'dart:ui' as ui;

import '../color_transform.dart';
import '../definitions.dart';
import '../fill_cache.dart';
import '../library.dart';
import 'node.dart';

class ShapeNode extends Node {
  final ShapeDef def;
  final Library lib;
  ShapeNode(this.def, this.lib);

  @override
  double get height => def.bounds.height * yscale / 100;

  @override
  void drawContent(ui.Canvas canvas, ColorTransform eff) => paintShape(canvas, def, lib, eff);

  @override
  bool hitShape(ui.Offset p) => def.hit(p);
}

void paintShape(ui.Canvas canvas, ShapeDef def, Library lib, ColorTransform eff) {
  for (final op in def.ops) {
    final fill = op.fill;
    if (fill != null && fill.kind != FillKind.solid && FillTextureCache.tryDraw(canvas, op, lib, eff, (c, o) => _paintOp(c, o, lib, ColorTransform()))) {
      continue;
    }
    _paintOp(canvas, op, lib, eff);
  }
}

void _paintOp(ui.Canvas canvas, ShapeOp op, Library lib, ColorTransform eff) {
  final fill = op.fill;
  if (fill != null) {
    final paint = ui.Paint()..isAntiAlias = true;
    if (fill.kind == FillKind.solid) {
      paint.color = eff.apply(fill.color!);
    } else {
      final sh = fill.shader(lib.images);
      if (sh == null) return;
      paint.shader = sh;
      if (!eff.isIdentity) paint.colorFilter = eff.toFilter();
    }
    canvas.drawPath(op.path, paint);
  } else {
    final s = op.stroke!;
    final paint = ui.Paint()
      ..isAntiAlias = true
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = s.width
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..color = eff.apply(s.color);
    canvas.drawPath(op.path, paint);
  }
}
