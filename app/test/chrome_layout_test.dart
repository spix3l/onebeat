// Chrome widgets have to survive the constraints the top bar actually gives
// them (OB-3-14).
//
// This exists because of a real failure: `ReadoutWell` shrink-wraps when no
// width is passed, and a `Row` hands its non-flexible children an *unbounded*
// width. The well's inner row still asked for `MainAxisSize.max` with flexible
// children, which throws in `performLayout`. Nothing below the top bar could
// then lay out, and the app launched as a black window — with every widget
// test still green, because no test had ever put a chrome widget in a row.
//
// So the assertion here is not about pixels. It is: put each top-bar widget in
// the unbounded slot of a Row and finish a frame without an exception.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui/chrome.dart';
import 'package:onebeat/src/ui/engine_controller.dart' show WorkspaceView;

import 'support/stage3_harness.dart';

/// The widgets the top bar lays out side by side, each in the shape the shell
/// builds it.
Map<String, Widget> _topBarWidgets(OneBeatTokens tokens) {
  return <String, Widget>{
    'BrandMark': const BrandMark(version: 'v0.3 SEQUENCES'),
    'TitleBarInset': const TitleBarInset(),
    'TransportCluster': TransportCluster(
      playing: false,
      canUndo: true,
      canRedo: false,
      onTogglePlay: () {},
      onUndo: () {},
      onRedo: () {},
      onReturnToZero: () {},
      onToggleLoop: () {},
    ),
    // The two shapes the well is used in: sized (the tempo field) and
    // shrink-wrapped (the clock, which is as wide as its digits).
    'ReadoutWell sized': ReadoutWell(
      label: 'BPM',
      width: 180,
      child: Text('120.00', style: tokens.type.numericLarge),
    ),
    'ReadoutWell shrink-wrapped': ReadoutWell(
      label: 'BAR · BEAT · TICK',
      child: Text('01:01:000', style: tokens.type.numericLarge),
    ),
    'ReadoutWell unlabelled': ReadoutWell(
      label: '',
      child: Text('4/4', style: tokens.type.numericLarge),
    ),
    'ViewSwitcher': ViewSwitcher(
      activeView: WorkspaceView.arrangement,
      onSelect: (_) {},
    ),
    'SearchAffordance': SearchAffordance(onTap: () {}),
    'ExportButton': ExportButton(onPressed: () {}),
    'MasterPeakIndicator': const MasterPeakIndicator(),
  };
}

void main() {
  // Real fonts: block glyphs measure nothing like Archivo or MartianMono.
  setUpAll(loadAppFonts);

  final OneBeatTokens tokens = OneBeatTokens.dark();

  group('top-bar chrome lays out as a row child', () {
    for (final MapEntry<String, Widget> entry in _topBarWidgets(
      tokens,
    ).entries) {
      testWidgets('${entry.key} survives an unbounded width', (
        WidgetTester tester,
      ) async {
        // No Expanded: this is the unbounded slot, which is exactly the
        // constraint the shell's top bar hands each of these.
        await pumpForTest(
          tester,
          Row(children: <Widget>[entry.value]),
          size: const Size(1400, 60),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Mirrors the shell's `_TopBar` composition — same widgets, same order, same
  // one flexible slot — without the `EngineController` the private widget
  // needs. What is being checked is the *flex arrangement*: that the search
  // well is the thing that gives, so nothing at the right-hand end of the bar
  // is pushed off it.
  Widget topBarRow() {
    return Container(
      height: tokens.size.topBarHeight,
      // The real bar's own gutters count against the fit.
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
      child: Row(
        children: <Widget>[
          const TitleBarInset(),
          const BrandMark(version: 'v0.3 SEQUENCES'),
          SizedBox(width: tokens.spacing.lg),
          TransportCluster(
            playing: false,
            canUndo: true,
            canRedo: true,
            onTogglePlay: () {},
            onUndo: () {},
            onRedo: () {},
            onReturnToZero: () {},
            onToggleLoop: () {},
          ),
          SizedBox(width: tokens.spacing.md),
          ReadoutWell(
            label: 'BPM',
            child: Text('120.00', style: tokens.type.numericLarge),
          ),
          SizedBox(width: tokens.spacing.xs),
          ReadoutWell(
            label: 'SIG',
            child: Text('4/4', style: tokens.type.numericLarge),
          ),
          SizedBox(width: tokens.spacing.xs),
          ReadoutWell(
            label: 'BAR · BEAT · TICK',
            // The clock reserves every digit at its widest, as
            // `TransportReadout` does, so the bar is measured at the width it
            // has to survive rather than at "01:01:000".
            child: Text('88:88:888', style: tokens.type.numericLarge),
          ),
          SizedBox(width: tokens.spacing.md),
          Flexible(child: SearchAffordance(onTap: () {})),
          SizedBox(width: tokens.spacing.md),
          ViewSwitcher(activeView: WorkspaceView.arrangement, onSelect: (_) {}),
          SizedBox(width: tokens.spacing.sm),
          ExportButton(onPressed: () {}),
          SizedBox(width: tokens.spacing.sm),
          const MasterPeakIndicator(),
        ],
      ),
    );
  }

  // 1280 is the window's minimum width in MainFlutterWindow.swift. If the bar
  // cannot fit there, the app ships a window it cannot be resized out of — and
  // that is exactly what shipped: the readouts were set four points larger than
  // the design draws them and the bar needed 1290px it was never given.
  for (final double width in <double>[1280, 1440, 1920]) {
    testWidgets('the top bar fits a ${width.toInt()}px window', (
      WidgetTester tester,
    ) async {
      await pumpForTest(tester, topBarRow(), size: Size(width, 200));
      expect(tester.takeException(), isNull);
    });
  }
}
