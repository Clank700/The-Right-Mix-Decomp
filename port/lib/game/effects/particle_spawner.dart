import 'dart:math' as math;

import '../../engine/engine.dart';

/// A short-lived sprite with simple physics, owned by a [ParticleSpawner].
class Particle {
  double x;
  double y;
  double velX;
  double velY;
  final double mass;
  final double rotationStep;
  final double startScale;
  final int depth;
  int life;
  final MovieClip? clip;

  Particle({
    required MovieClip parent,
    required math.Random random,
    required this.x,
    required this.y,
    required this.velX,
    required this.velY,
    required this.mass,
    required double maxRotationStep,
    required double scale,
    required String symbol,
    required this.life,
    required this.depth,
    required int? tint,
  })  : rotationStep = random.nextDouble() * maxRotationStep,
        startScale = scale,
        clip = parent.attachMovie(symbol, 'clipIDName$depth', depth) {
    final sprite = clip;
    if (sprite != null) {
      // A tint of 0 (or none) means "keep the artwork's own colours", as in the original.
      if (tint != null && tint != 0) ColorControl(sprite).setSolidColour(tint);
      sprite.xscale = scale;
      sprite.yscale = scale;
    }
    syncClip();
  }

  void syncClip() {
    clip?.x = x;
    clip?.y = y;
  }

  void remove() => clip?.removeFromParent();
}

/// Emits [Particle]s: the pour stream, ice and lemon bursts, serve splashes.
///
/// Port of the original `DoubleParticleSpawner`. That class could also attach a second "double" clip to each
/// particle; every spawner in the game had the feature switched off, so it is not ported.
class ParticleSpawner {
  /// Depth range of the pool that child particle depths are drawn from.
  static const int defaultFirstDepth = 1;
  static const int defaultLastDepth = 101;

  final MovieClip layer;
  final math.Random random;

  double x;
  double y;
  final String symbol;
  final double gravityForceX;
  final double gravityForceY;
  final int maxParticles;
  final int lifeSpan;
  final double drag; // velocity is multiplied by (1 - damping) each step
  final double spreadX;
  final double spreadY;
  final double mass;
  final bool randomVelocity;
  final bool randomScale;
  final bool fadeOut;
  final bool shrink;

  /// Spawn [maxParticles] at once (a burst) instead of a steady trickle.
  final bool burst;
  double maxRotationStep = 0;
  double minScale = 10;
  double maxScale = 100;
  int? tint;

  /// When set, a line is drawn through consecutive particles (the liquid stream).
  int? streamColour;
  double streamWidth = 0;

  /// While locked, no new particles are emitted (existing ones keep moving).
  bool emitLocked;

  final List<int> _depthPool = [];
  final List<Particle> particles = [];

  late final MovieClip _stream = layer.createEmptyMovieClip('lineClip', 0);

  ParticleSpawner(
    MovieClip parent, {
    required int depth,
    required this.x,
    required this.y,
    required this.gravityForceX,
    required this.gravityForceY,
    required this.symbol,
    required this.maxParticles,
    required this.lifeSpan,
    required double damping,
    required this.spreadX,
    required this.spreadY,
    required this.mass,
    required this.random,
    this.randomVelocity = true,
    this.randomScale = false,
    this.fadeOut = false,
    this.shrink = false,
    this.burst = false,
    this.emitLocked = true,
    int firstDepth = defaultFirstDepth,
    int lastDepth = defaultLastDepth,
    bool hasStreamLayer = true,
  })  : drag = 1 - damping,
        layer = parent.createEmptyMovieClip('pspawner$depth', depth) {
    if (hasStreamLayer) _stream; // create the line layer now so its depth matches the original
    for (var i = firstDepth; i <= lastDepth; i++) {
      _depthPool.insert(0, i);
    }
  }

  double _between(double min, double max) => random.nextDouble() * (max - min) + min;

  /// Emit one burst of particles right now, regardless of the lock.
  void kick() {
    emitLocked = false;
    update();
    emitLocked = true;
  }

  void _emit() {
    final scale = randomScale ? _between(minScale, maxScale) : 100.0;
    final double vx, vy;
    if (randomVelocity) {
      vx = gravityForceX + _between(-spreadX, spreadX);
      vy = gravityForceY + mass + _between(-spreadY, spreadY);
    } else {
      vx = gravityForceX + spreadX;
      vy = gravityForceY + mass + spreadY;
    }
    particles.add(Particle(
      parent: layer,
      random: random,
      x: x,
      y: y,
      velX: vx,
      velY: vy,
      mass: mass,
      maxRotationStep: maxRotationStep,
      scale: scale,
      symbol: symbol,
      life: lifeSpan,
      depth: _depthPool.removeLast(),
      tint: tint,
    ));
  }

  /// Advance every particle one step, retire the dead ones, and emit new ones unless locked.
  void update() {
    final stream = streamColour == null ? null : _stream;
    if (stream != null) {
      stream.clearDrawing();
      stream.lineStyle(streamWidth, streamColour!, 100);
    }
    var i = 0;
    while (i < particles.length) {
      final p = particles[i];
      // (The original could run several physics sub-steps per frame; every spawner uses exactly one.)
      p.velX *= drag;
      p.velY *= drag;
      p.velY += p.mass;
      p.x += p.velX;
      p.y += p.velY;
      if (p.rotationStep > 0) p.clip?.rotation = (p.clip?.rotation ?? 0) + p.rotationStep;
      if (i > 0 && stream != null) {
        final prev = particles[i - 1];
        if ((p.y - prev.y).abs() < 35) {
          stream.moveTo(p.x, p.y);
          stream.lineTo(prev.x, prev.y);
        }
      }
      p.syncClip();
      final lifeLeft = p.life / lifeSpan;
      if (fadeOut) p.clip?.alpha = (lifeLeft * 100).roundToDouble();
      if (shrink) {
        final s = (lifeLeft * p.startScale).roundToDouble();
        p.clip?.xscale = s;
        p.clip?.yscale = s;
      }
      p.life--;
      if (p.life <= 0) {
        _depthPool.insert(0, p.depth);
        p.remove();
        particles.removeAt(i);
      } else {
        i++;
      }
    }
    if (emitLocked || particles.length >= maxParticles) return;
    if (burst) {
      for (var n = particles.length; n < maxParticles; n++) {
        _emit();
      }
    } else {
      final perFrame = maxParticles > lifeSpan ? (maxParticles / lifeSpan).floor() : 1;
      for (var n = 0; n < perFrame; n++) {
        _emit();
      }
    }
  }
}

/// A splash that fires when particles of [trigger] fall below the splash line [y].
class SplashSpawner extends ParticleSpawner {
  final ParticleSpawner trigger;
  SoundObject? sound;

  SplashSpawner(
    super.parent, {
    required super.depth,
    required super.x,
    required super.y,
    required super.gravityForceY,
    required super.maxParticles,
    required super.lifeSpan,
    required super.mass,
    required super.random,
    required this.trigger,
    super.randomScale = true,
    super.burst = false,
    String? symbol,
  }) : super(
          symbol: symbol ?? '${trigger.symbol}rsp',
          gravityForceX: 0,
          damping: 0.04,
          spreadX: 5,
          spreadY: 5,
          fadeOut: true,
          shrink: true,
          firstDepth: 0,
          lastDepth: 100,
          hasStreamLayer: false,
        );

  /// A splash only emits on the frame after it has been triggered.
  @override
  void kick() {
    emitLocked = false;
  }

  /// Called once per frame after [update]: re-lock, then fire again if a trigger particle is below the line.
  void checkTrigger() {
    emitLocked = true;
    for (final p in trigger.particles) {
      if (p.y >= y) {
        p.life = 0;
        kick();
        sound
          ?..stop()
          ..start();
      }
    }
  }
}
