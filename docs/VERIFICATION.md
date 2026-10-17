# Verification report

Scope of this pass: independent checks of the matching decompilation, behavioural parity of the Dart port with the
original game, rendering, Android behaviour and code layering. The 42 stock `mx.*` component units are not part of
the published source (see MATCHING.md), and the existing assembly-level matches (`decomp/asm`) were left untouched. Nothing here claims full
equivalence; the "Unverified" and "Risks" sections say what is not covered.

Every number below comes from a command listed in "Reproduce". The **recorded outputs** of those runs (audit reports, per-frame
traces, result tables, screenshots, device logs, the sprite-comparison CSV) are written to `build/` or the git-ignored `docs/verification/`
on your machine and are **not part of the published repository**, because they record state of the original game. Where the
"Evidence" column below names a file in `docs/verification/` or a trace archive, it is the author's local copy of that output: re-run the
command to produce your own. What *is* published are the inputs and tools that produce them (`tools/diff/plans.json`,
`tools/diff/scenarios*.json` (frame-timed button presses only, no expected values), the harness scripts and the Dart tests).

## Publishing and the build tool (added last)

The repository is published **without the game**: `src/as2`, the tools, the ports as code, docs and result files only. Everything derived from the game
(`decomp/`, `port/assets/`, icons, screenshots, renderings, builds) is git-ignored, and `tools/publish_check.py` refuses to pass if any
such file, any file with a Flash signature, any image/audio/archive outside a short allow-list, or any machine-specific path is about to be published.
`rightmix.py` joins that repository with the user's own `bartender.swf`.

| Check | Result |
|---|---|
| Acceptance build: only the files `publish_check` lists (the published files) copied to an empty folder, the SWF in another folder, `python rightmix.py build --swf ...` | all 6 steps pass for **both** ports; matching check passes |
| Assets extracted natively (no FFDec, no Java) versus the earlier FFDec-based ones | `game.json` identical, all 34 sound files byte-identical, images identical on every visible pixel (the 22 images that differ only differ in fully transparent pixels) |
| Windows exe built in that clean copy, run silently on the left monitor | window, focus, F1 panel, F11 full screen and back, settings file, ultrawide backdrop: 7 of 7 (three runs) |
| APK built in that clean copy, installed on the Android 17 emulator | installs, launches, no crash in 12 s, shows the intro screen, launcher icon resolves |
| Dart tests in that clean copy | 71 pass, 1 skipped (render comparison skips without the optional FFDec reference frames) |
| `setup`: JDK 21 (Adoptium), Android command-line tools, Flutter 3.47.7 downloaded into an empty folder, checksums verified, `doctor` recognises them | pass (found and fixed a 403 from one server caused by a missing User-Agent) |
| GUI | opens, "check" button runs `doctor` and shows the result |

Not exercised: accepting the Android SDK licenses through `setup --accept-android-licenses` (the code path is the one used by hand earlier, but was
not run in the final test), building with the *downloaded* Flutter (only its version was checked), macOS and Linux (the tool is written for them, but
only Windows was available), the Visual Studio install hint (`winget`), a machine with none of the tools.

## 1. Confirmed passes

| Area | Result | Evidence |
|---|---|---|
| Rebuild from a clean checkout | A copy of exactly the files that are published (no extracted data, no assets), plus the user's `bartender.swf` kept in a separate folder, runs `python rightmix.py build`: the SWF rebuilt from the 40 published sources plus the 42 component scripts of your own file is byte-identical to the original once decompressed (SHA-256 `916f7178...ff80`, 980,066 bytes). Details in the section "Publishing and the build tool" above. | `rightmix.py`, `tools/build.py` |
| Per-unit bytecode match | **40 of 40** published script units (48,138 of 48,138 bytes) are produced by compiling `src/as2` and equal the original's bytecode. The other 42 units (88,534 B, stock Macromedia components) are not published and are not compared in a public checkout; the author's private full set matched 82 of 82 (136,672 of 136,672 bytes, 72 of 72 mutations), which cannot be re-checked from this repository. | `matching_audit.md` |
| Compiler independence | Sources compile in a sandbox that contains neither `decomp/` nor any SWF. 38 of 38 source mutations (on the published sources) changed the output bytes (the compiler is not echoing stored bytes). | `matching_audit.md` |
| `hints.json` | Versioned (`schema_version 1`) with a content hash that `tools/build.py` verifies (tampering is refused); identical to a fresh extraction from the original. The build does not read `bartender.swf`. | `tools/build.py`, `tools/as2c/gen_hints.py` |
| Accounting (corrected) | **40 game-specific units** = 10 classes (46,017 B) + 30 timeline/button/clip-event scripts (2,121 B). **42 framework units** = 23 `mx.*` classes, 11 registration stubs, 7 `stop()` stubs, 1 button action (88,534 B). The earlier "48 / 49 scripts" figure was wrong and is retracted. | `matching_audit.md`, README |
| Behavioural parity vs. the original | **94 of 94 scenarios identical** over **140,831 frames**, every traced field including RNG state (details and coverage: `differential_report.md`). 9 of 9 injected bugs in the port were caught by the harness. | `differential_report.md`, `differential_traces.zip` |
| Rendering vs FFDec | 324 sprite frames compared: **312 pass** (mean pixel difference <= 0.15 and bounding box within 2 px), **12 are listed exceptions** with reasons, **0 unexplained failures**. | `render_report.csv`, `port/test/render_known_exceptions.json` |
| Android 7.0 / 11 / 14 / 17 (API 24 / 30 / 34 / 37) | 16 of 16 device checks pass on each: installs and launches without a crash; 17.9 to 18.3 game ticks per second; touch drives start, bottle pick, pour (volume rises) and shake; going Home stops ticking and pauses the app's audio streams; returning resumes both with no catch-up burst; the stage stays centred at 20:9, 16:9, 21:9, 4:3, 5:4 and 1:1 (aspect 1.36 +-0.01). | `android/*.json`, screenshots |
| Frame-rate independence | The 1/18 s accumulator yields 180 +-1 steps per 10 s at 24, 30, 48, 60, 72, 90, 120, 144, 165 and 240 Hz and with jittery frame times; long stalls are dropped, not replayed. | `port/test/input_timing_test.dart` |
| Single-finger input | A second finger cannot press, move or release the first finger's "mouse". | `input_timing_test.dart` (unit level) |
| Layering | `lib/game` imports only `dart:math`, the engine barrel and itself (no `dart:io`/`ffi`/`ui`/Flutter); the engine never imports the game; `dart:io`/`ffi` only in `*_io.dart`; `game/model` and `game/config` are pure Dart; a whole round plays headless with a recording audio back end. | `port/test/architecture_test.dart` |

### Display options added after the first pass (this section is newer than the rest)

| Feature | What was checked | Result |
|---|---|---|
| Smooth motion (frame blending) | `display_test.dart`: blend 0 reproduces the previous tick **pixel for pixel**, blend 1 the current one, 0.5 differs from both; painting at any blend leaves game logic unchanged; rotation keeps size and takes the short way round. 94-scenario differential re-run unchanged. Recording a frame costs 0.6 ms median / 1.6 ms p95 (CPU side only). | pass |
| Integer scaling | unit tests (dpr 2.625, fall-back below 1x); Android emulator: stage 876 px of a 1080 px screen = 2x (hand measured) | pass |
| Safe areas | unit tests; Android 17 emulator with an emulated tall cutout and a width-limited screen: picture stayed inside the reported insets | pass (API 28+; not applicable before) |
| Windows full screen (F11) | built exe on the left monitor: covers the monitor, F11 again restores; Alt+Enter is **not** delivered to the app by Windows here and is not offered | pass for F11 |
| Blurred backdrop | Windows ultrawide window screenshot: side bars filled (`docs/verification/windows/4_ultrawide_backdrop.png`) | pass (Windows); not run on Android |
| Settings panel + persistence | Android: gear shows after a touch, panel opens, switch toggles, value survives force-stop; Windows: file written | pass |

**Interpolation across discontinuities (follow-up pass).** An audit over 15 replayed games found objects that would have slid
up to 940 px in one blended step (a bottle snapping back to its shelf, ice/lemon dropping into the shaker, Miguel and the
finale timelines jumping or looping, the end card rewinding). Fixes, all render-side (the 18 Hz logic is untouched):

* timeline blending only for ordinary playback (exactly one frame forward) and only when the move is plausibly a tween
  (<= 100 px and < 57 degrees); jumps, rewinds and cuts are drawn where they land;
* explicit "this is a jump" marks when a bottle/ice/lemon is picked up or put back, plus detection of a free-standing
  item moving more than 60 px in one step (the original's dropped-bottle quirk); a global cap of 450 px as a last resort;
* new objects (particles, finale clips, anything attached by script or placed by the timeline) have no previous state and
  are drawn where they are; removed objects are not drawn at all;
* pause/resume, window loss of focus and any frame gap longer than 250 ms: the lost time is dropped (no catch-up) and every
  object's previous state is cleared, so nothing is blended across the gap (`FrameDriver`).

| Check | Result |
|---|---|
| 15 whole games replayed: no timeline object blended over > 100 px, no free bottle over > 60 px, nothing over 400 px, and ordinary motion still blends | pass (`blend_integrity_test.dart`) |
| bottle put back, ice drop, dropped-bottle jump, new/removed objects, timeline jump/rewind/loop/cut, pause, long stall, 200 ms hitch | pass, each a separate test |
| painting at random blends and sizes, clearing blends and suspending between ticks changes **no** game state over 3 full games (per-frame state trace identical, same format as the differential) | pass |
| the same blended picture at two window sizes is the same picture (mean difference < 3%); painting at 5 sizes leaves state untouched | pass |
| the tests notice when a guard is removed (6 injected mistakes) | 6 of 6 caught (`tools/diff/blend_mutation_check.py`) |
| 94-scenario differential vs the original (Dart side re-run) and golden trace | unchanged, 94/94 |
| Windows restart: settings changed through the panel by mouse are saved; the restarted exe comes up full screen with integer scaling and backdrop and draws the **identical** picture (mean pixel difference 0.00); integer-only run draws exactly 1200 x 880 on a 1080 p screen; a corrupt settings file falls back to defaults | pass, 20 checks (`tools/windows/persistence_check.py`) |
| Windows resizing while the arm moves (7 sizes incl. portrait and ultrawide): aspect ratio kept every time, game keeps running, clicks still land | pass |
| Android 17 emulator suite incl. pause/resume with the new frame driver | 22 of 22 |

**Hand-drawn character animation (head before drinking, the rope, finales).** Reported by the user and traced to the same
class of problem: Miguel and the finales are drawn frame by frame, with parts swapped or appearing each frame while other
parts are tweened. Blending the tweened parts (half-way) against swapped parts (at their new frame) put the parts of one
drawing in positions that were never drawn together. Rule now: when anything inside an animation (Miguel, a finale, the hand,
the intro card...) appears, vanishes or is swapped for another drawing, or its timeline jumps, the **whole animation** is
drawn at its current frame for that tick, including parts whose own timelines advance after the parent's. Blending now only
applies to the same drawing moving, to tween-only animation, and to script-driven motion (arm, bottles, particles, shaker).
Consequence to know about: Miguel and the finales mostly step at the original 18 fps, by design.

| Check | Result |
|---|---|
| over 7 replayed games: 2,323 drawings swapped or created, 1,716 animation-ticks held whole; in every one, no part of that animation blends | pass |
| removing the whole-animation hold (and the same-drawing rule) makes that test fail | caught (`blend_mutation_check.py`, 8 of 8 mutations caught) |
| frame audit of rotation/flip/shear/scale outliers in serve and finale: only a swinging tie and similar same-drawing tweens remain | reviewed by picture, not asserted |

Not verified for these: how smooth the motion *looks* on a real 90/120 Hz screen (I can only check the maths and pictures,
not watch motion), GPU cost of the blurred backdrop on phones, true tablet/foldable layouts. Known limits of smooth motion:
the pour-stream line and all pre-drawn frame animations still change at 18 Hz; objects that teleport (a bottle snapping
back to its shelf) slide for one 1/18 s step.

### Frame times: the end-card curtain stutter (found, fixed, measured on both platforms)

Reported as "the curtain after he drank is laggy, in full screen". `tools/windows/frame_timing.py` (real exe, verified
full screen on the left monitor, RX 570, 1080p, `RIGHTMIX_FRAMELOG`) logs build/raster time per frame with a note of what
the game was doing. Findings, by switching suspects off one at a time:

* the cost is **large gradient and bitmap fills** (the curtain is a few full-screen radial gradients): with them replaced by
  flat colour the curtain frames cost 8 ms; colour filters, alpha blending, strokes and the finale underneath were not it;
* with smooth motion the curtain moves on every display frame, so those fills were re-shaded every frame: 24 ms raster
  (about 40 ms per frame, 34 frames per second); with smooth motion off the same scene cost 14 ms (a hidden warm-up tried
  first changed nothing and was removed);
* **fix:** `FillTextureCache` renders each large (over 120,000 device pixels), axis-aligned gradient/bitmap fill once into a
  texture and blits it (texture capped at 2.5 texels per stage unit, 96 MB budget, only for unchanged colour or alpha-only).

| Check | Result |
|---|---|
| Windows, verified full screen, smooth motion ON, curtain frames | raster **24 ms -> 9 to 11 ms**, frames over 16.7 ms: **33 -> 0** (two runs each) |
| Windows, whole game in verified full screen | no slow frames in play; four isolated hitches remain (start-up 33 ms, **two ~95 ms frames the first time the bar is drawn**, one 71 ms frame when the end text appears) |
| Android 17 emulator (host GPU; absolute numbers pessimistic, compare the pair): the problem exists there too | curtain raster **19 -> 9 ms** (worst 60 -> 27 ms); finale scene 25 -> 11 ms (`tools/android/frame_timing.py`) |
| Android 7 emulator (software-rendered, everything costs about 30 ms): no regression, small gain (curtain 35 -> 32 ms); full suite 20/20 | pass, but says little about real hardware |
| Android 17 suite with the cache | 22 of 22 |
| the cached picture equals direct drawing | mean difference < 1% at several scales and sub-pixel positions, and over a whole game replay (`fill_cache_test.dart`) |
| not used for rotated draws, tinted draws, small fills, or when switched off; memory bounded | pass |

Not verified: the absolute numbers on a real phone (the emulator is slower than hardware; the relative gain is what was measured),
and the four remaining one-frame hitches (first draw of the bar and of the end text), which the user did not report.

## 2. Defects found and fixed in this pass

* **Tick order** (found by the differential): the port advanced all timelines, then ran all `onEnterFrame` handlers. The original runs a clip's handler, then its playhead, then its children. Effect: finale animation started and ended one frame off. Fixed in `MovieClip.tickFrame`; golden trace re-recorded (one tick moved).
* **Garnish particles** (differential): `spawnerArray[7]`/`[8]` lacked random scale, so one `Math.random()` draw per particle was missing and sizes were wrong. Fixed.
* **Restart** did not reset the finale id (not observable in play). Fixed.
* **Second finger** could release or press the first finger's button. Fixed with a single-pointer gate.
* **Background audio** (found by reading the code, **not reproduced before the fix**): MediaPlayer sounds would keep playing when the app is not visible. Now paused in `onStop`, resumed in `onStart` (verified on 4 API levels after the fix).
* **Audio ~150 ms late on both platforms** (reported by the user, then measured): 22 of the 26 sounds are 11 kHz MP3s whose first 1,661 samples (150 ms) are encoder delay that Flash skips (`SeekSamples`); the port decoded and played that silence (measured 146 to 200 ms of leading silence, and a 150 ms gap on every loop of the music and rattle). Sounds are now converted at build time to WAV with the delay removed (leading silence now 0 to 50 ms). `tools/assetc/build_assets.py`, `port/test/sound_assets_test.dart`.
* **Sound envelopes ignored**: 11 timeline sound cues (8 distinct) carry volume/pan envelopes (fades); the port played them flat. They are now baked into per-cue WAV variants.
* **Android sound start latency**: replaced one `MediaPlayer` per sound with `SoundPool` (decoded in memory, overlapping streams). Not measured end to end; the previous path's latency is device dependent.
* **Windows mixer**: buffering set to 10 ms periods (measured 30 ms total, `audio_test.dart`).
* **Held button when leaving the app**: pressed state is released on pause.

## 3. Partial tests

* **Parity oracle is Ruffle, not Adobe Flash Player.** Agreement is strong evidence; the tick-order rule was inferred from Ruffle's behaviour and could differ in Flash Player.
* **Inputs call game handlers directly** (what a click would call). Hit testing, rollover/rollout side effects and the pointer-to-handler path are covered only by older unit tests and the Android taps, not by the differential.
* **Android runs used a TRACE variant** of the app (`--dart-define=TRACE=true`, same source, adds log lines). The shipped APK was built from the same source without it but was not itself run through these checks.
* **Audio sync after the fix** was verified by measuring the assets and mixer buffering, and by stream state on devices; I have not measured sound-to-picture delay on a device or by ear. Remaining known difference: a sound retriggered while playing restarts instead of overlapping (Flash event sounds overlap); `nomulti` is not honoured.
* **Android audio**: stream state (started/paused) was checked; actual sound output was not (emulators ran with audio off).
* **"Portrait" screen size**: the activity is locked to landscape, so the 1080x2400 override still rendered as 2400x1080. A true portrait/large-screen (>= 600 dp, where Android 16+ ignores orientation locks) layout was not exercised.
* **Rendering** is compared per sprite frame against FFDec (anti-aliasing differs, so thresholds are loose). Whole-scene screenshots of gameplay frames were not compared against a reference player. 12 exceptions are explained only as tiny-shape coverage differences or unconfirmed sub-pixel effects.
* **Matching**: the compiler reproduces the output only given the register-allocation hints extracted from the original (`hints.json`) and the original parameter names. The source is faithful to those inputs, not a hint-free reconstruction.

## 4. Unverified claims (do not rely on these)

* Windows 11 build: rebuilt and repackaged (`dist/`), unit tests pass, but not run on the desktop in this pass; audio pause on minimise was not implemented or tested.
* Real devices, ARM CPUs, high-refresh panels, display cutouts, foldables, split-screen, audio focus/interruptions (calls), Bluetooth: none tested (x86_64 emulators at 60 Hz only).
* Multi-touch on a device (only the unit-level gate is tested).
* Bit-exact reproduction of the original **compressed** `.swf` (not achieved).
* Equivalence of rendering, audio and every possible input sequence with Flash Player.

## 5. Remaining risks

1. The one-frame tick-order rule rests on Ruffle; if Flash Player differs, finale timing is off by a frame (cosmetic).
2. Anything outside the 94 scenarios (very odd input orders, long sessions, hover effects) is untested against the original.
3. Port logic is not separated from the scene graph: phases drive clips directly and Miguel's frame number is part of the timing (as in the original). Layering is enforced between game, engine and platform, but a gameplay change still needs the differential/golden tests to catch regressions.
4. `hints.json` encodes decisions of Macromedia's compiler; editing code that changes register pressure will not re-derive them, so a modified function may need hints adjusted to stay byte-matching to the original (it will still compile and run).
5. Emulator-only Android evidence; the release APK is debug-signed.

## 6. Reproduce

```bash
python rightmix.py verify --swf bartender.swf          # rebuild from src/as2 and compare (matching check)
python tools/verify_matching.py                      # per-unit audit + sandbox compile + 38 mutations (set RIGHTMIX_AS2_SRC to audit a different source set)
python tools/diff/gen_scenarios.py                   # plans.json
(cd port && flutter test test/plan_scenarios_test.dart)    # resolve to scenarios.json (inputs only)
DIFF_FPS=240 python tools/diff/run_diff.py --resume  # original in Ruffle (muted, left monitor) vs port
python tools/diff/coverage.py && python tools/diff/mutation_check.py
python tools/render/export_fixtures.py --check       # FFDec fixtures reproduce (2,696 frame hashes)
(cd port && flutter test)                            # all Dart tests incl. render comparison, layering, input timing
python tools/android/make_avds.py                    # emulator definitions (API 24/30/34); images via sdkmanager
python tools/android/verify_device.py rightmix24 rightmix30 rightmix34 rightmix37
```

Pinned tools: Ruffle nightly 2026-10-16 (zip sha256 `b91dd186...`, `tools/ruffle_dl`), FFDec 26.3.0, Flutter 3.47.7,
JDK 21.0.12.
