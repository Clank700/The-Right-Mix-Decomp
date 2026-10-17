import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 2x3 affine matrix as stored in SWF: x' = a*x + c*y + tx, y' = b*x + d*y + ty.
class Matrix2D {
  double a, b, c, d, tx, ty;

  Matrix2D([this.a = 1, this.b = 0, this.c = 0, this.d = 1, this.tx = 0, this.ty = 0]);

  factory Matrix2D.fromJson(List<dynamic> j) => Matrix2D(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        (j[2] as num).toDouble(),
        (j[3] as num).toDouble(),
        (j[4] as num).toDouble(),
        (j[5] as num).toDouble(),
      );

  Matrix2D clone() => Matrix2D(a, b, c, d, tx, ty);

  Float64List toMatrix4() {
    final m = Float64List(16);
    m[0] = a;
    m[1] = b;
    m[4] = c;
    m[5] = d;
    m[10] = 1;
    m[12] = tx;
    m[13] = ty;
    m[15] = 1;
    return m;
  }

  /// this ∘ other : first apply [other], then this.
  Matrix2D multiply(Matrix2D o) => Matrix2D(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.tx + c * o.ty + tx,
        b * o.tx + d * o.ty + ty,
      );

  Matrix2D? inverse() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12) return null;
    final ia = d / det, ib = -b / det, ic = -c / det, id = a / det;
    return Matrix2D(ia, ib, ic, id, -(ia * tx + ic * ty), -(ib * tx + id * ty));
  }

  /// True when going from `this` to [to] in one step looks like a cut rather than motion: it moves further than
  /// [maxMove] px or turns an axis by more than [maxTurn] radians.
  bool isJumpTo(Matrix2D to, {double maxMove = 100, double maxTurn = 1.0}) {
    final dx = to.tx - tx, dy = to.ty - ty;
    if (dx * dx + dy * dy > maxMove * maxMove) return true;
    if ((a != 0 || b != 0) && (to.a != 0 || to.b != 0)) {
      var d = math.atan2(to.b, to.a) - math.atan2(b, a);
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      if (d.abs() > maxTurn) return true;
    }
    return false;
  }

  /// Blend from [from] to [to] (t in 0..1). Each axis vector is interpolated by length and angle (shortest way round),
  /// so a rotating object keeps its size instead of shrinking through the middle of the step; an axis that collapses
  /// to zero length falls back to a plain linear blend.
  static Matrix2D lerp(Matrix2D from, Matrix2D to, double t) {
    if (t <= 0) return from;
    if (t >= 1) return to;
    double mix(double p, double q) => p + (q - p) * t;
    final r0a = math.sqrt(from.a * from.a + from.b * from.b), r1a = math.sqrt(to.a * to.a + to.b * to.b);
    final r0c = math.sqrt(from.c * from.c + from.d * from.d), r1c = math.sqrt(to.c * to.c + to.d * to.d);
    if (r0a < 1e-9 || r1a < 1e-9 || r0c < 1e-9 || r1c < 1e-9) {
      return Matrix2D(mix(from.a, to.a), mix(from.b, to.b), mix(from.c, to.c), mix(from.d, to.d), mix(from.tx, to.tx),
          mix(from.ty, to.ty));
    }
    double turn(double a0, double a1) {
      var d = a1 - a0;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      return a0 + d * t;
    }

    final angA = turn(math.atan2(from.b, from.a), math.atan2(to.b, to.a));
    final angC = turn(math.atan2(from.d, from.c), math.atan2(to.d, to.c));
    final ra = mix(r0a, r1a), rc = mix(r0c, r1c);
    return Matrix2D(ra * math.cos(angA), ra * math.sin(angA), rc * math.cos(angC), rc * math.sin(angC),
        mix(from.tx, to.tx), mix(from.ty, to.ty));
  }

  ui.Offset apply(ui.Offset p) => ui.Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);
}
