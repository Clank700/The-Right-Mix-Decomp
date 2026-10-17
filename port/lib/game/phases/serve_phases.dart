import '../../engine/engine.dart';
import '../config/verdicts.dart';
import '../world.dart';
import 'phase.dart';

/// Serve was pressed: Miguel puts the shaker down (frames up to 71). With a garnish he then fetches the lemon.
class ServeRestPhase extends Phase {
  const ServeRestPhase();

  @override
  void update(GameWorld w) {
    final miguel = w.miguel;
    if (miguel.frame < 71) {
      miguel.gotoAndStop(miguel.frame + 3 > 71 ? 71 : miguel.frame + 3);
    } else if (w.garnished) {
      w.hand.fetch(w.shelf.lemon);
      miguel.clipChild('backArm')?.visible = false;
      w.phase = GamePhase.getBottle;
    } else {
      w.phase = GamePhase.serve;
    }
  }
}

/// The hand has brought the lemon: Miguel squeezes it over the drink (frames 72..103).
class ServeLemonPhase extends Phase {
  const ServeLemonPhase();

  @override
  void update(GameWorld w) {
    w.hud.idleText = 'How good is your cocktail?';
    w.hud.showIdle();
    w.sounds.fadeShakeNoise();
    final miguel = w.miguel;
    if (miguel.frame < 72) miguel.gotoAndStop(72);
    if (miguel.frame < 104) {
      final spraying = miguel.frame > 74 && miguel.frame < 101;
      w.effects.garnishSpray.emitLocked = !spraying;
      w.effects.garnishMist.emitLocked = !spraying;
      miguel.gotoAndStop(miguel.frame + 1);
    } else {
      w.phase = GamePhase.serve;
    }
  }
}

/// Miguel pours the drink into the glass and drinks it; at the end the score decides the finale.
class ServePhase extends Phase {
  const ServePhase();

  @override
  void update(GameWorld w) {
    w.hud.idleText = 'How good is your cocktail?';
    w.sounds.fadeShakeNoise();
    final miguel = w.miguel;
    final fx = w.effects;
    if (miguel.frame < 104) miguel.gotoAndStop(104);
    if (miguel.frame == 119) {
      // The glass appears: tint the drink with the colour of the ingredients.
      final drink = miguel.clipChild('glass')?.child('drink_mc');
      if (drink != null) ColorControl(drink).tint(w.shaker.drinkColour, 50);
      fx.serveStream.streamColour = w.shaker.drinkColour;
    }
    // (The original set `miguel.fullGlass._visible = true` at frame 304. The clip is actually named "fullglass" and
    // SWF 7 is case sensitive, so that line never did anything and is not ported.)
    if (miguel.frame < miguel.totalFrames) {
      miguel.gotoAndStop(miguel.frame + 1);
      final pouring = miguel.frame > 129 && miguel.frame < 164;
      if (pouring) {
        final spout = miguel.clipChild('serveParticles');
        for (final s in [fx.serveStream, fx.serveDroplets]) {
          s.x = (spout?.x ?? 0) + 535;
          s.y = (spout?.y ?? 0) + 204;
          s.emitLocked = false;
        }
      } else {
        fx.serveStream.emitLocked = true;
        fx.serveDroplets.emitLocked = true;
      }
      if (miguel.frame > 132 && miguel.frame < 164) {
        // Fill the glass one frame at a time.
        final drink = miguel.clipChild('glass')?.clipChild('drink_mc');
        drink?.gotoAndStop(drink.frame + 1);
      }
      return;
    }
    // Animation finished: score the drink.
    w.shaker.points = adjustForVariety(w.shaker.points, w.shaker.variety);
    w.verdict = verdictForScore(w.shaker.points);
    w.phase = GamePhase.finaleInit;
  }
}
