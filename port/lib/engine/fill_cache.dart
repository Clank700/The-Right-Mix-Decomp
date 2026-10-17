import 'dart:math' as math;
import 'dart:ui' as ui;

import 'color_transform.dart';
import 'definitions.dart';
import 'library.dart';

/// Renders big gradient / bitmap fills once into a texture and draws that texture afterwards.
///
/// A full-screen radial gradient or photo-style fill is expensive for the GPU (every pixel runs the fill shader, every
/// frame): measured on a Radeon RX 570 at 1080p, the end-card curtain (a few of these fills moving down the screen) cost
/// 24 ms per frame once smooth motion made it move on every display frame. As a texture it is a plain blit.
///
/// Only axis-aligned, un-rotated draws of large fills are cached, with an unchanged colour or just an alpha change; the
/// texture is at most [maxTexelsPerUnit] texels per stage unit (gradients and the game's small bitmaps lose nothing at
/// that size), and the whole cache is bounded by [maxBytes]. Everything else is painted directly as before.
class FillTextureCache {
  static bool enabled = true;

  /// Physical pixels per logical pixel of the surface being painted (set by [Stage.paint]).
  static double devicePixelRatio = 1;

  /// Smallest filled area (physical pixels) worth caching.
  static const int minPixels = 120000;
  static const double maxTexelsPerUnit = 2.5;
  static const int maxBytes = 96 << 20;

  static final Expando<_Entry> _byOp = Expando<_Entry>();
  static final List<_Entry> _used = [];
  static int _bytes = 0;

  /// Textures currently held (diagnostics / tests).
  static int get count => _used.length;
  static int get bytes => _bytes;

  static void clear() {
    for (final e in _used) {
      e.image?.dispose();
      e.image = null;
    }
    _used.clear();
    _bytes = 0;
  }

  /// Draw [op] from its texture if that is worthwhile and exact enough; false means "paint it directly".
  static bool tryDraw(ui.Canvas canvas, ShapeOp op, Library lib, ColorTransform eff, void Function(ui.Canvas, ShapeOp) paintDirect) {
    final fill = op.fill;
    if (!enabled || fill == null || fill.kind == FillKind.solid) return false;
    final alphaOnly = eff.ra == 1 && eff.ga == 1 && eff.ba == 1 && eff.rb == 0 && eff.gb == 0 && eff.bb == 0 && eff.ab == 0;
    if (!alphaOnly) return false;
    final m = canvas.getTransform();
    if (m[1].abs() > 1e-6 || m[4].abs() > 1e-6 || m[0] <= 0 || m[5] <= 0) return false; // rotated / skewed / flipped
    final e = _byOp[op] ??= _Entry(op.path.getBounds().inflate(1.5));
    final devW = e.bounds.width * m[0] * devicePixelRatio, devH = e.bounds.height * m[5] * devicePixelRatio;
    if (devW * devH < minPixels) return false;
    final sx = math.min(m[0] * devicePixelRatio, maxTexelsPerUnit), sy = math.min(m[5] * devicePixelRatio, maxTexelsPerUnit);
    final w = (e.bounds.width * sx).ceil(), h = (e.bounds.height * sy).ceil();
    if (w < 2 || h < 2 || w > 8192 || h > 8192) return false;
    var img = e.image;
    if (img == null || (e.sx / sx - 1).abs() > 0.15 || (e.sy / sy - 1).abs() > 0.15) {
      if (img != null) {
        _bytes -= e.byteSize;
        img.dispose();
        _used.remove(e);
      }
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.scale(w / e.bounds.width, h / e.bounds.height);
      c.translate(-e.bounds.left, -e.bounds.top);
      paintDirect(c, op);
      final pic = rec.endRecording();
      img = pic.toImageSync(w, h);
      pic.dispose();
      e
        ..image = img
        ..sx = sx
        ..sy = sy
        ..byteSize = w * h * 4;
      _bytes += e.byteSize;
      _used.add(e);
      while (_bytes > maxBytes && _used.length > 1) {
        final old = _used.removeAt(0);
        old.image?.dispose();
        old.image = null;
        _bytes -= old.byteSize;
      }
    } else {
      // most recently used goes last
      if (!identical(_used.isEmpty ? null : _used.last, e)) {
        _used.remove(e);
        _used.add(e);
      }
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.low;
    if (eff.aa != 1) paint.color = ui.Color.fromRGBO(255, 255, 255, eff.aa.clamp(0.0, 1.0));
    canvas.drawImageRect(img, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), e.bounds, paint);
    return true;
  }
}

class _Entry {
  final ui.Rect bounds;
  ui.Image? image;
  double sx = 0, sy = 0;
  int byteSize = 0;
  _Entry(this.bounds);
}
