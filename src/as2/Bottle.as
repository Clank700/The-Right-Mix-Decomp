// Bottle
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// A bottle on the shelf. Clicking fetches it with the barman hand; when released it falls back to its shelf spot.

class Bottle
{
   var attachedToHand;
   var clip;
   var depth;
   var fluidAmount;
   var fluidCol;
   var highlightCol;
   var infoText;
   var isAdditive;
   var linkageClip;
   var objType;
   var parentObj;
   var pourOffsX;
   var pourOffsY;
   var scoreVal;
   var shopLocX;
   var shopLocY;
   var xpos;
   var xvel;
   var ypos;
   var yvel;
   /**
    * Attach the bottle clip at its shelf position and hook up click / hover behaviour.
    */
   function Bottle(par_targetObj, par_linkage, par_spawnX, par_spawnY, par_depth)
   {
      this.scoreVal = 0;
      this.shopLocX = par_spawnX;
      this.shopLocY = par_spawnY;
      this.linkageClip = par_linkage;
      this.pourOffsX = 56;
      this.pourOffsY = 30;
      this.isAdditive = false;
      this.xpos = this.shopLocX;
      this.ypos = this.shopLocY;
      this.infoText = "";
      this.xvel = 0;
      this.yvel = 0;
      this.objType = "bottle";
      this.depth = par_depth;
      this.fluidAmount = 1;
      this.fluidCol = 0;
      this.highlightCol = null;
      this.attachedToHand = false;
      this.clip = par_targetObj.attachMovie(this.linkageClip,this.linkageClip + this.depth,this.depth);
      this.clip.gotoAndStop(1);
      this.clip.parentObj = this;
      this.clip.onPress = function()
      {
         if(_global.game.gameState == "rest" && !_global.game.gameShaker.isFull || _global.game.gameState == "getBottle")
         {
            _global.game.barmanHand.fetchTarget(this.parentObj);
            _global.game.switchState("getBottle");
         }
      };
      this.clip.onRollOver = function()
      {
         if(_global.game.gameState == "rest" && !_global.game.gameShaker.isFull || _global.game.gameState == "getBottle")
         {
            _global.game.dynText.info.text = this.parentObj.infoText;
         }
      };
      this.clip.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.updateClip();
   }
   /**
    * Toggle between "in the barman's hand" and "back on the shelf".
    */
   function pushHandAction()
   {
      if(!this.attachedToHand)
      {
         this.attachedToHand = true;
         this.yvel = this.xvel = 0;
         this.clip.gotoAndStop(2);
         this.clip.shadow._visible = false;
      }
      else
      {
         this.clip.gotoAndStop(1);
         this.clip._rotation = 0;
         this.clip.shadow._visible = true;
         this.attachedToHand = false;
         this.xpos = this.shopLocX;
         this.ypos = this.shopLocY;
         this.updateClip();
      }
   }
   /**
    * Copy the bottle position to its clip.
    */
   function updateClip()
   {
      this.clip._x = this.xpos;
      this.clip._y = this.ypos;
   }
   /**
    * Per-frame: follow the hand while held, otherwise bounce back onto the shelf.
    */
   function update()
   {
      if(this.attachedToHand)
      {
         this.xpos = _global.game.barmanHand.xpos;
         this.ypos = _global.game.barmanHand.ypos;
      }
      else
      {
         this.xvel *= 0.9;
         this.yvel *= 0.9;
         if(this.ypos < this.shopLocY - 1)
         {
            this.yvel += 1;
         }
         else
         {
            this.yvel *= -0.2;
            this.ypos = this.shopLocY;
         }
         this.ypos += this.yvel;
         this.xpos += this.xvel;
      }
      this.updateClip();
   }
}
