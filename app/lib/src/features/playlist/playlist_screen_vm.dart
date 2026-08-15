// Playlist screen view model (UI-C-04 / UI-D-04).
import 'package:flutter/widgets.dart';

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
    this.loop = true,
    this.muted = false,
    this.transpose = 0,
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
