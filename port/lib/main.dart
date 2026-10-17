import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'engine/engine.dart';
import 'game/frame_scripts.dart';
import 'game/config/verdicts.dart';
import 'game/world.dart';
import 'env_stub.dart' if (dart.library.io) 'env_io.dart';
import 'frame_log_stub.dart' if (dart.library.io) 'frame_log_io.dart';
import 'settings.dart';
import 'settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  final lib = await Library.load(rootBundle);
  final settings = await SettingsStore.load();
  startFrameLog();
  runApp(RightMixApp(lib, settings));
}

class RightMixApp extends StatelessWidget {
  final Library lib;
  final Settings settings;
  const RightMixApp(this.lib, this.settings, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'The Right Mix',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(backgroundColor: Colors.black, body: GameView(lib, settings)),
      );
}

class GameView extends StatefulWidget {
  final Library lib;
  final Settings settings;
  const GameView(this.lib, this.settings, {super.key});

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _window = MethodChannel('org.decomp.therightmix/window');
  static bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  late final Stage stage;
  late final Ticker _ticker;
  late final Settings settings = widget.settings;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final FrameDriver _driver = FrameDriver(stage, 1 / Library.fps); // the SWF runs at 18 frames per second
  final SinglePointerGate _gate = SinglePointerGate(); // one finger acts as the mouse
  final GameHost _host = GameHost();
  Offset _lastPoint = Offset.zero;
  Size _size = Size.zero;

  bool _panelOpen = false;
  bool _gearVisible = true;
  Timer? _gearTimer;

  /// `--dart-define=TRACE=true` prints phase changes and a once-a-second tick heartbeat to the log (device test runs).
  static const bool _trace = bool.fromEnvironment('TRACE');
  GamePhase? _tracePhase;
  String _lastInsetsLine = '';
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    stage = Stage(widget.lib, AudioBackend.create());
    registerFrameScripts(stage, _host);
    stage.start();
    _applyDiagnosticSwitches();
    if (_trace) _driver.onTick = _traceTick;
    _applySettings(save: false);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    _wakeGear();
  }

  // ---- settings ---------------------------------------------------------------------------------
  void _applySettings({bool save = true}) {
    stage.viewOptions
      ..integerScale = settings.integerScale
      ..blurredBackdrop = settings.blurredBackdrop;
    if (_isWindows) {
      _window.invokeMethod('setFullscreen', settings.fullscreen).catchError((_) {});
    }
    if (save) SettingsStore.save(settings);
    if (_trace) {
      debugPrint('RM settings integer=${settings.integerScale} blur=${settings.blurredBackdrop} '
          'smooth=${settings.smoothMotion} fullscreen=${settings.fullscreen}');
    }
  }

  void _change(void Function() edit) {
    setState(edit);
    _applySettings();
  }

  void _toggleFullscreen() {
    if (_isWindows) _change(() => settings.fullscreen = !settings.fullscreen);
  }

  void _wakeGear() {
    _gearTimer?.cancel();
    if (!_gearVisible && mounted) setState(() => _gearVisible = true);
    _gearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_panelOpen) setState(() => _gearVisible = false);
    });
  }

  void _togglePanel() => setState(() {
        _panelOpen = !_panelOpen;
        if (_panelOpen) {
          _gate.reset();
          stage.pointerUp(_lastPoint, leaves: true); // let go of anything held in the game
        }
        _wakeGear();
      });

  // ---- frame loop -------------------------------------------------------------------------------
  void _onTick(Duration elapsed) {
    _driver.frame(elapsed);
    _diagnosticAutoplay();

    if (frameLogEnabled) {
      final w = _host.game?.world;
      frameNote(w == null
          ? 'boot'
          : '${w.phase.name} endCard=${w.endCard.frame} visible=${w.endCard.visible} finale=${w.finaleClip?.frame} '
              'miguel=${w.miguel.frame}');
    }
    _repaint.value++;
  }

  /// Diagnostics only (frame-time measurements): RIGHTMIX_AUTOPLAY=end jumps straight to a finale and its end card.
  bool _autoplayed = false;
  /// Diagnostics: RIGHTMIX_PROBE=nocache (or --dart-define=NOCACHE=true) turns the fill texture cache off.
  void _applyDiagnosticSwitches() {
    FillTextureCache.enabled = !(environmentVariable('RIGHTMIX_PROBE') ?? '').contains('nocache') &&
        !const bool.fromEnvironment('NOCACHE');
  }
  void _diagnosticAutoplay() {
    final wanted = environmentVariable('RIGHTMIX_AUTOPLAY') == 'end' || const String.fromEnvironment('AUTOPLAY') == 'end';
    if (_autoplayed || !frameLogEnabled || !wanted) return;
    final w = _host.game?.world;
    if (w == null || stage.frameCount < 40) return;
    _autoplayed = true;
    w.startRound();
    w.shaker.points = 500;
    w.verdict = verdictForScore(500);
    w.phase = GamePhase.finaleInit;
  }

  void _traceTick() {
    _ticks++;
    final world = _host.game?.world;
    if (world != null && world.phase != _tracePhase) {
      _tracePhase = world.phase;
      debugPrint('RM phase=${world.phase.name} tick=$_ticks vol=${world.shaker.fluidVolume} pts=${world.shaker.points}');
    }
    if (_ticks % 18 == 0) debugPrint('RM hb tick=$_ticks');
  }

  /// Leaving the foreground: let go of any held button (the up event may never arrive) and don't replay the pause.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _driver.suspend(); // time spent away is dropped; nothing is blended across it
      return;
    }
    if (_gate.active != null) {
      _gate.reset();
      stage.pointerUp(_lastPoint, leaves: true);
    }
    _driver.suspend();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gearTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  Offset _stagePoint(Offset p) => stage.toStage(p, _size);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    // (Alt+Enter is accepted if the system delivers it, but Windows did not pass it to the app in testing; F11 works.)
    if (key == LogicalKeyboardKey.f11 ||
        (key == LogicalKeyboardKey.enter && HardwareKeyboard.instance.isAltPressed)) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f1 || key == LogicalKeyboardKey.escape) {
      if (key == LogicalKeyboardKey.escape && !_panelOpen && settings.fullscreen) {
        _toggleFullscreen(); // Esc leaves full screen first
      } else {
        _togglePanel();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.viewPadding;
    stage.viewOptions
      ..devicePixelRatio = mq.devicePixelRatio
      ..safe = SafeInsets(pad.left, pad.top, pad.right, pad.bottom);
    if (_trace) {
      final line = 'RM insets l=${pad.left.toStringAsFixed(1)} t=${pad.top.toStringAsFixed(1)} '
          'r=${pad.right.toStringAsFixed(1)} b=${pad.bottom.toStringAsFixed(1)} dpr=${mq.devicePixelRatio.toStringAsFixed(3)}';
      if (line != _lastInsetsLine) {
        _lastInsetsLine = line;
        debugPrint(line);
      }
    }

    return PopScope(
      canPop: !_panelOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _panelOpen) _togglePanel();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _panelOpen,
              child: LayoutBuilder(builder: (context, c) {
                _size = Size(c.maxWidth, c.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _wakeGear();
                    if (!_gate.down(e.pointer)) return;
                    stage.pointerDown(_lastPoint = _stagePoint(e.localPosition));
                  },
                  onPointerMove: (e) {
                    if (!_gate.move(e.pointer)) return;
                    stage.pointerMove(_lastPoint = _stagePoint(e.localPosition));
                  },
                  onPointerHover: (e) {
                    if (e.kind == PointerDeviceKind.mouse) _wakeGear();
                    stage.pointerMove(_lastPoint = _stagePoint(e.localPosition));
                  },
                  onPointerUp: (e) {
                    if (!_gate.up(e.pointer)) return;
                    stage.pointerUp(_lastPoint = _stagePoint(e.localPosition), leaves: e.kind == PointerDeviceKind.touch);
                  },
                  onPointerCancel: (e) {
                    if (!_gate.up(e.pointer)) return;
                    stage.pointerUp(_lastPoint, leaves: true);
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _StagePainter(stage, _repaint, () => _driver.blend(settings.smoothMotion)),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            top: pad.top + 6,
            right: pad.right + 6,
            child: IgnorePointer(
              ignoring: !_gearVisible && !_panelOpen,
              child: AnimatedOpacity(
                opacity: (_gearVisible || _panelOpen) ? 0.55 : 0,
                duration: const Duration(milliseconds: 250),
                child: IconButton(
                  tooltip: 'Display settings (F1)',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  onPressed: _togglePanel,
                ),
              ),
            ),
          ),
          if (_panelOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePanel,
                child: const ColoredBox(color: Color(0x99000000)),
              ),
            ),
            Center(child: _SettingsPanel(settings: settings, onChange: _change, onClose: _togglePanel, showFullscreen: _isWindows)),
          ],
        ]),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final Settings settings;
  final void Function(void Function()) onChange;
  final VoidCallback onClose;
  final bool showFullscreen;
  const _SettingsPanel({required this.settings, required this.onChange, required this.onClose, required this.showFullscreen});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 420),
      child: Card(
        color: const Color(0xF0202020),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: const Text('Display', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
              dense: true,
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Smooth motion'),
              subtitle: const Text('Blend between the game\'s 18 steps per second to match your display. Off = original 18 fps.'),
              value: settings.smoothMotion,
              onChanged: (v) => onChange(() => settings.smoothMotion = v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Integer scaling'),
              subtitle: const Text('Whole-number sizes only: crisper edges, bigger borders.'),
              value: settings.integerScale,
              onChanged: (v) => onChange(() => settings.integerScale = v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Blurred backdrop'),
              subtitle: const Text('Fill the side bars of wide screens with a blurred copy of the picture (uses more GPU).'),
              value: settings.blurredBackdrop,
              onChanged: (v) => onChange(() => settings.blurredBackdrop = v),
            ),
            if (showFullscreen)
              SwitchListTile(
                dense: true,
                title: const Text('Full screen'),
                subtitle: const Text('F11 toggles it. F1 opens this panel.'),
                value: settings.fullscreen,
                onChanged: (v) => onChange(() => settings.fullscreen = v),
              ),
          ]),
        ),
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  final Stage stage;
  final double Function() blend;
  _StagePainter(this.stage, Listenable repaint, this.blend) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) => stage.paint(canvas, size, blend: blend());

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
