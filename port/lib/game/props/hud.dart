import '../../engine/engine.dart';

/// The bottom control strip: Pour / Shake / Serve buttons and the info panel with the volume gauge.
class Hud {
  static const String defaultInfo = 'What will you add?';

  final ButtonNode pourButton;
  final ButtonNode shakeButton;
  final ButtonNode serveButton;
  final MovieClip panel;

  /// True while the button is being held down (the original called this `active`).
  bool pourHeld = false;
  bool shakeHeld = false;

  /// Text the panel falls back to when the pointer leaves a hot spot.
  String idleText = defaultInfo;

  /// Called when Serve is released; the game decides whether serving is allowed right now.
  void Function()? onServe;

  Hud(MovieClip table)
      : pourButton = _button(table, 'buttonpour', 9909, 75, 415),
        shakeButton = _button(table, 'buttonshake', 9910, 210, 415),
        serveButton = _button(table, 'buttonserve', 9911, 340, 415),
        panel = table.attachMovie('dynText', 'dynText_mc', 9912)!
          ..x = 410
          ..y = 355 {
    pourButton.onPress = () {
      pourHeld = true;
    };
    pourButton.onRelease = () {
      pourHeld = false;
    };
    pourButton.onRollOver = () {
      showInfo('Click and hold to add');
      shakeHeld = false;
    };
    pourButton.onRollOut = showIdle;

    shakeButton.onPress = () {
      shakeHeld = true;
    };
    shakeButton.onRelease = () {
      shakeHeld = false;
    };
    shakeButton.onRollOver = () {
      showInfo('Click and hold to shake');
    };
    shakeButton.onRollOut = showIdle;

    serveButton.onRelease = () {
      onServe?.call();
    };
    serveButton.onRollOver = () {
      showInfo('Click once to serve');
      pourHeld = false;
      shakeHeld = false;
    };
    serveButton.onRollOut = showIdle;
    showIdle();
  }

  static ButtonNode _button(MovieClip table, String symbol, int depth, double x, double y) =>
      table.attachButton(symbol, symbol, depth)!
        ..x = x
        ..y = y;

  MovieClip? get _gauge => panel.clipChild('shakerVolClip');

  void showInfo(String text) {
    final field = panel.child('info');
    if (field is TextFieldNode) field.text = text;
  }

  void showIdle() => showInfo(idleText);

  void releaseButtons() {
    pourHeld = false;
    shakeHeld = false;
  }

  // ---- the little glass that shows how full the shaker is ----------------------------------------
  void showGauge(bool visible) => _gauge?.visible = visible;

  void resetGauge() {
    _gauge
      ?..visible = false
      ..gotoAndStop(1);
  }

  /// Show the level (0..1) and switch to the "full" artwork when the shaker is full.
  void updateGauge(double level, {required bool full}) {
    final gauge = _gauge;
    if (gauge == null) return;
    gauge.clipChild('frame1')?.child('indicator')?.yscale = level * 100;
    if (full && gauge.frame != 2) {
      gauge.visible = true;
      gauge.gotoAndStop(2);
    }
  }
}
