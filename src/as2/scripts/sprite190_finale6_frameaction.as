var i = 0;
while(i <= _global.game.bottleObjArray.length - 1)
{
   _global.game.bottleObjArray[i].yvel = Math.round(Math.random() * 10) + 20;
   i++;
}
