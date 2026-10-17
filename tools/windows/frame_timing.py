#!/usr/bin/env python
"""frame_timing.py - measure real frame build/raster times of the Windows build on this machine.

  python tools/windows/frame_timing.py [path\\to\\the_right_mix.exe]

The exe writes `build raster total` milliseconds per frame to the file named by RIGHTMIX_FRAMELOG. The script plays a
short session (idle intro, the intro curtain animation, picking a bottle, pouring) for several settings and prints
statistics per segment. Silent; windows are kept on the left-most monitor.
"""
import ctypes
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import smoke_run as s  # noqa: E402

u = ctypes.windll.user32
_args = [a for a in sys.argv[1:] if not a.startswith('--')]
EXE = _args[0] if _args else os.path.join(os.path.dirname(os.path.dirname(HERE)), 'port', 'build', 'windows', 'x64', 'runner', 'Release', 'the_right_mix.exe')


def go_fullscreen(h, label):
    """Move the window to the left-most monitor, press F11 and prove it covers that monitor (prints the rectangle)."""
    left = min(s.monitors())
    u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 1296, 960, 0x0004)
    time.sleep(1.0)
    s.focus(h)
    s.key('F11')
    time.sleep(1.2)
    r = s.rect(h)
    mon = [m for m in s.monitors() if m[0] <= r[0] + 5 < m[2] and m[1] <= r[1] + 5 < m[3]]
    ok = bool(mon) and r == mon[0]
    print('   [%s] window %s, monitor %s -> %s' % (label, r, mon[0] if mon else None, 'FULL SCREEN VERIFIED' if ok else 'NOT FULL SCREEN'))
    try:
        from PIL import ImageGrab
        os.makedirs(s.OUT, exist_ok=True)
        ImageGrab.grab(bbox=r, all_screens=True).save(os.path.join(s.OUT, 'fullscreen_%s.png' % label))
    except Exception:
        pass
    return ok


def read_log(path):
    rows = []
    try:
        for ln in open(path):
            p = ln.split()
            if len(p) == 3:
                rows.append(tuple(float(x) for x in p))
    except OSError:
        pass
    return rows


def stats(rows):
    if not rows:
        return 'no frames'
    raster = sorted(r[1] for r in rows)
    total = sorted(r[2] for r in rows)
    n = len(rows)
    return 'frames %4d  raster ms mean %5.2f p95 %5.2f max %6.2f   total ms mean %5.2f p95 %5.2f max %6.2f   >16.7ms: %d' % (
        n, statistics.mean(raster), raster[int(n * .95)], raster[-1], statistics.mean(total), total[int(n * .95)], total[-1],
        sum(1 for r in rows if r[2] > 16.7))


def session(label, settings, fullscreen=False):
    tmp = tempfile.mkdtemp(prefix='rightmix_ft_')
    os.makedirs(os.path.join(tmp, 'TheRightMix'))
    st = dict(settings, fullscreen=fullscreen)
    json.dump(st, open(os.path.join(tmp, 'TheRightMix', 'settings.json'), 'w'))
    log = os.path.join(tmp, 'frames.log')
    proc = subprocess.Popen([EXE], env=dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=tmp, RIGHTMIX_FRAMELOG=log),
                            cwd=os.path.dirname(EXE))
    try:
        h = s.find_window(proc.pid)
        left = min(s.monitors())
        if not fullscreen:
            u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 1296, 960, 0x0004)
        else:
            u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 0, 0, 0x0001 | 0x0004)
        time.sleep(2.5)
        s.focus(h)

        def click_stage(sx, sy):
            cr = wintypes.RECT()
            u.GetClientRect(h, ctypes.byref(cr))
            pt = wintypes.POINT(0, 0)
            u.ClientToScreen(h, ctypes.byref(pt))
            w, hh = cr.right, cr.bottom
            scale = min(w / 600, hh / 440)
            u.SetCursorPos(int(pt.x + (w - 600 * scale) / 2 + sx * scale), int(pt.y + (hh - 440 * scale) / 2 + sy * scale))
            time.sleep(0.15)
            u.mouse_event(2, 0, 0, 0, 0)
            time.sleep(0.08)
            u.mouse_event(4, 0, 0, 0, 0)

        marks = [('idle intro', len(read_log(log)))]
        time.sleep(3)
        marks.append(('intro curtain animation', len(read_log(log))))
        click_stage(264, 348)  # Let's mix
        time.sleep(2.5)
        marks.append(('pick a bottle / arm sweeps', len(read_log(log))))
        click_stage(156, 147)
        time.sleep(3)
        marks.append(('pour', len(read_log(log))))
        u.mouse_event(2, 0, 0, 0, 0)  # hold on the Pour button
        click_cr = wintypes.RECT()
        u.GetClientRect(h, ctypes.byref(click_cr))
        pt = wintypes.POINT(0, 0)
        u.ClientToScreen(h, ctypes.byref(pt))
        scale = min(click_cr.right / 600, click_cr.bottom / 440)
        u.mouse_event(4, 0, 0, 0, 0)
        u.SetCursorPos(int(pt.x + (click_cr.right - 600 * scale) / 2 + 72 * scale), int(pt.y + (click_cr.bottom - 440 * scale) / 2 + 363 * scale))
        time.sleep(0.2)
        u.mouse_event(2, 0, 0, 0, 0)
        time.sleep(3)
        u.mouse_event(4, 0, 0, 0, 0)
        marks.append(('end', len(read_log(log))))
        rows = read_log(log)
        print(label)
        for (name, a), (_, b) in zip(marks, marks[1:] + [('', len(rows))]):
            print('   %-28s %s' % (name, stats(rows[a:b])))
        return rows
    finally:
        proc.kill()
        proc.wait()
        time.sleep(1)


base = {'smoothMotion': True, 'integerScale': False, 'blurredBackdrop': False}


def main_old_entry():
    session('windowed 1296x960, smooth motion ON', base)
    session('windowed 1296x960, smooth motion OFF', dict(base, smoothMotion=False))
    session('fullscreen 1080p, smooth motion ON', base, fullscreen=True)
    session('fullscreen 1080p, smooth ON + blurred backdrop', dict(base, blurredBackdrop=True), fullscreen=True)


def full_game(label, settings, fullscreen=True, seconds_after_serve=50, first_wait=2.5, env_extra=None):
    """Play a whole drink (pick, pour, shake, serve) and print frame statistics for every second of the run."""
    tmp = tempfile.mkdtemp(prefix='rightmix_ft_')
    os.makedirs(os.path.join(tmp, 'TheRightMix'))
    json.dump(dict(settings, fullscreen=False), open(os.path.join(tmp, 'TheRightMix', 'settings.json'), 'w'))
    log = os.path.join(tmp, 'frames.log')
    proc = subprocess.Popen([EXE], env=dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=tmp, RIGHTMIX_FRAMELOG=log,
                                            **(env_extra or {})), cwd=os.path.dirname(EXE))
    stamps = []  # (seconds since start, frames logged so far, what was happening)
    t0 = time.time()
    try:
        h = s.find_window(proc.pid)
        if fullscreen:
            go_fullscreen(h, 'full_game')
        else:
            left = min(s.monitors())
            u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 1296, 960, 0x0004)
        time.sleep(first_wait)
        s.focus(h)

        def to_screen(sx, sy):
            cr = wintypes.RECT()
            u.GetClientRect(h, ctypes.byref(cr))
            pt = wintypes.POINT(0, 0)
            u.ClientToScreen(h, ctypes.byref(pt))
            scale = min(cr.right / 600, cr.bottom / 440)
            return int(pt.x + (cr.right - 600 * scale) / 2 + sx * scale), int(pt.y + (cr.bottom - 440 * scale) / 2 + sy * scale)

        def move(sx, sy):
            u.SetCursorPos(*to_screen(sx, sy))
            time.sleep(0.2)

        def down():
            u.mouse_event(2, 0, 0, 0, 0)

        def up():
            u.mouse_event(4, 0, 0, 0, 0)

        def mark(what):
            stamps.append((time.time() - t0, len(read_log(log)), what))

        mark('intro')
        move(264, 348); down(); time.sleep(0.1); up(); mark('start pressed'); time.sleep(2.5)
        move(156, 147); down(); time.sleep(0.1); up(); mark('bottle'); time.sleep(2.5)
        move(72, 363); down(); mark('pour'); time.sleep(3.2); up()
        move(207, 363); down(); mark('shake'); time.sleep(4.5); up(); mark('shake released'); time.sleep(1.5)
        move(333, 363); down(); time.sleep(0.1); up(); mark('serve pressed')
        end = time.time() + seconds_after_serve
        while time.time() < end:
            time.sleep(1)
            mark('')
        rows = read_log(log)
        try:
            notes = open(log + '.notes').read().splitlines()
        except OSError:
            notes = []
        print(label)
        slow = [i for i, r in enumerate(rows) if r[1] > 25]
        for i in slow[:40]:
            print('   slow frame %5d raster %6.1f ms  total %6.1f ms   %s' % (i, rows[i][1], rows[i][2], notes[i] if i < len(notes) else '?'))
        # one line per second: where did frames get slow?
        prev_n, prev_t = 0, 0.0
        for t, n, what in stamps:
            seg = rows[prev_n:n]
            if seg:
                tot = sorted(r[2] for r in seg)
                rast = [r[1] for r in seg]
                flag = '  <-- slow' if tot[-1] > 25 or statistics.mean(rast) > 14 else ''
                print('  t=%5.1fs %-15s frames %3d  raster mean %5.2f max %6.2f   total max %6.2f%s' % (
                    t, what, len(seg), statistics.mean(rast), max(rast), tot[-1], flag))
            prev_n, prev_t = n, t
    finally:
        proc.kill()
        proc.wait()
        time.sleep(1)


def main():
    if '--end' in sys.argv:
        probe = next((a[8:] for a in sys.argv if a.startswith('--probe=')), '')
        smooth = '--nosmooth' not in sys.argv
        end_only('fullscreen smooth=%s probe=%s' % (smooth, probe or '-'), dict(base, smoothMotion=smooth), probe,
                 fullscreen='--windowed' not in sys.argv)
        return
    if '--game' in sys.argv:
        for arg in sys.argv:
            if arg.startswith('--wait='):
                wait = float(arg[7:])
                break
        else:
            wait = 2.5
        extra = None
        cfg = dict(base, smoothMotion=False) if '--nosmooth' in sys.argv else base
        full_game('FULL GAME fullscreen 1080p, smooth motion %s, first click after %.1f s' % ('OFF' if '--nosmooth' in sys.argv else 'ON', wait), cfg, first_wait=wait, env_extra=extra)
        return
    main_old_entry()



def end_only(label, settings, probe='', fullscreen=True, runtime=17):
    """Jump straight to a finale and its end-card curtain (RIGHTMIX_AUTOPLAY=end) and report the curtain frames."""
    tmp = tempfile.mkdtemp(prefix='rightmix_ft_')
    os.makedirs(os.path.join(tmp, 'TheRightMix'))
    json.dump(dict(settings, fullscreen=False), open(os.path.join(tmp, 'TheRightMix', 'settings.json'), 'w'))
    log = os.path.join(tmp, 'frames.log')
    proc = subprocess.Popen([EXE], env=dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=tmp, RIGHTMIX_FRAMELOG=log,
                                            RIGHTMIX_AUTOPLAY='end', RIGHTMIX_PROBE=probe), cwd=os.path.dirname(EXE))
    try:
        h = s.find_window(proc.pid)
        if fullscreen:
            go_fullscreen(h, label.replace(' ', '_').replace('=', '-'))
        else:
            left = min(s.monitors())
            u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 1296, 960, 0x0004)
        time.sleep(runtime)
        rows = read_log(log)
        notes = open(log + '.notes').read().splitlines()
        import re
        curtain = []
        for i, r in enumerate(rows):
            m = re.search(r'endCard=(\d+) visible=true', notes[i]) if i < len(notes) else None
            if m and 5 <= int(m.group(1)) <= 19:
                curtain.append(r)
        scene = [r for i, r in enumerate(rows) if i < len(notes) and 'finale=' in notes[i] and 'visible=false' in notes[i] and 'finale=None' not in notes[i]]
        def fmt(rs):
            if not rs:
                return 'no frames'
            ra = sorted(x[1] for x in rs); to = sorted(x[2] for x in rs)
            return 'n=%3d raster mean %5.1f p95 %5.1f max %5.1f | total mean %5.1f max %5.1f | >16.7ms %d' % (
                len(rs), statistics.mean(ra), ra[int(len(ra) * .95)], ra[-1], statistics.mean(to), to[-1], sum(1 for x in rs if x[2] > 16.7))
        print('%-46s finale only: %s' % (label, fmt(scene)))
        print('%-46s curtain    : %s' % ('', fmt(curtain)))
        return curtain
    finally:
        proc.kill()
        proc.wait()
        time.sleep(1)

if __name__ == '__main__':
    main()
