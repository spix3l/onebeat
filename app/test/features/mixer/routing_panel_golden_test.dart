// Routing panel (UI-B-10): the Drums Bus golden, plus the slider and toggle
// behaviour the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/mixer/routing_panel.dart';

import '../../support/ui_harness.dart';

/// The Drums Bus routing, verbatim from `screens/routing-mixer.png`.
final RoutingPanelVm demoRouting = RoutingPanelVm(
  trackName: 'Drums Bus',
  feeds: <FeedVm>[
    FeedVm(
      name: 'Kick 808',
      color: channelColors[0],
      routeText: 'out 1 → Drums Bus',
    ),
    FeedVm(
      name: 'Snare',
      color: channelColors[5],
      routeText: 'out 1 → Drums Bus',
    ),
    FeedVm(
      name: 'Hats',
      color: channelColors[1],
      routeText: 'out 1 → Drums Bus',
    ),
    FeedVm(
      name: 'Clap',
      color: channelColors[7],
      routeText: 'out 1 → Drums Bus',
    ),
  ],
  feedsInto: <FeedVm>[
    FeedVm(name: 'Master', color: channelColors[7], routeText: '→ output'),
  ],
  sends: const <SendVm>[
    SendVm(name: '→ Reverb Send', value: 0.42, valueText: '0.42', pre: true),
    SendVm(name: '→ Delay', value: 0.18, valueText: '0.18', pre: false),
  ],
  sidechain: SidechainVm(
    sourceName: 'Sub Bass',
    sourceColor: channelColors[3],
    targetName: 'Drums Bus',
    targetCaption: 'compressor key input',
    amountText: '−6 dB',
  ),
  caption:
      'Whenever Sub Bass hits, the Drums Bus compressor ducks a little — the '
      'kick steps aside so the bass punches. That\'s the whole sidechain.',
);

/// The panel's own size in the mockup, at the export's 2× scale.
const Size _panel = Size(1092, 880);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the Drums Bus routing renders as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      ObRoutingPanel(key: const Key('routing'), vm: demoRouting),
      size: _panel,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('routing')),
      uiGolden('routing_panel'),
    );
  });

  testWidgets('every section says what it holds', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, ObRoutingPanel(vm: demoRouting), size: _panel);
    expect(find.text('ROUTING — DRUMS BUS'), findsOneWidget);
    expect(find.text('FEEDS THIS TRACK'), findsOneWidget);
    expect(find.text('4 inputs'), findsOneWidget);
    expect(find.text('THIS TRACK FEEDS'), findsOneWidget);
    expect(find.text('→ output'), findsOneWidget);
    expect(find.text('PRE'), findsOneWidget);
    expect(find.text('POST'), findsOneWidget);
    expect(find.textContaining('the whole sidechain'), findsOneWidget);
  });

  testWidgets('tapping a feed reports its index', (WidgetTester tester) async {
    final List<int> tapped = <int>[];
    await pumpUi(
      tester,
      ObRoutingPanel(vm: demoRouting, onFeedTap: tapped.add),
      size: _panel,
    );
    await tester.tap(find.text('Hats'));
    expect(tapped, <int>[2]);
  });

  testWidgets('dragging a send reports its index and new value', (
    WidgetTester tester,
  ) async {
    final List<(int, double)> changes = <(int, double)>[];
    await pumpUi(
      tester,
      ObRoutingPanel(
        vm: demoRouting,
        onSendChange: (int i, double v) => changes.add((i, v)),
      ),
      size: _panel,
    );
    final Rect slider = tester.getRect(find.byType(SendRow).first).deflate(0);
    // Tap three-quarters of the way along the first send's slider.
    await tester.tapAt(
      Offset(slider.right - 320, slider.center.dy),
    );
    expect(changes, hasLength(1));
    expect(changes.single.$1, 0);
    expect(changes.single.$2, greaterThan(0));
  });

  testWidgets('the pre/post tag and the sidechain switch report taps', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ObRoutingPanel(
        vm: demoRouting,
        onPrePostToggle: (int i) => fired.add('prepost:$i'),
        onSidechainToggle: () => fired.add('sidechain'),
      ),
      size: _panel,
    );
    await tester.tap(find.text('PRE'));
    await tester.tap(find.text('POST'));
    await tester.tap(find.text('Enabled'));
    expect(fired, <String>['prepost:0', 'prepost:1']);
    // The switch is beside the label, not the label itself.
    await tester.tap(find.byType(SidechainCard));
    expect(fired, <String>['prepost:0', 'prepost:1']);
  });

  testWidgets('a disabled sidechain renders its off state', (
    WidgetTester tester,
  ) async {
    final RoutingPanelVm off = RoutingPanelVm(
      trackName: demoRouting.trackName,
      feeds: demoRouting.feeds,
      feedsInto: demoRouting.feedsInto,
      sends: demoRouting.sends,
      caption: demoRouting.caption,
      sidechain: SidechainVm(
        sourceName: 'Sub Bass',
        sourceColor: channelColors[3],
        targetName: 'Drums Bus',
        targetCaption: 'compressor key input',
        amountText: '−6 dB',
        enabled: false,
      ),
    );
    await pumpUi(tester, ObRoutingPanel(vm: off), size: _panel);
    expect(find.byType(SidechainCard), findsOneWidget);
    expect(find.text('−6 dB'), findsOneWidget);
  });

  testWidgets('a track with no sidechain drops the section entirely', (
    WidgetTester tester,
  ) async {
    final RoutingPanelVm plain = RoutingPanelVm(
      trackName: 'Soft Keys',
      feeds: const <FeedVm>[],
      feedsInto: demoRouting.feedsInto,
      sends: const <SendVm>[],
      caption: 'Soft Keys goes straight to Music, and nothing ducks it.',
    );
    await pumpUi(tester, ObRoutingPanel(vm: plain), size: _panel);
    expect(find.byType(SidechainCard), findsNothing);
    expect(find.text('SIDECHAIN'), findsNothing);
    expect(find.text('0 inputs'), findsOneWidget);
  });
}
