#!/usr/bin/env python3
"""rightmix - build the native Windows and Android ports of "The Right Mix" from YOUR OWN copy of bartender.swf.

This repository does not contain the game. It contains the readable ActionScript source we decompiled, a compiler for it,
the Flutter ports (code only) and the tooling. This tool joins them with your copy of the game:

  python rightmix.py doctor                          what is installed / missing
  python rightmix.py setup [--accept-android-licenses]   download the missing toolchains (Flutter, JDK, Android SDK)
  python rightmix.py build --swf bartender.swf       check the file, rebuild it from our source, make assets + icons,
                                                     build the ports            [--windows] [--android] [--skip-matching]
  python rightmix.py verify --swf bartender.swf      only the "matching decomp" check (rebuilt SWF == your SWF)
  python rightmix.py gui                             the same in a small window

Steps of `build` (all local, nothing is uploaded; your SWF is never modified or copied into the repository):
  1  identify the file (sha256 against reference/original.json)
  2  take it apart into decomp/ (tools/swfproj; local, git-ignored)
  3  compile src/as2 with our compiler and rebuild the SWF, require it to be byte-identical (tools/build.py)
  4  extract bitmaps and sounds natively and convert them into port/assets (tools/assetc; local, git-ignored)
  5  render the app icon from the game's artwork (tools/make_icons.py)
  6  flutter build windows / apk, package into dist/
"""
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = os.path.join(ROOT, 'port')
TOOLS = os.path.join(ROOT, 'tools')
IS_WIN = os.name == 'nt'
PIN_FLUTTER = '3.47.7'
PIN_JDK = 21
MIN_JDK = 17

sys.path.insert(0, os.path.join(TOOLS, 'assetc'))
sys.path.insert(0, os.path.join(TOOLS, 'swfproj'))


CURRENT_SWF = [None]  # the user's bartender.swf for the child processes (tools/build.py compares with it directly)


def log(msg=''):
    print(msg, flush=True)


# ---- toolchain discovery ------------------------------------------------------------------------------------------------
def toolchain_dir():
    return os.environ.get('RIGHTMIX_TOOLCHAIN') or os.path.join(ROOT, '.rightmix', 'toolchain')


def _exists(*parts):
    p = os.path.join(*parts)
    return p if os.path.exists(p) else None


def find_flutter():
    """Path of the flutter launcher, or None."""
    exe = 'flutter.bat' if IS_WIN else 'flutter'
    cands = [os.environ.get('RIGHTMIX_FLUTTER'), os.path.join(toolchain_dir(), 'flutter'), os.path.join(TOOLS, 'flutter'),
             os.environ.get('FLUTTER_ROOT')]
    for c in cands:
        if c and _exists(c, 'bin', exe):
            return os.path.join(c, 'bin', exe)
    return shutil.which('flutter')


def find_jdk():
    """JAVA_HOME of a JDK >= MIN_JDK, or None."""
    java = 'java.exe' if IS_WIN else 'java'
    cands = []
    for base in (os.path.join(toolchain_dir(), 'jdk'), os.path.join(TOOLS, 'jdk')):
        if os.path.isdir(base):
            cands += [os.path.join(base, d) for d in sorted(os.listdir(base))] + [base]
    cands += [os.environ.get('JAVA_HOME')]
    for c in cands:
        if c and _exists(c, 'bin', java) and (jdk_major(c) or 0) >= MIN_JDK:
            return c
    w = shutil.which('java')
    if w:
        home = os.path.dirname(os.path.dirname(os.path.realpath(w)))
        if (jdk_major(home) or 0) >= MIN_JDK:
            return home
    return None


def jdk_major(home):
    try:
        out = subprocess.run([os.path.join(home, 'bin', 'java.exe' if IS_WIN else 'java'), '-version'], capture_output=True,
                             text=True).stderr
        m = re.search(r'version "(\d+)(?:\.(\d+))?', out)
        if m:
            return int(m.group(2)) if m.group(1) == '1' and m.group(2) else int(m.group(1))
    except OSError:
        pass
    return None


def find_android_sdk():
    cands = [os.path.join(toolchain_dir(), 'android-sdk'), os.environ.get('ANDROID_HOME'), os.environ.get('ANDROID_SDK_ROOT')]
    if IS_WIN:
        cands.append(os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk'))
    else:
        cands += [os.path.expanduser('~/Android/Sdk'), os.path.expanduser('~/Library/Android/sdk')]
    for c in cands:
        if c and os.path.isdir(c) and (os.path.isdir(os.path.join(c, 'platforms')) or os.path.isdir(os.path.join(c, 'cmdline-tools'))):
            return c
    return None


def android_licenses_accepted(sdk):
    return bool(sdk) and os.path.exists(os.path.join(sdk, 'licenses', 'android-sdk-license'))


def flutter_version(flutter):
    try:
        out = subprocess.run([flutter, '--version'], capture_output=True, text=True, timeout=300).stdout
        m = re.search(r'Flutter (\d+\.\d+\.\d+)', out)
        return m.group(1) if m else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def tool_env():
    """Environment for child processes: the discovered Flutter, JDK and Android SDK first."""
    env = dict(os.environ)
    paths = []
    fl = find_flutter()
    if fl:
        paths.append(os.path.dirname(fl))
    jdk = find_jdk()
    if jdk:
        env['JAVA_HOME'] = jdk
        paths.append(os.path.join(jdk, 'bin'))
    sdk = find_android_sdk()
    if sdk:
        env['ANDROID_HOME'] = env['ANDROID_SDK_ROOT'] = sdk
    env['PATH'] = os.pathsep.join(paths + [env.get('PATH', '')])
    env['PUB_ENVIRONMENT'] = 'rightmix'
    if CURRENT_SWF[0]:
        env['RIGHTMIX_SWF'] = CURRENT_SWF[0]
    env['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    return env


def run(cmd, cwd=None, env=None, check=True):
    log('$ ' + ' '.join('"%s"' % c if ' ' in c else c for c in cmd))
    r = subprocess.run(cmd, cwd=cwd, env=env or tool_env(), shell=False)
    if check and r.returncode != 0:
        raise SystemExit('command failed (exit %d): %s' % (r.returncode, ' '.join(cmd)))
    return r.returncode


# ---- doctor ------------------------------------------------------------------------------------------------------------
def cmd_doctor(args):
    ok = True

    def row(name, status, detail='', need=True):
        nonlocal ok
        mark = 'OK ' if status else ('-- ' if not need else 'MISSING')
        log('  %-26s %-8s %s' % (name, 'OK' if status else ('optional' if not need else 'MISSING'), detail))
        if not status and need:
            ok = False

    log('Platform: %s %s, Python %s' % (platform.system(), platform.release(), platform.python_version()))
    row('Python >= 3.9', sys.version_info >= (3, 9), platform.python_version())
    try:
        import PIL
        row('Pillow (pip install pillow)', True, PIL.__version__)
    except ImportError:
        row('Pillow (pip install pillow)', False, 'needed to decode / write images')
    import mp3tool_build
    row('C compiler (for mp3tool)', bool(mp3tool_build.compiler_description()), mp3tool_build.compiler_description() or
        ('install Visual Studio Build Tools, workload "Desktop development with C++"' if IS_WIN else 'install gcc or clang'))
    fl = find_flutter()
    ver = flutter_version(fl) if fl else None
    row('Flutter %s' % PIN_FLUTTER, bool(fl), '%s (version %s%s)' % (fl, ver, '' if ver == PIN_FLUTTER else ', tested with ' + PIN_FLUTTER) if fl else 'run: python rightmix.py setup')
    jdk = find_jdk()
    row('JDK >= %d (Android)' % MIN_JDK, bool(jdk), jdk or 'run: python rightmix.py setup', need=False)
    sdk = find_android_sdk()
    row('Android SDK (Android)', bool(sdk), sdk or 'run: python rightmix.py setup', need=False)
    row('Android licenses accepted', android_licenses_accepted(sdk), '' if android_licenses_accepted(sdk) else
        'run: python rightmix.py setup --accept-android-licenses', need=False)
    if IS_WIN:
        import mp3tool_build as m
        row('Visual Studio C++ (Windows)', bool(m.find_vcvars()), m.find_vcvars() or 'needed for the Windows build', need=False)
    else:
        log('  (the Windows port can only be built on Windows)')
    log('')
    log('Ready to build.' if ok else 'Something required is missing; see above.')
    return 0 if ok else 1


# ---- downloads ---------------------------------------------------------------------------------------------------------
def http_get(url, timeout=120):
    """GET with a User-Agent (some servers answer 403 to Python's default one)."""
    req = urllib.request.Request(url, headers={'User-Agent': 'rightmix-setup'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch(url, dest, sha256=None, sha1=None):
    log('downloading %s' % url)
    req = urllib.request.Request(url, headers={'User-Agent': 'rightmix-setup'})
    h256, h1 = hashlib.sha256(), hashlib.sha1()
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, 'wb') as f:
        total = int(r.headers.get('Content-Length') or 0)
        got, last = 0, 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            h256.update(chunk)
            h1.update(chunk)
            got += len(chunk)
            if total and got * 20 // total != last:
                last = got * 20 // total
                log('  %3d%%  (%d MB of %d MB)' % (last * 5, got >> 20, total >> 20))
    if sha256 and h256.hexdigest() != sha256:
        raise SystemExit('checksum mismatch for %s' % url)
    if sha1 and h1.hexdigest() != sha1:
        raise SystemExit('checksum mismatch for %s' % url)


def unzip(path, dest):
    with zipfile.ZipFile(path) as z:
        z.extractall(dest)


def host_key():
    s = platform.system()
    return {'Windows': 'windows', 'Darwin': 'macos', 'Linux': 'linux'}[s]


def setup_flutter():
    if find_flutter() and flutter_version(find_flutter()) == PIN_FLUTTER:
        log('Flutter %s already available.' % PIN_FLUTTER)
        return
    key = host_key()
    base = 'https://storage.googleapis.com/flutter_infra_release/releases'
    j = json.loads(http_get(base + '/releases_%s.json' % key))
    rel = [r for r in j['releases'] if r['version'] == PIN_FLUTTER and r['channel'] == 'stable']
    if not rel:
        raise SystemExit('Flutter %s not listed for %s' % (PIN_FLUTTER, key))
    r = rel[0]
    tc = toolchain_dir()
    os.makedirs(tc, exist_ok=True)
    tmp = os.path.join(tc, 'flutter_download' + os.path.splitext(r['archive'])[1].replace('.xz', '.tar.xz'))
    fetch(j['base_url'] + '/' + r['archive'], tmp, sha256=r['sha256'])
    shutil.rmtree(os.path.join(tc, 'flutter'), ignore_errors=True)
    if tmp.endswith('.zip'):
        unzip(tmp, tc)
    else:
        import tarfile
        with tarfile.open(tmp) as t:
            t.extractall(tc)
    os.remove(tmp)
    log('Flutter installed in %s' % os.path.join(tc, 'flutter'))


def setup_jdk():
    if find_jdk():
        log('A JDK >= %d is already available.' % MIN_JDK)
        return
    key = {'windows': 'windows', 'macos': 'mac', 'linux': 'linux'}[host_key()]
    arch = 'aarch64' if platform.machine().lower() in ('arm64', 'aarch64') else 'x64'
    j = json.loads(http_get('https://api.adoptium.net/v3/assets/latest/%d/hotspot?architecture=%s&image_type=jdk&os=%s'
                            % (PIN_JDK, arch, key)))
    pkg = j[0]['binary']['package']
    tc = os.path.join(toolchain_dir(), 'jdk')
    os.makedirs(tc, exist_ok=True)
    tmp = os.path.join(tc, pkg['name'])
    fetch(pkg['link'], tmp, sha256=pkg['checksum'])
    if tmp.endswith('.zip'):
        unzip(tmp, tc)
    else:
        import tarfile
        with tarfile.open(tmp) as t:
            t.extractall(tc)
    os.remove(tmp)
    log('JDK installed in %s' % tc)


def setup_android(accept):
    import xml.etree.ElementTree as ET
    tc = toolchain_dir()
    sdk = find_android_sdk() or os.path.join(tc, 'android-sdk')
    jdk = find_jdk()
    if not jdk:
        raise SystemExit('a JDK is needed first (run setup without --android-only, or install JDK %d)' % PIN_JDK)
    if not os.path.isdir(os.path.join(sdk, 'cmdline-tools', 'latest')):
        xml = http_get('https://dl.google.com/android/repository/repository2-3.xml')
        root = ET.fromstring(xml)
        best = None
        for pkg in root.iter('remotePackage'):
            if pkg.get('path') != 'cmdline-tools;latest':
                continue
            rev = int(pkg.find('revision/major').text)
            for arch in pkg.iter('archive'):
                hos = arch.findtext('host-os')
                if hos == {'windows': 'windows', 'macos': 'macosx', 'linux': 'linux'}[host_key()] and (best is None or rev > best[0]):
                    best = (rev, arch.findtext('complete/url'), arch.findtext('complete/checksum'))
        if not best:
            raise SystemExit('could not find the Android command-line tools download')
        os.makedirs(sdk, exist_ok=True)
        tmp = os.path.join(sdk, best[1])
        fetch('https://dl.google.com/android/repository/' + best[1], tmp, sha1=best[2])
        stage = os.path.join(sdk, '_cmdline_tmp')
        shutil.rmtree(stage, ignore_errors=True)
        unzip(tmp, stage)
        os.makedirs(os.path.join(sdk, 'cmdline-tools'), exist_ok=True)
        shutil.move(os.path.join(stage, 'cmdline-tools'), os.path.join(sdk, 'cmdline-tools', 'latest'))
        shutil.rmtree(stage, ignore_errors=True)
        os.remove(tmp)
        log('Android command-line tools installed in %s' % sdk)
    if accept:
        # call the tool's Java entry point directly (the .bat launchers mangle arguments containing ';')
        lib = os.path.join(sdk, 'cmdline-tools', 'latest', 'lib')
        cmd = [os.path.join(jdk, 'bin', 'java.exe' if IS_WIN else 'java'), '-classpath', os.path.join(lib, '*'),
               'com.android.sdklib.tool.sdkmanager.SdkManagerCli', '--sdk_root=' + sdk, '--licenses']
        p = subprocess.run(cmd, input='y\n' * 40, text=True, capture_output=True, env=tool_env())
        log(p.stdout[-400:])
        sub = [cmd[0], '-classpath', os.path.join(lib, '*'), 'com.android.sdklib.tool.sdkmanager.SdkManagerCli', '--sdk_root=' + sdk,
               'platform-tools']
        subprocess.run(sub, input='y\n' * 5, text=True, capture_output=True, env=tool_env())
        log('Android licenses accepted (you asked for this with --accept-android-licenses).')
    else:
        log('Android SDK tools are in place, but the Android licenses are NOT accepted. Read them at')
        log('  https://developer.android.com/studio/terms  and run again with --accept-android-licenses to accept them.')


def cmd_setup(args):
    which = {'flutter': args.flutter_only, 'android': args.android_only}
    only = [k for k, v in which.items() if v]
    if not only or 'flutter' in only:
        setup_flutter()
    if not only or 'android' in only:
        setup_jdk()
        setup_android(args.accept_android_licenses)
    if IS_WIN and not args.no_vs:
        import mp3tool_build
        if not mp3tool_build.find_vcvars():
            log('')
            log('The Windows build and the audio converter need the Visual Studio C++ tools. To install them (needs administrator rights):')
            log('  winget install Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"')
    log('')
    return cmd_doctor(args)


# ---- the build ---------------------------------------------------------------------------------------------------------
def verify_swf(path, force=False):
    """Make sure `path` is the game this project is made for. Returns the sha256 of the file."""
    ref = json.load(open(os.path.join(ROOT, 'reference', 'original.json'), encoding='utf-8'))
    if not os.path.isfile(path):
        raise SystemExit('file not found: %s' % path)
    data = open(path, 'rb').read()
    sha = hashlib.sha256(data).hexdigest()
    if sha == ref['original_file_sha256']:
        log('Your bartender.swf is the expected file (sha256 %s...).' % sha[:12])
        return sha
    try:
        import swfio
        payload = swfio.Swf.load(path).to_fws()
        if hashlib.sha256(payload).hexdigest() == ref['decompressed_payload_sha256']:
            log('Your file has the expected contents (compressed differently from the one we know).')
            return sha
    except Exception:
        pass
    msg = ('This is not the file the project was made for.\n  expected sha256 %s (%d bytes)\n  your file       %s (%d bytes)\n'
           'The source in src/as2 only matches that exact file.' % (ref['original_file_sha256'], ref['original_file_bytes'], sha, len(data)))
    if force:
        log('WARNING: ' + msg)
        return sha
    raise SystemExit(msg + '\nUse --force to continue anyway (the matching check will fail).')


def step(n, total, title):
    log('')
    log('=== [%d/%d] %s ===' % (n, total, title))


def prepare(swf, skip_matching=False, force=False):
    """Steps 1-5: everything that does not depend on the target platform. Returns the number of steps done."""
    verify_swf(swf, force)
    CURRENT_SWF[0] = swf
    py = sys.executable
    step(2, 6, 'taking the file apart into decomp/ (local, not part of the repository)')
    shutil.rmtree(os.path.join(ROOT, 'decomp'), ignore_errors=True)
    run([py, os.path.join(TOOLS, 'swfproj', 'swfproj.py'), 'extract', swf, os.path.join(ROOT, 'decomp')])
    step(3, 6, 'compiling src/as2 with our compiler and rebuilding the SWF (matching check)')
    if skip_matching:
        log('skipped (--skip-matching)')
    else:
        rc = run([py, os.path.join(TOOLS, 'build.py')], check=False)
        if rc != 0:
            raise SystemExit('The rebuilt SWF is NOT byte-identical to your file. Check that you use the file this repository was made for.')
        log('Matching check passed: the SWF rebuilt from our source is byte-identical to your file (decompressed).')
    step(4, 6, 'extracting bitmaps and sounds into port/assets (local, not part of the repository)')
    run([py, os.path.join(TOOLS, 'assetc', 'build_assets.py'), swf, os.path.join(PORT, 'assets')])
    step(5, 6, 'rendering the app icon from the game artwork')
    fl = find_flutter()
    if not fl:
        raise SystemExit('Flutter is not installed: run  python rightmix.py setup')
    run([fl, 'pub', 'get'], cwd=PORT)
    run([fl, 'test', 'test/icon_render_test.dart', '--dart-define=ICON=true'], cwd=PORT)
    run([py, os.path.join(TOOLS, 'make_icons.py')])


def package_windows(out):
    rel = os.path.join(PORT, 'build', 'windows', 'x64', 'runner', 'Release')
    if not os.path.exists(os.path.join(rel, 'the_right_mix.exe')):
        raise SystemExit('Windows build output not found')
    stage = os.path.join(out, 'TheRightMix')
    shutil.rmtree(stage, ignore_errors=True)
    shutil.copytree(rel, stage)
    sysdir = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32')
    missing = []
    for dll in ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'):
        src = os.path.join(sysdir, dll)
        if os.path.exists(src):
            shutil.copy(src, stage)
        else:
            missing.append(dll)
    with open(os.path.join(stage, 'README.txt'), 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('The Right Mix - native Windows port (built locally from your own copy of the game)\n'
                'Run the_right_mix.exe. F1 or Esc: display settings. F11: full screen.\n'
                'Settings are saved in %APPDATA%\\TheRightMix\\settings.json.\n'
                'This build contains the game\'s artwork and sound: it is for your own use, do not redistribute it.\n')
    zpath = os.path.join(out, 'TheRightMix-windows-x64.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for d, _, fs in os.walk(stage):
            for fn in sorted(fs):
                p = os.path.join(d, fn)
                z.write(p, os.path.join('TheRightMix', os.path.relpath(p, stage)).replace(os.sep, '/'))
    if missing:
        log('note: %s not found on this PC; the zip needs the Visual C++ runtime installed on the target PC.' % ', '.join(missing))
    return stage, zpath


def cmd_build(args):
    swf = os.path.abspath(args.swf)
    want_win = args.windows or not (args.windows or args.android)
    want_and = args.android or not (args.windows or args.android)
    if want_win and not IS_WIN:
        log('The Windows port can only be built on Windows; skipping it.')
        want_win = False
    if not (want_win or want_and):
        raise SystemExit('nothing to build')
    step(1, 6, 'checking your copy of the game')
    prepare(swf, args.skip_matching, args.force)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    fl = find_flutter()
    step(6, 6, 'building the ports')
    built = []
    if want_win:
        run([fl, 'build', 'windows', '--release'], cwd=PORT)
        stage, zpath = package_windows(out)
        built += [stage, zpath]
    if want_and:
        if not find_jdk() or not find_android_sdk():
            raise SystemExit('Android needs a JDK and the Android SDK: run  python rightmix.py setup --accept-android-licenses')
        run([fl, 'build', 'apk', '--release'], cwd=PORT)
        apk = os.path.join(PORT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk')
        dst = os.path.join(out, 'TheRightMix-android.apk')
        shutil.copy(apk, dst)
        built.append(dst)
    log('')
    log('Done. Built for your own use (they contain the game\'s artwork and sound; do not redistribute):')
    for b in built:
        log('  ' + b)
    if want_and:
        log('The APK is signed with the Flutter debug key: enable "install unknown apps" on the phone to install it.')
    return 0


def cmd_verify(args):
    swf = os.path.abspath(args.swf)
    verify_swf(swf, args.force)
    CURRENT_SWF[0] = swf
    py = sys.executable
    shutil.rmtree(os.path.join(ROOT, 'decomp'), ignore_errors=True)
    run([py, os.path.join(TOOLS, 'swfproj', 'swfproj.py'), 'extract', swf, os.path.join(ROOT, 'decomp')])
    rc = run([py, os.path.join(TOOLS, 'build.py')], check=False)
    if rc == 0 and args.full:
        rc = run([py, os.path.join(TOOLS, 'verify_matching.py')], check=False)
    return rc


def cmd_gui(args):
    import rightmix_gui
    rightmix_gui.main()
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog='rightmix', description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('doctor', help='check what is installed')
    s = sub.add_parser('setup', help='download missing toolchains')
    s.add_argument('--accept-android-licenses', action='store_true', help='accept the Android SDK licenses (read them first)')
    s.add_argument('--flutter-only', action='store_true')
    s.add_argument('--android-only', action='store_true')
    s.add_argument('--no-vs', action='store_true', help='do not print the Visual Studio install hint')
    b = sub.add_parser('build', help='build the ports from your bartender.swf')
    b.add_argument('--swf', required=True, help='path of your bartender.swf')
    b.add_argument('--windows', action='store_true')
    b.add_argument('--android', action='store_true')
    b.add_argument('--out', default=os.path.join(ROOT, 'dist'))
    b.add_argument('--skip-matching', action='store_true', help='do not run the byte-identical rebuild check')
    b.add_argument('--force', action='store_true', help='continue even if the SWF is not the expected file')
    v = sub.add_parser('verify', help='only the matching-decomp check')
    v.add_argument('--swf', required=True)
    v.add_argument('--force', action='store_true')
    v.add_argument('--full', action='store_true', help='also run the per-unit audit with mutation tests (slow)')
    sub.add_parser('gui', help='open the graphical front end')
    args = ap.parse_args(argv)
    return {'doctor': cmd_doctor, 'setup': cmd_setup, 'build': cmd_build, 'verify': cmd_verify, 'gui': cmd_gui}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
