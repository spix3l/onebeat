// A melody lane's piano-roll preview and a step lane's grid are two drawings
// of the same bar. These tests pin the arithmetic that keeps them one bar: the
// preview's time base is the pattern's span, and its columns are the grid's
// columns.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen_vm.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';
import 'package:onebeat/src/features/channel_rack/rack_toolbar.dart';

import '../../support/ui_harness.dart';

const int _stepTicks = 240;
const int _columns = 16;
const int _span = _columns * _stepTicks;

const RackToolbarVm _toolbar = RackToolbarVm(channelType: 'Synth', group: 'All', snap: '1/4', steps: 16);

RackRowVm _melodyRow() => RackRowVm(
  name: 'Keys',
  type: 'Synth',
  color: const Color(0xFF7FC8F8),
  steps: List<StepVm>.filled(_columns, const StepVm.off()),
  vol: 0.7,
  pan: 0.5,
  route: '→ D1',
  // A riff that stops a quarter of the way in: the case that used to be
  // stretched across the whole lane.
  previewNotes: const <RackPreviewNoteVm>[
    RackPreviewNoteVm(startTick: 0, lengthTicks: 240, midiNote: 60),
    RackPreviewNoteVm(startTick: 720, lengthTicks: 240, midiNote: 64),
  ],
);

RackPianoPreview _preview(WidgetTester tester) => tester.widget<RackPianoPreview>(find.byType(RackPianoPreview));

void main() {
  setUpAll(loadAppFonts);

  test('a tick lands on the column of the step that plays it', () {
    final SizeTokens size = OneBeatTokens.dark().size;

    for (int step = 0; step < _columns; step++) {
      expect(
        rackTickX(size, columns: _columns, spanTicks: _span, tick: step * _stepTicks),
        rackColumnStart(size, step),
        reason: 'the note at step $step must start where step $step starts',
      );
    }
  });

  test('a tick inside a column is placed inside that column, never in the gap', () {
    final SizeTokens size = OneBeatTokens.dark().size;

    final double half = rackTickX(size, columns: _columns, spanTicks: _span, tick: _stepTicks + _stepTicks ~/ 2);
    expect(half, rackColumnStart(size, 1) + size.rackStepCell / 2);

    // The gaps are not time: half the ticks is not half the pixels, because the
    // group gaps sit between the columns rather than inside them.
    final double middle = rackTickX(size, columns: _columns, spanTicks: _span, tick: _span ~/ 2);
    expect(middle, rackColumnStart(size, _columns ~/ 2));
  });

  test('ticks outside the pattern clamp to the ends of the lane', () {
    final SizeTokens size = OneBeatTokens.dark().size;

    expect(rackTickX(size, columns: _columns, spanTicks: _span, tick: -240), 0);
    expect(
      rackTickX(size, columns: _columns, spanTicks: _span, tick: _span * 2),
      rackColumnStart(size, _columns - 1) + size.rackStepCell,
    );
  });

  testWidgets('the lane hands the preview the pattern span, not the notes\' extent', (WidgetTester tester) async {
    await pumpUi(
      tester,
      SizedBox(
        width: 1200,
        child: ObRackRow(vm: _melodyRow(), gridStepCount: _columns, stepTicks: _stepTicks, playingTick: 480),
      ),
    );

    expect(_preview(tester).spanTicks, _span);
    expect(_preview(tester).stepCount, _columns);
  });

  testWidgets('the rack screen passes its own time base down to a melody lane', (WidgetTester tester) async {
    await pumpUi(
      tester,
      SizedBox(
        width: 1400,
        height: 600,
        child: ChannelRackScreen(
          vm: ChannelRackScreenVm(
            toolbar: _toolbar,
            stepCount: _columns,
            stepTicks: _stepTicks,
            rows: <RackRowVm>[_melodyRow()],
            playingTick: 960,
          ),
        ),
      ),
    );

    expect(_preview(tester).spanTicks, _span, reason: 'the preview counts in the rack\'s ticks, not its own');
    expect(_preview(tester).stepCount, _columns);
    expect(_preview(tester).playingTick, 960, reason: 'one read head position for the whole rack');
  });

  testWidgets('a lane drawn outside a rack still renders, on its notes alone', (WidgetTester tester) async {
    await pumpUi(tester, SizedBox(width: 1200, child: ObRackRow(vm: _melodyRow())));

    expect(_preview(tester).spanTicks, isNull);
    expect(tester.takeException(), isNull);
  });
}
