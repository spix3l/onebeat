// OneBeat v0.1 — "it makes sound".
//
// The app owns the engine handle: it is created here, on the UI isolate, and
// destroyed when the app closes (ADR-002 §6).
import 'dart:io' show stdout;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'src/design/tokens.dart';
import 'src/engine/engine_client.dart';
import 'src/engine/engine_library.dart';
import 'src/ui/shell.dart';

/// Time from Dart entry to a window the user can act on. NFR-04 puts a five
/// second ceiling on cold start with a large plug-in library, and the only way
/// to know whether a change moved it is to have the number printed on every
/// launch rather than measured once into a document that then goes stale.
///
/// Started explicitly at the top of `main` and *not* with a top-level
/// initialiser: top-level finals in Dart are lazy, so `Stopwatch()..start()`
/// there would not run until something first read the variable — which is the
/// moment the elapsed time is asked for, and it would read zero every time.
/// (It did.)
final Stopwatch startupStopwatch = Stopwatch();

void main() {
  startupStopwatch.start();
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    // stdout rather than developer.log or debugPrint: this has to survive a
    // release build, because a release build is what the five second ceiling
    // is about. One line, once, at startup.
    stdout.writeln('onebeat: first frame in ${startupStopwatch.elapsedMilliseconds} ms');
  });
  runApp(const OneBeatApp());
}

class OneBeatApp extends StatefulWidget {
  const OneBeatApp({super.key});

  @override
  State<OneBeatApp> createState() => _OneBeatAppState();
}

class _OneBeatAppState extends State<OneBeatApp> with WidgetsBindingObserver {
  EngineClient? _client;
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      final EngineClient client = EngineClient.start(useNullDevice: isHeadlessEnvironment);
      client.startAudio();
      _client = client;
    } on EngineLoadException catch (error) {
      _failure = error.message;
    } on EngineException catch (error) {
      _failure = error.message;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client?.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Stop the audio device before the process goes away, so the last thing the
    // user hears is silence rather than a buffer of garbage.
    _client?.dispose();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    return OneBeatTheme(
      tokens: tokens,
      child: WidgetsApp(
        title: 'OneBeat',
        color: tokens.color.surfaceDeep,
        debugShowCheckedModeBanner: false,
        builder: (BuildContext context, Widget? child) {
          final EngineClient? client = _client;
          if (client == null) {
            return _EngineUnavailable(message: _failure ?? 'The engine could not start.');
          }
          return OneBeatShell(client: client);
        },
      ),
    );
  }
}

/// A failure state, designed rather than thrown: it says what happened and what
/// to do next (FR-UX-12).
class _EngineUnavailable extends StatelessWidget {
  const _EngineUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Container(
      color: tokens.color.surfaceDeep,
      alignment: Alignment.center,
      padding: EdgeInsets.all(tokens.spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('OneBeat cannot reach its audio engine', style: tokens.type.title),
          SizedBox(height: tokens.spacing.md),
          SizedBox(
            width: tokens.size.dialogProseWidth,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: tokens.type.body.copyWith(color: tokens.color.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
