// The computer keyboard as a MIDI controller, from an open plug-in window.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/plugins/plugin_binding.dart';
import 'package:onebeat/src/features/plugins/stock/piano_editor.dart';
import 'package:onebeat/src/features/plugins/typing_keyboard.dart';

import '../../support/app_harness.dart';
import '../../support/fake_engine_client.dart';

class _FakePluginEngineClient extends FakeEngineClient implements EngineClient {
  final List<int> notesOn = <int>[];
  final List<int> notesOff = <int>[];
  final List<String> selectedInstruments = <String>[];

  @override
  void auditionNoteOn(int key, double velocity) => notesOn.add(key);

  @override
  void auditionNoteOff(int key) => notesOff.add(key);

  @override
  void selectInstrument(String instrumentId) => selectedInstruments.add(instrumentId);
}

Future<void> _pumpPiano(WidgetTester tester, _FakePluginEngineClient client) async {
  await pumpForTest(
    tester,
    PluginBinding(
      client: client,
      trackId: 'inst_piano',
      pluginName: 'OneBeat Piano',
      trackName: 'Grand Piano',
      onClose: () {},
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('letter keys play the plug-in and release on key up', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    // Z is the base octave's C — MIDI 48 — and Q is the C above it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(client.notesOn, <int>[48]);
    expect(client.notesOff, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(client.notesOn, <int>[48, 60], reason: 'a second key adds a voice rather than replacing one');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(client.notesOff, <int>[48, 60]);
  });

  testWidgets('holding a key sustains one voice instead of repeating it', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();

    expect(client.notesOn, <int>[48]);
  });

  testWidgets('a key held with a command modifier is not a note', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(client.notesOn, isEmpty, reason: '⌘Z is undo, not a C');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  });

  testWidgets('the octave keys transpose, and a note released after the shift still stops', (
    WidgetTester tester,
  ) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(client.notesOn, <int>[60]);

    // Shift down while the key is still held: the release must end the voice
    // that was started, not the one the letter now maps to.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(client.notesOff, <int>[60]);
  });

  testWidgets('losing focus ends every held note', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(client.notesOff, isEmpty);

    tester.state<TypingKeyboardState>(find.byType(TypingKeyboard)).context.owner!.focusManager.primaryFocus?.unfocus();
    await tester.pump();

    expect(client.notesOff, <int>[48], reason: 'a stuck voice would drone until the app restarted');
  });

  testWidgets('typing points the engine at the window\'s own instrument', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    expect(client.selectedInstruments, contains('inst_piano'));
  });

  testWidgets('the drawn key lights up under the typed note', (WidgetTester tester) async {
    final _FakePluginEngineClient client = _FakePluginEngineClient();
    await _pumpPiano(tester, client);

    bool pressedAt(int midi) {
      final Iterable<PianoWhiteKey> keys = tester.widgetList<PianoWhiteKey>(find.byType(PianoWhiteKey));
      return keys.any((PianoWhiteKey key) => key.midiKey == midi && key.isPressed);
    }

    expect(pressedAt(48), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(pressedAt(48), isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(pressedAt(48), isFalse);
  });
}
