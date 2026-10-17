// Shared pieces of the differential harness: the deterministic RNG, the per-frame state line and the input vocabulary.
// See differential_dump_test.dart and plan_scenarios_test.dart.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/engine/engine.dart';

import 'sim_helpers.dart';

/// Park-Miller minimal standard generator, the same one the probe installs as Math.random in the original.
class ParkMiller implements math.Random {
  int seed;
  ParkMiller(this.seed);

  @override
  double nextDouble() {
    seed = seed * 16807 % 2147483647;
    return seed / 2147483647;
  }

  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => nextDouble() < 0.5;
}

/// Flash's Math.round: halves round up.
int flashRound(double v) => (v + 0.5).floor();

String text(Object? node) => node is TextFieldNode ? node.text : 'undefined';

String stateLine(Sim sim, int frame, ParkMiller rng) {
  final w = sim.world;
  final endCard = w.endCard;
  final ys = endCard.child('yourScore');
  final fm = endCard.child('finaleMsg');
  return 'F$frame ${w.phase.name}'
      ' v=${flashRound(w.shaker.fluidVolume * 100)}'
      ' p=${flashRound(w.shaker.points * 100)}'
      ' var=${w.shaker.variety}'
      ' cyc=${w.shaker.shakeCycles}'
      ' full=${w.shaker.isFull}'
      ' hx=${flashRound(w.hand.x * 100)}'
      ' hy=${flashRound(w.hand.y * 100)}'
      ' item=${w.hand.holdingItem}'
      ' mf=${w.miguel.frame}'
      ' dc=${w.shaker.drinkColour}'
      ' g=${w.garnished}'
      ' fa=${w.verdict.finale}'
      ' parts=${w.effects.liveParticles}'
      ' info=[${text(w.hud.panel.child('info'))}]'
      ' ys=[${text(ys)}]'
      ' fm=${fm is TextFieldNode ? fm.text.length : 'undefined'}'
      ' ff=${w.finaleClip?.frame ?? 'undefined'}'
      ' rs=${rng.seed}';
}

void applyOp(Sim sim, Object op) {
  final w = sim.world;
  if (op is List) {
    // ["pick", i]: press the i-th bottle exactly as its onPress handler would
    expect(op[0], 'pick');
    w.shelf.bottles[op[1] as int].clip.onPress?.call();
    return;
  }
  switch (op) {
    case 'start':
      (w.introCard.child('startButton') as ButtonNode).onPress?.call();
    case 'ice':
      w.shelf.ice.mask.onPress?.call();
    case 'lemon':
      w.shelf.lemon.mask.onPress?.call();
    case 'pourDown':
      w.hud.pourButton.onPress?.call();
      w.mouseDown = true; // what the Mouse listener's onMouseDown does
    case 'pourUp':
      w.hud.pourButton.onRelease?.call();
      w.mouseDown = false;
    case 'shakeDown':
      w.hud.shakeButton.onPress?.call();
      w.mouseDown = true; // what the Mouse listener's onMouseDown does
    case 'shakeUp':
      w.hud.shakeButton.onRelease?.call();
      w.mouseDown = false;
    case 'serve':
      w.hud.serveButton.onRelease?.call();
    case 'restart':
      w.restart();
    default:
      fail('unknown op $op');
  }
}

