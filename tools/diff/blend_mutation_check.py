#!/usr/bin/env python
"""blend_mutation_check.py - do the interpolation tests notice when a discontinuity guard is removed?

Each mutation removes one guard from the port; port/test/blend_integrity_test.dart must then fail. Sources are restored.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
LIB = os.path.join(ROOT, 'port', 'lib')
# Guards that overlap (so removing one alone changes nothing): removed together.
COMBINED = [
    ('frame-by-frame art blended (no same-drawing rule, no whole-clip hold)', [
        ('engine/nodes/movie_clip.dart', 'existing.charId == cmd.charId &&' + chr(10) + '          !existing.matrix.isJumpTo(inst.matrix)) {',
         'existing.runtimeType == inst.runtimeType &&' + chr(10) + '          !existing.matrix.isJumpTo(inst.matrix)) {'),
        ('engine/nodes/movie_clip.dart', '    if (_structural) animationRoot.holdChildren();' + chr(10), ''),
        ('engine/stage.dart', '    root.applyBlendHolds();' + chr(10), ''),
    ]),
    ('timeline jumps blended (no jump rule, no whole-clip hold, no cut rule)', [
        ('engine/nodes/movie_clip.dart', 'final smooth = !initial && target == frame + 1;', 'final smooth = !initial;'),
        ('engine/nodes/movie_clip.dart', '    if (_structural) animationRoot.holdChildren();' + chr(10), ''),
        ('engine/stage.dart', '    root.applyBlendHolds();' + chr(10), ''),
        ('engine/geometry.dart', 'if (dx * dx + dy * dy > maxMove * maxMove) return true;', 'if (false) return true;'),
    ]),
]

MUTATIONS = [
    ('bottle put-back/pick-up not marked as a jump', 'game/props/shelf.dart',
     '    clip.breakBlend(); // picked up / put back: the bottle jumps between the shelf and the hand\n', ''),
    ('free-standing item jump detection removed', 'game/props/shelf.dart',
     'if (dx * dx + dy * dy > 60 * 60) clip.breakBlend();', 'if (false) clip.breakBlend();'),
    ('timeline cuts (big moves) blended', 'engine/geometry.dart',
     'if (dx * dx + dy * dy > maxMove * maxMove) return true;', 'if (false) return true;'),
    ('long stalls replayed instead of dropped', 'engine/fixed_step.dart',
     '    if (dt > maxFrameTime) {\n      // The app was suspended (or the frame stalled for a long time): don\'t replay the gap.\n      suspended = true;\n      _acc = 0;\n      return 0;\n    }',
     '    if (dt > maxFrameTime) dt = maxFrameTime;'),
    ('pause does not clear the blend', 'engine/frame_driver.dart', '    stepper.reset();\n    stage.clearBlend();', '    stepper.reset();'),
]


def run_edits(edits, env):
    saved = {}
    try:
        for rel, old, new in edits:
            path = os.path.join(LIB, rel)
            text = open(path, encoding='utf-8').read()
            saved.setdefault(path, text)
            if old not in text:
                return None
            open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new, 1))
        r = subprocess.run(['flutter', 'test', 'test/blend_integrity_test.dart'], cwd=os.path.join(ROOT, 'port'),
                           env=env, shell=True, capture_output=True, text=True)
        return r.returncode != 0 and 'Some tests failed' in r.stdout
    finally:
        for path, text in saved.items():
            open(path, 'w', encoding='utf-8', newline='').write(text)


def main():
    env = dict(os.environ, PATH=os.path.join(ROOT, 'tools', 'flutter', 'bin') + os.pathsep + os.environ['PATH'])
    missed = 0
    for title, rel, old, new in MUTATIONS:
        path = os.path.join(LIB, rel)
        text = open(path, encoding='utf-8').read()
        if old not in text:
            print('%-52s PATTERN NOT FOUND' % title)
            missed += 1
            continue
        try:
            open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new, 1))
            r = subprocess.run(['flutter', 'test', 'test/blend_integrity_test.dart'], cwd=os.path.join(ROOT, 'port'),
                               env=env, shell=True, capture_output=True, text=True)
        finally:
            open(path, 'w', encoding='utf-8', newline='').write(text)
        failed = r.returncode != 0 and 'Some tests failed' in r.stdout
        print('%-52s %s' % (title, 'caught' if failed else 'MISSED'))
        missed += 0 if failed else 1
    for title, edits in COMBINED:
        res = run_edits(edits, env)
        print('%-52s %s' % (title, 'PATTERN NOT FOUND' if res is None else ('caught' if res else 'MISSED')))
        missed += 0 if res else 1
    return 1 if missed else 0


if __name__ == '__main__':
    sys.exit(main())
