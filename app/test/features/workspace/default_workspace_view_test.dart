import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/workspace/default_workspace_view.dart';

import '../../support/app_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('DefaultWorkspaceView renders dual-pane empty states and headers', (
    WidgetTester tester,
  ) async {
    bool insertPatternClicked = false;
    bool dragAudioClicked = false;
    bool addInstrumentClicked = false;
    bool browseBuiltinsClicked = false;
    bool addLaneClicked = false;

    await pumpForTest(
      tester,
      DefaultWorkspaceView(
        vm: const DefaultWorkspaceVm(),
        onInsertPatternClip: () => insertPatternClicked = true,
        onDragAudio: () => dragAudioClicked = true,
        onAddInstrument: () => addInstrumentClicked = true,
        onBrowseBuiltins: () => browseBuiltinsClicked = true,
        onAddLane: () => addLaneClicked = true,
      ),
      size: const Size(1600, 1000),
    );

    // Playlist pane headers & copy
    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('Untitled.onebeat · nothing here yet'), findsOneWidget);
    expect(find.text('Add your first clip'), findsOneWidget);
    expect(find.text('Insert pattern clip'), findsOneWidget);
    expect(find.text('Drag audio here'), findsOneWidget);
    expect(find.text('or press ⌘R · the menu bar has it too'), findsOneWidget);
    expect(find.text('Lane 1'), findsOneWidget);
    expect(find.text('empty'), findsOneWidget);

    // Channel rack pane headers & copy
    expect(find.text('CHANNEL RACK — Pattern 1 (empty)'), findsOneWidget);
    expect(find.text('a step is a note'), findsOneWidget);
    expect(find.text('Add an instrument to Pattern 1'), findsOneWidget);
    expect(find.text('Add instrument'), findsOneWidget);
    expect(find.text('Browse built-ins'), findsOneWidget);

    // Test actions
    await tester.tap(find.text('Insert pattern clip'));
    await tester.pump();
    expect(insertPatternClicked, isTrue);

    await tester.tap(find.text('Drag audio here'));
    await tester.pump();
    expect(dragAudioClicked, isTrue);

    await tester.tap(find.text('Add instrument'));
    await tester.pump();
    expect(addInstrumentClicked, isTrue);

    await tester.tap(find.text('Browse built-ins'));
    await tester.pump();
    expect(browseBuiltinsClicked, isTrue);

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(addLaneClicked, isTrue);
  });
}
