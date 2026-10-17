# The tools: SWF project layer, assembler and the AS2 compiler (`tools/swfproj`, `tools/as2c`)

Everything here is plain Python 3 with no dependencies (Pillow is only used by the asset tools). Nothing in these tools
contains or downloads game data; they work on a `bartender.swf` that you supply.

## Pipeline at a glance

```
bartender.swf ──swfproj extract──▶ decomp/            (local, git-ignored; created on your PC)
                                    ├─ swf.json        every tag in order (long/short headers, ids, names, small payloads inline)
                                    ├─ payload/        every non-script tag, byte for byte (shapes, bitmaps, sounds, fonts, ...)
                                    └─ asm/            every script as editable assembly text (.as2asm), one line per instruction

src/as2/*.as ──tools/as2c──▶ assembly text ──as2asm.assemble──▶ bytecode
hints.json + names.json  ─┘

decomp/ with the 40 compiled scripts replacing asm/ (the other 42 keep your file's bytecode) ──swfproj build──▶ rebuilt SWF (decompressed bytes identical to the original)
```

`python tools/build.py` does the second half and compares the result with the recorded hashes in `reference/original.json`.

## `tools/swfproj` (lossless container layer)

| File | Role |
|---|---|
| `swfio.py` | Reads/writes the SWF container: header, zlib (CWS) or plain (FWS), the tag stream including nested sprites; `write(parse(x)) == x` bit-exact for the decompressed form. |
| `as2asm.py` | **Exact** disassembler / assembler for AVM1 actions. `assemble(disassemble(b)) == b` for every script of this game. One instruction per line, nothing normalised (constant-pool indices, push types, dead code and jump offsets are kept); unknown actions are emitted as `Raw 0xNN hex...` which also round-trips. Jump targets are written as labels. |
| `swfproj.py` | `extract` (SWF → project folder), `build` (project → SWF), `verify` (round trip). Scripts (DoAction, DoInitAction, button actions, clip events) become `.as2asm`; every other tag payload is kept verbatim, so tag order, long/short headers and oddities such as the 1,917 duplicate `barfront` export entries survive. |

## `tools/as2c` (the ActionScript 2 compiler)

### What it is

A compiler from the **subset of ActionScript 1/2 used by this game and by the Macromedia v2 components** to AVM1 assembly, designed
to emit what Macromedia's compiler (Flash MX 2004 era) emitted for this file, not to be an optimising or general compiler.

| File | Role |
|---|---|
| `parser.py` | Lexer and recursive-descent parser producing plain tuples (expressions and statements, classes with `extends` / `static` / `get` / `set`, `with`, `for..in`, `switch`, `trace`, ...). |
| `compiler.py` | Code generator (~1,000 lines): a small IR (`('P',...)` pushes, labels, jumps, `DefineFunction2` blocks) plus an emitter that decides constant-pool use, push merging and register use. |
| `gen_hints.py` | Reads the `DefineFunction`/`DefineFunction2` headers of the *original* assembly and writes `src/as2/hints.json` (versioned, hashed). The only step that reads the original's code to produce compiler input. |
| `match.py`, `report.py` | Compile one source / every source and diff against the original assembly (development aids). |
| `deobfuscate.py`, `document.py`, `seed_scripts.py`, `regstudy.py` | **Provenance only** (how the readable sources were produced and how register use was studied). They need decompiler output that is not part of this repository and are not used by any build. |

### Output behaviours reproduced (found by diffing against the original, one by one)

* constant pool: built only when some string occurs more than once (class scripts always have one), in first-use order;
* adjacent `Push`es merged into one multi-value `Push`; `0` pushed as a double, other integers as int32; strings through the pool;
* chained assignment `a = b = c` with `StoreRegister 0`; post/pre increment forms; `i++` as a statement vs. as a value;
* conditionals as `Not` / `If` jump pairs of a fixed shape; loops with the original's label layout;
* `switch` as a `StrictEquals` chain with the original's default handling;
* class definitions of the AS2 compiler: `Extends`, `ASSetPropFlags`, `prototype`, statics, `__get__`/`__set__` + `addProperty`
  accessors; and the **older** prototype-based scheme the stock `mx.*` classes were compiled with (a second code path; it was used to match the 23 `mx.*` classes in the author's private archive, and no published source exercises it);
* `DefineFunction` (no registers) where `with` is used, `DefineFunction2` elsewhere with preload flags from the hints;
* legacy global functions turned into dedicated actions (`removeMovieClip`, `stop`, `play`, `getTimer` -> `GetTime`, ...);
* `for..in` with the original's enumerate/pop dance, dead `Pop` after certain statements (`deadpop`).

### Inputs that are data, not logic

* `src/as2/hints.json`: for each function, in order of appearance within its script: kind (`F1`/`F2`), register count, flags,
  and the register of each parameter. 454 functions in 35 scripts. `_meta.content_sha256` guards it.
* `src/as2/names.json`: which register each readable local-variable name lives in (22 names, 7 scripts); locals are
  anonymous in bytecode, so these names are free to change.

Functions that have no hint (new ones you add) get the compiler's own allocation.

### Source conventions required to match

Because the compiler must reproduce byte-exact output, a few spellings matter: `i++` where the original did `i++`, explicit
`else { return false; }` where the original had one, a `break;` after the last `case`, parameter names unchanged (`par_*` are
in the bytecode), `// @unit` between two pieces of a script that the original tool compiled separately, and the pseudo call
`gotoFrame(1)` for a lone `GotoFrame` action. Comments and local-variable names are free.

### Verification tools

* `tools/build.py`: compile everything, rebuild, compare (hashes; also against your SWF directly when `RIGHTMIX_SWF` is set).
* `tools/verify_matching.py`: the independent audit: parses the original's bytecode from the SWF, compiles in a sandbox with no
  extracted data, compares every unit, then runs 72 literal-mutation tests (each must change the output).

### Known limits

* Only the language subset that occurs in this file is implemented; other AS2 constructs raise a compile error.
* Not tested on any other SWF; it makes no claim of matching other programs.
* Error messages are those of a development tool, not of a product.
