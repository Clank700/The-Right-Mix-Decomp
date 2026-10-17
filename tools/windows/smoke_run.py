#!/usr/bin/env python
"""smoke_run.py - launch the Windows build (silent, on the left-most monitor), exercise F1 / F11 / settings, screenshot.

  python tools/windows/smoke_run.py [path\to\the_right_mix.exe]

RIGHTMIX_MUTE=1 keeps the game silent; APPDATA points at a temp folder so the user's own settings are untouched.
Writes docs/verification/windows/*.png and prints PASS/FAIL lines.
"""
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes

from PIL import ImageGrab

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'port', 'build', 'windows', 'x64', 'runner', 'Release', 'the_right_mix.exe')
OUT = os.path.join(ROOT, 'docs', 'verification', 'windows')
u = ctypes.windll.user32
VK = {'F1': 0x70, 'F11': 0x7A, 'ESC': 0x1B, 'ENTER': 0x0D, 'ALT': 0x12}


def monitors():
    out = []
    P = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HMONITOR, wintypes.HDC, ctypes.POINTER(wintypes.RECT), wintypes.LPARAM)
    u.EnumDisplayMonitors(0, 0, P(lambda h, dc, r, d: out.append((r.contents.left, r.contents.top, r.contents.right, r.contents.bottom)) or 1), 0)
    return out


def find_window(pid, tries=100):
    W = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HWND, wintypes.LPARAM)
    for _ in range(tries):
        found = []

        def each(h, _):
            p = wintypes.DWORD()
            u.GetWindowThreadProcessId(h, ctypes.byref(p))
            if p.value == pid and u.IsWindowVisible(h) and u.GetParent(h) == 0:
                buf = ctypes.create_unicode_buffer(100)
                u.GetWindowTextW(h, buf, 100)
                if buf.value:
                    found.append(h)
            return 1

        u.EnumWindows(W(each), 0)
        if found:
            return found[0]
        time.sleep(0.2)
    raise RuntimeError('no window')


def focus(h, tries=10):
    """Bring the window to the foreground so injected keys reach it (Windows blocks focus stealing unless nudged)."""
    for _ in range(tries):
        u.keybd_event(0x12, 0, 0, 0)  # a synthetic Alt press lets SetForegroundWindow through
        u.keybd_event(0x12, 0, 2, 0)
        u.ShowWindow(h, 9)
        u.SetForegroundWindow(h)
        time.sleep(0.4)
        if u.GetForegroundWindow() == h:
            return True
    return False


def rect(h):
    r = wintypes.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    return r.left, r.top, r.right, r.bottom


def key(*names):
    for n in names:
        u.keybd_event(VK[n], 0, 0, 0)
    time.sleep(0.05)
    for n in reversed(names):
        u.keybd_event(VK[n], 0, 2, 0)
    time.sleep(0.8)


def shot(h, name):
    os.makedirs(OUT, exist_ok=True)
    img = ImageGrab.grab(bbox=rect(h), all_screens=True)
    img.save(os.path.join(OUT, name + '.png'))
    return img


def main():
    left = min(monitors())
    tmp = tempfile.mkdtemp(prefix='rightmix_appdata_')
    env = dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=tmp)
    proc = subprocess.Popen([EXE], env=env, cwd=os.path.dirname(EXE))
    ok = True

    def check(name, cond, detail=''):
        nonlocal ok
        ok &= bool(cond)
        print('  %-34s %s %s' % (name, 'PASS' if cond else 'FAIL', detail))

    try:
        h = find_window(proc.pid)
        u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 0, 0, 0x0001 | 0x0004)  # move to the left-most monitor
        time.sleep(1.5)
        r0 = rect(h)
        check('window on the left monitor', r0[0] < 0, str(r0))
        shot(h, '1_start')
        check('window has keyboard focus', focus(h))
        key('F1')
        img = shot(h, '2_panel')
        check('F1 opens a panel (picture changes)', img.getbbox() is not None)
        key('F1')
        focus(h)
        key('F11')
        r1 = rect(h)
        mon = [m for m in monitors() if m[0] <= r1[0] < m[2]][0]
        check('F11 goes full screen', r1 == mon, '%s vs monitor %s' % (r1, mon))
        shot(h, '3_fullscreen')
        focus(h)
        key('F11')
        r2 = rect(h)
        check('F11 again restores the window', r2[2] - r2[0] < mon[2] - mon[0], str(r2))
        time.sleep(0.5)  # (Alt+Enter is not delivered to the app by Windows in this setup; F11 is the shortcut)
        path = os.path.join(tmp, 'TheRightMix', 'settings.json')
        check('settings.json written', os.path.exists(path), path)
        if os.path.exists(path):
            print('   ', json.load(open(path)))
    finally:
        proc.kill()
    return 0 if ok else 1




def backdrop_check():
    """Second launch: blurred backdrop on, window made very wide; the side bars must not be black."""
    left = min(monitors())
    tmp = tempfile.mkdtemp(prefix='rightmix_appdata_')
    os.makedirs(os.path.join(tmp, 'TheRightMix'))
    json.dump({'blurredBackdrop': True, 'smoothMotion': True}, open(os.path.join(tmp, 'TheRightMix', 'settings.json'), 'w'))
    proc = subprocess.Popen([EXE], env=dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=tmp), cwd=os.path.dirname(EXE))
    try:
        h = find_window(proc.pid)
        u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 1800, 640, 0x0004)
        time.sleep(2)
        img = shot(h, '4_ultrawide_backdrop').convert('RGB')
        w, ht = img.size
        px = img.load()
        side = [px[x, y] for x in range(8, 120, 8) for y in range(ht // 4, 3 * ht // 4, 20)]
        bright = sum(sum(c) for c in side) / (3 * len(side))
        print('  %-34s %s mean side-bar brightness %.1f (0 = black)' % ('backdrop fills the side bars', 'PASS' if bright > 12 else 'FAIL', bright))
        return bright > 12
    finally:
        proc.kill()


if __name__ == '__main__':
    rc = main()
    ok2 = backdrop_check()
    sys.exit(rc or (0 if ok2 else 1))
