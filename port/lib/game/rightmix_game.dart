import 'dart:math' as math;

import '../engine/engine.dart';
import 'model/shaker.dart';
import 'phases/finale_phases.dart';
import 'phases/phase.dart';
import 'phases/serve_phases.dart';
import 'phases/shake_phases.dart';
import 'phases/shelf_phases.dart';
import 'world.dart';

/// The Right Mix: builds the world and runs the active [Phase] once per frame.
class RightMixGame {
  final GameWorld world;

  static const Map<GamePhase, Phase> _phases = {
    GamePhase.preGame: PreGamePhase(),
    GamePhase.getBottle: GetBottlePhase(),
    GamePhase.pour: PourPhase(),
    GamePhase.rest: RestPhase(),
    GamePhase.returnTweenHand: ReturnHandPhase(),
    GamePhase.shakeRest: ShakeRestPhase(),
    GamePhase.shake: ShakePhase(),
    GamePhase.serve: ServePhase(),
    GamePhase.serveRest: ServeRestPhase(),
    GamePhase.serveLemon: ServeLemonPhase(),
    GamePhase.finaleInit: FinaleInitPhase(),
    GamePhase.finale: FinalePhase(),
    GamePhase.endGame: EndGamePhase(),
    GamePhase.waitInput: WaitInputPhase(),
  };

  /// [root] is the main timeline clip; [random] is injectable so tests can be deterministic.
  RightMixGame(Stage stage, MovieClip root, {math.Random? random})
      : world = GameWorld(stage, root, random ?? math.Random()) {
    root.onEnterFrame = tick;
    world.miguel.onEnterFrame = _keepFullGlassTinted;
    world.hud.onServe = () {
      if (world.phase == GamePhase.shakeRest) world.phase = GamePhase.serveRest;
    };
    final start = world.introCard.child('startButton');
    if (start is ButtonNode) start.onPress = world.startRound;
  }

  /// One frame of game logic.
  void tick() {
    _phases[world.phase]!.update(world);
    world.hud.updateGauge(world.shaker.fluidVolume / Shaker.capacity, full: world.shaker.isFull);
    world.hand.syncClips();
    world.effects.update();
    world.shelf.update();
  }

  /// Once the drink has been served, Miguel's "full glass" clip is tinted every frame, and its lemon shown
  /// only for a garnished drink (this was a script on frame 302 of Miguel's timeline).
  void _keepFullGlassTinted() {
    final glass = world.miguel.clipChild('fullglass');
    if (glass == null) return;
    final drink = glass.child('drink_mc');
    if (drink != null) ColorControl(drink).tint(world.shaker.drinkColour, 50);
    glass.child('lemonGarnish')?.visible = world.garnished;
  }
}
