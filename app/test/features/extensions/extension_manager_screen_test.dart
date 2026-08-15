// The extension manager's three screens (UI-C-11) in one golden, plus the
// callbacks and the copy the golden cannot assert on its own.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/extensions/extension_manager_screen.dart';
import 'package:onebeat/src/features/extensions/extension_manager_vm.dart';
import 'package:onebeat/src/features/playlist/clip_card.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';
import 'package:onebeat/src/features/playlist/timeline_ruler.dart';
import 'package:onebeat/src/ui_kit/popover_menu.dart';

import '../../support/ui_frame.dart';
import '../../support/ui_harness.dart';
import '../playlist/fixture.dart';
import 'fixture.dart';

/// The Tools menu, anchored under its menu-bar item the way the mockup draws
/// it. The offsets are the anchor's position in the frame, which the shell
/// computes; here they are what the PNG measures.
class _ToolsMenuOverlay extends StatelessWidget {
  const _ToolsMenuOverlay();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 236,
      top: 24,
      child: ObPopoverMenu(vm: demoToolsMenu),
    );
  }
}

/// The playlist band above the docked panels in `screens/ext-panel.png`: four
/// clips on one lane, with the playhead through them.
class _PanelBackdrop extends StatelessWidget {
  const _PanelBackdrop();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    final List<ClipVm> band = <ClipVm>[
      for (int i = 0; i < 4; i++)
        ClipVm(
          id: i,
          name: '',
          duration: '',
          color: demoClips[i == 0 || i == 1 ? 0 : (i == 2 ? 3 : 6)].color,
          startBar: 0.25 + i * 3.55,
          lengthBars: 2.8,
          lane: 0,
        ),
    ];
    return SizedBox(
      height: tokens.size.playlistRulerHeight + tokens.size.playlistLaneHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PlaylistRuler(pxPerBar: 72),
          Expanded(
            child: PlaylistCanvas(
              vm: PlaylistVm(
                clips: band,
                pxPerBar: 72,
                playheadBar16ths: 82,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One mockup-sized window the golden is recorded in.
Widget _variant(Widget frame) => SizedBox(width: 1600, height: 1000, child: frame);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the manager, empty and docked-panel screens render as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Row(
        key: const Key('screens'),
        children: <Widget>[
          _variant(
            UiFrame(
              rail: demoExtensionsRail,
              menuBar: demoMenuBar(activeIndex: 4),
              status: demoExtensionStatus,
              overlay: const _ToolsMenuOverlay(),
              content: const ExtensionManagerScreen(vm: demoExtensionManager),
            ),
          ),
          _variant(
            const UiFrame(
              rail: demoExtensionsRail,
              status: demoExtensionEmptyStatus,
              content: ExtensionEmptyScreen(vm: demoExtensionEmpty),
            ),
          ),
          _variant(
            UiFrame(
              rail: demoWorkspaceRail,
              status: demoExtensionPanelStatus,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _PanelBackdrop(),
                  Expanded(
                    child: ExtensionPanelScreen(vm: demoExtensionPanelScreen),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      size: const Size(4800, 1000),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('screens')),
      uiGolden('extension_manager_screen'),
    );
  });

  testWidgets('every capability, granted or not, states its reason', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ExtensionManagerScreen(vm: demoExtensionManager),
    );
    for (final CapabilityVm capability in demoExtensionDetail.capabilities) {
      expect(find.text(capability.name), findsOneWidget);
      expect(find.text(capability.note), findsOneWidget);
    }
    // The denied ones are the point: a capability that was never granted is
    // shown and explained, not omitted.
    expect(find.text('never granted'), findsOneWidget);
    expect(find.text('impossible by design'), findsOneWidget);
  });

  testWidgets('the crashed extension is outlined, tagged and switched off', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ExtensionManagerScreen(vm: demoExtensionManager),
    );
    expect(find.text('CRASHED'), findsOneWidget);
    final Iterable<ObSwitch> switches = tester.widgetList<ObSwitch>(
      find.byType(ObSwitch),
    );
    expect(switches.map((ObSwitch s) => s.on), <bool>[
      true,
      true,
      true,
      false,
    ]);
  });

  testWidgets('selecting, toggling and installing report themselves', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ExtensionManagerScreen(
        vm: demoExtensionManager,
        onSelect: (String id) => fired.add('select:$id'),
        onToggle: (String id, bool on) => fired.add('toggle:$id:$on'),
        onInstall: () => fired.add('install'),
      ),
    );
    await tester.tap(find.text('Clip Roulette'));
    await tester.tap(find.byType(ObSwitch).at(2));
    await tester.tap(find.text('Install from file…'));
    expect(fired, <String>[
      'select:clip-roulette',
      'toggle:drum-fill:false',
      'install',
    ]);
  });

  testWidgets('the detail panel buttons and crash actions report themselves', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ExtensionManagerScreen(
        vm: demoExtensionManager,
        onToggleSelected: () => fired.add('enabled'),
        onUninstall: () => fired.add('uninstall'),
        onCrashAction: (int index) => fired.add('crash:$index'),
      ),
    );
    await tester.tap(find.text('Enabled'));
    // `Uninstall` appears twice — in the header and in the crash card. The
    // header's is the first in the tree.
    await tester.tap(find.text('Uninstall').first);
    await tester.tap(find.text('Report crash'));
    expect(fired, <String>['enabled', 'uninstall', 'crash:1']);
  });

  testWidgets('the Tools menu marks the screen you are already on', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      const ObPopoverMenu(vm: demoToolsMenu),
      center: true,
    );
    for (final ObMenuRowVm row in demoToolsMenu.rows) {
      expect(find.text(row.label), findsOneWidget);
      expect(find.text(row.shortcut!), findsOneWidget);
    }
    final ObMenuRowVm active = demoToolsMenu.rows.singleWhere(
      (ObMenuRowVm r) => r.tone == ObMenuRowTone.active,
    );
    expect(active.label, 'Extension manager…');
  });

  testWidgets('the empty state pitches rather than apologises', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ExtensionEmptyScreen(
        vm: demoExtensionEmpty,
        onWriteScript: () => fired.add('write'),
        onBrowse: () => fired.add('browse'),
        onTemplate: () => fired.add('template'),
      ),
    );
    expect(find.text('This is where OneBeat bends'), findsOneWidget);
    for (final ExtensionStepVm step in demoExtensionEmpty.steps) {
      expect(find.text(step.title), findsOneWidget);
      expect(find.text(step.body), findsOneWidget);
    }
    await tester.tap(find.text('Write your first script'));
    await tester.tap(find.text('Browse the library'));
    await tester.tap(find.text('Start from a template'));
    expect(fired, <String>['write', 'browse', 'template']);
  });

  testWidgets('the extension panel wears the same chrome as its neighbours', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      ExtensionPanelScreen(
        vm: demoExtensionPanelScreen,
        onRun: () => fired.add('run'),
        onUndo: () => fired.add('undo'),
        onClosePanel: () => fired.add('close'),
      ),
    );
    // The `EXT` badge is the only mark separating it from a native panel.
    expect(find.text('EXT'), findsOneWidget);
    expect(find.text('CHANNEL RACK'), findsOneWidget);
    expect(find.text('HARMONIZER'), findsOneWidget);
    expect(find.text('COMPRESSOR'), findsOneWidget);
    await tester.tap(find.text('Harmonize'));
    await tester.tap(find.text('Undo'));
    expect(fired, <String>['run', 'undo']);
  });

  test('the installed count is derived from the list, never passed', () {
    expect(demoExtensionManager.countLabel, '4 installed');
    final ExtensionManagerVm shorter = ExtensionManagerVm(
      extensions: <ExtensionVm>[demoExtensions.first],
      detail: demoExtensionDetail,
    );
    expect(shorter.countLabel, '1 installed');
  });

  test('the preview painter repaints on its notes and nothing else', () {
    final OneBeatTokens tokens = OneBeatTokens.dark();
    PreviewPainter build(List<PreviewNoteVm> notes) => PreviewPainter(
      notes: notes,
      gridLine: tokens.color.gridLine,
      note: tokens.color.noteFill,
      lineWidth: tokens.border.hairline,
      noteHeight: tokens.size.prNoteHeight,
      noteWidth: tokens.size.prVelocityStemWidth,
      radius: tokens.radius.xs,
    );
    const List<PreviewNoteVm> notes = <PreviewNoteVm>[
      PreviewNoteVm(x: 0.1, y: 0.1),
    ];
    final PreviewPainter base = build(notes);
    expect(build(notes).shouldRepaint(base), isFalse);
    expect(
      build(const <PreviewNoteVm>[PreviewNoteVm(x: 0.2, y: 0.1)]).shouldRepaint(base),
      isTrue,
    );
  });
}
