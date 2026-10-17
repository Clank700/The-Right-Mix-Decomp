this.onEnterFrame = function()
{
   var drinkColour;
   if(fullglass)
   {
      drinkColour = new net.pluginmedia.PIM_Colour(fullglass.drink_mc);
      drinkColour.setTint(_global.game.finalDrinkCol,50,true);
      if(!_global.game.garnishFlag)
      {
         fullglass.lemonGarnish._visible = false;
      }
      else
      {
         fullglass.lemonGarnish._visible = true;
      }
   }
};
