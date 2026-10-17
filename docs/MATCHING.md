# How "matching" is this decompilation? (exact scope and limits)

Short answer: **all 40 game-specific scripts compile from the readable source in `src/as2/` to exactly the bytecode in the
original file, and the whole file is rebuilt byte-identically (uncompressed) from those scripts, the original bytecode of the 42
stock Macromedia component scripts, and the untouched non-code data.** That is a real bytecode match for the game's own code.
The 42 Macromedia units are **not** published in this repository (see below); the author's private archive also matches them. It is **not** the strongest kind of "matching decompilation",
because two kinds of input to the compiler come from the original file instead of being re-derived (see
[What is not derived](#what-is-not-derived)). Read this page before describing the project as "a matching decomp".

## What was decompiled

`bartender.swf` is a Flash movie (SWF version 7) whose game code is ActionScript 2, compiled to **AVM1 bytecode** (not CPU
machine code). The file contains exactly **82 script units**, totalling **136,672 bytes** of bytecode:

| Kind of unit | Units | Bytes | Source in this repository |
|---|---:|---:|---|
| Game classes (`CocktailGame`, `BarmanHand`, `Bottle`, `Additive`, `Shaker`, `Particle`, `DoubleParticleSpawner`, `reactionSplashParticleSpawner`, `Cam`, `net.pluginmedia.PIM_Colour`) | 10 | 46,017 | `src/as2/*.as`, `src/as2/net/...` |
| Game timeline / button / clip-event scripts | 30 | 2,121 | `src/as2/scripts/` |
| Macromedia's stock `mx.*` v2 component framework classes (not used by the game itself, but shipped inside the file) | 23 | 87,247 | **not published**; taken from your file at build time |
| Component registration stubs, `stop()` stubs, one button action | 19 | 1,287 | **not published**; taken from your file at build time |
| **Total** | **82** | **136,672** | 40 `.as` files published (48,138 bytes) |

"Game-specific" code is therefore **40 units / 48,138 bytes**; the other 42 units (88,534 bytes, 64.8 % of the bytecode) are
Macromedia's component library. They were left out of the public repository to publish less third-party source. When you build,
`tools/build.py` keeps those 42 scripts exactly as they are in your own `bartender.swf`, so the rebuilt file is still identical
to yours, but for those 42 units that identity is **inherited from your file, not demonstrated by compiling source**. The author
reconstructed and matched all 82 units privately (82 of 82, 136,672 of 136,672 bytes, 72 of 72 mutations detected); that archive is
not part of this repository and its result cannot be checked from here.

## What "matches" means here, checkable by anyone with the original file

1. **Per unit.** `python tools/verify_matching.py` parses the original bytecode straight out of your `bartender.swf`,
   compiles each `.as` file in a sandbox that has **no extracted data and no SWF**, and compares the bytes. Result recorded in
   `build/verification/matching_audit.md` (written locally, not published): **40 of 40 published units, 48,138 of 48,138 bytes
   identical**; the other 42 units are listed as "no source" (stock Macromedia components, not compared).
2. **Whole file.** `python rightmix.py verify --swf bartender.swf` (or `python tools/build.py` after extraction) compiles all
   40 sources, drops them into the lossless project of your file (which still holds the other 42 scripts as in your file) and rebuilds the SWF. The **decompressed** result has
   SHA-256 `916f7178aa5662e75699a848df2e99f74b5a89cb118930510de132ff5587ff80` (980,066 bytes) and must equal the original's
   (`reference/original.json`).
3. **The compiler really compiles.** The audit changes a numeric literal in each source file (38 mutations over the published
   files): in every case the
   output bytes change. So the matching bytes are produced from the source, not copied from the original.

What is **not** reproduced: the original *compressed* `.swf` file (693,558 bytes). It was written by an unknown deflate
encoder; the same content compressed with standard zlib differs in size by a few hundred bytes. The decompressed content,
which is what the Flash Player executes, is identical.

## What is not derived

These are the exact limits of the claim. They are data taken from the original, not rediscovered by our compiler:

1. **Register allocation and function headers (`src/as2/hints.json`).** AS2 functions compiled by Macromedia's tool use
   `DefineFunction2` with a register count, a set of "preload" flags (`this`, `arguments`, `super`, `_root`, `_parent`,
   `_global`) and a register number for each parameter. Macromedia's allocator is not documented and we did not reverse it.
   For each of the **84 functions in 12 scripts** of the published sources (the private full set: 454 functions in 35 scripts) the file records those header values, read out of the original, and the
   compiler is told to use them. They are constraints on the output, not an explanation of them. The file is versioned
   (`schema_version 1`) and content-hashed; `tools/build.py` refuses a modified copy.
2. **Parameter names.** Parameter names are stored in the bytecode (they cannot be renamed), so they keep the original authors'
   obfuscated-style `par_*` names.
3. **Everything that is not a script.** All shapes, bitmaps, sounds, fonts, text objects, sprite timelines, placements, labels and
   exports (2,673 top-level tags, 162 sprites) are kept as the original tag payloads and re-inserted unchanged
   (`tools/swfproj`). They are **not decompiled** into anything readable. This repository does not contain them: the build
   tool extracts them from your copy.

## What is ours (and therefore not "the original source")

* **Names of local variables** that live in registers (22 names in 7 scripts, `src/as2/names.json`) do not exist in the
  bytecode. We chose readable names; the compiler maps them back to the recorded registers.
* **Comments, documentation blocks, formatting** are ours.
* **Source shape.** For a given bytecode there are several source texts that compile to it. Ours is one that does
  (for example `i++` rather than `i = i + 1`, explicit `else { return false; }`, empty `else {}` blocks, a `break;` after
  the last `case`). It is not claimed to be the authors' text. Two non-AS2 conveniences were needed: a `// @unit` marker (two
  independently compiled halves of one script) and a pseudo call `gotoFrame(1)` for a lone `GotoFrame` action that
  plain AS2 cannot express.
* **The 23 `mx.*` classes** (private archive only) were written from decompiler output as a starting point and keep its
  register-local names (`_loc1_`, `_loc2_`, ...); they are matching but not made readable.

## The compiler is specific to this file

`tools/as2c` is a purpose-built ActionScript 2 to AVM1 compiler that reproduces what the original compiler produced for
**this** file's code (constant-pool order, merged multi-value `Push` actions, `0` as a double but other integers as int32,
`StoreRegister 0` for chained assignment, the `Not`/`If` jump shapes, `switch` as a `StrictEquals` chain, the `Extends` /
`ASSetPropFlags` class wrapper, the older prototype-based class scheme of the `mx.*` classes (implemented in the compiler, but
exercised by no published source), ...; see
[COMPILER.md](COMPILER.md)). It was validated against this one binary. It is **not** a general-purpose AS2 compiler and
makes no promise to match other SWF files.

## Where that places the project

| Level | This project |
|---|---|
| Bytecode of every **game-specific** script reproduced from published source, whole file rebuilt byte-identically | **Yes** (decompressed); the 42 stock Macromedia scripts are carried over from your file |
| Bytecode of all 82 scripts reproduced from source | **Yes, privately**; only 40 of the 82 are published |
| Compiler independent of the original binary | **Partly**: it needs the recorded register allocation and function flags |
| Source text equals the original authors' source | **No**, and it cannot be known |
| Reproduces the original compressed file | **No** |
| Non-code data decompiled to editable form | **No**, kept as raw data |
| Works on other SWFs | **Not claimed** |

Fair one-line description: *a bytecode-matching decompilation of the game-specific ActionScript in The Right Mix (40 units),
built with a custom compiler that is told the original's register allocation; the stock Macromedia components are carried over from the
user's own file.*

## Modifying the source

Edit `src/as2/*.as` (you can only change the 40 published units; the other 42 come from your file), then run `python tools/build.py` (after `python tools/swfproj/swfproj.py extract your.swf decomp`). A changed
program compiles (functions that have no recorded hint, such as newly added ones, use the compiler's own allocation) and the
rebuilt movie is written to `build/bartender_rebuilt.swf` (plus a compressed `.cws.swf`), but it is of course no longer
byte-identical: the script prints `BYTE-IDENTICAL ...: False` and exits with status 1, and `rightmix.py build` stops at that
check unless you pass `--skip-matching`. The hints are applied **by position** (the n-th function of a script), so
inserting or deleting a function before hinted ones can change how later functions compile; add new functions at the end of a
class to keep the rest identical. A new function compiled this way is verified to compile; behaviour of modified code is not
guaranteed by the matching result.
