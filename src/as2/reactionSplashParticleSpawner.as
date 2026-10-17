// reactionSplashParticleSpawner
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// A splash that fires when particles of another spawner fall below a line (extends DoubleParticleSpawner).
// Note: the original ran the base constructor with no arguments, so the base fields keep their defaults.

class reactionSplashParticleSpawner extends DoubleParticleSpawner
{
   var childDepthArrayAlpha;
   var childDepthArrayBeta;
   var childFadeOnDie;
   var childLifeSpan;
   var childMass;
   var childParticleDamping;
   var childParticles;
   var childShrinkOnDie;
   var clip;
   var depth;
   var doubleChildParticles;
   var hasRandomScale;
   var isDouble;
   var isExplosion;
   var iterationCounter;
   var linkedActionSound;
   var maxChildParticles;
   var maxChildXVel;
   var maxChildYVel;
   var maxIterations;
   var normalForceX;
   var normalForceY;
   var numIterations;
   var particleLinkage;
   var pushLocked;
   var triggerSpawner;
   var updateChildAtStep;
   var updateLocked;
   var variableVel;
   var xpos;
   var ypos;
   /**
    * par_triggeredBy: the spawner whose falling particles trigger this splash.
    */
   function reactionSplashParticleSpawner(par_targetClip, par_depth, par_updateChildAtStep, par_spawnerX, par_spawnerY, par_normalForceX, par_normalForceY, par_numParticles, par_childLifeSpan, par_childParticleDamping, par_maxChildXVel, par_maxChildYVel, par_childMass, par_maxIterations, par_variableVel, par_hasRandomScale, par_childFadeOnDie, par_isExplosion, par_isDouble, par_childShrinkOnDie, par_pushLocked, par_updateLocked, par_triggeredBy)
   {
      super();
      this.triggerSpawner = par_triggeredBy;
      this.updateLocked = par_updateLocked;
      this.pushLocked = par_pushLocked;
      this.xpos = par_spawnerX;
      this.ypos = par_spawnerY;
      this.linkedActionSound = null;
      this.maxChildXVel = par_maxChildXVel;
      this.maxChildYVel = par_maxChildYVel;
      this.childMass = par_childMass;
      this.normalForceX = par_normalForceX;
      this.normalForceY = par_normalForceY;
      this.particleLinkage = this.triggerSpawner.particleLinkage + "rsp";
      this.childParticleDamping = 1 - par_childParticleDamping;
      this.maxChildParticles = par_numParticles;
      this.updateChildAtStep = par_updateChildAtStep;
      this.maxIterations = par_maxIterations;
      this.numIterations = 0;
      this.iterationCounter = 0;
      this.hasRandomScale = par_hasRandomScale;
      this.isDouble = par_isDouble;
      this.isExplosion = par_isExplosion;
      this.childFadeOnDie = par_childFadeOnDie;
      this.childShrinkOnDie = par_childShrinkOnDie;
      this.variableVel = par_variableVel;
      this.depth = par_depth;
      this.clip = par_targetClip.createEmptyMovieClip("pspawner" + this.depth,this.depth);
      this.childLifeSpan = par_childLifeSpan;
      this.childDepthArrayAlpha = new Array();
      var poolDepth = 0;
      while(poolDepth <= 100)
      {
         this.childDepthArrayAlpha.unshift(poolDepth);
         poolDepth++;
      }
      this.childDepthArrayBeta = new Array();
      poolDepth = 101;
      while(poolDepth <= 250)
      {
         this.childDepthArrayBeta.unshift(poolDepth);
         poolDepth++;
      }
      this.doubleChildParticles = new Array();
      this.childParticles = new Array();
   }
   /**
    * Arm the splash; it emits on the next update.
    */
   function kickUpdate()
   {
      this.pushLocked = false;
   }
   /**
    * Per-frame: re-lock, then trigger (and play the linked sound) for particles below the line.
    */
   function checkForTrigger()
   {
      if(this.pushLocked == false)
      {
         this.pushLocked = true;
      }
      var i = 0;
      while(i <= this.triggerSpawner.childParticles.length - 1)
      {
         if(this.triggerSpawner.childParticles[i].ypos >= this.ypos)
         {
            this.triggerSpawner.childParticles[i].lifeCounter = 0;
            this.kickUpdate();
            if(this.linkedActionSound != null)
            {
               trace("playing sound: " + this.linkedActionSound + " volume is: " + this.linkedActionSound.getVolume());
               this.linkedActionSound.stop();
               this.linkedActionSound.start();
            }
         }
         i++;
      }
   }
}
