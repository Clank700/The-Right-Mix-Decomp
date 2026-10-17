import 'dart:math' as math;

import '../engine/engine.dart';
import 'config/verdicts.dart';
import 'model/shaker.dart';
import 'props/barman_hand.dart';
import 'props/effect_bank.dart';
import 'props/hud.dart';
import 'props/shelf.dart';
import 'props/sound_bank.dart';

/// The stages of a round. Each has a matching `Phase` object that runs once per frame.
enum GamePhase {
  preGame,
  getBottle,
  pour,
  rest,
  returnTweenHand,
  shakeRest,
  shake,
  serve,
  serveRest,
  serveLemon,
  finaleInit,
  finale,
  endGame,
  waitInput,
}

/// Everything that exists during a round, wired together. Phases and props receive this instead of reaching
/// for a global.
class GameWorld {
  /// Depth a bottle is lifted to while the hand reaches for it, and while it is in the hand.
  static const int activeBottleDepth = 6000;
  static const int handOnBottleDepth = 5998;

  final Stage stage;
  final MovieClip root;
  final math.Random random;

  GamePhase phase = GamePhase.preGame;
  bool mouseDown = false;

  /// The lemon garnish is being added (changes what the buttons do and what Miguel animates).
  bool garnished = false;

  /// Shake was requested while a bottle was in hand: put the bottle back first, then shake.
  bool reshelveBeforeShaking = false;

  Verdict verdict = milkshakeVerdict;
  MovieClip? finaleClip;

  late final MovieClip table;
  late final MovieClip miguel;
  late final Shaker shaker;
  late final Shelf shelf;
  late final BarmanHand hand;
  late final SoundBank sounds;
  late final EffectBank effects;
  late final Hud hud;
  late final MovieClip introCard;
  late final MovieClip endCard;
  late final MovieClip logo;

  final List<int> _freeDepths = [for (var i = 100; i >= 0; i--) i];
  final MouseListener _mouse = MouseListener();

  GameWorld(this.stage, this.root, this.random) {
    table = root.createEmptyMovieClip('containerClip', 0);
    table.attachMovie('barback', 'barback_mc', _freeDepths.removeLast())!
      ..x = 0
      ..y = 0;
    hand = BarmanHand(this, table, 518, 240, 5999);
    miguel = table.attachMovie('miguel', 'miguel_01', 6520)!
      ..gotoAndStop(1)
      ..x = 523
      ..y = 193;
    shaker = Shaker(470, 243);
    shelf = Shelf(this, () => _freeDepths.removeLast());
    sounds = SoundBank(stage);
    effects = EffectBank(table, random, shaker, shelf, sounds);
    sounds.startLoops();
    hud = Hud(table);
    _wireLemonGarnish();

    _mouse.onMouseDown = () {
      mouseDown = true;
    };
    _mouse.onMouseUp = () {
      mouseDown = false;
    };
    stage.addMouseListener(_mouse);

    introCard = root.attachMovie('preGameScreen', 'preGameMask', 9999)!
      ..x = 300
      ..y = 220;
    endCard = root.attachMovie('endGameScreen', 'endGameMask', 10001)!
      ..x = 0
      ..y = 0
      ..gotoAndStop(1)
      ..visible = false;
    logo = root.attachMovie('landLogo', 'landLogo', 11313)!
      ..x = 10
      ..y = 10;
    table.visible = false;
  }

  /// Something may be picked up from the bar right now.
  bool get canFetch => (phase == GamePhase.rest && !shaker.isFull) || phase == GamePhase.getBottle;

  /// The lemon bowl doubles as the garnish button once the drink has been shaken.
  void _wireLemonGarnish() {
    final mask = shelf.lemon.mask;
    mask.onPress = () {
      if (phase == GamePhase.shakeRest) {
        garnished = true;
        shaker.points += 200;
        miguel.gotoAndStop(64);
        phase = GamePhase.serveRest;
      } else if (canFetch) {
        hand.fetch(shelf.lemon);
        phase = GamePhase.getBottle;
      }
    };
    mask.onRollOver = () {
      if (phase == GamePhase.shakeRest) {
        hud.showInfo('Add a lemon garnish?');
      } else if (phase != GamePhase.serve) {
        hud.showInfo('Add a lemon!?');
      }
    };
    mask.onRollOut = () => hud.showIdle();
  }

  /// Start playing: reveal the bar and let the intro card fold away.
  void startRound() {
    table.visible = true;
    phase = GamePhase.rest;
  }

  /// "Back to the bar?" - reset everything for a new drink.
  void restart() {
    table.visible = true;
    endCard.gotoAndPlay(20);
    shaker.reset();
    verdict = milkshakeVerdict; // the original resets finaleAnim to 1
    reshelveBeforeShaking = false;
    if (garnished) {
      garnished = false;
      final item = hand.held;
      if (item != null) {
        item.inHand = false;
        item.x = item.homeX;
        item.y = item.homeY;
        item.clip.breakBlend();
      }
    }
    hand.reset();
    hud.releaseButtons();
    mouseDown = false;
    miguel.gotoAndStop(1);
    phase = GamePhase.rest;
    hud.resetGauge();
    miguel.visible = true;
    sounds.restartRattle();
    table.visible = true;
    hud.idleText = Hud.defaultInfo;
    hud.showIdle();
  }

  /// What a held mouse button means in the current phase (shared by several phases).
  void applyPlayerInput() {
    if (mouseDown && hud.shakeHeld) {
      final canShake = phase != GamePhase.returnTweenHand &&
          phase != GamePhase.shake &&
          phase != GamePhase.shakeRest &&
          shaker.fluidVolume > 0 &&
          !garnished &&
          phase != GamePhase.serve;
      if (canShake) {
        if (hand.holdingItem) {
          // Put the bottle back before shaking.
          hand.fetch(hand.held!);
          reshelveBeforeShaking = true;
          phase = GamePhase.getBottle;
          return;
        }
        miguel.gotoAndStop(25);
        phase = GamePhase.shakeRest;
      } else if (phase != GamePhase.returnTweenHand &&
          shaker.fluidVolume > 0 &&
          !garnished &&
          phase != GamePhase.shake &&
          phase != GamePhase.serve) {
        phase = GamePhase.shake;
      }
    } else if (phase == GamePhase.shake && miguel.frame > 41) {
      phase = GamePhase.shakeRest;
    }
    if (!(mouseDown && hud.pourHeld && hand.holdingItem && !garnished)) {
      if (phase != GamePhase.getBottle && hand.holdingItem && !garnished) phase = GamePhase.rest;
      return;
    }
    if (!shaker.isFull) {
      phase = GamePhase.pour;
      return;
    }
    hud.showInfo('');
    phase = GamePhase.rest;
  }
}
