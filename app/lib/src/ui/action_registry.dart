// The action registry (OB-3-14 §5, FR-UX-17, groundwork for FR-UX-18/22).
//
// Every user action in the Stage 3 editors is declared here once: its id, the
// label the user reads, the area it belongs to, and the shortcut if it has one.
//
// The point is not documentation. FR-UX-17 says nothing may be reachable only
// by right-click, and that is the kind of rule that decays quietly — someone
// adds a context-menu item, ships it, and nobody notices for a release. The
// registry turns it into a test: `action_reachability_test.dart` renders each
// editor and asserts that every action declared for that area is present as a
// **visible control**, found by [actionKey]. A new context-menu-only action
// fails the build.
//
// The contract for widget authors is therefore one line long: if you declare an
// action here, give its visible control `key: actionKey(id)`.
import 'package:flutter/widgets.dart';

/// Which editor an action lives in. Also what the reachability test iterates.
enum ActionArea {
  transport('Transport'),
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
    this.shortcut = '',
    this.description = '',
  });

  /// Stable identifier. Used by [actionKey], and the future seed of the command
  /// palette and remappable shortcuts (FR-UX-22).
  final String id;

  /// What the control says, or what its tooltip says when it is icon-only.
  final String label;
  final ActionArea area;

  /// Display form, e.g. `⌘D`. Empty when the action has no shortcut. Shown in
  /// tooltips so the keyboard path is discoverable from the mouse path
  /// (FR-UX-18 groundwork).
  final String shortcut;

  final String description;

  /// The tooltip text: label plus shortcut, which is the pairing that teaches.
  String get tooltip => shortcut.isEmpty ? label : '$label  ·  $shortcut';
}

/// The key a visible control must carry to satisfy FR-UX-17 for [id].
ValueKey<String> actionKey(String id) => ValueKey<String>('action:$id');

/// The declared surface. Adding an entry without a matching visible control
/// fails `action_reachability_test.dart`, which is the whole mechanism.
abstract final class ActionRegistry {
  static const List<UiAction> all = <UiAction>[
    // ----- pattern management (OB-3-11) -------------------------------------
    UiAction(
      id: 'pattern.create',
      label: 'New pattern',
      area: ActionArea.pattern,
      shortcut: '⌘N',
    ),
    UiAction(
      id: 'pattern.rename',
      label: 'Rename pattern',
      area: ActionArea.pattern,
      shortcut: 'F2',
    ),
    UiAction(
      id: 'pattern.recolor',
      label: 'Pattern colour',
      area: ActionArea.pattern,
    ),
    UiAction(
      id: 'pattern.duplicate',
      label: 'Duplicate pattern',
      area: ActionArea.pattern,
      description:
          'An independent copy that no clip points at yet — distinct from '
          'Make unique, which repoints the selected clips.',
    ),
    UiAction(
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
      shortcut: 'B',
    ),
    UiAction(
      id: 'piano.tool.select',
      label: 'Select',
      area: ActionArea.pianoRoll,
      shortcut: 'V',
    ),
    UiAction(
      id: 'piano.grid',
      label: 'Grid',
      area: ActionArea.pianoRoll,
      description: 'Snap resolution, including triplets.',
    ),
    UiAction(
      id: 'piano.scale',
      label: 'Scale highlight',
      area: ActionArea.pianoRoll,
    ),
    UiAction(
      id: 'piano.quantise',
      label: 'Quantise',
      area: ActionArea.pianoRoll,
      shortcut: '⌘J',
    ),
    UiAction(
      id: 'piano.duplicate',
      label: 'Duplicate notes',
      area: ActionArea.pianoRoll,
      shortcut: '⌘D',
    ),
    UiAction(
      id: 'piano.delete',
      label: 'Delete notes',
      area: ActionArea.pianoRoll,
      shortcut: '⌫',
    ),
    UiAction(
      id: 'piano.selectAll',
      label: 'Select all',
      area: ActionArea.pianoRoll,
      shortcut: '⌘A',
    ),
    UiAction(
      id: 'piano.transposeUp',
      label: 'Transpose up an octave',
      area: ActionArea.pianoRoll,
      shortcut: '⇧↑',
    ),
    UiAction(
      id: 'piano.transposeDown',
      label: 'Transpose down an octave',
      area: ActionArea.pianoRoll,
      shortcut: '⇧↓',
    ),
    UiAction(
      id: 'piano.zoomToSelection',
      label: 'Zoom to selection',
      area: ActionArea.pianoRoll,
      shortcut: '⌘=',
    ),
    UiAction(
      id: 'piano.velocity',
      label: 'Note velocity',
      area: ActionArea.pianoRoll,
      description: 'The strip under the grid; edits the selection together.',
    ),

    // ----- arrangement (OB-3-12) --------------------------------------------
    UiAction(
      id: 'arrangement.addLane',
      label: 'Add lane',
      area: ActionArea.arrangement,
    ),
    UiAction(
      id: 'arrangement.placeClip',
      label: 'Place pattern',
      area: ActionArea.arrangement,
      shortcut: '⌘B',
      description: 'Puts the current pattern on the selected lane.',
    ),
    UiAction(
      id: 'arrangement.duplicateClip',
      label: 'Duplicate clip',
      area: ActionArea.arrangement,
      shortcut: '⌘D',
    ),
    UiAction(
      id: 'arrangement.deleteClip',
      label: 'Delete clip',
      area: ActionArea.arrangement,
      shortcut: '⌫',
    ),
    UiAction(
      id: 'arrangement.laneMute',
      label: 'Mute lane events',
      area: ActionArea.arrangement,
      description:
          'An event gate, not an audio fade: clips on the lane stop firing '
          '(D-M4). The mixer owns audio muting.',
    ),
    UiAction(
      id: 'arrangement.laneSolo',
      label: 'Solo lane',
      area: ActionArea.arrangement,
    ),
    UiAction(
      id: 'arrangement.laneCollapse',
      label: 'Collapse lane',
      area: ActionArea.arrangement,
    ),
    UiAction(
      id: 'arrangement.laneDelete',
      label: 'Delete lane',
      area: ActionArea.arrangement,
    ),
    UiAction(
      id: 'arrangement.snap',
      label: 'Snap',
      area: ActionArea.arrangement,
    ),

    // ----- clip inspector (OB-3-13) -----------------------------------------
    UiAction(id: 'clip.start', label: 'Clip start', area: ActionArea.clip),
    UiAction(id: 'clip.length', label: 'Clip length', area: ActionArea.clip),
    UiAction(
      id: 'clip.offset',
      label: 'Source offset',
      area: ActionArea.clip,
      shortcut: '⌥drag',
      description: 'Shifts the window into the pattern (DM-Q2).',
    ),
    UiAction(
      id: 'clip.loop',
      label: 'Loop mode',
      area: ActionArea.clip,
      description: 'Loop repeats the pattern; hold-off leaves silence.',
    ),
    UiAction(id: 'clip.mute', label: 'Mute clip', area: ActionArea.clip),
    UiAction(
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
      shortcut: '⇧⌘D',
      description:
          'Clones the pattern and repoints only the selected clips. Sits '
          'beside the transforms because cloning is the explicit path, not '
          'the default one (D-M3).',
    ),
  ];

  static List<UiAction> forArea(ActionArea area) =>
      all.where((UiAction action) => action.area == area).toList();

  static UiAction byId(String id) =>
      all.firstWhere((UiAction action) => action.id == id);
}
