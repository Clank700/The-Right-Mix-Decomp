import 'dart:math' as math;

import '../../engine/engine.dart';
import '../model/shaker.dart';
import '../world.dart';
import 'shelf.dart';

/// The barman's disembodied hand and the arm sleeve that follows it: fetches items, pours, returns.
class BarmanHand {
  static const double _sineWavelength = 40;
  static const double _sineAmplitude = 5;

  final GameWorld world;
  final double originX;
  final double originY;
  final int depth;

  late final MovieClip armClip;
  late final MovieClip clip;

  /// Position of the hand; the arm sleeve stretches from the shoulder (origin) to here.
  double x;
  double y;

  double _restX;
  double _restY;
  double _targetX = 0;
  double _targetY = 0;
  double _armAngle = 0;

  bool atGoal = true; // true once the current fetch is complete
  bool holdingItem = false;
  ShelfItem? held;
  ShelfItem? _target;
  ShelfItem? _lastTarget;
  int _grabStep = 0;
  bool _pouring = false;
  bool _pourSoundStarted = false;
  int _wobbleIndex = 0;
  final List<double> _wobble = List<double>.generate(
      _sineWavelength.toInt() + 1, (i) => math.sin(i / _sineWavelength * 2 * math.pi));

  BarmanHand(this.world, MovieClip parent, this.originX, this.originY, this.depth)
      : x = originX,
        y = originY,
        _restX = originX,
        _restY = originY {
    armClip = parent.attachMovie('armSeg', 'armSegClip', 56)!
      ..x = originX
      ..y = originY;
    clip = parent.attachMovie('hand', 'barmanhand', depth)!
      ..gotoAndStop(1)
      ..visible = false;
  }

  void show(bool visible) {
    clip.visible = visible;
    armClip.visible = visible;
  }

  /// Back to the start state for a new drink.
  void reset() {
    held = null;
    holdingItem = false;
    atGoal = true;
    _pouring = false;
    _grabStep = 0;
    _targetX = 0;
    _targetY = 0;
    show(false);
  }

  /// Reach for [item]. If something is already held, the hand first returns it to its shelf spot.
  void fetch(ShelfItem item) {
    if (!atGoal) return;
    _target = item;
    atGoal = false;
    _grabStep = 0;
    show(true);
    if (!holdingItem) {
      if (!item.isAdditive) item.clip.swapDepths(GameWorld.activeBottleDepth);
      // Miguel reaches out, unless he is already mid-reach or garnishing.
      if (world.miguel.frame != 24 && !world.garnished) world.miguel.gotoAndPlay(1);
      _targetX = item.x;
      _targetY = item.y;
    } else {
      _targetX = _lastTarget!.homeX;
      _targetY = _lastTarget!.homeY;
    }
  }

  /// Per-frame: put the hand and arm clips where the state says.
  void syncClips() {
    clip.gotoAndStop(holdingItem ? 2 : 1);
    clip.x = x;
    clip.y = y;
    final dy = armClip.y - clip.y;
    final dx = armClip.x - clip.x;
    _armAngle = math.atan(dy / dx) * 180 / math.pi - 90;
    if (_armAngle < 0) _armAngle = 360 - _armAngle.abs();
    armClip.rotation = _armAngle;
    armClip.yscale = 10 * math.sqrt(dy * dy + dx * dx);
  }

  /// Move a fraction [damping] of the way to the target; true once within [minDistanceSquared].
  bool _easeTo(double tx, double ty, double damping, double minDistanceSquared) {
    y -= (y - ty) * damping;
    x -= (x - tx) * damping;
    final dy = y - ty;
    final dx = x - tx;
    return dy * dy + dx * dx < minDistanceSquared;
  }

  void _quietPour() {
    _pourSoundStarted = false;
    world.sounds.fadePour();
  }

  /// Phase `getBottle`: travel to the target, grab it (or put the held item back), then retreat.
  void moveToGoal() {
    _quietPour();
    clip.rotation = holdingItem ? 0 : _armAngle + 70;
    if (!_easeTo(_targetX, _targetY, 0.65, 8)) return;
    _grabStep++;
    if (_grabStep == 1) {
      if (!holdingItem) {
        holdingItem = true;
        world.hud.idleText = 'Hold pour to add...';
        world.hud.showInfo(world.hud.idleText);
        _target!.toggleHeld();
        if (!_target!.isAdditive) _target!.clip.swapDepths(GameWorld.handOnBottleDepth);
        if (!world.garnished) {
          _restX = originX - 100;
          _restY = originY - 30;
        } else {
          _restX = originX - 10;
          _restY = originY + 90;
        }
      } else {
        _lastTarget!.toggleHeld();
        if (!_lastTarget!.isAdditive) _lastTarget!.clip.swapDepths(_lastTarget!.depth);
        _restX = originX;
        _restY = originY;
        holdingItem = false;
      }
      _targetX = _restX;
      _targetY = _restY;
    } else if (_grabStep == 2) {
      if (!holdingItem) {
        if (_target != _lastTarget) {
          atGoal = true;
          fetch(_target!);
        } else {
          atGoal = true;
          world.phase = GamePhase.returnTweenHand;
        }
      } else {
        atGoal = true;
        held = _target;
        world.effects.pourDroplets.tint = held!.highlightColour;
        _lastTarget = _target;
        world.phase = world.garnished ? GamePhase.returnTweenHand : GamePhase.rest;
      }
    }
  }

  /// Phase `rest`: hang at the rest position, straightening the bottle.
  void returnToRest() {
    final item = held;
    if (item != null && item.clip.rotation > 0) {
      item.clip.rotation -= item.clip.rotation * 0.4;
      clip.rotation = item.clip.rotation;
    }
    _quietPour();
    world.effects.pourStream.emitLocked = true;
    world.effects.pourDroplets.emitLocked = true;
    _pouring = false;
    _easeTo(_restX, _restY, 0.2, 2);
  }

  /// Phase `returnTweenHand`: slide off the bottom of the screen while Miguel's arm lowers.
  void leaveScreen() {
    _quietPour();
    if (world.garnished) {
      if (_easeTo(500, 400, 0.2, 2)) world.phase = GamePhase.serveLemon;
    } else if (_easeTo(500, 400, 0.3, 6)) {
      clip.visible = false;
      final miguel = world.miguel;
      if (miguel.frame > 1) {
        miguel.gotoAndStop(math.max(1, miguel.frame - 3));
      } else if (world.reshelveBeforeShaking) {
        miguel.gotoAndStop(25);
        world.phase = GamePhase.shakeRest;
        world.reshelveBeforeShaking = false;
      } else {
        world.phase = GamePhase.getBottle;
      }
    }
  }

  /// Phase `pour`: tip the bottle over the shaker (or drop in ice / lemon).
  void pour() {
    final item = held!;
    final fx = world.effects;
    if (!item.isAdditive) {
      if (_easeTo(originX - 130, originY - 130, 0.5, 4) && !_pouring) _pouring = true;
      if (_pouring) {
        _wobbleIndex = _wobbleIndex < _sineWavelength ? _wobbleIndex + 1 : 0;
        y += _wobble[_wobbleIndex] * _sineAmplitude;
      }
      item.x = x;
      item.y = y;
      fx.pourStream.x = item.x + item.pourOffsetX;
      fx.pourDroplets.x = item.x + item.pourOffsetX;
      fx.pourStream.y = item.y + item.pourOffsetY;
      fx.pourDroplets.y = item.y + item.pourOffsetY;
      fx.pourStream.streamColour = item.liquidColour;
      if (item.clip.rotation > 116) {
        fx.pourStream.emitLocked = false;
        fx.pourDroplets.emitLocked = false;
        if (!_pourSoundStarted) {
          world.sounds.pour
            ..stop()
            ..setVolume(20)
            ..start();
          _pourSoundStarted = true;
        }
        world.shaker.pour(1, item.score);
      } else {
        item.clip.rotation += (120 - item.clip.rotation) * 0.2;
        fx.pourStream.emitLocked = true;
        fx.pourDroplets.emitLocked = true;
      }
      clip.rotation = item.clip.rotation;
    } else {
      if (_easeTo(originX - 50, originY - 130, 0.5, 4) && !_pouring) _pouring = true;
      if (!_pouring) return;
      final intoShaker = (item as Additive).kind == AdditiveKind.ice ? fx.iceIntoShaker : fx.lemonIntoShaker;
      intoShaker
        ..x = x
        ..y = y
        ..kick();
      item.inHand = false;
      item.x = item.homeX;
      item.y = item.homeY;
      item.syncClip();
      final shaker = world.shaker;
      if (shaker.fluidVolume + 50 < Shaker.capacity) {
        shaker.pour(50, item.score);
      } else {
        shaker.pour(Shaker.capacity - shaker.fluidVolume, item.score);
        shaker.isFull = true;
      }
      held = null;
      holdingItem = false;
      world.phase = GamePhase.returnTweenHand;
    }
  }
}
