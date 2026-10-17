"""Turn the matching sources (decomp/src, FFDec-style names) into readable sources (src/as2) plus a names map.

Only compiler-generated `_locN_` locals are renamed. (Parameter names are stored in the bytecode, inside the
DefineFunction2 header, so they must stay as the original author wrote them.) Registers do not appear in the bytecode, so the result still compiles to the identical bytes; the
names.json file records which register each readable local lives in (the original allocator is not reproduced).
"""
import json
import os
import re
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
SRC = os.path.join(ROOT, 'decomp', 'src')
OUT = os.path.join(ROOT, 'src', 'as2')

# class -> function -> {old local: new name}
RENAMES = {
    'Cam': {'update': {'_loc3_': 'deltaX', '_loc2_': 'deltaY'}},
    'Particle': {'Particle': {'_loc2_': 'tintColor'}},
    'BarmanHand': {
        'BarmanHand': {'_loc2_': 'i', '_loc3_': 'angle'},
        'updateClip': {'_loc3_': 'dy', '_loc2_': 'dx', '_loc4_': 'distance'},
        'easeToTarget': {'_loc3_': 'dy', '_loc2_': 'dx', '_loc4_': 'distanceSquared'},
        'returnTweenHand': {'_loc3_': 'targetFrame'},
        'pour': {'_loc3_': 'burstIndex'},
    },
    'reactionSplashParticleSpawner': {
        'reactionSplashParticleSpawner': {'_loc3_': 'poolDepth'},
        'checkForTrigger': {'_loc2_': 'i'},
    },
    'DoubleParticleSpawner': {
        'DoubleParticleSpawner': {'_loc2_': 'poolDepth'},
        'pushParticle': {'_loc3_': 'scale', '_loc5_': 'xVelocity', '_loc4_': 'yVelocity', '_loc2_': 'particle'},
        'attachDouble': {'_loc3_': 'doubleDepth', '_loc2_': 'doubleClip'},
        'updateChildParticles': {'_loc2_': 'i', '_loc3_': 'step', '_loc4_': 'spawned', '_loc5_': 'particlesPerFrame'},
    },
    'CocktailGame': {
        'createUseableDepths': {'_loc1_': 'depth'},
        'popUseableDepth': {'_loc1_': 'depth'},
        'randomRange': {'_loc1_': 'value'},
        'placeBottles_set': {'_loc3_': 'shelfOffsetX', '_loc2_': 'shelfOffsetY'},
        'placeBottles': {'_loc4_': 'x', '_loc5_': 'y', '_loc3_': 'i', '_loc2_': 'bottle'},
        'updateBottles': {'_loc2_': 'i'},
        'updateDynamics': {'_loc3_': 'i', '_loc2_': 'j'},
        'mainLoop': {'_loc3_': 'drinkColour'},
    },
}
# anonymous function expressions inside scripts are handled by name-less renames
SCRIPT_RENAMES = {'sprite387_miguel_frameaction_5': {'_loc2_': 'drinkColour'}}


def function_regions(lines):
    """Yield (name, start, end) line ranges of `function name(...) {...}` blocks (brace matched)."""
    i = 0
    while i < len(lines):
        m = re.match(r'\s*function\s+(\w+)\s*\(', lines[i])
        if m:
            depth, j, seen = 0, i, False
            while j < len(lines):
                depth += lines[j].count('{') - lines[j].count('}')
                if '{' in lines[j]:
                    seen = True
                if seen and depth == 0:
                    break
                j += 1
            yield m.group(1), i, j
            i = j + 1
        else:
            i += 1


def mx_classes():
    """Relative paths (without .as) of the stock Macromedia component classes under decomp/src/mx."""
    out = []
    for dp, _dn, fns in os.walk(os.path.join(SRC, 'mx')):
        for f in sorted(fns):
            if f.endswith('.as'):
                out.append(os.path.relpath(os.path.join(dp, f), SRC)[:-3].replace(os.sep, '/'))
    return sorted(out)


def convert(name, text):
    lines = text.split('\n')
    names = {}
    renames = RENAMES.get(name, {})
    for fn, a, b in function_regions(lines):
        region = '\n'.join(lines[a:b + 1])
        mapping = dict(renames.get(fn, {}))
        for old, new in mapping.items():
            region = re.sub(r'\b%s\b' % re.escape(old), new, region)
        lines[a:b + 1] = region.split('\n')
        if mapping:
            names[fn] = {new: int(re.search(r'\d+', old).group()) for old, new in mapping.items()}
    out = '\n'.join(lines)
    # sanity: no generated names left (the stock mx.* classes keep FFDec's _locN_ register-local names)
    left = sorted(set(re.findall(r'_loc\d+_', out)))
    if left and not name.startswith('mx.'):
        raise SystemExit('%s: unrenamed locals %s' % (name, left))
    return out, names


def main():
    all_names = {}
    shutil.rmtree(OUT, ignore_errors=True)
    for cls in ('Shaker', 'Particle', 'Cam', 'Bottle', 'Additive', 'DoubleParticleSpawner',
                'reactionSplashParticleSpawner', 'BarmanHand', 'CocktailGame', 'net/pluginmedia/PIM_Colour') + tuple(mx_classes()):
        text = open(os.path.join(SRC, cls + '.as'), encoding='utf-8').read()
        # game classes are keyed by their short name in RENAMES; mx classes by the dotted full name
        out, names = convert(cls.replace('/', '.') if cls.startswith('mx/') else cls.split('/')[-1], text)
        dst = os.path.join(OUT, cls + '.as')
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, 'w', encoding='utf-8', newline='\n').write(out)
        if names:
            all_names[cls.replace('/', '.')] = names
    os.makedirs(os.path.join(OUT, 'scripts'), exist_ok=True)
    for f in os.listdir(os.path.join(SRC, 'scripts')):
        text = open(os.path.join(SRC, 'scripts', f), encoding='utf-8').read()
        n = f[:-3]
        mp = SCRIPT_RENAMES.get(n)
        if mp:
            for old, new in mp.items():
                text = re.sub(r'\b%s\b' % re.escape(old), new, text)
            all_names[n] = {'script': {new: int(re.search(r'\d+', old).group()) for old, new in mp.items()}}
            # the anonymous handler function: map by the empty display name
            all_names[n] = {'': {new: int(re.search(r'\d+', old).group()) for old, new in mp.items()}}
        open(os.path.join(OUT, 'scripts', f), 'w', encoding='utf-8', newline='\n').write(text)
    json.dump(all_names, open(os.path.join(OUT, 'names.json'), 'w', encoding='utf-8'), indent=1)
    print('wrote', OUT, 'with names for', sorted(all_names))


if __name__ == '__main__':
    main()
