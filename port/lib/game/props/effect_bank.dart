import 'dart:math' as math;

import '../../engine/engine.dart';
import '../effects/particle_spawner.dart';
import '../model/shaker.dart';
import 'shelf.dart';
import 'sound_bank.dart';

/// Every particle effect in the game, named after what it does. Positions and tuning are the original values.
class EffectBank {
  /// The liquid stream while pouring, and the droplets thrown off it.
  late final ParticleSpawner pourStream;
  late final ParticleSpawner pourDroplets;

  /// Pop of lemon / ice pieces on the shelf when the item is picked up.
  late final ParticleSpawner lemonPickup;
  late final ParticleSpawner icePickup;

  /// Lemon / ice dropping into the shaker.
  late final ParticleSpawner lemonIntoShaker;
  late final ParticleSpawner iceIntoShaker;

  /// The drink pouring out into the glass when served (mirrored stream), and its droplets.
  late final ParticleSpawner serveStream;
  late final ParticleSpawner serveDroplets;

  /// Lemon-garnish spray while the garnish is squeezed.
  late final ParticleSpawner garnishSpray;
  late final ParticleSpawner garnishMist;

  /// Splashes where the streams and droplets land.
  late final SplashSpawner pourSplash;
  late final SplashSpawner pourDropletSplash;
  late final SplashSpawner lemonSplash;
  late final SplashSpawner serveSplash;
  late final SplashSpawner serveDropletSplash;
  late final SplashSpawner iceSplash;

  /// Update order matters for drawing depth only; it follows the original `spawnerArray` order.
  late final List<ParticleSpawner> spawners;
  late final List<SplashSpawner> splashes;

  EffectBank(MovieClip table, math.Random random, Shaker shaker, Shelf shelf, SoundBank sounds) {
    ParticleSpawner make(
      int depth,
      double x,
      double y,
      double fx,
      double fy,
      String symbol,
      int count,
      int life,
      double damping,
      double vx,
      double vy,
      double mass, {
      bool randomScale = false,
      bool burst = false,
      double maxRotation = 0,
      double minScale = 10,
    }) =>
        ParticleSpawner(table,
            depth: depth,
            x: x,
            y: y,
            gravityForceX: fx,
            gravityForceY: fy,
            symbol: symbol,
            maxParticles: count,
            lifeSpan: life,
            damping: damping,
            spreadX: vx,
            spreadY: vy,
            mass: mass,
            random: random,
            randomScale: randomScale,
            burst: burst)
          ..maxRotationStep = maxRotation
          ..minScale = minScale;

    pourStream = make(6500, 10, 30, 3, 0, 'particle_01', 50, 50, 0.04, 0.3, 0.3, 1.5)
      ..streamColour = 0x3F95EB
      ..streamWidth = 7;
    pourDroplets = make(6501, 100, 128, 3, 0, 'particle_02', 25, 25, 0.04, 1, 1, 1.5, randomScale: true);
    lemonPickup = make(6502, shelf.lemon.x, shelf.lemon.y - 14, 0, -20, 'lemon_burst', 3, 20, 0, 5, -5, 2.4,
        randomScale: true, burst: true, maxRotation: 20, minScale: 70);
    icePickup = make(6503, shelf.ice.x, shelf.ice.y - 14, 0, -20, 'icecube_burst', 4, 20, 0, 5, -5, 2.5,
        randomScale: true, burst: true, maxRotation: 20, minScale: 70);
    lemonIntoShaker = make(6504, 180, 320, 0, 0, 'lemon_burst', 1, 37, 0, 0, 0, 1.9,
        randomScale: true, burst: true, maxRotation: 20, minScale: 70);
    iceIntoShaker = make(6514, 180, 320, 0, 0, 'icecube_burst', 3, 37, 0, 0.9, 1, 1.9,
        randomScale: true, burst: true, maxRotation: 20, minScale: 70);
    serveStream = make(6530, 10, 30, -3, 0, 'particle_01', 50, 50, 0.04, 0.3, 0.3, 1.9)
      ..streamColour = 0xFFFFFF
      ..streamWidth = 7;
    serveDroplets = make(6531, 100, 128, -3, 0, 'particle_02', 25, 25, 0.04, 1, 1, 1.9, randomScale: true);
    garnishSpray = make(6507, 430, 300, 0, -16, 'lemon_slcParticle', 4, 20, 0, 7, 7, 1.9,
        randomScale: true, maxRotation: 20, minScale: 70);
    garnishMist = make(6508, 430, 300, 0, -16, 'particle_02', 15, 15, 0, 7, 7, 1.9, randomScale: true)
      ..tint = 0xF9FF6C;

    shelf.lemon.pickupBurst = lemonPickup;
    shelf.ice.pickupBurst = icePickup;

    SplashSpawner splash(int depth, double x, double y, double fy, int count, int life, double mass,
            ParticleSpawner trigger,
            {bool randomScale = true, bool burst = true, String? symbol}) =>
        SplashSpawner(table,
            depth: depth,
            x: x,
            y: y,
            gravityForceY: fy,
            maxParticles: count,
            lifeSpan: life,
            mass: mass,
            random: random,
            trigger: trigger,
            randomScale: randomScale,
            burst: burst,
            symbol: symbol);

    pourSplash = splash(6509, shaker.x, shaker.y, -2, 10, 14, 0.6, pourStream, burst: false);
    // This one asks for no particles at all in the original (count 0); kept for faithfulness.
    pourDropletSplash = splash(6510, shaker.x, shaker.y, -2, 0, 0, 0.6, pourDroplets, burst: false);
    lemonSplash = splash(6511, shaker.x, shaker.y, -8, 10, 20, 0.9, lemonIntoShaker, symbol: 'particle_02');
    serveSplash = splash(6512, 430, 258, -8, 10, 20, 0.9, serveStream);
    // 'particle_02rsp' does not exist in the original library either, so these splashes are invisible.
    serveDropletSplash = splash(6513, 430, 258, -8, 10, 20, 0.9, serveDroplets);
    iceSplash = splash(6515, shaker.x, shaker.y, -8, 10, 20, 0.9, iceIntoShaker,
        randomScale: false, symbol: 'particle_02');
    lemonSplash.sound = sounds.lemonDrop;
    iceSplash.sound = sounds.iceGlass;

    spawners = [
      pourStream,
      pourDroplets,
      lemonPickup,
      icePickup,
      lemonIntoShaker,
      serveStream,
      serveDroplets,
      garnishSpray,
      garnishMist,
      iceIntoShaker,
    ];
    splashes = [pourSplash, pourDropletSplash, lemonSplash, serveSplash, serveDropletSplash, iceSplash];
  }

  int get liveParticles =>
      spawners.fold(0, (n, s) => n + s.particles.length) + splashes.fold(0, (n, s) => n + s.particles.length);

  void update() {
    for (final s in spawners) {
      s.update();
    }
    for (final s in splashes) {
      s.update();
      s.checkTrigger();
    }
  }
}
