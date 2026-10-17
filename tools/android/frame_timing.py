#!/usr/bin/env python
"""frame_timing.py - raster/total frame time of the end-card curtain on an Android emulator, with and without the cache.

  python tools/android/frame_timing.py <avd> [apk ...]

Needs APKs built with --dart-define=TRACE=true --dart-define=FRAMELOG=true --dart-define=AUTOPLAY=end (and NOCACHE=true for
the comparison build); see build/android/ft_*.apk. The app jumps to a finale and the end card by itself and prints one
`RM ft ...` line per frame. Reports the curtain frames (end-card frames 5..19).
"""
import re
import statistics
import sys
import time

sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import verify_device as v  # noqa: E402


def run(d, apk, label, wait=26):
    d.adb('shell', 'am', 'force-stop', v.PKG)
    d.adb('install', '-r', apk, timeout=240)
    d.adb('shell', 'pm', 'clear', v.PKG)
    d.adb('logcat', '-c')
    d.launch()
    time.sleep(wait)
    raw = d.adb('logcat', '-d', '-v', 'time', 'flutter:I', '*:S', timeout=180)
    frames = []
    for ln in raw.splitlines():
        m = re.search(r'RM ft raster=([\d.]+) total=([\d.]+) (.*)$', ln)
        if m:
            frames.append((float(m.group(1)), float(m.group(2)), m.group(3)))
    curtain = [f for f in frames if (m := re.search(r'endCard=(\d+) visible=true', f[2])) and 5 <= int(m.group(1)) <= 19]
    scene = [f for f in frames if 'finale=' in f[2] and 'finale=null' not in f[2] and 'visible=false' in f[2]]

    def fmt(rs):
        if not rs:
            return 'no frames'
        ra = sorted(x[0] for x in rs)
        to = sorted(x[1] for x in rs)
        return 'n=%3d raster mean %5.1f p95 %5.1f max %5.1f | total mean %5.1f max %5.1f | >16.7ms %d' % (
            len(rs), statistics.mean(ra), ra[int(len(ra) * .95)], ra[-1], statistics.mean(to), to[-1], sum(1 for x in rs if x[1] > 16.7))

    print('%-34s finale scene: %s' % (label, fmt(scene)))
    print('%-34s curtain     : %s' % ('', fmt(curtain)))
    print('%-34s all frames  : %s' % ('', fmt(frames)))


if __name__ == '__main__':
    avd = sys.argv[1]
    apks = sys.argv[2:] or ['build/android/ft_nocache.apk', 'build/android/ft_cache.apk']
    d = v.Dev(avd, 5590)
    d.start()
    try:
        for apk in apks:
            run(d, apk, apk.split('/')[-1])
        w, h = d.size()
        print('display %dx%d' % (w, h))
    finally:
        d.stop()
