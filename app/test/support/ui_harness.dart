// The shared widget-test harness for the rebuilt UI (UI-A-02).
//
// Every component and screen golden pumps through here, so they all agree on
// fonts, surface size and theme wrapping. A golden that disagrees with the
// mockups should disagree for one reason — the widget it tests — not because
// two tests wrapped the same widget differently.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';

/// Loads the app's two real font families into the test binding.
///
/// Without this every glyph is the test fallback's fixed-width box, which
/// measures nothing like Archivo or MartianMono. Goldens then record blocks
/// instead of text, and any test that asks "does this fit?" measures a font
/// the app does not ship. Call once from `setUpAll`, before any golden runs.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const Map<String, String> families = <String, String>{
    'Archivo': '../third_party/fonts/archivo/Archivo[wdth,wght].ttf',
    'MartianMono': '../third_party/fonts/martian_mono/MartianMono[wdth,wght].ttf',
  };
  for (final MapEntry<String, String> family in families.entries) {
    final FontLoader loader = FontLoader(family.key)
      ..addFont(File(family.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

/// Pumps [child] inside the app's real chrome at a [size] window.
///
/// The child is wrapped in the dark [OneBeatTheme], `Directionality` and a
/// `MediaQuery` at `devicePixelRatio: 1.0` with animations disabled, so the
/// render is deterministic across machines and CI runs.
///
/// Pass [center] for component goldens: the child is laid out at its natural
/// size on a [ColorTokens.surfaceSunken] background, so the golden records the
/// component rather than a stretched copy of it. Screen goldens leave [center]
/// false and fill the whole surface.
Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1600, 1000),
  bool center = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final OneBeatTokens tokens = OneBeatTokens.dark();

  // The dropdown (and any future overlay popover) needs a real `Overlay` to
  // render into, exactly like the `WidgetsApp` the real app runs under. The
  // overlay's only entry is the widget under test, so when [center] is false
  // the child still fills the surface, and when it is true the `Center` is the
  // entry's child — the overlay fills the surface and the `Center` hands the
  // child loose constraints, keeping component layout identical to before.
  final Widget entry = center ? Center(child: child) : child;

  final Widget content = OneBeatTheme(
    tokens: tokens,
    child: Localizations(
      // The real app runs under `WidgetsApp`, which supplies these. Widgets
      // that announce themselves to assistive tech — the reorderable rack lanes
      // are the first — assert on their presence, so the harness has to stand
      // in the same place the app does.
      locale: const Locale('en', 'US'),
      delegates: const <LocalizationsDelegate<Object>>[
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1.0,
            disableAnimations: true,
          ),
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(builder: (BuildContext context) => entry),
            ],
          ),
        ),
      ),
    ),
  );

  await tester.pumpWidget(
    ColoredBox(color: tokens.color.surfaceSunken, child: content),
  );
}

/// The golden matcher for a component or screen.
///
/// Goldens live in a `goldens/` folder colocated with the calling test, named
/// `<name>.png` — so a test in `test/ui_kit/` writes
/// `test/ui_kit/goldens/<name>.png`. A component's variants — states, content,
/// themes — are composed into that one file rather than given sibling files.
Matcher uiGolden(String name) => matchesGoldenFile('goldens/$name.png');
