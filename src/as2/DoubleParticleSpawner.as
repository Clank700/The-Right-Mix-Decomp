// DoubleParticleSpawner
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// Emits particles: the pour stream, ice and lemon bursts, serve splashes. (The "double" feature, a second clip per
// particle, is switched off by every spawner in this game.)

class DoubleParticleSpawner
{
   var apiLineCol;
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
   var hasAPILine;
   var hasRandomScale;
   var isDouble;
   var isExplosion;
   var iterationCounter;
   var lineClip;
   var lineWidth;
   var maxChildParticles;
   var maxChildXVel;
   var maxChildYVel;
   var maxIterations;
   var maxScale;
   var minScale;
   var normalForceX;
   var normalForceY;
   var numIterations;
   var particleLinkage;
   var pushLocked;
   var rotationMaxStep;
   var tintParticles;
   var updateChildAtStep;
   var updateLocked;
   var variableVel;
   var xpos;
   var xvel;
   var ypos;
   var yvel;
   /**
    * par_* configure position, forces, particle symbol, count, lifetime, damping, velocity spread, mass and flags.
    */
   function DoubleParticleSpawner(par_targetClip, par_depth, par_updateChildAtStep, par_spawnerX, par_spawnerY, par_normalForceX, par_normalForceY, par_particleLinkage, par_numParticles, par_childLifeSpan, par_childParticleDamping, par_maxChildXVel, par_maxChildYVel, par_childMass, par_maxIterations, par_variableVel, par_hasRandomScale, par_childFadeOnDie, par_isExplosion, par_isDouble, par_childShrinkOnDie, par_pushLocked, par_updateLocked)
   {
      this.updateLocked = par_updateLocked;
      this.pushLocked = par_pushLocked;
      this.xpos = par_spawnerX;
      this.ypos = par_spawnerY;
      this.xvel = 0;
      this.yvel = 0;
      this.rotationMaxStep = 0;
      this.maxScale = 100;
      this.minScale = 10;
      this.maxChildXVel = par_maxChildXVel;
      this.maxChildYVel = par_maxChildYVel;
      this.childMass = par_childMass;
      this.normalForceX = par_normalForceX;
      this.normalForceY = par_normalForceY;
      this.particleLinkage = par_particleLinkage;
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
      this.tintParticles = null;
      this.hasAPILine = false;
      this.lineClip = this.clip.createEmptyMovieClip("lineClip",0);
      this.apiLineCol = 0;
      this.lineWidth = 0;
      this.childLifeSpan = par_childLifeSpan;
      this.childDepthArrayAlpha = new Array();
      var poolDepth = 1;
      while(poolDepth <= 101)
      {
         this.childDepthArrayAlpha.unshift(poolDepth);
         poolDepth++;
      }
      this.childDepthArrayBeta = new Array();
      poolDepth = 102;
      while(poolDepth <= 251)
      {
         this.childDepthArrayBeta.unshift(poolDepth);
         poolDepth++;
      }
      this.doubleChildParticles = new Array();
      this.childParticles = new Array();
   }
   /**
    * Emit one burst right now, even if pushing is locked.
    */
   function kickUpdate()
   {
      this.pushLocked = false;
      this.updateChildParticles();
      this.pushLocked = true;
   }
   /**
    * Random number in [par_min, par_max).
    */
   function genRandom(par_min, par_max)
   {
      return Math.random() * (par_max - par_min) + par_min;
   }
   /**
    * Return a depth to the pool.
    */
   function pushChildDepth(par_depthArray, par_value)
   {
      par_depthArray.unshift(par_value);
   }
   /**
    * Take a free depth from the pool.
    */
   function popChildDepth(par_depthArray)
   {
      return 0 + par_depthArray.pop();
   }
   /**
    * Create one particle with randomised velocity / scale.
    */
   function pushParticle()
   {
      var scale;
      if(this.hasRandomScale)
      {
         scale = this.genRandom(this.minScale,this.maxScale);
      }
      else
      {
         scale = 100;
      }
      var xVelocity;
      var yVelocity;
      if(this.variableVel)
      {
         xVelocity = this.normalForceX + this.genRandom(- this.maxChildXVel,this.maxChildXVel);
         yVelocity = this.normalForceY + this.childMass + this.genRandom(- this.maxChildYVel,this.maxChildYVel);
      }
      else
      {
         xVelocity = this.normalForceX + this.maxChildXVel;
         yVelocity = this.normalForceY + this.childMass + this.maxChildYVel;
      }
      var particle = new Particle(this.clip,this.xpos,this.ypos,scale,xVelocity,yVelocity,this.rotationMaxStep,this.childMass,this.particleLinkage,this.childLifeSpan,this.popChildDepth(this.childDepthArrayAlpha),this.tintParticles);
      this.childParticles.push(particle);
      if(this.isDouble)
      {
         this.attachDouble(particle);
      }
      if(this.maxIterations > 0)
      {
         this.iterationCounter++;
         if(this.iterationCounter == this.maxChildParticles)
         {
            this.iterationCounter = 0;
            this.numIterations++;
         }
      }
   }
   /**
    * Attach the optional second "double" clip to a particle (unused in this game).
    */
   function attachDouble(par_targetParticle)
   {
      var doubleDepth = this.popChildDepth(this.childDepthArrayBeta);
      var doubleClip = this.clip.attachMovie(this.particleLinkage + "db",this.particleLinkage + "db" + doubleDepth,doubleDepth);
      doubleClip._x = par_targetParticle.xpos;
      doubleClip._y = par_targetParticle.ypos;
      doubleClip._xscale = doubleClip._yscale = par_targetParticle.scale;
      this.doubleChildParticles.push(doubleClip);
   }
   /**
    * Per-frame: move every particle, draw the stream line, retire dead ones, emit new ones.
    */
   function updateChildParticles()
   {
      var i;
      var step;
      var spawned;
      var particlesPerFrame;
      if(!this.updateLocked)
      {
         if(this.hasAPILine)
         {
            this.lineClip.clear();
            this.lineClip.lineStyle(this.lineWidth,this.apiLineCol,100);
         }
         this.xpos += this.xvel;
         this.ypos += this.yvel;
         i = 0;
         while(i <= this.childParticles.length - 1)
         {
            if(this.childParticles[i].updateStep == this.updateChildAtStep)
            {
               step = 0;
               while(step <= this.updateChildAtStep)
               {
                  this.childParticles[i].xvel *= this.childParticleDamping;
                  this.childParticles[i].yvel *= this.childParticleDamping;
                  this.childParticles[i].yvel += this.childParticles[i].mass;
                  this.childParticles[i].xpos += this.childParticles[i].xvel;
                  this.childParticles[i].ypos += this.childParticles[i].yvel;
                  if(this.childParticles[i].rotStep > 0)
                  {
                     this.childParticles[i].clip._rotation += this.childParticles[i].rotStep;
                  }
                  if(i > 0 && this.hasAPILine)
                  {
                     if(Math.abs(this.childParticles[i].ypos - this.childParticles[i - 1].ypos) < 35)
                     {
                        this.lineClip.moveTo(this.childParticles[i].xpos,this.childParticles[i].ypos);
                        this.lineClip.lineTo(this.childParticles[i - 1].xpos,this.childParticles[i - 1].ypos);
                     }
                  }
                  step++;
               }
               this.childParticles[i].updateClip();
               if(this.childFadeOnDie)
               {
                  this.childParticles[i].clip._alpha = Math.round(this.childParticles[i].lifeCounter / this.childLifeSpan * 100);
               }
               if(this.childShrinkOnDie)
               {
                  this.childParticles[i].clip._xscale = this.childParticles[i].clip._yscale = Math.round(this.childParticles[i].lifeCounter / this.childLifeSpan * this.childParticles[i].startingScale);
               }
               if(this.doubleChildParticles.length > 0)
               {
                  this.doubleChildParticles[i]._x = this.childParticles[i].xpos;
                  this.doubleChildParticles[i]._y = this.childParticles[i].ypos;
                  this.doubleChildParticles[i]._alpha = this.childParticles[i].clip._alpha;
                  this.doubleChildParticles[i]._xscale = this.doubleChildParticles[i]._yscale = this.childParticles[i].clip._xscale;
                  if(this.childParticles[i].rotStep > 0)
                  {
                     this.doubleChildParticles[i]._rotation += this.childParticles[i].rotStep;
                  }
               }
               this.childParticles[i].updateStep = 0;
            }
            else
            {
               this.childParticles[i].updateStep++;
            }
            this.childParticles[i].lifeCounter--;
            if(this.childParticles[i].lifeCounter <= 0)
            {
               this.pushChildDepth(this.childDepthArrayAlpha,this.childParticles[i].depth);
               this.childParticles[i].selfDestruct();
               this.childParticles.splice(i,1);
               if(this.doubleChildParticles.length > 0)
               {
                  this.pushChildDepth(this.childDepthArrayBeta,this.doubleChildParticles[i].getDepth());
                  removeMovieClip(this.doubleChildParticles[i]);
                  this.doubleChildParticles.splice(i,1);
               }
               i--;
            }
            i++;
         }
         if(!this.pushLocked)
         {
            if(this.numIterations < this.maxIterations || this.maxIterations == 0)
            {
               if(this.childParticles.length < this.maxChildParticles)
               {
                  if(this.isExplosion)
                  {
                     spawned = this.childParticles.length;
                     while(spawned < this.maxChildParticles)
                     {
                        this.pushParticle();
                        spawned++;
                     }
                  }
                  else
                  {
                     if(this.maxChildParticles > this.childLifeSpan)
                     {
                        particlesPerFrame = Math.floor(this.maxChildParticles / this.childLifeSpan);
                     }
                     else
                     {
                        particlesPerFrame = 1;
                     }
                     spawned = 0;
                     while(spawned < particlesPerFrame)
                     {
                        this.pushParticle();
                        spawned++;
                     }
                  }
               }
            }
            else
            {
            }
         }
      }
   }
   /**
    * Remove the spawner clips.
    */
   function dismantleSpawner()
   {
      removeMovieClip(this.clip);
      removeMovieClip(this.lineClip);
      false;
   }
}
