import 'package:flutter_test/flutter_test.dart';
import 'package:the_right_mix/game/world.dart';

import 'sim_helpers.dart';

// Stage coordinates (600 x 440).
const startKnob = (300.0, 400.0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('boots into the intro card and starts a game', () async {
    final sim = await Sim.create();
    expect(sim.world.phase, GamePhase.preGame);
    sim.ticks(3);
    await sim.save('01_intro');
    sim.click(startKnob.$1, startKnob.$2);
    expect(sim.world.phase, GamePhase.rest);
    sim.ticks(40);
    expect(sim.world.introCard.visible, isFalse, reason: 'intro card hides itself after its animation');
    await sim.save('02_bar');
  });

  test('a quick tap on the start knob (press and release in the same frame) still starts the game', () async {
    final sim = await Sim.create();
    sim.click(startKnob.$1, startKnob.$2, hold: 0);
    expect(sim.world.phase, GamePhase.rest);
  });

  test('fetch a bottle, pour it, shake, serve and reach an ending', () async {
    final sim = await Sim.create();
    sim.click(startKnob.$1, startKnob.$2);
    sim.ticks(40);

    final v = sim.findHit(sim.world.shelf.bottles[14].clip)!; // the vodka bottle
    sim.click(v.dx, v.dy);
    sim.ticks(60);
    expect(sim.world.hand.holdingItem, isTrue, reason: 'hand should be holding the bottle');
    expect(sim.world.hud.idleText, 'Hold pour to add...');
    await sim.save('03_holding');

    final pb = sim.findHit(sim.world.hud.pourButton)!;
    sim.move(pb.dx, pb.dy);
    sim.press(pb.dx, pb.dy);
    sim.ticks(90);
    await sim.save('04_pouring');
    expect(sim.world.phase, GamePhase.pour);
    expect(sim.world.shaker.fluidVolume, greaterThan(20));
    expect(sim.world.shaker.points, greaterThan(0));
    sim.release(pb.dx, pb.dy);
    sim.ticks(40);
    expect(sim.world.phase, GamePhase.rest);

    final sb = sim.findHit(sim.world.hud.shakeButton)!;
    sim.move(sb.dx, sb.dy);
    sim.press(sb.dx, sb.dy);
    sim.ticks(80);
    await sim.save('05_shaking');
    sim.release(sb.dx, sb.dy);
    sim.ticks(10);

    final vb = sim.findHit(sim.world.hud.serveButton)!;
    sim.move(vb.dx, vb.dy);
    sim.press(vb.dx, vb.dy);
    sim.ticks(2);
    sim.release(vb.dx, vb.dy);
    sim.ticks(150);
    await sim.save('06_serve');
    sim.ticks(400);
    await sim.save('07_end');
    expect(sim.world.phase, anyOf(GamePhase.waitInput, GamePhase.finale, GamePhase.endGame));
    expect(sim.world.verdict.finale, inInclusiveRange(2, 10));
  });

  test('five shakes ruin the drink (milkshake ending, no score)', () async {
    final sim = await Sim.create();
    sim.click(startKnob.$1, startKnob.$2);
    sim.ticks(40);
    final v = sim.findHit(sim.world.shelf.bottles[3].clip)!;
    sim.click(v.dx, v.dy);
    sim.ticks(60);
    final pb = sim.findHit(sim.world.hud.pourButton)!;
    sim.move(pb.dx, pb.dy);
    sim.press(pb.dx, pb.dy);
    sim.ticks(40);
    sim.release(pb.dx, pb.dy);
    sim.ticks(30);
    final sb = sim.findHit(sim.world.hud.shakeButton)!;
    sim.move(sb.dx, sb.dy);
    sim.press(sb.dx, sb.dy);
    sim.ticks(600);
    expect(sim.world.verdict.finale, 1);
    expect(sim.world.shaker.points, 0);
  });
}
