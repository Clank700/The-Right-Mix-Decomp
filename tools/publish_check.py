#!/usr/bin/env python
"""publish_check.py - check for blocked assets and obvious personal identifiers.

This is not copyright clearance: it does not assess whether decompiled code or game-derived text/data may be published.

  python tools/publish_check.py            check what git would commit (tracked files + untracked, not ignored)
  python tools/publish_check.py --list     also print every file
  python tools/publish_check.py --bundle out.zip   after a clean check, zip exactly the files selected by gitignore

It uses .gitignore, so it sees exactly what `git add -A` would add. Exit code 1 means DO NOT PUSH.
Works in a repository (uses `git ls-files`) or in a plain folder (uses a temporary git dir with the same .gitignore).
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# file types that can carry the game's artwork / sound / code: allowed only at these exact paths
RISKY_EXT = {'.swf', '.mp3', '.wav', '.ogg', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.zip', '.apk', '.aab',
             '.exe', '.dll', '.so', '.msi', '.jar', '.bin', '.fla', '.xfl'}
ALLOWED_RISKY = {
    'port/android/gradle/wrapper/gradle-wrapper.jar',      # Gradle wrapper (Apache-2.0); Flutter's .gitignore normally keeps it out
}
ALLOWED_RISKY_PREFIXES = ()
# upstream author attribution that is part of a third-party licence/header, not a privacy leak: path -> exact strings allowed
UPSTREAM_ATTRIBUTION = {
    'port/windows/audio/miniaudio.h': (b'mackron@gmail.com',),   # David Reid's contact line in miniaudio's header (public domain / MIT-0)
}
FORBIDDEN_PREFIXES = ('local_archive/', 'src/as2/mx/', 'decomp/', 'port/assets/', 'fixtures/ffdec/sprites/', 'work/', 'build/', 'dist/', '.rightmix/',
                      'tools/flutter/', 'tools/jdk/', 'tools/ffdec/', 'tools/android-cmdline/', 'tools/ruffle', 'port/build/')
MAX_BYTES = 6 * 1024 * 1024
PERSONAL = re.compile(rb'(?:[A-Z]:\\Users\\[^\\\r\n ]+|/Users/[^/\s]+|/home/[^/\s]+)', re.I)
EMAIL = re.compile(rb'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', re.I)
SWF_MAGIC = (b'FWS', b'CWS', b'ZWS')


def candidate_files():
    def git(*a, git_dir=None):
        base = ['git']
        if git_dir:
            base += ['--git-dir', git_dir, '--work-tree', ROOT]
        else:
            base += ['-C', ROOT]
        return subprocess.run(base + list(a), capture_output=True, text=True)

    if os.path.isdir(os.path.join(ROOT, '.git')):
        r = git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
    else:
        tmp = tempfile.mkdtemp(prefix='rightmix_gitdir_')
        subprocess.run(['git', 'init', '--bare', '-q', tmp], check=True)
        r = git('ls-files', '--others', '--exclude-standard', '-z', git_dir=tmp)
    if r.returncode != 0:
        raise SystemExit('git failed: ' + r.stderr)
    return sorted(set(p for p in r.stdout.split('\0') if p))


def main():
    files = candidate_files()
    problems, warnings = [], []
    total = 0
    by_top = {}
    for rel in files:
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        size = os.path.getsize(path)
        total += size
        top = rel.split('/')[0] if '/' in rel else '(root)'
        by_top[top] = by_top.get(top, 0) + size
        ext = os.path.splitext(rel)[1].lower()
        if rel.startswith(FORBIDDEN_PREFIXES):
            problems.append('%s: inside a folder that must never be published' % rel)
        if ext in RISKY_EXT and rel not in ALLOWED_RISKY and not rel.startswith(ALLOWED_RISKY_PREFIXES):
            problems.append('%s: %s files can carry the game\'s artwork/sound/code and are not on the allow-list' % (rel, ext))
        if size > MAX_BYTES and rel not in ALLOWED_RISKY:
            problems.append('%s: %.1f MB is unusually large' % (rel, size / 1e6))
        try:
            with open(path, 'rb') as f:
                head = f.read(1 << 16)
        except OSError:
            continue
        if head[:3] in SWF_MAGIC and len(head) > 8:
            problems.append('%s: starts with a Flash (SWF) signature' % rel)
        if rel != 'tools/publish_check.py' and ext not in RISKY_EXT:
            contents = head if size <= (1 << 16) else open(path, 'rb').read()
            for allowed in UPSTREAM_ATTRIBUTION.get(rel, ()):
                contents = contents.replace(allowed, b'')
            if PERSONAL.search(contents) or EMAIL.search(contents):
                warnings.append('%s: contains a personal path or e-mail address' % rel)
    print('files that would be published: %d, %.1f MB' % (len(files), total / 1e6))
    for k in sorted(by_top, key=lambda k: -by_top[k]):
        print('  %-14s %7.1f MB' % (k, by_top[k] / 1e6))
    if '--list' in sys.argv:
        print('\n'.join(files))
    for w in warnings:
        print('WARNING:', w)
    for p in problems:
        print('PROBLEM:', p)
    if problems:
        print('\nDO NOT PUSH: %d problem(s).' % len(problems))
        return 1
    print('\nOK: no blocked assets found in what would be published%s.' % (' (%d privacy warning(s) above need review)' % len(warnings) if warnings else ''))
    if '--bundle' in sys.argv:
        import zipfile
        out = sys.argv[sys.argv.index('--bundle') + 1]
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for rel in files:
                if os.path.isfile(os.path.join(ROOT, rel)):
                    z.write(os.path.join(ROOT, rel), rel)
        print('bundle written: %s (%.1f MB)' % (out, os.path.getsize(out) / 1e6))
    return 0


if __name__ == '__main__':
    sys.exit(main())
