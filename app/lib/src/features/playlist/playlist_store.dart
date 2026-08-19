// Playlist store — arrangement state and gestures (UI-D-04).
//
// Lanes and clips live in the engine. What lives here is selection, viewport,
// and in-flight drag gesture state.
import 'package:flutter/foundation.dart';

import '../../core/pattern_store.dart';
import '../../engine/engine_client.dart';
import 'playlist_selection.dart';

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

@immutable
class PlaylistInsertItem {
  const PlaylistInsertItem({required this.id, this.patternId = '', this.audioPath = ''});

  final String id;
  final String patternId;
  final String audioPath;

  bool get isAudio => audioPath.isNotEmpty;
}

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
  PlaylistInsertItem? lastClickedItem;

  GridChoice snap = const GridChoice('1 bar', ticksPerBar);
  double horizontalZoom = 1.0;
  double scrollTicks = 0.0;
  double scrollLanes = 0.0;
  PlaylistTool tool = PlaylistTool.select;
  PlaylistTimeSelection? timeSelection;

  ClipDragKind dragKind = ClipDragKind.none;
  PlaylistMarquee? marquee;
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
      final PatternSummary? current = patterns.cast<PatternSummary?>().firstWhere(
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

  bool isHighlighted(ArrangementClip clip) => selectedPatternId.isNotEmpty && clip.patternId == selectedPatternId;

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

  void setTool(PlaylistTool value) {
    if (tool == value) return;
    tool = value;
    notifyListeners();
  }

  void setTimeSelection(int startTick, int endTick) {
    timeSelection = PlaylistTimeSelection(startTick < 0 ? 0 : startTick, endTick < 0 ? 0 : endTick);
    notifyListeners();
  }

  void clearTimeSelection() {
    if (timeSelection == null) return;
    timeSelection = null;
    notifyListeners();
  }

  void zoomHorizontally(double factor) {
    horizontalZoom = (horizontalZoom * factor).clamp(0.1, 20.0);
    notifyListeners();
  }

  void panTo(double ticks, [double? lanes]) {
    scrollTicks = ticks < 0 ? 0 : ticks;
    if (lanes != null) scrollLanes = lanes < 0 ? 0 : lanes;
    notifyListeners();
  }

  /// Pans the viewport without imposing a content boundary. The playlist is an
  /// arrangement surface, not a document with a meaningful last page: a wheel
  /// gesture may reveal a future bar or a future lane before anything exists
  /// there.
  void panBy({double deltaTicks = 0, double deltaLanes = 0}) {
    panTo(scrollTicks + deltaTicks, scrollLanes + deltaLanes);
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

  void setLastClickedItem(PlaylistInsertItem item) {
    lastClickedItem = item;
    notifyListeners();
  }

  /// Places an explicit browser item at a playlist location. Patterns and
  /// audio files use the same drop target; only the engine command differs.
  void placeItem(PlaylistInsertItem item, String laneId, int startTicks) {
    if (!item.isAudio) {
      if (item.patternId.isNotEmpty) {
        selectedPatternId = item.patternId;
        try {
          _client.selectPattern(item.patternId);
        } catch (_) {
          // A presentation fake may not expose pattern selection.
        }
      }
      placeCurrentPattern(laneId, startTicks);
      return;
    }
    final int start = snapTick(startTicks);
    try {
      _client.addAudioClip(laneId, item.audioPath, start);
    } catch (_) {
      return;
    }
    refresh();
    final ArrangementClip? added = clips.cast<ArrangementClip?>().firstWhere(
      (ArrangementClip? clip) => clip?.isAudio == true && clip?.laneId == laneId && clip?.startTicks == start,
      orElse: () => null,
    );
    if (added != null) selectClip(added.id);
  }

  /// Places the last item chosen in the browser when empty playlist space is
  /// clicked. Drag-and-drop uses [placeItem] directly so it does not change the
  /// browser's click selection as a side effect.
  void placeLastClickedItem(String laneId, int startTicks) {
    final PlaylistInsertItem? item = lastClickedItem;
    if (item == null) {
      placeCurrentPattern(laneId, startTicks);
      return;
    }
    placeItem(item, laneId, startTicks);
  }

  void placeCurrentPattern(String laneId, int startTicks) {
    // Read the current flag at insertion time. The browser can change the
    // selected pattern without rebuilding this binding's store, and the next
    // empty-slot click must use that last browser choice rather than whatever
    // pattern a previously selected clip happened to reference.
    final List<PatternSummary> available = _client.readPatterns();
    PatternSummary? pattern = available.cast<PatternSummary?>().firstWhere(
      (PatternSummary? candidate) => candidate?.isCurrent ?? false,
      orElse: () => null,
    );
    if (pattern == null && selectedPatternId.isNotEmpty) {
      pattern = available.cast<PatternSummary?>().firstWhere(
        (PatternSummary? candidate) => candidate?.id == selectedPatternId,
        orElse: () => null,
      );
    }
    pattern ??= available.isNotEmpty ? available.first : null;
    if (pattern == null) return;
    selectedPatternId = pattern.id;

    final int start = snapTick(startTicks);
    _client.addClip(laneId, patternId: pattern.id, startTicks: start, lengthTicks: pattern.lengthTicks);
    refresh();

    for (final ArrangementClip clip in clipsOnLane(laneId)) {
      if (clip.startTicks == start) {
        selectClip(clip.id);
        break;
      }
    }
  }

  /// Duplicates the selection one selection-length later, and leaves the copies
  /// selected (⌘B / ⌘D — the piano roll's [PianoRollStore.duplicateSelection]
  /// behaviour, on clips).
  ///
  /// One offset for the whole selection, not one per clip: duplicating a
  /// two-bar phrase spread over three lanes has to produce the same phrase two
  /// bars later, and offsetting each clip by its own length would shear it.
  /// Selecting the copies is what makes ⌘B repeatable — press it four times and
  /// you have four bars of the phrase.
  void duplicateSelection() {
    if (selectedClipIds.isEmpty) return;
    final List<ArrangementClip> selected = <ArrangementClip>[];
    for (final String id in selectedClipIds) {
      final ArrangementClip? clip = clipById(id);
      if (clip != null) selected.add(clip);
    }
    if (selected.isEmpty) return;

    int lowest = selected.first.startTicks;
    int highest = selected.first.endTicks;
    for (final ArrangementClip clip in selected) {
      if (clip.startTicks < lowest) lowest = clip.startTicks;
      if (clip.endTicks > highest) highest = clip.endTicks;
    }
    int delta = highest - lowest;
    // Rounded *up* to the snap step, so the copy lands on the grid the user is
    // working to rather than a step before it.
    if (snap.ticks > 0) {
      delta = ((delta + snap.ticks - 1) ~/ snap.ticks) * snap.ticks;
    }
    if (delta <= 0) return;

    final Set<String> before = clips.map((ArrangementClip clip) => clip.id).toSet();
    _client.beginGesture(selected.length == 1 ? 'Duplicate clip' : 'Duplicate clips');
    for (final ArrangementClip clip in selected) {
      _client.duplicateClip(clip.id, laneId: clip.laneId, startTicks: clip.startTicks + delta);
    }
    _client.commitGesture();
    refresh();

    // The engine mints the ids, so the copies are "whatever is new" — read
    // back rather than guessed at from positions, which two clips could share.
    final Iterable<String> copies = clips
        .map((ArrangementClip clip) => clip.id)
        .where((String id) => !before.contains(id));
    if (copies.isNotEmpty) selectClips(copies);
  }

  void deleteSelection() {
    if (selectedClipIds.isEmpty) return;
    _client.beginGesture(selectedClipIds.length == 1 ? 'Delete clip' : 'Delete clips');
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

  /// Resize, applying the clip's own rule for what its right edge means.
  ///
  /// A pattern clip's length is just a length. An audio clip's is a length
  /// *and* a decision: an unstretched clip re-trims and a stretched one
  /// stretches, and the engine owns that branch so the two can never drift
  /// apart. Sending an audio clip through the plain resize would silently pick
  /// the trimming half of it forever.
  void resizeClip(String clipId, int lengthTicks) {
    final int length = lengthTicks < 1 ? 1 : lengthTicks;
    final ArrangementClip? clip = clipById(clipId);
    if (clip != null && clip.isAudio) {
      _client.resizeAudioClip(clipId, length);
    } else {
      _client.resizeClip(clipId, length);
    }
    refresh();
  }

  // ----- audio clip editing -------------------------------------------------

  /// The selected audio clip's edit parameters, or null when the selection is
  /// not one audio clip.
  AudioClipEdit? get selectedAudioEdit {
    final ArrangementClip? clip = selectedClip;
    if (clip == null || !clip.isAudio) return null;
    return _client.readAudioClip(clip.id);
  }

  /// Cuts at an absolute tick. The left half keeps the clip's ID and stays
  /// selected; the right half is new, and selecting it instead would move the
  /// selection out from under the user's cursor.
  void splitClipAt(String clipId, int atTicks) {
    _client.splitClip(clipId, atTicks);
    refresh();
  }

  void setClipStretchMode(String clipId, StretchMode mode) {
    _client.setAudioClipStretchMode(clipId, mode);
    refresh();
  }

  void setClipSourceBpm(String clipId, double bpm) {
    _client.setAudioClipSourceBpm(clipId, bpm);
    refresh();
  }

  void setClipReversed(String clipId, {required bool reversed}) {
    _client.setAudioClipReversed(clipId, reversed: reversed);
    refresh();
  }

  void setClipSourceWindow(String clipId, {required int offsetTicks, required int lengthTicks}) {
    _client.setAudioClipWindow(
      clipId,
      sourceOffsetTicks: offsetTicks < 0 ? 0 : offsetTicks,
      sourceLengthTicks: lengthTicks < 0 ? 0 : lengthTicks,
    );
    refresh();
  }

  /// Resizes the clip so its material plays at the project tempo. Does nothing
  /// when the clip has no source tempo recorded — the engine refuses rather
  /// than guessing, and a guess here is how a project ends up out of time.
  void fitClipToTempo(String clipId) {
    _client.fitAudioClipToTempo(clipId);
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

  void makeClipsUnique(List<String> clipIds) {
    _client.makeClipsUnique(clipIds);
    refresh();
  }

  /// FL's "split by channel": the clip is replaced by one clip per channel of
  /// its pattern, each on its own lane. The old selection is dropped — the
  /// clip it named no longer exists.
  void splitClipByChannel(String clipId) {
    _client.splitClipByChannel(clipId);
    selectedClipIds.clear();
    refresh();
  }

  // ----- selection marquee --------------------------------------------------

  void beginMarquee(int tick, int lane) {
    dragKind = ClipDragKind.marquee;
    marquee = PlaylistMarquee(tick, lane, tick, lane);
    notifyListeners();
  }

  void updateMarquee(int tick, int lane) {
    final PlaylistMarquee? current = marquee;
    if (dragKind != ClipDragKind.marquee || current == null) return;
    marquee = PlaylistMarquee(current.startTick, current.startLane, tick, lane);
    final Map<String, int> laneIndexes = <String, int>{
      for (int index = 0; index < lanes.length; index++) lanes[index].id: index,
    };
    selectedClipIds
      ..clear()
      ..addAll(
        clips
            .where((ArrangementClip clip) => marquee!.contains(clip, laneIndexes[clip.laneId] ?? 0))
            .map((ArrangementClip clip) => clip.id),
      );
    notifyListeners();
  }

  void endMarquee() {
    if (dragKind != ClipDragKind.marquee) return;
    dragKind = ClipDragKind.none;
    marquee = null;
    notifyListeners();
  }

  void cancelMarquee() {
    if (dragKind != ClipDragKind.marquee) return;
    dragKind = ClipDragKind.none;
    marquee = null;
    notifyListeners();
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
      _client.moveClip(id, laneId: laneId, startTicks: start < 0 ? 0 : start);
    }
    _dragDelta = deltaTicks;
    _dragLaneId = laneId;
    refresh();
  }

  void updateClipResize(String clipId, int lengthTicks) {
    if (dragKind != ClipDragKind.resizeEnd) return;
    // Same branch as `resizeClip`: dragging the edge and typing a length must
    // mean the same thing, or a stretched clip stretches one way and trims the
    // other.
    final int length = lengthTicks < 1 ? 1 : lengthTicks;
    final ArrangementClip? clip = clipById(clipId);
    if (clip != null && clip.isAudio) {
      _client.resizeAudioClip(clipId, length);
    } else {
      _client.resizeClip(clipId, length);
    }
    refresh();
  }

  void updateClipOffset(String clipId, int windowStartTicks) {
    if (dragKind != ClipDragKind.offset) return;
    _client.setClipWindowStart(clipId, windowStartTicks < 0 ? 0 : windowStartTicks);
    refresh();
  }

  void endClipDrag() {
    if (dragKind == ClipDragKind.none) return;
    dragKind = ClipDragKind.none;
    marquee = null;
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
    marquee = null;
    if (_gestureOpen) {
      _client.abortGesture();
      _gestureOpen = false;
    }
    _dragDelta = 0;
    _dragLaneId = '';
    refresh();
  }
}
