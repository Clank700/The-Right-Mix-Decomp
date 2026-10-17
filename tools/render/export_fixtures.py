#!/usr/bin/env python
"""export_fixtures.py - reproducible reference renderings from FFDec for the render comparison.

  python tools/render/export_fixtures.py            export from build/bartender_rebuilt.cws.swf and (re)write the fixtures
  python tools/render/export_fixtures.py --check    re-export and verify every frame against fixtures/ffdec/manifest.json

Source of the pictures: the rebuilt SWF (byte-identical to the original after decompression - see
reference/original.json), so the fixtures can be regenerated from a rebuilt SWF (python tools/build.py after extracting your bartender.swf).
Renderer: JPEXS Free Flash Decompiler (tools/ffdec, version recorded in the manifest).

fixtures/ffdec/sprites/DefineSprite_<id>_<name>/<frame>.png   a representative subset (first, middle, last frame, and
                                                              about eight evenly spaced frames of long timelines)
fixtures/ffdec/manifest.json                                  sha256 of EVERY exported frame (not only the committed
                                                              subset), the FFDec version and the SWF hashes
"""
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
JAVA = os.path.join(ROOT, 'tools', 'jdk', 'jdk-21.0.12.1+1', 'bin', 'java.exe')
FFDEC = os.path.join(ROOT, 'tools', 'ffdec', 'ffdec-cli.jar')
SWF = os.path.join(ROOT, 'build', 'bartender_rebuilt.cws.swf')
FIX = os.path.join(ROOT, 'fixtures', 'ffdec')
WORK = os.path.join(ROOT, 'work', 'ffdec_sprites')


def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    return int.from_bytes(head[16:20], 'big'), int.from_bytes(head[20:24], 'big')


def ffdec_version():
    out = subprocess.run([JAVA, '-jar', FFDEC, '-help'], capture_output=True, text=True).stdout
    m = re.search(r'v\.([\d.]+)', out)
    return m.group(1) if m else 'unknown'


def export(dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    subprocess.check_call([JAVA, '-jar', FFDEC, '-format', 'sprite:png', '-export', 'sprite', dest, SWF],
                          stdout=subprocess.DEVNULL)


def frames_of(dest):
    out = {}
    for d in sorted(os.listdir(dest)):
        fs = sorted(int(f[:-4]) for f in os.listdir(os.path.join(dest, d)) if f.endswith('.png'))
        if fs:
            out[d] = fs
    return out


def committed_subset(frames):
    n = frames[-1]
    pick = {1, math.ceil(n / 2), n}
    if n > 30:
        pick |= {max(1, round(n * i / 8)) for i in range(1, 8)}
    return [f for f in sorted(pick) if f in frames]


def main():
    if not os.path.exists(SWF):
        subprocess.check_call([sys.executable, os.path.join(ROOT, 'tools', 'build.py')])
    orig = json.load(open(os.path.join(ROOT, 'reference', 'original.json'), encoding='utf-8'))
    export(WORK)
    allf = frames_of(WORK)
    manifest = {
        'ffdec_version': ffdec_version(),
        'format': 'sprite:png (FFDec defaults)',
        'swf_decompressed_payload_sha256': orig['decompressed_payload_sha256'],
        'rebuilt_swf_sha256': sha(SWF),
        'sprites': {},
    }
    for d, fs in allf.items():
        keep = set(committed_subset(fs))
        manifest['sprites'][d] = {str(f): {'sha256': sha(os.path.join(WORK, d, '%d.png' % f)),
                                           'size': list(png_size(os.path.join(WORK, d, '%d.png' % f))),
                                           'committed': f in keep}
                                  for f in fs}
    if '--check' in sys.argv:
        old = json.load(open(os.path.join(FIX, 'manifest.json'), encoding='utf-8'))
        bad = 0
        for d, frames in old['sprites'].items():
            for f, meta in frames.items():
                now = manifest['sprites'].get(d, {}).get(f)
                if not now or now['sha256'] != meta['sha256']:
                    bad += 1
                    print('DIFFERS', d, f)
        extra = sum(len(v) for v in manifest['sprites'].values()) - sum(len(v) for v in old['sprites'].values())
        print('frames checked: %d, differing: %d, new frames not in manifest: %d (ffdec %s vs recorded %s)' % (
            sum(len(v) for v in old['sprites'].values()), bad, extra, manifest['ffdec_version'], old['ffdec_version']))
        return 1 if bad or extra else 0
    if os.path.exists(os.path.join(FIX, 'sprites')):
        shutil.rmtree(os.path.join(FIX, 'sprites'))
    kept = 0
    for d, frames in manifest['sprites'].items():
        for f, meta in frames.items():
            if meta['committed']:
                os.makedirs(os.path.join(FIX, 'sprites', d), exist_ok=True)
                shutil.copy(os.path.join(WORK, d, '%s.png' % f), os.path.join(FIX, 'sprites', d, '%s.png' % f))
                kept += 1
    os.makedirs(FIX, exist_ok=True)
    with open(os.path.join(FIX, 'manifest.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print('exported %d frames, committed subset %d, FFDec %s' % (
        sum(len(v) for v in manifest['sprites'].values()), kept, manifest['ffdec_version']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
