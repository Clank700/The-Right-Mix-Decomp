"""Freeze the DefineFunction2 / DefineFunction headers of the original scripts into src/as2/hints.json.

The compiler needs, per function (in compile order): the register count, preload flags and the register given to
each parameter. These are decisions of the original compiler's register allocator, recorded here as data.
The file carries a schema version and a content hash (`_meta`); tools/build.py refuses to build when the hash does
not match, so hand edits are noticed. Regenerating this file is the only step that reads the original's assembly.
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import match  # noqa: E402

ROOT = match.ROOT
SRC = os.path.join(ROOT, 'src', 'as2')
SCHEMA = 1


def content_hash(table):
    body = {k: v for k, v in table.items() if not k.startswith('_')}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
    table = {}
    asm_dir = os.path.join(ROOT, 'decomp', 'asm')
    for fn in sorted(os.listdir(asm_dir)):
        stem = fn[:-len('.as2asm')]
        key = stem[len('init_class_'):] if stem.startswith('init_class_') else stem
        text = open(os.path.join(asm_dir, fn), encoding='utf-8').read()
        hints = match.read_hints(text)
        if hints:
            table[key] = [{'kind': h.kind, 'regs': h.regs, 'flags': h.flags, 'params': [[r, n] for r, n in h.params]}
                          for h in hints]
    out = {'_meta': {'schema_version': SCHEMA,
                     'generator': 'tools/as2c/gen_hints.py',
                     'source': 'DefineFunction / DefineFunction2 headers of the original SWF scripts',
                     'scripts': len(table),
                     'functions': sum(len(v) for v in table.values()),
                     'content_sha256': content_hash(table)}}
    out.update(table)
    os.makedirs(SRC, exist_ok=True)
    with open(os.path.join(SRC, 'hints.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(out, f, indent=1)
    print('hints for', len(table), 'scripts, sha256', out['_meta']['content_sha256'][:16])


if __name__ == '__main__':
    main()
