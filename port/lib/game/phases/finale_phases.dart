import '../../engine/engine.dart';
import '../props/sound_bank.dart';
import '../world.dart';
import 'phase.dart';

/// Start the finale animation chosen by the verdict, over everything else.
class FinaleInitPhase extends Phase {
  const FinaleInitPhase();

  @override
  void update(GameWorld w) {
    w.hand.show(false);
    w.miguel.visible = false;
    final finale = w.verdict.finale;
    if (finale == 1) {
      // Milkshake ending: no score at all, and it plays above the end card.
      w.shaker.points = 0;
      w.finaleClip = w.table.attachMovie('finale1', 'finale', 11000);
    } else {
      w.finaleClip = w.table.attachMovie('finale$finale', 'finale', 6521);
    }
    w.shaker.points = w.shaker.points.roundToDouble();
    w.finaleClip
      ?..x = 523
      ..y = 193
      ..gotoAndPlay(1);
    w.phase = GamePhase.finale;
  }
}

/// Wait for the finale animation to reach its last frame.
class FinalePhase extends Phase {
  const FinalePhase();

  @override
  void update(GameWorld w) {
    final clip = w.finaleClip;
    if (clip != null && clip.frame >= clip.totalFrames) {
      clip.stop();
      w.phase = GamePhase.endGame;
    }
  }
}

/// Bring the music back (the milkshake finale silences it) and show the end card.
class EndGamePhase extends Phase {
  const EndGamePhase();

  @override
  void update(GameWorld w) {
    w.endCard.visible = true;
    if (w.sounds.music.getVolume() == 0) {
      w.sounds.music
        ..setVolume(SoundBank.musicVolume)
        ..start(0, 99999);
    }
    w.phase = GamePhase.waitInput;
  }
}

/// End card is up: slide it in, show message and score, wait for "Back to the bar?".
class WaitInputPhase extends Phase {
  const WaitInputPhase();

  @override
  void update(GameWorld w) {
    final card = w.endCard;
    if (card.frame < 20) {
      card.gotoAndStop(card.frame + 1);
      return;
    }
    (card.child('finaleMsg') as TextFieldNode?)?.text = w.verdict.message;
    (card.child('yourScore') as TextFieldNode?)?.text = 'Your score: ${_whole(w.shaker.points)}';
    w.finaleClip?.removeFromParent();
    w.finaleClip = null;
    if (w.table.visible) w.table.visible = false;
  }

  /// ActionScript prints whole numbers without a decimal point.
  static String _whole(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
