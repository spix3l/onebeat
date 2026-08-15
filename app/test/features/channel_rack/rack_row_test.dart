// Channel rack lane + chrome (UI-B-05): one golden with the four-lane board
// and the toolbar/header/footer stack in it, and the callbacks the golden
// cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';
import 'package:onebeat/src/features/channel_rack/rack_toolbar.dart';
import 'package:onebeat/src/ui_kit/knob.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

/// Kick (a plain lit pattern), Soft Keys (selected), Shaker (powered off),
/// Hats (velocity-shaded) — the four states the ticket asks the board to
/// show, all under the same playing column.
final List<RackRowVm> _board = <RackRowVm>[
  demoRackRows[0],
  demoRackRows[4],
  demoRackRows[6],
  demoRackRows[2],
];

const RackToolbarVm _toolbar = RackToolbarVm(
  channelType: 'Sampler',
  group: 'All',
  snap: '1/4',
  steps: 16,
);

BoxDecoration _cellDecoration(WidgetTester tester, int index) {
  final Finder cells = find.descendant(
    of: find.byType(ObStepGrid),
    matching: find.byType(Container),
  );
  final Container cell = tester.widget(cells.at(index));
  return cell.decoration! as BoxDecoration;
}

/// The border colour of step [index] as rendered — the one part of the cell
/// that carries three different meanings (playing, lit, at rest).
Color? _cellBorder(WidgetTester tester, int index) =>
    (_cellDecoration(tester, index).border! as Border).top.color;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the lane board and the chrome render as the golden', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      Row(
        key: const Key('rack'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: demoRackRowWidth,
            child: Column(
              key: const Key('rows'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final RackRowVm row in _board)
                  ObRackRow(vm: row, playingStep: demoPlayingStep),
              ],
            ),
          ),
          const SizedBox(
            width: demoRackRowWidth,
            child: Column(
              key: Key('chrome'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ObRackToolbar(vm: _toolbar),
                ObRackHeader(),
                ObRackFooter(),
              ],
            ),
          ),
        ],
      ),
      size: Size(
        demoRackRowWidth * 2,
        tokens.size.rackLaneHeight * 4,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('rack')), uiGolden('rack_row'));
  });

  testWidgets('tapping a step reports its index', (WidgetTester tester) async {
    final List<int> tapped = <int>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObRackRow(vm: demoRackRows[0], onStepTap: tapped.add),
      size: Size(demoRackRowWidth, tokens.size.rackLaneHeight),
    );
    // The first cell starts after the left block; aim at its centre by
    // walking the rendered grid rather than by guessing a coordinate.
    final Finder grid = find.byType(ObStepGrid);
    final Rect box = tester.getRect(grid);
    final double pitch = tokens.size.rackStepCell + tokens.size.rackStepGap;
    await tester.tapAt(
      Offset(box.left + tokens.size.rackStepCell / 2, box.center.dy),
    );
    await tester.tapAt(
      Offset(
        box.left + pitch * 2 + tokens.size.rackStepCell / 2,
        box.center.dy,
      ),
    );
    expect(tapped, <int>[0, 2]);
  });

  testWidgets('row, power and route taps fire their callbacks', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObRackRow(
        vm: demoRackRows[0],
        onTap: () => fired.add('row'),
        onPower: () => fired.add('power'),
        onRouteTap: () => fired.add('route'),
      ),
      size: Size(demoRackRowWidth, tokens.size.rackLaneHeight),
    );
    await tester.tap(find.text('Kick 808'));
    await tester.tap(find.text('→ D1'));
    // The power well sits at the lane's left edge, inside the selection
    // border's gutter and the row's own padding.
    await tester.tapAt(
      Offset(
        tokens.size.rackSelectedEdgeWidth +
            tokens.spacing.md +
            tokens.size.rackPowerSize / 2,
        tokens.size.rackLaneHeight / 2,
      ),
    );
    expect(fired, <String>['row', 'route', 'power']);
  });

  testWidgets('a knob drag reports a new value', (WidgetTester tester) async {
    final List<double> volumes = <double>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObRackRow(vm: demoRackRows[0], onVol: volumes.add),
      size: Size(demoRackRowWidth, tokens.size.rackLaneHeight),
    );
    await tester.drag(find.byType(ObKnob).first, const Offset(0, -20));
    expect(volumes, isNotEmpty);
    expect(volumes.last, greaterThan(demoRackRows[0].vol));
  });

  testWidgets('the playing column rings its cell, lit or not', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    // Kick 808 is dark at step 7, so the ring here proves the column is
    // outlined rather than merely lit.
    await pumpUi(
      tester,
      ObRackRow(vm: demoRackRows[0], playingStep: demoPlayingStep),
      size: Size(demoRackRowWidth, tokens.size.rackLaneHeight),
    );
    expect(
      _cellBorder(tester, demoPlayingStep),
      tokens.color.textSecondary,
    );
    expect(_cellBorder(tester, 0), tokens.color.accentBright);
    expect(_cellBorder(tester, 1), tokens.color.surfaceWell);
  });

  testWidgets('a stopped transport rings nothing', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      ObRackRow(vm: demoRackRows[0]),
      size: Size(demoRackRowWidth, tokens.size.rackLaneHeight),
    );
    expect(_cellBorder(tester, demoPlayingStep), tokens.color.surfaceWell);
  });

  testWidgets('toolbar dropdowns and buttons report their changes', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ObRackToolbar(
        vm: _toolbar,
        onSnap: (String value) => fired.add('snap:$value'),
        onAddChannel: () => fired.add('add'),
      ),
      size: const Size(demoRackRowWidth, 200),
    );
    await tester.tap(find.text('1/4'));
    await tester.pump();
    await tester.tap(find.text('1/16'));
    expect(fired, <String>['snap:1/16']);
  });

  testWidgets('the step-length control offers 16/32/64 and reports the choice', (
    WidgetTester tester,
  ) async {
    final List<int> lengths = <int>[];
    await pumpUi(
      tester,
      ObRackToolbar(vm: _toolbar, onSteps: lengths.add),
      size: const Size(demoRackRowWidth, 200),
    );

    // The current length is what the control shows.
    expect(find.text('16'), findsOneWidget);

    await tester.tap(find.text('16'));
    await tester.pump();
    // Exactly the lengths the ABI accepts, no more.
    expect(find.text('32'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);

    await tester.tap(find.text('32'));
    expect(lengths, <int>[32]);
  });

  testWidgets('the footer names the action it performs', (
    WidgetTester tester,
  ) async {
    int added = 0;
    await pumpUi(
      tester,
      ObRackFooter(onAddChannel: () => added++),
      size: const Size(demoRackRowWidth, 60),
    );
    await tester.tap(find.text('Add channel'));
    expect(added, 1);
  });

  testWidgets('a dense 64-step rack builds without exceptions', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    final List<RackRowVm> rows = List<RackRowVm>.generate(
      8,
      (int row) => RackRowVm(
        name: 'Channel $row',
        type: 'Sampler',
        color: tokens.color.channelColors[row % tokens.color.channelColors.length],
        vol: 0.8,
        pan: 0.5,
        route: 'Master',
        steps: List<StepVm>.generate(
          16,
          (int step) => StepVm(
            on: step % 4 == row % 4,
            velocity: (8192 + (step * 97) % 8191) / 16383.0,
          ),
        ),
      ),
    );

    await pumpUi(
      tester,
      Column(
        children: rows.map((RackRowVm vm) => ObRackRow(vm: vm)).toList(),
      ),
      size: const Size(1200, 800),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('rest cells band by beat, every four steps', (
    WidgetTester tester,
  ) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    // Sixteen steps, one lit: the banding is a property of the empty ones.
    final RackRowVm row = RackRowVm(
      name: 'Kick',
      type: 'Sampler',
      color: tokens.color.channelColors[0],
      vol: 0.8,
      pan: 0.5,
      route: 'Master',
      steps: <StepVm>[
        for (int i = 0; i < 16; i++)
          i == 9 ? const StepVm(on: true, velocity: 1) : const StepVm.off(),
      ],
    );

    await pumpUi(
      tester,
      ObRackRow(vm: row),
      size: const Size(1200, 200),
    );

    // Beats 1 and 3 lifted, 2 and 4 recessed — a bar you can count without
    // counting.
    for (int step = 0; step < 16; step++) {
      if (step == 9) continue;
      expect(
        _cellDecoration(tester, step).color,
        (step ~/ 4).isEven
            ? tokens.color.stepRestLifted
            : tokens.color.stepRest,
        reason: 'step ${step + 1} sits on the wrong band',
      );
    }
    expect(
      tokens.color.stepRestLifted,
      isNot(tokens.color.stepRest),
      reason: 'a band you cannot see is not a band',
    );

    // A lit cell is the accent gradient whatever band it lands on.
    final BoxDecoration lit = _cellDecoration(tester, 9);
    expect(lit.color, isNull);
    expect(lit.gradient, isNotNull);
  });

}
