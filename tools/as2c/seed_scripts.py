"""Seed decomp/src/scripts/*.as from the FFDec export for every non-class script (wrappers stripped)."""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
FF = os.path.join(ROOT, 'decomp', 'ffdec_as')
ASM = os.path.join(ROOT, 'decomp', 'asm')
OUT = os.path.join(ROOT, 'decomp', 'src', 'scripts')
os.makedirs(OUT, exist_ok=True)


def strip_wrapper(text):
    t = text.strip()
    m = re.match(r'^(on\s*\([^)]*\)|onClipEvent\s*\([^)]*\))\s*\{(.*)\}\s*$', t, re.S)
    return m.group(2).strip() + '\n' if m else text


def find_one(patterns):
    for p in patterns:
        hits = sorted(glob.glob(os.path.join(FF, p)))
        if hits:
            return hits
    return []


mapping = {}
for f in sorted(os.listdir(ASM)):
    n = f[:-len('.as2asm')]
    if n.startswith('init_class_'):
        continue
    src = None
    m = re.match(r'button(\d+)_cond0$', n)
    if m:
        hits = glob.glob(os.path.join(FF, 'DefineButton2_%s' % m.group(1), 'BUTTONCONDACTION*'))
        src = hits[0] if hits else None
    elif n == 'main_frameaction':
        src = os.path.join(FF, 'frame_1', 'DoAction.as')
    elif n == 'init_sprite19':
        src = os.path.join(FF, 'DoInitAction.as')
    elif n.startswith('init_'):
        src = os.path.join(FF, n[len('init_'):] + '.as')
    else:
        m = re.match(r'sprite(\d+)(?:_(\w+?))?_(frameaction|clipevent(\d+))(?:_(\d+))?$', n)
        if m:
            sid, kind, idx = m.group(1), m.group(3), m.group(5)
            dirs = sorted(glob.glob(os.path.join(FF, 'DefineSprite_%s*' % sid)))
            dirs = [d for d in dirs if re.fullmatch(r'DefineSprite_%s(_\w+)?' % sid, os.path.basename(d))]
            if dirs:
                d = dirs[0]
                if kind == 'frameaction':
                    frames = sorted(glob.glob(os.path.join(d, 'frame_*', 'DoAction.as')),
                                    key=lambda p: int(re.search(r'frame_(\d+)', p).group(1)))
                    k = int(idx) - 1 if idx else 0
                    src = frames[k] if k < len(frames) else None
                else:
                    hits = glob.glob(os.path.join(d, 'frame_*', 'PlaceObject2_*', 'CLIPACTIONRECORD*'))
                    src = hits[0] if hits else None
    if src and os.path.exists(src):
        text = strip_wrapper(open(src, encoding='utf-8').read())
        open(os.path.join(OUT, n + '.as'), 'w', encoding='utf-8').write(text)
        mapping[n] = os.path.relpath(src, FF)
    else:
        print('no source for', n)
print('seeded', len(mapping), 'scripts')
