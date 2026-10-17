import 'dart:convert';

/// Player-adjustable display options. Pure data; stored by [SettingsStore].
class Settings {
  /// Draw the stage at whole-number multiples of its size (crisp edges, larger borders).
  bool integerScale;

  /// Fill the space around the picture with a blurred, dimmed copy of it instead of black bars.
  bool blurredBackdrop;

  /// Blend between the game's 18 Hz steps so motion runs at the display's refresh rate (60 / 120 Hz...).
  /// Off shows the original 18 frames per second.
  bool smoothMotion;

  /// Windows only: borderless full screen.
  bool fullscreen;

  Settings({this.integerScale = false, this.blurredBackdrop = false, this.smoothMotion = true, this.fullscreen = false});

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        integerScale: j['integerScale'] == true,
        blurredBackdrop: j['blurredBackdrop'] == true,
        smoothMotion: j['smoothMotion'] != false,
        fullscreen: j['fullscreen'] == true,
      );

  Map<String, dynamic> toJson() => {
        'integerScale': integerScale,
        'blurredBackdrop': blurredBackdrop,
        'smoothMotion': smoothMotion,
        'fullscreen': fullscreen,
      };

  static Settings decode(String? text) {
    try {
      if (text != null) return Settings.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {}
    return Settings();
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
