"""AS2 -> AVM1 assembly compiler that reproduces the original Macromedia compiler's output.

Output is as2asm text (see ../swfproj/as2asm.py); assemble() turns it into bytes. Register allocation is taken
from "hints" (the original DefineFunction2 headers) because the original allocator is opaque.
"""
import json
import re

from parser import parse

BIN_OPS = {'+': 'Add2', '-': 'Subtract', '*': 'Multiply', '/': 'Divide', '%': 'Modulo', '==': 'Equals2',
           '===': 'StrictEquals', '<': 'Less2', '>': 'Greater', '&': 'BitAnd', '|': 'BitOr', '^': 'BitXor',
           '<<': 'BitLShift', '>>': 'BitRShift', '>>>': 'BitURShift', 'instanceof': 'InstanceOf'}
COMPOUND = {'+=': '+', '-=': '-', '*=': '*', '/=': '/', '%=': '%', '<<=': '<<', '>>=': '>>', '>>>=': '>>>',
            '&=': '&', '|=': '|', '^=': '^'}


# Legacy global functions that the original compiler turned into dedicated actions (no value left on the stack).
VOID_ACTIONS = {('removeMovieClip', 1): ['RemoveSprite'], ('stop', 0): ['Stop'], ('play', 0): ['Play'],
                ('nextFrame', 0): ['NextFrame'], ('prevFrame', 0): ['PreviousFrame'],
                ('stopAllSounds', 0): ['StopSounds']}
VALUE_ACTIONS = {('getTimer', 0): 'GetTime'}


class CompileError(Exception):
    pass


# --- IR -------------------------------------------------------------------------------------------
# ('P', kind, value) | ('I', 'OpName') | ('S', reg) store register | ('L', label) | ('J', 'Jump'|'If', label)
# ('F2', name, regs, flags, params[(reg,name)], body) | ('F1', name, params, body) | ('R', raw text)

class Hint:
    def __init__(self, kind, regs=None, flags=None, params=None):
        self.kind, self.regs, self.flags, self.params = kind, regs, flags, params or []


class FnScope:
    def __init__(self, params, hint, name):
        self.params = params
        self.hint = hint
        self.name = name
        self.vars = {}          # name -> register
        self.special = {}       # 'this'|'_global'|'super'|... -> register (after preload decision)
        self.uses = set()
        self.v1 = hint is not None and hint.kind == 'F1'


def scan_uses(node, uses, in_func=False):
    """Collect which specials a function body references (not descending into nested function expressions)."""
    if isinstance(node, tuple):
        if not node:
            return
        k = node[0]
        if k == 'func':
            return
        if k == 'this':
            uses.add('this')
        elif k == 'id' and node[1] in ('_global', '_root', '_parent', 'arguments', 'super'):
            uses.add(node[1])
        elif k == 'super_call':
            uses.add('super')
        for c in node[1:]:
            scan_uses(c, uses)
    elif isinstance(node, list):
        for c in node:
            scan_uses(c, uses)


def has_with(node):
    if isinstance(node, tuple):
        if node and node[0] == 'with':
            return True
        if node and node[0] == 'func':
            return False
        return any(has_with(c) for c in node[1:])
    if isinstance(node, list):
        return any(has_with(c) for c in node)
    return False


class Compiler:
    def __init__(self, hints=None, names=None):
        self.hints = list(hints or [])
        self.names = names or {}      # function display name -> {variable name: register}
        self.fn_display = None
        self.hint_i = 0
        self.nlabel = 0
        self.scope = None
        self.loops = []   # (break_label, continue_label)
        self.forin_depth = 0

    # -- infrastructure
    def label(self):
        self.nlabel += 1
        return 'L%x' % (0x1000 + self.nlabel)

    def next_hint(self):
        if self.hint_i < len(self.hints):
            h = self.hints[self.hint_i]
            self.hint_i += 1
            return h
        self.hint_i += 1
        return None

    # -- IR helpers
    @staticmethod
    def P(kind, value=None):
        return ('P', kind, value)

    def push_num(self, v):
        if isinstance(v, int) and v != 0 and -2 ** 31 <= v < 2 ** 31:
            return self.P('int', v)
        return self.P('dbl', float(v))

    # -- identifiers
    def reg_of(self, name):
        s = self.scope
        if s is None:
            return None
        if name in s.vars:
            return s.vars[name]
        return None

    def load_id(self, name, ir):
        r = self.reg_of(name)
        if r is not None:
            ir.append(self.P('reg', r))
        else:
            sp = self.scope.special.get(name) if self.scope else None
            if sp is not None:
                ir.append(self.P('reg', sp))
            else:
                ir.append(self.P('str', name))
                ir.append(('I', 'GetVariable'))

    # -- expressions ---------------------------------------------------------------------------
    def expr(self, e, ir):
        """Emit code that leaves the value of e on the stack."""
        k = e[0]
        if k == 'paren':
            return self.expr(e[1], ir)
        if k == 'num':
            ir.append(self.push_num(e[1]))
        elif k == 'str':
            ir.append(self.P('str', e[1]))
        elif k == 'bool':
            ir.append(self.P('bool', e[1]))
        elif k == 'null':
            ir.append(self.P('null'))
        elif k == 'undef':
            ir.append(self.P('undef'))
        elif k == 'this':
            if self.scope.v1:
                ir.append(self.P('str', 'this'))
                ir.append(('I', 'GetVariable'))
            else:
                ir.append(self.P('reg', self.scope.special['this']))
        elif k == 'id':
            self.load_id(e[1], ir)
        elif k == 'member':
            self.expr(e[1], ir)
            ir.append(self.P('str', e[2]))
            ir.append(('I', 'GetMember'))
        elif k == 'index':
            self.expr(e[1], ir)
            self.expr(e[2], ir)
            ir.append(('I', 'GetMember'))
        elif k == 'call':
            self.call(e, ir)
        elif k == 'new':
            self.new(e, ir)
        elif k == 'bin':
            self.binary(e, ir)
        elif k == 'logic':
            self.logic(e, ir)
        elif k == 'un':
            self.unary(e, ir)
        elif k in ('pre', 'post'):
            self.incdec(e, ir, want=True)
        elif k == 'assign':
            self.assign(e, ir, want=True)
        elif k == 'cond':
            lelse, lend = self.label(), self.label()
            cond_ir = []
            self.expr(e[1], cond_ir)
            if cond_ir and cond_ir[-1] == ('I', 'Not'):
                cond_ir.pop()          # ternaries cancel a trailing Not against their own jump inversion
            else:
                cond_ir.append(('I', 'Not'))
            ir.extend(cond_ir)
            ir.append(('J', 'If', lelse))
            self.expr(e[2], ir)
            ir.append(('J', 'Jump', lend))
            ir.append(('L', lelse))
            self.expr(e[3], ir)
            ir.append(('L', lend))
        elif k == 'array':
            for it in reversed(e[1]):
                self.expr(it, ir)
            ir.append(self.P('int', len(e[1])) if e[1] else self.P('dbl', 0.0))
            ir.append(('I', 'InitArray'))
        elif k == 'object':
            for key, val in reversed(e[1]):
                pass
            for key, val in e[1]:
                ir.append(self.P('str', key))
                self.expr(val, ir)
            ir.append(self.P('int', len(e[1])) if e[1] else self.P('dbl', 0.0))
            ir.append(('I', 'InitObject'))
        elif k == 'func':
            ir.append(self.function(e[1], e[2], e[3], anonymous=True))
        elif k == 'super_call':
            # super(args): call the preloaded super register as a method with undefined name
            for a in reversed(e[1]):
                self.expr(a, ir)
            ir.append(self.push_count(len(e[1])))
            ir.append(self.P('reg', self.scope.special['super']))
            ir.append(self.P('undef'))
            ir.append(('I', 'CallMethod'))
        elif k == 'seq':
            self.stmt_expr(e[1], ir)
            self.expr(e[2], ir)
        else:
            raise CompileError('expr %r' % (k,))

    def push_count(self, n):
        return self.P('int', n) if n else self.P('dbl', 0.0)

    def void_action(self, e, ir):
        """If e is a legacy action-function call, emit it (leaving nothing on the stack) and return True."""
        fn, args = e[1], e[2]
        if fn[0] != 'id':
            return False
        key = (fn[1], len(args))
        if key in VOID_ACTIONS:
            for a in args:
                self.expr(a, ir)
            for op in VOID_ACTIONS[key]:
                ir.append(('I', op))
            return True
        if fn[1] == 'getURL' and len(args) == 2 and args[0][0] == 'str' and args[1][0] == 'str':
            ir.append(('R', 'GetURL %s, %s' % (json.dumps(args[0][1]), json.dumps(args[1][1]))))
            return True
        if fn[1] == 'gotoFrame' and len(args) == 1 and args[0][0] == 'num':
            # pseudo-function: a lone GotoFrame action (the original's bare gotoAndStop(1) in Additive.update)
            ir.append(('R', 'GotoFrame %d' % (int(args[0][1]) - 1)))
            return True
        if fn[1] in ('gotoAndStop', 'gotoAndPlay') and len(args) == 1 and args[0][0] == 'num':
            ir.append(('R', 'GotoFrame %d' % (int(args[0][1]) - 1)))
            ir.append(('I', 'Stop' if fn[1] == 'gotoAndStop' else 'Play'))
            return True
        return False

    def call(self, e, ir):
        fn, args = e[1], e[2]
        if fn[0] == 'paren':
            fn = fn[1]
        key = (fn[1], len(args)) if fn[0] == 'id' else None
        if key in VALUE_ACTIONS:
            ir.append(('I', VALUE_ACTIONS[key]))
            return
        if key == ('eval', 1):
            self.expr(args[0], ir)
            ir.append(('I', 'GetVariable'))
            return
        if self.void_action(e, ir):
            ir.append(self.P('undef'))
            return
        if fn[0] == 'id' and fn[1] == 'trace' and len(args) == 1:
            self.expr(args[0], ir)
            ir.append(('I', 'Trace'))
            ir.append(self.P('undef'))   # trace leaves nothing; value context gets undefined
            return
        for a in reversed(args):
            self.expr(a, ir)
        ir.append(self.push_count(len(args)))
        if fn[0] == 'member':
            self.expr(fn[1], ir)
            ir.append(self.P('str', fn[2]))
            ir.append(('I', 'CallMethod'))
        elif fn[0] == 'index':
            self.expr(fn[1], ir)
            self.expr(fn[2], ir)
            ir.append(('I', 'CallMethod'))
        elif fn[0] == 'id':
            ir.append(self.P('str', fn[1]))
            ir.append(('I', 'CallFunction'))
        else:
            self.expr(fn, ir)
            ir.append(self.P('undef'))
            ir.append(('I', 'CallMethod'))

    def new(self, e, ir):
        ctor, args = e[1], e[2]
        for a in reversed(args):
            self.expr(a, ir)
        ir.append(self.push_count(len(args)))
        if ctor[0] == 'id':
            ir.append(self.P('str', ctor[1]))
            ir.append(('I', 'NewObject'))
        else:
            self.expr(ctor[1], ir)
            ir.append(self.P('str', ctor[2]))
            ir.append(('I', 'NewMethod'))

    def binary(self, e, ir):
        op = e[1]
        if op in ('!=', '!=='):
            self.expr(e[2], ir)
            self.expr(e[3], ir)
            ir.append(('I', 'Equals2' if op == '!=' else 'StrictEquals'))
            ir.append(('I', 'Not'))
            return
        if op in ('<=', '>='):
            self.expr(e[2], ir)
            self.expr(e[3], ir)
            ir.append(('I', 'Greater' if op == '<=' else 'Less2'))
            ir.append(('I', 'Not'))
            return
        self.expr(e[2], ir)
        self.expr(e[3], ir)
        ir.append(('I', BIN_OPS[op]))

    def logic(self, e, ir):
        lend = self.label()
        self.expr(e[2], ir)
        ir.append(('I', 'PushDuplicate'))
        if e[1] == '&&':
            ir.append(('I', 'Not'))
        ir.append(('J', 'If', lend))
        ir.append(('I', 'Pop'))
        self.expr(e[3], ir)
        ir.append(('L', lend))

    def unary(self, e, ir):
        op, x = e[1], e[2]
        if op == '!':
            self.expr(x, ir)
            ir.append(('I', 'Not'))
        elif op == '-':
            ir.append(self.P('dbl', 0.0))
            self.expr(x, ir)
            ir.append(('I', 'Subtract'))
        elif op == '+':
            self.expr(x, ir)
        elif op == '~':
            self.expr(x, ir)
            ir.append(self.P('dbl', 4294967295.0))
            ir.append(('I', 'BitXor'))
        elif op == 'typeof':
            self.expr(x, ir)
            ir.append(('I', 'TypeOf'))
        elif op == 'void':
            self.expr(x, ir)
            ir.append(('I', 'Pop'))
            ir.append(self.P('undef'))
        elif op == 'delete':
            if x[0] == 'member':
                self.expr(x[1], ir)
                ir.append(self.P('str', x[2]))
                ir.append(('I', 'Delete'))
            elif x[0] == 'index':
                self.expr(x[1], ir)
                self.expr(x[2], ir)
                ir.append(('I', 'Delete'))
            else:
                ir.append(self.P('str', x[1]))
                ir.append(('I', 'Delete2'))
        else:
            raise CompileError('unary ' + op)

    # -- lvalues
    def assign(self, e, ir, want):
        op, tgt, val = e[1], e[2], e[3]
        if tgt[0] == 'paren':
            tgt = tgt[1]
        if op != '=':
            val = ('bin', COMPOUND[op], tgt, val)
            op = '='
        if tgt[0] == 'id':
            r = self.reg_of(tgt[1])
            if r is not None:
                self.expr(val, ir)
                ir.append(('S', r))
                if not want:
                    ir.append(('I', 'Pop'))
            else:
                ir.append(self.P('str', tgt[1]))
                self.expr(val, ir)
                if want:
                    ir.append(('S', 0))
                ir.append(('I', 'SetVariable'))
                if want:
                    ir.append(self.P('reg', 0))
        elif tgt[0] in ('member', 'index'):
            self.expr(tgt[1], ir)
            if tgt[0] == 'member':
                ir.append(self.P('str', tgt[2]))
            else:
                self.expr(tgt[2], ir)
            self.expr(val, ir)
            if want:
                ir.append(('S', 0))
            ir.append(('I', 'SetMember'))
            if want:
                ir.append(self.P('reg', 0))
        else:
            raise CompileError('assign target %r' % (tgt[0],))

    def incdec(self, e, ir, want):
        kind, op, tgt = e[0], e[1], e[2]
        opname = 'Increment' if op == '++' else 'Decrement'
        if tgt[0] == 'id' and self.reg_of(tgt[1]) is not None:
            r = self.reg_of(tgt[1])
            if want and kind == 'post':
                ir.append(self.P('reg', r))
                ir.append(self.P('reg', r))
                ir.append(('I', opname))
                ir.append(('S', r))
                ir.append(('I', 'Pop'))
            else:
                ir.append(self.P('reg', r))
                ir.append(('I', opname))
                ir.append(('S', r))
                if not want:
                    ir.append(('I', 'Pop'))
            return
        if tgt[0] == 'id':
            # named (non-register) variable
            if want and kind == 'post':
                ir.append(self.P('str', tgt[1]))
                self.load_id(tgt[1], ir)
                ir.append(self.P('str', tgt[1]))
                self.load_id(tgt[1], ir)
                ir.append(('I', opname))
                ir.append(('I', 'SetVariable'))
                return
            ir.append(self.P('str', tgt[1]))
            self.load_id(tgt[1], ir)
            ir.append(('I', opname))
            if want:
                ir.append(('S', 0))
            ir.append(('I', 'SetVariable'))
            if want:
                ir.append(self.P('reg', 0))
            return
        if tgt[0] == 'member':
            if want and kind == 'post':
                # value of old, then store incremented
                self.expr(tgt, ir)
                self.expr(tgt[1], ir)
                ir.append(self.P('str', tgt[2]))
                self.expr(tgt, ir)
                ir.append(('I', opname))
                ir.append(('I', 'SetMember'))
                return
            self.expr(tgt[1], ir)
            ir.append(self.P('str', tgt[2]))
            self.expr(tgt, ir)
            ir.append(('I', opname))
            if want:
                ir.append(('S', 0))
            ir.append(('I', 'SetMember'))
            if want:
                ir.append(self.P('reg', 0))
            return
        raise CompileError('incdec target %r' % (tgt[0],))

    def stmt_expr(self, e, ir):
        """Expression statement: evaluate for side effects, leave the stack unchanged."""
        k = e[0]
        if k == 'paren':
            return self.stmt_expr(e[1], ir)
        if k == 'assign':
            return self.assign(e, ir, want=False)
        if k in ('pre', 'post'):
            return self.incdec(e, ir, want=False)
        if k == 'call' and e[1][0] == 'id' and e[1][1] == 'trace' and len(e[2]) == 1:
            self.expr(e[2][0], ir)
            ir.append(('I', 'Trace'))
            return
        if k == 'call' and self.void_action(e, ir):
            return
        self.expr(e, ir)
        ir.append(('I', 'Pop'))

    # -- statements ----------------------------------------------------------------------------
    def block(self, stmts, ir):
        for s in stmts:
            self.stmt(s, ir)

    def cond_jump_false(self, cond, ir, target):
        """Jump to target when cond is false."""
        self.expr(cond, ir)
        ir.append(('I', 'Not'))
        ir.append(('J', 'If', target))

    def stmt(self, s, ir):
        k = s[0]
        if k == 'block':
            self.block(s[1], ir)
        elif k == 'empty':
            pass
        elif k == 'deadpop':
            ir.append(('I', 'Pop'))     # unreachable Pop the original emitted after a setter's implicit return
        elif k == 'expr':
            self.stmt_expr(s[1], ir)
        elif k == 'var':
            for name, init in s[1]:
                if self.scope.v1:
                    # register-less function: locals are named variables
                    ir.append(self.P('str', name))
                    if init is not None:
                        self.expr(init, ir)
                        ir.append(('I', 'DefineLocal'))
                    else:
                        ir.append(('I', 'DefineLocal2'))
                elif init is not None:
                    self.stmt_expr(('assign', '=', ('id', name), init), ir)
        elif k == 'if':
            if s[3] is None:
                lend = self.label()
                self.cond_jump_false(s[1], ir, lend)
                self.stmt(s[2], ir)
                ir.append(('L', lend))
            else:
                lelse, lend = self.label(), self.label()
                self.cond_jump_false(s[1], ir, lelse)
                self.stmt(s[2], ir)
                ir.append(('J', 'Jump', lend))
                ir.append(('L', lelse))
                self.stmt(s[3], ir)
                ir.append(('L', lend))
        elif k == 'while':
            lloop, lend = self.label(), self.label()
            ir.append(('L', lloop))
            self.cond_jump_false(s[1], ir, lend)
            self.loops.append((lend, lloop))
            self.stmt(s[2], ir)
            self.loops.pop()
            ir.append(('J', 'Jump', lloop))
            ir.append(('L', lend))
        elif k == 'for':
            init, cond, step, body = s[1], s[2], s[3], s[4]
            lloop, lend, lcont = self.label(), self.label(), self.label()
            if init:
                self.stmt(init, ir)
            ir.append(('L', lloop))
            if cond:
                self.cond_jump_false(cond, ir, lend)
            self.loops.append((lend, lcont))
            self.stmt(body, ir)
            self.loops.pop()
            ir.append(('L', lcont))
            if step:
                self.stmt_expr(step, ir)
            ir.append(('J', 'Jump', lloop))
            ir.append(('L', lend))
        elif k == 'break':
            ir.append(('J', 'Jump', self.loops[-1][0]))
        elif k == 'continue':
            ir.append(('J', 'Jump', self.loops[-1][1]))
        elif k == 'return':
            for _ in range(self.forin_depth):
                # leaving a for-in early: drain the rest of the enumeration (down to its null terminator)
                ldrain = self.label()
                ir.append(('L', ldrain))
                ir.append(self.P('null'))
                ir.append(('I', 'Equals2'))
                ir.append(('I', 'Not'))
                ir.append(('J', 'If', ldrain))
            if s[1] is None:
                ir.append(self.P('undef'))
            else:
                self.expr(s[1], ir)
            ir.append(('I', 'Return'))
        elif k == 'switch':
            self.switch(s, ir)
        elif k == 'with':
            self.expr(s[1], ir)
            body = []
            self.stmt(s[2], body)
            ir.append(('W', body))
        elif k == 'forin':
            self.forin(s, ir)
        else:
            raise CompileError('stmt %r' % (k,))

    def forin(self, s, ir):
        """for (x in obj): Enumerate2 pushes the keys (then null); register 0 is the scratch for the current key."""
        _, name, _is_var, obj, body = s
        lloop, lend = self.label(), self.label()
        self.expr(obj, ir)
        ir.append(('I', 'Enumerate2'))
        ir.append(('L', lloop))
        ir.append(('S', 0))
        ir.append(self.P('null'))
        ir.append(('I', 'Equals2'))
        ir.append(('J', 'If', lend))
        r = self.reg_of(name)
        if r is not None:
            ir.append(self.P('reg', 0))
            ir.append(('S', r))
            ir.append(('I', 'Pop'))
        else:
            ir.append(self.P('str', name))
            ir.append(self.P('reg', 0))
            ir.append(('I', 'SetVariable'))
        self.loops.append((lend, lloop))
        self.forin_depth += 1
        self.stmt(body, ir)
        self.forin_depth -= 1
        self.loops.pop()
        ir.append(('J', 'Jump', lloop))
        ir.append(('L', lend))

    def switch(self, s, ir):
        lend = self.label()
        cases = s[2]
        labels = [self.label() for _ in cases]
        self.expr(s[1], ir)
        tests = [c for c in cases if c[0] is not None]
        first = True
        default_label = None
        for (test, _), lab in zip(cases, labels):
            if test is None:
                default_label = lab
                continue
            if len(tests) > 1:
                if first:
                    ir.append(('S', 0))
                    first = False
                else:
                    ir.append(self.P('reg', 0))
            self.expr(test, ir)
            ir.append(('I', 'StrictEquals'))
            ir.append(('J', 'If', lab))
        ir.append(('J', 'Jump', default_label or lend))
        self.loops.append((lend, None))
        for (_, body), lab in zip(cases, labels):
            ir.append(('L', lab))
            self.block(body, ir)
        self.loops.pop()
        ir.append(('L', lend))

    # -- functions -----------------------------------------------------------------------------
    def function(self, name, params, body, anonymous=False, is_ctor=False, display=None):
        hint = self.next_hint()
        use_v1 = has_with(body) or (hint is not None and hint.kind == 'F1')
        outer = self.scope
        outer_loops, self.loops = self.loops, []
        outer_forin, self.forin_depth = self.forin_depth, 0
        sc = FnScope(params, hint, name)
        self.scope = sc
        ir = []
        if use_v1:
            sc.v1 = True
            for stmt in body:
                self.stmt(stmt, ir)
            self.scope, self.loops, self.forin_depth = outer, outer_loops, outer_forin
            return ('F1', name, params, ir)
        uses = set()
        scan_uses(body, uses)
        reg = 1
        flags = 0
        hflags = hint.flags if hint is not None and hint.flags is not None else None
        for sp, bit_preload, bit_suppress in (('this', 0x01, 0x02), ('arguments', 0x04, 0x08), ('super', 0x10, 0x20),
                                              ('_root', 0x40, 0), ('_parent', 0x80, 0), ('_global', 0x100, 0)):
            # a preloaded special may be unused in the body (the original still reserved its register)
            if (sp in uses) if hflags is None else bool(hflags & bit_preload):
                flags |= bit_preload
                sc.special[sp] = reg
                reg += 1
            else:
                flags |= bit_suppress
        sc_params = []
        if hint is not None and len(hint.params) == len(params):
            for (r, _n), pname in zip(hint.params, params):
                sc.vars[pname] = r
                sc_params.append((r, pname))
        else:
            for pname in params:
                sc.vars[pname] = reg
                sc_params.append((reg, pname))
                reg += 1
        maxreg = max([reg - 1] + [r for r, _ in sc_params])
        # FFDec names register locals _locN_
        loc_names = set()

        def collect(n):
            if isinstance(n, tuple):
                if n and n[0] == 'id' and re.fullmatch(r'_loc\d+_', n[1]):
                    loc_names.add(n[1])
                if n and n[0] == 'var':
                    for nm, _ in n[1]:
                        loc_names.add(nm)
                if n and n[0] == 'func':
                    return
                for c in n[1:]:
                    collect(c)
            elif isinstance(n, list):
                for c in n:
                    collect(c)

        collect(body)
        hint_locals = self.names.get(display or name or '', {})
        for nm in sorted(loc_names):
            if nm in sc.vars:
                continue
            if nm in hint_locals:
                sc.vars[nm] = hint_locals[nm]
                maxreg = max(maxreg, sc.vars[nm])
                continue
            m = re.fullmatch(r'_loc(\d+)_', nm)
            if m:
                sc.vars[nm] = int(m.group(1))
                maxreg = max(maxreg, sc.vars[nm])
            elif hint_locals and nm in hint_locals:
                sc.vars[nm] = hint_locals[nm]
                maxreg = max(maxreg, sc.vars[nm])
        for stmt in body:
            self.stmt(stmt, ir)
        nregs = hint.regs if hint is not None and hint.regs else maxreg + 1
        if hint is not None and hint.flags is not None:
            flags = hint.flags
        self.scope, self.loops, self.forin_depth = outer, outer_loops, outer_forin
        return ('F2', name, nregs, flags, sc_params, ir)

    # -- classes -------------------------------------------------------------------------------
    def dotted_ast(self, name):
        parts = name.split('.')
        e = ('id', parts[0])
        for p in parts[1:]:
            e = ('member', e, p)
        return e

    def compile_class_legacy(self, cls):
        """The older ("Flash MX 2004 / v2 component") class pattern used by the stock mx.* framework: the constructor
        is kept in register 1 and the prototype (`new Super()`, no Extends action) in register 2; statics are assigned
        on the constructor, instance methods and field initialisers on the prototype; accessors are __get__x /
        __set__x methods plus addProperty calls at the end."""
        _, kind, name, ext, impls, members, imports = cls
        parts = name.split('.')
        ir = []
        self.package_prelude(parts, ir)
        lend = self.label()
        self.path_get(parts, ir)
        ir.append(('I', 'Not'))
        ir.append(('I', 'Not'))
        ir.append(('J', 'If', lend))
        ctor = None
        for m in members:
            if m[0] == 'method' and not m[1] and m[2] == parts[-1]:
                ctor = m
        self.path_get(parts[:-1], ir, as_var=True)
        ir.append(self.P('str', parts[-1]))
        if ctor is not None:
            ir.append(self.function('', ctor[3], ctor[4] or [], is_ctor=True, display=ctor[2]))
        else:
            ir.append(self.function('', [], []))
        ir.append(('S', 1))
        ir.append(('I', 'SetMember'))
        if ext:
            self.path_get(parts, ir, as_var=True)
            ir.append(self.P('str', 'prototype'))
            self.new(('new', self.dotted_ast(ext), []), ir)
            ir.append(('S', 2))
            ir.append(('I', 'SetMember'))
        else:
            ir.append(self.P('reg', 1))
            ir.append(self.P('str', 'prototype'))
            ir.append(('I', 'GetMember'))
            ir.append(('S', 2))
            ir.append(('I', 'Pop'))
        accessors = {}      # (static, property) -> {'get': bool, 'set': bool}
        for m in members:
            if m[0] != 'method' or m is ctor:
                continue
            _, static, mname, params, body, accessor = m
            holder = 1 if static else 2
            if accessor:
                accessors.setdefault((static, mname), {})[accessor] = True
                mname = '__%s__%s' % (accessor, mname)
            if accessor == 'set' and any(o[0] == 'method' and o[2] == m[2] and o[1] == static and o[5] == 'get'
                                         for o in members):
                # the original compiler makes a setter return the value of its getter
                body = list(body or []) + [('return', ('call', ('member', ('this',), '__get__' + m[2]), [])),
                                              ('deadpop',)]
            ir.append(self.P('reg', holder))
            ir.append(self.P('str', mname))
            ir.append(self.function('', params, body or [], display=mname))
            ir.append(('I', 'SetMember'))
        for m in members:
            if m[0] != 'field':
                continue
            for fname, init in m[2]:
                if init is None:
                    continue
                ir.append(self.P('reg', 1 if m[1] else 2))
                ir.append(self.P('str', fname))
                self.expr(init, ir)
                ir.append(('I', 'SetMember'))
        for (static, pname), have in sorted(accessors.items(), key=lambda kv: (not kv[0][0], kv[0][1])):
            holder = 1 if static else 2
            if 'set' in have:
                ir.append(self.P('reg', holder))
                ir.append(self.P('str', '__set__' + pname))
                ir.append(('I', 'GetMember'))
            else:
                self.next_hint()
                ir.append(('F1', '', [], []))
            ir.append(self.P('reg', holder))
            ir.append(self.P('str', '__get__' + pname))
            ir.append(('I', 'GetMember'))
            ir.append(self.P('str', pname))
            ir.append(self.P('int', 3))
            ir.append(self.P('reg', holder))
            ir.append(self.P('str', 'addProperty'))
            ir.append(('I', 'CallMethod'))
        ir.append(self.P('int', 1))
        ir.append(self.P('null'))
        self.path_get(parts, ir, as_var=True)
        ir.append(self.P('str', 'prototype'))
        ir.append(('I', 'GetMember'))
        ir.append(self.P('int', 3))
        ir.append(self.P('str', 'ASSetPropFlags'))
        ir.append(('I', 'CallFunction'))
        ir.append(('L', lend))
        ir.append(('I', 'Pop'))
        ir.append(('I', 'End'))
        return ir

    def package_prelude(self, parts, ir):
        # ensure package objects exist: _global.a, _global.a.b ...
        for i in range(len(parts) - 1):
            path = parts[:i + 1]
            lend = self.label()
            self.path_get(path, ir)
            ir.append(('I', 'Not'))
            ir.append(('I', 'Not'))
            ir.append(('J', 'If', lend))
            self.path_get(path[:-1], ir)
            ir.append(self.P('str', path[-1]))
            ir.append(self.P('dbl', 0.0))
            ir.append(self.P('str', 'Object'))
            ir.append(('I', 'NewObject'))
            ir.append(('I', 'SetMember'))
            ir.append(('L', lend))
            ir.append(('I', 'Pop'))

    def compile_class(self, cls):
        _, kind, name, ext, impls, members, imports = cls
        parts = name.split('.')
        ir = []
        # ensure package objects exist: _global.a, _global.a.b ...
        for i in range(len(parts) - 1):
            path = parts[:i + 1]
            lend = self.label()
            self.path_get(path, ir)
            ir.append(('I', 'Not'))
            ir.append(('I', 'Not'))
            ir.append(('J', 'If', lend))
            self.path_get(path[:-1], ir)
            ir.append(self.P('str', path[-1]))
            ir.append(self.P('dbl', 0.0))
            ir.append(self.P('str', 'Object'))
            ir.append(('I', 'NewObject'))
            ir.append(('I', 'SetMember'))
            ir.append(('L', lend))
            ir.append(('I', 'Pop'))
        lend = self.label()
        self.path_get(parts, ir)
        ir.append(('I', 'Not'))
        ir.append(('I', 'Not'))
        ir.append(('J', 'If', lend))
        # constructor
        ctor = None
        methods = []
        for m in members:
            if m[0] == 'method' and not m[1]:
                if m[2] == parts[-1]:
                    ctor = m
                else:
                    methods.append(m)
        packaged = len(parts) > 1
        self.path_get(parts[:-1], ir, as_var=packaged)
        ir.append(self.P('str', parts[-1]))
        if ctor is not None:
            ir.append(self.function('', ctor[3], ctor[4] or [], is_ctor=True, display=ctor[2]))
        else:
            ir.append(self.function('', [], []))
        ir.append(('S', 0))
        ir.append(('I', 'SetMember'))
        if ext:
            self.path_get(parts, ir, as_var=packaged)
            self.path_get(ext.split('.'), ir, as_var=True)
            ir.append(('I', 'Extends'))
        ir.append(self.P('reg', 0))
        ir.append(self.P('str', 'prototype'))
        ir.append(('I', 'GetMember'))
        ir.append(('S', 1))
        ir.append(('I', 'Pop'))
        for m in methods:
            ir.append(self.P('reg', 1))
            ir.append(self.P('str', m[2]))
            ir.append(self.function('', m[3], m[4] or [], display=m[2]))
            ir.append(('I', 'SetMember'))
        ir.append(self.P('int', 1))
        ir.append(self.P('null'))
        self.path_get(parts, ir, as_var=packaged)
        ir.append(self.P('str', 'prototype'))
        ir.append(('I', 'GetMember'))
        ir.append(self.P('int', 3))
        ir.append(self.P('str', 'ASSetPropFlags'))
        ir.append(('I', 'CallFunction'))
        ir.append(('L', lend))
        ir.append(('I', 'Pop'))
        ir.append(('I', 'End'))
        return ir

    def path_get(self, parts, ir, last_global_var=False, as_var=False):
        """Push the value of _global.a.b.c (or, as_var, of the bare path a.b.c)."""
        if as_var:
            ir.append(self.P('str', parts[0]))
            ir.append(('I', 'GetVariable'))
            for p in parts[1:]:
                ir.append(self.P('str', p))
                ir.append(('I', 'GetMember'))
            return
        ir.append(self.P('str', '_global'))
        ir.append(('I', 'GetVariable'))
        for p in parts:
            ir.append(self.P('str', p))
            ir.append(('I', 'GetMember'))

    def compile_script(self, stmts):
        ir = []
        self.scope = FnScope([], None, '')
        self.scope.v1 = True
        self.scope.names = self.names.get('script', {})
        for s in stmts:
            self.stmt(s, ir)
        ir.append(('I', 'End'))
        return ir


# --- emission -------------------------------------------------------------------------------------
def count_strings(ir, counts):
    for it in ir:
        if it[0] == 'P' and it[1] == 'str':
            counts[it[2]] = counts.get(it[2], 0) + 1
        elif it[0] in ('F2',):
            count_strings(it[5], counts)
        elif it[0] == 'F1':
            count_strings(it[3], counts)
        elif it[0] == 'W':
            count_strings(it[1], counts)


class Emitter:
    def __init__(self, use_pool=True):
        self.pool = []
        self.index = {}
        self.lines = []
        self.use_pool = use_pool

    def const(self, s):
        if s not in self.index:
            self.index[s] = len(self.pool)
            self.pool.append(s)
        return self.index[s]

    def fmt(self, p):
        _, kind, v = p
        if kind == 'str':
            if not self.use_pool:
                return json.dumps(v, ensure_ascii=False)
            i = self.const(v)
            return ('c8:%d' if i < 256 else 'c16:%d') % i
        if kind == 'int':
            return 'i:%d' % v
        if kind == 'dbl':
            return 'd:' + repr(float(v))
        if kind == 'reg':
            return 'r:%d' % v
        if kind == 'bool':
            return 'true' if v else 'false'
        if kind == 'null':
            return 'null'
        return 'undefined'

    def emit(self, ir, indent=''):
        i = 0
        while i < len(ir):
            it = ir[i]
            t = it[0]
            if t == 'P':
                group = []
                while i < len(ir) and ir[i][0] == 'P':
                    group.append(self.fmt(ir[i]))
                    i += 1
                self.lines.append(indent + 'Push ' + ', '.join(group))
                continue
            if t == 'I':
                self.lines.append(indent + it[1])
            elif t == 'R':
                self.lines.append(indent + it[1])
            elif t == 'S':
                self.lines.append(indent + 'StoreRegister %d' % it[1])
            elif t == 'L':
                self.lines.append(indent + it[1] + ':')
            elif t == 'J':
                self.lines.append(indent + '%s %s' % (it[1], it[2]))
            elif t == 'F2':
                _, name, nregs, flags, params, body = it
                ps = ', '.join('%d:%s' % (r, json.dumps(n)) for r, n in params)
                self.lines.append(indent + 'DefineFunction2 %s regs=%d flags=0x%04x [%s] {' % (json.dumps(name), nregs, flags, ps))
                self.emit(body, indent + '  ')
                self.lines.append(indent + '}')
            elif t == 'F1':
                _, name, params, body = it
                self.lines.append(indent + 'DefineFunction %s [%s] {' % (json.dumps(name), ', '.join(json.dumps(p) for p in params)))
                self.emit(body, indent + '  ')
                self.lines.append(indent + '}')
            elif t == 'W':
                body = it[1]
                self.lines.append(indent + 'With {')
                self.emit(body, indent + '  ')
                self.lines.append(indent + '}')
            i += 1


def compile_to_asm(src, hints=None, names=None):
    """Compile one source. A script may be split into independently compiled units with `// @unit` lines
    (the original tool compiled some component init scripts as several pieces and concatenated them)."""
    units = re.split(r'^[ \t]*//[ \t]*@unit[ \t]*$', src, flags=re.M)
    if len(units) > 1:
        body = []
        for u in units:
            lines = compile_unit(u, hints, names).rstrip(chr(10)).split(chr(10))
            if lines and lines[-1] == 'End':
                lines = lines[:-1]
            body.extend(lines)
        return chr(10).join(body) + chr(10) + 'End' + chr(10)
    return compile_unit(src, hints, names)


def compile_unit(src, hints=None, names=None):
    tree = parse(src)
    c = Compiler(hints, names)
    if tree[0] == 'class':
        # the stock Macromedia components (mx.*) were built with the older class scheme
        ir = c.compile_class_legacy(tree) if tree[2].startswith('mx.') else c.compile_class(tree)
    else:
        ir = c.compile_script(tree[1])
    counts = {}
    count_strings(ir, counts)
    # The original compiler only builds a constant pool when some string is used more than once
    # (class definitions always have one).
    em = Emitter(use_pool=any(n > 1 for n in counts.values()) or tree[0] == 'class')
    em.emit(ir)
    pool = ''
    if em.use_pool:
        pool = 'ConstantPool ' + ', '.join(json.dumps(s, ensure_ascii=False) for s in em.pool) + '\n'
    return pool + '\n'.join(em.lines) + '\n'
