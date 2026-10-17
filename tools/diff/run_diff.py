#!/usr/bin/env python
"""run_diff.py - differential test: instrumented ORIGINAL SWF (in Ruffle) vs the Dart port.

  python tools/diff/run_diff.py [scenarios.json] [--skip-dart] [--skip-orig]

For every scenario:
  1. make_probe.py builds the original SWF with a deterministic RNG, scripted inputs and a per-frame state trace
  2. Ruffle runs it; the trace() output is captured from stdout           -> build/diff/orig_<name>.txt
  3. `flutter test test/differential_dump_test.dart` replays the same scenario in the Dart port
                                                                          -> build/diff/dart_<name>.txt
  4. the traces are compared field by field and a report is written       -> docs/verification/differential_report.md

A "match" means every traced field is equal on every frame; the report lists the first divergence per field and the
number of differing frames, so partial agreement stays visible.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
FPS = os.environ.get('DIFF_FPS', '60')
RUFFLE = os.path.join(ROOT, 'tools', 'ruffle', 'ruffle.exe')
OUT = os.path.join(ROOT, 'build', 'diff')
ANSI = re.compile(r'\x1b\[[0-9;]*m')
TRACE = re.compile(r'avm_trace: (.*)$')
FIELD = re.compile(r'(\w+)=(\[[^\]]*\]|\S+)')


def park_window(pid, tries=60):
    """Move the Ruffle window of process `pid` onto the left-most monitor (Windows only; best effort)."""
    try:
        import ctypes
        from ctypes import wintypes
        u = ctypes.windll.user32
        mons = []
        P = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HMONITOR, wintypes.HDC, ctypes.POINTER(wintypes.RECT), wintypes.LPARAM)
        u.EnumDisplayMonitors(0, 0, P(lambda h, dc, r, d: mons.append((r.contents.left, r.contents.top)) or 1), 0)
        left = min(mons)
        found = []
        W = ctypes.WINFUNCTYPE(ctypes.c_int, wintypes.HWND, wintypes.LPARAM)

        def each(hwnd, _):
            p = wintypes.DWORD()
            u.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
            if p.value == pid and u.IsWindowVisible(hwnd):
                found.append(hwnd)
            return 1

        for _ in range(tries):
            u.EnumWindows(W(each), 0)
            if found:
                # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
                u.SetWindowPos(found[0], 0, left[0] + 20, left[1] + 20, 0, 0, 0x0001 | 0x0004 | 0x0010)
                return
            time.sleep(0.1)
    except Exception:
        pass


def run_original(name, swf, frames, timeout=120):
    # muted, shown without taking focus, and moved to the left-hand monitor (never the main one)
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 4  # SW_SHOWNOACTIVE
    proc = subprocess.Popen([RUFFLE, '--volume', '0', swf], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, startupinfo=si,
                            env=dict(os.environ, RUST_LOG='info'), text=True, encoding='utf-8', errors='replace')
    lines, deadline = [], time.time() + timeout
    threading.Thread(target=park_window, args=(proc.pid,), daemon=True).start()
    try:
        for raw in proc.stdout:
            m = TRACE.search(ANSI.sub('', raw).rstrip())
            if m:
                t = m.group(1)
                if re.match(r'F\d+ ', t):
                    lines.append(t)
                if t == 'PROBE_DONE' or time.time() > deadline:
                    break
    finally:
        proc.kill()
        proc.wait()
    # the probe prints a few frames after PROBE_DONE conditions; keep exactly the requested number
    lines = lines[:frames]
    with open(os.path.join(OUT, 'orig_%s.txt' % name), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    return lines


def parse(line):
    head, _, rest = line.partition(' ')
    state, _, rest = rest.partition(' ')
    d = {'state': state}
    d.update({k: v for k, v in FIELD.findall(rest)})
    return int(head[1:]), d


def compare(a_lines, b_lines):
    n = min(len(a_lines), len(b_lines))
    first, count = {}, {}
    frames_bad = 0
    for i in range(n):
        fa, a = parse(a_lines[i])
        fb, b = parse(b_lines[i])
        bad = False
        for k in a:
            if a.get(k) != b.get(k):
                bad = True
                count[k] = count.get(k, 0) + 1
                first.setdefault(k, (fa, a.get(k), b.get(k)))
        frames_bad += bad
    return {'frames': n, 'len_orig': len(a_lines), 'len_dart': len(b_lines), 'bad_frames': frames_bad,
            'first': first, 'count': count}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    scen_path = args[0] if args else os.path.join(HERE, 'scenarios.json')
    scen = json.load(open(scen_path, encoding='utf-8'))['scenarios']
    os.makedirs(OUT, exist_ok=True)

    if '--skip-orig' not in sys.argv:
        from concurrent.futures import ThreadPoolExecutor

        def job(sc):
            done = os.path.join(OUT, 'orig_%s.txt' % sc['name'])
            keyf = os.path.join(OUT, 'orig_%s.key' % sc['name'])
            key = hashlib.sha256(json.dumps([sc['seed'], sc['frames'], sc['ops']], sort_keys=True).encode()).hexdigest()
            if ('--resume' in sys.argv and os.path.exists(done) and os.path.exists(keyf)
                    and open(keyf).read() == key and len(open(done).read().splitlines()) == sc['frames']):
                return sc['name'], sc['frames']
            subprocess.check_call([sys.executable, os.path.join(HERE, 'make_probe.py'), scen_path,
                                   os.path.join(ROOT, 'build', 'probes'), '--fps', FPS, '--only', sc['name']],
                                  stdout=subprocess.DEVNULL)
            swf = os.path.join(ROOT, 'build', 'probes', sc['name'] + '.swf')
            n = len(run_original(sc['name'], swf, sc['frames']))
            open(keyf, 'w').write(key)
            return sc['name'], n

        with ThreadPoolExecutor(int(os.environ.get('DIFF_JOBS', '4'))) as pool:
            for name, n in pool.map(job, scen):
                print('original %-34s %d frames traced' % (name, n))
    if '--skip-dart' not in sys.argv:
        env = dict(os.environ, DIFF_SCENARIOS=os.path.relpath(scen_path, os.path.join(ROOT, 'port')),
                   PATH=os.path.join(ROOT, 'tools', 'flutter', 'bin') + os.pathsep + os.environ['PATH'])
        subprocess.check_call(['flutter', 'test', 'test/differential_dump_test.dart'], cwd=os.path.join(ROOT, 'port'),
                              env=env, shell=True)

    results = {}
    for sc in scen:
        a = open(os.path.join(OUT, 'orig_%s.txt' % sc['name']), encoding='utf-8').read().splitlines()
        b = open(os.path.join(OUT, 'dart_%s.txt' % sc['name']), encoding='utf-8').read().splitlines()
        res = compare(a, b)
        res['original_reruns'] = 0
        # A match cannot be a false positive, but a mismatch can be: the real mouse pointer or window events can reach
        # the Ruffle window and fire rollOver/rollOut in the original. Re-run the original until two consecutive runs
        # agree before reporting a divergence.
        if (res['bad_frames'] or res['len_orig'] != res['len_dart']) and '--skip-orig' not in sys.argv:
            swf = os.path.join(ROOT, 'build', 'probes', sc['name'] + '.swf')
            for _ in range(4):
                again = run_original(sc['name'], swf, sc['frames'])
                res['original_reruns'] += 1
                stable = again == a
                a = again
                if stable:
                    break
            res = dict(compare(a, b), original_reruns=res['original_reruns'], original_stable=stable)
        results[sc['name']] = res
    json.dump(results, open(os.path.join(OUT, 'result.json'), 'w'), indent=1)
    for name, r in results.items():
        status = 'MATCH' if r['bad_frames'] == 0 and r['len_orig'] == r['len_dart'] else 'DIVERGES'
        print('%-30s %-8s frames=%d differing=%d  fields=%s' % (name, status, r['frames'], r['bad_frames'], dict(r['count'])))
    return 0 if all(r['bad_frames'] == 0 and r['len_orig'] == r['len_dart'] for r in results.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
