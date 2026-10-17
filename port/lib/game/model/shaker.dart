/// Pure game state of the cocktail shaker: what has been poured and the points earned so far.
/// It knows nothing about clips or the scene, so it can be unit tested on its own.
class Shaker {
  static const double capacity = 180;
  static const int defaultDrinkColour = 0xFFFF99;

  final double x;
  final double y;

  double fluidVolume = 0;
  bool isFull = false;
  int shakeCycles = 0;

  /// Distinct ingredients so far (counted whenever the poured ingredient changes).
  int variety = 0;
  double points = 0;

  /// Tint of the finished drink; a few signature ingredients change it.
  int drinkColour = defaultDrinkColour;
  double _lastIngredientScore = 0;

  Shaker(this.x, this.y);

  /// Add [amount] of an ingredient worth [ingredientScore] points.
  ///
  /// Nothing is added once the shaker is at capacity; that call just flags it as full.
  void pour(double amount, double ingredientScore) {
    if (_lastIngredientScore != ingredientScore) variety++;
    // The ingredient's score doubles as its identity for the drink colour (Creme de Menthe / Absinthe, Triple Sec
    // and Cranberry, Creme de Cacao).
    switch (ingredientScore.toInt()) {
      case 13:
        drinkColour = 0xC8ECC8;
      case 45:
        drinkColour = 0xFEBCBC;
      case 29:
        drinkColour = 0xEFE3CB;
    }
    if (fluidVolume < capacity) {
      fluidVolume += amount;
      points += ingredientScore;
      _lastIngredientScore = ingredientScore;
    } else {
      isFull = true;
    }
  }

  /// Empty the shaker for the next drink.
  void reset() {
    points = 0;
    fluidVolume = 0;
    _lastIngredientScore = 0;
    variety = 0;
    shakeCycles = 0;
    isFull = false;
    drinkColour = defaultDrinkColour;
  }
}
