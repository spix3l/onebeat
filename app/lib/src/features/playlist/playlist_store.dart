// Playlist store — arrangement state and gestures (UI-D-04).
//
// Lanes and clips live in the engine. What lives here is selection, viewport,
// and in-flight drag gesture state.
import 'package:flutter/foundation.dart';

import '../../core/pattern_store.dart';
import '../../engine/engine_client.dart';

enum ClipDragKind { none, move, resizeEnd, offset, marquee }

class GridChoice {
  const GridChoice(this.label, this.ticks);
  final String label;
  final int ticks;

  static const int ticksPerQuarter = 960;
  static const int ticksPerBar = ticksPerQuarter * 4;

  static const List<GridChoice> all = <GridChoice>[
    GridChoice('4 bars', ticksPerBar * 4),
    GridChoice('1 bar', ticksPerBar),
    GridChoice('1/4', ticksPerQuarter),
    GridChoice('1/8', ticksPerQuarter ~/ 2),
    GridChoice('1/16', ticksPerQuarter ~/ 4),
    GridChoice('Off', 0),
  ];
}

const int ticksPerQuarter = GridChoice.ticksPerQuarter;
const int ticksPerBar = GridChoice.ticksPerBar;

typedef ArrangementStore = PlaylistStore;
typedef ArrangementClipDragKind = ClipDragKind;

class PlaylistStore extends ChangeNotifier {
  PlaylistStore(this._client, [this._patternStore]);

  final EngineClient _client;
  // ignore: unused_field
  final Object? _patternStore;

  List<ArrangementLane> lanes = const <ArrangementLane>[];
  List<ArrangementClip> clips = const <ArrangementClip>[];
  List<PatternSummary> patterns = const <PatternSummary>[];

  final Set<String> selectedClipIds = <String>{};
  String selectedLaneId = '';
  String selectedPatternId = '';

  GridChoice snap = const GridChoice('1 bar', ticksPerBar);
  double horizontalZoom = 1.0;
  double scrollTicks = 0.0;

  ClipDragKind dragKind = ClipDragKind.none;
  bool _gestureOpen = false;
  int _dragDelta = 0;
  String _dragLaneId = '';

  static const double _basePixelsPerTick = 0.012;
  double get pixelsPerTick => _basePixelsPerTick * horizontalZoom;

  void load() => refresh();

  void refresh() {
    lanes = _client.readLanes();
    clips = _client.readClips();
    patterns = _client.readPatterns();
    final Object? pat = _patternStore;
    if (pat is PatternStore) {
      pat.refresh();
    }

    final Set<String> live = clips.map((ArrangementClip c) => c.id).toSet();
    selectedClipIds.removeWhere((String id) => !live.contains(id));

    if (selectedLaneId.isEmpty && lanes.isNotEmpty) {
      selectedLaneId = lanes.first.id;
    }

    if (selectedPatternId.isEmpty && patterns.isNotEmpty) {
      final PatternSummary? current =
          patterns.cast<PatternSummary?>().firstWhere(
                (PatternSummary? p) => p?.isCurrent ?? false,
                orElse: () => patterns.first,
              );
      selectedPatternId = current?.id ?? '';
    }

    notifyListeners();
  }

  ArrangementClip? get selectedClip {
    if (selectedClipIds.length != 1) return null;
    return clipById(selectedClipIds.first);
  }

  ArrangementClip? clipById(String id) {
    for (final ArrangementClip clip in clips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  List<ArrangementClip> clipsOnLane(String laneId) =>
      clips.where((ArrangementClip clip) => clip.laneId == laneId).toList();

  bool isSelected(ArrangementClip clip) => selectedClipIds.contains(clip.id);

  bool isHighlighted(ArrangementClip clip) =>
      selectedPatternId.isNotEmpty && clip.patternId == selectedPatternId;

  int get contentEndTicks {
    int end = ticksPerBar * 8;
    for (final ArrangementClip clip in clips) {
      if (clip.endTicks > end) end = clip.endTicks;
    }
    return end;
  }

  int snapTick(int tick) {
    if (snap.ticks <= 0) return tick < 0 ? 0 : tick;
    final int snapped = ((tick / snap.ticks).round()) * snap.ticks;
    return snapped < 0 ? 0 : snapped;
  }

  /// Snaps a movement delta without clamping it. Unlike an absolute position,
  /// a drag delta is allowed to be negative so a clip can move left.
  int snapDelta(int delta) {
    if (snap.ticks <= 0) return delta;
    return ((delta / snap.ticks).round()) * snap.ticks;
  }

  void setSnap(GridChoice value) {
    snap = value;
    notifyListeners();
  }

  void zoomHorizontally(double factor) {
    horizontalZoom = (horizontalZoom * factor).clamp(0.1, 20.0);
    notifyListeners();
  }

  void panTo(double ticks) {
    scrollTicks = ticks < 0 ? 0 : ticks;
    notifyListeners();
  }

  // ----- selection ----------------------------------------------------------

  void selectLane(String laneId) {
    if (selectedLaneId == laneId) return;
    selectedLaneId = laneId;
    notifyListeners();
  }

  void selectClip(String clipId, {bool additive = false}) {
    if (!additive) selectedClipIds.clear();
    if (additive && selectedClipIds.contains(clipId)) {
      selectedClipIds.remove(clipId);
    } else {
      selectedClipIds.add(clipId);
    }
    final ArrangementClip? clip = clipById(clipId);
    if (clip != null) {
      selectedLaneId = clip.laneId;
      selectedPatternId = clip.patternId;
    }
    notifyListeners();
  }

  void selectClips(Iterable<String> ids) {
    selectedClipIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void clearClipSelection() {
    if (selectedClipIds.isEmpty) return;
    selectedClipIds.clear();
    notifyListeners();
  }

  // ----- lanes --------------------------------------------------------------

  void addLane(String name) {
    _client.createLane(name);
    refresh();
  }

  void renameLane(String laneId, String name) {
    if (name.trim().isEmpty) return;
    _client.renameLane(laneId, name.trim());
    refresh();
  }

  void recolorLane(String laneId, String color) {
    _client.recolorLane(laneId, color);
    refresh();
  }

  void reorderLane(String laneId, int order) {
    _client.reorderLane(laneId, order);
    refresh();
  }

  void moveLaneTo(String laneId, int targetIndex) {
    final List<ArrangementLane> ordered = List<ArrangementLane>.from(lanes);
    final int from = ordered.indexWhere((ArrangementLane l) => l.id == laneId);
    if (from < 0) return;
    final int to = targetIndex.clamp(0, ordered.length - 1);
    if (from == to) return;
    final ArrangementLane moving = ordered.removeAt(from);
    ordered.insert(to, moving);
    for (int index = 0; index < ordered.length; index++) {
      if (ordered[index].order != index) {
        _client.reorderLane(ordered[index].id, index);
      }
    }
    refresh();
  }

  void setLaneHeight(String laneId, int height) {
    _client.setLaneHeight(laneId, height.clamp(24, 400));
    refresh();
  }

  void toggleLaneMute(ArrangementLane lane) {
    _client.setLaneMuted(lane.id, muted: !lane.muted);
    refresh();
  }

  void toggleLaneSolo(ArrangementLane lane) {
    _client.setLaneSoloed(lane.id, soloed: !lane.soloed);
    refresh();
  }

  void toggleLaneCollapsed(ArrangementLane lane) {
    _client.setLaneCollapsed(lane.id, collapsed: !lane.collapsed);
    refresh();
  }

  void removeLane(String laneId) {
    _client.removeLane(laneId);
    if (selectedLaneId == laneId) selectedLaneId = '';
    refresh();
  }

  // ----- clips --------------------------------------------------------------

  void placeCurrentPattern(String laneId, int startTicks) {
    PatternSummary? pattern;
    if (selectedPatternId.isNotEmpty) {
      pattern = patterns.cast<PatternSummary?>().firstWhere(
            (PatternSummary? p) => p?.id == selectedPatternId,
            orElse: () => null,
          );
    }
    pattern ??= patterns.isNotEmpty ? patterns.first : null;
    if (pattern == null) return;

    final int start = snapTick(startTicks);
    _client.addClip(
      laneId,
      patternId: pattern.id,
      startTicks: start,
      lengthTicks: pattern.lengthTicks,
    );
    refresh();

    for (final ArrangementClip clip in clipsOnLane(laneId)) {
      if (clip.startTicks == start) {
        selectClip(clip.id);
        break;
      }
    }
  }

  void duplicateSelection() {
    if (selectedClipIds.isEmpty) return;
    _client.beginGesture('Duplicate clips');
    for (final String id in selectedClipIds.toList()) {
      final ArrangementClip? clip = clipById(id);
      if (clip == null) continue;
      _client.duplicateClip(id, startTicks: clip.endTicks);
    }
    _client.commitGesture();
    refresh();
  }

  void deleteSelection() {
    if (selectedClipIds.isEmpty) return;
    _client.beginGesture(
      selectedClipIds.length == 1 ? 'Delete clip' : 'Delete clips',
    );
    for (final String id in selectedClipIds.toList()) {
      _client.removeClip(id);
    }
    _client.commitGesture();
    selectedClipIds.clear();
    refresh();
  }

  void toggleClipMute(ArrangementClip clip) {
    _client.setClipMuted(clip.id, muted: !clip.muted);
    refresh();
  }

  void resizeClip(String clipId, int lengthTicks) {
    _client.resizeClip(clipId, lengthTicks < 1 ? 1 : lengthTicks);
    refresh();
  }

  void setClipStart(String clipId, int startTicks) {
    _client.moveClip(clipId, startTicks: startTicks < 0 ? 0 : startTicks);
    refresh();
  }

  void setClipWindowStart(String clipId, int windowStartTicks) {
    _client.setClipWindowStart(
      clipId,
      windowStartTicks < 0 ? 0 : windowStartTicks,
    );
    refresh();
  }

  void setClipLoop(String clipId, {required bool loop}) {
    _client.setClipLoop(clipId, loop: loop);
    refresh();
  }

  void setClipTranspose(String clipId, int semitones) {
    _client.setClipTranspose(clipId, semitones.clamp(-48, 48));
    refresh();
  }

  void makeClipsUnique(List<String> clipIds) {
    _client.makeClipsUnique(clipIds);
    refresh();
  }

  // ----- drags --------------------------------------------------------------

  void beginClipDrag(ClipDragKind kind, {String name = 'Move clip'}) {
    if (selectedClipIds.isEmpty) return;
    dragKind = kind;
    _dragDelta = 0;
    _dragLaneId = '';
    _client.beginGesture(name);
    _gestureOpen = true;
    notifyListeners();
  }

  void updateClipMove(int deltaTicks, {String laneId = ''}) {
    if (dragKind != ClipDragKind.move) return;
    if (deltaTicks == _dragDelta && laneId == _dragLaneId) return;
    final int step = deltaTicks - _dragDelta;
    for (final String id in selectedClipIds) {
      final ArrangementClip? clip = clipById(id);
      if (clip == null) continue;
      final int start = clip.startTicks + step;
      _client.moveClip(
        id,
        laneId: laneId,
        startTicks: start < 0 ? 0 : start,
      );
    }
    _dragDelta = deltaTicks;
    _dragLaneId = laneId;
    refresh();
  }

  void updateClipResize(String clipId, int lengthTicks) {
    if (dragKind != ClipDragKind.resizeEnd) return;
    _client.resizeClip(clipId, lengthTicks < 1 ? 1 : lengthTicks);
    refresh();
  }

  void updateClipOffset(String clipId, int windowStartTicks) {
    if (dragKind != ClipDragKind.offset) return;
    _client.setClipWindowStart(
      clipId,
      windowStartTicks < 0 ? 0 : windowStartTicks,
    );
    refresh();
  }

  void endClipDrag() {
    if (dragKind == ClipDragKind.none) return;
    dragKind = ClipDragKind.none;
    if (_gestureOpen) {
      _client.commitGesture();
      _gestureOpen = false;
    }
    _dragDelta = 0;
    _dragLaneId = '';
    refresh();
  }

  void cancelClipDrag() {
    if (dragKind == ClipDragKind.none) return;
    dragKind = ClipDragKind.none;
    if (_gestureOpen) {
      _client.abortGesture();
      _gestureOpen = false;
    }
    _dragDelta = 0;
    _dragLaneId = '';
    refresh();
  }
}
