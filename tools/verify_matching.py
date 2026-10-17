#!/usr/bin/env python
"""verify_matching.py - independent audit of the source-level matching claim.

For every script unit in the SWF it checks, from three independent inputs:
  1. the ORIGINAL bytecode, parsed straight out of bartender.swf (not from decomp/),
  2. the bytecode compiled from src/as2 by tools/as2c in a sandbox tree that contains neither decomp/ nor the SWF,
  3. mutation tests: a changed source line must change the compiled bytes (proves the sources drive the output).

It also classifies every unit (game class / game timeline script / mx framework / component stub) and writes
docs/verification/matching_audit.{json,md}.
"""
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, os.path.join(HERE, 'swfproj'))
sys.path.insert(0, os.path.join(HERE, 'as2c'))
import as2asm  # noqa: E402
import swfio  # noqa: E402
import swfproj  # noqa: E402

GAME_SPRITES_FRAMEWORK = {13, 14, 15, 19, 23, 25, 26}   # component-library timelines (UIObject, Border, ...)


def sha(b):
    return hashlib.sha256(b).hexdigest()


# --- 1. original bytecode, straight from the SWF --------------------------------------------------
def original_units(swf_path):
    """[(tag path description, bytes)] for every script in tag order (same order as decomp/swf.json)."""
    swf = swfio.Swf.load(swf_path)
    out = []

    def walk(tags, ctx):
        for t in tags:
            if t.code == 39:
                walk(t.children, ctx + [('sprite', t.sprite_id)])
            elif t.code == 12:
                out.append((ctx, 'DoAction', t.payload))
            elif t.code == 59:
                out.append((ctx, 'DoInitAction', t.payload[2:]))
            elif t.code == 26 and t.payload[0] & 0x80:
                head, events = swfproj.split_place_object2(t.payload, swf.version)
                for ev, key, body in events:
                    out.append((ctx, 'ClipEvent', body))
            elif t.code == 34:
                sp = swfproj.split_define_button2(t.payload)
                if sp:
                    for cflags, body in sp[1]:
                        out.append((ctx, 'ButtonCond', body))

    walk(swf.tags, [])
    return out


def asm_refs(decomp):
    """asm file stems in the same traversal order, from decomp/swf.json (names only; no bytes are used)."""
    doc = json.load(open(os.path.join(decomp, 'swf.json'), encoding='utf-8'))
    refs = []

    def walk(ents):
        for e in ents:
            if e['t'] == 39:
                walk(e['tags'])
            for k in ('asm',):
                if k in e:
                    refs.append(os.path.basename(e[k])[:-len('.as2asm')])
            for sub in ('events', 'conds'):
                for x in e.get(sub, []):
                    refs.append(os.path.basename(x['asm'])[:-len('.as2asm')])

    walk(doc['tags'])
    return refs


def classify(stem, ctx):
    if stem.startswith('init_class_mx.'):
        return 'mx framework class'
    if stem.startswith('init_class_'):
        return 'game class'
    if stem.startswith('init_'):
        return 'mx component registration stub'
    sprite_ids = [c[1] for c in ctx if c[0] == 'sprite']
    if sprite_ids and sprite_ids[0] in GAME_SPRITES_FRAMEWORK:
        return 'mx component timeline stub (stop())'
    if stem.startswith('button18'):
        return 'mx component button action (TextInput Tab key)'
    return 'game timeline / button / clip-event script'


# --- 2. compile in a sandbox that has no decomp/ and no SWF --------------------------------------
SANDBOX_DRIVER = r'''
import json, os, sys
sys.path.insert(0, os.path.join(%(root)r, "tools", "as2c"))
sys.path.insert(0, os.path.join(%(root)r, "tools", "swfproj"))
import compiler, as2asm
SRC = os.path.join(%(root)r, "src", "as2")
hints = json.load(open(os.path.join(SRC, "hints.json"), encoding="utf-8"))
names = json.load(open(os.path.join(SRC, "names.json"), encoding="utf-8"))
def H(key):
    return [compiler.Hint(h["kind"], h.get("regs"), h.get("flags"), [(r, n) for r, n in h["params"]]) for h in hints.get(key, [])]
only = sys.argv[2] if len(sys.argv) > 2 else None
out = {}
for dp, dn, fn in os.walk(SRC):
    for f in fn:
        if not f.endswith(".as"):
            continue
        p = os.path.join(dp, f)
        rel = os.path.relpath(p, SRC).replace(os.sep, "/")
        if rel.startswith("scripts/"):
            key = rel[len("scripts/"):-3]; stem = key
        else:
            key = rel[:-3].replace("/", "."); stem = "init_class_" + key
        if only and rel != only:
            continue
        text = compiler.compile_to_asm(open(p, encoding="utf-8").read(), H(key), names.get(key, {}))
        out[stem] = as2asm.assemble(text).hex()
json.dump(out, open(sys.argv[1], "w"))
'''


def make_sandbox():
    tmp = tempfile.mkdtemp(prefix='rightmix_sandbox_')
    for rel in ('tools/as2c', 'tools/swfproj'):
        shutil.copytree(os.path.join(ROOT, rel), os.path.join(tmp, rel),
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    # RIGHTMIX_AS2_SRC: audit a different source directory (e.g. the complete 82-unit set kept privately)
    src = os.environ.get('RIGHTMIX_AS2_SRC') or os.path.join(ROOT, 'src', 'as2')
    shutil.copytree(src, os.path.join(tmp, 'src', 'as2'), ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    return tmp


def compile_in_sandbox(sandbox, only=None):
    drv = os.path.join(sandbox, 'driver.py')
    open(drv, 'w').write(SANDBOX_DRIVER % {'root': sandbox})
    outp = os.path.join(sandbox, 'out.json')
    assert not os.path.exists(os.path.join(sandbox, 'decomp')) and not os.path.exists(os.path.join(sandbox, 'bartender.swf'))
    subprocess.check_call([sys.executable, drv, outp] + ([only] if only else []))
    return {k: bytes.fromhex(v) for k, v in json.load(open(outp)).items()}


# --- 3. mutation tests ----------------------------------------------------------------------------
def mutate(text, rnd):
    """Change one numeric literal (or one string literal) in a source text; returns (new_text, description)."""
    code_lines = [(i, l) for i, l in enumerate(text.split('\n')) if re.search(r'\b\d+\b', l) and not l.strip().startswith(('//', '*', '/*'))]
    rnd.shuffle(code_lines)
    lines = text.split('\n')
    for i, l in code_lines:
        m = list(re.finditer(r'(?<![\w.])(\d+)(?![\w.])', l))
        if not m:
            continue
        mm = rnd.choice(m)
        new = str(int(mm.group(1)) + 7)
        lines[i] = l[:mm.start()] + new + l[mm.end():]
        return '\n'.join(lines), 'line %d: %s -> %s' % (i + 1, mm.group(1), new)
    return None, None


def mutation_tests(sandbox, originals, seed=1):
    """Mutate EVERY source file that has a numeric literal (two different mutations each) and require the
    compiled bytes of that unit to change."""
    rnd = random.Random(seed)
    src_root = os.path.join(sandbox, 'src', 'as2')
    files = []
    for dp, dn, fn in os.walk(src_root):
        for f in fn:
            if f.endswith('.as'):
                files.append(os.path.join(dp, f))
    files.sort()
    results = []
    for p in files:
        rel = os.path.relpath(p, src_root).replace(os.sep, '/')
        orig_text = open(p, encoding='utf-8').read()
        base = compile_in_sandbox(sandbox, rel)
        for _ in range(2):
            new_text, desc = mutate(orig_text, rnd)
            if new_text is None:
                break
            try:
                open(p, 'w', encoding='utf-8').write(new_text)
                muted = compile_in_sandbox(sandbox, rel)
                changed = [k for k in base if base[k] != muted.get(k)]
                results.append((rel, desc, 'bytes changed' if changed else 'NO CHANGE', bool(changed)))
            except subprocess.CalledProcessError:
                results.append((rel, desc, 'compile error after mutation', True))
            finally:
                open(p, 'w', encoding='utf-8').write(orig_text)
    return results


def main():
    swf_path = os.environ.get('RIGHTMIX_SWF') or os.path.join(ROOT, 'bartender.swf')
    decomp = os.path.join(ROOT, 'decomp')
    originals = original_units(swf_path)
    refs = asm_refs(decomp)
    assert len(originals) == len(refs), (len(originals), len(refs))
    sandbox = make_sandbox()
    try:
        compiled = compile_in_sandbox(sandbox)
        rows = []
        for (ctx, kind, orig_bytes), stem in zip(originals, refs):
            key = stem
            got = compiled.get(key)
            rows.append({'unit': stem, 'kind': kind, 'category': classify(stem, ctx), 'bytes': len(orig_bytes),
                         'original_sha256': sha(orig_bytes), 'compiled_sha256': sha(got) if got is not None else None,
                         'has_source': got is not None, 'match': got == orig_bytes})
        extra = sorted(set(compiled) - set(refs))
        mut = mutation_tests(sandbox, originals)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    cats = {}
    for r in rows:
        c = cats.setdefault(r['category'], {'units': 0, 'bytes': 0, 'matched_units': 0, 'matched_bytes': 0})
        c['units'] += 1
        c['bytes'] += r['bytes']
        if r['match']:
            c['matched_units'] += 1
            c['matched_bytes'] += r['bytes']
    total = {'units': len(rows), 'bytes': sum(r['bytes'] for r in rows), 'matched_units': sum(r['match'] for r in rows),
             'matched_bytes': sum(r['bytes'] for r in rows if r['match'])}
    report = {'categories': cats, 'total': total, 'sources_without_unit': extra,
              'mutation_tests': [{'file': a, 'mutation': b, 'result': c, 'detected': d} for a, b, c, d in mut], 'units': rows}
    out_dir = os.environ.get('RIGHTMIX_AUDIT_OUT') or os.path.join(ROOT, 'build', 'verification')
    os.makedirs(out_dir, exist_ok=True)
    json.dump(report, open(os.path.join(out_dir, 'matching_audit.json'), 'w'), indent=1)

    md = ['# Matching audit (generated by tools/verify_matching.py)', '',
          'Original bytecode is parsed from `bartender.swf`; sources are compiled in a sandbox with **no `decomp/` and no SWF**.', '',
          '| Category | Units | Bytecode bytes | Matched units | Matched bytes |', '|---|---:|---:|---:|---:|']
    for c, v in sorted(cats.items()):
        md.append('| %s | %d | %d | %d | %d |' % (c, v['units'], v['bytes'], v['matched_units'], v['matched_bytes']))
    md.append('| **total** | %(units)d | %(bytes)d | %(matched_units)d | %(matched_bytes)d |' % total)
    md.append('')
    md.append('Units shown as "no source" are stock Macromedia component units (`mx` categories); when the SWF is rebuilt they keep the bytecode of the supplied file and are not compared here.')
    md += ['', 'Sources that map to no SWF unit: %s' % (extra or 'none'), '', '## Mutation tests (a changed source must change the output)', '',
           '| Source | Mutation | Result |', '|---|---|---|']
    for a, b, c, d in mut:
        md.append('| %s | %s | %s |' % (a, b, ('OK: ' if d else 'FAIL: ') + c))
    md += ['', '## Units', '', '| Unit | Category | Bytes | Match |', '|---|---|---:|---|']
    for r in rows:
        md.append('| %s | %s | %d | %s |' % (r['unit'], r['category'], r['bytes'], 'yes' if r['match'] else ('NO' if r['has_source'] else 'no source')))
    open(os.path.join(out_dir, 'matching_audit.md'), 'w', encoding='utf-8').write('\n'.join(md) + '\n')
    print('report written to', out_dir)

    # Units without a source are acceptable only if they are stock Macromedia component units; those keep the bytecode of
    # YOUR file when the SWF is rebuilt, so they are not independently checked here.
    game_without_source = [r['unit'] for r in rows if not r['has_source'] and not r['category'].startswith('mx')]
    with_source = [r for r in rows if r['has_source']]
    ok = (not game_without_source and all(r['match'] for r in with_source) and all(m[3] for m in mut))
    print('units in the file: %d (%d bytes); compiled from source here: %d, matched: %d (%d bytes)' % (
        total['units'], total['bytes'], len(with_source), sum(r['match'] for r in with_source), sum(r['bytes'] for r in with_source if r['match'])))
    no_src = [r for r in rows if not r['has_source']]
    print('not reconstructed in this checkout (taken from your file when rebuilding): %d units, %d bytes' % (
        len(no_src), sum(r['bytes'] for r in no_src)))
    if game_without_source:
        print('GAME-SPECIFIC UNITS WITHOUT SOURCE:', game_without_source)
    for c, v in sorted(cats.items()):
        print('  %-50s %3d units %7d bytes  matched %3d' % (c, v['units'], v['bytes'], v['matched_units']))
    print('mutation tests: %d run, %d detected' % (len(mut), sum(1 for m in mut if m[3])))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
