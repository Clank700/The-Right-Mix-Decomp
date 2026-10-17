"""SWF (v<=7) character parsers: shapes, fonts, text, buttons, sprite timelines -> plain Python data.

Coordinates leave this module in pixels (twips / 20). Output is consumed by build_assets.py.
"""
import struct
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'swfproj'))
import swfio  # noqa: E402


class Bits:
    def __init__(self, d, pos=0):
        self.d = d
        self.bp = pos * 8

    def ub(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | ((self.d[self.bp >> 3] >> (7 - (self.bp & 7))) & 1)
            self.bp += 1
        return v

    def sb(self, n):
        if n == 0:
            return 0
        v = self.ub(n)
        if v & (1 << (n - 1)):
            v -= 1 << n
        return v

    def fb(self, n):
        return self.sb(n) / 65536.0

    def flag(self):
        return self.ub(1)

    def align(self):
        self.bp = (self.bp + 7) & ~7

    @property
    def pos(self):
        return (self.bp + 7) >> 3

    # byte-aligned reads
    def u8(self):
        self.align()
        v = self.d[self.bp >> 3]
        self.bp += 8
        return v

    def u16(self):
        self.align()
        v = struct.unpack_from('<H', self.d, self.bp >> 3)[0]
        self.bp += 16
        return v

    def s16(self):
        self.align()
        v = struct.unpack_from('<h', self.d, self.bp >> 3)[0]
        self.bp += 16
        return v

    def u32(self):
        self.align()
        v = struct.unpack_from('<I', self.d, self.bp >> 3)[0]
        self.bp += 32
        return v

    def cstr(self):
        self.align()
        p = self.bp >> 3
        e = self.d.index(b'\0', p)
        self.bp = (e + 1) * 8
        return self.d[p:e].decode('utf-8', 'replace')


def px(v):
    r = round(v / 20.0, 2)
    return int(r) if r == int(r) else r


def rect(b):
    n = b.ub(5)
    xmin, xmax, ymin, ymax = b.sb(n), b.sb(n), b.sb(n), b.sb(n)
    b.align()
    return [px(xmin), px(ymin), px(xmax), px(ymax)]


def matrix(b, to_px=True):
    """-> [a, b, c, d, tx, ty]; x' = a*x + c*y + tx ; y' = b*x + d*y + ty"""
    sx, sy, r0, r1 = 1.0, 1.0, 0.0, 0.0
    if b.flag():
        n = b.ub(5)
        sx, sy = b.fb(n), b.fb(n)
    if b.flag():
        n = b.ub(5)
        r0, r1 = b.fb(n), b.fb(n)
    n = b.ub(5)
    tx, ty = b.sb(n), b.sb(n)
    b.align()
    if to_px:
        tx, ty = tx / 20.0, ty / 20.0
    return [round(sx, 6), round(r0, 6), round(r1, 6), round(sy, 6), round(tx, 3), round(ty, 3)]


def cxform(b, with_alpha=True):
    """-> [ra, ga, ba, aa, rb, gb, bb, ab] with multipliers as 0..1+ floats and adds as 0..255"""
    has_add, has_mult = b.flag(), b.flag()
    n = b.ub(4)
    m = [256, 256, 256, 256]
    a = [0, 0, 0, 0]
    if has_mult:
        m = [b.sb(n) for _ in range(4 if with_alpha else 3)] + ([] if with_alpha else [256])
    if has_add:
        a = [b.sb(n) for _ in range(4 if with_alpha else 3)] + ([] if with_alpha else [0])
    b.align()
    return [round(x / 256.0, 5) for x in m] + a


def rgb(b, alpha):
    r, g, bl = b.u8(), b.u8(), b.u8()
    a = b.u8() if alpha else 255
    return [r, g, bl, a]


# ---- shapes ---------------------------------------------------------------------------------------
def fill_styles(b, ver, alpha):
    n = b.u8()
    if n == 0xFF and ver >= 2:
        n = b.u16()
    out = []
    for _ in range(n):
        t = b.u8()
        if t == 0x00:
            out.append({'t': 's', 'c': rgb(b, alpha)})
        elif t in (0x10, 0x12, 0x13):
            m = matrix(b, to_px=False)
            m = [m[0] / 20, m[1] / 20, m[2] / 20, m[3] / 20, m[4] / 20, m[5] / 20]
            if ver >= 4 or t == 0x13:
                b.align()
                flags = b.u8()
                ng = flags & 15
            else:
                ng = b.u8() & 15
            stops = []
            for _ in range(ng):
                ratio = b.u8()
                stops.append([ratio] + rgb(b, alpha))
            st = {'t': {0x10: 'lg', 0x12: 'rg', 0x13: 'rg'}[t], 'm': [round(x, 5) for x in m], 'stops': stops}
            if t == 0x13:
                st['focal'] = struct.unpack('<h', bytes([b.u8(), b.u8()]))[0] / 256.0
            out.append(st)
        elif 0x40 <= t <= 0x43:
            bid = b.u16()
            m = matrix(b, to_px=False)
            m = [m[0] / 20, m[1] / 20, m[2] / 20, m[3] / 20, m[4] / 20, m[5] / 20]
            out.append({'t': 'bm', 'id': bid, 'm': [round(x, 5) for x in m], 'smooth': t in (0x40, 0x41), 'repeat': t in (0x40, 0x42)})
        else:
            raise ValueError('fill style %x' % t)
    return out


def line_styles(b, ver, alpha):
    n = b.u8()
    if n == 0xFF:
        n = b.u16()
    out = []
    for _ in range(n):
        w = b.u16()
        out.append({'w': round(w / 20.0, 3), 'c': rgb(b, alpha)})
    return out


def shape_records(b, nfb, nlb, fills, lines, ver, alpha, with_styles):
    """Yield layers: each layer = (fills, lines, segs). seg = (fill0, fill1, line, kind, x0, y0, cx, cy, x1, y1, newrun)"""
    layers = []
    segs = []
    x = y = 0
    f0 = f1 = ln = 0
    newrun = True
    while True:
        if b.flag() == 0:
            flags = b.ub(5)
            if flags == 0:
                break
            if flags & 1:
                n = b.ub(5)
                x, y = b.sb(n), b.sb(n)
                newrun = True
            if flags & 2:
                f0 = b.ub(nfb)
            if flags & 4:
                f1 = b.ub(nfb)
            if flags & 8:
                ln = b.ub(nlb)
                newrun = True
            if flags & 16 and with_styles:
                layers.append((fills, lines, segs))
                segs = []
                b.align()
                fills = fill_styles(b, ver, alpha)
                lines = line_styles(b, ver, alpha)
                nfb, nlb = b.ub(4), b.ub(4)
                f0 = f1 = ln = 0
                newrun = True
        else:
            if b.flag():  # straight
                n = b.ub(4) + 2
                if b.flag():
                    dx, dy = b.sb(n), b.sb(n)
                elif b.flag():
                    dx, dy = 0, b.sb(n)
                else:
                    dx, dy = b.sb(n), 0
                segs.append((f0, f1, ln, 'L', x, y, 0, 0, x + dx, y + dy, newrun))
                x, y = x + dx, y + dy
            else:
                n = b.ub(4) + 2
                cdx, cdy, adx, ady = b.sb(n), b.sb(n), b.sb(n), b.sb(n)
                cx, cy = x + cdx, y + cdy
                segs.append((f0, f1, ln, 'Q', x, y, cx, cy, cx + adx, cy + ady, newrun))
                x, y = cx + adx, cy + ady
            newrun = False
    layers.append((fills, lines, segs))
    b.align()
    return layers


def stitch(edges):
    """edges: list of (kind, x0,y0,cx,cy,x1,y1). Returns list of paths (flat cmd arrays, px)."""
    by_start = {}
    for i, e in enumerate(edges):
        by_start.setdefault((e[1], e[2]), []).append(i)
    used = [False] * len(edges)
    paths = []
    for i0 in range(len(edges)):
        if used[i0]:
            continue
        used[i0] = True
        chain = [edges[i0]]
        start = (edges[i0][1], edges[i0][2])
        cur = (edges[i0][5], edges[i0][6])
        while cur != start:
            nxt = None
            for j in by_start.get(cur, ()):
                if not used[j]:
                    nxt = j
                    break
            if nxt is None:
                break
            used[nxt] = True
            chain.append(edges[nxt])
            cur = (edges[nxt][5], edges[nxt][6])
        paths.append(emit_path(chain, close=(cur == start)))
    return paths


def emit_path(chain, close):
    out = [0, px(chain[0][1]), px(chain[0][2])]
    for k, x0, y0, cx, cy, x1, y1 in chain:
        if k == 'L':
            out += [1, px(x1), px(y1)]
        else:
            out += [2, px(cx), px(cy), px(x1), px(y1)]
    if close:
        out.append(3)
    return out


def rev(e):
    k, x0, y0, cx, cy, x1, y1 = e
    return (k, x1, y1, cx, cy, x0, y0)


def build_ops(layers):
    ops = []
    for fills, lines, segs in layers:
        per_fill = {}
        per_line = {}
        run = None
        for f0, f1, ln, k, x0, y0, cx, cy, x1, y1, newrun in segs:
            e = (k, x0, y0, cx, cy, x1, y1)
            if f1:
                per_fill.setdefault(f1, []).append(e)
            if f0:
                per_fill.setdefault(f0, []).append(rev(e))
            if ln:
                if newrun or run is None or run[0] != ln:
                    run = (ln, [])
                    per_line.setdefault(ln, []).append(run[1])
                run[1].append(e)
            else:
                run = None
        for idx in sorted(per_fill):
            if 1 <= idx <= len(fills):
                ops.append({'fill': fills[idx - 1], 'path': [c for p in stitch(per_fill[idx]) for c in p]})
        for idx in sorted(per_line):
            if 1 <= idx <= len(lines):
                path = []
                for chain in per_line[idx]:
                    path += emit_path(chain, close=False)
                ops.append({'stroke': lines[idx - 1], 'path': path})
    return ops


def parse_shape(tag):
    ver = {2: 1, 22: 2, 32: 3}[tag.code]
    alpha = ver >= 3
    b = Bits(tag.payload)
    cid = b.u16()
    bounds = rect(b)
    fills = fill_styles(b, ver, alpha)
    lines = line_styles(b, ver, alpha)
    nfb, nlb = b.ub(4), b.ub(4)
    layers = shape_records(b, nfb, nlb, fills, lines, ver, alpha, True)
    return cid, {'k': 'shape', 'bounds': bounds, 'ops': build_ops(layers)}


# ---- fonts / text ---------------------------------------------------------------------------------
def parse_font2(tag):
    d = tag.payload
    b = Bits(d)
    fid = b.u16()
    flags = b.u8()
    has_layout, wide_off, wide_codes = bool(flags & 0x80), bool(flags & 0x08), bool(flags & 0x04)
    b.u8()  # language
    nlen = b.u8()
    name = d[b.bp // 8:b.bp // 8 + nlen].decode('latin1').rstrip('\0')
    b.bp += nlen * 8
    ng = b.u16()
    offs = [(b.u32() if wide_off else b.u16()) for _ in range(ng)]
    code_off = b.u32() if wide_off else b.u16()
    table_start = (b.bp // 8) - (4 if wide_off else 2) - (4 if wide_off else 2) * ng
    base = table_start
    glyphs = []
    for i in range(ng):
        gb = Bits(d, base + offs[i])
        nfb, nlb = gb.ub(4), gb.ub(4)
        layers = shape_records(gb, nfb, nlb, [{'t': 's', 'c': [0, 0, 0, 255]}], [], 2, False, False)
        segs = layers[0][2]
        # font glyphs use fill0/fill1 = 1; just fill all edges forward
        edges = []
        for f0, f1, ln, k, x0, y0, cx, cy, x1, y1, nr in segs:
            e = (k, x0, y0, cx, cy, x1, y1)
            if f1:
                edges.append(e)
            if f0:
                edges.append(rev(e))
        # raw coordinates are in EM units (1024): convert px() undoes /20, so rescale after
        path = []
        for p in stitch(edges):
            path += p
        glyphs.append(path)
    cb = Bits(d, base + code_off)
    codes = [(cb.u16() if wide_codes else cb.u8()) for _ in range(ng)]
    out = {'k': 'font', 'name': name, 'bold': bool(flags & 1), 'italic': bool(flags & 2), 'codes': codes,
           'glyphs': glyphs, 'em': 1024}
    if has_layout:
        out['ascent'] = cb.s16()
        out['descent'] = cb.s16()
        out['leading'] = cb.s16()
        out['adv'] = [cb.s16() for _ in range(ng)]
        for _ in range(ng):
            n = cb.ub(5)
            cb.sb(n), cb.sb(n), cb.sb(n), cb.sb(n)
            cb.align()
        nk = cb.u16()
        kern = []
        for _ in range(nk):
            c1 = cb.u16() if wide_codes else cb.u8()
            c2 = cb.u16() if wide_codes else cb.u8()
            kern.append([c1, c2, cb.s16()])
        out['kern'] = kern
    return fid, out


def glyph_path_scaled(path, sx, sy, ox, oy, m):
    """glyph path (coords were divided by 20 by px() but are really EM units) -> px path under text matrix."""
    out = []
    i = 0
    while i < len(path):
        op = path[i]
        if op in (0, 1):
            pts = [(path[i + 1], path[i + 2])]
            i += 3
        elif op == 2:
            pts = [(path[i + 1], path[i + 2]), (path[i + 3], path[i + 4])]
            i += 5
        else:
            out.append(3)
            i += 1
            continue
        out.append(op)
        for gx, gy in pts:
            gx *= 20.0
            gy *= 20.0  # back to raw EM units
            x = ox + gx * sx
            y = oy + gy * sy
            X = m[0] * x + m[2] * y + m[4] * 20
            Y = m[1] * x + m[3] * y + m[5] * 20
            out += [px(X), px(Y)]
    return out


def parse_text(tag, fonts):
    alpha = tag.code == 33
    b = Bits(tag.payload)
    cid = b.u16()
    bounds = rect(b)
    m = matrix(b, to_px=True)
    gbits, abits = b.u8(), b.u8()
    ops = []
    font = None
    height = 0
    color = [0, 0, 0, 255]
    x = y = 0
    while True:
        b.align()
        peek = b.d[b.bp // 8]
        if peek == 0:
            break
        if b.flag() == 1:
            b.ub(3)
            has_font, has_color, has_y, has_x = b.flag(), b.flag(), b.flag(), b.flag()
            if has_font:
                font = fonts[b.u16()]
            if has_color:
                color = rgb(b, alpha)
            if has_x:
                x = b.s16()
            if has_y:
                y = b.s16()
            if has_font:
                height = b.u16()
        else:
            n = b.ub(7)
            path = []
            for _ in range(n):
                gi = b.ub(gbits)
                adv = b.sb(abits)
                if gi < len(font['glyphs']):
                    s = height / float(font['em'])
                    path += glyph_path_scaled(font['glyphs'][gi], s, s, x, y, m)
                x += adv
            if path:
                ops.append({'fill': {'t': 's', 'c': color}, 'path': path})
    return cid, {'k': 'shape', 'bounds': bounds, 'ops': ops, 'text': True}


def parse_edit_text(tag):
    b = Bits(tag.payload)
    cid = b.u16()
    bounds = rect(b)
    f1, f2 = b.u8(), b.u8()
    o = {'k': 'edit', 'bounds': bounds, 'wrap': bool(f1 & 0x40), 'multiline': bool(f1 & 0x20), 'password': bool(f1 & 0x10),
         'readonly': bool(f1 & 0x08), 'html': bool(f2 & 0x02), 'outlines': bool(f2 & 0x01), 'border': bool(f2 & 0x08),
         'autosize': bool(f2 & 0x40), 'selectable': not (f2 & 0x10)}
    if f1 & 0x01:
        o['font'] = b.u16()
        o['height'] = b.u16() / 20.0
    if f2 & 0x80:
        o['fontclass'] = b.cstr()
    o['color'] = rgb(b, True) if f1 & 0x04 else [0, 0, 0, 255]
    if f1 & 0x02:
        o['maxlen'] = b.u16()
    if f2 & 0x20:
        o['align'] = b.u8()
        o['lmargin'] = b.u16() / 20.0
        o['rmargin'] = b.u16() / 20.0
        o['indent'] = b.s16() / 20.0
        o['leading'] = b.s16() / 20.0
    o['var'] = b.cstr()
    if f1 & 0x80:
        o['text'] = b.cstr()
    return cid, o


# ---- buttons / sprites ----------------------------------------------------------------------------
def parse_button2(tag):
    d = tag.payload
    b = Bits(d)
    cid = b.u16()
    b.u8()
    act_off = b.u16()
    recs = {'up': [], 'over': [], 'down': [], 'hit': []}
    while True:
        flags = b.u8()
        if flags == 0:
            break
        ch, depth = b.u16(), b.u16()
        m = matrix(b)
        cx = cxform(b, True)
        r = {'c': ch, 'd': depth, 'm': m, 'x': cx}
        for bit, nm in ((1, 'up'), (2, 'over'), (4, 'down'), (8, 'hit')):
            if flags & bit:
                recs[nm].append(r)
    return cid, {'k': 'button', 'states': recs}


def parse_place2(p):
    flags = p[0]
    b = Bits(p, 1)
    cmd = {'d': b.u16()}
    if flags & 0x02:
        cmd['c'] = b.u16()
    if flags & 0x04:
        cmd['m'] = matrix(b)
    if flags & 0x08:
        cmd['x'] = cxform(b, True)
    if flags & 0x10:
        cmd['r'] = b.u16()
    if flags & 0x20:
        cmd['n'] = b.cstr()
    if flags & 0x40:
        cmd['cd'] = b.u16()
    if flags & 1:
        cmd['mv'] = 1
    if flags & 0x80:
        cmd['clip'] = 1
    return cmd


def parse_start_sound(p):
    sid = struct.unpack_from('<H', p, 0)[0]
    fl = p[2]
    q = 3
    o = {'id': sid, 'stop': bool(fl & 0x20), 'nomulti': bool(fl & 0x10), 'loops': 1}
    if fl & 1:
        o['in'] = struct.unpack_from('<I', p, q)[0]
        q += 4
    if fl & 2:
        o['out'] = struct.unpack_from('<I', p, q)[0]
        q += 4
    if fl & 4:
        o['loops'] = struct.unpack_from('<H', p, q)[0]
        q += 2
    if fl & 8:  # volume envelope: [position in 44.1 kHz samples, left, right (0..32768)] per point
        n = p[q]
        q += 1
        o['env'] = [list(struct.unpack_from('<IHH', p, q + 8 * i)) for i in range(n)]
    return o


def parse_timeline(tags):
    frames = []
    cur = {'cmds': []}
    labels = {}
    for t in tags:
        c = t.code
        if c == 26:
            cur['cmds'].append(parse_place2(t.payload))
        elif c == 28:
            cur['cmds'].append({'rm': struct.unpack_from('<H', t.payload, 0)[0]})
        elif c == 4 or c == 5:
            raise ValueError('PlaceObject v1 not supported')
        elif c == 12:
            pl = t.payload
            cur['a'] = 'stop' if pl == b'\x07\x00' else ('nop' if pl == b'\x00' else 'script')
        elif c == 43:
            name = t.payload[:t.payload.index(b'\0')].decode('utf-8')
            labels[name] = len(frames) + 1
        elif c == 15:
            cur.setdefault('snd', []).append(parse_start_sound(t.payload))
        elif c == 1:
            if not cur['cmds']:
                del cur['cmds']
            frames.append(cur)
            cur = {'cmds': []}
    if cur['cmds'] or cur.get('a') or cur.get('snd'):
        frames.append(cur)
    for f in frames:
        if not f.get('cmds'):
            f.pop('cmds', None)
    return frames, labels


def parse_all(swf):
    chars = {}
    fonts = {}
    bitmaps = []
    sounds = {}
    sprites = []
    for t in swf.tags:
        if t.code == 48:
            fid, f = parse_font2(t)
            fonts[fid] = f
            chars[fid] = f
    for t in swf.tags:
        c = t.code
        if c in (2, 22, 32):
            cid, o = parse_shape(t)
            chars[cid] = o
        elif c in (11, 33):
            cid, o = parse_text(t, fonts)
            chars[cid] = o
        elif c == 37:
            cid, o = parse_edit_text(t)
            chars[cid] = o
        elif c == 34:
            cid, o = parse_button2(t)
            chars[cid] = o
        elif c == 39:
            frames, labels = parse_timeline(t.children)
            o = {'k': 'sprite', 'nframes': t.sprite_frames, 'frames': frames}
            if labels:
                o['labels'] = labels
            chars[t.sprite_id] = o
        elif c in (6, 20, 21, 35, 36):
            bitmaps.append(struct.unpack_from('<H', t.payload, 0)[0])
            chars[bitmaps[-1]] = {'k': 'bitmap'}
        elif c == 14:
            sid = struct.unpack_from('<H', t.payload, 0)[0]
            fl = t.payload[2]
            rate = [5512, 11025, 22050, 44100][(fl >> 2) & 3]
            chars[sid] = {'k': 'sound', 'rate': rate}
            if fl >> 4 == 2:  # MP3: the first `seek` decoded samples are encoder/decoder delay that Flash skips
                chars[sid]['seek'] = struct.unpack_from('<h', t.payload, 7)[0]
    main_frames, main_labels = parse_timeline([t for t in swf.tags if t.code in (26, 28, 12, 43, 15, 1)])
    exports = {}
    for t in swf.tags:
        if t.code == 56:
            n = struct.unpack_from('<H', t.payload, 0)[0]
            q = 2
            for _ in range(n):
                cid = struct.unpack_from('<H', t.payload, q)[0]
                q += 2
                e = t.payload.index(b'\0', q)
                exports.setdefault(t.payload[q:e].decode('utf-8'), cid)
                q = e + 1
    return chars, exports, main_frames
