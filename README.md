# The Right Mix: decompilation, tools and native ports

*The Right Mix* (also catalogued by Flashpoint as *Bartender The Right Mix*) is a 2004 Flash cocktail-mixing game (SWF 7,
ActionScript 2, 600 x 440 @ 18 fps) made for Land Securities by Liquid Light and Plugin Media. This project contains

1. **readable ActionScript 2 source of the game's 40 game-specific scripts**, which a custom compiler turns back into the original
   bytecode, byte for byte (a *bytecode-matching decompilation*; see exactly how far that goes in [docs/MATCHING.md](docs/MATCHING.md)).
   The file's other 42 scripts are Macromedia's stock component library; they are not published here, and the build tool keeps them
   as they are in your own copy;
2. **the tools**: a lossless SWF project layer, an exact AVM1 assembler/disassembler and that AS2 compiler ([docs/COMPILER.md](docs/COMPILER.md));
3. **native ports** (Flutter/Dart, no Flash player, no emulator) for **Windows 11 x64** and **Android 7.0 - 17**, with display
   options the original never had ([docs/PORT.md](docs/PORT.md));
4. **a build tool** that makes both ports from *your own* copy of the game, and the verification method with a summary of results ([docs/VERIFICATION.md](docs/VERIFICATION.md)).

> **The game itself is not in this repository**, and neither is any artwork, sound or animation extracted from it. The local SWF copy
> used for this project was sourced from Flashpoint Archive. It is 693,558 bytes with SHA-256
> `ede221ad99e031732a049409278ce45bc1602706045b95ab83756e72af8f23a7`. Flashpoint's [catalog record](https://flashpointproject.github.io/flashpoint-database/search/#a64d77ab-bff7-c8f5-8c22-b6bd42343886)
> lists the title as *The Right Mix* and its alternate title as *Bartender The Right Mix*. The hash records the local file's identity;
> the SWF itself is not included. Builds made from your own copy contain the game's assets. See [docs/LEGAL.md](docs/LEGAL.md).

## Build the ports yourself

```
pip install -r requirements.txt
python rightmix.py doctor                                   # what is installed / missing
python rightmix.py setup --accept-android-licenses          # downloads Flutter, JDK, Android SDK if you lack them
python rightmix.py build --swf C:\path\to\bartender.swf     # -> dist/TheRightMix-windows-x64.zip and TheRightMix-android.apk
```

Or double-click `rightmix-gui.bat` (Windows) / run `python rightmix.py gui`. Details, requirements and troubleshooting:
[docs/BUILDING.md](docs/BUILDING.md). The build first rebuilds the game file from our source and requires it to be byte-identical to
yours (decompressed), so a successful build also *is* the matching check.

## How "matching" is the decompilation?

| Claim | Status |
|---|---|
| The 40 game-specific scripts (48,138 of the file's 136,672 bytes of AVM1 bytecode) compile from `src/as2/` to exactly the original bytes | **Yes** |
| The other 42 scripts (88,534 bytes, Macromedia's stock `mx.*` component library) | **Not published.** They are carried over from your own file when rebuilding; the author matched them privately (82 of 82), but that cannot be checked from this repository |
| The whole file rebuilds byte-identically from our scripts, your file's 42 component scripts and the untouched non-code data (decompressed) | **Yes**, SHA-256 `916f7178...ff80`, 980,066 bytes |
| A changed source line changes the output (the compiler really compiles) | **Yes**, 38 of 38 mutation tests on the published sources |
| The compiler works out the original compiler's register allocation by itself | **No**: the register count, preload flags and parameter registers of the 84 functions in the published sources are read from the original and recorded in `src/as2/hints.json` |
| The source text is the authors' original source | **No**: local-variable names, comments and formatting are ours; only parameter names (stored in the bytecode) are original |
| The original *compressed* file is reproduced | **No** (unknown deflate encoder); the decompressed content is |
| Graphics, sound, fonts, timelines are decompiled | **No**: kept as raw data and extracted from your copy at build time |
| The compiler works on other SWFs | **Not claimed**; it was made for this file |

## What the ports add

Smooth motion at 60/120 Hz (the logic stays at the original 18 Hz), integer scaling, ultrawide backdrop, safe areas,
full screen, correct sound timing (the original's MP3 encoder-delay trimming and volume envelopes), single-finger input,
pause/resume handling, and an app icon from the game's artwork. The ports were checked against the original running in an independent
Flash emulator: 94 scripted games, 140,831 frames, every traced value identical including the random-number state
([docs/VERIFICATION.md](docs/VERIFICATION.md), which also lists what is **not** verified: real devices, Adobe's own player, hands-on
feel at 120 Hz).

## Repository layout

```
LICENSE, LICENSING.md, THIRD_PARTY_NOTICES.md, third_party/licenses/   licence (MIT, scoped), scope, third-party notices
src/as2/            readable ActionScript 2 source of the 40 game-specific scripts, hints.json (register data), names.json (NOT under our MIT grant: see NOTICE.md)
reference/          hashes of the original file (no game data)
tools/swfproj/      lossless SWF <-> project, exact assembler/disassembler
tools/as2c/         the AS2 compiler and its helpers
tools/assetc/       SWF -> app assets (bitmaps, sounds, vector shapes, timelines), no external decompiler
tools/build.py, verify_matching.py   rebuild + independent audit of the matching claim
tools/diff/ tools/windows/ tools/android/ tools/render/   verification harnesses (optional; see docs)
tools/publish_check.py              guards against publishing game data
port/               the Flutter project (code only; assets are generated locally)
docs/               MATCHING, COMPILER, PORT, BUILDING, VERIFICATION, LEGAL and recorded results
rightmix.py, rightmix_gui.py, rightmix.bat, rightmix.sh   the build tool
```

## Licence

The project's own tools, port code and documentation are released under the **MIT licence** ([LICENSE](LICENSE),
Copyright (c) 2026 The Right Mix decomp contributors). The licence is **scoped**; [LICENSING.md](LICENSING.md) lists exactly what it covers.
In particular:

* **`src/as2/` is not under our MIT grant.** It is reconstructed from the game file (the game's own scripts) and remains
  third-party material; see [src/as2/NOTICE.md](src/as2/NOTICE.md).
* The game, and anything built from it with `rightmix.py`, is not licensed by this project and must not be redistributed.
* miniaudio, the Gradle wrapper and the Flutter template files keep their own licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
  texts in [third_party/licenses/](third_party/licenses/).

## How this was made

The decompilation, the AS2 compiler and SWF tooling, the Windows/Android ports, the build tool, the verification work and the
documentation were developed with **Claude Sonnet 5.5** (Anthropic, High effort setting) in Claude Code, working from start to
finish under the direction of the project owner. As with any generated work, check the claims against the evidence: what is
and is not verified is stated in [docs/MATCHING.md](docs/MATCHING.md) and [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Credits

The game, its artwork, music and the "Land Securities" branding belong to their owners (Land Securities, Liquid Light, Plugin
Media). This project claims no ownership of the game or of third-party code. Third-party components used by the tools and ports
are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [docs/LEGAL.md](docs/LEGAL.md).
