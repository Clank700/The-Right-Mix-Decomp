#!/usr/bin/env python
"""swfproj - lossless SWF <-> editable project.

  swfproj.py extract <in.swf> <project_dir>   split a SWF into json + payload files + AS2 assembly
  swfproj.py build   <project_dir> <out.swf> [--compress]   rebuild the SWF from the project
  swfproj.py verify  <in.swf> <project_dir>   rebuild and compare against the original (decompressed bytes)

Every script (DoAction, DoInitAction, button actions, clip events) becomes a .as2asm text file
(see as2asm.py). Everything else is kept as the exact original tag payload. Nothing is normalised:
tag order, long/short tag headers, the 1,917 duplicate `barfront` exports, ... all survive.
"""
import hashlib
import json
import os
import re
import struct
import sys

import as2asm
import swfio

INLINE_MAX = 96  # payloads up to this size are kept inline as hex in swf.json


# --- bit helpers (matrix / cxform) -----------------------------------------------------------------
class BitReader:
    def __init__(self, data, pos):
        self.d, self.bitpos = data, pos * 8

    def read(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | ((self.d[self.bitpos >> 3] >> (7 - (self.bitpos & 7))) & 1)
            self.bitpos += 1
        return v

    def align(self):
        self.bitpos = (self.bitpos + 7) & ~7

    @property
    def pos(self):
        return self.bitpos >> 3


def skip_matrix(d, pos):
    br = BitReader(d, pos)
    if br.read(1):
        n = br.read(5)
        br.read(n), br.read(n)
    if br.read(1):
        n = br.read(5)
        br.read(n), br.read(n)
    n = br.read(5)
    br.read(n), br.read(n)
    br.align()
    return br.pos


def skip_cxform(d, pos):
    br = BitReader(d, pos)
    has_add, has_mult = br.read(1), br.read(1)
    n = br.read(4)
    if has_mult:
        for _ in range(4):
            br.read(n)
    if has_add:
        for _ in range(4):
            br.read(n)
    br.align()
    return br.pos


# --- script-bearing tag codecs ---------------------------------------------------------------------
CLIP_KEYPRESS = 1 << 17  # ClipEventKeyPress


def split_place_object2(p, version):
    """-> (head_bytes, events) or None when there are no clip actions."""
    flags = p[0]
    if not flags & 0x80:
        return None
    q = 3  # flags + depth
    if flags & 0x02:
        q += 2
    if flags & 0x04:
        q = skip_matrix(p, q)
    if flags & 0x08:
        q = skip_cxform(p, q)
    if flags & 0x10:
        q += 2
    if flags & 0x20:
        q = p.index(b'\0', q) + 1
    if flags & 0x40:
        q += 2
    head_end = q + 2 + 4  # reserved u16 + AllEventFlags u32 (SWF >= 6)
    head = p[:head_end]
    q = head_end
    events = []
    while True:
        ev = struct.unpack_from('<I', p, q)[0]
        q += 4
        if ev == 0:
            break
        size = struct.unpack_from('<I', p, q)[0]
        q += 4
        key = None
        body = p[q:q + size]
        if ev & CLIP_KEYPRESS:
            key, body = body[0], body[1:]
        events.append((ev, key, body))
        q += size
    if q != len(p):
        raise ValueError('trailing bytes after clip actions')
    return head, events


def join_place_object2(head, events):
    out = [head]
    for ev, key, body in events:
        data = (bytes([key]) if key is not None else b'') + body
        out.append(struct.pack('<II', ev, len(data)) + data)
    out.append(struct.pack('<I', 0))
    return b''.join(out)


def split_define_button2(p):
    """-> (head_bytes, conds[(flags, body)]) or None."""
    char_id, flags, act_off = struct.unpack_from('<HBH', p, 0)
    if act_off == 0:
        return None
    start = 3 + act_off  # ActionOffset is relative to the field itself (at byte 3)
    head = p[:start]
    conds = []
    q = start
    while True:
        size = struct.unpack_from('<H', p, q)[0]
        cflags = struct.unpack_from('<H', p, q + 2)[0]
        end = q + size if size else len(p)
        conds.append((cflags, p[q + 4:end]))
        if size == 0:
            break
        q += size
    return head, conds


def join_define_button2(head, conds):
    out = [head]
    for i, (cflags, body) in enumerate(conds):
        last = i == len(conds) - 1
        size = 0 if last else 4 + len(body)
        out.append(struct.pack('<HH', size, cflags) + body)
    return b''.join(out)


# --- extraction ----------------------------------------------------------------------------------
class Namer:
    def __init__(self):
        self.used = set()

    def make(self, base):
        base = re.sub(r'[^A-Za-z0-9_.\-]', '_', base)
        n, cand = 1, base
        while cand in self.used:
            n += 1
            cand = '%s_%d' % (base, n)
        self.used.add(cand)
        return cand


def collect_exports(tags):
    names = {}
    for t in tags:
        if t.code == 56:
            n = struct.unpack_from('<H', t.payload, 0)[0]
            q = 2
            for _ in range(n):
                cid = struct.unpack_from('<H', t.payload, q)[0]
                q += 2
                e = t.payload.index(b'\0', q)
                names.setdefault(cid, t.payload[q:e].decode('utf-8'))
                q = e + 1
    return names


def extract(swf_path, proj):
    swf = swfio.Swf.load(swf_path)
    os.makedirs(os.path.join(proj, 'asm'), exist_ok=True)
    os.makedirs(os.path.join(proj, 'payload'), exist_ok=True)
    exports = collect_exports(swf.tags)
    namer = Namer()
    counters = {'tag': 0}

    def write_asm(base, code, comment):
        name = namer.make(base) + '.as2asm'
        txt = as2asm.disassemble(code, comment)
        if as2asm.assemble(txt) != code:
            raise RuntimeError('assembler round trip failed for ' + name)
        with open(os.path.join(proj, 'asm', name), 'w', encoding='utf-8', newline='\n') as f:
            f.write(txt)
        return 'asm/' + name

    def conv(tags, ctx):
        out = []
        for idx, t in enumerate(tags):
            counters['tag'] += 1
            n = counters['tag']
            ent = {'t': t.code, 'name': t.name}
            if t.code in (2, 6, 7, 10, 11, 14, 20, 21, 22, 32, 33, 34, 35, 36, 37, 46, 48) and len(t.payload) >= 2:
                cid = struct.unpack_from('<H', t.payload, 0)[0]
                ent['id'] = cid
                if cid in exports:
                    ent['export'] = exports[cid]
            if t.long_hdr and (len(t.payload) < 63 or t.code in (12, 59, 26, 34)):
                ent['L'] = 1
            if t.code == 39:
                ent['id'] = t.sprite_id
                ent['frames'] = t.sprite_frames
                if t.sprite_id in exports:
                    ent['export'] = exports[t.sprite_id]
                sub = ctx + ['sprite%d%s' % (t.sprite_id, '_' + exports[t.sprite_id] if t.sprite_id in exports else '')]
                ent['tags'] = conv(t.children, sub)
            elif t.code == 12:
                base = '_'.join(ctx + ['frameaction']) if ctx else 'main_frameaction'
                ent['asm'] = write_asm(base, t.payload, 'DoAction in ' + (' > '.join(ctx) or 'main timeline'))
            elif t.code == 59:
                sid = struct.unpack_from('<H', t.payload, 0)[0]
                ent['sprite'] = sid
                exp = exports.get(sid)
                label = exp.replace('__Packages.', 'class_') if exp else 'sprite%d' % sid
                ent['asm'] = write_asm('init_' + label, t.payload[2:], 'DoInitAction for sprite %d (%s)' % (sid, exp))
            elif t.code == 26 and t.payload[0] & 0x80 and (sp := split_place_object2(t.payload, swf.version)):
                head, events = sp
                if join_place_object2(head, events) != t.payload:
                    raise RuntimeError('PlaceObject2 clip rebuild mismatch')
                ent['head'] = head.hex()
                ent['events'] = []
                for k, (ev, key, body) in enumerate(events):
                    e = {'flags': ev}
                    if key is not None:
                        e['key'] = key
                    e['asm'] = write_asm('_'.join(ctx + ['clipevent%d' % n]), body, 'clip event 0x%x in %s' % (ev, ' > '.join(ctx)))
                    ent['events'].append(e)
            elif t.code == 34 and (sp := split_define_button2(t.payload)):
                head, conds = sp
                if join_define_button2(head, conds) != t.payload:
                    raise RuntimeError('DefineButton2 cond rebuild mismatch')
                ent['head'] = head.hex()
                ent['conds'] = []
                for k, (cf, body) in enumerate(conds):
                    ent['conds'].append({'flags': cf, 'asm': write_asm('button%d_cond%d' % (ent['id'], k), body, 'button %d condition 0x%x' % (ent['id'], cf))})
            else:
                if len(t.payload) <= INLINE_MAX:
                    ent['hex'] = t.payload.hex()
                else:
                    fn = 'payload/%05d_%s.bin' % (n, t.name)
                    with open(os.path.join(proj, fn), 'wb') as f:
                        f.write(t.payload)
                    ent['file'] = fn
            out.append(ent)
        return out

    doc = {
        'signature': swf.signature.decode(),
        'version': swf.version,
        'header_hex': swf.rect_frame.hex(),
        'tags': conv(swf.tags, []),
        'trailing_hex': swf.trailing.hex(),
    }
    with open(os.path.join(proj, 'swf.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(doc, f, indent=0, ensure_ascii=False)
    return doc


# --- build ---------------------------------------------------------------------------------------
def build_swf(proj):
    with open(os.path.join(proj, 'swf.json'), encoding='utf-8') as f:
        doc = json.load(f)

    def asm_bytes(rel):
        with open(os.path.join(proj, rel), encoding='utf-8') as f:
            return as2asm.assemble(f.read())

    def conv(ents):
        tags = []
        for e in ents:
            t = swfio.Tag(e['t'], b'', bool(e.get('L')))
            if e['t'] == 39:
                t.sprite_id, t.sprite_frames = e['id'], e['frames']
                t.children = conv(e['tags'])
            elif e['t'] == 12:
                t.payload = asm_bytes(e['asm'])
            elif e['t'] == 59:
                t.payload = struct.pack('<H', e['sprite']) + asm_bytes(e['asm'])
            elif 'events' in e:
                evs = []
                for x in e['events']:
                    evs.append((x['flags'], x.get('key'), asm_bytes(x['asm'])))
                t.payload = join_place_object2(bytes.fromhex(e['head']), evs)
            elif 'conds' in e:
                t.payload = join_define_button2(bytes.fromhex(e['head']), [(c['flags'], asm_bytes(c['asm'])) for c in e['conds']])
            elif 'hex' in e:
                t.payload = bytes.fromhex(e['hex'])
            elif 'file' in e:
                with open(os.path.join(proj, e['file']), 'rb') as f:
                    t.payload = f.read()
            tags.append(t)
        return tags

    return swfio.Swf(doc['signature'].encode(), doc['version'], bytes.fromhex(doc['header_hex']),
                     conv(doc['tags']), bytes.fromhex(doc['trailing_hex']))


def sha(b):
    return hashlib.sha256(b).hexdigest()


def verify(swf_path, proj):
    orig = swfio.Swf.load(swf_path)
    ref = orig.to_fws()
    rebuilt = build_swf(proj).to_fws()
    ok = ref == rebuilt
    print('original decompressed sha256 :', sha(ref), len(ref), 'bytes')
    print('rebuilt  decompressed sha256 :', sha(rebuilt), len(rebuilt), 'bytes')
    print('UNCOMPRESSED SWF BYTE-IDENTICAL:', ok)
    return ok


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == 'extract':
        extract(argv[2], argv[3])
        print('extracted to', argv[3])
    elif cmd == 'build':
        swf = build_swf(argv[2])
        data = swf.to_cws() if '--compress' in argv else swf.to_fws()
        with open(argv[3], 'wb') as f:
            f.write(data)
        print('wrote', argv[3], len(data), 'bytes sha256', sha(data))
    elif cmd == 'verify':
        return 0 if verify(argv[2], argv[3]) else 1
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
