import 'dart:math' as math;
import 'dart:ui' as ui;

/// Space around the picture that must stay clear (display cutout, rounded corners, system bars), in logical pixels.
class SafeInsets {
  final double left, top, right, bottom;
  const SafeInsets([this.left = 0, this.top = 0, this.right = 0, this.bottom = 0]);
  static const SafeInsets none = SafeInsets();
}

/// How the 600 x 440 stage is placed on the screen.
class ViewOptions {
  /// Use only whole-number multiples of the stage size (in physical pixels) when at least 1x fits.
  bool integerScale;

  /// Fill the space beside/above the stage with a blurred, dimmed copy of the picture instead of black.
  bool blurredBackdrop;

  /// Physical pixels per logical pixel of the surface the stage is drawn on.
  double devicePixelRatio;
  SafeInsets safe;

  ViewOptions({this.integerScale = false, this.blurredBackdrop = false, this.devicePixelRatio = 1, this.safe = SafeInsets.none});
}

class ViewTransform {
  final double scale;
  final ui.Offset offset;
  const ViewTransform(this.scale, this.offset);
}

/// Largest stage placement inside [size] minus the safe insets that keeps the aspect ratio, centred in the screen
/// (not in the safe area, so a cutout on one side does not push the picture off-centre unless it has to).
ViewTransform computeViewTransform(ui.Size size, double stageW, double stageH, ViewOptions o) {
  final left = o.safe.left, top = o.safe.top, right = o.safe.right, bottom = o.safe.bottom;
  final availW = math.max(1.0, size.width - left - right);
  final availH = math.max(1.0, size.height - top - bottom);
  var s = math.min(availW / stageW, availH / stageH);
  if (o.integerScale) {
    final physical = s * o.devicePixelRatio;
    if (physical >= 1) s = physical.floorToDouble() / o.devicePixelRatio;
  }
  final w = stageW * s, h = stageH * s;
  // Centre on the screen, then slide just enough to stay inside the safe area.
  var x = (size.width - w) / 2, y = (size.height - h) / 2;
  x = x.clamp(left, math.max(left, size.width - right - w)).toDouble();
  y = y.clamp(top, math.max(top, size.height - bottom - h)).toDouble();
  if (o.integerScale) {
    // snap to whole physical pixels so edges stay crisp
    x = (x * o.devicePixelRatio).round() / o.devicePixelRatio;
    y = (y * o.devicePixelRatio).round() / o.devicePixelRatio;
  }
  return ViewTransform(s, ui.Offset(x, y));
}
