import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/channel_rack/rack_store.dart';

import 'support/fake_rack_client.dart';

void main() {
  test('paint drag is one transaction and paints each crossed step once', () {
    final FakeRackClient client = FakeRackClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    expect(store.isVisible(store.rows.single), isFalse);
    store.includeInstrument('kick');
    expect(store.isVisible(store.rows.single), isTrue);

    store.beginPaint('kick', 0, active: true);
    store.paintStep('kick', 1);
    store.paintStep('kick', 1);
    store.paintStep('kick', 2);
    store.commitPaint();

    expect(client.transactionBegins, 1);
    expect(client.transactionCommits, 1);
    expect(
      store.rows.single.steps.take(3).every((step) => step.active),
      isTrue,
    );
    expect(store.canUndo, isTrue);
  });

  test('velocity and pattern controls stay on the same fake-engine seam', () {
    final FakeRackClient client = FakeRackClient();
    final RackStore store = RackStore(client)..load();
    addTearDown(store.dispose);

    store.setVelocity('kick', 4, 8192);
    store.setSwing(0.55);
    store.setLength(32);

    expect(store.rows.single.steps[4].velocity, 8192);
    expect(store.pattern!.swing, 0.55);
    expect(store.pattern!.baseStepCount, 32);
  });
}
