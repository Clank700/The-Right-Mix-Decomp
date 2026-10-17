#!/usr/bin/env python
"""build.py - rebuild the SWF from the project and verify it.

Inputs (nothing here reads bartender.swf):
  src/as2/            readable AS2 source + hints.json (register data) + names.json
  decomp/             lossless project: every non-script tag (graphics, sounds, fonts, placement...) as raw payload
Scripts with a source in src/as2 (the 40 game-specific units) are compiled by tools/as2c and replace the .as2asm files; every
other script (the 42 stock Macromedia component units) keeps the bytecode taken from your own file; then the whole SWF is
reassembled. RIGHTMIX_AS2_SRC=<dir> points at a different source directory (e.g. a complete 82-unit set kept privately).

Verification: the result is compared with the recorded hashes of the original (reference/original.json). If
bartender.swf is present it is additionally parsed and compared directly.

  python tools/build.py            writes build/bartender_rebuilt.swf (uncompressed) and .cws.swf
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, os.path.join(HERE, 'as2c'))
sys.path.insert(0, os.path.join(HERE, 'swfproj'))

import compiler  # noqa: E402
import swfio  # noqa: E402
import swfproj  # noqa: E402

SRC = os.environ.get('RIGHTMIX_AS2_SRC') or os.path.join(ROOT, 'src', 'as2')
DECOMP = os.path.join(ROOT, 'decomp')
HINTS_SCHEMA = 1


def load_json(name):
    with open(os.path.join(SRC, name), encoding='utf-8') as f:
        return json.load(f)


def hints_content_hash(table):
    body = {k: v for k, v in table.items() if not k.startswith('_')}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def load_hints():
    table = load_json('hints.json')
    meta = table.get('_meta', {})
    if meta.get('schema_version') != HINTS_SCHEMA:
        raise SystemExit('hints.json: unsupported schema version %r' % meta.get('schema_version'))
    if meta.get('content_sha256') != hints_content_hash(table):
        raise SystemExit('hints.json was modified (content hash mismatch); regenerate it with tools/as2c/gen_hints.py')
    return table


def hints_for(table, name):
    return [compiler.Hint(h['kind'], h.get('regs'), h.get('flags'), [(r, n) for r, n in h['params']])
            for h in table.get(name, [])]


def source_for(asm_name):
    """asm file stem -> (source path, key used in hints/names) or None."""
    if asm_name.startswith('init_class_'):
        cls = asm_name[len('init_class_'):]
        p = os.path.join(SRC, cls.replace('.', '/') + '.as')
        return (p, cls) if os.path.exists(p) else None
    p = os.path.join(SRC, 'scripts', asm_name + '.as')
    return (p, asm_name) if os.path.exists(p) else None


def compile_sources(workdir, verbose=True):
    hints, names = load_hints(), load_json('names.json')
    compiled = 0
    for fn in sorted(os.listdir(os.path.join(workdir, 'asm'))):
        stem = fn[:-len('.as2asm')]
        found = source_for(stem)
        if not found:
            continue
        path, key = found
        with open(path, encoding='utf-8') as f:
            text = compiler.compile_to_asm(f.read(), hints_for(hints, key), names.get(key, {}))
        with open(os.path.join(workdir, 'asm', fn), 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        compiled += 1
    if verbose:
        print('compiled %d scripts from AS2 source' % compiled)
    return compiled


def main():
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='rightmix_')
    try:
        shutil.copytree(DECOMP, os.path.join(tmp, 'p'), ignore=shutil.ignore_patterns('ffdec_as', 'src', 'ORIGINAL.json'))
        proj = os.path.join(tmp, 'p')
        compile_sources(proj)
        swf = swfproj.build_swf(proj)
        fws = swf.to_fws()
        digest = hashlib.sha256(fws).hexdigest()
        expected = json.load(open(os.path.join(ROOT, 'reference', 'original.json'), encoding='utf-8'))
        ok = digest == expected['decompressed_payload_sha256'] and len(fws) == expected['decompressed_payload_bytes']
        print('rebuilt  (decompressed) sha256', digest, len(fws), 'bytes')
        print('recorded original       sha256', expected['decompressed_payload_sha256'], expected['decompressed_payload_bytes'], 'bytes')
        direct = os.environ.get('RIGHTMIX_SWF') or os.path.join(ROOT, 'bartender.swf')
        if os.path.exists(direct):
            ref = swfio.Swf.load(direct).to_fws()
            print('bartender.swf present: direct comparison identical:', fws == ref)
            ok = ok and fws == ref
        else:
            print('bartender.swf not present: verified against recorded hash only')
        print('BYTE-IDENTICAL TO THE ORIGINAL (uncompressed SWF):', ok)
        with open(os.path.join(ROOT, 'build', 'bartender_rebuilt.swf'), 'wb') as f:
            f.write(fws)
        with open(os.path.join(ROOT, 'build', 'bartender_rebuilt.cws.swf'), 'wb') as f:
            f.write(swf.to_cws())
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
