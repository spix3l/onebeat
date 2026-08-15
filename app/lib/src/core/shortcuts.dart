// Keyboard shortcuts and focus policy (FR-UX-18, FR-UX-24, groundwork FR-UX-22).
//
// This file exists because shortcuts scattered across editor widgets produced
// three specific, recurring bugs:
//
//   1. **Typing triggered tools.** The piano roll bound bare `B` and `V`. Those
//      activators still match while a rename field has focus, because a raw key
//      event reaches `Shortcuts` whether or not an `EditableText` also consumed
//      it. Renaming a pattern to "Bass" switched tools twice and deleted the
//      selection on the first backspace.
//   2. **Two widgets both claimed the keyboard.** The shell and the piano roll
//      each had `Focus(autofocus: true)`. Which one won depended on build order,
//      so Space-to-play worked or did not depending on how you got there.
//   3. **Tooltips drifted from bindings.** The label said ⌘D and the binding
//      said something else, with nothing to catch it.
//
// The fixes, in order:
//
//   1. [OneBeatShortcutManager] refuses bare-key activators while text is being
//      edited. Modified shortcuts (⌘Z) still work — those are never ambiguous.
//   2. Exactly one `autofocus` in the app, on the shell. Editors take focus on
//      interaction, and [FocusPolicy] documents who owns what.
//   3. Activators are declared on the action registry and the display string is
//      *derived* from the activator, so they cannot disagree. A test asserts
//      every registry entry with a shortcut is actually bound.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'action_registry.dart';

/// Where a shortcut is live.
enum ShortcutScope {
  /// Works anywhere in the app: transport, undo, view switching.
  global,

  /// Works only while its editor has focus.
  editor,
}

// ---------------------------------------------------------------------------
// Intents. One per action, shared by every editor rather than redeclared.
// ---------------------------------------------------------------------------

class TogglePlayIntent extends Intent {
  const TogglePlayIntent();
}

class TogglePauseIntent extends Intent {
  const TogglePauseIntent();
}

class ReturnToZeroIntent extends Intent {
  const ReturnToZeroIntent();
}

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class ShowViewIntent extends Intent {
  const ShowViewIntent(this.index);

  /// 1-based, matching the number the user pressed.
  final int index;
}

class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

/// Project files (OB-3-05 §4). Structural like transport and undo — the shell
/// owns the project, so these are intents rather than editor-dispatched ids.
class SaveProjectIntent extends Intent {
  const SaveProjectIntent();
}

class SaveProjectAsIntent extends Intent {
  const SaveProjectAsIntent();
}

class OpenProjectIntent extends Intent {
  const OpenProjectIntent();
}

class RenameProjectIntent extends Intent {
  const RenameProjectIntent();
}

/// Escape. Cancels an in-flight drag, then closes an overlay, then clears a
/// selection — whichever applies first. Never leaves the user in a state they
/// cannot see how to get out of.
class CancelIntent extends Intent {
  const CancelIntent();
}

class RunActionIntent extends Intent {
  const RunActionIntent(this.id);

  /// An [ActionRegistry] id. Editors map these onto their own handlers, so a
  /// registry entry is bound in exactly one place.
  final String id;
}

// ---------------------------------------------------------------------------
// The manager
// ---------------------------------------------------------------------------

/// True when the primary focus is inside a text field.
///
/// Walks up from the focused element looking for an [EditableText]. Cheap: the
/// walk is bounded by widget-tree depth and only runs on a key event that
/// actually matched a bare activator.
bool isEditingText() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  bool editing = false;
  context.visitAncestorElements((Element element) {
    if (element.widget is EditableText) {
      editing = true;
      return false;
    }
    return true;
  });
  if (editing) return true;
  // The focus node of an EditableText belongs to the EditableText itself, so
  // the ancestor walk usually finds it. A field that puts focus on a wrapper
  // is caught by looking down one level as well.
  context.visitChildElements((Element element) {
    if (element.widget is EditableText) editing = true;
  });
  return editing;
}

/// A [ShortcutManager] that stays out of the way while the user is typing.
///
/// Only *bare* activators are suppressed — no modifier, or Shift alone. ⌘Z is
/// unambiguous while typing and keeps working; `B` is not, and does not.
/// Backspace and Delete are suppressed too: in a text field they mean "delete a
/// character", never "delete the selected notes".
class OneBeatShortcutManager extends ShortcutManager {
  OneBeatShortcutManager({required super.shortcuts});

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_isTypingHostile(event) && isEditingText()) {
      return KeyEventResult.ignored;
    }
    return super.handleKeypress(context, event);
  }

  static bool _isTypingHostile(KeyEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) return false;
    if (keyboard.isAltPressed) return false;
    // Everything left is a bare key or Shift+key: exactly what typing produces.
    return true;
  }
}

// ---------------------------------------------------------------------------
// Focus policy
// ---------------------------------------------------------------------------

/// Who owns the keyboard, written down because it was previously implicit and
/// therefore wrong.
///
/// - **The shell** holds the only `autofocus` in the app and carries every
///   [ShortcutScope.global] binding. It never gives focus up permanently; an
///   editor taking focus keeps the shell's shortcuts live because `Shortcuts`
///   resolve up the tree.
/// - **An editor** takes focus on pointer-down inside its canvas, and on being
///   shown from the view switcher. It carries [ShortcutScope.editor] bindings.
/// - **A text field** takes focus on tap and returns it on Enter, Escape or tap
///   outside: [returnToEditor] hands the keyboard back to whichever editor
///   last had it. While it holds focus, bare-key shortcuts are suppressed.
/// - **Space is the transport, everywhere.** No control binds it, so it works
///   no matter what was clicked last. This is the one rule that already existed
///   and it survives unchanged (FR-UX-24).
abstract final class FocusPolicy {
  /// The shell's root focus node — where focus lands when no editor has ever
  /// held it, and the default target [returnToEditor] falls back to.
  static FocusNode? _shellRoot;

  /// The editor that last took the keyboard. A finished text field returns
  /// focus here so the shortcuts of the place the user was working in wake
  /// back up, not just the global ones.
  static FocusNode? _editor;

  /// Registers the shell's root focus node as the default home for focus.
  ///
  /// The shell is the app's only `autofocus` and lives for the whole session,
  /// so this is set once at startup and never cleared.
  static void registerShell(FocusNode node) => _shellRoot = node;

  /// Takes focus on behalf of an editor — a pointer-down in its canvas, or the
  /// editor being shown. Records the node as the home a finished text field
  /// returns to, so the keyboard comes back to where the user was working.
  static void take(FocusNode node) {
    _editor = node;
    node.requestFocus();
  }

  /// A text field is done with the keyboard (Enter, Escape, or a tap that lands
  /// on an editor surface). Focus goes back to the editor that last had it —
  /// or the shell root when none ever did — which wakes the bare-key shortcuts
  /// the field had been suppressing.
  static void returnToEditor() {
    final FocusNode? editor = _editor;
    final FocusNode? target =
        editor != null && editor.context != null && editor.context!.mounted
            ? editor
            : _shellRoot;
    if (target == null || target.context == null || !target.context!.mounted) {
      return;
    }
    target.requestFocus();
  }
}

class _ReturnFocusIntent extends Intent {
  const _ReturnFocusIntent();
}

/// Wraps a text field so Escape returns focus to the editor that last had it.
///
/// While a field has focus, bare-key shortcuts are suppressed app-wide (see
/// [OneBeatShortcutManager]). Escape is the canonical way to leave a field,
/// and leaving it must wake those shortcuts back up. The field-local
/// [Shortcuts] consumes the key, so the shell's Cancel action does not fire on
/// top of it. The rename dialogs handle Escape to *close* instead; they do not
/// use this wrapper.
Widget escapeReturnsFocus({required Widget child}) {
  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.escape): _ReturnFocusIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _ReturnFocusIntent: CallbackAction<_ReturnFocusIntent>(
          onInvoke: (_) {
            FocusPolicy.returnToEditor();
            return null;
          },
        ),
      },
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Installing shortcuts
// ---------------------------------------------------------------------------

/// Builds the `Shortcuts` map for a scope from the registry, so a binding
/// exists in exactly one place and the tooltip is generated from it.
Map<ShortcutActivator, Intent> shortcutsForScope(ShortcutScope scope) {
  final Map<ShortcutActivator, Intent> map = <ShortcutActivator, Intent>{};
  for (final UiAction action in ActionRegistry.all) {
    final ShortcutActivator? activator = action.activator;
    if (activator == null || action.scope != scope) continue;
    map[activator] = action.intent ?? RunActionIntent(action.id);
  }
  return map;
}

/// Builds the map for one editor area plus anything global it should also see.
Map<ShortcutActivator, Intent> shortcutsForArea(ActionArea area) {
  final Map<ShortcutActivator, Intent> map = <ShortcutActivator, Intent>{};
  for (final UiAction action in ActionRegistry.forArea(area)) {
    final ShortcutActivator? activator = action.activator;
    if (activator == null) continue;
    map[activator] = action.intent ?? RunActionIntent(action.id);
  }
  return map;
}

/// Wraps a subtree in registry-derived shortcuts with the typing-aware manager.
///
/// `handlers` maps registry ids to callbacks; anything unhandled falls through
/// to an ancestor, which is what lets the shell keep transport and undo live
/// while an editor owns its own keys.
class ScopedShortcuts extends StatefulWidget {
  const ScopedShortcuts({
    required this.shortcuts,
    required this.handlers,
    required this.child,
    this.extraActions = const <Type, Action<Intent>>{},
    super.key,
  });

  final Map<ShortcutActivator, Intent> shortcuts;
  final Map<String, VoidCallback> handlers;
  final Map<Type, Action<Intent>> extraActions;
  final Widget child;

  @override
  State<ScopedShortcuts> createState() => _ScopedShortcutsState();
}

class _ScopedShortcutsState extends State<ScopedShortcuts> {
  late OneBeatShortcutManager _manager = OneBeatShortcutManager(
    shortcuts: widget.shortcuts,
  );

  @override
  void didUpdateWidget(ScopedShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shortcuts, widget.shortcuts)) {
      _manager = OneBeatShortcutManager(shortcuts: widget.shortcuts);
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts.manager(
      manager: _manager,
      child: Actions(
        actions: <Type, Action<Intent>>{
          RunActionIntent: CallbackAction<RunActionIntent>(
            onInvoke: (RunActionIntent intent) {
              final VoidCallback? handler = widget.handlers[intent.id];
              if (handler == null) return Object(); // unhandled: bubble up
              handler();
              return null;
            },
          ),
          ...widget.extraActions,
        },
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rendering an activator as the string a user reads
// ---------------------------------------------------------------------------

/// The macOS glyph form of an activator: `⇧⌘D`, `⌫`, `1`.
///
/// The registry's display string is generated by this rather than typed by
/// hand, which is what stops a tooltip promising a shortcut that is not bound.
String describeActivator(ShortcutActivator activator) {
  if (activator is! SingleActivator) return '';
  final StringBuffer buffer = StringBuffer();
  if (activator.control) buffer.write('⌃');
  if (activator.alt) buffer.write('⌥');
  if (activator.shift) buffer.write('⇧');
  if (activator.meta) buffer.write('⌘');
  buffer.write(_keyLabel(activator.trigger));
  return buffer.toString();
}

String _keyLabel(LogicalKeyboardKey key) {
  final String? special =
      <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.backspace: '⌫',
        LogicalKeyboardKey.delete: '⌦',
        LogicalKeyboardKey.escape: 'esc',
        LogicalKeyboardKey.enter: '⏎',
        LogicalKeyboardKey.space: 'space',
        LogicalKeyboardKey.tab: '⇥',
        LogicalKeyboardKey.arrowUp: '↑',
        LogicalKeyboardKey.arrowDown: '↓',
        LogicalKeyboardKey.arrowLeft: '←',
        LogicalKeyboardKey.arrowRight: '→',
        LogicalKeyboardKey.equal: '=',
        LogicalKeyboardKey.minus: '−',
        LogicalKeyboardKey.slash: '/',
      }[key];
  if (special != null) return special;
  final String label = key.keyLabel;
  return label.length == 1 ? label.toUpperCase() : label;
}
