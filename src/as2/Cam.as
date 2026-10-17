// Cam
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// Camera for the bar scene. Eases the world clip towards a target offset and can wobble. In this game the
// target is always (0, 0), so the camera never actually moves; the code is a leftover from a larger engine.

class Cam
{
   var camState;
   var centreStage_x;
   var centreStage_y;
   var isWobble;
   var trackLocX;
   var trackLocY;
   var trackObj;
   var wobbleConstraint;
   var worldClip;
   var xpos;
   var xvel;
   var ypos;
   var yvel;
   var zoom;
   /**
    * par_worldClip: the clip that gets moved around; stage size gives the screen centre.
    */
   function Cam(par_worldClip, par_stageWidth, par_stageHeight)
   {
      this.centreStage_x = par_stageWidth / 2;
      this.centreStage_y = par_stageHeight / 2;
      this.xpos = 0;
      this.ypos = 0;
      this.zoom = 0;
      this.xvel = 0;
      this.yvel = 0;
      this.isWobble = false;
      this.wobbleConstraint = 0;
      this.trackLocX = this.xpos;
      this.trackLocY = this.ypos;
      this.camState = "";
      this.worldClip = par_worldClip;
   }
   /**
    * Apply the camera position to the world clip.
    */
   function nudgeWorldView()
   {
      this.worldClip._x = this.xpos;
      this.worldClip._y = this.ypos;
   }
   /**
    * Apply the zoom level to the world clip (both axes).
    */
   function nudgeWorldZoom()
   {
      this.worldClip._xscale = this.worldClip._yscale = 100 + this.zoom;
   }
   /**
    * Start tracking an entity (anything with xpos / ypos).
    */
   function lockViewToEnt(par_lockToEnt)
   {
      this.isWobble = false;
      this.camState = "tracking";
      this.trackObj = par_lockToEnt;
      this.trackEnt();
   }
   /**
    * Ease the camera towards the tracked entity.
    */
   function trackEnt()
   {
      this.ypos = (this.ypos - this.trackObj.ypos + this.centreStage_y) * 0.5;
      this.xpos = (this.xpos - this.trackObj.xpos + this.centreStage_x) * 0.5;
   }
   /**
    * Start a decaying shake of the given magnitude, limited to par_wbConstraint pixels.
    */
   function wobble(par_magnitude, par_wbConstraint)
   {
      this.wobbleConstraint = par_wbConstraint;
      this.yvel = par_magnitude;
      this.xvel = par_magnitude;
      this.isWobble = true;
   }
   /**
    * Per-frame: ease towards the target, handle wobble damping, move the world clip.
    */
   function update()
   {
      switch(this.camState)
      {
         case "tracking":
            this.trackEnt();
            break;
         default:
            this.ypos -= (this.ypos - this.trackLocY) * 0.5;
            this.xpos -= (this.xpos - this.trackLocX) * 0.5;
            break;
      }
      var deltaX;
      var deltaY;
      if(this.isWobble)
      {
         deltaX = this.xpos - this.trackLocX;
         if(Math.abs(deltaX) > this.wobbleConstraint)
         {
            this.xvel *= -1;
         }
         deltaY = this.ypos - this.trackLocY;
         if(Math.abs(deltaY) > this.wobbleConstraint)
         {
            this.yvel *= -1;
         }
      }
      if(this.xvel != 0 || this.yvel != 0)
      {
         if(Math.abs(this.xvel) > 0.3)
         {
            this.xvel *= 0.9;
         }
         else
         {
            this.xvel = 0;
         }
         if(Math.abs(this.yvel) > 0.3)
         {
            this.yvel *= 0.9;
         }
         else
         {
            this.yvel = 0;
         }
      }
      else
      {
         this.isWobble = false;
      }
      this.xpos += this.xvel;
      this.ypos += this.yvel;
      this.nudgeWorldView();
   }
}
