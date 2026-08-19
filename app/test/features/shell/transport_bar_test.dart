// Transport bar (UI-B-02): the golden of the mockup's transport row, plus the
// control callbacks the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/shell/transport_bar.dart';
import 'package:onebeat/src/ui_kit/transport_button.dart';

import '../../support/ui_fixtures.dart';
import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders the transport row as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObTransportBar(
        key: Key('transportBar'),
        vm: ObTransportBarVm(
          title: 'ONEBEAT',
          playing: true,
          looping: false,
          bpmText: demoBpm,
          sigText: demoSig,
          positionText: demoPosition,
          durationText: '01:36',
          meterLeft: 0.72,
          meterRight: 0.65,
          searchHint: 'Search actions',
        ),
      ),
      size: const Size(1600, 68),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('transportBar')),
      uiGolden('transport_bar'),
    );
  });

  testWidgets('transport controls fire their callbacks', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ObTransportBar(
        vm: const ObTransportBarVm(
          title: 'ONEBEAT',
          playing: false,
          looping: false,
          bpmText: demoBpm,
          sigText: demoSig,
          positionText: demoPosition,
          durationText: '01:36',
          meterLeft: 0.5,
          meterRight: 0.5,
          searchHint: 'Search actions',
        ),
        onTogglePlay: () => fired.add('play'),
        onToggleLoop: () => fired.add('loop'),
        onExport: () => fired.add('export'),
        onSearchTap: () => fired.add('search'),
      ),
      size: const Size(1600, 68),
    );
    // undo, redo, play, stop, loop — play is the third well.
    await tester.tap(find.byType(ObTransportButton).at(2));
    await tester.tap(find.byType(ObTransportButton).at(4));
    await tester.tap(find.text('Export'));
    await tester.tap(find.text('Search actions'));
    expect(fired, <String>['play', 'loop', 'export', 'search']);
  });
}
