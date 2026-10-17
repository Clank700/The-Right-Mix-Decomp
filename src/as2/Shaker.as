// Shaker
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// The cocktail shaker: how much has been poured, which ingredients, and the points earned so far.

class Shaker
{
   var fluidVol;
   var isFull;
   var lastPushFluid;
   var maxVol;
   var pointsWon;
   var shakeCycles;
   var variety;
   var xpos;
   var ypos;
   /**
    * Create an empty shaker at the given screen position (the splash zone for pouring).
    */
   function Shaker(par_spawnX, par_spawnY)
   {
      this.fluidVol = 0;
      this.maxVol = 180;
      this.isFull = false;
      this.shakeCycles = 0;
      this.lastPushFluid = 0;
      this.variety = 0;
      this.xpos = par_spawnX;
      this.ypos = par_spawnY;
      this.pointsWon = 0;
   }
   /**
    * Pour par_fluidAmount of an ingredient worth par_pointage points. Counts ingredient variety, tints
    * the final drink for a few signature ingredients, and flags the shaker as full at maxVol.
    */
   function pushFluid(par_fluidAmount, par_pointage)
   {
      if(this.lastPushFluid != par_pointage)
      {
         this.variety++;
         trace("oohh.. variety :D");
      }
      switch(par_pointage)
      {
         case 13:
            _global.game.finalDrinkCol = 13167816;
            break;
         case 45:
            _global.game.finalDrinkCol = 16694460;
            break;
         case 29:
            _global.game.finalDrinkCol = 15721419;
            break;
      }
      if(this.fluidVol < this.maxVol)
      {
         this.fluidVol += par_fluidAmount;
         this.pointsWon += par_pointage;
         trace("points: " + this.pointsWon);
         this.lastPushFluid = par_pointage;
      }
      else
      {
         this.isFull = true;
      }
   }
}
