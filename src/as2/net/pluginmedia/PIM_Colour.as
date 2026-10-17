// PIM_Colour
//
// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the
// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.
// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.
// net.pluginmedia.PIM_Colour: a Color object with helpers to tint a clip (Plugin Media's utility class).

class net.pluginmedia.PIM_Colour extends Color
{
   var getTransform;
   var setTransform;
   /**
    * Wrap par target clip.
    */
   function PIM_Colour(target)
   {
      super(target);
   }
   /**
    * Blend the clip towards a colour by a percentage (resetMode: start from the untinted state).
    */
   function setTint(col, percent, resetMode)
   {
      if(isNaN(col) || isNaN(percent))
      {
         return undefined;
      }
      col = col > 0 ? (col < 16777215 ? Math.round(col) : 16777215) : 0;
      percent = percent > 0 ? (percent < 100 ? percent / 100 : 1) : 0;
      if(resetMode == undefined || resetMode != true && resetMode != false)
      {
         resetMode = true;
      }
      var trans = this.getTransform();
      if(resetMode)
      {
         with(trans)
         {
            ra = ga = ba = 100;
            rb = gb = bb = 0;
         }
      }
      with(trans)
      {
         ra -= ra * percent;
         ga -= ga * percent;
         ba -= ba * percent;
         rb += (((col & 0xFF0000) >> 16) - rb) * percent;
         gb += (((col & 0xFF00) >> 8) - gb) * percent;
         bb += ((col & 0xFF) - bb) * percent;
      }
      this.setTransform(trans);
   }
   /**
    * Lighten (positive) or darken (negative) the clip by a percentage.
    */
   function setBrightness(value, resetMode)
   {
      if(isNaN(value))
      {
         return undefined;
      }
      value = value > -100 ? (value < 100 ? value : 100) : -100;
      if(resetMode == undefined || resetMode != true && resetMode != false)
      {
         resetMode = true;
      }
      var trans = this.getTransform();
      if(resetMode)
      {
         with(trans)
         {
            ra = ga = ba = 100;
            rb = gb = bb = 0;
         }
      }
      var percent = Math.abs(value) / 100;
      var brightnessColor = value <= 0 ? 0 : 255;
      with(trans)
      {
         ra -= ra * percent;
         ga -= ga * percent;
         ba -= ba * percent;
         rb += (brightnessColor - rb) * percent;
         gb += (brightnessColor - gb) * percent;
         bb += (brightnessColor - bb) * percent;
      }
      this.setTransform(trans);
   }
}
