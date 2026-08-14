// PianoRollScreenVm — ViewModel for the PianoRollScreen (UI-D-03).
import 'package:flutter/widgets.dart';

import 'note_grid.dart';
import 'pr_toolbar.dart';

@immutable
class PianoRollScreenVm {
  const PianoRollScreenVm({
    required this.toolbar,
    required this.roll,
    this.channelColor,
    this.velocityLane = 'VEL',
    this.velocityLanes = const <String>['VEL', 'PAN', 'MOD'],
    this.hasInstrument = true,
    this.emptyMessage =
        'Select an instrument in the channel rack to edit its notes here.',
    this.canUndo = false,
    this.canRedo = false,
  });

  final PrToolbarVm toolbar;
  final PianoRollVm roll;
  final Color? channelColor;
  final String velocityLane;
  final List<String> velocityLanes;
  final bool hasInstrument;
  final String emptyMessage;
  final bool canUndo;
  final bool canRedo;
}
