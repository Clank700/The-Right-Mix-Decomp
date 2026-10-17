"""Lossless ActionScript 1/2 (SWF action) disassembler and assembler.

`disassemble(bytes) -> str` and `assemble(str) -> bytes` are exact inverses for every script in this game:
each instruction maps to one text line, nothing is normalised (constant-pool indices, push types,
dead code and jump offsets are all kept), so `assemble(disassemble(b)) == b`.
Anything the tool does not understand is emitted as `Raw 0xNN hex...` which also round-trips.
"""
import json
import re
import struct

# --- opcode tables -------------------------------------------------------------------------------
SIMPLE = {
    0x04: 'NextFrame', 0x05: 'PreviousFrame', 0x06: 'Play', 0x07: 'Stop', 0x08: 'ToggleQuality',
    0x09: 'StopSounds', 0x0A: 'Add', 0x0B: 'Subtract', 0x0C: 'Multiply', 0x0D: 'Divide', 0x0E: 'Equals',
    0x0F: 'Less', 0x10: 'And', 0x11: 'Or', 0x12: 'Not', 0x13: 'StringEquals', 0x14: 'StringLength',
    0x15: 'StringExtract', 0x17: 'Pop', 0x18: 'ToInteger', 0x1C: 'GetVariable', 0x1D: 'SetVariable',
    0x20: 'SetTarget2', 0x21: 'StringAdd', 0x22: 'GetProperty', 0x23: 'SetProperty', 0x24: 'CloneSprite',
    0x25: 'RemoveSprite', 0x26: 'Trace', 0x27: 'StartDrag', 0x28: 'EndDrag', 0x29: 'StringLess',
    0x2A: 'Throw', 0x2B: 'CastOp', 0x2C: 'ImplementsOp', 0x30: 'RandomNumber', 0x31: 'MBStringLength',
    0x32: 'CharToAscii', 0x33: 'AsciiToChar', 0x34: 'GetTime', 0x35: 'MBStringExtract',
    0x36: 'MBCharToAscii', 0x37: 'MBAsciiToChar', 0x3A: 'Delete', 0x3B: 'Delete2', 0x3C: 'DefineLocal',
    0x3D: 'CallFunction', 0x3E: 'Return', 0x3F: 'Modulo', 0x40: 'NewObject', 0x41: 'DefineLocal2',
    0x42: 'InitArray', 0x43: 'InitObject', 0x44: 'TypeOf', 0x45: 'TargetPath', 0x46: 'Enumerate',
    0x47: 'Add2', 0x48: 'Less2', 0x49: 'Equals2', 0x4A: 'ToNumber', 0x4B: 'ToString', 0x4C: 'PushDuplicate',
    0x4D: 'StackSwap', 0x4E: 'GetMember', 0x4F: 'SetMember', 0x50: 'Increment', 0x51: 'Decrement',
    0x52: 'CallMethod', 0x53: 'NewMethod', 0x54: 'InstanceOf', 0x55: 'Enumerate2', 0x60: 'BitAnd',
    0x61: 'BitOr', 0x62: 'BitXor', 0x63: 'BitLShift', 0x64: 'BitRShift', 0x65: 'BitURShift',
    0x66: 'StrictEquals', 0x67: 'Greater', 0x68: 'StringGreater', 0x69: 'Extends', 0x00: 'End',
}
SIMPLE_REV = {v: k for k, v in SIMPLE.items()}

OP_GOTOFRAME, OP_GETURL, OP_STOREREG, OP_CPOOL, OP_WAITFRAME = 0x81, 0x83, 0x87, 0x88, 0x8A
OP_SETTARGET, OP_GOTOLABEL, OP_WAITFRAME2, OP_FUNC2, OP_TRY = 0x8B, 0x8C, 0x8D, 0x8E, 0x8F
OP_WITH, OP_PUSH, OP_JUMP, OP_GETURL2, OP_FUNC, OP_IF, OP_CALL, OP_GOTOFRAME2 = 0x94, 0x96, 0x99, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F


class AsmError(Exception):
    pass


# --- helpers -------------------------------------------------------------------------------------
def _cstr(data, p):
    e = data.index(b'\0', p)
    return data[p:e].decode('utf-8'), e + 1


def _q(s):
    return json.dumps(s, ensure_ascii=False)


def _fmt_double(raw8):
    # SWF stores the two 32-bit halves of an IEEE double swapped
    b = raw8[4:8] + raw8[0:4]
    v = struct.unpack('<d', b)[0]
    if repr(v) not in ('nan', 'inf', '-inf') and _pack_double(v) == raw8:
        return 'd:' + repr(v)
    return 'dx:' + raw8.hex()


def _pack_double(v):
    b = struct.pack('<d', v)
    return b[4:8] + b[0:4]


def _fmt_float(raw4):
    v = struct.unpack('<f', raw4)[0]
    if repr(v) not in ('nan', 'inf', '-inf') and struct.pack('<f', v) == raw4:
        return 'f:' + repr(v)
    return 'fx:' + raw4.hex()


# --- disassembly ---------------------------------------------------------------------------------
class Node:
    __slots__ = ('addr', 'size', 'op', 'text', 'target', 'body', 'strings')

    def __init__(self, addr, size, op, text, target=None, body=None):
        self.addr, self.size, self.op, self.text, self.target, self.body = addr, size, op, text, target, body


def _parse_push(data):
    p, out = 0, []
    while p < len(data):
        t = data[p]
        p += 1
        if t == 0:
            s, p = _cstr(data, p)
            out.append(_q(s))
        elif t == 1:
            out.append(_fmt_float(data[p:p + 4])); p += 4
        elif t == 2:
            out.append('null')
        elif t == 3:
            out.append('undefined')
        elif t == 4:
            out.append('r:%d' % data[p]); p += 1
        elif t == 5:
            out.append('true' if data[p] else 'false')
            if data[p] not in (0, 1):
                raise AsmError('odd bool')
            p += 1
        elif t == 6:
            out.append(_fmt_double(data[p:p + 8])); p += 8
        elif t == 7:
            out.append('i:%d' % struct.unpack('<i', data[p:p + 4])[0]); p += 4
        elif t == 8:
            out.append('c8:%d' % data[p]); p += 1
        elif t == 9:
            out.append('c16:%d' % struct.unpack('<H', data[p:p + 2])[0]); p += 2
        else:
            raise AsmError('push type %d' % t)
    return out


def _decode_one(code, p, end, base, pools):
    """Decode a single action at code[p]; returns (Node, new_p). Raises on anything unusual."""
    start = p
    op = code[p]
    p += 1
    if op < 0x80:
        if op not in SIMPLE:
            raise AsmError('unknown op %02x' % op)
        return Node(base + start, 1, op, SIMPLE[op]), p
    ln = code[p] | code[p + 1] << 8
    p += 2
    data = code[p:p + ln]
    if len(data) != ln:
        raise AsmError('truncated')
    p += ln
    size = 3 + ln
    a = base + start
    if op == OP_GOTOFRAME and ln == 2:
        return Node(a, size, op, 'GotoFrame %d' % struct.unpack('<H', data)[0]), p
    if op == OP_GETURL:
        s1, q = _cstr(data, 0)
        s2, q = _cstr(data, q)
        if q != ln:
            raise AsmError('geturl')
        return Node(a, size, op, 'GetURL %s, %s' % (_q(s1), _q(s2))), p
    if op == OP_STOREREG and ln == 1:
        return Node(a, size, op, 'StoreRegister %d' % data[0]), p
    if op == OP_CPOOL:
        n = struct.unpack('<H', data[:2])[0]
        q, strs = 2, []
        for _ in range(n):
            s, q = _cstr(data, q)
            strs.append(s)
        if q != ln:
            raise AsmError('cpool')
        pools[:] = strs
        return Node(a, size, op, 'ConstantPool ' + ', '.join(_q(s) for s in strs)), p
    if op == OP_WAITFRAME and ln == 3:
        fr, skip = struct.unpack('<HB', data)
        return Node(a, size, op, 'WaitForFrame %d, %d' % (fr, skip)), p
    if op == OP_SETTARGET:
        s, q = _cstr(data, 0)
        if q != ln:
            raise AsmError('settarget')
        return Node(a, size, op, 'SetTarget ' + _q(s)), p
    if op == OP_GOTOLABEL:
        s, q = _cstr(data, 0)
        if q != ln:
            raise AsmError('gotolabel')
        return Node(a, size, op, 'GotoLabel ' + _q(s)), p
    if op == OP_WAITFRAME2 and ln == 1:
        return Node(a, size, op, 'WaitForFrame2 %d' % data[0]), p
    if op == OP_PUSH:
        vals = _parse_push(data)
        text = 'Push ' + ', '.join(vals)
        # annotate constant-pool references (comment only; ignored by the assembler)
        notes = []
        for v in vals:
            m = re.fullmatch(r'c(?:8|16):(\d+)', v)
            if m and int(m.group(1)) < len(pools):
                notes.append(_q(pools[int(m.group(1))]))
        if notes:
            text += '   ; ' + ', '.join(notes)
        return Node(a, size, op, text), p
    if op == OP_JUMP and ln == 2:
        off = struct.unpack('<h', data)[0]
        return Node(a, size, op, 'Jump', target=base + start + 5 + off), p
    if op == OP_IF and ln == 2:
        off = struct.unpack('<h', data)[0]
        return Node(a, size, op, 'If', target=base + start + 5 + off), p
    if op == OP_CALL and ln == 0:
        return Node(a, size, op, 'Call'), p
    if op == OP_GETURL2 and ln == 1:
        return Node(a, size, op, 'GetURL2 0x%02x' % data[0]), p
    if op == OP_GOTOFRAME2 and ln in (1, 3):
        if ln == 1:
            return Node(a, size, op, 'GotoFrame2 0x%02x' % data[0]), p
        return Node(a, size, op, 'GotoFrame2 0x%02x, %d' % (data[0], struct.unpack('<H', data[1:3])[0])), p
    if op == OP_WITH and ln == 2:
        bsize = struct.unpack('<H', data)[0]
        body, _ = _decode_block(code, p, p + bsize, base, pools)
        return Node(a, size + bsize, op, 'With', body=body), p + bsize
    if op == OP_FUNC:
        name, q = _cstr(data, 0)
        n = struct.unpack('<H', data[q:q + 2])[0]
        q += 2
        params = []
        for _ in range(n):
            s, q = _cstr(data, q)
            params.append(s)
        csize = struct.unpack('<H', data[q:q + 2])[0]
        if q + 2 != ln:
            raise AsmError('func hdr')
        body, _ = _decode_block(code, p, p + csize, base, pools)
        text = 'DefineFunction %s [%s]' % (_q(name), ', '.join(_q(x) for x in params))
        return Node(a, size + csize, op, text, body=body), p + csize
    if op == OP_FUNC2:
        name, q = _cstr(data, 0)
        n, regs, flags = struct.unpack('<HBH', data[q:q + 5])
        q += 5
        params = []
        for _ in range(n):
            r = data[q]
            q += 1
            s, q = _cstr(data, q)
            params.append('%d:%s' % (r, _q(s)))
        csize = struct.unpack('<H', data[q:q + 2])[0]
        if q + 2 != ln:
            raise AsmError('func2 hdr')
        body, _ = _decode_block(code, p, p + csize, base, pools)
        text = 'DefineFunction2 %s regs=%d flags=0x%04x [%s]' % (_q(name), regs, flags, ', '.join(params))
        return Node(a, size + csize, op, text, body=body), p + csize
    raise AsmError('unsupported form op=%02x len=%d' % (op, ln))


def _raw_node(code, p, base):
    op = code[p]
    if op < 0x80:
        return Node(base + p, 1, op, 'Raw 0x%02x' % op), p + 1
    ln = code[p + 1] | code[p + 2] << 8
    data = code[p + 3:p + 3 + ln]
    return Node(base + p, 3 + len(data), op, 'Raw 0x%02x %s' % (op, data.hex())), p + 3 + len(data)


def _decode_block(code, p, end, base, pools):
    nodes = []
    while p < end:
        try:
            n, q = _decode_one(code, p, end, base, pools)
            if q > end:
                raise AsmError('overrun')
        except (AsmError, ValueError, IndexError, struct.error, UnicodeDecodeError):
            n, q = _raw_node(code, p, base)
        nodes.append(n)
        p = q
    return nodes, p


def _flatten(nodes, acc):
    for n in nodes:
        acc.append(n)
        if n.body is not None:
            _flatten(n.body, acc)


def disassemble(code, header_comment=None):
    pools = []
    nodes, _ = _decode_block(code, 0, len(code), 0, pools)
    flat = []
    _flatten(nodes, flat)
    addrs = {n.addr for n in flat}
    targets = set()
    for n in flat:
        if n.target is not None:
            targets.add(n.target)
    end_addr = len(code)
    lines = []
    if header_comment:
        for ln in header_comment.splitlines():
            lines.append('; ' + ln)

    def label(addr):
        return 'L%04x' % addr

    def emit(ns, depth):
        ind = '  ' * depth
        for n in ns:
            if n.addr in targets:
                lines.append(ind + label(n.addr) + ':')
            if n.body is not None:
                lines.append(ind + n.text + ' {')
                emit(n.body, depth + 1)
                lines.append(ind + '}')
            elif n.target is not None:
                if n.target in addrs or n.target == end_addr:
                    lines.append(ind + '%s %s' % (n.text, label(n.target)))
                else:
                    lines.append(ind + '%s @%d' % (n.text, n.target))
            else:
                lines.append(ind + n.text)

    emit(nodes, 0)
    if end_addr in targets:
        lines.append(label(end_addr) + ':')
    return '\n'.join(lines) + '\n'


# --- assembly ------------------------------------------------------------------------------------
_TOK = re.compile(r'''\s*(?:("(?:[^"\\]|\\.)*")|([^\s,\[\]{}"]+)|([\[\]{},]))''')


def _tokens(s):
    pos, out = 0, []
    while pos < len(s):
        m = _TOK.match(s, pos)
        if not m or m.end() == pos:
            if s[pos:].strip() == '':
                break
            raise AsmError('bad token at %r' % s[pos:pos + 20])
        if m.group(1) is not None:
            out.append(('s', json.loads(m.group(1))))
        elif m.group(2) is not None:
            out.append(('w', m.group(2)))
        else:
            out.append(('p', m.group(3)))
        pos = m.end()
    return out


def _cs(s):
    return s.encode('utf-8') + b'\0'


def _enc_push(toks):
    out = b''
    for kind, val in toks:
        if kind == 's':
            out += b'\0' + _cs(val)
        elif kind == 'w':
            if val == 'null':
                out += b'\x02'
            elif val == 'undefined':
                out += b'\x03'
            elif val == 'true':
                out += b'\x05\x01'
            elif val == 'false':
                out += b'\x05\x00'
            elif val.startswith('r:'):
                out += b'\x04' + bytes([int(val[2:])])
            elif val.startswith('f:'):
                out += b'\x01' + struct.pack('<f', float(val[2:]))
            elif val.startswith('fx:'):
                out += b'\x01' + bytes.fromhex(val[3:])
            elif val.startswith('d:'):
                out += b'\x06' + _pack_double(float(val[2:]))
            elif val.startswith('dx:'):
                out += b'\x06' + bytes.fromhex(val[3:])
            elif val.startswith('i:'):
                out += b'\x07' + struct.pack('<i', int(val[2:]))
            elif val.startswith('c8:'):
                out += b'\x08' + bytes([int(val[3:])])
            elif val.startswith('c16:'):
                out += b'\x09' + struct.pack('<H', int(val[4:]))
            else:
                raise AsmError('bad push value %r' % val)
        # commas ('p') are separators
    return out


class _Ins:
    __slots__ = ('mnem', 'toks', 'label_ref', 'raw_target', 'body', 'size', 'addr', 'labels')

    def __init__(self):
        self.mnem = None
        self.toks = []
        self.label_ref = None
        self.raw_target = None
        self.body = None
        self.size = 0
        self.addr = 0
        self.labels = []


def _parse_lines(lines, idx, depth_close):
    """Parse instructions until a line '}' (if depth_close) or EOF. Returns (list, next_idx)."""
    out = []
    pending_labels = []
    while idx < len(lines):
        raw = lines[idx]
        idx += 1
        # strip comments (a ';' outside of a string) -- strings are JSON so scan quote state
        line, inq, esc = '', False, False
        for ch in raw:
            if inq:
                line += ch
                if esc:
                    esc = False
                elif ch == '\\':
                    esc = True
                elif ch == '"':
                    inq = False
            else:
                if ch == ';':
                    break
                if ch == '"':
                    inq = True
                line += ch
        line = line.strip()
        if not line:
            continue
        if line == '}':
            if not depth_close:
                raise AsmError('unbalanced }')
            return out, idx, pending_labels
        m = re.fullmatch(r'(L[0-9a-f]+):', line)
        if m:
            pending_labels.append(m.group(1))
            continue
        ins = _Ins()
        ins.labels = pending_labels
        pending_labels = []
        block = line.endswith('{')
        if block:
            line = line[:-1].rstrip()
        toks = _tokens(line)
        ins.mnem = toks[0][1]
        rest = toks[1:]
        if ins.mnem in ('Jump', 'If'):
            tgt = rest[-1][1]
            if tgt.startswith('@'):
                ins.raw_target = int(tgt[1:])
            else:
                ins.label_ref = tgt
            rest = rest[:-1]
        ins.toks = rest
        if block:
            ins.body, idx, trailing = _parse_lines(lines, idx, True)
            if trailing:
                # labels placed right before '}' belong to the end of this body: keep as marker
                z = _Ins()
                z.mnem = '__label__'
                z.labels = trailing
                ins.body.append(z)
        out.append(ins)
    if depth_close:
        raise AsmError('missing }')
    return out, idx, pending_labels


def _hdr_size(ins):
    """Encoded size of everything except nested body (3 + data for length-bearing ops)."""
    t = ins.toks
    m = ins.mnem
    if m in SIMPLE_REV:
        return 1
    if m == 'Raw':
        op = int(t[0][1], 16)
        return 1 if op < 0x80 else 3 + len(bytes.fromhex(t[1][1])) if len(t) > 1 else 3
    return 3 + len(_data(ins, {}, 0, None))


def _data(ins, labels, addr, size_total):
    """Payload bytes (after opcode+len) for length-bearing instruction."""
    m, t = ins.mnem, ins.toks
    if m == 'GotoFrame':
        return struct.pack('<H', int(t[0][1]))
    if m == 'GetURL':
        return _cs(t[0][1]) + _cs(t[2][1])
    if m == 'StoreRegister':
        return bytes([int(t[0][1])])
    if m == 'ConstantPool':
        strs = [v for k, v in t if k == 's']
        return struct.pack('<H', len(strs)) + b''.join(_cs(s) for s in strs)
    if m == 'WaitForFrame':
        return struct.pack('<HB', int(t[0][1]), int(t[2][1]))
    if m == 'SetTarget' or m == 'GotoLabel':
        return _cs(t[0][1])
    if m == 'WaitForFrame2':
        return bytes([int(t[0][1])])
    if m == 'Push':
        return _enc_push([x for x in t if not (x[0] == 'p')])
    if m in ('Jump', 'If'):
        if ins.raw_target is not None:
            tgt = ins.raw_target
        elif ins.label_ref is not None and labels:
            tgt = labels[ins.label_ref]
        else:
            tgt = addr + 5
        return struct.pack('<h', tgt - (addr + 5))
    if m == 'Call':
        return b''
    if m == 'GetURL2':
        return bytes([int(t[0][1], 0)])
    if m == 'GotoFrame2':
        d = bytes([int(t[0][1], 0)])
        if len(t) > 1:
            d += struct.pack('<H', int(t[2][1]))
        return d
    if m == 'With':
        return struct.pack('<H', size_total)
    if m == 'DefineFunction':
        name = t[0][1]
        params = [v for k, v in t[2:] if k == 's']
        return _cs(name) + struct.pack('<H', len(params)) + b''.join(_cs(p) for p in params) + struct.pack('<H', size_total)
    if m == 'DefineFunction2':
        name = t[0][1]
        regs = int(t[1][1].split('=')[1])
        flags = int(t[2][1].split('=')[1], 0)
        rest = t[3:]
        params, i = [], 0
        # rest: [ 1:"a" , 2:"b" ]  -> words like '1:' followed by string tokens
        # tokenizer splits  1:"a"  into word '1:' and string "a"
        while i < len(rest):
            k, v = rest[i]
            if k == 'w' and v.endswith(':'):
                params.append((int(v[:-1]), rest[i + 1][1]))
                i += 2
            else:
                i += 1
        return (_cs(name) + struct.pack('<HBH', len(params), regs, flags)
                + b''.join(bytes([r]) + _cs(n) for r, n in params) + struct.pack('<H', size_total))
    raise AsmError('cannot encode ' + m)


def _layout(inss, addr):
    """Assign addresses and sizes (bodies included)."""
    for ins in inss:
        if ins.mnem == '__label__':
            ins.addr, ins.size = addr, 0
            continue
        ins.addr = addr
        if ins.body is not None:
            _layout(ins.body, addr + (3 + len(_data_nolabels(ins))))
            body_size = sum(b.size for b in ins.body)
            ins.size = 3 + len(_data_nolabels(ins, body_size)) + body_size
        else:
            ins.size = _hdr_size(ins)
        addr += ins.size
    return addr


def _data_nolabels(ins, body_size=0):
    return _data(ins, None, 0, body_size)


def _collect_labels(inss, labels):
    for ins in inss:
        for l in ins.labels:
            labels[l] = ins.addr
        if ins.body is not None:
            _collect_labels(ins.body, labels)


def _emit(inss, labels, out):
    for ins in inss:
        if ins.mnem == '__label__':
            continue
        m = ins.mnem
        if m in SIMPLE_REV:
            out.append(bytes([SIMPLE_REV[m]]))
            continue
        if m == 'Raw':
            op = int(ins.toks[0][1], 16)
            if op < 0x80:
                out.append(bytes([op]))
            else:
                d = bytes.fromhex(ins.toks[1][1]) if len(ins.toks) > 1 else b''
                out.append(bytes([op]) + struct.pack('<H', len(d)) + d)
            continue
        opcode = {'GotoFrame': OP_GOTOFRAME, 'GetURL': OP_GETURL, 'StoreRegister': OP_STOREREG,
                  'ConstantPool': OP_CPOOL, 'WaitForFrame': OP_WAITFRAME, 'SetTarget': OP_SETTARGET,
                  'GotoLabel': OP_GOTOLABEL, 'WaitForFrame2': OP_WAITFRAME2, 'Push': OP_PUSH,
                  'Jump': OP_JUMP, 'If': OP_IF, 'Call': OP_CALL, 'GetURL2': OP_GETURL2,
                  'GotoFrame2': OP_GOTOFRAME2, 'With': OP_WITH, 'DefineFunction': OP_FUNC,
                  'DefineFunction2': OP_FUNC2}[m]
        body_size = sum(b.size for b in ins.body) if ins.body is not None else 0
        d = _data(ins, labels, ins.addr, body_size)
        out.append(bytes([opcode]) + struct.pack('<H', len(d)) + d)
        if ins.body is not None:
            _emit(ins.body, labels, out)


def assemble(text):
    lines = text.splitlines()
    inss, _, trailing = _parse_lines(lines, 0, False)
    if trailing:
        z = _Ins()
        z.mnem = '__label__'
        z.labels = trailing
        inss.append(z)
    _layout(inss, 0)
    labels = {}
    _collect_labels(inss, labels)
    out = []
    _emit(inss, labels, out)
    return b''.join(out)


if __name__ == '__main__':
    import sys
    code = open(sys.argv[1], 'rb').read()
    txt = disassemble(code)
    assert assemble(txt) == code, 'round trip failed'
    print(txt)
