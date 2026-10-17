# Building the Windows and Android ports from your own `bartender.swf`

This repository does **not** contain the game. You need your own copy of `bartender.swf` (the 693,558-byte original; its
SHA-256 is `ede221ad99e031732a049409278ce45bc1602706045b95ab83756e72af8f23a7`). Everything is built on your PC; nothing is
uploaded and your file is never modified. The builds contain the game's artwork and sound, so they are for your own use.

## 1. Requirements

| Needed for | What | How |
|---|---|---|
| everything | Python 3.9+ and Pillow | `pip install -r requirements.txt` |
| everything | a C compiler (builds a tiny MP3 converter) | Windows: Visual Studio Build Tools, workload "Desktop development with C++"; Linux/macOS: gcc or clang |
| Windows port | Windows 10/11 64-bit, Visual Studio Build Tools (same workload) | `winget install Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"` |
| both | Flutter 3.47.7 | `python rightmix.py setup` downloads it into `.rightmix/toolchain/` (or use your own) |
| Android port | JDK 17+ and the Android SDK command-line tools, with licenses accepted | `python rightmix.py setup --accept-android-licenses` (read the licenses first: https://developer.android.com/studio/terms) |

`python rightmix.py doctor` shows what is found and what is missing. It looks for tools in `.rightmix/toolchain/`, then in
`RIGHTMIX_FLUTTER` / `FLUTTER_ROOT`, `JAVA_HOME`, `ANDROID_HOME` / `ANDROID_SDK_ROOT`, the usual install locations and `PATH`.

## 2. Build

```
python rightmix.py doctor
python rightmix.py setup --accept-android-licenses        # only if something is missing
python rightmix.py build --swf C:\path\to\bartender.swf   # both ports (Windows only builds the .exe on Windows)
python rightmix.py build --swf bartender.swf --android    # just the APK
python rightmix.py build --swf bartender.swf --windows    # just the .exe
```

Windows users can also double-click `rightmix-gui.bat` for the same thing in a small window.

What `build` does:

1. checks that your file is the expected one (SHA-256, or the SHA-256 of its decompressed contents);
2. takes it apart into `decomp/` (tools/swfproj; local);
3. compiles `src/as2` with our compiler and rebuilds the SWF, which must be **byte-identical** to your file once decompressed
   (this is the matching-decompilation check, see [MATCHING.md](MATCHING.md)); `--skip-matching` skips it;
4. extracts bitmaps and sounds natively (no external decompiler) and converts them into `port/assets/` (trimmed WAV sounds with
   the volume envelopes baked in, PNG/JPEG images, `game.json` with all vector shapes, timelines and text);
5. renders the app icon from the game's artwork;
6. `flutter build windows --release` and/or `flutter build apk --release`, then packages into `dist/`.

Outputs (in `dist/`): `TheRightMix-windows-x64.zip` (and the unpacked `TheRightMix/` folder, with the Visual C++ runtime DLLs next to
the exe) and `TheRightMix-android.apk` (signed with the Flutter debug key: enable "install unknown apps" to install it).

## 3. Running the tests

```
cd port
flutter test                      # needs the generated assets (run `rightmix.py build` or its first five steps once)
python ../tools/verify_matching.py   # per-unit audit with mutation tests (RIGHTMIX_SWF=<your swf>)
```

Expected from a clean checkout: **71 tests pass, 1 is skipped**. The skipped one is the sprite comparison against FFDec reference frames,
which needs optional local data and says so. The scripted-playthrough test has no recorded golden trace in a public checkout (traces
record game state and are not published), so it checks determinism only and prints a `NOTE`; `RIGHTMIX_RECORD_GOLDEN=1` records one locally.
The scenario files `tools/diff/plans.json` / `scenarios*.json` (button presses only) are published, and `flutter test` re-resolves
`scenarios.json` from `plans.json`, reproducing the published file exactly. Test outputs go to `build/` (git-ignored).

Optional, heavier checks (not needed to build): the differential test against the original needs Ruffle
(`tools/diff/run_diff.py`), the Android device tests need an emulator (`tools/android/verify_device.py`), the Windows checks drive
the built exe (`tools/windows/*.py`). See [VERIFICATION.md](VERIFICATION.md) for what each one proves.

## 4. Troubleshooting

* *"This is not the file the project was made for"*: your `bartender.swf` differs from the one the source matches (the project matches one
  specific release). `--force` continues, but the matching check will fail and the ports may behave differently.
* *Flutter asks to accept analytics / runs slowly the first time*: normal, it downloads its Dart SDK and engine artifacts on first use.
* *Android: "licenses not accepted"*: run `python rightmix.py setup --accept-android-licenses`.
* *Windows: "no C compiler found"*: install the Build Tools workload above, then open a new terminal.
* *The exe does not start on another PC*: the zip includes the Visual C++ runtime DLLs it was built against; if they were missing
  on the build PC, install "Microsoft Visual C++ Redistributable 2015-2022 (x64)" on the other PC.
* *Antivirus flags the exe*: it is an unsigned local build; check the hash of what you built.
