// Arrangement editor state (OB-3-12, OB-3-13).
//
// Lanes and clips live natively. What lives here is selection, the viewport,
// and in-flight drag state.
//
// The critical negative, restated because this is the file most likely to
// grow a violation: a lane carries no signal. There is no gain, no meter, no
// instrument and no plugin here, and there is no client call that could add
// one. Moving a clip between lanes changes nothing audible, and the offline
// render equality test in `engine/tests` is what keeps that honest.
import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';
import 'pattern_store.dart';
import 'piano_roll_store.dart' show GridChoice, ticksPerBar, ticksPerQuarter;

enum ClipDragKind { none, move, resizeEnd, offset, marquee }

class ArrangementStore extends ChangeNotifier {
  ArrangementStore(this._client, this._patterns);

  final ArrangementClient _client;
  final PatternStore _patterns;

  List<ArrangementLane> lanes = const <ArrangementLane>[];
  List<ArrangementClip> clips = const <ArrangementClip>[];

  final Set<String> selectedClipIds = <String>{};
  String selectedLaneId = '';

  GridChoice snap = const GridChoice('1 bar', ticksPerBar);
  double horizontalZoom = 1;
  double scrollTicks = 0;

  ClipDragKind dragKind = ClipDragKind.none;
  bool _gestureOpen = false;
  int _dragDelta = 0;
  String _dragLaneId = '';

  static const List<GridChoice> snapChoices = <GridChoice>[
    GridChoice('4 bars', ticksPerBar * 4),
    GridChoice('1 bar', ticksPerBar),
    GridChoice('1/4', ticksPerQuarter),
    GridChoice('1/8', ticksPerQuarter ~/ 2),
    GridChoice('1/16', ticksPerQuarter ~/ 4),
    GridChoice('Off', 0),
  ];

  static const double _basePixelsPerTick = 0.012;
  double get pixelsPerTick => _basePixelsPerTick * horizontalZoom;

  void load() => refresh();

  void refresh() {
    lanes = _client.readLanes();
    clips = _client.readClips();
    // A clip that was deleted (or undone away) must not stay selected, or the
    // inspector edits an id the model no longer knows.
    final Set<String> live = clips.map((ArrangementClip c) => c.id).toSet();
    selectedClipIds.removeWhere((String id) => !live.contains(id));
    if (selectedLaneId.isEmpty && lanes.isNotEmpty) {
      selectedLaneId = lanes.first.id;
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

  /// D-M6's instance highlighting: every clip of the selected pattern reads as
  /// one family, so the user sees the blast radius before they edit.
  bool isHighlighted(ArrangementClip clip) =>
      _patterns.highlightsPattern(clip.patternId);

  bool isSelected(ArrangementClip clip) => selectedClipIds.contains(clip.id);

  /// The end of the last clip, which is how long the arrangement is.
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
    if (clip != null) selectedLaneId = clip.laneId;
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

  /// Drag-reorder: lanes are renumbered densely so that `order` stays a small
  /// contiguous range rather than drifting apart over many moves.
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

  /// The event gate (D-M4). Named for what it does everywhere it appears.
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

  /// Places the current pattern. Length defaults to the pattern's own length,
  /// so a dropped clip plays exactly once before it starts repeating.
  void placeCurrentPattern(String laneId, int startTicks) {
    final PatternSummary? pattern = _patterns.current;
    if (pattern == null) return;
    _client.addClip(
      laneId,
      patternId: pattern.id,
      startTicks: snapTick(startTicks),
      lengthTicks: pattern.lengthTicks,
    );
    refresh();
    _patterns.refresh();
    // Select what was just created, which is what makes the inspector useful
    // immediately after a drop.
    for (final ArrangementClip clip in clipsOnLane(laneId)) {
      if (clip.startTicks == snapTick(startTicks)) {
        selectClip(clip.id);
        break;
      }
    }
  }

  /// Each duplicate lands immediately after its source. Bracketed so that
  /// duplicating a multi-clip selection is one undo entry, not one per clip.
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
    _patterns.refresh();
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
    _patterns.refresh();
  }

  void toggleClipMute(ArrangementClip clip) {
    _client.setClipMuted(clip.id, muted: !clip.muted);
    refresh();
  }

  // ----- OB-3-13: windowing and transforms ---------------------------------

  void resizeClip(String clipId, int lengthTicks) {
    _client.resizeClip(clipId, lengthTicks < 1 ? 1 : lengthTicks);
    refresh();
  }

  void setClipStart(String clipId, int startTicks) {
    _client.moveClip(clipId, startTicks: startTicks < 0 ? 0 : startTicks);
    refresh();
  }

  void setClipWindowStart(String clipId, int windowStartTicks) {
    _client.setClipWindowStart(clipId, windowStartTicks < 0 ? 0 : windowStartTicks);
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

  /// Moves the whole selection by a delta, optionally onto another lane. Every
  /// selected clip shifts by the same amount, so their relative timing holds.
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
    _patterns.refresh();
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
