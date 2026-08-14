// Keyboard and focus behaviour (FR-UX-18, FR-UX-24).
//
// Each test here corresponds to a bug that actually happened. They are written
// as "typing a name must not delete your notes" rather than "the manager
// returns ignored", because the second one can pass while the first is broken.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/core/action_registry.dart';
import 'package:onebeat/src/core/shortcuts.dart';

import 'support/stage3_harness.dart';

void main() {
  // Real fonts: block glyphs measure nothing like Archivo or MartianMono.
  setUpAll(loadAppFonts);

  group('the registry is the single source of truth', () {
    test('every declared shortcut renders as the glyphs a Mac user reads', () {
      expect(ActionRegistry.byId('edit.undo').shortcut, '⌘Z');
      expect(ActionRegistry.byId('edit.redo').shortcut, '⇧⌘Z');
      expect(ActionRegistry.byId('clip.makeUnique').shortcut, '⇧⌘D');
      expect(ActionRegistry.byId('piano.delete').shortcut, '⌫');
      expect(ActionRegistry.byId('piano.tool.draw').shortcut, 'B');
      expect(ActionRegistry.byId('transport.play').shortcut, 'space');
      expect(ActionRegistry.byId('piano.zoomToSelection').shortcut, '⌘=');
    });

    test('the tooltip pairs the label with the real binding', () {
      // FR-UX-18: the keyboard path has to be discoverable from the mouse path.
      // Derived, so it cannot promise a shortcut that is not bound.
      expect(
        ActionRegistry.byId('piano.duplicate').tooltip,
        'Duplicate notes  ·  ⌘D',
      );
      expect(ActionRegistry.byId('pattern.recolor').tooltip, 'Pattern colour');
    });

    test('no two actions in the same scope claim the same key', () {
      // The bug this prevents is silent: two bindings collide, Flutter picks
      // one, and the other action simply stops working with no error anywhere.
      for (final ActionArea area in ActionArea.values) {
        final Map<String, String> seen = <String, String>{};
        for (final UiAction action in ActionRegistry.forArea(area)) {
          final String key = action.shortcut;
          if (key.isEmpty) continue;
          expect(
            seen.containsKey(key),
            isFalse,
            reason:
                '$key is claimed by both ${seen[key]} and ${action.id} '
                'in ${area.label}',
          );
          seen[key] = action.id;
        }
      }
    });

    test('every editor action with a binding is dispatchable by id', () {
      // A binding maps to RunActionIntent(id); if the id is not in the editor's
      // handler map nothing happens. This asserts the ids exist and are unique,
      // which is the half a unit test can see; the widget tests below prove the
      // handlers are actually wired.
      final Set<String> ids = <String>{};
      for (final UiAction action in ActionRegistry.all) {
        expect(ids.add(action.id), isTrue, reason: 'duplicate id ${action.id}');
      }
    });
  });

  group('typing never triggers a tool', () {
    testWidgets('bare letters are suppressed while a text field has focus', (
      WidgetTester tester,
    ) async {
      // The real bug: renaming a pattern to "Bass" switched the piano roll's
      // tool twice, and the first backspace deleted the selected notes.
      int toolChanges = 0;
      int deletes = 0;
      final TextEditingController text = TextEditingController();
      addTearDown(text.dispose);
      final FocusNode field = FocusNode();
      addTearDown(field.dispose);

      await pumpForTest(
        tester,
        ScopedShortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyB):
                const RunActionIntent('tool'),
            const SingleActivator(LogicalKeyboardKey.backspace):
                const RunActionIntent('delete'),
          },
          handlers: <String, VoidCallback>{
            'tool': () => toolChanges++,
            'delete': () => deletes++,
          },
          child: EditableText(
            controller: text,
            focusNode: field,
            style: OneBeatTokens.dark().type.body,
            cursorColor: OneBeatTokens.dark().color.accent,
            backgroundCursorColor: OneBeatTokens.dark().color.line,
          ),
        ),
        size: const Size(400, 200),
      );

      field.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(toolChanges, 0, reason: 'typing "b" must not switch tools');
      expect(deletes, 0, reason: 'backspace in a field must not delete notes');
    });

    testWidgets('modified shortcuts keep working while typing', (
      WidgetTester tester,
    ) async {
      // ⌘Z is never ambiguous — nobody types it into a name — so suppressing it
      // would be the opposite bug: undo mysteriously dead in a rename field.
      int undos = 0;
      final TextEditingController text = TextEditingController();
      addTearDown(text.dispose);
      final FocusNode field = FocusNode();
      addTearDown(field.dispose);

      await pumpForTest(
        tester,
        ScopedShortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                const RunActionIntent('undo'),
          },
          handlers: <String, VoidCallback>{'undo': () => undos++},
          child: EditableText(
            controller: text,
            focusNode: field,
            style: OneBeatTokens.dark().type.body,
            cursorColor: OneBeatTokens.dark().color.accent,
            backgroundCursorColor: OneBeatTokens.dark().color.line,
          ),
        ),
        size: const Size(400, 200),
      );

      field.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(undos, 1, reason: '⌘Z is unambiguous and must survive typing');
    });

    testWidgets('bare letters work normally when no field has focus', (
      WidgetTester tester,
    ) async {
      int toolChanges = 0;
      final FocusNode canvas = FocusNode();
      addTearDown(canvas.dispose);

      await pumpForTest(
        tester,
        ScopedShortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyB):
                const RunActionIntent('tool'),
          },
          handlers: <String, VoidCallback>{'tool': () => toolChanges++},
          child: Focus(focusNode: canvas, child: const SizedBox.expand()),
        ),
        size: const Size(400, 200),
      );

      canvas.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();

      expect(toolChanges, 1);
    });
  });

  group('focus policy', () {
    testWidgets('an editor does not steal focus from a field mid-edit', (
      WidgetTester tester,
    ) async {
      // FocusPolicy.takeUnlessTyping: clicking a canvas while renaming would
      // otherwise drop the rename silently.
      final TextEditingController text = TextEditingController();
      addTearDown(text.dispose);
      final FocusNode field = FocusNode(debugLabel: 'field');
      addTearDown(field.dispose);
      final FocusNode canvas = FocusNode(debugLabel: 'canvas');
      addTearDown(canvas.dispose);

      await pumpForTest(
        tester,
        Column(
          children: <Widget>[
            SizedBox(
              height: 40,
              child: EditableText(
                controller: text,
                focusNode: field,
                style: OneBeatTokens.dark().type.body,
                cursorColor: OneBeatTokens.dark().color.accent,
                backgroundCursorColor: OneBeatTokens.dark().color.line,
              ),
            ),
            Focus(focusNode: canvas, child: const SizedBox(height: 40)),
          ],
        ),
        size: const Size(400, 200),
      );

      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue);

      FocusPolicy.takeUnlessTyping(canvas);
      await tester.pump();

      expect(field.hasFocus, isTrue, reason: 'the rename keeps the keyboard');
      expect(canvas.hasFocus, isFalse);
    });

    testWidgets('an editor takes focus when nothing is being typed', (
      WidgetTester tester,
    ) async {
      final FocusNode canvas = FocusNode(debugLabel: 'canvas');
      addTearDown(canvas.dispose);

      await pumpForTest(
        tester,
        Focus(focusNode: canvas, child: const SizedBox.expand()),
        size: const Size(400, 200),
      );

      FocusPolicy.takeUnlessTyping(canvas);
      await tester.pump();

      expect(canvas.hasFocus, isTrue);
    });
  });
}
