# Notice: `src/as2/` is reconstructed third-party code

**This directory is not covered by the MIT licence of this repository, and no licence is granted for it by the project.**

## What it is

`src/as2/` holds readable ActionScript 2 source for the 40 game-specific scripts inside the Flash game *The Right Mix* (also catalogued as
*Bartender The Right Mix*; made for Land Securities by Liquid Light and Plugin Media, 2004). The text was **reconstructed from the
compiled game file** by decompilation and manual work, so that our compiler (`tools/as2c`) can turn it back into the same bytecode.
It contains:

* **the game's own scripts** (40 game-specific units). The rights belong to the game's authors/owners.
* `hints.json` and `names.json`: compiler hints and name tables derived from the same compiled file (register counts, preload flags and
  parameter names recorded in the original bytecode).

The game file also embeds Macromedia/Adobe's stock `mx.*` v2 component library (42 further script units). Its source is **not**
published in this repository; when you build, those units are taken unchanged from your own copy of the game.

What is ours here is limited to the **decompilation effort itself**: local variable names, comments and formatting invented by us,
because that information is not stored in the compiled file. This does **not** make us the owner of the underlying code, and we do not
claim to be.

## What this means for you

* The project does **not** grant you any right to use, copy, modify or redistribute this material. The authors and owners of the
  original code keep all their rights.
* It is published for **study, interoperability research and preservation** of a game whose original distribution has ended,
  and so that the claim "this source compiles back to the original bytecode" can be checked by anyone who owns a copy of the game.
* Do not use it commercially, do not present it as original or as the work of the project, and do not assume that the licence in
  `/LICENSE` applies to it.
* Redistribution is at your own responsibility and risk. Check the rights position yourself.

## Removal

If you hold rights in any of this material and want it taken down, contact the repository owner (open an issue on the repository);
the affected files will be removed promptly. The tools and ports do not depend on keeping this folder public: anyone with their own
copy of the game can regenerate equivalent files with the tools in `tools/`.

## Related

* [`/LICENSING.md`](../../LICENSING.md): which parts of the repository are under which terms.
* [`/docs/LEGAL.md`](../../docs/LEGAL.md): what the repository contains and does not contain.
* [`/docs/MATCHING.md`](../../docs/MATCHING.md): exactly what "matching" means here and what it does not mean.
