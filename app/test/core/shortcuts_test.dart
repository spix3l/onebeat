// Keyboard and focus behaviour for core infrastructure.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/action_registry.dart';
import 'package:onebeat/src/core/shortcuts.dart';
import 'package:onebeat/src/design/tokens.dart';

import '../support/app_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the core registry is the single source of truth', () {
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
      expect(
        ActionRegistry.byId('piano.duplicate').tooltip,
        'Duplicate notes  ·  ⌘D',
      );
      expect(ActionRegistry.byId('pattern.recolor').tooltip, 'Pattern colour');
    });

    test('no two actions in the same scope claim the same key', () {
      for (final ActionArea area in ActionArea.values) {
        final Map<String, String> seen = <String, String>{};
        for (final UiAction action in ActionRegistry.forArea(area)) {
          final String key = action.shortcut;
          if (key.isEmpty) continue;
          expect(
            seen.containsKey(key),
            isFalse,
            reason:
                '$key is claimed by both ${seen[key]} and ${action.id} in ${area.label}',
          );
          seen[key] = action.id;
        }
      }
    });

    test('every editor action with a binding is dispatchable by id', () {
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
            const SingleActivator(
              LogicalKeyboardKey.keyB,
            ): const RunActionIntent('tool'),
            const SingleActivator(
              LogicalKeyboardKey.backspace,
            ): const RunActionIntent('delete'),
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
            const SingleActivator(
              LogicalKeyboardKey.keyB,
            ): const RunActionIntent('tool'),
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

    testWidgets('modified shortcuts keep working while typing', (
      WidgetTester tester,
    ) async {
      int undos = 0;
      final TextEditingController text = TextEditingController();
      addTearDown(text.dispose);
      final FocusNode field = FocusNode();
      addTearDown(field.dispose);

      await pumpForTest(
        tester,
        ScopedShortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
            ): const RunActionIntent('undo'),
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
  });

  group('focus policy', () {
    testWidgets('a tap on an editor surface takes focus back from a field', (
      WidgetTester tester,
    ) async {
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

      FocusPolicy.take(canvas);
      await tester.pump();

      expect(
        canvas.hasFocus,
        isTrue,
        reason: 'clicking the canvas means "I am done with the field"',
      );
      expect(field.hasFocus, isFalse);
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

      FocusPolicy.take(canvas);
      await tester.pump();

      expect(canvas.hasFocus, isTrue);
    });

    testWidgets('returnToEditor hands the keyboard back to the last editor', (
      WidgetTester tester,
    ) async {
      final FocusNode shell = FocusNode(debugLabel: 'shell');
      final FocusNode editor = FocusNode(debugLabel: 'editor');
      final FocusNode field = FocusNode(debugLabel: 'field');
      addTearDown(shell.dispose);
      addTearDown(editor.dispose);
      addTearDown(field.dispose);

      await pumpForTest(
        tester,
        Column(
          children: <Widget>[
            Focus(focusNode: shell, child: const SizedBox(height: 40)),
            Focus(focusNode: editor, child: const SizedBox(height: 40)),
            SizedBox(
              height: 40,
              child: EditableText(
                controller: TextEditingController(),
                focusNode: field,
                style: OneBeatTokens.dark().type.body,
                cursorColor: OneBeatTokens.dark().color.accent,
                backgroundCursorColor: OneBeatTokens.dark().color.line,
              ),
            ),
          ],
        ),
        size: const Size(400, 200),
      );

      FocusPolicy.registerShell(shell);
      addTearDown(() => FocusPolicy.registerShell(shell));
      FocusPolicy.take(editor);
      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue);

      FocusPolicy.returnToEditor();
      await tester.pump();

      expect(
        editor.hasFocus,
        isTrue,
        reason: 'the keyboard comes back to where the user was working',
      );
      expect(field.hasFocus, isFalse);
    });

    testWidgets(
      'returnToEditor falls back to the shell when no editor held it',
      (WidgetTester tester) async {
        final FocusNode shell = FocusNode(debugLabel: 'shell');
        final FocusNode field = FocusNode(debugLabel: 'field');
        addTearDown(shell.dispose);
        addTearDown(field.dispose);

        await pumpForTest(
          tester,
          Column(
            children: <Widget>[
              Focus(focusNode: shell, child: const SizedBox(height: 40)),
              SizedBox(
                height: 40,
                child: EditableText(
                  controller: TextEditingController(),
                  focusNode: field,
                  style: OneBeatTokens.dark().type.body,
                  cursorColor: OneBeatTokens.dark().color.accent,
                  backgroundCursorColor: OneBeatTokens.dark().color.line,
                ),
              ),
            ],
          ),
          size: const Size(400, 200),
        );

        FocusPolicy.registerShell(shell);
        addTearDown(() => FocusPolicy.registerShell(shell));
        field.requestFocus();
        await tester.pump();

        FocusPolicy.returnToEditor();
        await tester.pump();

        expect(shell.hasFocus, isTrue);
        expect(field.hasFocus, isFalse);
      },
    );

    testWidgets('Escape in a field returns focus to the editor', (
      WidgetTester tester,
    ) async {
      final FocusNode shell = FocusNode(debugLabel: 'shell');
      final FocusNode editor = FocusNode(debugLabel: 'editor');
      final TextEditingController text = TextEditingController();
      final FocusNode field = FocusNode(debugLabel: 'field');
      addTearDown(shell.dispose);
      addTearDown(editor.dispose);
      addTearDown(text.dispose);
      addTearDown(field.dispose);

      await pumpForTest(
        tester,
        ScopedShortcuts(
          shortcuts: <ShortcutActivator, Intent>{},
          handlers: const <String, VoidCallback>{},
          child: Column(
            children: <Widget>[
              Focus(focusNode: shell, child: const SizedBox(height: 40)),
              Focus(focusNode: editor, child: const SizedBox(height: 40)),
              SizedBox(
                height: 40,
                child: escapeReturnsFocus(
                  child: EditableText(
                    controller: text,
                    focusNode: field,
                    style: OneBeatTokens.dark().type.body,
                    cursorColor: OneBeatTokens.dark().color.accent,
                    backgroundCursorColor: OneBeatTokens.dark().color.line,
                  ),
                ),
              ),
            ],
          ),
        ),
        size: const Size(400, 200),
      );

      FocusPolicy.registerShell(shell);
      addTearDown(() => FocusPolicy.registerShell(shell));
      FocusPolicy.take(editor);
      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(editor.hasFocus, isTrue, reason: 'Escape leaves the field');
      expect(field.hasFocus, isFalse);
    });
  });
}
