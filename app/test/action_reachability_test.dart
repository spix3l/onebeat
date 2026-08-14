// FR-UX-17 as a test, not a walkthrough (OB-3-14 §3a).
//
// The rule is "nothing is reachable only by right-click". A walkthrough checks
// that once, by hand, and then rots. This renders each editor and asserts that
// every action the registry declares for that area is present as a **visible
// control** — so adding a context-menu-only action fails the build.
//
// The deliberate-violation demonstration the ticket asks for is at the bottom:
// a fake registry entry with no control, asserted to fail.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui/action_registry.dart';
import 'package:onebeat/src/ui/arrangement_store.dart';
import 'package:onebeat/src/ui/engine_controller.dart' show WorkspaceView;
import 'package:onebeat/src/ui/clip_inspector.dart';
import 'package:onebeat/src/ui/pattern_selector.dart';
import 'package:onebeat/src/ui/pattern_store.dart';

import 'support/fake_stage3_client.dart';
import 'support/stage3_harness.dart';

void main() {
  testWidgets('every pattern action is reachable from a visible control', (
    WidgetTester tester,
  ) async {
    final FakeStage3Client client = FakeStage3Client();
    final PatternStore patterns = PatternStore(client)..load();

    await tester.pumpWidget(
      wrapForTest(
        PatternSelector(store: patterns, onOpenPattern: (_) {}),
        size: const Size(320, 700),
      ),
    );

    expectAreaReachable(ActionArea.pattern);
  });

  testWidgets('every piano roll action is reachable from a visible control', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness()
      ..seedNotes('inst_a', count: 4);
    // A selection is live, because half the toolbar is only enabled with one —
    // enabled or not, the control has to be *there*, which is what this asserts.
    harness.pianoRoll.selectAll();

    await tester.pumpWidget(
      wrapForTest(harness.buildPianoRoll(), size: const Size(1200, 800)),
    );

    expectAreaReachable(ActionArea.pianoRoll);
  });

  testWidgets('every arrangement action is reachable from a visible control', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness()..seedArrangement();

    await tester.pumpWidget(
      wrapForTest(harness.buildArrangement(), size: const Size(1400, 800)),
    );

    expectAreaReachable(ActionArea.arrangement);
  });

  testWidgets('every clip action is reachable from the inspector', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness()..seedArrangement();
    final ArrangementStore store = harness.arrangement;
    store.selectClip(store.clips.first.id);

    await tester.pumpWidget(
      wrapForTest(
        ClipInspector(store: store, patterns: harness.patterns),
        size: const Size(320, 900),
      ),
    );

    expectAreaReachable(ActionArea.clip);
  });

  testWidgets('every transport and view action is reachable from the chrome', (
    WidgetTester tester,
  ) async {
    // The area that used to be exempt, and therefore the one where a
    // keyboard-only action could hide. Undo had ⌘Z and no button, which is as
    // unreachable as a right-click-only action to someone who does not already
    // know it is there.
    final Stage3Harness harness = Stage3Harness()..seedArrangement();

    await tester.pumpWidget(
      wrapForTest(
        ShellChromeForTest(
          patterns: harness.patterns,
          activeView: WorkspaceView.arrangement,
        ),
        size: const Size(1600, 320),
      ),
    );

    expectAreaReachable(ActionArea.transport);
  });

  testWidgets(
    'the reachability check fails when an action has no visible control',
    (WidgetTester tester) async {
      // OB-3-14's "catches a deliberately-introduced violation, demonstrated
      // and reverted" — kept permanently rather than performed once, so the
      // guard itself cannot silently stop guarding.
      final FakeStage3Client client = FakeStage3Client();
      final PatternStore patterns = PatternStore(client)..load();

      await tester.pumpWidget(
        wrapForTest(
          PatternSelector(store: patterns, onOpenPattern: (_) {}),
          size: const Size(320, 700),
        ),
      );

      const UiAction contextMenuOnly = UiAction(
        id: 'pattern.hiddenInAContextMenu',
        label: 'Right-click only',
        area: ActionArea.pattern,
      );
      expect(
        find.byKey(actionKey(contextMenuOnly.id)),
        findsNothing,
        reason: 'the violating action is genuinely absent from the UI',
      );
      expect(
        () => expectActionReachable(contextMenuOnly),
        throwsA(isA<TestFailure>()),
        reason: 'so the reachability assertion must reject it',
      );
    },
  );
}

/// Asserts one action has at least one visible control carrying its key.
///
/// "At least one" rather than "exactly one" on purpose: per-row actions such as
/// the lane's event-gate mute legitimately appear once per lane, and requiring
/// uniqueness would make the guard fail as soon as a fixture grew a second row.
/// FR-UX-17 asks whether an action is reachable, not how many ways there are.
void expectActionReachable(UiAction action) {
  expect(
    find.byKey(actionKey(action.id)),
    findsAtLeastNWidgets(1),
    reason:
        'FR-UX-17: "${action.label}" (${action.id}) is declared in the action '
        'registry but has no visible control. Give its control '
        "key: actionKey('${action.id}'), or remove the registry entry.",
  );
}

void expectAreaReachable(ActionArea area) {
  final List<UiAction> actions = ActionRegistry.forArea(area);
  expect(
    actions,
    isNotEmpty,
    reason: 'an area with no declared actions is a registry mistake',
  );
  for (final UiAction action in actions) {
    expectActionReachable(action);
  }
}
