// View models for the extension manager (UI-C-11).
//
// Plain immutable data and nothing else: no engine types, no WASM model, no
// notion of what an extension actually *is*. The screen's whole argument is
// that an extension is a thing you can see, switch off and read the
// permissions of — so the vm is the permissions, the switch and the words.
import 'package:flutter/widgets.dart';

import '../../ui_kit/kit_glyphs.dart';
import '../../ui_kit/prose.dart';

/// One row in the installed list.
@immutable
class ExtensionVm {
  const ExtensionVm({
    required this.id,
    required this.name,
    required this.meta,
    required this.icon,
    this.enabled = true,
    this.crashed = false,
    this.selected = false,
  });

  final String id;
  final String name;

  /// The dim mono line under the name, already assembled:
  /// `by @luma · v1.2.0 · bound to ⇧⌘H`.
  final String meta;

  final ObKitGlyphKind icon;
  final bool enabled;

  /// Draws the danger outline and the `CRASHED` tag instead of a switch you
  /// can flick back on. A crashed extension is off because it failed, which is
  /// a different state from off because you said so.
  final bool crashed;

  final bool selected;
}

/// One line of the CAPABILITIES table: what the extension may do, and the
/// dim right-aligned qualifier that says how far that goes.
@immutable
class CapabilityVm {
  const CapabilityVm({
    required this.name,
    required this.granted,
    required this.note,
  });

  final String name;
  final bool granted;

  /// `patterns, notes, mixer`, `impossible by design`.
  final String note;
}

/// One line of BINDINGS: how the extension is reachable.
@immutable
class BindingVm {
  const BindingVm({
    required this.icon,
    required this.label,
    this.detail,
    this.tag,
    this.tagNote,
  });

  final ObKitGlyphKind icon;

  /// `Keyboard shortcut`, `Menu action`, `MIDI note`.
  final String label;

  /// Inline after the label, dim: `Tools › Harmonize selection`.
  final String? detail;

  /// Right-aligned mono key tag: `⇧⌘H`, `C#4`.
  final String? tag;

  /// Dim text after the tag: `when recording`.
  final String? tagNote;
}

/// The contained-failure card at the foot of the detail panel.
@immutable
class CrashCardVm {
  const CrashCardVm({
    required this.title,
    required this.body,
    required this.actions,
  });

  /// `GROOVE FETCHER CRASHED — CONTAINED & DISABLED`.
  final String title;

  /// Mixed emphasis: the reassurance is at full ink, the forensics are dim.
  final List<ObProseRun> body;

  /// `Try again once`, `Report crash`, `Uninstall` — in that order, least
  /// destructive first.
  final List<String> actions;
}

/// The right-hand panel: everything known about the selected extension.
@immutable
class ExtensionDetailVm {
  const ExtensionDetailVm({
    required this.name,
    required this.meta,
    required this.icon,
    required this.description,
    required this.capabilities,
    required this.bindings,
    this.enabled = true,
    this.capabilitiesHeader = 'CAPABILITIES',
    this.capabilitiesRightHeader = 'WHAT IT CAN DO TO YOUR PROJECT',
    this.bindingsHeader = 'BINDINGS',
    this.enabledLabel = 'Enabled',
    this.uninstallLabel = 'Uninstall',
    this.crash,
  });

  final String name;
  final String meta;
  final ObKitGlyphKind icon;
  final List<ObProseRun> description;
  final List<CapabilityVm> capabilities;
  final List<BindingVm> bindings;
  final bool enabled;
  final String capabilitiesHeader;
  final String capabilitiesRightHeader;
  final String bindingsHeader;
  final String enabledLabel;
  final String uninstallLabel;

  /// Shown when *some* extension has crashed — not necessarily this one. The
  /// mockup shows Harmonizer's detail carrying Groove Fetcher's crash card,
  /// which is deliberate: a contained failure is worth telling you about
  /// wherever you happen to be looking.
  final CrashCardVm? crash;
}

@immutable
class ExtensionManagerVm {
  const ExtensionManagerVm({
    required this.extensions,
    required this.detail,
    this.listTitle = 'EXTENSIONS',
    this.installLabel = 'Install from file…',
    this.caption = 'sandboxed WASM · you grant capabilities',
  });

  final List<ExtensionVm> extensions;
  final ExtensionDetailVm detail;
  final String listTitle;
  final String installLabel;

  /// The dim line under the install button — the promise the whole screen is
  /// built to make good on.
  final String caption;

  /// `4 installed`, derived rather than passed: two numbers that can disagree
  /// is one number too many.
  String get countLabel => '${extensions.length} installed';
}

/// One numbered step under the empty state's actions.
@immutable
class ExtensionStepVm {
  const ExtensionStepVm({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

/// A keyboard hint at the very bottom of the empty state: a mono key tag and
/// the word for what it does.
@immutable
class ExtensionHintVm {
  const ExtensionHintVm({required this.keys, required this.label});

  final String keys;
  final String label;
}

@immutable
class ExtensionEmptyVm {
  const ExtensionEmptyVm({
    required this.heading,
    required this.body,
    required this.steps,
    required this.hints,
    this.title = 'EXTENSIONS',
    this.rightNote = 'nothing installed yet',
    this.primaryAction = 'Write your first script',
    this.browseAction = 'Browse the library',
    this.templateAction = 'Start from a template',
  });

  final String heading;
  final List<ObProseRun> body;
  final List<ExtensionStepVm> steps;
  final List<ExtensionHintVm> hints;
  final String title;
  final String rightNote;
  final String primaryAction;
  final String browseAction;
  final String templateAction;
}

/// A parameter row inside an extension's own panel: a label, a filled track and
/// either a numeric readout at the right or a word sitting on the track.
@immutable
class PanelParamVm {
  const PanelParamVm({
    required this.label,
    required this.value,
    required this.readout,
    this.readoutOnTrack = false,
  });

  final String label;

  /// 0..1 fill.
  final double value;

  /// `0.62`, `5th`.
  final String readout;

  /// `INTERVAL`'s `5th` sits just past the end of its fill rather than at the
  /// right edge — the value is the position, so it is drawn there.
  final bool readoutOnTrack;
}

/// A note in the extension panel's live preview, in unit coordinates so the
/// preview scales with the panel and the golden stays deterministic.
@immutable
class PreviewNoteVm {
  const PreviewNoteVm({required this.x, required this.y});

  /// 0..1 across and down the preview canvas.
  final double x;
  final double y;
}

/// One row of a neighbouring panel's list (the channel rack in
/// `screens/ext-panel.png`).
@immutable
class PanelListRowVm {
  const PanelListRowVm({
    required this.name,
    required this.caption,
    required this.trailing,
    required this.color,
  });

  final String name;

  /// `Sampler`, `Reese`, `EP`.
  final String caption;

  /// The mono route chip: `→ D1`.
  final String trailing;
  final Color color;
}

/// One knob in a neighbouring plug-in panel.
@immutable
class PanelKnobVm {
  const PanelKnobVm({
    required this.label,
    required this.value,
    required this.readout,
  });

  final String label;
  final double value;
  final String readout;
}

/// A meter well: a titled dark box with a value at its top right and a bar
/// along its bottom.
@immutable
class PanelWellVm {
  const PanelWellVm({
    required this.label,
    required this.readout,
    required this.level,
  });

  final String label;
  final String readout;

  /// 0..1 of the bar across the well's foot.
  final double level;
}

/// A panel beside the extension's, drawn so the screen can make its point:
/// same chrome, same header, same frame. One of [rows] or [knobs] is filled.
@immutable
class PanelNeighbourVm {
  const PanelNeighbourVm({
    required this.title,
    this.rightNote = 'native',
    this.rows = const <PanelListRowVm>[],
    this.knobs = const <PanelKnobVm>[],
    this.wells = const <PanelWellVm>[],
    this.flex = 1,
  });

  final String title;
  final String rightNote;
  final List<PanelListRowVm> rows;
  final List<PanelKnobVm> knobs;
  final List<PanelWellVm> wells;

  /// Share of the row's width.
  final int flex;
}

@immutable
class ExtensionPanelVm {
  const ExtensionPanelVm({
    required this.title,
    required this.author,
    required this.params,
    required this.previewNotes,
    this.badge = 'EXT',
    this.previewCaption = 'live preview · selected pattern',
    this.runAction = 'Harmonize',
    this.undoAction = 'Undo',
    this.binding = '⌥⌘H',
    this.bindingNote = 'bound',
    this.flex = 1,
  });

  final String title;

  /// `by @luma`.
  final String author;

  final List<PanelParamVm> params;
  final List<PreviewNoteVm> previewNotes;

  /// The accent-outlined tag after the title that says where this panel came
  /// from. It is the only thing distinguishing it from a native panel, which
  /// is the screen's entire thesis.
  final String badge;

  final String previewCaption;
  final String runAction;
  final String undoAction;
  final String binding;
  final String bindingNote;
  final int flex;
}

/// The docked-panel row of `screens/ext-panel.png`: neighbours either side of
/// the extension's own surface.
@immutable
class ExtensionPanelScreenVm {
  const ExtensionPanelScreenVm({
    required this.before,
    required this.panel,
    required this.after,
  });

  final List<PanelNeighbourVm> before;
  final ExtensionPanelVm panel;
  final List<PanelNeighbourVm> after;
}
