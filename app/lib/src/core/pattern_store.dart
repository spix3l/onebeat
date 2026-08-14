// Pattern management state (OB-3-11).
//
// The model stays native. What lives here is the selection, and the one piece
// of genuinely session-scoped state D-M6 asks for: which shared patterns the
// user has already been warned about, so the warning never nags.
import 'package:flutter/foundation.dart';

import '../engine/engine_client.dart';

/// The non-blocking notice D-M6 specifies: "Editing 'Verse Drums' — used in 6
/// places". It is a *notice*, never a dialog and never a confirmation — the
/// edit has already happened by the time this exists.
@immutable
class SharedPatternNotice {
  const SharedPatternNotice({
    required this.patternId,
    required this.patternName,
    required this.usageCount,
    required this.clipId,
  });

  final String patternId;
  final String patternName;
  final int usageCount;

  /// The clip the edit came from, when the user got here by double-clicking a
  /// clip. Only then can "Make unique for this clip" mean anything, so the
  /// inline action appears exactly when it is actionable.
  final String clipId;

  bool get canMakeUnique => clipId.isNotEmpty;

  String get message =>
      "Editing '$patternName' — used in $usageCount places. Changes apply to "
      'all of them.';
}

class PatternStore extends ChangeNotifier {
  PatternStore(this._client);

  final PatternClient _client;

  List<PatternSummary> patterns = const <PatternSummary>[];

  /// Set when the user arrived in an editor from a specific clip. Cleared on
  /// pattern change, because the clip context no longer applies.
  String editingFromClipId = '';

  SharedPatternNotice? notice;

  /// Patterns already warned about this session. D-M6: "once per pattern per
  /// session" — the point of the notice is to teach the reference model, and a
  /// message that appears on every keystroke teaches only irritation.
  final Set<String> _warned = <String>{};

  void load() => refresh();

  void refresh() {
    patterns = _client.readPatterns();
    notifyListeners();
  }

  PatternSummary? get current {
    for (final PatternSummary pattern in patterns) {
      if (pattern.isCurrent) return pattern;
    }
    return patterns.isEmpty ? null : patterns.first;
  }

  PatternSummary? byId(String patternId) {
    for (final PatternSummary pattern in patterns) {
      if (pattern.id == patternId) return pattern;
    }
    return null;
  }

  /// Clips of the current pattern are highlighted in the arrangement (D-M6's
  /// instance highlighting). The arrangement asks this rather than keeping its
  /// own copy of the selection.
  bool highlightsPattern(String patternId) =>
      patternId.isNotEmpty && current?.id == patternId;

  void select(String patternId, {String fromClipId = ''}) {
    _client.selectPattern(patternId);
    editingFromClipId = fromClipId;
    notice = null;
    refresh();
  }

  void create(String name) {
    _client.createPattern(name);
    editingFromClipId = '';
    refresh();
  }

  void rename(String patternId, String name) {
    if (name.trim().isEmpty) return;
    _client.renamePattern(patternId, name.trim());
    refresh();
  }

  void recolor(String patternId, String color) {
    _client.recolorPattern(patternId, color);
    refresh();
  }

  void duplicate(String patternId) {
    _client.duplicatePattern(patternId);
    editingFromClipId = '';
    refresh();
  }

  void remove(String patternId) {
    _client.removePattern(patternId);
    _warned.remove(patternId);
    refresh();
  }

  /// Called by the note editors *before* they mutate. Raises the notice the
  /// first time this session that a multi-referenced pattern is edited, and
  /// never blocks: the return value is deliberately ignored by callers.
  void noteEditStarted() {
    final PatternSummary? pattern = current;
    if (pattern == null || !pattern.isShared) return;
    if (!_warned.add(pattern.id)) return;
    notice = SharedPatternNotice(
      patternId: pattern.id,
      patternName: pattern.name,
      usageCount: pattern.usageCount,
      clipId: editingFromClipId,
    );
    notifyListeners();
  }

  void dismissNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  /// FR-SEQ-04. Also the notice's inline action, which is why it takes the
  /// clips explicitly rather than reading a selection it does not own.
  void makeUnique(List<String> clipIds) {
    if (clipIds.isEmpty) return;
    _client.makeClipsUnique(clipIds);
    notice = null;
    // The clone is now current, and it is referenced once, so it is not shared
    // and carries no warning of its own.
    refresh();
  }

  @visibleForTesting
  bool hasWarnedAbout(String patternId) => _warned.contains(patternId);
}
