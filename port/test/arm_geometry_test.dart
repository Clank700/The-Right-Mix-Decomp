import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/game/world.dart';

import 'sim_helpers.dart';

/// Scans scripted playthroughs and checks that the arm sleeve always runs from the shoulder to the hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the arm sleeve always connects the shoulder and the hand', () async {
    final sim = await Sim.create(random: math.Random(3));
    sim.click(300, 400);
    sim.ticks(40);
    var worst = 0.0;
    var worstInfo = '';
    var checked = 0;

    void check(String label) {
      final w = sim.world;
      final arm = w.hand.armClip;
      if (!arm.visible) return;
      final m = arm.matrix;
      // tip of the sleeve = local point (0, -10)
      final tipX = m.c * -10 + m.tx, tipY = m.d * -10 + m.ty;
      final err = math.sqrt(math.pow(tipX - w.hand.x, 2) + math.pow(tipY - w.hand.y, 2));
      final dist = math.sqrt(math.pow(w.hand.x - m.tx, 2) + math.pow(w.hand.y - m.ty, 2));
      checked++;
      if (dist > 20 && err > worst) {
        worst = err;
        worstInfo = '$label phase=${w.phase.name} hand=(${w.hand.x.toStringAsFixed(0)},${w.hand.y.toStringAsFixed(0)}) '
            'tip=(${tipX.toStringAsFixed(0)},${tipY.toStringAsFixed(0)}) dist=${dist.toStringAsFixed(0)} '
            'rot=${arm.rotation.toStringAsFixed(0)} xs=${arm.xscale.toStringAsFixed(0)} ys=${arm.yscale.toStringAsFixed(0)}';
      }
    }

    // every shelf item, one after the other, then the garnish
    final items = [...sim.world.shelf.bottles, sim.world.shelf.ice, sim.world.shelf.lemon];
    for (final item in items) {
      final target = item is dynamic && item == sim.world.shelf.lemon
          ? sim.world.shelf.lemon.mask
          : item == sim.world.shelf.ice
              ? sim.world.shelf.ice.mask
              : item.clip;
      final p = sim.findHit(target);
      if (p == null) continue;
      sim.click(p.dx, p.dy);
      for (var i = 0; i < 70; i++) {
        sim.ticks(1);
        check(item.label);
      }
    }
    // leave screen: shake path
    final sb = sim.findHit(sim.world.hud.shakeButton)!;
    sim.press(sb.dx, sb.dy);
    for (var i = 0; i < 60; i++) {
      sim.ticks(1);
      check('shake');
    }
    sim.release(sb.dx, sb.dy);
    // ignore: avoid_print
    print('checked $checked frames; worst sleeve/hand mismatch ${worst.toStringAsFixed(1)} px: $worstInfo');
    expect(sim.world.phase, isNot(GamePhase.preGame));
  });
}
