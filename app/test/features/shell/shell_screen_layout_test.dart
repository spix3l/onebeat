import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/browser/browser_panel.dart';
import 'package:onebeat/src/features/shell/rail_glyphs.dart';
import 'package:onebeat/src/features/shell/shell_screen.dart';
import 'package:onebeat/src/features/shell/shell_screen_vm.dart';
import 'package:onebeat/src/features/shell/side_rail.dart';
import 'package:onebeat/src/features/shell/status_bar.dart';
import 'package:onebeat/src/features/shell/transport_bar.dart';

import '../../support/ui_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('browser panel resizes horizontally from its right edge', (
    WidgetTester tester,
  ) async {
    const ShellScreenVm vm = ShellScreenVm(
      transport: ObTransportBarVm(
        title: 'ONEBEAT',
        playing: false,
        looping: false,
        bpmText: '124.00',
        sigText: '4/4',
        positionText: '01:01:000',
        durationText: '01:36',
        meterLeft: 0,
        meterRight: 0,
        searchHint: 'Search actions',
      ),
      rail: ObSideRailVm(
        items: <RailItemVm>[
          RailItemVm(icon: ObRailGlyphKind.help, label: 'Channels'),
          RailItemVm(icon: ObRailGlyphKind.grid, label: 'Playlist'),
          RailItemVm(icon: ObRailGlyphKind.sliders, label: 'Mixer'),
        ],
        activeIndex: 0,
      ),
      status: ObStatusBarVm(tone: StatusTone.ok, primary: 'Ready'),
      browser: ObBrowserPanelVm(
        nodes: <BrowserNodeVm>[
          BrowserFolderVm(id: 'instruments', name: 'Instruments'),
        ],
      ),
    );

    await pumpUi(
      tester,
      const ShellScreen(vm: vm, workspace: SizedBox.expand()),
      size: const Size(1600, 700),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ObBrowserPanel)).width, 240);
    await tester.drag(
      find.byKey(const Key('browser-resize-handle')),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(ObBrowserPanel)).width, 320);
  });
}
