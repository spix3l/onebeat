// Mixer screen view models (UI-C-05 / UI-D-05).
import 'package:flutter/widgets.dart';

import 'mixer_strip.dart';
import 'routing_panel.dart';

enum MixerMode { trackFocus, graphOverview, matrixView }

@immutable
class MixerScreenVm {
  const MixerScreenVm({
    required this.title,
    required this.strips,
    required this.masterStrip,
    required this.selectedTrackIndex,
    required this.routingPanel,
    this.mode = MixerMode.trackFocus,
  });

  final String title;
  final List<MixerStripVm> strips;
  final MixerStripVm masterStrip;
  final int selectedTrackIndex;
  final RoutingPanelVm routingPanel;
  final MixerMode mode;

  MixerScreenVm copyWith({
    String? title,
    List<MixerStripVm>? strips,
    MixerStripVm? masterStrip,
    int? selectedTrackIndex,
    RoutingPanelVm? routingPanel,
    MixerMode? mode,
  }) =>
      MixerScreenVm(
        title: title ?? this.title,
        strips: strips ?? this.strips,
        masterStrip: masterStrip ?? this.masterStrip,
        selectedTrackIndex: selectedTrackIndex ?? this.selectedTrackIndex,
        routingPanel: routingPanel ?? this.routingPanel,
        mode: mode ?? this.mode,
      );
}
