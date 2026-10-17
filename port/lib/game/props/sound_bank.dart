import '../../engine/engine.dart';

/// The game's five named sounds (the ActionScript `Sound` objects of the original).
class SoundBank {
  static const int musicVolume = 10;

  final SoundObject music;
  final SoundObject iceGlass;
  final SoundObject lemonDrop;
  final SoundObject pour;
  final SoundObject shakeNoise;

  SoundBank(Stage stage)
      : music = _sound(stage, 'musicLoop', musicVolume),
        iceGlass = _sound(stage, 'iceGlass', 20),
        lemonDrop = _sound(stage, 'lemondrop', 30),
        pour = _sound(stage, 'pour', 100),
        shakeNoise = _sound(stage, 'shakeNoise', 0);

  static SoundObject _sound(Stage stage, String symbol, int volume) =>
      SoundObject(stage.backend, stage.lib)
        ..attachSound(symbol)
        ..setVolume(volume);

  /// Start the endless loops (background music, and the shaker rattle which stays silent until shaking).
  void startLoops() {
    music.start(0, 99999);
    shakeNoise.start(0, 99999);
  }

  /// The shaker rattle dies away by 5 per frame once shaking stops.
  void fadeShakeNoise() {
    shakeNoise.setVolume(shakeNoise.getVolume() > 0 ? shakeNoise.getVolume() - 5 : 0);
  }

  /// The pour sound dies away by 2 per frame whenever the hand is not pouring.
  void fadePour() {
    if (pour.getVolume() > 0) pour.setVolume(pour.getVolume() - 2);
  }

  void silenceMusicAndRattle() {
    music.setVolume(0);
    music.stop();
    shakeNoise.stop();
  }

  void restartRattle() {
    shakeNoise.stop();
    shakeNoise.setVolume(0);
    shakeNoise.start(0, 99999);
  }
}
