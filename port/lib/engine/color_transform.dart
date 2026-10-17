import 'dart:ui' as ui;

/// Flash colour transform: out = in * mult + add (add in 0..255).
class ColorTransform {
  double ra, ga, ba, aa, rb, gb, bb, ab;

  ColorTransform([
    this.ra = 1,
    this.ga = 1,
    this.ba = 1,
    this.aa = 1,
    this.rb = 0,
    this.gb = 0,
    this.bb = 0,
    this.ab = 0,
  ]);

  factory ColorTransform.fromJson(List<dynamic> j) => ColorTransform(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        (j[2] as num).toDouble(),
        (j[3] as num).toDouble(),
        (j[4] as num).toDouble(),
        (j[5] as num).toDouble(),
        (j[6] as num).toDouble(),
        (j[7] as num).toDouble(),
      );

  ColorTransform clone() => ColorTransform(ra, ga, ba, aa, rb, gb, bb, ab);

  bool get isIdentity =>
      ra == 1 && ga == 1 && ba == 1 && aa == 1 && rb == 0 && gb == 0 && bb == 0 && ab == 0;

  /// `this` is the inner (child) transform, [parent] is applied after it.
  ColorTransform concat(ColorTransform parent) => ColorTransform(
        ra * parent.ra,
        ga * parent.ga,
        ba * parent.ba,
        aa * parent.aa,
        rb * parent.ra + parent.rb,
        gb * parent.ga + parent.gb,
        bb * parent.ba + parent.bb,
        ab * parent.aa + parent.ab,
      );

  ui.Color apply(List<int> c) {
    int ch(double v) => v.isNaN ? 0 : v.clamp(0, 255).round();
    return ui.Color.fromARGB(
      ch(c[3] * aa + ab),
      ch(c[0] * ra + rb),
      ch(c[1] * ga + gb),
      ch(c[2] * ba + bb),
    );
  }

  ui.ColorFilter toFilter() => ui.ColorFilter.matrix(<double>[
        ra, 0, 0, 0, rb, //
        0, ga, 0, 0, gb,
        0, 0, ba, 0, bb,
        0, 0, 0, aa, ab,
      ]);

  @override
  bool operator ==(Object other) =>
      other is ColorTransform &&
      ra == other.ra &&
      ga == other.ga &&
      ba == other.ba &&
      aa == other.aa &&
      rb == other.rb &&
      gb == other.gb &&
      bb == other.bb &&
      ab == other.ab;

  @override
  int get hashCode => Object.hash(ra, ga, ba, aa, rb, gb, bb, ab);
}
