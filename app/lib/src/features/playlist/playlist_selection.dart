import 'package:flutter/foundation.dart';

import '../../engine/engine_client.dart';

enum PlaylistTool { select, draw, paint, delete, mute, slice, slip }

@immutable
class PlaylistTimeSelection {
  const PlaylistTimeSelection(this.startTick, this.endTick);

  final int startTick;
  final int endTick;

  int get lowTick => startTick < endTick ? startTick : endTick;
  int get highTick => startTick < endTick ? endTick : startTick;
  bool contains(int tick) => tick >= lowTick && tick <= highTick;
}

@immutable
class PlaylistMarquee {
  const PlaylistMarquee(this.startTick, this.startLane, this.endTick, this.endLane);

  final int startTick;
  final int startLane;
  final int endTick;
  final int endLane;

  int get lowTick => startTick < endTick ? startTick : endTick;
  int get highTick => startTick < endTick ? endTick : startTick;
  int get lowLane => startLane < endLane ? startLane : endLane;
  int get highLane => startLane < endLane ? endLane : startLane;

  bool contains(ArrangementClip clip, int laneIndex) =>
      laneIndex >= lowLane && laneIndex <= highLane && clip.endTicks > lowTick && clip.startTicks < highTick;
}
