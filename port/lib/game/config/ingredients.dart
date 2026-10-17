/// One bottle on the shelf. [score] is what each unit poured adds to the drink's points.
class Ingredient {
  /// Library symbol of the bottle artwork.
  final String symbol;

  /// Name shown in the info panel when the bottle is hovered.
  final String label;

  /// Position on the shelf before [shelfOffsetX] / [shelfOffsetY] are applied.
  final double x;
  final double y;

  /// Colour of the pour stream (0xRRGGBB).
  final int liquidColour;

  /// Tint for the splash droplets while this bottle is held (0xRRGGBB).
  final int highlightColour;
  final double score;

  const Ingredient(this.symbol, this.label, this.x, this.y, this.liquidColour, this.highlightColour, this.score);
}

const double shelfOffsetX = 20;
const double shelfOffsetY = 66;

/// The 21 bottles, in depth order (top shelf left to right, then the lower shelf).
///
/// Values come straight from the original `placeBottles_set()`. Note the original quirks that are kept:
/// "Champagne" appears twice, and the `bttle_amaretto` artwork is labelled "Cointreau".
const List<Ingredient> shelfIngredients = [
  Ingredient('bttle_kahlua', 'Kahlua', 6, 44, 0xD09688, 0xF8DDDC, 5),
  Ingredient('bttle_triple_sec', 'Triple Sec', 45, 44, 0xE0DFA9, 0xF9F2DF, 45),
  Ingredient('bttle_creme_de_cacao', 'Creme de Cacao', 91, 43, 0xB16F2E, 0xDFB386, 29),
  Ingredient('bttle_creme_de_menthe', 'Creme de Menthe', 140, 43, 0x0D9D0D, 0x68EC82, 13),
  Ingredient('bttle_absinthe', 'Absinthe', 187, 41, 0x1FBA3E, 0x63E47C, 13),
  Ingredient('bttle_vermouth', 'Vermouth', 227, 40, 0xC7E6E7, 0xFFFFFF, 4),
  Ingredient('bttle_calvados', 'Calvados', 273, 41, 0xEADE9F, 0xFFFFFF, 11),
  Ingredient('bttle_gin', 'Gin', 322, 41, 0xC7E6E7, 0xFFFFFF, 3),
  Ingredient('bttle_tequila', 'Tequila', 364, 40, 0xE8ED72, 0xFBFADD, 39),
  Ingredient('bttle_champagne', 'Champagne', 408, 40, 0xFBFEAF, 0xFFFFFF, 26),
  Ingredient('bttle_champagne', 'Champagne', 453, 40, 0xFBFEAF, 0xFFFFFF, 26),
  Ingredient('bttle_whisky', 'Whisky', 4.5, 150, 0xDDB471, 0xEAD0A6, 17),
  Ingredient('bttle_cognac', 'Cognac', 51, 151, 0xCD9D50, 0xDCBA83, 33),
  Ingredient('bttle_amaretto', 'Cointreau', 102, 152, 0xFFCC00, 0xFFF2C8, 20),
  Ingredient('bttle_vodka', 'Vodka', 158, 148, 0xC7E6E7, 0xFFFFFF, 50),
  Ingredient('bttle_sambuca', 'Sambuca', 202, 147, 0xCBDCDE, 0xFFFFFF, 35),
  Ingredient('bttle_orange', 'Orange Juice', 244, 150, 0xF9B15B, 0xFBCD95, 14),
  Ingredient('bttle_cranberry', 'Cranberry Juice', 291, 153, 0xE82F58, 0xF1819A, 45),
  Ingredient('bttle_lime', 'Lime Juice', 337, 154, 0xAFEA75, 0xFFFFFF, 44),
  Ingredient('bttle_passion_fruit', 'Passion Fruit Juice', 383, 154, 0xF4A659, 0xFAD1A9, 17),
  Ingredient('bttle_tonic', 'Tonic', 430, 160, 0xC8E8FF, 0xFFFFFF, 2),
];
