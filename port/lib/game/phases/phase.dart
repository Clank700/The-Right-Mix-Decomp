import '../world.dart';

/// One stage of a round. [update] runs once per frame (18 per second) while the world is in that stage and
/// switches `world.phase` when it is time to move on.
abstract class Phase {
  const Phase();
  void update(GameWorld world);
}
