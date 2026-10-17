#!/usr/bin/env python
"""verify_device.py - behavioural checks of the Android build on an emulator (headless and muted).

  python tools/android/verify_device.py rightmix24 [rightmix30 ...]      AVD names (see docs/VERIFICATION.md)

Uses the TRACE build (build/android/trace.apk: `flutter build apk --release --dart-define=TRACE=true`), which logs phase
changes and a once-per-second tick heartbeat ("RM ..." lines). Checks per device:
  boot/API level, install, launch without crash, tick rate (18/s), touch -> game actions (stage->screen mapping),
  home/resume lifecycle (ticks stop, no catch-up burst, audio players pause/resume), several screen sizes / aspect
  ratios (stage fits, centred, aspect preserved). Writes docs/verification/android/<avd>.json and screenshots.
Not covered here (cannot be injected through adb): multi-finger input (unit-tested in port/test/input_timing_test.dart).
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SDK = (os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or
       os.path.join(os.environ.get('LOCALAPPDATA', os.path.expanduser('~')), 'Android', 'Sdk' if os.name == 'nt' else 'sdk'))
EXE = '.exe' if os.name == 'nt' else ''
ADB = os.path.join(SDK, 'platform-tools', 'adb' + EXE)
EMU = os.path.join(SDK, 'emulator', 'emulator' + EXE)
APK = os.path.join(ROOT, 'build', 'android', 'trace.apk')
OUT = os.path.join(ROOT, 'docs', 'verification', 'android')
PKG = 'org.decomp.the_right_mix'
STAGE_W, STAGE_H = 600, 440


class Dev:
    def __init__(self, avd, port):
        self.avd, self.port = avd, port
        self.serial = 'emulator-%d' % port
        self.proc = None

    def adb(self, *a, timeout=60, binary=False):
        r = subprocess.run([ADB, '-s', self.serial, *a], capture_output=True, timeout=timeout)
        return r.stdout if binary else r.stdout.decode('utf-8', 'replace')

    def start(self):
        flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
        self.proc = subprocess.Popen([EMU, '-avd', self.avd, '-port', str(self.port), '-no-window', '-no-audio',
                                      '-no-snapshot', '-no-boot-anim', '-gpu', 'host'], creationflags=flags,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([ADB, 'start-server'], capture_output=True)
        t0 = time.time()
        while time.time() - t0 < 420:
            if 'device' in subprocess.run([ADB, 'devices'], capture_output=True, text=True).stdout.split(self.serial)[-1][:12]:
                if self.adb('shell', 'getprop', 'sys.boot_completed').strip() == '1':
                    return time.time() - t0
            time.sleep(3)
        raise RuntimeError('emulator did not boot')

    def stop(self):
        subprocess.run([ADB, '-s', self.serial, 'emu', 'kill'], capture_output=True)
        time.sleep(3)

    def size(self):
        m = re.search(r'(?:Override size|Physical size): (\d+)x(\d+)', self.adb('shell', 'wm', 'size').split('Override')[-1]
                      if 'Override' in self.adb('shell', 'wm', 'size') else self.adb('shell', 'wm', 'size'))
        out = self.adb('shell', 'wm', 'size')
        mm = re.findall(r'(\d+)x(\d+)', out)
        return tuple(map(int, mm[-1]))

    def logs(self):
        raw = self.adb('logcat', '-d', '-v', 'time', 'flutter:I', '*:S', timeout=120)
        out = []
        for ln in raw.splitlines():
            m = re.match(r'(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+\w/flutter.*?: (RM .*)$', ln)
            if m:
                ts = datetime.strptime('2000-' + m.group(1), '%Y-%m-%d %H:%M:%S.%f').timestamp()
                out.append((ts, m.group(2)))
        return out

    def screenshot(self, name=None):
        png = self.adb('exec-out', 'screencap', '-p', binary=True, timeout=60)
        path = os.path.join(OUT, '%s_%s.png' % (self.avd, name)) if name else None
        tmp = os.path.join(OUT, '_tmp.png')
        open(tmp, 'wb').write(png)
        img = Image.open(tmp).convert('RGB')
        if path:
            img.resize((img.width // 3, img.height // 3)).save(path)
        return img

    def launch(self):
        self.adb('shell', 'am', 'start', '-n', PKG + '/.MainActivity')

    def players_started(self):
        """Audio streams currently playing for the app: Android's player list (API 26+) or the mixer's active tracks."""
        txt = self.adb('shell', 'dumpsys', 'audio', timeout=60)
        pid = self.pid()
        # only the app's own players (other apps on Google images also play sounds): "u/pid:<uid>/<pid> ... state:started"
        started = len([ln for ln in txt.splitlines() if 'state:started' in ln and re.search(r'/%s' % pid, ln)]) if pid else 0
        fl = self.adb('shell', 'dumpsys', 'media.audio_flinger', timeout=60)
        active = sum(int(x) for x in re.findall(r'of which (\d+) are active', fl))
        return max(started, active)

    def mark(self, tag):
        """Write a marker line to logcat and return its logcat timestamp (same clock as the app's log lines)."""
        self.adb('shell', 'log', '-t', 'RMMARK', tag)
        time.sleep(0.5)
        raw = self.adb('logcat', '-d', '-v', 'time', '-s', 'RMMARK', timeout=60)
        ts = None
        for ln in raw.splitlines():
            m = re.match(r'(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+\w/RMMARK.*: ' + tag, ln)
            if m:
                ts = datetime.strptime('2000-' + m.group(1), '%Y-%m-%d %H:%M:%S.%f').timestamp()
        return ts

    def pid(self):
        return self.adb('shell', 'pidof', PKG).strip()


def to_screen(sx, sy, w, h):
    s = min(w / STAGE_W, h / STAGE_H)
    return round((w - STAGE_W * s) / 2 + sx * s), round((h - STAGE_H * s) / 2 + sy * s)


def content_box(img):
    """Bounding box of the non-black area (sampled). The top-right corner is skipped: the settings gear button can sit there."""
    w, h = img.size
    px = img.load()
    xs, ys = [], []
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            if x > w - 260 and y < 260:
                continue
            r, g, b = px[x, y]
            if r + g + b > 24:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


def run(avd, port):
    os.makedirs(OUT, exist_ok=True)
    pts = json.load(open(os.path.join(ROOT, 'build', 'hit_points.json')))
    d = Dev(avd, port)
    rep = {'avd': avd, 'checks': {}}

    def check(name, ok, detail=''):
        rep['checks'][name] = {'pass': bool(ok), 'detail': detail}
        print('  %-34s %s %s' % (name, 'PASS' if ok else 'FAIL', detail))

    try:
        rep['boot_seconds'] = round(d.start(), 1)
        rep['api'] = int(d.adb('shell', 'getprop', 'ro.build.version.sdk').strip())
        rep['release'] = d.adb('shell', 'getprop', 'ro.build.version.release').strip()
        print(avd, 'API', rep['api'], 'Android', rep['release'], 'boot %ss' % rep['boot_seconds'])
        d.adb('logcat', '-c')
        out = d.adb('install', '-r', APK, timeout=240)
        check('install', 'Success' in out, out.strip()[-60:])
        d.adb('shell', 'pm', 'clear', PKG)  # start from default settings (they are saved between runs)
        d.adb('shell', 'wm', 'size', 'reset')
        d.launch()
        time.sleep(10)
        logs = d.logs()
        crash = d.adb('logcat', '-d', '-b', 'crash', timeout=60)
        check('launch_no_crash', d.pid() != '' and 'FATAL' not in crash, 'pid ' + d.pid())
        hb = [(t, m) for t, m in logs if ' hb ' in m]
        if not hb:  # cold start on a fresh emulator can take longer than 10 s (first-run dex/shader work)
            time.sleep(15)
            logs = d.logs()
            hb = [(t, m) for t, m in logs if ' hb ' in m]
        check('game_ticking', len(hb) >= 1, '%d heartbeats within the start-up window' % len(hb))
        d.screenshot('1_intro')

        # --- tick rate -------------------------------------------------------------------------------------------
        d.adb('logcat', '-c')
        time.sleep(15)
        hb = [(t, m) for t, m in d.logs() if ' hb ' in m]
        if len(hb) >= 5:
            n0 = int(re.search(r'tick=(\d+)', hb[0][1]).group(1))
            n1 = int(re.search(r'tick=(\d+)', hb[-1][1]).group(1))
            rate = (n1 - n0) / (hb[-1][0] - hb[0][0])
            check('tick_rate_18_per_s', abs(rate - 18) < 1.0, '%.2f ticks/s over %d s' % (rate, hb[-1][0] - hb[0][0]))
        else:
            check('tick_rate_18_per_s', False, 'too few heartbeats: %d' % len(hb))
        refresh = d.adb('shell', 'dumpsys', 'display')
        m = re.search(r'renderFrameRate=([\d.]+)|fps=([\d.]+)', refresh)
        rep['display_refresh_hint'] = m.group(0) if m else 'unknown'

        # --- touch -> game actions ---------------------------------------------------------------------------------
        w, h = d.size()
        if h > w:
            w, h = h, w
        d.adb('logcat', '-c')

        def tap(name):
            x, y = to_screen(*pts[name], w, h)
            d.adb('shell', 'input', 'tap', str(x), str(y))

        def hold(name, ms):
            x, y = to_screen(*pts[name], w, h)
            d.adb('shell', 'input', 'swipe', str(x), str(y), str(x), str(y), str(ms))

        def phases():
            return [re.search(r'phase=(\w+)', m).group(1) for _, m in d.logs() if 'phase=' in m]

        tap('start')
        time.sleep(2)
        check('touch_start_button', 'rest' in phases(), str(phases()))
        d.screenshot('2_bar')
        tap('bottle14')
        time.sleep(4)
        ph = phases()
        check('touch_pick_bottle', 'getBottle' in ph, str(ph))
        hold('pour', 3500)
        time.sleep(1)
        logs = [m for _, m in d.logs() if 'phase=' in m]
        poured = [m for m in logs if 'phase=pour' in m]
        check('touch_hold_pour', bool(poured), (poured[-1] if poured else str(logs[-3:])))
        d.screenshot('3_after_pour')
        vols = [float(re.search(r'vol=([\d.]+)', m).group(1)) for m in logs if 'vol=' in m]
        check('pour_adds_volume', bool(vols) and max(vols) > 0, 'max vol %s' % (max(vols) if vols else None))
        hold('shake', 3500)
        time.sleep(1)
        ph = phases()
        check('touch_hold_shake', 'shake' in ph or 'shakeRest' in ph, str(ph[-6:]))
        d.screenshot('4_shaking')

        # --- lifecycle ----------------------------------------------------------------------------------------------
        rep['audio_players_before_home'] = d.players_started()
        d.adb('logcat', '-c')
        d.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        time.sleep(4)
        d.adb('logcat', '-c')
        time.sleep(4)
        hb_paused = [m for _, m in d.logs() if ' hb ' in m]
        check('background_stops_ticks', len(hb_paused) == 0, '%d heartbeats while in background' % len(hb_paused))
        rep['audio_players_in_background'] = d.players_started()
        check('background_pauses_audio', rep['audio_players_before_home'] >= 1 and rep['audio_players_in_background'] == 0,
              'started players: before %s, in background %s' % (rep['audio_players_before_home'],
                                                                rep['audio_players_in_background']))
        d.adb('logcat', '-c')
        t_resume = d.mark('resume')
        d.launch()
        time.sleep(6)
        hb2 = [(t, m) for t, m in d.logs() if ' hb ' in m]
        check('resume_ticks_again', len(hb2) >= 2, '%d heartbeats after resume' % len(hb2))
        if len(hb2) >= 3:
            # heartbeats are every 18 ticks: after resuming they must come once a second, not in a burst
            gaps = [b[0] - a[0] for a, b in zip(hb2, hb2[1:])]
            check('resume_no_catchup_burst', all(0.85 < g < 1.2 for g in gaps),
                  'heartbeat gaps after resume: %s s' % ', '.join('%.2f' % g for g in gaps))
        rep['audio_players_after_resume'] = d.players_started()
        check('resume_restarts_audio', rep['audio_players_after_resume'] >= 1,
              'started players after resume: %s' % rep['audio_players_after_resume'])
        d.screenshot('5_resumed')
        check('process_alive_after_resume', d.pid() != '')

        # --- settings panel, integer scaling, safe areas ------------------------------------------------------------
        d.adb('shell', 'wm', 'size', 'reset')
        time.sleep(3)
        w, h = d.size()
        if h > w:
            w, h = h, w
        dens = int(re.search(r'(\d+)', d.adb('shell', 'wm', 'density')).group(1)) / 160.0
        base = d.screenshot('ui_0_normal')
        base_box = content_box(base)
        d.adb('shell', 'input', 'tap', str(w // 2), '40')  # any touch makes the gear button appear (this tap goes to the game)
        time.sleep(1)
        d.adb('shell', 'input', 'tap', str(int(w - 30 * dens - 18)), str(int(30 * dens + 6)))  # gear (top right)
        time.sleep(1.5)
        panel = d.screenshot('ui_1_panel')
        diff = sum(1 for x, y in ((px, py) for px in range(0, panel.width, 50) for py in range(0, panel.height, 50))
                   if sum(abs(a - b) for a, b in zip(panel.getpixel((x, y)), base.getpixel((x, y)))) > 60)
        check('gear opens the settings panel', diff > 40, '%d sampled pixels changed' % diff)
        d.adb('logcat', '-c')
        d.adb('shell', 'input', 'tap', str(int(w / 2 + 162 * dens)), str(int(h / 2 + 23.5 * dens)))  # "Integer scaling" switch
        time.sleep(1.5)
        sets = [m for _, m in d.logs() if 'settings' in m]
        check('integer scaling switch toggles', any('integer=true' in m for m in sets), sets[-1] if sets else 'no log')
        d.adb('shell', 'input', 'tap', str(int(w / 2 + 300 * dens)), str(int(h / 2 - 150 * dens)))  # outside the panel: close
        time.sleep(1.5)
        scaled = d.screenshot('ui_2_integer')
        box = content_box(scaled)
        if box and base_box:
            rep['integer_scaling'] = {'fit_height_px': base_box[3] - base_box[1], 'integer_height_px': box[3] - box[1]}
            expect = int(440 * int(((h) / 440))) if h >= 440 else None
            check('integer scaling uses a whole multiple', expect and abs((box[3] - box[1]) - expect) < 6,
                  'stage height %d px (screen %d px tall, whole multiple %s)' % (box[3] - box[1], h, expect))
        # settings survive a restart
        d.adb('shell', 'am', 'force-stop', PKG)
        d.adb('logcat', '-c')
        d.launch()
        time.sleep(8)
        sets = [m for _, m in d.logs() if 'settings' in m]
        check('settings persist across restarts', bool(sets) and 'integer=true' in sets[0], sets[0] if sets else 'no log')
        d.adb('shell', 'pm', 'clear', PKG)  # back to defaults for the remaining checks
        d.launch()
        time.sleep(6)
        # safe area: emulate a display cutout and make the stage nearly as wide as the screen
        if rep['api'] >= 28:  # display cutouts (and their emulation) exist from Android 9
          d.adb('shell', 'cmd', 'overlay', 'enable', 'com.android.internal.display.cutout.emulation.tall')
        d.adb('shell', 'wm', 'size', '1500x1080')
        d.adb('logcat', '-c')
        time.sleep(5)
        ins = [m for _, m in d.logs() if 'insets' in m]
        m_ins = None if rep['api'] < 28 else re.search(r'l=([\d.]+) t=([\d.]+) r=([\d.]+) b=([\d.]+) dpr=([\d.]+)', ins[-1]) if ins else None
        if m_ins:
            l, t, r, b, dpr = map(float, m_ins.groups())
            shot = d.screenshot('ui_3_cutout')
            sbox = content_box(shot)
            sw = shot.width
            need_l, need_r = l * dpr, r * dpr
            check('cutout: insets reported', max(l, t, r, b) > 0, ins[-1])
            need_t, need_b = t * dpr, b * dpr
            check('cutout: picture stays inside the safe area',
                  sbox and sbox[0] >= need_l - 3 and sbox[2] <= sw - need_r + 3 and sbox[1] >= need_t - 3 and sbox[3] <= shot.height - need_b + 3,
                  'content x %s..%s y %s..%s of %dx%d, inset px l=%.0f t=%.0f r=%.0f b=%.0f' % (
                      sbox[0] if sbox else None, sbox[2] if sbox else None, sbox[1] if sbox else None, sbox[3] if sbox else None,
                      sw, shot.height, need_l, need_t, need_r, need_b))
        elif rep['api'] >= 28:
            check('cutout: insets reported', False, 'no inset log')
        else:
            print('  (cutout checks skipped: no display cutouts before Android 9)')
        d.adb('shell', 'cmd', 'overlay', 'disable', 'com.android.internal.display.cutout.emulation.tall')
        d.adb('shell', 'wm', 'size', 'reset')
        time.sleep(2)

        # --- screen sizes / aspect ratios ---------------------------------------------------------------------------
        aspects = {}
        for label, (sw, sh) in {'20:9': (2400, 1080), '16:9': (1920, 1080), '4:3': (1600, 1200), '5:4': (1280, 1024),
                                '21:9': (2520, 1080), '1:1': (1200, 1200), 'portrait 9:20': (1080, 2400)}.items():
            d.adb('shell', 'wm', 'size', '%dx%d' % (sw, sh))
            time.sleep(4)
            img = d.screenshot('size_%dx%d' % (sw, sh))
            box = content_box(img)
            if not box:
                aspects[label] = {'pass': False, 'detail': 'blank screen'}
                continue
            W, H = img.size
            bw, bh = box[2] - box[0], box[3] - box[1]
            asp = bw / bh
            cx, cy = (box[0] + box[2]) / 2 / W, (box[1] + box[3]) / 2 / H
            ok = abs(asp - STAGE_W / STAGE_H) < 0.06 and abs(cx - .5) < 0.03 and abs(cy - .5) < 0.03 and box[0] >= 0 and box[2] < W
            aspects[label] = {'pass': ok, 'screen': '%dx%d' % (W, H), 'content_aspect': round(asp, 3),
                              'centre': [round(cx, 3), round(cy, 3)]}
            print('    %-14s %dx%d content aspect %.3f centre (%.3f, %.3f) %s' % (label, W, H, asp, cx, cy, 'PASS' if ok else 'FAIL'))
        d.adb('shell', 'wm', 'size', 'reset')
        rep['aspect_ratios'] = aspects
        check('aspect_ratios_fit_and_centre', all(v['pass'] for v in aspects.values()),
              ', '.join(k for k, v in aspects.items() if not v['pass']) or 'all')
    finally:
        try:
            d.stop()
        except Exception:
            pass
    json.dump(rep, open(os.path.join(OUT, avd + '.json'), 'w'), indent=1)
    return rep


if __name__ == '__main__':
    names = sys.argv[1:] or ['rightmix24']
    port = 5560
    for n in names:
        run(n, port)
        port += 2
