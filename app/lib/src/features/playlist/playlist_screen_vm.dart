// Playlist screen view model (UI-C-04 / UI-D-04).
import 'package:flutter/widgets.dart';

import '../../engine/engine_client.dart';
import 'playlist_canvas.dart';

@immutable
class ClipInspectorVm {
  const ClipInspectorVm({
    required this.selectedCount,
    this.clipId = '',
    this.name = '',
    this.color = const Color(0xFF6C8CFF), // token-lint-ok: fallback track swatch
    this.usageText = '',
    this.isShared = false,
    this.isAudio = false,
    this.startBar = 0,
    this.lengthBars = 1,
    this.offsetBeats = 0,
    this.loop = false,
    this.muted = false,
    this.transpose = 0,
    this.stretchMode = StretchMode.off,
    this.reversed = false,
    this.sourceBpm = 0,
    this.canFitToTempo = false,
  });

  final int selectedCount;
  final String clipId;
  final String name;
  final Color color;
  final String usageText;
  final bool isShared;
  final bool isAudio;
  final int startBar;
  final int lengthBars;
  final int offsetBeats;
  final bool loop;
  final bool muted;
  final int transpose;

  // --- audio clips only; ignored when [isAudio] is false ---

  /// What the right edge means for this clip: a trim, a repitch or a stretch.
  final StretchMode stretchMode;
  final bool reversed;

  /// The tempo the material was recorded at, 0 when unknown.
  final double sourceBpm;

  /// Whether fit-to-tempo has enough to work with. Offered as a disabled
  /// control rather than a hidden one when it does not: the reason it cannot
  /// run is the missing source tempo right beside it.
  final bool canFitToTempo;

  bool get isEmpty => selectedCount == 0;
  bool get isMulti => selectedCount > 1;
}

@immutable
class PlaylistScreenVm {
  const PlaylistScreenVm({
    required this.canvas,
    this.inspector = const ClipInspectorVm(selectedCount: 0),
  });

  final PlaylistVm canvas;
  final ClipInspectorVm inspector;
}
