// ChannelRackScreenVm — view model for the full channel rack surface (UI-C-02, UI-D-02).
import 'package:flutter/widgets.dart';

import 'channel_inspector.dart';
import 'rack_row.dart';
import 'rack_toolbar.dart';

/// One tab in the pattern switcher header.
@immutable
class PatternTabVm {
  const PatternTabVm({
    required this.id,
    required this.name,
    this.selected = false,
    this.count,
  });

  final String id;
  final String name;
  final bool selected;

  /// Optional count badge (e.g. 4 for 4 active sequences).
  final int? count;
}

@immutable
class ChannelRackScreenVm {
  const ChannelRackScreenVm({
    this.title = 'CHANNEL RACK',
    this.patterns = const <PatternTabVm>[],
    this.hint = 'right-click a channel to open its piano roll',
    required this.toolbar,
    this.stepCount = 16,
    required this.rows,
    this.playingStep,
    this.playingTick,
    this.footerLead = 'Drop a sample from the browser, or',
    this.footerAction = 'Add channel',
    this.footerTrail = 'to grow the rack',
    this.footerShortcut = '⌘A',
    this.inspector,
    this.canUndo = false,
    this.canRedo = false,
  });

  final String title;
  final List<PatternTabVm> patterns;
  final String hint;
  final RackToolbarVm toolbar;
  final int stepCount;
  final List<RackRowVm> rows;
  final int? playingStep;

  /// The loop-wrapped transport tick, for rows drawing a piano-roll preview
  /// (the read head). [playingStep] is the grid-cell equivalent.
  final int? playingTick;

  final String footerLead;
  final String footerAction;
  final String footerTrail;
  final String footerShortcut;
  final ChannelInspectorVm? inspector;
  final bool canUndo;
  final bool canRedo;
}
