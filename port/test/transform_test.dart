import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

class _D extends Node {
  @override
  void drawContent(canvas, eff) {}
}

void main() {
  test('rotation / yscale keep the axes perpendicular, even across a zero scale', () {
    final d = _D();
    // The barman's arm starts with yscale 0 (hand on the arm's origin) and is rotated before it is stretched.
    d.yscale = 0;
    for (final step in [(313.0, 1778.0), (317.0, 1900.0), (313.0, 1774.0), (500.0, 900.0), (-20.0, 2500.0)]) {
      d.rotation = step.$1;
      d.yscale = step.$2;
      final m = d.matrix;
      final dot = m.a * m.c + m.b * m.d;
      // ignore: avoid_print
      print('rot=${step.$1} ys=${step.$2}: a=${m.a.toStringAsFixed(3)} b=${m.b.toStringAsFixed(3)} '
          'c=${m.c.toStringAsFixed(3)} d=${m.d.toStringAsFixed(3)} dot=${dot.toStringAsFixed(4)}');
      expect(dot.abs(), lessThan(1e-6));
    }
    expect(Matrix2D().a, 1);
  });
}
