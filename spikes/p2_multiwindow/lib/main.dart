// Spike P2 — panel tear-off into a second native window (OB-0-02).
//
// THROWAWAY CODE. This is not how OneBeat will be structured; it exists to
// answer whether Flutter can do this at all.
//
// IMPORTANT — this does NOT run on the version OneBeat ships (stable 3.44.4).
// The windowing API is `@internal`, experimental, and gated behind a feature
// flag the tool refuses to set outside the master channel. This directory is
// pinned to master via its own .fvmrc, which is why it can run at all:
//
//   cd spikes/p2_multiwindow
//   fvm flutter config --enable-windowing
//   fvm flutter run -d macos --dart-define=AUTO_TEAROFF=true
//
// The API also drifted between 3.44 (stable) and master in seven weeks:
// RegularWindowController -> WindowController, RegularWindow -> Window, and
// WindowManager went from taking `child` to taking `initialWindows`. That
// instability is a finding, not an inconvenience — see ADR-001.
//
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show AppExitType, FlutterView;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

/// Shared state, deliberately owned above both windows.
///
/// The point of the exercise: if the detached window renders from this same
/// object, panels do NOT have to serialize state on detach, and tear-off
/// collapses into a widget-tree question rather than an IPC one.
class PanelModel extends ChangeNotifier {
  double _level = 0;
  int _clicks = 0;
  String _typed = '';

  double get level => _level;
  int get clicks => _clicks;
  String get typed => _typed;

  void setLevel(double value) {
    _level = value;
    notifyListeners();
  }

  void click() {
    _clicks++;
    notifyListeners();
  }

  void type(String character) {
    _typed = (_typed + character).characters.takeLast(24).toString();
    notifyListeners();
  }
}

class _QuitOnClose with WindowControllerDelegate {
  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(const SpikeApp());
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> with SingleTickerProviderStateMixin {
  final PanelModel model = PanelModel();
  late final WindowController _mainWindow = WindowController(
    size: const Size(760, 560),
    title: 'P2 spike — main window',
    delegate: _QuitOnClose(),
  );
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Live content, so rendering in the second window is genuinely exercised
    // rather than "a window opened with a static label in it".
    _ticker = createTicker((Duration elapsed) {
      final double t = elapsed.inMilliseconds / 1000.0;
      model.setLevel(0.5 + 0.5 * _sin(t * 2));
    })..start();
  }

  static double _sin(double x) {
    const double twoPi = 6.283185307179586;
    final double wrapped = x % twoPi;
    final double x2 = wrapped - 3.141592653589793;
    return -(x2 - (x2 * x2 * x2) / 6 + (x2 * x2 * x2 * x2 * x2) / 120);
  }

  @override
  void dispose() {
    _ticker.dispose();
    model.dispose();
    _mainWindow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WindowManager(
      initialWindows: <WindowEntry>[
        WindowEntry(
          controller: _mainWindow,
          builder: (BuildContext context) => WidgetsApp(
            color: const Color(0xFF101014),
            builder: (BuildContext context, Widget? child) => MainWindowBody(model: model),
          ),
        ),
      ],
    );
  }
}

class MainWindowBody extends StatefulWidget {
  const MainWindowBody({required this.model, super.key});

  final PanelModel model;

  @override
  State<MainWindowBody> createState() => _MainWindowBodyState();
}

class _MainWindowBodyState extends State<MainWindowBody> {
  WindowEntry? _entry;
  WindowController? _controller;
  String _status = 'windowing enabled: $isWindowingEnabled';

  bool get _detached => _entry != null;

  /// Prints hard evidence rather than relying on someone eyeballing a
  /// screenshot: how many root views the engine drives, and from which isolate.
  /// `views=2` from one isolate answers "same engine, or a second isolate?".
  void _report(String phase) {
    final Iterable<FlutterView> views = WidgetsBinding.instance.platformDispatcher.views;
    debugPrint('P2[$phase] views=${views.length} '
        'ids=${views.map((FlutterView v) => v.viewId).toList()} '
        'isolate=${Isolate.current.debugName} '
        'rss=${(ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(1)}MB');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _report('startup');
      // Optional, so the whole run is scriptable; the buttons still work.
      if (const bool.fromEnvironment('AUTO_TEAROFF')) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          _tearOff();
          _report('after tear-off');
        });
        Future<void>.delayed(const Duration(seconds: 6), () {
          _reDock();
          _report('after re-dock');
        });
      }
    });
  }

  void _tearOff() {
    final WindowRegistry? registry = WindowRegistry.maybeOf(context);
    if (registry == null) {
      setState(() => _status = 'no WindowRegistry — windowing is disabled');
      return;
    }
    try {
      final WindowController controller = WindowController(
        size: const Size(420, 340),
        title: 'Torn-off panel',
      );
      final WindowEntry entry = WindowEntry(
        controller: controller,
        // The detached window builds from the SAME model instance.
        builder: (BuildContext context) => WidgetsApp(
          color: const Color(0xFF101014),
          builder: (BuildContext context, Widget? child) => ColoredBox(
            color: const Color(0xFF101014),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PanelContent(model: widget.model, label: 'DETACHED WINDOW'),
            ),
          ),
        ),
      );
      registry.register(entry);
      setState(() {
        _controller = controller;
        _entry = entry;
        _status = 'torn off';
      });
    } on Object catch (error) {
      setState(() => _status = 'tear-off failed: $error');
    }
  }

  void _reDock() {
    final WindowRegistry? registry = WindowRegistry.maybeOf(context);
    final WindowEntry? entry = _entry;
    if (registry == null || entry == null) {
      return;
    }
    registry.unregister(entry);
    _controller?.destroy();
    setState(() {
      _entry = null;
      _controller = null;
      _status = 're-docked';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101014),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _Text('P2 spike — panel tear-off', size: 20),
            const SizedBox(height: 4),
            _Text(_status, size: 12, color: const Color(0xFF8A8A99)),
            const SizedBox(height: 20),
            _Button(
              label: _detached ? 'Re-dock panel' : 'Tear off panel',
              onTap: _detached ? _reDock : _tearOff,
            ),
            const SizedBox(height: 24),
            if (!_detached)
              PanelContent(model: widget.model, label: 'DOCKED')
            else
              const _Text('panel is in its own window →', color: Color(0xFF8A8A99)),
          ],
        ),
      ),
    );
  }
}

/// The panel. Identical widget in both windows, reading the same model.
class PanelContent extends StatelessWidget {
  const PanelContent({required this.model, required this.label, super.key});

  final PanelModel model;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16161C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: model,
          builder: (BuildContext context, Widget? child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Text(label, size: 11, color: const Color(0xFF6E6E7E)),
                const SizedBox(height: 12),
                // Live render, driven by the ticker that lives in the main window.
                CustomPaint(
                  size: const Size(320, 24),
                  painter: _LevelPainter(model.level),
                ),
                const SizedBox(height: 16),
                // Mouse input, in whichever window this is showing.
                _Button(label: 'clicked ${model.clicks}x', onTap: model.click),
                const SizedBox(height: 12),
                // Keyboard input, in whichever window this is showing.
                Focus(
                  autofocus: true,
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent && event.character != null) {
                      model.type(event.character!);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (BuildContext context) {
                      final bool focused = Focus.of(context).hasFocus;
                      return Container(
                        width: 320,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: focused ? const Color(0xFF5B8DEF) : const Color(0xFF2A2A34),
                          ),
                        ),
                        child: _Text(
                          model.typed.isEmpty ? 'click here, then type...' : model.typed,
                          size: 12,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.level);

  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF23232C));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * level.clamp(0.0, 1.0), size.height),
      Paint()..color = const Color(0xFF4ED07A),
    );
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) => oldDelegate.level != level;
}

class _Text extends StatelessWidget {
  const _Text(this.text, {this.size = 14, this.color = const Color(0xFFE6E6F0)});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: size, color: color),
      textDirection: TextDirection.ltr,
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF2A2A34),
        child: _Text(label, size: 13),
      ),
    );
  }
}
