"""report.py: how much of the SWF's ActionScript compiles from readable AS2 source to the identical bytes."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'swfproj'))
import as2asm  # noqa: E402
import match  # noqa: E402

match.CLEAN = True
ASM = os.path.join(match.ROOT, 'decomp', 'asm')
rows = []
for fn in sorted(os.listdir(ASM)):
    stem = fn[:-len('.as2asm')]
    key = stem[len('init_class_'):] if stem.startswith('init_class_') else stem
    size = len(as2asm.assemble(open(os.path.join(ASM, fn), encoding='utf-8').read()))
    has_src = os.path.exists(match.src_path(key))
    ok = False
    if has_src:
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ok = match.run(key, show=False)
    rows.append((key, size, has_src, ok))

tot = sum(r[1] for r in rows)
src = sum(r[1] for r in rows if r[3])
print('%-48s %8s  %s' % ('script', 'bytes', 'status'))
for k, s, h, ok in rows:
    print('%-48s %8d  %s' % (k, s, 'MATCHES from AS2 source' if ok else ('SOURCE DOES NOT MATCH' if h else 'assembly only (exact)')))
print()
print('scripts: %d total, %d compile from source to identical bytes' % (len(rows), sum(1 for r in rows if r[3])))
print('bytecode: %d bytes total, %d bytes (%.1f%%) matched from readable source' % (tot, src, 100.0 * src / tot))
game = [r for r in rows if not r[0].startswith('mx.') and not r[0].startswith('init_')]
print('game-specific code (everything except the stock mx.* component framework): %d/%d scripts matched' %
      (sum(1 for r in game if r[3]), len(game)))
