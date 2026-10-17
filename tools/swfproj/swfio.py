"""Low-level SWF container I/O: header, tag stream (with nested sprites), bit-exact re-serialisation."""
import struct
import zlib

TAG_NAMES = {
    0: 'End', 1: 'ShowFrame', 2: 'DefineShape', 4: 'PlaceObject', 5: 'RemoveObject', 6: 'DefineBits',
    7: 'DefineButton', 8: 'JPEGTables', 9: 'SetBackgroundColor', 10: 'DefineFont', 11: 'DefineText',
    12: 'DoAction', 13: 'DefineFontInfo', 14: 'DefineSound', 15: 'StartSound', 17: 'DefineButtonSound',
    18: 'SoundStreamHead', 19: 'SoundStreamBlock', 20: 'DefineBitsLossless', 21: 'DefineBitsJPEG2',
    22: 'DefineShape2', 23: 'DefineButtonCxform', 24: 'Protect', 26: 'PlaceObject2', 28: 'RemoveObject2',
    32: 'DefineShape3', 33: 'DefineText2', 34: 'DefineButton2', 35: 'DefineBitsJPEG3',
    36: 'DefineBitsLossless2', 37: 'DefineEditText', 39: 'DefineSprite', 43: 'FrameLabel',
    45: 'SoundStreamHead2', 46: 'DefineMorphShape', 48: 'DefineFont2', 56: 'ExportAssets',
    57: 'ImportAssets', 58: 'EnableDebugger', 59: 'DoInitAction', 62: 'DefineFontInfo2', 64: 'EnableDebugger2',
    65: 'ScriptLimits', 66: 'SetTabIndex',
}


class Tag:
    """One SWF tag. `children` is set only for DefineSprite (its nested control tags)."""

    __slots__ = ('code', 'payload', 'long_hdr', 'children', 'sprite_id', 'sprite_frames')

    def __init__(self, code, payload=b'', long_hdr=False):
        self.code = code
        self.payload = payload
        self.long_hdr = long_hdr
        self.children = None
        self.sprite_id = None
        self.sprite_frames = None

    @property
    def name(self):
        return TAG_NAMES.get(self.code, 'Tag%d' % self.code)


def parse_tags(buf, pos, end, nested=False):
    tags = []
    while pos < end:
        hdr = struct.unpack_from('<H', buf, pos)[0]
        pos += 2
        code, ln = hdr >> 6, hdr & 63
        long_hdr = False
        if ln == 63:
            ln = struct.unpack_from('<I', buf, pos)[0]
            pos += 4
            long_hdr = True
        payload = bytes(buf[pos:pos + ln])
        t = Tag(code, payload, long_hdr)
        if code == 39:
            sid, frames = struct.unpack_from('<HH', payload, 0)
            t.sprite_id, t.sprite_frames = sid, frames
            t.children = parse_tags(payload, 4, len(payload), True)
            t.payload = b''
        tags.append(t)
        pos += ln
        if code == 0 and not nested:
            break
    return tags


def write_tag(t):
    if t.code == 39:
        payload = struct.pack('<HH', t.sprite_id, t.sprite_frames) + write_tags(t.children)
    else:
        payload = t.payload
    ln = len(payload)
    if t.long_hdr or ln >= 63:
        return struct.pack('<HI', (t.code << 6) | 63, ln) + payload
    return struct.pack('<H', (t.code << 6) | ln) + payload


def write_tags(tags):
    return b''.join(write_tag(t) for t in tags)


class Swf:
    def __init__(self, signature, version, rect_frame_bytes, tags, trailing=b''):
        self.signature = signature      # b'FWS' or b'CWS'
        self.version = version
        self.rect_frame = rect_frame_bytes  # RECT + frame rate + frame count, verbatim
        self.tags = tags
        self.trailing = trailing

    @staticmethod
    def load(path):
        data = open(path, 'rb').read()
        sig, ver = data[:3], data[3]
        body = zlib.decompress(data[8:]) if sig == b'CWS' else data[8:]
        nbits = body[0] >> 3
        rect_len = (5 + 4 * nbits + 7) // 8
        hdr_len = rect_len + 4
        tags = parse_tags(body, hdr_len, len(body))
        consumed = hdr_len + sum(len(write_tag(t)) for t in tags)
        return Swf(sig, ver, body[:hdr_len], tags, body[consumed:])

    def body_bytes(self):
        return self.rect_frame + write_tags(self.tags) + self.trailing

    def to_fws(self):
        body = self.body_bytes()
        return b'FWS' + bytes([self.version]) + struct.pack('<I', len(body) + 8) + body

    def to_cws(self, level=9):
        body = self.body_bytes()
        return b'CWS' + bytes([self.version]) + struct.pack('<I', len(body) + 8) + zlib.compress(body, level)
