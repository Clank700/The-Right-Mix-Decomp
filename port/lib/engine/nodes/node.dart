import 'dart:math' as math;
import 'dart:ui' as ui;

import '../color_transform.dart';
import '../geometry.dart';
import '../stage.dart';
import 'movie_clip.dart';

/// Base of everything that can sit in a display list (the equivalent of a Flash DisplayObject).
abstract class Node {
  MovieClip? parent;
  int depth = 0;
  String name = '';
  Matrix2D matrix = Matrix2D();
  ColorTransform colorTransform = ColorTransform();
  bool visible = true;
  int clipDepth = 0; // >0: this object masks every object up to this depth
  bool timelineOwned = false;

  /// Library character this object was placed from by a timeline (null for script-created objects).
  int? charId;

  Stage get stage => parent!.stage;

  // ---- ActionScript-style properties -----------------------------------------------------------
  double get x => matrix.tx;
  set x(double v) {
    if (v.isFinite) matrix.tx = v;
  }
  double get y => matrix.ty;
  set y(double v) {
    if (v.isFinite) matrix.ty = v;
  }

  // Flash keeps rotation and scale as separate properties, so a scale of 0 must not forget the rotation.
  double _lastRotation = 0; // radians, remembered while an axis is collapsed

  double get _rotRad {
    if (matrix.a != 0 || matrix.b != 0) return _lastRotation = math.atan2(matrix.b, matrix.a);
    return _lastRotation;
  }

  double get xscale => math.sqrt(matrix.a * matrix.a + matrix.b * matrix.b) * 100;
  set xscale(double pct) {
    if (!pct.isFinite) return;
    final rot = _rotRad;
    final s = pct / 100;
    matrix.a = math.cos(rot) * s;
    matrix.b = math.sin(rot) * s;
  }

  double get yscale => math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d) * 100;
  set yscale(double pct) {
    if (!pct.isFinite) return;
    final cur = math.sqrt(matrix.c * matrix.c + matrix.d * matrix.d);
    final s = pct / 100;
    if (cur == 0) {
      // Restore the y axis perpendicular to the x axis (no skew).
      final rot = _rotRad;
      matrix.c = -math.sin(rot) * s;
      matrix.d = math.cos(rot) * s;
    } else {
      matrix.c *= s / cur;
      matrix.d *= s / cur;
    }
  }

  double get rotation => _rotRad * 180 / math.pi;
  set rotation(double deg) {
    if (!deg.isFinite) return;
    final delta = (deg * math.pi / 180) - _rotRad;
    final cs = math.cos(delta), sn = math.sin(delta);
    final a = matrix.a * cs - matrix.b * sn;
    final b = matrix.a * sn + matrix.b * cs;
    final c = matrix.c * cs - matrix.d * sn;
    final d = matrix.c * sn + matrix.d * cs;
    matrix.a = a;
    matrix.b = b;
    matrix.c = c;
    matrix.d = d;
    _lastRotation = deg * math.pi / 180;
  }

  /// `_alpha` (0..100) is the alpha multiplier of the colour transform.
  double get alpha => colorTransform.aa * 100;
  set alpha(double pct) => colorTransform.aa = pct / 100;

  /// Bounds height in px in this object's parent space (approximation of `_height`).
  double get height => 0;

  void removeFromParent() => parent?.removeChild(this);

  void swapDepths(int newDepth) => parent?.swapChildDepth(this, newDepth);

  // ---- rendering -------------------------------------------------------------------------------
  /// How far between the previous tick (0) and the current one (1) the picture being painted is. Set by
  /// [Stage.paint] around a paint; 1 draws the current state exactly (no smoothing).
  static double blend = 1;

  /// Position/size at the start of the latest tick, kept so a paint between ticks can blend towards [matrix].
  Matrix2D? _prevMatrix;
  double _prevAlpha = 1;

  /// Remember the current state as "the previous tick". Objects that were hidden then, or that are created later,
  /// have no earlier state and are drawn where they are.
  void snapshotForBlend() {
    if (visible) {
      final p = _prevMatrix;
      if (p == null) {
        _prevMatrix = matrix.clone();
      } else {
        p
          ..a = matrix.a
          ..b = matrix.b
          ..c = matrix.c
          ..d = matrix.d
          ..tx = matrix.tx
          ..ty = matrix.ty;
      }
      _prevAlpha = colorTransform.aa;
    } else {
      _prevMatrix = null;
    }
  }

  /// Position/size this object had at the start of the latest tick, or null when it must be drawn where it is now.
  Matrix2D? get blendStart => _prevMatrix;

  /// No object in this game legitimately moves this far in one 1/18 s step (the arm's first sweep is ~330 px);
  /// anything further is a jump that was not marked with [breakBlend], and is drawn without blending.
  static const double maxBlendTravel = 450;

  /// The next paint(s) draw this object where it is now instead of blending from where it was at the start of the
  /// tick. Call it when code moves an object discontinuously (snapped back to its shelf, reset, teleported); it lasts
  /// until the next tick starts.
  void breakBlend() {
    _prevMatrix = null;
    debugOnBreak?.call(this);
  }

  /// Test hook: told whenever [breakBlend] is called.
  static void Function(Node)? debugOnBreak;

  /// Where the object is drawn for [t] between the previous tick (0) and the current one (1).
  Matrix2D renderMatrix(double t) {
    final prev = _prevMatrix;
    if (t >= 1 || prev == null) return matrix;
    final dx = matrix.tx - prev.tx, dy = matrix.ty - prev.ty;
    if (dx * dx + dy * dy > maxBlendTravel * maxBlendTravel) return matrix;
    return Matrix2D.lerp(prev, matrix, t);
  }

  /// A replacement object (same symbol placed again at the same depth) continues from what it replaces.
  void inheritBlendFrom(Node old) {
    _prevMatrix = old._prevMatrix?.clone(); // how `old` looked at the start of this tick
    _prevAlpha = old._prevAlpha;
  }

  void draw(ui.Canvas canvas, ColorTransform parentCx) {
    if (!visible) return;
    var cx = colorTransform;
    final m = renderMatrix(blend);
    if (blend < 1 && !identical(m, matrix) && _prevAlpha != cx.aa) {
      cx = cx.clone()..aa = _prevAlpha + (cx.aa - _prevAlpha) * blend;
    }
    final eff = cx.concat(parentCx);
    if (eff.aa <= 0 && eff.ab <= 0) return;
    canvas.save();
    canvas.transform(m.toMatrix4());
    drawContent(canvas, eff);
    canvas.restore();
  }

  void drawContent(ui.Canvas canvas, ColorTransform eff);

  // ---- interaction -----------------------------------------------------------------------------
  /// True when [p] (this object's local px) touches any filled area of this object or its descendants.
  bool hitShape(ui.Offset p) => false;

  /// Topmost mouse-aware object under [p] (given in the parent's coordinate space).
  Node? hitInteractive(ui.Offset p) => null;

  bool get isInteractive => false;

  /// Local-space version of [p] for this display object.
  ui.Offset toLocal(ui.Offset p) {
    final inv = matrix.inverse();
    return inv == null ? p : inv.apply(p);
  }
}
