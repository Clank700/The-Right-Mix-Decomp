import '../props/hud.dart';
import '../world.dart';
import 'phase.dart';

/// Waiting on the intro card: the bar stays hidden until the player presses Let's Mix.
class PreGamePhase extends Phase {
  const PreGamePhase();
  @override
  void update(GameWorld w) => w.table.visible = false;
}

/// The hand is travelling to a bottle (or returning one).
class GetBottlePhase extends Phase {
  const GetBottlePhase();
  @override
  void update(GameWorld w) {
    if (!w.hand.atGoal) {
      w.hand.moveToGoal();
    } else {
      w.applyPlayerInput();
    }
  }
}

/// Holding the Pour button: the bottle tips over the shaker.
class PourPhase extends Phase {
  const PourPhase();
  @override
  void update(GameWorld w) {
    w.hud.showGauge(true);
    w.hand.pour();
    w.applyPlayerInput();
  }
}

/// Idle at the bar: pick something, or hold Pour / Shake.
class RestPhase extends Phase {
  const RestPhase();
  @override
  void update(GameWorld w) {
    // The intro card folds away over its last frames once the game has started.
    if (w.introCard.visible && w.introCard.frame < 12) w.introCard.gotoAndStop(w.introCard.frame + 1);
    w.hud.idleText = w.hand.holdingItem ? 'Hold pour to add...' : Hud.defaultInfo;
    if (!w.shaker.isFull) w.hud.showGauge(false);
    w.applyPlayerInput();
    w.hand.returnToRest();
  }
}

/// The hand slides away after putting something in the shaker.
class ReturnHandPhase extends Phase {
  const ReturnHandPhase();
  @override
  void update(GameWorld w) {
    w.hud.idleText = Hud.defaultInfo;
    if (!w.shaker.isFull) w.hud.showGauge(false);
    w.applyPlayerInput();
    w.hand.leaveScreen();
  }
}
