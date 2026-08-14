// The shell, assembled and driven — the test that was missing (OB-3-14 §1).
//
// Every widget test in this suite pumped one editor at a time, so two failures
// that make the app unusable both shipped green:
//
//   1. A layout exception in the top bar. Nothing under it could lay out and
//      the app launched as a black window.
//   2. The rail and the workspace read `controller.view` without listening to
//      anything, so clicking a rail tile moved the top bar's switcher and left
//      the editor behind it on the previous view.
//
// Neither is subtle in the running app and neither was visible to a test that
// never built the whole tree. This builds it, against the real engine with the
// null audio backend, and drives the rail.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/action_registry.dart';
import 'package:onebeat/src/ui/arrangement.dart';
import 'package:onebeat/src/ui/channel_rack.dart';
import 'package:onebeat/src/ui/mixer_view.dart';
import 'package:onebeat/src/ui/piano_roll.dart';
import 'package:onebeat/src/ui/shell.dart';

import 'support/stage3_harness.dart';

/// Where `tools/build.sh` and `tools/dev.sh` leave the engine.
String? _engineLibraryPath() {
  final String? explicit = Platform.environment['OB_ENGINE_DYLIB'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final Directory app = Directory.current;
  for (final String candidate in <String>[
    '${app.parent.path}/build/libonebeat_engine.dylib',
    '${app.path}/../build/libonebeat_engine.dylib',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

void main() {
  if (_engineLibraryPath() == null) {
    // ignore: avoid_print
    print(
      'Skipping the shell smoke test: no engine dylib. '
      'Run tools/build.sh, or set OB_ENGINE_DYLIB.',
    );
    return;
  }

  // Real fonts: block glyphs measure nothing like Archivo or MartianMono, and
  // this test is partly about whether the chrome fits.
  setUpAll(loadAppFonts);

  late EngineClient client;

  setUp(() => client = EngineClient.start(useNullDevice: true));
  tearDown(() => client.dispose());

  /// Pumps the shell at [size] and returns once it has settled.
  Future<void> pumpShell(WidgetTester tester, {required Size size}) async {
    final double ratio = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(size.width * ratio, size.height * ratio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OneBeatTheme(
          tokens: OneBeatTokens.dark(),
          child: OneBeatShell(client: client),
        ),
      ),
    );
    await tester.pump();
  }

  // The window's own minimum, and a size a large display would use. A shell
  // that throws during layout paints nothing at all.
  for (final Size size in <Size>[const Size(1280, 720), const Size(1920, 1200)]) {
    testWidgets('the shell builds a frame at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, size: size);
      expect(tester.takeException(), isNull);
      // The playlist, as the design screens open on.
      expect(find.byType(ArrangementView), findsOneWidget);
    });
  }

  testWidgets('the rail switches the workspace it points at', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(1440, 900));

    // Each rail tile carries its action id as a key, which is how the
    // reachability test finds them too.
    Future<void> tapRail(String actionId) async {
      await tester.tap(find.byKey(actionKey(actionId)));
      await tester.pump();
    }

    await tapRail('view.channels');
    expect(find.byType(ChannelRack), findsOneWidget);
    expect(find.byType(ArrangementView), findsNothing);

    await tapRail('view.pianoRoll');
    expect(find.byType(PianoRoll), findsOneWidget);

    await tapRail('view.mixer');
    expect(find.byType(MixerRoutingView), findsOneWidget);

    await tapRail('view.playlist');
    expect(find.byType(ArrangementView), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
