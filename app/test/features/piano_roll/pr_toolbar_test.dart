// Piano roll toolbar (UI-B-07): the golden of the breadcrumb and tool row,
// plus the tool and dropdown behaviour the golden cannot show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/piano_roll/pr_toolbar.dart';

import '../../support/ui_harness.dart';

const PrToolbarVm _toolbar = PrToolbarVm(
  crumbs: <String>['Piano roll', 'Main Groove', 'Soft Keys'],
  pattern: 'Main Groove',
  scale: 'C min',
  snap: '1/4',
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders the toolbar as the golden', (WidgetTester tester) async {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      PrToolbar(
        key: const Key('toolbar'),
        vm: _toolbar,
        channelColor: channelColors[4],
      ),
      size: Size(1600, tokens.size.prToolbarHeight),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('toolbar')), uiGolden('pr_toolbar'));
  });

  testWidgets('the back button is the icon alone and reports its tap', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    final OneBeatTokens tokens = OneBeatTokens.dark();
    await pumpUi(
      tester,
      PrToolbar(
        vm: _toolbar,
        onTool: (PrTool tool) => fired.add('tool:${tool.name}'),
        onBack: () => fired.add('back'),
      ),
      size: Size(1600, tokens.size.prToolbarHeight),
    );
    expect(
      find.text('Back to playlist'),
      findsNothing,
      reason: 'the way back is the icon, not a labelled button',
    );
    await tester.tap(find.byKey(const Key('pr-back')));
    expect(fired, <String>['back']);
  });
}
