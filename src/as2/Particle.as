// Particle
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// One particle: a library symbol with a position, velocity and a lifetime, owned by a particle spawner.

class Particle
{
   var clip;
   var clipIDName;
   var depth;
   var lifeCounter;
   var mass;
   var maxLife;
   var rotStep;
   var startingScale;
   var updateStep;
   var xpos;
   var xvel;
   var ypos;
   var yvel;
   /**
    * Attach the particle symbol to par_targetClip, optionally tinting it (0 / null = no tint).
    */
   function Particle(par_targetClip, par_spawnX, par_spawnY, par_scale, par_xvel, par_yvel, par_rotStep, par_mass, par_particleLinkage, par_lifeSpan, par_depth, par_tintParticles)
   {
      this.xpos = par_spawnX;
      this.ypos = par_spawnY;
      this.rotStep = Math.random() * par_rotStep;
      this.startingScale = par_scale;
      this.xvel = par_xvel;
      this.yvel = par_yvel;
      this.mass = par_mass;
      this.depth = par_depth;
      this.lifeCounter = par_lifeSpan;
      this.maxLife = this.lifeCounter;
      this.updateStep = 0;
      this.clipIDName = par_particleLinkage;
      var tintColor;
      if(!par_tintParticles)
      {
         this.clip = par_targetClip.attachMovie(this.clipIDName,"clipIDName" + this.depth,this.depth);
      }
      else
      {
         this.clip = par_targetClip.attachMovie(this.clipIDName,"clipIDName" + this.depth,this.depth);
         tintColor = new Color(this.clip);
         tintColor.setRGB(par_tintParticles);
      }
      this.clip._xscale = this.clip._yscale = this.startingScale;
      this.updateClip();
   }
   /**
    * Copy the particle position to its clip.
    */
   function updateClip()
   {
      this.clip._x = this.xpos;
      this.clip._y = this.ypos;
   }
   /**
    * Remove the particle clip.
    */
   function selfDestruct()
   {
      removeMovieClip(this.clip);
      false;
   }
}
