// A 32-step pattern has to be visible in one piece (UI-B-05). The sizing rule
// itself lives in rack_step_fit_test; this is the end of it — the assembled
// screen at a window the app actually opens at, with nothing left to scroll to.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen.dart';
import 'package:onebeat/src/features/channel_rack/channel_rack_screen_vm.dart';
import 'package:onebeat/src/features/channel_rack/rack_row.dart';
import 'package:onebeat/src/features/channel_rack/rack_toolbar.dart';

import '../../support/ui_harness.dart';
import 'fixture.dart';

List<StepVm> _steps32(List<int> lit) => <StepVm>[
  for (int i = 1; i <= 32; i++) lit.contains(i) ? const StepVm(on: true, velocity: 1) : const StepVm.off(),
];

RackRowVm _row(RackRowVm base, List<StepVm> steps) => RackRowVm(
  name: base.name,
  type: base.type,
  color: base.color,
  steps: steps,
  vol: base.vol,
  pan: base.pan,
  route: base.route,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('32 steps fit the rack without a horizontal scroll', (
    WidgetTester tester,
  ) async {
    final ChannelRackScreenVm vm = ChannelRackScreenVm(
      toolbar: const RackToolbarVm(
        channelType: 'Sampler',
        group: 'All',
        snap: '1/16',
        steps: 32,
      ),
      stepCount: 32,
      playingStep: 6,
      rows: <RackRowVm>[
        _row(demoRackRows[0], _steps32(<int>[1, 9, 17, 25])),
        _row(demoRackRows[1], _steps32(<int>[5, 13, 21, 29])),
      ],
    );

    await pumpUi(tester, ChannelRackScreen(vm: vm), size: const Size(1150, 300));
    await tester.pump();

    final ScrollableState horizontal = tester.state(
      find.byWidgetPredicate(
        (Widget widget) => widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    expect(
      horizontal.position.maxScrollExtent,
      0,
      reason: 'the whole bar is on screen, so there is nowhere to scroll',
    );

    // And the grid really is 32 columns wide, not 32 columns clipped.
    expect(
      tester.getRect(find.byType(ObStepGrid).first).right,
      lessThanOrEqualTo(1150),
    );
  });
}
