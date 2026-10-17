this._visible = true;
lastTimer = getTimer();
this.onEnterFrame = function()
{
   if(this._visible)
   {
      myTimer = getTimer();
      cTime = myTimer - lastTimer;
      framerate_txt.text = Math.round(1 / cTime * 1000);
      lastTimer = myTimer;
   }
};
