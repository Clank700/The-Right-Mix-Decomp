"""extract_media.py - bitmaps and sounds out of a SWF, without any external decompiler.

  images:  DefineBits (+JPEGTables), DefineBitsJPEG2/3, DefineBitsLossless/2  ->  <id>.png (or <id>.jpg when the picture
           is an opaque JPEG, which is kept byte for byte)
  sounds:  DefineSound (MP3)                                                  ->  <id>.mp3 (the MP3 frames, without
           the SWF's 2-byte seek field)

Needs Pillow for decoding the JPEG and writing PNG. The result is what tools/assetc/build_assets.py consumes.
"""
import io
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'swfproj'))
import swfio  # noqa: E402


def _strip_jpeg(data):
    """Flash JPEG streams may start with an erroneous 'FF D9 FF D8' pair and carry a stray EOI; normalise to one JPEG."""
    if data[:4] == b'\xff\xd9\xff\xd8':
        data = data[4:]
    return data


def _merge_tables(tables, data):
    """JPEGTables (SOI, tables, EOI) + image data (SOI, frame, EOI) -> one JPEG."""
    data = _strip_jpeg(data)
    if tables and tables[-2:] == b'\xff\xd9':
        tables = tables[:-2]
    if data[:2] == b'\xff\xd8':
        data = data[2:]
    return tables + data


def _decode_jpeg(data):
    from PIL import Image
    return Image.open(io.BytesIO(data)).convert('RGB')


def _png_bytes(img):
    out = io.BytesIO()
    img.save(out, format='PNG')
    return out.getvalue()


def _lossless(payload, has_alpha):
    from PIL import Image
    cid, fmt, w, h = struct.unpack_from('<HBHH', payload, 0)
    pos = 7
    ncolors = 0
    if fmt == 3:
        ncolors = payload[pos] + 1
        pos += 1
    raw = zlib.decompress(payload[pos:])
    if fmt == 3:
        bpp = 4 if has_alpha else 3
        table = raw[:ncolors * bpp]
        idx = raw[ncolors * bpp:]
        stride = (w + 3) & ~3
        px = bytearray(w * h * 4)
        for y in range(h):
            row = idx[y * stride:y * stride + w]
            for x, i in enumerate(row):
                if i >= ncolors:
                    r = g = b = a = 0
                else:
                    e = table[i * bpp:(i + 1) * bpp]
                    if has_alpha:
                        r, g, b, a = e[0], e[1], e[2], e[3]
                    else:
                        r, g, b, a = e[0], e[1], e[2], 255
                o = (y * w + x) * 4
                px[o:o + 4] = bytes((r, g, b, a))
    elif fmt == 5:
        px = bytearray(w * h * 4)
        for i in range(w * h):
            a, r, g, b = raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]
            px[i * 4:i * 4 + 4] = bytes((r, g, b, a)) if has_alpha else bytes((r, g, b, 255))
    elif fmt == 4:  # 15-bit RGB (Lossless only)
        px = bytearray(w * h * 4)
        stride = (w * 2 + 3) & ~3
        for y in range(h):
            for x in range(w):
                v = (raw[y * stride + x * 2] << 8) | raw[y * stride + x * 2 + 1]
                r, g, b = ((v >> 10) & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31, (v & 31) * 255 // 31
                px[(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes((r, g, b, 255))
    else:
        raise ValueError('unsupported lossless bitmap format %d' % fmt)
    if has_alpha:
        # Lossless2 stores colour premultiplied by alpha: undo it (round to nearest)
        for i in range(w * h):
            a = px[i * 4 + 3]
            if 0 < a < 255:
                for c in range(3):
                    px[i * 4 + c] = min(255, (px[i * 4 + c] * 255) // a)
    return cid, Image.frombytes('RGBA', (w, h), bytes(px))


def extract(swf_path, out_dir):
    """Write images/ and sounds/ into out_dir. Returns (n_images, n_sounds)."""
    swf = swfio.Swf.load(swf_path)
    img_dir = os.path.join(out_dir, 'images')
    snd_dir = os.path.join(out_dir, 'sounds')
    os.makedirs(img_dir, exist_ok=True)
    os.makedirs(snd_dir, exist_ok=True)
    from PIL import Image
    tables = b''
    ni = ns = 0
    for t in swf.tags:
        c, p = t.code, t.payload
        if c == 8:  # JPEGTables
            tables = p
        elif c == 6:  # DefineBits
            cid = struct.unpack_from('<H', p, 0)[0]
            data = _merge_tables(tables, p[2:])
            with open(os.path.join(img_dir, '%d.jpg' % cid), 'wb') as f:
                f.write(data)
            ni += 1
        elif c == 21:  # DefineBitsJPEG2
            cid = struct.unpack_from('<H', p, 0)[0]
            with open(os.path.join(img_dir, '%d.jpg' % cid), 'wb') as f:
                f.write(_strip_jpeg(p[2:]))
            ni += 1
        elif c == 35:  # DefineBitsJPEG3: JPEG + zlib-compressed alpha plane
            cid, off = struct.unpack_from('<HI', p, 0)
            jpeg = _strip_jpeg(p[6:6 + off])
            alpha_raw = p[6 + off:]
            img = _decode_jpeg(jpeg)
            alpha = zlib.decompress(alpha_raw) if alpha_raw else b''
            if len(alpha) == img.width * img.height and any(b != 255 for b in alpha):
                rgba = img.convert('RGBA')
                rgba.putalpha(Image.frombytes('L', img.size, alpha))
                # the colour of a JPEG3 picture is premultiplied by its alpha (as in Lossless2): undo it
                px = bytearray(rgba.tobytes())
                for i in range(0, len(px), 4):
                    a = px[i + 3]
                    if a == 0:
                        px[i] = px[i + 1] = px[i + 2] = 0
                    elif a < 255:
                        for c in range(3):
                            px[i + c] = min(255, (px[i + c] * 255) // a)
                rgba = Image.frombytes('RGBA', img.size, bytes(px))
                with open(os.path.join(img_dir, '%d.png' % cid), 'wb') as f:
                    f.write(_png_bytes(rgba))
            else:
                with open(os.path.join(img_dir, '%d.jpg' % cid), 'wb') as f:
                    f.write(jpeg)
            ni += 1
        elif c in (20, 36):  # DefineBitsLossless / Lossless2
            cid, img = _lossless(p, c == 36)
            with open(os.path.join(img_dir, '%d.png' % cid), 'wb') as f:
                f.write(_png_bytes(img))
            ni += 1
        elif c == 14:  # DefineSound
            cid, flags = struct.unpack_from('<HB', p, 0)
            fmt = flags >> 4
            if fmt != 2:
                raise ValueError('sound %d: only MP3 sounds are supported (format %d)' % (cid, fmt))
            with open(os.path.join(snd_dir, '%d.mp3' % cid), 'wb') as f:
                f.write(p[9:])  # id(2) flags(1) sampleCount(4) seekSamples(2), then the MP3 frames
            ns += 1
    return ni, ns


if __name__ == '__main__':
    print('images %d, sounds %d' % extract(sys.argv[1], sys.argv[2]))
