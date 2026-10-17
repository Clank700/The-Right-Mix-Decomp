#!/usr/bin/env python
"""persistence_check.py - settings and rendering across a Windows restart, plus window resizing while the game moves.

  python tools/windows/persistence_check.py [path\\to\\the_right_mix.exe]

Silent (RIGHTMIX_MUTE=1), windows are kept on the left-most monitor, APPDATA points at a temp folder.
 run A  fresh settings: change integer scaling / blurred backdrop / full screen through the panel with the keyboard, kill
 run B  same APPDATA: must start full screen with the same options and draw the same picture as run A
 run C  corrupt settings file: must start with defaults
 run D  resize the window repeatedly while the arm is moving; the picture must keep its aspect ratio and the game keeps running
Screenshots go to docs/verification/windows/.
"""
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes

from PIL import ImageChops, ImageGrab, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import smoke_run as s  # noqa: E402

u = ctypes.windll.user32
EXE = sys.argv[1] if len(sys.argv) > 1 else s.EXE
OUT = s.OUT
results = []


def check(name, cond, detail=''):
    results.append(bool(cond))
    print('  %-46s %s %s' % (name, 'PASS' if cond else 'FAIL', detail))


def launch(appdata, park=True):
    proc = subprocess.Popen([EXE], env=dict(os.environ, RIGHTMIX_MUTE='1', APPDATA=appdata), cwd=os.path.dirname(EXE))
    h = s.find_window(proc.pid)
    if park:
        left = min(s.monitors())
        u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, 0, 0, 0x0001 | 0x0004)
    time.sleep(1.5)
    return proc, h


def monitor_of(r):
    cx, cy = (r[0] + r[2]) // 2, (r[1] + r[3]) // 2
    return [m for m in s.monitors() if m[0] <= cx < m[2] and m[1] <= cy < m[3]][0]


def grab(h, name):
    os.makedirs(OUT, exist_ok=True)
    img = ImageGrab.grab(bbox=s.rect(h), all_screens=True).convert('RGB')
    img.save(os.path.join(OUT, name + '.png'))
    return img


def content_box(img, thresh=24):
    """Box around the picture: rows/columns that are mostly non-black (ignores the small gear button and window edges)."""
    w, hgt = img.size
    px = img.load()
    cols = [0] * w
    rows = [0] * hgt
    for y in range(0, hgt, 2):
        for x in range(0, w, 2):
            if sum(px[x, y]) > thresh:
                cols[x] += 1
                rows[y] += 1
    xs = [x for x in range(w) if cols[x] > 0.35 * (hgt / 2)]
    ys = [y for y in range(hgt) if rows[y] > 0.35 * (w / 2)]
    return (min(xs), min(ys), max(xs), max(ys)) if xs and ys else None


def settings_path(appdata):
    return os.path.join(appdata, 'TheRightMix', 'settings.json')


def load(appdata):
    try:
        return json.load(open(settings_path(appdata)))
    except Exception:
        return None


def tab(n):
    for _ in range(n):
        u.keybd_event(0x09, 0, 0, 0)
        u.keybd_event(0x09, 0, 2, 0)
        time.sleep(0.15)


def space():
    u.keybd_event(0x20, 0, 0, 0)
    u.keybd_event(0x20, 0, 2, 0)
    time.sleep(0.4)


def main():
    appdata = tempfile.mkdtemp(prefix='rightmix_persist_')

    print('run A: change settings through the panel')
    proc, h = launch(appdata)
    try:
        check('keyboard focus', s.focus(h))
        s.key('F1')

        def click_client(dx, dy):
            """Click at an offset from the centre of the window's client area."""
            cr = wintypes.RECT()
            u.GetClientRect(h, ctypes.byref(cr))
            pt = wintypes.POINT(0, 0)
            u.ClientToScreen(h, ctypes.byref(pt))
            u.SetCursorPos(int(pt.x + cr.right / 2 + dx), int(pt.y + cr.bottom / 2 + dy))
            time.sleep(0.2)
            u.mouse_event(2, 0, 0, 0, 0)
            time.sleep(0.08)
            u.mouse_event(4, 0, 0, 0, 0)
            time.sleep(0.6)

        click_client(162, -10.5)  # "Integer scaling" switch (row offsets measured from the panel layout)
        click_client(162, 50.5)   # "Blurred backdrop" switch
        s.key('F1')  # close the panel
        time.sleep(0.5)
        saved = load(appdata)
        check('integer scaling + backdrop saved', saved and saved['integerScale'] and saved['blurredBackdrop'], str(saved))
        s.focus(h)
        s.key('F11')
        time.sleep(1.0)
        saved = load(appdata)
        check('full screen saved', saved and saved['fullscreen'], str(saved))
        rA = s.rect(h)
        mon = monitor_of(rA)
        check('run A is full screen', rA == mon, str(rA))
        imgA = grab(h, 'persist_A_before_restart')
    finally:
        proc.kill()
        proc.wait()
    time.sleep(1.0)

    print('run B: restart with the same settings')
    proc, h = launch(appdata, park=False)
    try:
        time.sleep(1.5)
        rB = s.rect(h)
        monB = monitor_of(rB)
        check('restart comes up full screen', rB == monB, str(rB))
        imgB = grab(h, 'persist_B_after_restart')
        savedB = load(appdata)
        check('settings file unchanged by the restart', savedB == saved, str(savedB))
        if imgA.size == imgB.size:
            diff = ImageStat.Stat(ImageChops.difference(imgA, imgB)).mean
            check('same picture before and after restart', max(diff) < 3, 'mean channel difference %.2f' % max(diff))
        else:
            check('same picture before and after restart', False, 'sizes differ %s vs %s' % (imgA.size, imgB.size))
        box = content_box(imgB)
        # integer scaling at 100%% DPI on a 1080 px screen: 2x = 880 px tall, centred; the backdrop fills the bars
        mid = imgB.getpixel((40, imgB.height // 2))
        check('blurred backdrop is applied (bars are not black)', sum(mid) > 40, 'bar pixel %s' % (mid,))
    finally:
        proc.kill()
        proc.wait()
    time.sleep(1.0)

    print('run B2: integer scaling alone, full screen, no backdrop')
    appdata4 = tempfile.mkdtemp(prefix='rightmix_persist_')
    os.makedirs(os.path.join(appdata4, 'TheRightMix'))
    json.dump({'integerScale': True, 'fullscreen': True}, open(settings_path(appdata4), 'w'))
    proc, h = launch(appdata4, park=False)
    try:
        time.sleep(1.5)
        img = grab(h, 'persist_B2_integer_only')
        box = content_box(img)
        sh = box[3] - box[1] + 1 if box else 0
        sw = box[2] - box[0] + 1 if box else 0
        check('integer scaling: stage drawn exactly 2x (1200 x 880)', abs(sh - 880) <= 2 and abs(sw - 1200) <= 2,
              'picture %dx%d on a %dx%d screen' % (sw, sh, img.width, img.height))
    finally:
        proc.kill()
        proc.wait()
    time.sleep(1.0)

    print('run C: corrupt settings file')
    appdata2 = tempfile.mkdtemp(prefix='rightmix_persist_')
    os.makedirs(os.path.join(appdata2, 'TheRightMix'))
    open(settings_path(appdata2), 'w').write('{ this is not json')
    proc, h = launch(appdata2)
    try:
        r = s.rect(h)
        check('corrupt file: starts normally, windowed', r != monitor_of(r) and (r[2] - r[0]) < 1900, str(r))
        img = grab(h, 'persist_C_corrupt_settings')
        mid = img.getpixel((12, img.height // 2))
        check('corrupt file: default look (black bars, no backdrop)', sum(mid) < 40, 'bar pixel %s' % (mid,))
    finally:
        proc.kill()
        proc.wait()
    time.sleep(1.0)

    print('run D: resize while the arm is moving')
    appdata3 = tempfile.mkdtemp(prefix='rightmix_persist_')
    proc, h = launch(appdata3)
    try:
        s.focus(h)

        def client_to_screen(sx, sy):
            cr = wintypes.RECT()
            u.GetClientRect(h, ctypes.byref(cr))
            pt = wintypes.POINT(0, 0)
            u.ClientToScreen(h, ctypes.byref(pt))
            w, hh = cr.right, cr.bottom
            scale = min(w / 600, hh / 440)
            return int(pt.x + (w - 600 * scale) / 2 + sx * scale), int(pt.y + (hh - 440 * scale) / 2 + sy * scale)

        def click(sx, sy):
            x, y = client_to_screen(sx, sy)
            u.SetCursorPos(x, y)
            time.sleep(0.15)
            u.mouse_event(2, 0, 0, 0, 0)
            time.sleep(0.08)
            u.mouse_event(4, 0, 0, 0, 0)
            time.sleep(0.4)

        click(264, 348)  # Let's mix
        time.sleep(1.5)
        click(156, 147)  # a bottle: the arm sweeps
        sizes = [(900, 700), (1400, 560), (700, 900), (1000, 1000), (640, 480), (1600, 700), (800, 600)]
        left = min(s.monitors())
        boxes = []
        for i, (w, hh) in enumerate(sizes):
            u.SetWindowPos(h, 0, left[0] + 40, left[1] + 40, w, hh, 0x0004)
            time.sleep(0.6)
            img = grab(h, 'resize_%d_%dx%d' % (i, w, hh))
            # skip the title bar / borders: measure the client area only
            cr = wintypes.RECT()
            u.GetClientRect(h, ctypes.byref(cr))
            pt = wintypes.POINT(0, 0)
            u.ClientToScreen(h, ctypes.byref(pt))
            r = s.rect(h)
            client = img.crop((pt.x - r[0], pt.y - r[1], pt.x - r[0] + cr.right, pt.y - r[1] + cr.bottom))
            box = content_box(client, thresh=60)
            boxes.append((w, hh, client.size, box))
        for w, hh, cs, box in boxes:
            if not box:
                check('resize %dx%d: picture visible' % (w, hh), False)
                continue
            bw, bh = box[2] - box[0], box[3] - box[1]
            aspect = bw / bh
            check('resize %dx%d: aspect ratio kept' % (w, hh), abs(aspect - 600 / 440) < 0.08,
                  'client %dx%d picture %dx%d aspect %.3f' % (cs[0], cs[1], bw, bh, aspect))
        check('still running after resizing', proc.poll() is None)
        # still responsive: the pointer mapping follows the new size (click the Pour area; the picture must change)
        before = grab(h, 'resize_final_before_click')
        click(72, 363)
        time.sleep(0.8)
        after = grab(h, 'resize_final_after_click')
        check('input still works after resizing', ImageStat.Stat(ImageChops.difference(before, after)).mean[0] > 0.05)
    finally:
        proc.kill()
        proc.wait()
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main())
