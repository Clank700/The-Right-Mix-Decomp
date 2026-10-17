# The native ports (Windows 11 and Android) - design, additions, limits

`port/` is an ordinary Flutter project (Dart 3.13, Flutter 3.47.7, **no Flutter plugins**). It is **not generated from the
decompiled ActionScript**: the game logic was re-implemented by hand in Dart from the decompiled sources, and the result is checked
against the original running in an independent Flash emulator (see [VERIFICATION.md](VERIFICATION.md)). The ports contain no game
data: `rightmix.py` extracts the art and sound from *your* `bartender.swf` into `port/assets/` (git-ignored) at build time.

## Layout

```
port/lib/engine/    Flash-like scene engine (no game rules)
port/lib/game/      the game (rules, states, effects); imports only the engine and dart:math
port/lib/main.dart  the app: ticker, input, settings panel, lifecycle
port/android/       Kotlin MainActivity: SoundPool audio, files dir, cutout theme
port/windows/       runner (+ full-screen channel) and audio/ (miniaudio-based DLL)
port/test/          72 tests (unit, simulation, layering, differential support)
```

Layering is enforced by `test/architecture_test.dart`: `lib/game` may import only the engine and `dart:math`; the engine never imports
the game; `dart:io`/`dart:ffi` only appear in `*_io.dart` files; Flutter widgets only in `main.dart`; `game/model` and
`game/config` are pure Dart. The whole game runs headless in tests (no renderer, audio device or widgets).

### Engine (`lib/engine`)

Movie clips with timelines and frame scripts, vector shapes (paths, linear/radial gradients, bitmap fills, strokes), masks
(`saveLayer` + `dstIn`), embedded-outline text, buttons and hit testing, colour transforms, the drawing API used by the pour stream,
sounds (`Sound` objects and timeline `StartSound` cues), and an 18 Hz stage tick whose order matches the original player
(depth first: a clip's `onEnterFrame`, then its playhead, then its children).

### Game (`lib/game`)

`GameWorld` instead of globals; one `Phase` class per game state (14 states: preGame, getBottle, pour, rest, returnTweenHand, shake,
shakeRest, serve, serveRest, serveLemon, finaleInit, finale, endGame, waitInput); data tables for the 21 bottles and the score
verdicts; a pure `Shaker` model; named effect spawners. Original quirks are kept on purpose (Champagne twice on the shelf, the
Amaretto bottle labelled Cointreau, the ice/lemon `gotoAndStop(1)` that does nothing, a held Pour/Shake button when dragging off it,
invisible splashes for a missing symbol).

## Things added to the original game (all optional or invisible)

| Addition | What it does |
|---|---|
| **Smooth motion** (settings, default on) | The simulation stays at the original 18 steps per second. Between steps the picture blends every object's position, rotation, scale and alpha at the display's refresh rate (60/120 Hz...). Objects that jump (a bottle snapping to its shelf, new or removed objects, timeline jumps or cuts, anything after a pause) are drawn where they land, and an animation in which any drawing is swapped is held whole, so hand-drawn animation (Miguel, the finales) keeps its 18 fps look instead of distorting. Painting never changes game state (tested). |
| **Display** | Correct aspect ratio at any shape, safe areas (cutouts, rounded corners), integer scaling, optional blurred backdrop for ultrawide, F11 full screen (Windows), immersive mode (Android). The vector art is drawn at the screen's real resolution; the 43 small bitmaps are only upscaled (bicubic). |
| **Fill texture cache** | Large gradient/bitmap fills are rendered once into a texture and blitted (capped resolution and memory). Cut the end-card curtain from 24 ms to 9-11 ms per frame at 1080p full screen with smooth motion on. |
| **Settings** | `F1`/`Esc` (Windows) or the gear that appears when you touch the screen (Android). Stored in `%APPDATA%\TheRightMix\settings.json` / the app's private folder; a corrupt file falls back to defaults. |
| **Audio fixes** | Flash skips the MP3 encoder delay (`SeekSamples`, 150 ms for the 11 kHz sounds) and applies the volume envelopes of 11 timeline sound cues; plain MP3 playback does neither, so sounds were late and loops had gaps. Sounds are converted at build time to trimmed WAV with envelopes baked in. Android uses `SoundPool` (low latency, overlapping streams) and pauses audio when the app leaves the screen. |
| **Input** | One finger acts as the mouse (a second finger cannot press or release the first one's button); held buttons are released when the app loses focus. |
| **Frame pacing** | A fixed-step accumulator (tested at 24 to 240 Hz); gaps longer than 250 ms (pause, drag, sleep) are dropped, not replayed. |
| **App icon** | Rendered from the game's artwork at build time (Miguel); never stored in the repository. |

## Differences from the original that are known and kept

* A sound started again while still playing restarts instead of overlapping (Flash event sounds overlap); `nomulti` is not honoured (no cue in this file uses it).
* Alt+Enter does not reach the app on Windows (F11 does).
* Hand-drawn animations are not interpolated (by design, see above).

## Diagnostics built into the app

| Switch | Effect |
|---|---|
| `RIGHTMIX_MUTE=1` (environment, Windows) | silent run (used by automated tests) |
| `RIGHTMIX_FRAMELOG=<file>` | write build/raster time of every frame (and `<file>.notes` with what the game was doing) |
| `RIGHTMIX_AUTOPLAY=end` (with the frame log) | jump straight to a finale and the end card |
| `RIGHTMIX_PROBE=nocache` or `--dart-define=NOCACHE=true` | turn the fill texture cache off |
| `--dart-define=TRACE=true` | print phase changes and a heartbeat (used by the Android device tests) |

## Tests

`cd port && flutter test` (after `python rightmix.py build ...` or at least `prepare`, because many tests load the extracted assets):
gameplay and golden-trace tests, input/timing, layering, rendering (needs the optional FFDec reference frames and skips without),
interpolation integrity (replays whole games and checks no object slides across a jump, plus mutation checks that remove each guard),
the fill cache, sound assets, and the differential-test support. The differential comparison with the original is
`tools/diff/run_diff.py` (needs Ruffle; see [VERIFICATION.md](VERIFICATION.md)).
