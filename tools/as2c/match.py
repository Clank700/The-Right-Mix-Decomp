"""match.py <ClassOrScript> [--full]: compile decomp/src/<name>.as and compare with the original bytecode."""
import difflib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'swfproj'))

import as2asm  # noqa: E402
import compiler  # noqa: E402

ROOT = os.path.join(HERE, '..', '..')
HDR2 = re.compile(r'^\s*DefineFunction2 "([^"]*)" regs=(\d+) flags=(0x[0-9a-f]+) \[(.*?)\] \{$')
HDR1 = re.compile(r'^\s*DefineFunction "([^"]*)" \[(.*?)\] \{$')


def read_hints(asm_text):
    hints = []
    for line in asm_text.splitlines():
        m = HDR2.match(line)
        if m:
            params = [(int(r), n) for r, n in re.findall(r'(\d+):"([^"]+)"', m.group(4))]
            hints.append(compiler.Hint('F2', int(m.group(2)), int(m.group(3), 16), params))
            continue
        m = HDR1.match(line)
        if m:
            hints.append(compiler.Hint('F1', None, None, [(0, n) for n in re.findall(r'"([^"]+)"', m.group(2))]))
    return hints


def canonical(text):
    """Assemble and disassemble again so labels / comments are normalised."""
    return as2asm.disassemble(as2asm.assemble(text))


def norm_labels(lines):
    """Rename byte-offset labels (L0a0b) to sequential names so diffs show only real instruction changes."""
    names = {}

    def rn(m):
        return names.setdefault(m.group(0), 'L%d' % (len(names) + 1))
    return [re.sub(r'L[0-9a-f]{3,}', rn, l) for l in lines]


def asm_path(name):
    for pat in ('init_class_%s.as2asm', '%s.as2asm'):
        p = os.path.join(ROOT, 'decomp', 'asm', pat % name)
        if os.path.exists(p):
            return p
    raise SystemExit('no asm for ' + name)


CLEAN = False   # use the readable sources in src/as2 (with names.json)


def clean_root():
    return os.path.join(ROOT, 'src', 'as2')


def load_names(name):
    p = os.path.join(clean_root(), 'names.json')
    if CLEAN and os.path.exists(p):
        return json.load(open(p, encoding='utf-8')).get(name, {})
    return {}


def src_path(name):
    if CLEAN:
        scripted = os.path.join(clean_root(), 'scripts', name + '.as')
        if os.path.exists(scripted):
            return scripted
        return os.path.join(clean_root(), name.replace('.', '/') + '.as')
    scripted = os.path.join(ROOT, 'decomp', 'src', 'scripts', name + '.as')
    if os.path.exists(scripted):
        return scripted
    return os.path.join(ROOT, 'decomp', 'src', name.replace('.', '/') + '.as')


def run(name, show=True, context=6, limit=60):
    orig_text = open(asm_path(name), encoding='utf-8').read()
    orig = as2asm.assemble(orig_text)
    hints = read_hints(orig_text)
    src = open(src_path(name), encoding='utf-8').read()
    try:
        out = compiler.compile_to_asm(src, hints, load_names(name))
        mine = as2asm.assemble(out)
    except Exception as e:  # noqa: BLE001
        print(name, 'COMPILE ERROR:', type(e).__name__, e)
        return False
    ok = mine == orig
    print('%-40s %s  (%d vs %d bytes)' % (name, 'MATCH' if ok else 'DIFF', len(mine), len(orig)))
    if not ok and show:
        a = norm_labels(as2asm.disassemble(orig).splitlines())
        b = norm_labels(as2asm.disassemble(mine).splitlines())
        sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
        shown = 0
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == 'equal':
                continue
            print('--- original lines %d-%d / mine %d-%d' % (i1 + 1, i2, j1 + 1, j2))
            for l in a[max(0, i1 - 3):i1]:
                print('   ', l[:110])
            for l in a[i1:i2][:12]:
                print('  -', l[:110])
            for l in b[j1:j2][:12]:
                print('  +', l[:110])
            shown += 1
            if shown >= int(os.environ.get('MATCH_HUNKS', '3')):
                break
    return ok


if __name__ == '__main__':
    names = sys.argv[1:] or ['Shaker']
    for n in names:
        run(n)
