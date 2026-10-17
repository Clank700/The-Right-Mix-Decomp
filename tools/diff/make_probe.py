#!/usr/bin/env python
"""make_probe.py - build an instrumented copy of the original game for differential testing.

The probe is AS2 source compiled by tools/as2c and spliced into the main-timeline script. It
  * replaces Math.random with a deterministic Park-Miller generator (seeded per scenario),
  * replays a scripted input sequence by calling the game's own mouse handlers (the same entry points the pointer
    uses), and
  * traces one line of game state per frame (after the game's own onEnterFrame has run).
The rest of the SWF is the unchanged original (all other scripts compile to the identical bytes).

  python tools/diff/make_probe.py <scenarios.json> <out_dir> [--fps 60]
"""
import json
import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'as2c'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'swfproj'))

import build  # noqa: E402
import compiler  # noqa: E402
import swfproj  # noqa: E402

# Input vocabulary shared by the Flash probe and the Dart harness (see port/test/differential_test.dart).
OPS = {
    'start': '_loc2_.preGameMask.startButton.onPress();',
    'ice': '_loc2_.grabIce.clipMask.onPress();',
    'lemon': '_loc2_.grabLemon.clipMask.onPress();',
    'pourDown': '_loc2_.button_pour.onPress(); _loc2_.mouseListener.onMouseDown();',
    'pourUp': '_loc2_.button_pour.onRelease(); _loc2_.mouseListener.onMouseUp();',
    'shakeDown': '_loc2_.button_shake.onPress(); _loc2_.mouseListener.onMouseDown();',
    'shakeUp': '_loc2_.button_shake.onRelease(); _loc2_.mouseListener.onMouseUp();',
    'serve': '_loc2_.button_serve.onRelease();',
    'restart': '_loc2_.restartGame();',
}


def op_code(op):
    if isinstance(op, list):
        name, arg = op
        if name == 'pick':
            return '_loc2_.bottleObjArray[%d].clip.onPress();' % arg
        raise ValueError(op)
    return OPS[op]


STATE_TRACE = (
    '"F" + _loc3_ + " " + _loc2_.gameState'
    ' + " v=" + Math.round(_loc2_.gameShaker.fluidVol * 100)'
    ' + " p=" + Math.round(_loc2_.gameShaker.pointsWon * 100)'
    ' + " var=" + _loc2_.gameShaker.variety'
    ' + " cyc=" + _loc2_.gameShaker.shakeCycles'
    ' + " full=" + _loc2_.gameShaker.isFull'
    ' + " hx=" + Math.round(_loc2_.barmanHand.xpos * 100)'
    ' + " hy=" + Math.round(_loc2_.barmanHand.ypos * 100)'
    ' + " item=" + _loc2_.barmanHand.itemInHand'
    ' + " mf=" + _loc2_.miguel._currentframe'
    ' + " dc=" + _loc2_.finalDrinkCol'
    ' + " g=" + _loc2_.garnishFlag'
    ' + " fa=" + _loc2_.finaleAnim'
    ' + " parts=" + _loc4_'
    ' + " info=[" + _loc2_.dynText.info.text + "]"'
    ' + " ys=[" + _loc2_.endGameMask.yourScore.text + "]"'
    ' + " fm=" + _loc2_.endGameMask.finaleMsg.text.length'
    ' + " ff=" + _loc2_.finaleClip._currentframe'
    ' + " rs=" + _level0.probeSeed'
)


def probe_source(sc):
    cases = {}
    for frame, op in sc['ops']:
        cases.setdefault(frame, []).append(op_code(op))
    sw = []
    for frame in sorted(cases):
        sw.append('      case %d:\n         %s\n         break;' % (frame, '\n         '.join(cases[frame])))
    switch = ('      switch(_loc3_)\n      {\n' + '\n'.join(sw) + '\n      }\n') if sw else ''
    return '''_global.game = new CocktailGame(this);
stop();
_level0.probeSeed = %(seed)d;
ASSetPropFlags(Math,"random",0,7);
Math.random = function()
{
   _level0.probeSeed = _level0.probeSeed * 16807 %% 2147483647;
   return _level0.probeSeed / 2147483647;
};
this.createEmptyMovieClip("probe",20000);
this.probe.n = 0;
trace("PROBE_START " + _level0.probeSeed);
this.probe.onEnterFrame = function()
{
   this.n++;
   var _loc2_ = _global.game;
   var _loc3_ = this.n;
   var _loc4_ = 0;
   var _loc5_ = 0;
%(switch)s   while(_loc5_ <= 9)
   {
      _loc4_ += _loc2_.spawnerArray[_loc5_].childParticles.length;
      _loc5_++;
   }
   _loc5_ = 0;
   while(_loc5_ <= 5)
   {
      _loc4_ += _loc2_.reactionSpawnerArray[_loc5_].childParticles.length;
      _loc5_++;
   }
   trace(%(trace)s);
   if(_loc3_ >= %(last)d)
   {
      trace("PROBE_DONE");
   }
};
''' % {'seed': sc['seed'], 'switch': switch, 'trace': STATE_TRACE, 'last': sc['frames']}


def build_probe(sc, out_dir, fps):
    tmp = tempfile.mkdtemp(prefix='rightmix_probe_')
    try:
        proj = os.path.join(tmp, 'p')
        shutil.copytree(build.DECOMP, proj, ignore=shutil.ignore_patterns('ffdec_as', 'src', 'ORIGINAL.json'))
        build.compile_sources(proj, verbose=False)
        asm = compiler.compile_to_asm(probe_source(sc), [], {})
        with open(os.path.join(proj, 'asm', 'main_frameaction.as2asm'), 'w', encoding='utf-8') as f:
            f.write(asm)
        # raise the frame rate in the SWF header (8.8 fixed point, little endian, after the RECT)
        doc = json.load(open(os.path.join(proj, 'swf.json'), encoding='utf-8'))
        hdr = bytearray(bytes.fromhex(doc['header_hex']))
        hdr[-4:-2] = struct.pack('<H', int(fps * 256))
        doc['header_hex'] = hdr.hex()
        json.dump(doc, open(os.path.join(proj, 'swf.json'), 'w', encoding='utf-8'), ensure_ascii=False)
        swf = swfproj.build_swf(proj)
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, sc['name'] + '.swf')
        open(path, 'wb').write(swf.to_fws())
        return path
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    scen = json.load(open(sys.argv[1], encoding='utf-8'))
    out = sys.argv[2]
    fps = float(sys.argv[sys.argv.index('--fps') + 1]) if '--fps' in sys.argv else 60
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else None
    for sc in scen['scenarios']:
        if only is None or sc['name'] == only:
            print(build_probe(sc, out, fps))


if __name__ == '__main__':
    main()
