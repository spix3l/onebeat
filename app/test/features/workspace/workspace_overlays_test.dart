// The workspace overlays over their backdrops (UI-C-12).
//
// The golden is the whole window — twice, one variant each — because both
// mockups are about something sitting *over* the workspace: the golden has to
// show what it is over, or it is a picture of a popover rather than a picture
// of the screen.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/browser/browser_panel.dart';
import 'package:onebeat/src/features/mixer/mixer_strip.dart';
import 'package:onebeat/src/features/playlist/playlist_canvas.dart';
import 'package:onebeat/src/features/playlist/timeline_ruler.dart';
import 'package:onebeat/src/features/workspace/workspace_overlays.dart';
import 'package:onebeat/src/features/workspace/workspace_vm.dart';
import 'package:onebeat/src/ui_kit/popover_menu.dart';

import '../../support/ui_frame.dart';
import '../../support/ui_harness.dart';
import '../browser/fixture.dart';
import '../playlist/fixture.dart';
import 'fixture.dart';

/// The workspace under the overlays: the browser column and the playlist,
/// with the layouts pill sitting in the browser's header where the mockup
/// puts it.
class _Workspace extends StatelessWidget {
  const _Workspace({this.showPill = true});

  final bool showPill;

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: tokens.size.browserWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showPill)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.spacing.xl,
                    vertical: tokens.spacing.sm,
                  ),
                  child: const LayoutsPill(vm: demoLayouts),
                ),
              Expanded(
                child: ObBrowserPanel(
                  vm: ObBrowserPanelVm(
                    nodes: demoBrowserSamples,
                    selectedId: 'sub',
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PlaylistHeader(
                title: 'Playlist',
                right: demoPlaylist.headerRight,
              ),
              const PlaylistRuler(pxPerBar: 38.3),
              Expanded(child: PlaylistCanvas(vm: demoPlaylist)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The fader board a detached Mixer window holds. The window takes a child
/// slot rather than importing the mixer, so this is what a caller passes —
/// which is what UI-D-05 will do with real strips.
class _FaderBoard extends StatelessWidget {
  const _FaderBoard();

  @override
  Widget build(BuildContext context) {
    final OneBeatTokens tokens = OneBeatTheme.of(context);
    return Padding(
      padding: EdgeInsets.all(tokens.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final MixerStripVm strip in demoDetachedStrips) ObMixerStrip.fader(vm: strip),
        ],
      ),
    );
  }
}

/// One mockup-sized window the golden is recorded in.
Widget _variant(Widget frame) => SizedBox(width: 1600, height: 1000, child: frame);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the window and mid-drag variants render as the golden', (
    WidgetTester tester,
  ) async {
    await pumpUi(
      tester,
      Row(
        key: const Key('screens'),
        children: <Widget>[
          _variant(
            UiFrame(
              status: demoWorkspaceWindowStatus,
              menuBar: demoMenuBar(activeIndex: 5),
              content: const _Workspace(),
              overlay: const Stack(
                children: <Widget>[
                  // The menu is anchored under its pill; the window floats
                  // over the right of the workspace, as the mockup shows both
                  // at once.
                  Positioned(
                    left: 92,
                    top: 134,
                    child: LayoutsMenu(vm: demoLayouts),
                  ),
                  Positioned(
                    left: 903,
                    top: 104,
                    child: DetachedPanelWindow(
                      title: 'Mixer',
                      subtitle: 'Drums Bus selected',
                      child: _FaderBoard(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _variant(
            const UiFrame(
              status: demoWorkspaceDragStatus,
              content: Stack(
                children: <Widget>[
                  _Workspace(showPill: false),
                  Positioned.fill(
                    // The drag layer covers the content area only: the chrome
                    // does not accept a drop, so it does not light up.
                    child: WorkspaceDragLayer(vm: demoWorkspaceDrag),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      size: const Size(3200, 1000),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('screens')),
      uiGolden('workspace_overlays'),
    );
  });

  testWidgets('the pill shows the current layout, not the first one', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, const LayoutsPill(vm: demoLayouts), center: true);
    expect(find.text('Beatmaking'), findsOneWidget);
    expect(find.text('Layouts'), findsOneWidget);

    const WorkspaceLayoutsVm mixing = WorkspaceLayoutsVm(
      layouts: <LayoutVm>[
        LayoutVm(name: 'Beatmaking'),
        LayoutVm(name: 'Mixing', current: true),
      ],
    );
    expect(mixing.currentName, 'Mixing');
  });

  testWidgets('the menu ticks the current layout and rules off the actions', (
    WidgetTester tester,
  ) async {
    await pumpUi(tester, const LayoutsMenu(vm: demoLayouts), center: true);
    for (final LayoutVm layout in demoLayouts.layouts) {
      expect(find.text(layout.name), findsOneWidget);
    }
    for (final String action in <String>[
      'Save as…',
      'Rename…',
      'Delete…',
      'Reset to default',
    ]) {
      expect(find.text(action), findsOneWidget);
    }

    final ObPopoverMenuVm vm = layoutsMenuVm(demoLayouts);
    // Only the current layout is ticked, and it is the only accented row.
    expect(
      vm.rows.where((ObMenuRowVm r) => r.checked).map((ObMenuRowVm r) => r.label),
      <String>['Beatmaking'],
    );
    expect(
      vm.rows.where((ObMenuRowVm r) => r.tone == ObMenuRowTone.danger).map((ObMenuRowVm r) => r.label),
      <String>['Delete…'],
    );
    // `Reset to default` sits behind its own rule — never the row you hit by
    // accident.
    expect(vm.sections.last.separated, isTrue);
    expect(vm.sections.last.rows.single.label, 'Reset to default');
  });

  testWidgets('every layout menu action reports itself', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      LayoutsMenu(
        vm: demoLayouts,
        onLayoutSelect: (int index) => fired.add('layout:$index'),
        onSaveAs: () => fired.add('save'),
        onRename: () => fired.add('rename'),
        onDelete: () => fired.add('delete'),
        onReset: () => fired.add('reset'),
      ),
      center: true,
    );
    await tester.tap(find.text('Mixing'));
    await tester.tap(find.text('Save as…'));
    await tester.tap(find.text('Rename…'));
    await tester.tap(find.text('Delete…'));
    await tester.tap(find.text('Reset to default'));
    expect(fired, <String>[
      'layout:2',
      'save',
      'rename',
      'delete',
      'reset',
    ]);
  });

  testWidgets('the detached window leaves the system its own controls', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await pumpUi(
      tester,
      DetachedPanelWindow(
        title: 'Mixer',
        subtitle: 'Drums Bus selected',
        onAdd: () => fired.add('add'),
        onClose: () => fired.add('close'),
        child: const _FaderBoard(),
      ),
      center: true,
    );
    final OneBeatTokens tokens = OneBeatTokens.dark();
    // The title starts after the inset the OS's close/minimise/zoom buttons
    // occupy — we make room for them rather than drawing our own.
    final Rect window = tester.getRect(find.byType(DetachedPanelWindow));
    final Rect title = tester.getRect(find.text('Mixer'));
    expect(
      title.left - window.left,
      greaterThanOrEqualTo(
        tokens.size.titleBarInset,
      ),
    );
  });

  testWidgets('the drag layer offers four edges and a tab', (
    WidgetTester tester,
  ) async {
    final List<DockEdge?> fired = <DockEdge?>[];
    await pumpUi(
      tester,
      WorkspaceDragLayer(vm: demoWorkspaceDrag, onDock: fired.add),
    );
    for (final DockTargetVm target in demoWorkspaceDrag.targets) {
      expect(find.text(target.label), findsOneWidget);
    }
    expect(find.text('Dock as tab'), findsOneWidget);
    expect(find.text('CHANNEL RACK → PLAYLIST'), findsOneWidget);
    expect(find.text('CHANNEL RACK'), findsOneWidget);

    await tester.tap(find.text('Dock left'));
    await tester.tap(find.text('Dock bottom'));
    await tester.tap(find.text('Dock as tab'));
    expect(fired, <DockEdge?>[DockEdge.left, DockEdge.bottom, null]);
  });
}
