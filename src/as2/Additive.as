// Additive
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// The ice bucket and the lemon bowl (extends Bottle). The clickable area is a separate "mask" clip.

class Additive extends Bottle
{
   var additiveContainer;
   var attachedToHand;
   var clip;
   var clipMask;
   var depth;
   var isAdditive;
   var linkageClip;
   var linkedSpawner;
   var parentObj;
   var scoreVal;
   var shopLocX;
   var shopLocY;
   var xpos;
   var ypos;
   /**
    * Create the item clip and its clickable mask clip. Note: super() is called without arguments.
    */
   function Additive(par_targetObj, par_linkage, par_spawnX, par_spawnY, par_depth, par_linkedSpawner)
   {
      super();
      this.shopLocX = par_spawnX;
      this.shopLocY = par_spawnY;
      this.scoreVal = 0;
      this.isAdditive = true;
      this.linkedSpawner = par_linkedSpawner;
      this.linkageClip = par_linkage;
      this.xpos = this.shopLocX;
      this.ypos = this.shopLocY;
      this.depth = par_depth;
      this.attachedToHand = false;
      this.additiveContainer = par_targetObj.createEmptyMovieClip("additive" + this.depth,this.depth);
      this.clip = this.additiveContainer.attachMovie(par_linkage,par_linkage + this.depth,0);
      this.clip.gotoAndStop(1);
      this.clipMask = this.additiveContainer.attachMovie(par_linkage + "_mask",this.clip._name + "_mask",1);
      this.clipMask._x = this.xpos;
      this.clipMask._y = this.ypos;
      this.clipMask.parentObj = this;
      this.clipMask.onPress = function()
      {
         if(_global.game.gameState == "rest" && !_global.game.gameShaker.isFull || _global.game.gameState == "getBottle")
         {
            _global.game.barmanHand.fetchTarget(this.parentObj);
            _global.game.switchState("getBottle");
         }
      };
      this.clipMask.onRollOver = function()
      {
         if(_global.game.gameState == "rest" && !_global.game.gameShaker.isFull || _global.game.gameState == "getBottle")
         {
            _global.game.dynText.info.text = this.parentObj.infoText;
         }
      };
      this.clipMask.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.updateClip();
   }
   /**
    * Pick up / put back; picking up also pops a burst of pieces from the linked spawner.
    */
   function pushHandAction()
   {
      this.linkedSpawner.kickUpdate();
      if(!this.attachedToHand)
      {
         this.attachedToHand = true;
      }
      else
      {
         this.attachedToHand = false;
         this.xpos = this.shopLocX;
         this.ypos = this.shopLocY;
         this.updateClip();
      }
   }
   /**
    * Copy the item position to its clip.
    */
   function updateClip()
   {
      this.clip._x = this.xpos;
      this.clip._y = this.ypos;
   }
   /**
    * Per-frame: follow the hand while held (hidden while the garnish is being served).
    * The bare gotoAndStop(1) in the original compiled to a lone GotoFrame action that has no visible
    * effect; it is written here as the pseudo-function gotoFrame(1).
    */
   function update()
   {
      if(this.attachedToHand)
      {
         this.xpos = _global.game.barmanHand.xpos;
         this.ypos = _global.game.barmanHand.ypos;
         if(_global.game.garnishFlag)
         {
            this.clip._visible = false;
         }
         else if(!this.clip._visible)
         {
            this.clip._visible = true;
         }
         this.updateClip();
      }
      else if(this.clip._currentframe != 1)
      {
         gotoFrame(1);
      }
   }
}
