// CocktailGame
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// The whole game: state machine, shelf layout, controls and the per-frame main loop. States (gameState):
// preGame, getBottle, pour, rest, returnTweenHand, shakeRest, shake, serve, serveRest, serveLemon,
// finaleInit, finale, endGame, waitInput.

class CocktailGame
{
   var active;
   var activeBottleDepth;
   var barbackClip;
   var barmanHand;
   var bottleObjArray;
   var button_pour;
   var button_serve;
   var button_shake;
   var containerClip;
   var depths_0;
   var depths_1;
   var depths_2;
   var dynText;
   var endGameMask;
   var finalDrinkCol;
   var finaleAnim;
   var finaleClip;
   var gameObject;
   var gameShaker;
   var gameState;
   var garnishFlag;
   var grabIce;
   var grabLemon;
   var handOnActiveBottleDepth;
   var iceGlass;
   var infoText;
   var landLogo;
   var lemonDrop;
   var miguel;
   var mouseIsDown;
   var mouseListener;
   var musicLoop;
   var musicVol;
   var parentObj;
   var playAgainButton;
   var pour;
   var preGameMask;
   var preShakeReplacement;
   var reactionSpawnerArray;
   var rootLevel;
   var shakeNoise;
   var sounds;
   var spawnerArray;
   var vCam;
   var winMsg;
   /**
    * Build the scene: bar, hand, Miguel, shaker, 21 bottles, ice, lemon, particle effects, sounds, buttons and the intro / end screens.
    */
   function CocktailGame(par_rootLevel)
   {
      this.rootLevel = par_rootLevel;
      this.rootLevel.gameObject = this;
      this.rootLevel.onEnterFrame = function()
      {
         this.gameObject.mainLoop();
      };
      trace("rootLevel: " + this.rootLevel);
      this.depths_0 = new Array();
      this.createUseableDepths(this.depths_0,0,100);
      this.depths_1 = new Array();
      this.createUseableDepths(this.depths_1,101,200);
      this.depths_2 = new Array();
      this.createUseableDepths(this.depths_2,201,300);
      this.activeBottleDepth = 6000;
      this.handOnActiveBottleDepth = 5998;
      this.containerClip = this.rootLevel.createEmptyMovieClip("containerClip",0);
      this.vCam = new Cam(this.containerClip,600,440);
      this.barbackClip = this.containerClip.attachMovie("barback","barback_mc",this.popUseableDepth(this.depths_0));
      this.barbackClip._x = 0;
      this.barbackClip._y = 0;
      this.barmanHand = new BarmanHand(this.containerClip,518,240,5999);
      this.miguel = this.containerClip.attachMovie("miguel","miguel_01",6520);
      this.miguel.gotoAndStop(1);
      this.miguel._x = 523;
      this.miguel._y = 193;
      this.gameShaker = new Shaker(470,243);
      this.placeBottles_set();
      this.grabIce = new Additive(this.containerClip,"icecube",58,256,6600,null);
      this.grabIce.linkageClip = "icecube_burst";
      this.grabIce.infoText = "Add a little ice";
      this.grabIce.scoreVal = 1000;
      this.grabLemon = new Additive(this.containerClip,"lemon",140,268,6601,null);
      this.grabLemon.linkageClip = "lemon_burst";
      this.grabLemon.infoText = "Add a lemon!?";
      this.grabLemon.scoreVal = -100;
      this.grabLemon.clipMask.onPress = function()
      {
         if(_global.game.gameState == "shakeRest")
         {
            _global.game.garnishFlag = true;
            _global.game.gameShaker.pointsWon += 200;
            _global.game.miguel.gotoAndStop(64);
            _global.game.switchState("serveRest");
            trace("special lemon! - going to serveRest");
         }
         else if(_global.game.gameState == "rest" && !_global.game.gameShaker.isFull || _global.game.gameState == "getBottle")
         {
            _global.game.barmanHand.fetchTarget(this.parentObj);
            _global.game.switchState("getBottle");
         }
      };
      this.grabLemon.clipMask.onRollOver = function()
      {
         if(_global.game.gameState == "shakeRest")
         {
            _global.game.dynText.info.text = "Add a lemon garnish?";
         }
         else if(_global.game.gameState != "serve")
         {
            _global.game.dynText.info.text = "Add a lemon!?";
         }
      };
      this.grabLemon.clipMask.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.spawnerArray = new Array();
      this.spawnerArray[0] = new DoubleParticleSpawner(this.containerClip,6500,0,10,30,3,0,"particle_01",50,50,0.04,0.3,0.3,1.5,0,true,false,false,false,false,false,true,false);
      this.spawnerArray[0].hasAPILine = true;
      this.spawnerArray[0].apiLineCol = 4167147;
      this.spawnerArray[0].lineWidth = 7;
      this.spawnerArray[1] = new DoubleParticleSpawner(this.containerClip,6501,0,100,128,3,0,"particle_02",25,25,0.04,1,1,1.5,0,true,true,false,false,false,false,true,false);
      this.spawnerArray[1].tintParticles = null;
      this.spawnerArray[2] = new DoubleParticleSpawner(this.containerClip,6502,0,this.grabLemon.xpos,this.grabLemon.ypos - 14,0,-20,"lemon_burst",3,20,0,5,-5,2.4,0,true,true,false,true,false,false,true,false);
      this.spawnerArray[2].rotationMaxStep = 20;
      this.spawnerArray[2].minScale = 70;
      this.grabLemon.linkedSpawner = this.spawnerArray[2];
      this.spawnerArray[3] = new DoubleParticleSpawner(this.containerClip,6503,0,this.grabIce.xpos,this.grabIce.ypos - 14,0,-20,"icecube_burst",4,20,0,5,-5,2.5,0,true,true,false,true,false,false,true,false);
      this.spawnerArray[3].rotationMaxStep = 20;
      this.spawnerArray[3].minScale = 70;
      this.grabIce.linkedSpawner = this.spawnerArray[3];
      this.spawnerArray[4] = new DoubleParticleSpawner(this.containerClip,6504,0,180,320,0,0,"lemon_burst",1,37,0,0,0,1.9,0,true,true,false,true,false,false,true,false);
      this.spawnerArray[4].rotationMaxStep = 20;
      this.spawnerArray[4].minScale = 70;
      this.spawnerArray[9] = new DoubleParticleSpawner(this.containerClip,6514,0,180,320,0,0,"icecube_burst",3,37,0,0.9,1,1.9,0,true,true,false,true,false,false,true,false);
      this.spawnerArray[9].rotationMaxStep = 20;
      this.spawnerArray[9].minScale = 70;
      this.spawnerArray[5] = new DoubleParticleSpawner(this.containerClip,6530,0,10,30,-3,0,"particle_01",50,50,0.04,0.3,0.3,1.9,0,true,false,false,false,false,false,true,false);
      this.spawnerArray[5].hasAPILine = true;
      this.spawnerArray[5].apiLineCol = 16777215;
      this.spawnerArray[5].lineWidth = 7;
      this.spawnerArray[6] = new DoubleParticleSpawner(this.containerClip,6531,0,100,128,-3,0,"particle_02",25,25,0.04,1,1,1.9,0,true,true,false,false,false,false,true,false);
      this.spawnerArray[6].tintParticles = null;
      this.spawnerArray[7] = new DoubleParticleSpawner(this.containerClip,6507,0,430,300,0,-16,"lemon_slcParticle",4,20,0,7,7,1.9,0,true,true,false,false,false,false,true,false);
      this.spawnerArray[7].rotationMaxStep = 20;
      this.spawnerArray[7].minScale = 70;
      this.spawnerArray[8] = new DoubleParticleSpawner(this.containerClip,6508,0,430,300,0,-16,"particle_02",15,15,0,7,7,1.9,0,true,true,false,false,false,false,true,false);
      this.spawnerArray[8].tintParticles = 16383852;
      this.reactionSpawnerArray = new Array();
      this.reactionSpawnerArray[0] = new reactionSplashParticleSpawner(this.containerClip,6509,0,this.gameShaker.xpos,this.gameShaker.ypos,0,-2,10,14,0.04,5,5,0.6,0,true,true,true,false,false,true,true,false,this.spawnerArray[0]);
      this.reactionSpawnerArray[1] = new reactionSplashParticleSpawner(this.containerClip,6510,0,this.gameShaker.xpos,this.gameShaker.ypos,0,-2,0,0,0.04,5,5,0.6,0,true,true,true,false,false,true,true,false,this.spawnerArray[1]);
      this.reactionSpawnerArray[2] = new reactionSplashParticleSpawner(this.containerClip,6511,0,this.gameShaker.xpos,this.gameShaker.ypos,0,-8,10,20,0.04,5,5,0.9,0,true,true,true,true,false,true,true,false,this.spawnerArray[4]);
      this.reactionSpawnerArray[2].particleLinkage = "particle_02";
      this.reactionSpawnerArray[3] = new reactionSplashParticleSpawner(this.containerClip,6512,0,430,258,0,-8,10,20,0.04,5,5,0.9,0,true,true,true,true,false,true,true,false,this.spawnerArray[5]);
      this.reactionSpawnerArray[4] = new reactionSplashParticleSpawner(this.containerClip,6513,0,430,258,0,-8,10,20,0.04,5,5,0.9,0,true,true,true,true,false,true,true,false,this.spawnerArray[6]);
      this.reactionSpawnerArray[5] = new reactionSplashParticleSpawner(this.containerClip,6515,0,this.gameShaker.xpos,this.gameShaker.ypos,0,-8,10,20,0.04,5,5,0.9,0,true,false,true,true,false,true,true,false,this.spawnerArray[9]);
      this.reactionSpawnerArray[5].particleLinkage = "particle_02";
      this.musicVol = 10;
      this.sounds = this.containerClip.createEmptyMovieClip("soundContainer",13000);
      this.musicLoop = new Sound(this.sounds.createEmptyMovieClip("musicLoop",1));
      this.musicLoop.attachSound("musicLoop");
      this.musicLoop.setVolume(this.musicVol);
      this.musicLoop.start(0,99999);
      this.iceGlass = new Sound(this.reactionSpawnerArray[5].clip.createEmptyMovieClip("iceGlass",9999));
      this.iceGlass.attachSound("iceGlass");
      this.iceGlass.setVolume(20);
      this.lemonDrop = new Sound(this.reactionSpawnerArray[2].clip.createEmptyMovieClip("lemonDrop",9999));
      this.lemonDrop.attachSound("lemondrop");
      this.lemonDrop.setVolume(30);
      this.pour = new Sound(this.barmanHand.clip.createEmptyMovieClip("pour",100));
      this.pour.attachSound("pour");
      this.shakeNoise = new Sound(this.sounds.createEmptyMovieClip("shakeNoise",713));
      this.shakeNoise.attachSound("shakeNoise");
      this.shakeNoise.setVolume(0);
      this.shakeNoise.start(0,99999);
      this.reactionSpawnerArray[2].linkedActionSound = this.lemonDrop;
      this.reactionSpawnerArray[5].linkedActionSound = this.iceGlass;
      this.button_pour = this.containerClip.attachMovie("buttonpour","buttonpour",9909);
      this.button_pour._x = 75;
      this.button_pour._y = 415;
      this.button_pour.active = false;
      this.button_pour.onPress = function()
      {
         this.active = true;
      };
      this.button_pour.onRelease = function()
      {
         this.active = false;
      };
      this.button_pour.onRollOver = function()
      {
         _global.game.dynText.info.text = "Click and hold to add";
         _global.game.button_shake.active = false;
      };
      this.button_pour.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.button_shake = this.containerClip.attachMovie("buttonshake","buttonshake",9910);
      this.button_shake._x = 210;
      this.button_shake._y = 415;
      this.button_shake.active = false;
      this.button_shake.onPress = function()
      {
         this.active = true;
      };
      this.button_shake.onRelease = function()
      {
         this.active = false;
      };
      this.button_shake.onRollOver = function()
      {
         _global.game.dynText.info.text = "Click and hold to shake";
      };
      this.button_shake.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.button_serve = this.containerClip.attachMovie("buttonserve","buttonserve",9911);
      this.button_serve._x = 340;
      this.button_serve._y = 415;
      this.button_serve.active = false;
      this.button_serve.onRelease = function()
      {
         if(_global.game.gameState == "shakeRest")
         {
            this.miguel.gotoAndStop(64);
            _global.game.gameState = "serveRest";
         }
      };
      this.button_serve.onRollOver = function()
      {
         _global.game.dynText.info.text = "Click once to serve";
         _global.game.button_pour.active = false;
         _global.game.button_shake.active = false;
      };
      this.button_serve.onRollOut = function()
      {
         _global.game.dynText.info.text = _global.game.infoText;
      };
      this.dynText = this.containerClip.attachMovie("dynText","dynText_mc",9912);
      this.dynText._x = 410;
      this.dynText._y = 355;
      this.infoText = "What will you add?";
      this.dynText.info.text = this.infoText;
      this.gameState = "preGame";
      this.mouseListener = new Object();
      this.mouseIsDown = false;
      this.mouseListener.onMouseDown = function()
      {
         _global.game.mouseIsDown = true;
      };
      this.mouseListener.onMouseUp = function()
      {
         _global.game.mouseIsDown = false;
      };
      Mouse.addListener(this.mouseListener);
      this.preGameMask = this.rootLevel.attachMovie("preGameScreen","preGameMask",9999);
      this.preGameMask._x = 300;
      this.preGameMask._y = 220;
      this.preGameMask.startButton.onPress = function()
      {
         _global.game.containerClip._visible = true;
         _global.game.switchState("rest");
      };
      this.endGameMask = this.rootLevel.attachMovie("endGameScreen","endGameMask",10001);
      this.endGameMask._x = 0;
      this.endGameMask._y = 0;
      this.endGameMask.gotoAndStop(1);
      this.endGameMask._visible = false;
      this.playAgainButton._visible = false;
      this.preShakeReplacement = false;
      this.garnishFlag = false;
      this.finalDrinkCol = 16777113;
      this.finaleAnim = 1;
      this.containerClip._visible = false;
      this.landLogo = this.rootLevel.attachMovie("landLogo","landLogo",11313);
      this.landLogo._x = 10;
      this.landLogo._y = 10;
   }
   /**
    * "Back to the bar?": reset the shaker, hand, sounds and screens for a new drink.
    */
   function restartGame()
   {
      this.containerClip._visible = true;
      this.endGameMask.gotoAndPlay(20);
      this.playAgainButton._visible = false;
      this.gameShaker.pointsWon = 0;
      this.gameShaker.fluidVol = 0;
      this.gameShaker.lastPushFluid = 0;
      this.gameShaker.variety = 0;
      this.gameShaker.shakeCycles = 0;
      this.gameShaker.isFull = false;
      this.preShakeReplacement = false;
      if(this.garnishFlag)
      {
         this.garnishFlag = false;
         this.barmanHand.inHandObj.attachedToHand = false;
         this.barmanHand.inHandObj.xpos = _global.game.barmanHand.inHandObj.shopLocX;
         this.barmanHand.inHandObj.ypos = _global.game.barmanHand.inHandObj.shopLocY;
      }
      this.barmanHand.inHandObj = null;
      this.barmanHand.itemInHand = false;
      this.barmanHand.retrievedGoal = true;
      this.barmanHand.atRest = true;
      this.barmanHand.beginPour = false;
      this.barmanHand.grabBottleStepCounter = 0;
      this.barmanHand.currentTargetX = 0;
      this.barmanHand.currentTargetY = 0;
      this.barmanHand.clip._visible = false;
      this.barmanHand.armSegmentClip._visible = false;
      this.finalDrinkCol = 16777113;
      this.finaleAnim = 1;
      this.button_pour.active = false;
      this.button_shake.active = false;
      this.button_serve.active = false;
      this.mouseIsDown = false;
      this.miguel.gotoAndStop(1);
      this.switchState("rest");
      this.dynText.shakerVolClip._visible = false;
      this.dynText.shakerVolClip.gotoAndStop(1);
      this.miguel._visible = true;
      this.shakeNoise.stop();
      this.shakeNoise.setVolume(0);
      this.shakeNoise.start(0,99999);
      this.containerClip._visible = true;
      this.infoText = "What will you add?";
      this.dynText.info.text = this.infoText;
   }
   /**
    * Unused (empty in the original).
    */
   function swapInfoText()
   {
   }
   /**
    * Fill a depth pool with the integers par_minDepth..par_maxDepth (popped from the end).
    */
   function createUseableDepths(par_depthArr, par_minDepth, par_maxDepth)
   {
      var depth = par_minDepth;
      while(depth <= par_maxDepth)
      {
         par_depthArr.unshift(depth);
         depth++;
      }
   }
   /**
    * Take the next free depth.
    */
   function popUseableDepth(par_depthArr)
   {
      var depth = 0 + par_depthArr.pop();
      return depth;
   }
   /**
    * Return a depth to the pool.
    */
   function pushUseableDepth(par_depthArr, par_pushVal)
   {
      par_depthArr.push(par_pushVal);
   }
   /**
    * Random integer between min and max.
    */
   function randomRange(min, max)
   {
      var value = Math.round(Math.random() * (max - min)) + min;
      return value;
   }
   /**
    * Unused (empty in the original).
    */
   function assembleShop()
   {
   }
   /**
    * Place the 21 bottles at hand-tuned positions and set their colours, labels and score values.
    */
   function placeBottles_set()
   {
      this.bottleObjArray = new Array();
      var shelfOffsetX = 20;
      var shelfOffsetY = 66;
      this.bottleObjArray[0] = new Bottle(this.containerClip,"bttle_kahlua",6 + shelfOffsetX,44 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[0].fluidCol = 13670024;
      this.bottleObjArray[0].highlightCol = 16309724;
      this.bottleObjArray[0].infoText = "Kahlua";
      this.bottleObjArray[0].scoreVal = 5;
      this.bottleObjArray[1] = new Bottle(this.containerClip,"bttle_triple_sec",45 + shelfOffsetX,44 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[1].fluidCol = 14737321;
      this.bottleObjArray[1].highlightCol = 16380639;
      this.bottleObjArray[1].infoText = "Triple Sec";
      this.bottleObjArray[1].scoreVal = 45;
      this.bottleObjArray[2] = new Bottle(this.containerClip,"bttle_creme_de_cacao",91 + shelfOffsetX,43 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[2].fluidCol = 11628334;
      this.bottleObjArray[2].highlightCol = 14660486;
      this.bottleObjArray[2].infoText = "Creme de Cacao";
      this.bottleObjArray[2].scoreVal = 29;
      this.bottleObjArray[3] = new Bottle(this.containerClip,"bttle_creme_de_menthe",140 + shelfOffsetX,43 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[3].fluidCol = 892173;
      this.bottleObjArray[3].highlightCol = 6876290;
      this.bottleObjArray[3].infoText = "Creme de Menthe";
      this.bottleObjArray[3].scoreVal = 13;
      this.bottleObjArray[4] = new Bottle(this.containerClip,"bttle_absinthe",187 + shelfOffsetX,41 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[4].fluidCol = 2079294;
      this.bottleObjArray[4].highlightCol = 6546556;
      this.bottleObjArray[4].infoText = "Absinthe";
      this.bottleObjArray[4].scoreVal = 13;
      this.bottleObjArray[5] = new Bottle(this.containerClip,"bttle_vermouth",227 + shelfOffsetX,40 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[5].fluidCol = 13100775;
      this.bottleObjArray[5].highlightCol = 16777215;
      this.bottleObjArray[5].infoText = "Vermouth";
      this.bottleObjArray[5].scoreVal = 4;
      this.bottleObjArray[6] = new Bottle(this.containerClip,"bttle_calvados",273 + shelfOffsetX,41 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[6].fluidCol = 15392415;
      this.bottleObjArray[6].highlightCol = 16777215;
      this.bottleObjArray[6].infoText = "Calvados";
      this.bottleObjArray[6].scoreVal = 11;
      this.bottleObjArray[7] = new Bottle(this.containerClip,"bttle_gin",322 + shelfOffsetX,41 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[7].fluidCol = 13100775;
      this.bottleObjArray[7].highlightCol = 16777215;
      this.bottleObjArray[7].infoText = "Gin";
      this.bottleObjArray[7].scoreVal = 3;
      this.bottleObjArray[8] = new Bottle(this.containerClip,"bttle_tequila",364 + shelfOffsetX,40 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[8].fluidCol = 15265138;
      this.bottleObjArray[8].highlightCol = 16513757;
      this.bottleObjArray[8].infoText = "Tequila";
      this.bottleObjArray[8].scoreVal = 39;
      this.bottleObjArray[9] = new Bottle(this.containerClip,"bttle_champagne",408 + shelfOffsetX,40 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[9].fluidCol = 16514735;
      this.bottleObjArray[9].highlightCol = 16777215;
      this.bottleObjArray[9].infoText = "Champagne";
      this.bottleObjArray[9].scoreVal = 26;
      this.bottleObjArray[10] = new Bottle(this.containerClip,"bttle_champagne",453 + shelfOffsetX,40 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[10].fluidCol = 16514735;
      this.bottleObjArray[10].highlightCol = 16777215;
      this.bottleObjArray[10].infoText = "Champagne";
      this.bottleObjArray[10].scoreVal = 26;
      this.bottleObjArray[11] = new Bottle(this.containerClip,"bttle_whisky",4.5 + shelfOffsetX,150 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[11].fluidCol = 14529649;
      this.bottleObjArray[11].highlightCol = 15388838;
      this.bottleObjArray[11].infoText = "Whisky";
      this.bottleObjArray[11].scoreVal = 17;
      this.bottleObjArray[12] = new Bottle(this.containerClip,"bttle_cognac",51 + shelfOffsetX,151 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[12].fluidCol = 13475152;
      this.bottleObjArray[12].highlightCol = 14465667;
      this.bottleObjArray[12].infoText = "Cognac";
      this.bottleObjArray[12].scoreVal = 33;
      this.bottleObjArray[13] = new Bottle(this.containerClip,"bttle_amaretto",102 + shelfOffsetX,152 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[13].fluidCol = 16763904;
      this.bottleObjArray[13].highlightCol = 16773832;
      this.bottleObjArray[13].infoText = "Cointreau";
      this.bottleObjArray[13].scoreVal = 20;
      this.bottleObjArray[14] = new Bottle(this.containerClip,"bttle_vodka",158 + shelfOffsetX,148 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[14].fluidCol = 13100775;
      this.bottleObjArray[14].highlightCol = 16777215;
      this.bottleObjArray[14].infoText = "Vodka";
      this.bottleObjArray[14].scoreVal = 50;
      this.bottleObjArray[15] = new Bottle(this.containerClip,"bttle_sambuca",202 + shelfOffsetX,147 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[15].fluidCol = 13360350;
      this.bottleObjArray[15].highlightCol = 16777215;
      this.bottleObjArray[15].infoText = "Sambuca";
      this.bottleObjArray[15].scoreVal = 35;
      this.bottleObjArray[16] = new Bottle(this.containerClip,"bttle_orange",244 + shelfOffsetX,150 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[16].fluidCol = 16363867;
      this.bottleObjArray[16].highlightCol = 16502165;
      this.bottleObjArray[16].infoText = "Orange Juice";
      this.bottleObjArray[16].scoreVal = 14;
      this.bottleObjArray[17] = new Bottle(this.containerClip,"bttle_cranberry",291 + shelfOffsetX,153 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[17].fluidCol = 15216472;
      this.bottleObjArray[17].highlightCol = 15827354;
      this.bottleObjArray[17].infoText = "Cranberry Juice";
      this.bottleObjArray[17].scoreVal = 45;
      this.bottleObjArray[18] = new Bottle(this.containerClip,"bttle_lime",337 + shelfOffsetX,154 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[18].fluidCol = 11528821;
      this.bottleObjArray[18].highlightCol = 16777215;
      this.bottleObjArray[18].infoText = "Lime Juice";
      this.bottleObjArray[18].scoreVal = 44;
      this.bottleObjArray[19] = new Bottle(this.containerClip,"bttle_passion_fruit",383 + shelfOffsetX,154 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[19].fluidCol = 16033369;
      this.bottleObjArray[19].highlightCol = 16437673;
      this.bottleObjArray[19].infoText = "Passion Fruit Juice";
      this.bottleObjArray[19].scoreVal = 17;
      this.bottleObjArray[20] = new Bottle(this.containerClip,"bttle_tonic",430 + shelfOffsetX,160 + shelfOffsetY,this.popUseableDepth(this.depths_0));
      this.bottleObjArray[20].fluidCol = 13166847;
      this.bottleObjArray[20].highlightCol = 16777215;
      this.bottleObjArray[20].infoText = "Tonic";
      this.bottleObjArray[20].scoreVal = 2;
   }
   /**
    * Generic grid layout for bottles (unused; kept from an earlier version).
    */
   function placeBottles(par_linkageArray, par_bottlesPerShelf, par_startX, par_startY, par_spacingX, par_spacingY)
   {
      this.bottleObjArray = new Array();
      var x = par_startX;
      var y = par_startY;
      var i = 0;
      var bottle;
      while(i < par_linkageArray.length)
      {
         bottle = new Bottle(this.containerClip,par_linkageArray[i],x,y,this.popUseableDepth(this.depths_0));
         bottle.shopLocY -= bottle.clip._height / 2;
         bottle.ypos = bottle.shopLocY;
         bottle.clip.gotoAndStop(1);
         bottle.updateClip();
         this.bottleObjArray.push(bottle);
         x += par_spacingX;
         if(i % par_bottlesPerShelf == 0 && i > 0)
         {
            y += par_spacingY;
            x = par_startX;
         }
         i++;
      }
   }
   /**
    * Change the game state.
    */
   function switchState(par_newState)
   {
      this.gameState = par_newState;
   }
   /**
    * Update every bottle.
    */
   function updateBottles()
   {
      var i = 0;
      while(i <= this.bottleObjArray.length - 1)
      {
         this.bottleObjArray[i].update();
         i++;
      }
   }
   /**
    * Update every particle spawner and splash.
    */
   function updateDynamics()
   {
      var i = 0;
      while(i <= this.spawnerArray.length - 1)
      {
         this.spawnerArray[i].updateChildParticles();
         i++;
      }
      var j = 0;
      while(j <= this.reactionSpawnerArray.length - 1)
      {
         this.reactionSpawnerArray[j].updateChildParticles();
         this.reactionSpawnerArray[j].checkForTrigger();
         j++;
      }
   }
   /**
    * Translate the held mouse button + Pour / Shake into state changes.
    */
   function checkInput()
   {
      if(this.mouseIsDown && this.button_shake.active)
      {
         if(this.gameState != "returnTweenHand" && this.gameState != "shake" && this.gameState != "shakeRest" && this.gameShaker.fluidVol > 0 && !this.garnishFlag && this.gameState != "serve")
         {
            if(this.barmanHand.itemInHand)
            {
               trace("barman has item - return item before go to shake mode");
               this.barmanHand.fetchTarget(this.barmanHand.inHandObj);
               this.preShakeReplacement = true;
               this.switchState("getBottle");
               return undefined;
            }
            else
            {
               trace("barman has no item - going to shake mode");
               this.miguel.gotoAndStop(25);
               this.switchState("shakeRest");
            }
         }
         else if(this.gameState != "returnTweenHand" && this.gameShaker.fluidVol > 0 && !this.garnishFlag && this.gameState != "shake" && this.gameState != "serve")
         {
            this.switchState("shake");
         }
      }
      else if(this.gameState == "shake" && this.miguel._currentframe > 41)
      {
         this.switchState("shakeRest");
      }
      if(this.mouseIsDown && this.button_pour.active && this.barmanHand.itemInHand && !this.garnishFlag)
      {
         if(!this.gameShaker.isFull)
         {
            this.switchState("pour");
            return undefined;
         }
         else
         {
            this.dynText.info.text = "";
            this.switchState("rest");
         }
      }
      else
      {
         if(this.gameState != "getBottle" && this.barmanHand.itemInHand && !this.garnishFlag)
         {
            this.switchState("rest");
            return undefined;
         }
         else
         {
            return undefined;
         }
      }
   }
   /**
    * Once per frame (18 fps): run the current state, then update gauge, hand, effects and bottles.
    */
   function mainLoop()
   {
      var drinkColour;
      switch(this.gameState)
      {
         case "preGame":
            this.containerClip._visible = false;
            break;
         case "getBottle":
            if(!this.barmanHand.retrievedGoal)
            {
               this.barmanHand.moveHandToGoal();
            }
            else
            {
               this.checkInput();
            }
            break;
         case "pour":
            this.dynText.shakerVolClip._visible = true;
            this.barmanHand.pour();
            this.checkInput();
            break;
         case "rest":
            if(this.preGameMask._visible)
            {
               if(this.preGameMask._currentframe < 12)
               {
                  this.preGameMask.gotoAndStop(this.preGameMask._currentframe + 1);
               }
            }
            if(this.barmanHand.itemInHand)
            {
               this.infoText = "Hold pour to add...";
            }
            else
            {
               this.infoText = "What will you add?";
            }
            if(!this.gameShaker.isFull)
            {
               this.dynText.shakerVolClip._visible = false;
            }
            this.checkInput();
            this.barmanHand.returnToRest();
            break;
         case "returnTweenHand":
            this.infoText = "What will you add?";
            if(!this.gameShaker.isFull)
            {
               this.dynText.shakerVolClip._visible = false;
            }
            this.checkInput();
            this.barmanHand.returnTweenHand();
            break;
         case "shakeRest":
            this.infoText = "Shake, and serve when ready";
            if(this.shakeNoise.getVolume() > 0)
            {
               this.shakeNoise.setVolume(this.shakeNoise.getVolume() - 5);
            }
            else
            {
               this.shakeNoise.setVolume(0);
            }
            trace("decreasing shaker noise " + this.shakeNoise.getVolume());
            this.dynText.shakerVolClip._visible = false;
            this.checkInput();
            if(this.miguel._currentframe < 40)
            {
               this.miguel.gotoAndStop(this.miguel._currentframe + 1);
            }
            else
            {
               this.miguel.gotoAndStop(64);
            }
            break;
         case "shake":
            this.dynText.shakerVolClip._visible = false;
            trace("increasing shaker noise " + this.shakeNoise.getVolume());
            if(this.miguel._currentframe > 41)
            {
               if(this.shakeNoise.getVolume() < 40)
               {
                  this.shakeNoise.setVolume(this.shakeNoise.getVolume() + 1);
               }
            }
            this.checkInput();
            if(this.miguel._currentframe < 63)
            {
               this.miguel.gotoAndStop(this.miguel._currentframe + 1);
            }
            else
            {
               this.gameShaker.shakeCycles++;
               this.gameShaker.pointsWon += 10 * this.gameShaker.shakeCycles;
               if(this.gameShaker.shakeCycles >= 5)
               {
                  this.finaleClip.swapDepths(11000);
                  trace("boom!");
                  this.finaleAnim = 1;
                  this.switchState("finaleInit");
               }
               this.miguel.gotoAndStop(41);
            }
            break;
         case "serve":
            this.infoText = "How good is your cocktail?";
            if(this.shakeNoise.getVolume() > 0)
            {
               this.shakeNoise.setVolume(this.shakeNoise.getVolume() - 5);
            }
            else
            {
               this.shakeNoise.setVolume(0);
            }
            if(this.miguel._currentframe < 104)
            {
               this.miguel.gotoAndStop(104);
            }
            if(this.miguel._currentframe == 119)
            {
               drinkColour = new net.pluginmedia.PIM_Colour(this.miguel.glass.drink_mc);
               drinkColour.setTint(this.finalDrinkCol,50,true);
               this.spawnerArray[5].apiLineCol = this.finalDrinkCol;
            }
            if(this.miguel._currentframe == 304)
            {
               this.miguel.fullGlass._visible = true;
            }
            if(this.miguel._currentframe < this.miguel._totalframes)
            {
               this.miguel.gotoAndStop(this.miguel._currentframe + 1);
               if(this.miguel._currentframe > 129 && this.miguel._currentframe < 164)
               {
                  this.spawnerArray[5].xpos = this.miguel.serveParticles._x + 535;
                  this.spawnerArray[5].ypos = this.miguel.serveParticles._y + 204;
                  this.spawnerArray[5].pushLocked = false;
                  this.spawnerArray[6].xpos = this.miguel.serveParticles._x + 535;
                  this.spawnerArray[6].ypos = this.miguel.serveParticles._y + 204;
                  this.spawnerArray[6].pushLocked = false;
               }
               else
               {
                  this.spawnerArray[5].pushLocked = true;
                  this.spawnerArray[6].pushLocked = true;
               }
               if(this.miguel._currentframe > 132 && this.miguel._currentframe < 164)
               {
                  trace("filling glass: " + this.miguel.glass.drink_mc._currentframe);
                  this.miguel.glass.drink_mc.gotoAndStop(this.miguel.glass.drink_mc._currentframe + 1);
               }
            }
            else
            {
               if(this.gameShaker.variety <= 2)
               {
                  this.gameShaker.pointsWon /= 2;
                  trace("no variety :P");
               }
               else if(this.gameShaker.variety > 8)
               {
                  this.gameShaker.pointsWon /= 2;
                  trace("too much gunk");
               }
               if(this.gameShaker.pointsWon <= 1000)
               {
                  this.finaleAnim = 2;
                  this.winMsg = "A nice finishing touch might be a lemon garnish applied after shaking, as opposed to a 16 ton weight applied after drinking.";
               }
               else if(this.gameShaker.pointsWon <= 2000 && this.gameShaker.pointsWon > 1000)
               {
                  this.finaleAnim = 3;
                  this.winMsg = "Lame, to the point of being lethal. Triple Sec might just have saved my life...";
               }
               else if(this.gameShaker.pointsWon <= 3000 && this.gameShaker.pointsWon > 2000)
               {
                  this.finaleAnim = 4;
                  this.winMsg = "My mouth is angry with my head, and that\'s your fault. A little more ice perhaps?";
               }
               else if(this.gameShaker.pointsWon <= 4000 && this.gameShaker.pointsWon > 3000)
               {
                  this.finaleAnim = 5;
                  this.winMsg = "A dash of lime next time might help settle my tum...";
               }
               else if(this.gameShaker.pointsWon <= 5000 && this.gameShaker.pointsWon > 4000)
               {
                  this.finaleAnim = 6;
                  this.winMsg = "I\'d like to tell you that was good, but it just wasn\'t. Cranberry juice is considered essential...";
               }
               else if(this.gameShaker.pointsWon <= 6000 && this.gameShaker.pointsWon > 5000)
               {
                  this.finaleAnim = 7;
                  this.winMsg = "It\'s like a very boring party in my mouth. Might I suggest plenty of vodka next time...";
               }
               else if(this.gameShaker.pointsWon <= 7000 && this.gameShaker.pointsWon > 6000)
               {
                  this.finaleAnim = 8;
                  this.winMsg = "Surprisingly adequate.";
               }
               else if(this.gameShaker.pointsWon <= 8000 && this.gameShaker.pointsWon > 7000)
               {
                  this.finaleAnim = 9;
                  this.winMsg = "YOU ROCK DUDE! And that\'s one wailin\' Cosmopolitan!";
               }
               else if(this.gameShaker.pointsWon > 8000)
               {
                  this.finaleAnim = 10;
                  this.winMsg = "Mon Dieu! Vive l\'amour! Je t\'adore!!!!";
               }
               trace("final variety: " + this.gameShaker.variety);
               this.switchState("finaleInit");
            }
            break;
         case "serveRest":
            if(this.miguel._currentframe < 71)
            {
               if(this.miguel._currentframe + 3 > 71)
               {
                  this.miguel.gotoAndStop(71);
               }
               else
               {
                  this.miguel.gotoAndStop(this.miguel._currentframe + 3);
               }
            }
            else if(this.garnishFlag)
            {
               trace("special lemon! - garnishFlag is: " + this.garnishFlag + "going to getBottle");
               this.barmanHand.fetchTarget(this.grabLemon);
               this.miguel.backArm._visible = false;
               this.switchState("getBottle");
            }
            else
            {
               this.switchState("serve");
            }
            break;
         case "serveLemon":
            this.infoText = "How good is your cocktail?";
            this.dynText.info.text = this.infoText;
            if(this.shakeNoise.getVolume() > 0)
            {
               this.shakeNoise.setVolume(this.shakeNoise.getVolume() - 5);
            }
            else
            {
               this.shakeNoise.setVolume(0);
            }
            if(this.miguel._currentframe < 72)
            {
               this.miguel.gotoAndStop(72);
            }
            if(this.miguel._currentframe < 104)
            {
               if(this.miguel._currentframe > 74 && this.miguel._currentframe < 101)
               {
                  this.spawnerArray[7].pushLocked = false;
                  this.spawnerArray[8].pushLocked = false;
               }
               else
               {
                  this.spawnerArray[7].pushLocked = true;
                  this.spawnerArray[8].pushLocked = true;
               }
               this.miguel.gotoAndStop(this.miguel._currentframe + 1);
            }
            else
            {
               this.switchState("serve");
            }
            break;
         case "finaleInit":
            this.barmanHand.clip._visible = false;
            this.barmanHand.armSegmentClip._visible = false;
            this.miguel._visible = false;
            if(this.finaleAnim != 1)
            {
               this.finaleClip = this.containerClip.attachMovie("finale" + this.finaleAnim,"finale",6521);
            }
            else
            {
               this.gameShaker.pointsWon = 0;
               this.finaleClip = this.containerClip.attachMovie("finale" + this.finaleAnim,"finale",11000);
               this.winMsg = "It\'s a cocktail, not a milkshake! Do be a little less heavy handed...";
            }
            this.gameShaker.pointsWon = Math.round(this.gameShaker.pointsWon);
            this.finaleClip._x = 523;
            this.finaleClip._y = 193;
            this.finaleClip.gotoAndPlay(1);
            this.switchState("finale");
            break;
         case "finale":
            trace(this.finaleClip._currentframe);
            if(this.finaleClip._currentframe >= this.finaleClip._totalframes)
            {
               this.finaleClip.stop();
               this.switchState("endGame");
            }
            break;
         case "endGame":
            this.endGameMask._visible = true;
            if(_global.game.musicLoop.getVolume() == 0)
            {
               _global.game.musicLoop.setVolume(_global.game.musicVol);
               _global.game.musicLoop.start(0,99999);
            }
            this.switchState("waitInput");
            break;
         case "waitInput":
            if(this.endGameMask._currentframe < 20)
            {
               this.endGameMask.gotoAndStop(this.endGameMask._currentframe + 1);
            }
            else
            {
               this.endGameMask.finaleMsg.text = this.winMsg;
               this.endGameMask.yourScore.text = "Your score: " + this.gameShaker.pointsWon;
               if(this.finaleClip)
               {
                  removeMovieClip(this.finaleClip);
               }
               if(this.containerClip._visible)
               {
                  this.containerClip._visible = false;
               }
            }
            break;
      }
      this.dynText.shakerVolClip.frame1.indicator._yscale = 100 / this.gameShaker.maxVol * this.gameShaker.fluidVol;
      if(this.gameShaker.isFull && this.dynText.shakerVolClip._currentframe != 2)
      {
         this.dynText.shakerVolClip._visible = true;
         this.dynText.shakerVolClip.gotoAndStop(2);
      }
      this.barmanHand.updateClip();
      this.updateDynamics();
      this.updateBottles();
      this.grabLemon.update();
      this.grabIce.update();
      this.vCam.update();
   }
}
