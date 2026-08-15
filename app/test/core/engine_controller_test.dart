import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/engine_controller.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/engine/engine_client.dart';

import '../support/ui_harness.dart';

class _PreviewClient implements EngineClient {
  final List<EngineEvent> pendingEvents = <EngineEvent>[];
  final List<int> noteOns = <int>[];
  final List<int> noteOffs = <int>[];
  String? loadedPath;

  @override
  EngineSnapshot readSnapshot() => const EngineSnapshot.empty();

  @override
  List<EngineEvent> pollEvents() {
    final List<EngineEvent> events = List<EngineEvent>.of(pendingEvents);
    pendingEvents.clear();
    return events;
  }

  @override
  void loadSample(String samplePath) => loadedPath = samplePath;

  @override
  void auditionNoteOn(int key, double velocity) => noteOns.add(key);

  @override
  void auditionNoteOff(int key) => noteOffs.add(key);

  @override
  void previewNoteOn(int key, double velocity) => noteOns.add(key);

  @override
  void previewNoteOff(int key) => noteOffs.add(key);

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControllerHost extends StatefulWidget {
  const _ControllerHost({required this.client, required this.onReady});

  final _PreviewClient client;
  final ValueChanged<EngineController> onReady;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost> with SingleTickerProviderStateMixin {
  late final EngineController controller;

  @override
  void initState() {
    super.initState();
    controller = EngineController(
      client: widget.client,
      vsync: this,
      motion: OneBeatTokens.dark().motion,
    );
    widget.onReady(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets('sample preview waits for the sample-loaded event', (
    WidgetTester tester,
  ) async {
    final _PreviewClient client = _PreviewClient();
    late EngineController controller;

    await pumpUi(
      tester,
      _ControllerHost(
        client: client,
        onReady: (EngineController value) => controller = value,
      ),
      size: const Size(320, 200),
    );

    controller.previewSample('/tmp/Kick.wav');
    expect(client.loadedPath, '/tmp/Kick.wav');
    expect(client.noteOns, isEmpty);

    client.pendingEvents.add(
      const EngineEvent(evtSampleLoaded, 0, 0, 0, 'Kick.wav'),
    );
    await tester.pump();

    expect(client.noteOns, isNotEmpty);
    expect(client.noteOns.every((int key) => key == 60), isTrue);
    await tester.pump(controller.motion.settled);
    expect(client.noteOffs, isNotEmpty);
    expect(client.noteOffs.every((int key) => key == 60), isTrue);
  });
}
