// The insert rack: what the chain shows, and what each gesture asks the engine
// for. The rack is a pure view, so these drive it through its vm and assert on
// the callbacks — the same seam the binding uses.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/mixer/effect_rack.dart';
import 'package:onebeat/src/ui_kit/knob.dart';

import '../../support/app_harness.dart';

EffectRackVm _vm({
  List<EffectSlotVm> slots = const <EffectSlotVm>[],
  bool enabled = true,
}) => EffectRackVm(
  trackName: 'Drums',
  slots: slots,
  available: const <EffectChoiceVm>[
    EffectChoiceVm(id: 'dev.onebeat.fx.reverb', name: 'Reverb', summary: 'Room and hall.'),
    EffectChoiceVm(id: 'dev.onebeat.fx.delay', name: 'Delay', summary: 'Feedback delay.'),
  ],
  enabled: enabled,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('An empty chain says so and still offers every effect', (WidgetTester tester) async {
    await tester.pumpWidget(wrapForTest(ObEffectRack(vm: _vm())));

    expect(find.text('INSERTS — Drums'), findsOneWidget);
    expect(find.text('No effects on this track.'), findsOneWidget);
    expect(find.text('+ Reverb'), findsOneWidget);
    expect(find.text('+ Delay'), findsOneWidget);
  });

  testWidgets('With no track selected the rack explains rather than offering', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrapForTest(ObEffectRack(vm: _vm(enabled: false))));

    expect(find.text('Select a mixer track to add effects.'), findsOneWidget);
    // The add row is gone: there is nothing for it to add to.
    expect(find.text('+ Reverb'), findsNothing);
  });

  testWidgets('Slots are numbered by chain position', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(id: 'a', name: 'Reverb', params: <EffectParamVm>[]),
              EffectSlotVm(id: 'b', name: 'Delay', params: <EffectParamVm>[]),
            ],
          ),
        ),
      ),
    );

    // The order the signal takes, stated. Without the numbers "which runs
    // first" is answerable only by counting rows.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Reverb'), findsOneWidget);
    expect(find.text('Delay'), findsOneWidget);
  });

  testWidgets('Adding, bypassing and removing report the slot they act on', (
    WidgetTester tester,
  ) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(id: 'slot-a', name: 'Reverb', params: <EffectParamVm>[]),
            ],
          ),
          onAdd: (String id) => log.add('add:$id'),
          onRemove: (String id) => log.add('remove:$id'),
          onToggleBypass: (String id) => log.add('bypass:$id'),
        ),
      ),
    );

    await tester.tap(find.text('+ Delay'));
    await tester.tap(find.text('BYP'));
    await tester.tap(find.text('✕'));
    await tester.pump();

    expect(log, <String>['add:dev.onebeat.fx.delay', 'bypass:slot-a', 'remove:slot-a']);
  });

  testWidgets('Reordering is offered only where there is somewhere to go', (
    WidgetTester tester,
  ) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(id: 'a', name: 'Reverb', params: <EffectParamVm>[]),
              EffectSlotVm(id: 'b', name: 'Delay', params: <EffectParamVm>[]),
            ],
          ),
          onMove: (String id, int index) => log.add('$id→$index'),
        ),
      ),
    );

    // The first slot cannot move up and the last cannot move down, so the two
    // taps that do nothing must actually do nothing.
    await tester.tap(find.text('▲').first);
    await tester.tap(find.text('▼').last);
    expect(log, isEmpty);

    await tester.tap(find.text('▼').first);
    await tester.tap(find.text('▲').last);
    await tester.pump();
    expect(log, <String>['a→1', 'b→0']);
  });

  testWidgets('Only the expanded slot shows its knobs', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(
                id: 'a',
                name: 'Reverb',
                expanded: true,
                params: <EffectParamVm>[
                  EffectParamVm(id: 5, name: 'Mix', value: 0.3, display: '30%', minimum: 0, maximum: 1),
                ],
              ),
              EffectSlotVm(
                id: 'b',
                name: 'Delay',
                params: <EffectParamVm>[
                  EffectParamVm(id: 5, name: 'Mix', value: 0.5, display: '50%', minimum: 0, maximum: 1),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('30%'), findsOneWidget);
    // The collapsed slot's parameters are not drawn even though its vm carries
    // them — a chain of four expanded effects stops being readable at a glance.
    expect(find.text('50%'), findsNothing);
  });

  testWidgets('A missing effect is marked and kept, not hidden', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(id: 'a', name: 'Ghost Verb', missing: true, params: <EffectParamVm>[]),
            ],
          ),
        ),
      ),
    );

    // Dropping it would lose the automation pointing at it, so it stays in the
    // chain and says what it is.
    expect(find.text('Ghost Verb (missing)'), findsOneWidget);
  });

  testWidgets('A knob reports its value in the parameter own units', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(
      wrapForTest(
        ObEffectRack(
          vm: _vm(
            slots: const <EffectSlotVm>[
              EffectSlotVm(
                id: 'a',
                name: 'Delay',
                expanded: true,
                params: <EffectParamVm>[
                  // A range that is not 0..1, so a knob that forgot to convert
                  // would report a unit value and be caught here.
                  EffectParamVm(id: 2, name: 'Time', value: 1.0, display: '1.00', minimum: 0, maximum: 4),
                ],
              ),
            ],
          ),
          onParamChanged: (String slot, int param, double value) =>
              log.add('$slot:$param:${value.toStringAsFixed(2)}'),
        ),
      ),
    );

    await tester.drag(find.byType(ObKnob), const Offset(0, -40));
    await tester.pump();

    expect(log, isNotEmpty);
    final double reported = double.parse(log.first.split(':').last);
    // Dragged up from 1.0 of 4.0, so it must land above 1 and inside the range.
    expect(reported, greaterThan(1.0));
    expect(reported, lessThanOrEqualTo(4.0));
  });
}
