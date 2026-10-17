import 'color_transform.dart';
import 'nodes/node.dart';

/// Colour transform in ActionScript units: multipliers in percent, offsets in 0..255.
class ColorTransformPct {
  double ra, rb, ga, gb, ba, bb, aa, ab;
  ColorTransformPct(this.ra, this.rb, this.ga, this.gb, this.ba, this.bb, this.aa, this.ab);
}

/// The ActionScript `Color` object: tint a node through its colour transform.
class ColorControl {
  final Node target;
  ColorControl(this.target);

  /// Solid colour (0xRRGGBB), keeping the alpha part of the transform.
  void setSolidColour(int rgb) {
    target.colorTransform = ColorTransform(0, 0, 0, target.colorTransform.aa, ((rgb >> 16) & 255).toDouble(),
        ((rgb >> 8) & 255).toDouble(), (rgb & 255).toDouble(), target.colorTransform.ab);
  }

  ColorTransformPct get transform {
    final c = target.colorTransform;
    return ColorTransformPct(c.ra * 100, c.rb, c.ga * 100, c.gb, c.ba * 100, c.bb, c.aa * 100, c.ab);
  }

  set transform(ColorTransformPct t) {
    target.colorTransform = ColorTransform(t.ra / 100, t.ga / 100, t.ba / 100, t.aa / 100, t.rb, t.gb, t.bb, t.ab);
  }

  /// Blend towards [colour] by [percent] (0..100). With [reset] the transform starts from "no tint".
  void tint(num colour, num percent, {bool reset = true}) {
    if (colour.isNaN || percent.isNaN) return;
    final c = colour > 0 ? (colour < 0xFFFFFF ? colour.round() : 0xFFFFFF) : 0;
    final p = percent > 0 ? (percent < 100 ? percent / 100 : 1.0) : 0.0;
    final t = transform;
    if (reset) {
      t.ra = t.ga = t.ba = 100;
      t.rb = t.gb = t.bb = 0;
    }
    t.ra -= t.ra * p;
    t.ga -= t.ga * p;
    t.ba -= t.ba * p;
    t.rb += (((c & 0xFF0000) >> 16) - t.rb) * p;
    t.gb += (((c & 0xFF00) >> 8) - t.gb) * p;
    t.bb += ((c & 0xFF) - t.bb) * p;
    transform = t;
  }
}
