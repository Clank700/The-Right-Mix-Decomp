"""Study how the original compiler allocated registers in DefineFunction2 parameters."""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'swfproj'))

PAT = re.compile(r'^(\s*)DefineFunction2 "([^"]*)" regs=(\d+) flags=(0x[0-9a-f]+) \[(.*?)\] \{$')
rows = []
for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), '..', '..', 'decomp', 'asm', 'init_class_*.as2asm'))):
    lines = open(f, encoding='utf-8').read().splitlines()
    i = 0
    while i < len(lines):
        m = PAT.match(lines[i])
        if not m:
            i += 1
            continue
        indent = m.group(1)
        # collect body until matching close brace at same indent
        j = i + 1
        body = []
        while not (lines[j].startswith(indent + '}') and len(lines[j]) - len(lines[j].lstrip()) == len(indent)):
            body.append(lines[j])
            j += 1
        params = re.findall(r'(\d+):"([^"]+)"', m.group(5))
        text = '\n'.join(body)
        regs_used = [int(x) for x in re.findall(r'\br:(\d+)', text)]
        regs_used += [int(x) for x in re.findall(r'StoreRegister (\d+)', text)]
        first = {}
        count = {}
        for order, r in enumerate(re.findall(r'(?:\br:|StoreRegister )(\d+)', text)):
            r = int(r)
            first.setdefault(r, order)
            count[r] = count.get(r, 0) + 1
        rows.append((os.path.basename(f), m.group(2), int(m.group(3)), m.group(4), params, first, count))
        i += 1

for fn, name, nregs, flags, params, first, count in rows:
    if len(params) < 2:
        continue
    ps = [(int(r), n, first.get(int(r)), count.get(int(r), 0)) for r, n in params]
    byreg = sorted(ps)
    by_first = sorted(ps, key=lambda p: (p[2] if p[2] is not None else 1e9))
    consistent_first = [p[0] for p in by_first] == sorted(p[0] for p in by_first)
    print('%-28s regs=%d flags=%s  decl order -> %s | first-use order matches reg order: %s' % (
        fn.replace('init_class_', '').replace('.as2asm', ''), nregs, flags,
        ' '.join('%s=r%d(first#%s,n=%d)' % (n.replace('par_', ''), r, f, c) for r, n, f, c in ps), consistent_first))
