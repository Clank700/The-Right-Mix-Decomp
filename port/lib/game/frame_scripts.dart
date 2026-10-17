import 'dart:math' as math;

import '../engine/engine.dart';
import 'rightmix_game.dart';

/// Symbol ids from the original SWF (see decomp/swf.json).
class SymbolId {
  static const int preGameScreen = 73;
  static const int endGameScreen = 584;
  static const int finale1 = 177;
  static const int finale2 = 137;
  static const int finale3 = 159;
  static const int finale6 = 190;
  static const int loopingClip = 176;
  static const int glassWithGarnish1 = 252;
  static const int glassWithGarnish2 = 254;
}

/// Holds the running game so timeline scripts (which fire from inside the scene) can reach it.
class GameHost {
  RightMixGame? game;
  final math.Random random;
  GameHost([math.Random? random]) : random = random ?? math.Random();
}

/// Registers the ActionScript snippets that the original SWF attached to timeline frames and buttons.
void registerFrameScripts(Stage stage, GameHost host) {
  // Main timeline, frame 1: create the game and stop.
  stage.registerFrameScript(0, 1, (clip) {
    host.game = RightMixGame(stage, clip, random: host.random);
    clip.stop();
  });

  // The intro card and the end card hide themselves after their closing animation.
  void hideAndRewind(MovieClip clip) {
    clip.visible = false;
    clip.gotoAndStop(1);
  }

  stage.registerFrameScript(SymbolId.preGameScreen, 12, hideAndRewind);
  stage.registerFrameScript(SymbolId.endGameScreen, 33, hideAndRewind);

  // First finale (the milkshake): silence the music loop and the shaker rattle.
  stage.registerFrameScript(SymbolId.finale1, 1, (clip) => host.game?.world.sounds.silenceMusicAndRattle());

  // Some finales make the shelf bottles hop when something heavy lands.
  FrameScript bounceBottles(int base) => (clip) {
        for (final b in host.game!.world.shelf.bottles) {
          b.velY = (host.random.nextDouble() * 10).roundToDouble() + base;
        }
      };
  stage.registerFrameScript(SymbolId.finale2, 121, bounceBottles(10));
  stage.registerFrameScript(SymbolId.finale3, 101, bounceBottles(10));
  stage.registerFrameScript(SymbolId.finale6, 94, bounceBottles(20));

  stage.registerFrameScript(SymbolId.loopingClip, 75, (clip) => clip.gotoAndPlay(32));

  // The two glass symbols show their lemon garnish only after a garnished serve.
  void garnish(MovieClip clip) {
    clip.child('lemonGarnish')?.visible = host.game?.world.garnished ?? false;
    clip.stop();
  }

  stage.registerFrameScript(SymbolId.glassWithGarnish1, 1, garnish);
  stage.registerFrameScript(SymbolId.glassWithGarnish2, 1, garnish);

  // `on(release)` actions of the original button symbols.
  stage.setButtonAction(69, (b) => b.parent?.child('tandc')?.visible = false);
  stage.setButtonAction(567, (b) => host.game?.world.restart());
  stage.setButtonAction(575, (b) => openUrl('http://www.liquidlight.co.uk/'));
  stage.setButtonAction(579, (b) => openUrl('http://www.pluginmedia.net/'));
  stage.setButtonAction(581, (b) => b.parent?.child('credits')?.visible = false);
}
