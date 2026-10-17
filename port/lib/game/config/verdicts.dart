/// How the barman reacts to a finished drink: which finale animation plays and what he says.
class Verdict {
  /// Library symbol suffix: the finale clip is `finale<finale>`.
  final int finale;
  final String message;
  const Verdict(this.finale, this.message);
}

/// Shown when the drink was shaken too many times ("a cocktail, not a milkshake").
const Verdict milkshakeVerdict = Verdict(
  1,
  "It's a cocktail, not a milkshake! Do be a little less heavy handed...",
);

/// Score ceilings, best match first. A score <= [ceiling] earns that verdict; anything higher is the last one.
const List<(double ceiling, Verdict verdict)> _verdictTable = [
  (1000, Verdict(2, 'A nice finishing touch might be a lemon garnish applied after shaking, as opposed to a 16 ton weight applied after drinking.')),
  (2000, Verdict(3, 'Lame, to the point of being lethal. Triple Sec might just have saved my life...')),
  (3000, Verdict(4, "My mouth is angry with my head, and that's your fault. A little more ice perhaps?")),
  (4000, Verdict(5, 'A dash of lime next time might help settle my tum...')),
  (5000, Verdict(6, "I'd like to tell you that was good, but it just wasn't. Cranberry juice is considered essential...")),
  (6000, Verdict(7, "It's like a very boring party in my mouth. Might I suggest plenty of vodka next time...")),
  (7000, Verdict(8, 'Surprisingly adequate.')),
  (8000, Verdict(9, "YOU ROCK DUDE! And that's one wailin' Cosmopolitan!")),
];

const Verdict _topVerdict = Verdict(10, "Mon Dieu! Vive l'amour! Je t'adore!!!!");

Verdict verdictForScore(double points) {
  for (final (ceiling, verdict) in _verdictTable) {
    if (points <= ceiling) return verdict;
  }
  return _topVerdict;
}

/// A drink with too few (<= 2) or too many (> 8) different ingredients has its score halved.
double adjustForVariety(double points, int variety) => (variety <= 2 || variety > 8) ? points / 2 : points;
