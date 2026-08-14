// The shell, assembled and driven (OB-3-14 §1, UI-D-01..UI-D-09).
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/channel_rack/rack_binding.dart';
import 'package:onebeat/src/features/mixer/mixer_binding.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_binding.dart';
import 'package:onebeat/src/features/playlist/playlist_binding.dart';
import 'package:onebeat/src/features/shell/shell_binding.dart';
import 'package:onebeat/src/ui_kit/rail_button.dart';

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
          child: ShellBinding(client: client),
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
      expect(find.byType(PlaylistBinding), findsOneWidget);
    });
  }

  testWidgets('the rail switches the workspace it points at', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(1440, 900));

    // Rail buttons: 0=Playlist, 1=Channels, 2=Piano, 3=Mixer
    await tester.tap(find.byType(ObRailButton).at(1));
    await tester.pump();
    expect(find.byType(RackBinding), findsOneWidget);
    expect(find.byType(PlaylistBinding), findsNothing);

    await tester.tap(find.byType(ObRailButton).at(2));
    await tester.pump();
    expect(find.byType(PianoRollBinding), findsOneWidget);

    await tester.tap(find.byType(ObRailButton).at(3));
    await tester.pump();
    expect(find.byType(MixerBinding), findsOneWidget);

    await tester.tap(find.byType(ObRailButton).at(0));
    await tester.pump();
    expect(find.byType(PlaylistBinding), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
