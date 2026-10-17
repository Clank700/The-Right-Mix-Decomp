"""ActionScript 2 lexer and parser (the subset used by this game and the Macromedia component classes).

Produces plain tuples:
  expressions: ('num', v) ('str', s) ('bool', b) ('null',) ('undef',) ('id', name) ('this',) ('member', obj, name)
               ('index', obj, expr) ('call', fn_expr, [args]) ('new', ctor_expr, [args]) ('un', op, e) ('post', op, e)
               ('pre', op, e) ('bin', op, a, b) ('logic', op, a, b) ('assign', op, target, value) ('cond', c, a, b)
               ('func', name, [params], body) ('array', [items]) ('object', [(key, expr)]) ('super_call', [args])
  statements:  ('var', [(name, init|None)]) ('expr', e) ('if', c, then, else|None) ('while', c, body)
               ('dowhile', body, c) ('for', init|None, cond|None, step|None, body) ('forin', var, is_var, obj, body)
               ('switch', e, [(test|None, [stmts])]) ('break',) ('continue',) ('return', e|None) ('block', [stmts])
               ('with', e, body) ('empty',) ('trace', e)
"""
import re

KEYWORDS = {'var', 'function', 'if', 'else', 'while', 'do', 'for', 'in', 'switch', 'case', 'default', 'break',
            'continue', 'return', 'new', 'delete', 'typeof', 'void', 'this', 'null', 'undefined', 'true', 'false',
            'with', 'class', 'extends', 'implements', 'interface', 'static', 'private', 'public', 'instanceof',
            'import', 'get', 'set'}

TOKEN_RE = re.compile(r'''
    (?P<ws>\s+)
  | (?P<lc>//[^\n]*)
  | (?P<bc>/\*.*?\*/)
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|\d+(?:[eE][+-]?\d+)?)
  | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
  | (?P<id>[A-Za-z_$][A-Za-z0-9_$]*)
  | (?P<op>>>>=|===|!==|>>>|<<=|>>=|\+\+|--|\+=|-=|\*=|/=|%=|&=|\|=|\^=|==|!=|<=|>=|&&|\|\||<<|>>|[-+*/%&|^~!<>=?:.,;(){}\[\]])
''', re.X | re.S)

ESC = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f', '\\': '\\', '"': '"', "'": "'", '0': '\0'}


def unescape(s):
    out, i = [], 1
    body = s[1:-1]
    i = 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i + 1]
            if n == 'u' and i + 5 < len(body) + 1:
                out.append(chr(int(body[i + 2:i + 6], 16)))
                i += 6
                continue
            if n == 'x':
                out.append(chr(int(body[i + 2:i + 4], 16)))
                i += 4
                continue
            out.append(ESC.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


class Tok:
    __slots__ = ('kind', 'val', 'pos', 'line')

    def __init__(self, kind, val, pos, line):
        self.kind, self.val, self.pos, self.line = kind, val, pos, line

    def __repr__(self):
        return '%s:%r@%d' % (self.kind, self.val, self.line)


def lex(src):
    toks, pos, line = [], 0, 1
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise SyntaxError('bad character %r at line %d' % (src[pos], line))
        k = m.lastgroup
        text = m.group()
        if k in ('ws', 'lc', 'bc'):
            line += text.count('\n')
        elif k == 'num':
            toks.append(Tok('num', int(text, 16) if text[:2] in ('0x', '0X') else (float(text) if re.search(r'[.eE]', text) else int(text)), pos, line))
        elif k == 'str':
            toks.append(Tok('str', unescape(text), pos, line))
        elif k == 'id':
            toks.append(Tok('kw' if text in KEYWORDS else 'id', text, pos, line))
        else:
            toks.append(Tok('op', text, pos, line))
        pos = m.end()
    toks.append(Tok('eof', None, pos, line))
    return toks


class Parser:
    def __init__(self, src):
        self.t = lex(src)
        self.i = 0

    # -- helpers
    @property
    def cur(self):
        return self.t[self.i]

    def peek(self, n=1):
        return self.t[min(self.i + n, len(self.t) - 1)]

    def err(self, msg):
        raise SyntaxError('%s at line %d near %r' % (msg, self.cur.line, self.cur.val))

    def at(self, val):
        return self.cur.kind in ('op', 'kw') and self.cur.val == val

    def eat(self, val):
        if self.at(val):
            self.i += 1
            return True
        return False

    def expect(self, val):
        if not self.eat(val):
            self.err('expected %r' % val)

    def ident(self):
        # contextual keywords (get/set/static...) may be used as identifiers
        if self.cur.kind == 'id' or (self.cur.kind == 'kw' and self.cur.val in ('get', 'set', 'static', 'private', 'public', 'undefined')):
            v = self.cur.val
            self.i += 1
            return v
        self.err('expected identifier')

    # -- top level
    def parse_program(self):
        """Either a class/interface definition or a plain script."""
        imports = []
        while self.at('import'):
            self.i += 1
            parts = [self.ident()]
            while self.eat('.'):
                parts.append(self.ident() if not self.at('*') else '*')
                if parts[-1] == '*':
                    self.i += 1
            imports.append('.'.join(parts))
            self.eat(';')
        if self.at('class') or self.at('interface'):
            return self.parse_class(imports)
        stmts = []
        while self.cur.kind != 'eof':
            stmts.append(self.statement())
        return ('script', stmts)

    def dotted(self):
        parts = [self.ident()]
        while self.eat('.'):
            parts.append(self.ident())
        return '.'.join(parts)

    def parse_class(self, imports):
        kind = self.cur.val
        self.i += 1
        name = self.dotted()
        ext = None
        impls = []
        if self.eat('extends'):
            ext = self.dotted()
        if self.eat('implements'):
            impls.append(self.dotted())
            while self.eat(','):
                impls.append(self.dotted())
        self.expect('{')
        members = []
        while not self.at('}'):
            members.append(self.member())
        self.expect('}')
        return ('class', kind, name, ext, impls, members, imports)

    def member(self):
        static = private = False
        while self.cur.kind == 'kw' and self.cur.val in ('static', 'private', 'public'):
            if self.cur.val == 'static':
                static = True
            elif self.cur.val == 'private':
                private = True
            self.i += 1
        if self.at('var'):
            self.i += 1
            decls = []
            while True:
                n = self.ident()
                if self.eat(':'):
                    self.dotted()
                init = self.assign_expr() if self.eat('=') else None
                decls.append((n, init))
                if not self.eat(','):
                    break
            self.eat(';')
            return ('field', static, decls)
        if self.at('function'):
            self.i += 1
            accessor = None
            if self.cur.val in ('get', 'set') and self.peek().kind in ('id', 'kw') and self.peek().val != '(':
                accessor = self.cur.val
                self.i += 1
            name = self.ident()
            params = self.params()
            if self.eat(':'):
                self.dotted()
            if self.at(';'):
                self.i += 1
                return ('method', static, name, params, None, accessor)
            body = self.block()
            return ('method', static, name, params, body, accessor)
        self.err('unexpected member')

    def params(self):
        self.expect('(')
        ps = []
        while not self.at(')'):
            ps.append(self.ident())
            if self.eat(':'):
                self.dotted()
            if not self.eat(','):
                break
        self.expect(')')
        return ps

    # -- statements
    def block(self):
        self.expect('{')
        out = []
        while not self.at('}'):
            out.append(self.statement())
        self.expect('}')
        return out

    def statement(self):
        c = self.cur
        if c.kind == 'op' and c.val == '{':
            return ('block', self.block())
        if c.kind == 'op' and c.val == ';':
            self.i += 1
            return ('empty',)
        if c.kind == 'kw':
            v = c.val
            if v == 'var':
                self.i += 1
                decls = []
                while True:
                    n = self.ident()
                    if self.eat(':'):
                        self.dotted()
                    init = self.assign_expr() if self.eat('=') else None
                    decls.append((n, init))
                    if not self.eat(','):
                        break
                self.eat(';')
                return ('var', decls)
            if v == 'if':
                self.i += 1
                self.expect('(')
                cond = self.expr()
                self.expect(')')
                then = self.statement()
                els = self.statement() if self.eat('else') else None
                return ('if', cond, then, els)
            if v == 'while':
                self.i += 1
                self.expect('(')
                cond = self.expr()
                self.expect(')')
                return ('while', cond, self.statement())
            if v == 'do':
                self.i += 1
                body = self.statement()
                self.expect('while')
                self.expect('(')
                cond = self.expr()
                self.expect(')')
                self.eat(';')
                return ('dowhile', body, cond)
            if v == 'for':
                return self.for_stmt()
            if v == 'switch':
                return self.switch_stmt()
            if v == 'break':
                self.i += 1
                self.eat(';')
                return ('break',)
            if v == 'continue':
                self.i += 1
                self.eat(';')
                return ('continue',)
            if v == 'return':
                self.i += 1
                if self.at(';') or self.at('}'):
                    self.eat(';')
                    return ('return', None)
                e = self.expr()
                self.eat(';')
                return ('return', e)
            if v == 'with':
                self.i += 1
                self.expect('(')
                e = self.expr()
                self.expect(')')
                return ('with', e, self.statement())
        e = self.expr()
        self.eat(';')
        return ('expr', e)

    def for_stmt(self):
        self.i += 1
        self.expect('(')
        # for (var x in obj) / for (x in obj)
        save = self.i
        is_var = self.eat('var')
        if self.cur.kind in ('id', 'kw') and self.peek().val == 'in' and self.peek().kind == 'kw':
            name = self.ident()
            self.expect('in')
            obj = self.expr()
            self.expect(')')
            return ('forin', name, is_var, obj, self.statement())
        self.i = save
        init = None
        if not self.at(';'):
            if self.at('var'):
                self.i += 1
                decls = []
                while True:
                    n = self.ident()
                    ini = self.assign_expr() if self.eat('=') else None
                    decls.append((n, ini))
                    if not self.eat(','):
                        break
                init = ('var', decls)
            else:
                init = ('expr', self.expr())
        self.expect(';')
        cond = None if self.at(';') else self.expr()
        self.expect(';')
        step = None if self.at(')') else self.expr()
        self.expect(')')
        return ('for', init, cond, step, self.statement())

    def switch_stmt(self):
        self.i += 1
        self.expect('(')
        e = self.expr()
        self.expect(')')
        self.expect('{')
        cases = []
        while not self.at('}'):
            if self.eat('case'):
                test = self.expr()
            else:
                self.expect('default')
                test = None
            self.expect(':')
            body = []
            while not (self.at('case') or self.at('default') or self.at('}')):
                body.append(self.statement())
            cases.append((test, body))
        self.expect('}')
        return ('switch', e, cases)

    # -- expressions (precedence climbing)
    def expr(self):
        e = self.assign_expr()
        while self.at(','):
            self.i += 1
            e = ('seq', e, self.assign_expr())
        return e

    ASSIGN = {'=', '+=', '-=', '*=', '/=', '%=', '<<=', '>>=', '>>>=', '&=', '|=', '^='}

    def assign_expr(self):
        left = self.cond_expr()
        if self.cur.kind == 'op' and self.cur.val in self.ASSIGN:
            op = self.cur.val
            self.i += 1
            right = self.assign_expr()
            return ('assign', op, left, right)
        return left

    def cond_expr(self):
        c = self.binary(0)
        if self.eat('?'):
            a = self.assign_expr()
            self.expect(':')
            b = self.assign_expr()
            return ('cond', c, a, b)
        return c

    BIN = [['||'], ['&&'], ['|'], ['^'], ['&'], ['==', '!=', '===', '!=='], ['<', '>', '<=', '>=', 'instanceof'],
           ['<<', '>>', '>>>'], ['+', '-'], ['*', '/', '%']]

    def binary(self, level):
        if level == len(self.BIN):
            return self.unary()
        left = self.binary(level + 1)
        while self.cur.kind in ('op', 'kw') and self.cur.val in self.BIN[level]:
            op = self.cur.val
            self.i += 1
            right = self.binary(level + 1)
            left = ('logic' if op in ('||', '&&') else 'bin', op, left, right)
        return left

    def unary(self):
        c = self.cur
        if c.kind == 'op' and c.val in ('!', '-', '+', '~'):
            self.i += 1
            e = self.unary()
            if c.val == '-' and e[0] == 'num':
                return ('num', -e[1])
            return ('un', c.val, e)
        if c.kind == 'op' and c.val in ('++', '--'):
            self.i += 1
            return ('pre', c.val, self.unary())
        if c.kind == 'kw' and c.val in ('typeof', 'delete', 'void'):
            self.i += 1
            return ('un', c.val, self.unary())
        return self.postfix()

    def postfix(self):
        e = self.call_expr()
        if self.cur.kind == 'op' and self.cur.val in ('++', '--'):
            op = self.cur.val
            self.i += 1
            return ('post', op, e)
        return e

    def args(self):
        self.expect('(')
        out = []
        while not self.at(')'):
            out.append(self.assign_expr())
            if not self.eat(','):
                break
        self.expect(')')
        return out

    def call_expr(self):
        if self.at('new'):
            self.i += 1
            ctor = self.member_chain(self.primary_name(), allow_call=False)
            a = self.args() if self.at('(') else []
            e = ('new', ctor, a)
        else:
            e = self.primary()
        return self.member_chain(e, allow_call=True)

    def primary_name(self):
        if self.cur.kind in ('id',) or (self.cur.kind == 'kw' and self.cur.val in ('this', 'get', 'set', 'static')):
            return self.primary()
        self.err('expected constructor name')

    def member_chain(self, e, allow_call):
        while True:
            if self.at('.'):
                self.i += 1
                e = ('member', e, self.ident())
            elif self.at('['):
                self.i += 1
                idx = self.expr()
                self.expect(']')
                e = ('index', e, idx)
            elif allow_call and self.at('('):
                e = ('call', e, self.args())
            else:
                return e

    def primary(self):
        c = self.cur
        if c.kind == 'num':
            self.i += 1
            return ('num', c.val)
        if c.kind == 'str':
            self.i += 1
            return ('str', c.val)
        if c.kind == 'kw':
            v = c.val
            if v == 'true' or v == 'false':
                self.i += 1
                return ('bool', v == 'true')
            if v == 'null':
                self.i += 1
                return ('null',)
            if v == 'undefined':
                self.i += 1
                return ('undef',)
            if v == 'this':
                self.i += 1
                return ('this',)
            if v == 'function':
                self.i += 1
                name = self.ident() if self.cur.kind == 'id' else ''
                ps = self.params()
                return ('func', name, ps, self.block())
            if v in ('get', 'set', 'static', 'private', 'public'):
                self.i += 1
                return ('id', v)
        if c.kind == 'id':
            self.i += 1
            if c.val == 'super' and self.at('('):
                return ('super_call', self.args())
            return ('id', c.val)
        if c.kind == 'op':
            if c.val == '(':
                self.i += 1
                e = self.expr()
                self.expect(')')
                return ('paren', e)
            if c.val == '[':
                self.i += 1
                items = []
                while not self.at(']'):
                    items.append(self.assign_expr())
                    if not self.eat(','):
                        break
                self.expect(']')
                return ('array', items)
            if c.val == '{':
                self.i += 1
                props = []
                while not self.at('}'):
                    k = self.cur
                    self.i += 1
                    self.expect(':')
                    props.append((k.val, self.assign_expr()))
                    if not self.eat(','):
                        break
                self.expect('}')
                return ('object', props)
        self.err('unexpected token')


def parse(src):
    return Parser(src).parse_program()


if __name__ == '__main__':
    import sys
    import glob
    ok = bad = 0
    for f in sorted(glob.glob(sys.argv[1])):
        try:
            parse(open(f, encoding='utf-8').read())
            ok += 1
        except Exception as e:
            bad += 1
            print('FAIL', f, e)
    print('parsed', ok, 'failed', bad)
