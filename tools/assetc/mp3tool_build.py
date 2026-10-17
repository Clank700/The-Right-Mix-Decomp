"""mp3tool_build.py - compile tools/assetc/mp3tool.c (a tiny MP3 -> PCM converter around the public-domain miniaudio
decoder) with whatever C compiler the machine has: MSVC (found with vswhere) on Windows, or gcc / clang / cc elsewhere.

  python tools/assetc/mp3tool_build.py        builds tools/assetc/bin/mp3tool[.exe] if it is missing or older than its source
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'mp3tool.c')
OUT_DIR = os.path.join(HERE, 'bin')
EXE = os.path.join(OUT_DIR, 'mp3tool.exe' if os.name == 'nt' else 'mp3tool')


def find_vcvars():
    """Path of vcvars64.bat of a Visual Studio / Build Tools install that has the C++ tools, or None."""
    pf = os.environ.get('ProgramFiles(x86)') or os.environ.get('ProgramFiles') or r'C:\Program Files (x86)'
    vswhere = os.path.join(pf, 'Microsoft Visual Studio', 'Installer', 'vswhere.exe')
    if not os.path.exists(vswhere):
        return None
    try:
        out = subprocess.run([vswhere, '-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                              '-property', 'installationPath'], capture_output=True, text=True).stdout.strip()
    except OSError:
        return None
    if not out:
        return None
    p = os.path.join(out.splitlines()[0], 'VC', 'Auxiliary', 'Build', 'vcvars64.bat')
    return p if os.path.exists(p) else None


def compiler_description():
    if os.name == 'nt':
        v = find_vcvars()
        return 'MSVC (%s)' % v if v else None
    for c in ('cc', 'gcc', 'clang'):
        if shutil.which(c):
            return shutil.which(c)
    return None


def ensure():
    """Build mp3tool if needed. Returns its path; raises RuntimeError when no compiler is available."""
    if os.path.exists(EXE) and os.path.getmtime(EXE) >= os.path.getmtime(SRC):
        return EXE
    os.makedirs(OUT_DIR, exist_ok=True)
    if os.name == 'nt':
        vcvars = find_vcvars()
        if not vcvars:
            raise RuntimeError('no C compiler found: install "Visual Studio Build Tools" with the "Desktop development with C++" workload')
        bat = os.path.join(OUT_DIR, '_build.bat')
        with open(bat, 'w') as f:
            f.write('@echo off\r\ncall "%s" >nul\r\ncd /d "%s"\r\ncl /nologo /O2 /Fo:bin\\ /Fe:bin\\mp3tool.exe mp3tool.c >nul\r\n' % (vcvars, HERE))
        r = subprocess.run(['cmd', '/c', bat], capture_output=True, text=True)
        os.remove(bat)
    else:
        cc = next((shutil.which(c) for c in ('cc', 'gcc', 'clang') if shutil.which(c)), None)
        if not cc:
            raise RuntimeError('no C compiler found (install gcc or clang)')
        r = subprocess.run([cc, '-O2', '-o', EXE, SRC, '-lm', '-lpthread', '-ldl'], capture_output=True, text=True)
    if not os.path.exists(EXE):
        raise RuntimeError('compiling mp3tool failed:\n' + (r.stdout or '') + (r.stderr or ''))
    return EXE


if __name__ == '__main__':
    print(ensure())
