import '../config/verdicts.dart';
import '../world.dart';
import 'phase.dart';

/// Shaker in Miguel's hands, between shakes. Serving and garnishing become available.
class ShakeRestPhase extends Phase {
  const ShakeRestPhase();
  @override
  void update(GameWorld w) {
    w.hud.idleText = 'Shake, and serve when ready';
    w.sounds.fadeShakeNoise();
    w.hud.showGauge(false);
    w.applyPlayerInput();
    // Miguel raises the shaker (frames 25..40), then holds it at frame 64.
    if (w.miguel.frame < 40) {
      w.miguel.gotoAndStop(w.miguel.frame + 1);
    } else {
      w.miguel.gotoAndStop(64);
    }
  }
}

/// Holding Shake: the shake animation loops; five full shakes ruin the drink.
class ShakePhase extends Phase {
  static const int maxShakes = 5;
  const ShakePhase();

  @override
  void update(GameWorld w) {
    w.hud.showGauge(false);
    final rattle = w.sounds.shakeNoise;
    if (w.miguel.frame > 41 && rattle.getVolume() < 40) rattle.setVolume(rattle.getVolume() + 1);
    w.applyPlayerInput();
    if (w.miguel.frame < 63) {
      w.miguel.gotoAndStop(w.miguel.frame + 1);
      return;
    }
    w.shaker.shakeCycles++;
    w.shaker.points += 10 * w.shaker.shakeCycles;
    if (w.shaker.shakeCycles >= maxShakes) {
      w.finaleClip?.swapDepths(11000);
      w.verdict = milkshakeVerdict;
      w.phase = GamePhase.finaleInit;
    }
    w.miguel.gotoAndStop(41);
  }
}
