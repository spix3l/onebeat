// The action registry (OB-3-14 §5, FR-UX-17/18, groundwork for FR-UX-22).
//
// Every user action in the app is declared here once: its id, the label the
// user reads, the area it belongs to, and — where it has one — the actual
// [ShortcutActivator] that triggers it.
//
// Two properties this buys, both of which used to be broken:
//
//   1. **FR-UX-17 is a test.** Nothing may be reachable only by right-click.
//      `action_reachability_test.dart` renders each editor and asserts every
//      declared action has a *visible control* found by [actionKey]. A new
//      context-menu-only action fails the build.
//   2. **Tooltips cannot lie.** The shortcut a tooltip shows is *derived* from
//      the activator that is actually bound (`describeActivator`), so the two
//      cannot drift. Previously the display string was hand-typed beside the
//      binding and nothing checked them against each other.
//
// The contract for widget authors is two lines long: give the visible control
// `key: actionKey(id)`, and put the id in your `ScopedShortcuts` handler map.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'shortcuts.dart';

/// Which editor an action lives in. Also what the reachability test iterates.
enum ActionArea {
  transport('Transport'),
  project('Project'),
  pattern('Pattern'),
  rack('Channel rack'),
  pianoRoll('Piano roll'),
  arrangement('Arrangement'),
  clip('Clip');

  const ActionArea(this.label);
  final String label;
}

@immutable
class UiAction {
  const UiAction({
    required this.id,
    required this.label,
    required this.area,
    this.activator,
    this.intent,
    this.scope = ShortcutScope.editor,
    this.description = '',
  });

  /// Stable identifier, and the seed of the command palette and remappable
  /// shortcuts (FR-UX-22).
  final String id;

  /// What the control says, or what its tooltip says when it is icon-only.
  final String label;
  final ActionArea area;

  /// The binding, or null for actions that are mouse-only. **This is the source
  /// of truth**; [shortcut] is generated from it.
  final ShortcutActivator? activator;

  /// A specific intent, for actions the shell handles structurally (transport,
  /// undo). Everything else uses `RunActionIntent(id)` and is dispatched by the
  /// editor's handler map.
  final Intent? intent;

  final ShortcutScope scope;
  final String description;

  /// Display form, e.g. `⌘D`. Derived, never typed.
  String get shortcut =>
      activator == null ? '' : describeActivator(activator!);

  /// The tooltip: label plus shortcut, which is the pairing that teaches the
  /// keyboard path to someone who found the action with a mouse (FR-UX-18).
  String get tooltip => shortcut.isEmpty ? label : '$label  ·  $shortcut';
}

/// The key a visible control must carry to satisfy FR-UX-17 for [id].
ValueKey<String> actionKey(String id) => ValueKey<String>('action:$id');

// Shorthands. `_meta` rather than `_cmd` because these are logical modifiers;
// the glyph mapping to ⌘ happens once, in describeActivator.
SingleActivator _meta(LogicalKeyboardKey key) =>
    SingleActivator(key, meta: true);
SingleActivator _metaShift(LogicalKeyboardKey key) =>
    SingleActivator(key, meta: true, shift: true);
SingleActivator _bare(LogicalKeyboardKey key) => SingleActivator(key);
SingleActivator _shift(LogicalKeyboardKey key) =>
    SingleActivator(key, shift: true);

/// The declared surface.
abstract final class ActionRegistry {
  static final List<UiAction> all = <UiAction>[
    // ----- transport and shell (global scope) --------------------------------
    // These stay live no matter which editor has focus, which is the whole
    // reason they are a separate scope rather than repeated per editor.
    UiAction(
      id: 'transport.play',
      label: 'Play / stop',
      area: ActionArea.transport,
      activator: _bare(LogicalKeyboardKey.space),
      intent: const TogglePlayIntent(),
      scope: ShortcutScope.global,
      description:
          'Space is the transport everywhere, always. No control binds it, so '
          'it works no matter what was clicked last (FR-UX-24). Stopping '
          'returns the playhead to zero.',
    ),
    const UiAction(
      id: 'transport.pause',
      label: 'Pause / resume',
      area: ActionArea.transport,
      activator: SingleActivator(LogicalKeyboardKey.space, alt: true),
      intent: TogglePauseIntent(),
      scope: ShortcutScope.global,
      description:
          'Pauses without moving the playhead, so resuming continues from the '
          'same place — unlike Space, which restarts from the top.',
    ),
    UiAction(
      id: 'transport.returnToZero',
      label: 'Return to zero',
      area: ActionArea.transport,
      activator: _bare(LogicalKeyboardKey.enter),
      intent: const ReturnToZeroIntent(),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'edit.undo',
      label: 'Undo',
      area: ActionArea.transport,
      activator: _meta(LogicalKeyboardKey.keyZ),
      intent: const UndoIntent(),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'edit.redo',
      label: 'Redo',
      area: ActionArea.transport,
      activator: _metaShift(LogicalKeyboardKey.keyZ),
      intent: const RedoIntent(),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'view.channels',
      label: 'Channels',
      area: ActionArea.transport,
      activator: _bare(LogicalKeyboardKey.digit1),
      intent: const ShowViewIntent(1),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'view.playlist',
      label: 'Playlist',
      area: ActionArea.transport,
      activator: _bare(LogicalKeyboardKey.digit2),
      intent: const ShowViewIntent(2),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'view.mixer',
      label: 'Mixer',
      area: ActionArea.transport,
      activator: _bare(LogicalKeyboardKey.digit3),
      intent: const ShowViewIntent(3),
      scope: ShortcutScope.global,
    ),
    UiAction(
      id: 'view.search',
      label: 'Search actions',
      area: ActionArea.transport,
      activator: _meta(LogicalKeyboardKey.keyK),
      intent: const CommandPaletteIntent(),
      scope: ShortcutScope.global,
      description: 'Every action in this registry, by name.',
    ),

    // ----- project files (OB-3-05 §4) ---------------------------------------
    // Global, and deliberately the shortcuts every Mac app uses: ⌘S is the one
    // binding a user presses without deciding to. `pattern.create` keeps ⌘N —
    // patterns are what this app makes, and it is editor-scoped, so the two
    // never contend for the same keystroke.
    UiAction(
      id: 'project.save',
      label: 'Save',
      area: ActionArea.project,
      activator: _meta(LogicalKeyboardKey.keyS),
      intent: const SaveProjectIntent(),
      scope: ShortcutScope.global,
      description:
          'Writes the .obt bundle in place. The first save asks where, because '
          'a project that has never been written has nowhere to go.',
    ),
    UiAction(
      id: 'project.saveAs',
      label: 'Save as…',
      area: ActionArea.project,
      activator: _metaShift(LogicalKeyboardKey.keyS),
      intent: const SaveProjectAsIntent(),
      scope: ShortcutScope.global,
      description:
          'Writes a copy under a new name and adopts it, so the title and the '
          'file cannot disagree afterwards.',
    ),
    UiAction(
      id: 'project.open',
      label: 'Open…',
      area: ActionArea.project,
      activator: _meta(LogicalKeyboardKey.keyO),
      intent: const OpenProjectIntent(),
      scope: ShortcutScope.global,
      description:
          'Replaces the session. A file that cannot be read leaves the project '
          'you already have exactly as it was.',
    ),
    const UiAction(
      id: 'project.rename',
      label: 'Rename project…',
      area: ActionArea.project,
      intent: RenameProjectIntent(),
      scope: ShortcutScope.global,
      description:
          'Renames the project and, once it has been saved, the bundle on '
          'disk with it.',
    ),

    // ----- pattern management (OB-3-11) -------------------------------------
    UiAction(
      id: 'pattern.create',
      label: 'New pattern',
      area: ActionArea.pattern,
      activator: _meta(LogicalKeyboardKey.keyN),
    ),
    UiAction(
      id: 'pattern.rename',
      label: 'Rename pattern',
      area: ActionArea.pattern,
      activator: _bare(LogicalKeyboardKey.f2),
    ),
    const UiAction(
      id: 'pattern.recolor',
      label: 'Pattern colour',
      area: ActionArea.pattern,
    ),
    const UiAction(
      id: 'pattern.duplicate',
      label: 'Duplicate pattern',
      area: ActionArea.pattern,
      description:
          'An independent copy that no clip points at yet — distinct from '
          'Make unique, which repoints the selected clips.',
    ),
    const UiAction(
      id: 'pattern.delete',
      label: 'Delete pattern',
      area: ActionArea.pattern,
      description: 'Warns with the number of clips that would go with it.',
    ),

    // ----- piano roll (OB-3-10) ---------------------------------------------
    UiAction(
      id: 'piano.tool.draw',
      label: 'Draw',
      area: ActionArea.pianoRoll,
      activator: _bare(LogicalKeyboardKey.keyB),
    ),
    UiAction(
      id: 'piano.tool.select',
      label: 'Select',
      area: ActionArea.pianoRoll,
      activator: _bare(LogicalKeyboardKey.keyV),
    ),
    const UiAction(
      id: 'piano.grid',
      label: 'Grid',
      area: ActionArea.pianoRoll,
      description: 'Snap resolution, including triplets.',
    ),
    const UiAction(
      id: 'piano.scale',
      label: 'Scale highlight',
      area: ActionArea.pianoRoll,
    ),
    UiAction(
      id: 'piano.quantise',
      label: 'Quantise',
      area: ActionArea.pianoRoll,
      activator: _meta(LogicalKeyboardKey.keyJ),
    ),
    UiAction(
      id: 'piano.duplicate',
      label: 'Duplicate notes',
      area: ActionArea.pianoRoll,
      activator: _meta(LogicalKeyboardKey.keyD),
    ),
    UiAction(
      id: 'piano.delete',
      label: 'Delete notes',
      area: ActionArea.pianoRoll,
      activator: _bare(LogicalKeyboardKey.backspace),
    ),
    UiAction(
      id: 'piano.selectAll',
      label: 'Select all',
      area: ActionArea.pianoRoll,
      activator: _meta(LogicalKeyboardKey.keyA),
    ),
    UiAction(
      id: 'piano.transposeUp',
      label: 'Transpose up an octave',
      area: ActionArea.pianoRoll,
      activator: _shift(LogicalKeyboardKey.arrowUp),
    ),
    UiAction(
      id: 'piano.transposeDown',
      label: 'Transpose down an octave',
      area: ActionArea.pianoRoll,
      activator: _shift(LogicalKeyboardKey.arrowDown),
    ),
    UiAction(
      id: 'piano.zoomToSelection',
      label: 'Zoom to selection',
      area: ActionArea.pianoRoll,
      activator: _meta(LogicalKeyboardKey.equal),
    ),
    const UiAction(
      id: 'piano.velocity',
      label: 'Note velocity',
      area: ActionArea.pianoRoll,
      description: 'The strip under the grid; edits the selection together.',
    ),

    // ----- arrangement (OB-3-12) --------------------------------------------
    const UiAction(
      id: 'arrangement.addLane',
      label: 'Add lane',
      area: ActionArea.arrangement,
    ),
    UiAction(
      id: 'arrangement.placeClip',
      label: 'Place pattern',
      area: ActionArea.arrangement,
      activator: _meta(LogicalKeyboardKey.keyB),
      description: 'Puts the current pattern on the selected lane.',
    ),
    UiAction(
      id: 'arrangement.duplicateClip',
      label: 'Duplicate clip',
      area: ActionArea.arrangement,
      activator: _meta(LogicalKeyboardKey.keyD),
    ),
    UiAction(
      id: 'arrangement.deleteClip',
      label: 'Delete clip',
      area: ActionArea.arrangement,
      activator: _bare(LogicalKeyboardKey.backspace),
    ),
    const UiAction(
      id: 'arrangement.laneMute',
      label: 'Mute lane events',
      area: ActionArea.arrangement,
      description:
          'An event gate, not an audio fade: clips on the lane stop firing '
          '(D-M4). The mixer owns audio muting.',
    ),
    const UiAction(
      id: 'arrangement.laneSolo',
      label: 'Solo lane',
      area: ActionArea.arrangement,
    ),
    const UiAction(
      id: 'arrangement.laneCollapse',
      label: 'Collapse lane',
      area: ActionArea.arrangement,
    ),
    const UiAction(
      id: 'arrangement.laneDelete',
      label: 'Delete lane',
      area: ActionArea.arrangement,
    ),
    const UiAction(
      id: 'arrangement.snap',
      label: 'Snap',
      area: ActionArea.arrangement,
    ),

    // ----- clip inspector (OB-3-13) -----------------------------------------
    const UiAction(id: 'clip.start', label: 'Clip start', area: ActionArea.clip),
    const UiAction(id: 'clip.length', label: 'Clip length', area: ActionArea.clip),
    const UiAction(
      id: 'clip.offset',
      label: 'Source offset',
      area: ActionArea.clip,
      description:
          '⌥-drag inside the clip shifts the window into the pattern (DM-Q2).',
    ),
    const UiAction(
      id: 'clip.loop',
      label: 'Loop mode',
      area: ActionArea.clip,
      description: 'Loop repeats the pattern; hold-off leaves silence.',
    ),
    const UiAction(id: 'clip.mute', label: 'Mute clip', area: ActionArea.clip),
    const UiAction(
      id: 'clip.transpose',
      label: 'Transpose',
      area: ActionArea.clip,
      description:
          'Non-destructive, ±48 semitones. Varying a clip without cloning the '
          'pattern is the default path (D-M3).',
    ),
    UiAction(
      id: 'clip.makeUnique',
      label: 'Make unique',
      area: ActionArea.clip,
      activator: _metaShift(LogicalKeyboardKey.keyD),
      description:
          'Clones the pattern and repoints only the selected clips. Sits '
          'beside the transforms because cloning is the explicit path, not '
          'the default one (D-M3).',
    ),
  ];

  static List<UiAction> forArea(ActionArea area) =>
      all.where((UiAction action) => action.area == area).toList();

  static List<UiAction> forScope(ShortcutScope scope) =>
      all.where((UiAction action) => action.scope == scope).toList();

  static UiAction byId(String id) =>
      all.firstWhere((UiAction action) => action.id == id);

  /// Everything with a binding, for the shortcut sheet and the palette.
  static List<UiAction> get bound =>
      all.where((UiAction action) => action.activator != null).toList();
}
