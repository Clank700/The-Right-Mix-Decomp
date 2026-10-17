import '../../engine/engine.dart';
import '../config/ingredients.dart';
import '../effects/particle_spawner.dart';
import '../world.dart';

/// Anything the barman can pick up from the bar: bottles, the ice bucket and the lemon bowl.
abstract class ShelfItem {
  final GameWorld world;
  final int depth;

  /// Where the item lives when it is not in the hand.
  final double homeX;
  final double homeY;

  /// Current position (the clip follows this).
  double x;
  double y;

  late final MovieClip clip;
  String label = '';
  double score = 0;
  bool inHand = false;

  /// Colour of the pour stream and of the splash droplets while this item is held.
  int liquidColour = 0;
  int? highlightColour;

  ShelfItem(this.world, this.depth, this.homeX, this.homeY)
      : x = homeX,
        y = homeY;

  bool get isAdditive => false;

  /// Where the stream leaves the bottle relative to the hand.
  double get pourOffsetX => 56;
  double get pourOffsetY => 30;

  /// Hook up the click / hover behaviour on the clip that receives the pointer.
  void bindPointer(MovieClip target) {
    target.onPress = () {
      if (world.canFetch) {
        world.hand.fetch(this);
        world.phase = GamePhase.getBottle;
      }
    };
    target.onRollOver = () {
      if (world.canFetch) world.hud.showInfo(label);
    };
    target.onRollOut = () => world.hud.showIdle();
  }

  /// Called by the hand when it picks the item up and again when it puts it back.
  void toggleHeld();

  void syncClip() {
    // A free-standing item only moves by falling and bouncing (a few px per tick). A bigger move is a jump (the
    // original quirk of a dropped bottle reappearing at the hand): draw it where it lands.
    if (!inHand) {
      final dx = x - clip.x, dy = y - clip.y;
      if (dx * dx + dy * dy > 60 * 60) clip.breakBlend();
    }
    clip.x = x;
    clip.y = y;
  }

  void update();
}

/// A liquor or juice bottle. Falls back to its shelf spot with a damped bounce when dropped.
class Bottle extends ShelfItem {
  double velX = 0;
  double velY = 0;

  Bottle(GameWorld world, Ingredient ingredient, int depth)
      : super(world, depth, ingredient.x + shelfOffsetX, ingredient.y + shelfOffsetY) {
    label = ingredient.label;
    score = ingredient.score;
    liquidColour = ingredient.liquidColour;
    highlightColour = ingredient.highlightColour;
    clip = world.table.attachMovie(ingredient.symbol, '${ingredient.symbol}$depth', depth)!;
    clip.gotoAndStop(1);
    clip.parentObj = this;
    bindPointer(clip);
    syncClip();
  }

  @override
  void toggleHeld() {
    final shadow = clip.clipChild('shadow');
    clip.breakBlend(); // picked up / put back: the bottle jumps between the shelf and the hand
    if (!inHand) {
      inHand = true;
      velX = velY = 0;
      clip.gotoAndStop(2);
      shadow?.visible = false;
    } else {
      clip.gotoAndStop(1);
      clip.rotation = 0;
      shadow?.visible = true;
      inHand = false;
      x = homeX;
      y = homeY;
      syncClip();
    }
  }

  @override
  void update() {
    if (inHand) {
      x = world.hand.x;
      y = world.hand.y;
    } else {
      velX *= 0.9;
      velY *= 0.9;
      if (y < homeY - 1) {
        velY += 1; // gravity
      } else {
        velY *= -0.2; // bounce
        y = homeY;
      }
      y += velY;
      x += velX;
    }
    syncClip();
  }
}

enum AdditiveKind { ice, lemon }

/// The ice bucket and the lemon bowl. Their clickable area is a separate "mask" clip.
class Additive extends ShelfItem {
  final AdditiveKind kind;

  /// Burst played on the shelf when the item is picked up (set once the effects exist).
  ParticleSpawner? pickupBurst;
  late final MovieClip _container;
  late final MovieClip mask;

  Additive(GameWorld world, this.kind, String symbol, double x, double y, int depth)
      : super(world, depth, x, y) {
    _container = world.table.createEmptyMovieClip('additive$depth', depth);
    clip = _container.attachMovie(symbol, '$symbol$depth', 0)!;
    clip.gotoAndStop(1);
    mask = _container.attachMovie('${symbol}_mask', '${clip.name}_mask', 1)!;
    mask.x = x;
    mask.y = y;
    mask.parentObj = this;
    bindPointer(mask);
    syncClip();
  }

  @override
  bool get isAdditive => true;

  @override
  void toggleHeld() {
    pickupBurst?.kick();
    clip.breakBlend();
    if (!inHand) {
      inHand = true;
    } else {
      inHand = false;
      x = homeX;
      y = homeY;
      syncClip();
    }
  }

  @override
  void update() {
    if (!inHand) return;
    x = world.hand.x;
    y = world.hand.y;
    // The lemon disappears from the hand once the garnish is being served.
    clip.visible = !world.garnished;
    syncClip();
    // (The original also had a bare `gotoAndStop(1)` here that targeted nothing visible; it is omitted.)
  }
}

/// All 21 bottles plus the ice bucket and the lemon bowl.
class Shelf {
  final List<Bottle> bottles;
  final Additive ice;
  final Additive lemon;

  Shelf(GameWorld world, int Function() nextDepth)
      : bottles = [for (final i in shelfIngredients) Bottle(world, i, nextDepth())],
        ice = Additive(world, AdditiveKind.ice, 'icecube', 58, 256, 6600)
          ..label = 'Add a little ice'
          ..score = 1000,
        lemon = Additive(world, AdditiveKind.lemon, 'lemon', 140, 268, 6601)
          ..label = 'Add a lemon!?'
          ..score = -100;

  void update() {
    for (final b in bottles) {
      b.update();
    }
    lemon.update();
    ice.update();
  }
}
