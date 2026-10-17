// BarmanHand
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// The barman's hand and arm sleeve: fetches bottles, pours them, returns them and slides off screen.

class BarmanHand
{
   var amplitude;
   var ang;
   var apiClip;
   var armSegmentClip;
   var atRest;
   var beginPour;
   var clip;
   var cosinusStorageArray;
   var currentTargetX;
   var currentTargetY;
   var depth;
   var grabBottleStepCounter;
   var inHandObj;
   var itemInHand;
   var lastTargetObj;
   var lastTargetX;
   var lastTargetY;
   var moveStep;
   var originX;
   var originY;
   var pourStartNoiseFlag;
   var restposX;
   var restposY;
   var retrievedGoal;
   var rotation_deg;
   var rotation_rad;
   var sinCounter;
   var sinusStorageArray;
   var targetObj;
   var targetX;
   var targetY;
   var wavelength;
   var xpos;
   var xvel;
   var ypos;
   var yvel;
   /**
    * Create the hand and arm sleeve clips and a table of sine values used for the pouring wobble.
    */
   function BarmanHand(par_targetClip, par_originX, par_originY, par_depth)
   {
      this.wavelength = 40;
      this.amplitude = 5;
      this.sinCounter = 0;
      this.sinusStorageArray = new Array(this.wavelength);
      this.cosinusStorageArray = new Array(this.wavelength);
      var i = 0;
      var angle;
      while(i <= this.wavelength)
      {
         angle = i / this.wavelength * 2 * 3.141592653589793;
         this.sinusStorageArray[i] = Math.sin(angle);
         this.cosinusStorageArray[i] = Math.sin(angle);
         i++;
      }
      this.depth = par_depth;
      this.retrievedGoal = true;
      this.itemInHand = false;
      this.inHandObj = null;
      this.pourStartNoiseFlag = false;
      this.atRest = true;
      this.rotation_rad = 0;
      this.rotation_deg = 0;
      this.originX = par_originX;
      this.originY = par_originY;
      this.restposX = this.originX;
      this.restposY = this.originY;
      this.xpos = this.originX;
      this.ypos = this.originY;
      this.targetX = 0;
      this.targetY = 0;
      this.currentTargetX = this.targetX;
      this.currentTargetY = this.targetY;
      this.lastTargetX = this.originX;
      this.lastTargetY = this.originY;
      this.beginPour = false;
      this.grabBottleStepCounter = 0;
      this.xvel = 0;
      this.yvel = 0;
      this.moveStep = 2;
      this.armSegmentClip = par_targetClip.attachMovie("armSeg","armSegClip",56);
      this.armSegmentClip._x = this.originX;
      this.armSegmentClip._y = this.originY;
      this.clip = par_targetClip.attachMovie("hand","barmanhand",this.depth);
      this.clip.gotoAndStop(1);
      this.clip._visible = false;
      this.apiClip = this.clip.createEmptyMovieClip("barmanHandAPIClip",0);
   }
   /**
    * Start reaching for a bottle or additive (or, if one is held, put it back first).
    */
   function fetchTarget(par_targetObj)
   {
      if(this.retrievedGoal)
      {
         this.targetObj = par_targetObj;
         this.retrievedGoal = false;
         this.grabBottleStepCounter = 0;
         this.clip._visible = true;
         this.armSegmentClip._visible = true;
         if(!this.itemInHand && !this.retrievedGoal)
         {
            if(!this.targetObj.isAdditive)
            {
               this.targetObj.clip.swapDepths(_global.game.activeBottleDepth);
            }
            if(_global.game.miguel._currentframe != 24 && !_global.game.garnishFlag)
            {
               _global.game.miguel.gotoAndPlay(1);
            }
            this.currentTargetX = this.targetObj.xpos;
            this.currentTargetY = this.targetObj.ypos;
         }
         else
         {
            this.currentTargetX = this.lastTargetObj.shopLocX;
            this.currentTargetY = this.lastTargetObj.shopLocY;
         }
      }
   }
   /**
    * Position the hand clip and stretch / rotate the arm sleeve from the shoulder to the hand.
    */
   function updateClip()
   {
      if(!this.itemInHand)
      {
         this.clip.gotoAndStop(1);
      }
      else
      {
         this.clip.gotoAndStop(2);
      }
      this.clip._x = this.xpos;
      this.clip._y = this.ypos;
      var dy = this.armSegmentClip._y - this.clip._y;
      var dx = this.armSegmentClip._x - this.clip._x;
      this.ang = Math.atan(dy / dx) * 180 / 3.141592653589793 - 90;
      if(this.ang < 0)
      {
         this.ang = 360 - Math.abs(this.ang);
      }
      this.armSegmentClip._rotation = this.ang;
      var distance = Math.sqrt(dy * dy + dx * dx);
      this.armSegmentClip._yscale = 10 * distance;
   }
   /**
    * Move par_moveObj a fraction par_damping towards the target; true once close enough.
    */
   function easeToTarget(par_moveObj, par_tarX, par_tarY, par_damping, par_minDistance)
   {
      par_moveObj.ypos -= (par_moveObj.ypos - par_tarY) * par_damping;
      par_moveObj.xpos -= (par_moveObj.xpos - par_tarX) * par_damping;
      var dy = par_moveObj.ypos - par_tarY;
      var dx = par_moveObj.xpos - par_tarX;
      var distanceSquared = dy * dy + dx * dx;
      if(distanceSquared < par_minDistance)
      {
         return true;
      }
      else
      {
         return false;
      }
   }
   /**
    * Game state getBottle: travel, grab (or return) the item, then retreat to the rest position.
    */
   function moveHandToGoal()
   {
      this.pourStartNoiseFlag = false;
      if(_global.game.pour.getVolume() > 0)
      {
         _global.game.pour.setVolume(_global.game.pour.getVolume() - 2);
      }
      if(!this.itemInHand)
      {
         this.clip._rotation = this.ang + 70;
      }
      else
      {
         this.clip._rotation = 0;
      }
      if(this.easeToTarget(this,this.currentTargetX,this.currentTargetY,0.65,8))
      {
         this.grabBottleStepCounter++;
         if(this.grabBottleStepCounter == 1)
         {
            if(!this.itemInHand)
            {
               this.itemInHand = true;
               _global.game.infoText = "Hold pour to add...";
               _global.game.dynText.info.text = _global.game.infoText;
               this.targetObj.pushHandAction();
               if(!this.targetObj.isAdditive)
               {
                  this.targetObj.clip.swapDepths(_global.game.handOnActiveBottleDepth);
               }
               if(!_global.game.garnishFlag)
               {
                  this.restposX = this.originX - 100;
                  this.restposY = this.originY - 30;
               }
               else
               {
                  this.restposX = this.originX - 10;
                  this.restposY = this.originY + 90;
               }
            }
            else
            {
               this.lastTargetObj.pushHandAction();
               if(!this.lastTargetObj.isAdditive)
               {
                  this.lastTargetObj.clip.swapDepths(this.lastTargetObj.depth);
               }
               this.restposX = this.originX;
               this.restposY = this.originY;
               this.itemInHand = false;
            }
            this.currentTargetX = this.restposX;
            this.currentTargetY = this.restposY;
         }
         else if(this.grabBottleStepCounter == 2)
         {
            if(!this.itemInHand)
            {
               if(this.targetObj != this.lastTargetObj)
               {
                  this.retrievedGoal = true;
                  this.fetchTarget(this.targetObj);
               }
               else
               {
                  this.retrievedGoal = true;
                  _global.game.switchState("returnTweenHand");
               }
            }
            else
            {
               this.retrievedGoal = true;
               this.inHandObj = this.targetObj;
               _global.game.spawnerArray[1].tintParticles = this.inHandObj.highlightCol;
               this.lastTargetObj = this.targetObj;
               if(_global.game.garnishFlag)
               {
                  trace("got lemon - returning tween hand");
                  _global.game.switchState("returnTweenHand");
               }
               else
               {
                  _global.game.switchState("rest");
               }
            }
         }
      }
   }
   /**
    * Game state rest: hang at the rest position and straighten the held bottle.
    */
   function returnToRest()
   {
      if(this.inHandObj)
      {
         if(this.inHandObj.clip._rotation > 0)
         {
            this.inHandObj.clip._rotation -= this.inHandObj.clip._rotation * 0.4;
            this.clip._rotation = this.inHandObj.clip._rotation;
         }
      }
      else
      {
      }
      this.pourStartNoiseFlag = false;
      if(_global.game.pour.getVolume() > 0)
      {
         _global.game.pour.setVolume(_global.game.pour.getVolume() - 2);
      }
      _global.game.spawnerArray[0].pushLocked = true;
      _global.game.spawnerArray[1].pushLocked = true;
      this.beginPour = false;
      this.easeToTarget(this,this.restposX,this.restposY,0.2,2);
   }
   /**
    * Game state returnTweenHand: slide off the bottom of the screen and lower Miguel's arm.
    */
   function returnTweenHand()
   {
      this.pourStartNoiseFlag = false;
      if(_global.game.pour.getVolume() > 0)
      {
         _global.game.pour.setVolume(_global.game.pour.getVolume() - 2);
      }
      var targetFrame;
      if(_global.game.garnishFlag)
      {
         if(this.easeToTarget(this,500,400,0.2,2))
         {
            _global.game.switchState("serveLemon");
         }
         trace("returning tween hand with lemon");
      }
      else if(this.easeToTarget(this,500,400,0.3,6))
      {
         this.clip._visible = false;
         if(_global.game.miguel._currentframe > 1)
         {
            targetFrame = _global.game.miguel._currentframe - 3;
            if(targetFrame < 1)
            {
               targetFrame = 1;
            }
            _global.game.miguel.gotoAndStop(targetFrame);
         }
         else if(_global.game.preShakeReplacement)
         {
            _global.game.miguel.gotoAndStop(25);
            _global.game.switchState("shakeRest");
            _global.game.preShakeReplacement = false;
         }
         else
         {
            _global.game.switchState("getBottle");
         }
      }
   }
   /**
    * Game state pour: tip the bottle over the shaker, or drop in ice / lemon.
    */
   function pour()
   {
      var burstIndex;
      if(!this.inHandObj.isAdditive)
      {
         if(this.easeToTarget(this,this.originX - 130,this.originY - 130,0.5,4) && !this.beginPour)
         {
            this.beginPour = true;
         }
         if(this.beginPour)
         {
            if(this.sinCounter < this.wavelength)
            {
               this.sinCounter++;
            }
            else
            {
               this.sinCounter = 0;
            }
            this.ypos += this.sinusStorageArray[this.sinCounter] * this.amplitude;
         }
         this.inHandObj.xpos = this.xpos;
         this.inHandObj.ypos = this.ypos;
         _global.game.spawnerArray[0].xpos = this.inHandObj.xpos + this.inHandObj.pourOffsX;
         _global.game.spawnerArray[1].xpos = this.inHandObj.xpos + this.inHandObj.pourOffsX;
         _global.game.spawnerArray[0].ypos = this.inHandObj.ypos + this.inHandObj.pourOffsY;
         _global.game.spawnerArray[1].ypos = this.inHandObj.ypos + this.inHandObj.pourOffsY;
         _global.game.spawnerArray[0].apiLineCol = this.inHandObj.fluidCol;
         if(this.inHandObj.clip._rotation > 116)
         {
            _global.game.spawnerArray[0].pushLocked = false;
            _global.game.spawnerArray[1].pushLocked = false;
            if(!this.pourStartNoiseFlag)
            {
               _global.game.pour.stop();
               _global.game.pour.setVolume(20);
               _global.game.pour.start();
               this.pourStartNoiseFlag = true;
            }
            _global.game.gameShaker.pushFluid(1,this.inHandObj.scoreVal);
         }
         else
         {
            this.inHandObj.clip._rotation += (120 - this.inHandObj.clip._rotation) * 0.2;
            _global.game.spawnerArray[0].pushLocked = true;
            _global.game.spawnerArray[1].pushLocked = true;
         }
         this.clip._rotation = this.inHandObj.clip._rotation;
      }
      else
      {
         if(this.easeToTarget(this,this.originX - 50,this.originY - 130,0.5,4) && !this.beginPour)
         {
            this.beginPour = true;
         }
         if(this.beginPour)
         {
            if(this.inHandObj.linkageClip == "icecube_burst")
            {
               burstIndex = 9;
            }
            else if(this.inHandObj.linkageClip == "lemon_burst")
            {
               burstIndex = 4;
            }
            _global.game.spawnerArray[burstIndex].xpos = this.xpos;
            _global.game.spawnerArray[burstIndex].ypos = this.ypos;
            _global.game.spawnerArray[burstIndex].kickUpdate();
            this.inHandObj.attachedToHand = false;
            this.inHandObj.xpos = this.inHandObj.shopLocX;
            this.inHandObj.ypos = this.inHandObj.shopLocY;
            this.inHandObj.updateClip();
            if(_global.game.gameShaker.fluidVol + 50 < _global.game.gameShaker.maxVol)
            {
               _global.game.gameShaker.pushFluid(50,this.inHandObj.scoreVal);
            }
            else
            {
               _global.game.gameShaker.pushFluid(_global.game.gameShaker.maxVol - _global.game.gameShaker.fluidVol,this.inHandObj.scoreVal);
               _global.game.gameShaker.isFull = true;
            }
            this.inHandObj = null;
            this.itemInHand = false;
            _global.game.switchState("returnTweenHand");
         }
      }
   }
}
