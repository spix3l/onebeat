// The Dart side of the boundary (OB-1-10 §2).
//
// Threading contract (ADR-002 §6): the engine handle is owned by the Flutter UI
// isolate's main zone. Every method here is called from that isolate and from
// no other. Nothing here blocks, and nothing here allocates per frame:
//   - the snapshot struct is allocated once at startup and reused;
//   - the command struct is allocated once and rewritten in place;
//   - the event struct is allocated once and drained into plain Dart objects
//     only when an event actually arrives.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'engine_library.dart';
import 'generated/onebeat_bindings.dart';

/// Reads a fixed-size, NUL-terminated UTF-8 field out of a native struct.
///
/// Decoding as UTF-8 rather than character-by-character matters here: plug-in
/// and vendor names are full of accented characters and the occasional CJK
/// title, and treating each byte as a code point renders those as mojibake.
String _readFixedUtf8(Array<Char> field, int capacity) {
  final Uint8List bytes = Uint8List(capacity);
  int length = 0;
  while (length < capacity) {
    final int byte = field[length];
    if (byte == 0) {
      break;
    }
    bytes[length] = byte;
    length++;
  }
  // `allowMalformed`: this is data from disk, so a truncated multi-byte
  // sequence at the capacity boundary is possible. A replacement character in
  // a plug-in name beats an exception during a scan.
  return utf8.decode(bytes.sublist(0, length), allowMalformed: true);
}

/// A plain Dart copy of one snapshot. Constructed only when the UI wants an
/// immutable value to hold; the per-frame path reads the native struct directly.
class EngineSnapshot {
  const EngineSnapshot({
    required this.playing,
    required this.loopEnabled,
    required this.loopStartBeats,
    required this.loopEndBeats,
    required this.positionFrames,
    required this.positionBeats,
    required this.positionSeconds,
    required this.hostTimeNanos,
    required this.tempoBpm,
    required this.bar,
    required this.beat,
    required this.tick,
    required this.sampleRate,
    required this.blockFrames,
    required this.activeVoices,
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.cpuLoad,
    required this.xrunCount,
    required this.latencyFramesRoundTrip,
    required this.scheduleEventCount,
  });

  const EngineSnapshot.empty()
    : playing = false,
      loopEnabled = false,
      loopStartBeats = 0,
      loopEndBeats = 0,
      positionFrames = 0,
      positionBeats = 0,
      positionSeconds = 0,
      hostTimeNanos = 0,
      tempoBpm = 120,
      bar = 1,
      beat = 1,
      tick = 0,
      sampleRate = 48000,
      blockFrames = 0,
      activeVoices = 0,
      peakLeft = 0,
      peakRight = 0,
      rmsLeft = 0,
      rmsRight = 0,
      cpuLoad = 0,
      xrunCount = 0,
      latencyFramesRoundTrip = 0,
      scheduleEventCount = 0;

  final bool playing;
  final bool loopEnabled;

  /// The loop region, in beats. Drawn on the arrangement ruler, and dragged
  /// there (OB-3-12 §4).
  final double loopStartBeats;
  final double loopEndBeats;

  final int positionFrames;
  final double positionBeats;
  final double positionSeconds;
  final int hostTimeNanos;
  final double tempoBpm;
  final int bar;
  final int beat;
  final int tick;
  final double sampleRate;
  final int blockFrames;
  final int activeVoices;
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final double cpuLoad;
  final int xrunCount;
  final int latencyFramesRoundTrip;
  final int scheduleEventCount;

  double get latencyMilliseconds =>
      sampleRate <= 0 ? 0 : (latencyFramesRoundTrip / sampleRate) * 1000.0;
}

/// One notification from the engine (device change, error, sample loaded).
class EngineEvent {
  const EngineEvent(
    this.type,
    this.code,
    this.intValue,
    this.doubleValue,
    this.text,
  );

  final int type;
  final int code;
  final int intValue;
  final double doubleValue;
  final String text;

  bool get isError => type == evtError;
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class RackClient {
  RackPattern readRackPattern();
  List<RackRow> readRackRows();
  void setRackRowGrid(String instrumentId, int gridTicks);
  void setRackLength(int steps);
  void setRackSwing(double swing);
  void toggleRackStep(String instrumentId, int step);
  void setRackStepVelocity(String instrumentId, int step, int velocity);
  void removeRackSequence(String instrumentId);
  void beginRackGesture(String name);
  void commitRackGesture();
  void abortRackGesture();
  bool get canUndoProject;
  bool get canRedoProject;
  String get undoProjectName;
  String get redoProjectName;
  void undoProject();
  void redoProject();
}

/// Gesture bracketing, shared by every editor that drags.
///
/// A drag emits many small edits and must land in the history as one entry. All
/// three editors use the *same* native transaction — the rack's — so this is
/// one interface rather than three copies, and [RackClient]'s longer-named
/// members remain for the rack's existing call sites.
abstract interface class EditGestureClient {
  void beginGesture(String name);
  void commitGesture();
  void abortGesture();
}

/// The piano roll's seam (OB-3-10). Notes are addressed by value rather than by
/// index or ID, exactly as the native side does: an index would go stale the
/// moment another edit re-sorted the sequence, so the editor holds the notes it
/// selected and hands the same values back.
abstract interface class NoteClient implements EditGestureClient {
  List<SequenceNote> readNotes(String instrumentId);
  void addNote(
    String instrumentId,
    int startTicks,
    int lengthTicks,
    int key, {
    int velocity = 0,
  });
  void removeNotes(String instrumentId, List<SequenceNote> notes);
  void moveNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    int deltaTicks = 0,
    int semitones = 0,
    int snapTicks = 0,
  });
  void resizeNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int lengthDelta,
    int snapTicks = 0,
  });
  void setNoteVelocity(
    String instrumentId,
    List<SequenceNote> notes,
    int velocity,
  );
  void quantiseNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int gridTicks,
    required double strength,
  });
  void duplicateNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int deltaTicks,
  });

  /// Audition (OB-3-10 §5): the preview path through the selected instrument.
  void auditionNoteOn(int key, double velocity);
  void auditionNoteOff(int key);
}

/// Pattern management (OB-3-11). `usageCount` is derived natively on every read
/// rather than cached, so the badge cannot go stale.
abstract interface class PatternClient {
  List<PatternSummary> readPatterns();
  void selectPattern(String patternId);
  void createPattern(String name);
  void renamePattern(String patternId, String name);
  void recolorPattern(String patternId, String color);

  /// An unreferenced clone. Distinct from [makeClipsUnique], which repoints the
  /// clips it is given — both exist because they are different intentions
  /// (FR-UX-11's consistent action vocabulary).
  void duplicatePattern(String patternId);
  void removePattern(String patternId);

  /// FR-SEQ-04: one clone, every listed clip repointed at it, one undo entry.
  void makeClipsUnique(List<String> clipIds);
}

/// The arrangement's seam (OB-3-12, OB-3-13). Note what is absent: nothing here
/// carries signal. A lane has no instrument, no gain and no meter, and there is
/// deliberately no call that would give it one (ARCHITECTURE.md §6 #2).
abstract interface class ArrangementClient implements EditGestureClient {
  List<ArrangementLane> readLanes();
  void createLane(String name);
  void renameLane(String laneId, String name);
  void recolorLane(String laneId, String color);
  void reorderLane(String laneId, int order);
  void setLaneHeight(String laneId, int height);
  void setLaneMuted(String laneId, {required bool muted});
  void setLaneSoloed(String laneId, {required bool soloed});
  void setLaneCollapsed(String laneId, {required bool collapsed});
  void removeLane(String laneId);

  List<ArrangementClip> readClips();
  void addClip(
    String laneId, {
    String patternId = '',
    required int startTicks,
    required int lengthTicks,
  });
  void moveClip(String clipId, {String laneId = '', required int startTicks});
  void resizeClip(String clipId, int lengthTicks);
  void duplicateClip(
    String clipId, {
    String laneId = '',
    required int startTicks,
  });
  void removeClip(String clipId);
  void setClipMuted(String clipId, {required bool muted});
  void setClipLoop(String clipId, {required bool loop});
  void setClipWindowStart(String clipId, int windowStartTicks);
  void setClipTranspose(String clipId, int semitones);
}

/// The project file seam (OB-3-05 §4): where the project lives, what it is
/// called, and whether it still matches what was written.
///
/// A separate interface because the whole of ⌘S, ⌘O and Rename is expressible
/// through it, which is what lets [ProjectStore] be tested without an engine,
/// a dylib or an audio device.
abstract interface class ProjectFileClient {
  /// The bundle the project was last saved to or opened from; empty for a
  /// project that has never been written.
  String get projectPath;

  /// `meta.name` — the user-facing name, which is not the file name. An
  /// unsaved project has a name and no path.
  String get projectName;

  /// Renames the project. An edit like any other: it undoes, and it dirties.
  /// Renaming the bundle on disk is [ProjectStore]'s job, not the engine's.
  void setProjectName(String name);

  /// True when the project differs from what was last saved or opened.
  ///
  /// Walks the project to answer, so poll it at the rate a human notices —
  /// [ProjectStore] does — rather than calling it every frame.
  bool get isProjectModified;

  void saveProject(String path);
  void openProject(String path);
}

class EngineClient
    implements
        RackClient,
        NoteClient,
        PatternClient,
        ArrangementClient,
        ProjectFileClient {
  EngineClient._(this._bindings, this._engine)
    : _snapshot = calloc<ob_snapshot>(),
      _command = calloc<ob_command>(),
      _event = calloc<ob_event>(),
      _scanStatus = calloc<ob_plugin_scan_status>(),
      _pluginInfo = calloc<ob_plugin_info>(),
      _instanceInfo = calloc<ob_instance_info>(),
      _instrumentInfo = calloc<ob_instrument_info>(),
      _rackPatternInfo = calloc<ob_rack_pattern_info>(),
      _rackRowInfo = calloc<ob_rack_row_info>(),
      _patternInfo = calloc<ob_pattern_info>(),
      _laneInfo = calloc<ob_lane_info>(),
      _clipInfo = calloc<ob_clip_info>(),
      _noteCount = calloc<Int32>(),
      _paramInfo = calloc<ob_param_info>();

  /// Creates and initialises the engine. [useNullDevice] runs headless, which
  /// is how widget tests and CI drive the UI without audio hardware.
  factory EngineClient.start({
    double sampleRate = 48000,
    int blockFrames = 128,
    bool useNullDevice = false,
  }) {
    final OneBeatBindings bindings = openEngineLibrary();
    final Pointer<ob_engine_config> config = calloc<ob_engine_config>();
    final Pointer<Pointer<ob_engine>> out = calloc<Pointer<ob_engine>>();
    try {
      config.ref.struct_size = sizeOf<ob_engine_config>();
      config.ref.sample_rate = sampleRate;
      config.ref.block_frames = blockFrames;
      config.ref.use_null_device = useNullDevice ? 1 : 0;
      config.ref.log_directory = nullptr;

      final ob_status status = bindings.ob_engine_create(config, out);
      if (status != ob_status.OB_OK) {
        throw EngineException(
          bindings.ob_last_error_message().cast<Utf8>().toDartString(),
        );
      }
      return EngineClient._(bindings, out.value);
    } finally {
      calloc.free(config);
      calloc.free(out);
    }
  }

  final OneBeatBindings _bindings;
  final Pointer<ob_engine> _engine;

  // Allocated once, reused for the lifetime of the app: the per-frame path must
  // not allocate (OB-1-11 AC).
  final Pointer<ob_snapshot> _snapshot;
  final Pointer<ob_command> _command;
  final Pointer<ob_event> _event;
  // Reused the same way, though the plug-in path is not per-frame: the list is
  // re-read only when the scan's list generation moves.
  final Pointer<ob_plugin_scan_status> _scanStatus;
  final Pointer<ob_plugin_info> _pluginInfo;
  final Pointer<ob_instance_info> _instanceInfo;
  final Pointer<ob_instrument_info> _instrumentInfo;
  final Pointer<ob_rack_pattern_info> _rackPatternInfo;
  final Pointer<ob_rack_row_info> _rackRowInfo;
  final Pointer<ob_pattern_info> _patternInfo;
  final Pointer<ob_lane_info> _laneInfo;
  final Pointer<ob_clip_info> _clipInfo;
  final Pointer<Int32> _noteCount;
  final Pointer<ob_param_info> _paramInfo;

  // The note buffer is the one output that is not a single fixed struct, so it
  // grows on demand and is then reused. Reading a 2,000-note pattern must not
  // allocate 2,000 times, and the roll re-reads on every sequence change.
  Pointer<ob_note> _noteBuffer = nullptr;
  int _noteCapacity = 0;

  Pointer<ob_note> _ensureNoteCapacity(int needed) {
    if (needed <= _noteCapacity) return _noteBuffer;
    if (_noteBuffer != nullptr) calloc.free(_noteBuffer);
    // Round up so a sequence that grows a note at a time does not reallocate on
    // every single edit.
    _noteCapacity = needed < 128 ? 128 : needed * 2;
    _noteBuffer = calloc<ob_note>(_noteCapacity);
    return _noteBuffer;
  }

  int _generation = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  String get deviceName =>
      _bindings
          .ob_engine_output_device_name(_engine)
          .cast<Utf8>()
          .toDartString();

  void startAudio() {
    final ob_status status = _bindings.ob_engine_start(_engine);
    if (status != ob_status.OB_OK) {
      throw EngineException(
        _bindings.ob_last_error_message().cast<Utf8>().toDartString(),
      );
    }
  }

  void stopAudio() => _bindings.ob_engine_stop(_engine);

  // --- commands -------------------------------------------------------------

  void _post(int type, {int i64 = 0, double f64a = 0, double f64b = 0}) {
    if (_disposed) {
      return;
    }
    _command.ref.type = type;
    _command.ref.generation = ++_generation;
    _command.ref.i64_a = i64;
    _command.ref.f64_a = f64a;
    _command.ref.f64_b = f64b;
    _bindings.ob_engine_post_command(_engine, _command);
  }

  void play() => _post(cmdTransportPlay);
  void stop() => _post(cmdTransportStop);
  void seekFrames(int frames) => _post(cmdTransportSeekFrames, i64: frames);
  void seekBeats(double beats) => _post(cmdTransportSeekBeats, f64a: beats);
  void setTempo(double bpm) => _post(cmdSetTempo, f64a: bpm);
  void setLoop(double startBeats, double endBeats, {required bool enabled}) =>
      _post(cmdSetLoop, i64: enabled ? 1 : 0, f64a: startBeats, f64b: endBeats);
  void noteOn(int note, double velocity) =>
      _post(cmdNoteOn, i64: note, f64a: velocity);
  void noteOff(int note) => _post(cmdNoteOff, i64: note);
  void allNotesOff() => _post(cmdAllNotesOff);
  void setMasterGain(double gain) => _post(cmdSetMasterGain, f64a: gain);

  /// Loads a sample into the built-in preview voice without changing the
  /// project. The completion arrives as an `OB_EVT_SAMPLE_LOADED` event, which
  /// [EngineController] uses to start the audition at the right time.
  void loadSample(String samplePath) => _withNativeString(
    samplePath,
    (Pointer<Char> native) => _bindings.ob_engine_load_sample(_engine, native),
  );

  /// v0.1 content stand-in: a step pattern, flattened and published by the
  /// engine. Stage 3 replaces this with real model edits.
  void setStepPattern(
    List<int> steps, {
    int midiNote = 60,
    double stepBeats = 0.25,
  }) {
    final Pointer<Uint8> buffer = calloc<Uint8>(steps.length);
    try {
      for (int index = 0; index < steps.length; index++) {
        buffer[index] = steps[index];
      }
      _bindings.ob_engine_set_step_pattern(
        _engine,
        buffer,
        steps.length,
        midiNote,
        stepBeats,
      );
    } finally {
      calloc.free(buffer);
    }
  }

  // --- snapshots ------------------------------------------------------------

  /// Reads the latest snapshot. Allocation-free: the native struct is reused
  /// and only the returned Dart object is new (one small object per frame, which
  /// the UI needs anyway to rebuild).
  EngineSnapshot readSnapshot() {
    _bindings.ob_engine_read_snapshot(_engine, _snapshot);
    final ob_snapshot s = _snapshot.ref;
    return EngineSnapshot(
      playing: s.playing != 0,
      loopEnabled: s.loop_enabled != 0,
      loopStartBeats: s.loop_start_beats,
      loopEndBeats: s.loop_end_beats,
      positionFrames: s.position_frames,
      positionBeats: s.position_beats,
      positionSeconds: s.position_seconds,
      hostTimeNanos: s.host_time_ns,
      tempoBpm: s.tempo_bpm,
      bar: s.bar,
      beat: s.beat,
      tick: s.tick,
      sampleRate: s.sample_rate,
      blockFrames: s.block_frames,
      activeVoices: s.active_voices,
      peakLeft: s.peak_left,
      peakRight: s.peak_right,
      rmsLeft: s.rms_left,
      rmsRight: s.rms_right,
      cpuLoad: s.cpu_load,
      xrunCount: s.xrun_count,
      latencyFramesRoundTrip: s.latency_frames_roundtrip,
      scheduleEventCount: s.schedule_event_count,
    );
  }

  /// Drains pending engine notifications. Returns an empty list in the common
  /// case without allocating anything on the native side.
  List<EngineEvent> pollEvents() {
    List<EngineEvent>? events;
    while (_bindings.ob_engine_poll_event(_engine, _event) == 1) {
      final ob_event e = _event.ref;
      (events ??= <EngineEvent>[]).add(
        EngineEvent(
          e.type,
          e.code,
          e.i64_a,
          e.f64_a,
          _readFixedUtf8(e.text, 96),
        ),
      );
    }
    return events ?? const <EngineEvent>[];
  }

  // --- plugin library (OB-2-02) ---------------------------------------------

  /// Loads the persistent scan cache. Blocking, and meant to be: it is one file
  /// read, and doing it before the first frame is what makes the plug-in list
  /// present at startup instead of appearing seconds later (FR-PLG-05).
  void loadPluginCache() => _bindings.ob_engine_plugin_cache_load(_engine);

  /// Starts a background scan. [directories] empty scans the standard folders.
  /// Returns false if a scan is already running.
  bool startPluginScan({List<String> directories = const <String>[]}) {
    if (directories.isEmpty) {
      return _bindings.ob_engine_plugin_scan_start(_engine, nullptr) ==
          ob_status.OB_OK;
    }
    // NUL-separated and double-NUL-terminated, which is what the ABI takes so
    // that neither side has to own an array of string pointers.
    final Uint8List encoded = Uint8List.fromList(<int>[
      for (final String directory in directories) ...<int>[
        ...utf8.encode(directory),
        0,
      ],
      0,
    ]);
    final Pointer<Uint8> buffer = calloc<Uint8>(encoded.length);
    try {
      buffer.asTypedList(encoded.length).setAll(0, encoded);
      return _bindings.ob_engine_plugin_scan_start(
            _engine,
            buffer.cast<Char>(),
          ) ==
          ob_status.OB_OK;
    } finally {
      calloc.free(buffer);
    }
  }

  void cancelPluginScan() => _bindings.ob_engine_plugin_scan_cancel(_engine);

  /// Re-scans one quarantined bundle in the same background worker used by a
  /// full scan. Returns false when another scan is already in flight.
  bool retryPluginScan(String path) {
    final Pointer<Utf8> encoded = path.toNativeUtf8();
    try {
      return _bindings.ob_engine_plugin_retry(_engine, encoded.cast<Char>()) ==
          ob_status.OB_OK;
    } finally {
      calloc.free(encoded);
    }
  }

  /// Reads scan progress. Also the call that folds streamed results into the
  /// list, so it must be made regularly while a scan is running.
  PluginScanStatus readPluginScanStatus() {
    _bindings.ob_engine_plugin_scan_status(_engine, _scanStatus);
    final ob_plugin_scan_status s = _scanStatus.ref;
    return PluginScanStatus(
      state: ScanState.values[s.state.clamp(0, ScanState.values.length - 1)],
      bundlesDiscovered: s.bundles_discovered,
      bundlesReused: s.bundles_reused,
      bundlesProbed: s.bundles_probed,
      pluginsFound: s.plugins_found,
      pluginCount: s.plugin_count,
      listGeneration: s.list_generation,
      current: _readFixedUtf8(s.current, 256),
    );
  }

  /// Copies the whole list out. Called when `listGeneration` moves, never per
  /// frame — a thousand ~1 KB copies is not a frame budget item.
  List<PluginListing> readPluginList(int count) {
    final List<PluginListing> plugins = <PluginListing>[];
    for (int index = 0; index < count; index++) {
      if (_bindings.ob_engine_plugin_at(_engine, index, _pluginInfo) !=
          ob_status.OB_OK) {
        break; // the list changed under us; the next generation will re-read it
      }
      final ob_plugin_info p = _pluginInfo.ref;
      plugins.add(
        PluginListing(
          id: _readFixedUtf8(p.id, 128),
          name: _readFixedUtf8(p.name, 128),
          vendor: _readFixedUtf8(p.vendor, 128),
          version: _readFixedUtf8(p.version, 32),
          path: _readFixedUtf8(p.path, 512),
          format:
              PluginFormat.values[p.format.clamp(
                0,
                PluginFormat.values.length - 1,
              )],
          outcome:
              ScanOutcome.values[p.outcome.clamp(
                0,
                ScanOutcome.values.length - 1,
              )],
          failurePhase:
              ScanPhase.values[p.failure_phase.clamp(
                0,
                ScanPhase.values.length - 1,
              )],
          failureSignal: p.failure_signal,
          retryCount: p.retry_count,
          introspected: (p.flags & obPluginFlagIntrospected) != 0,
          paramCount: p.param_count,
          audioInputCount: p.audio_input_count,
          audioOutputCount: p.audio_output_count,
          noteInputCount: p.note_input_count,
          noteOutputCount: p.note_output_count,
        ),
      );
    }
    return plugins;
  }

  /// The first usable plug-in for an explicit "add an instrument" action.
  /// Bundled stock instruments are preferred, falling back to any usable
  /// plug-in.
  PluginListing? firstUsablePlugin() {
    final PluginScanStatus status = readPluginScanStatus();
    if (status.pluginCount <= 0) return null;
    PluginListing? fallback;
    for (final PluginListing p in readPluginList(status.pluginCount)) {
      if (!p.isUsable) continue;
      if (p.vendor == 'OneBeat') return p;
      fallback ??= p;
    }
    return fallback;
  }

  HostedInstance? readHostedInstance() {
    if (_bindings.ob_engine_instance_count(_engine) == 0 ||
        _bindings.ob_engine_instance_at(_engine, 0, _instanceInfo) !=
            ob_status.OB_OK) {
      return null;
    }
    final ob_instance_info value = _instanceInfo.ref;
    return HostedInstance(
      id: value.instance_id,
      pluginId: _readFixedUtf8(value.plugin_id, 128),
      name: _readFixedUtf8(value.name, 128),
      vendor: _readFixedUtf8(value.vendor, 128),
      path: _readFixedUtf8(value.path, 512),
      format:
          PluginFormat.values[value.format.clamp(
            0,
            PluginFormat.values.length - 1,
          )],
      missing: (value.flags & 1) != 0,
      hasEditor: (value.flags & 4) != 0,
      needsRestart: (value.flags & 8) != 0,
      paramCount: value.param_count,
    );
  }

  void addPlugin(PluginListing plugin) =>
      addPluginByPath(plugin.path, plugin.id);

  /// Adds a WAV-backed project instrument. The engine keeps the source path in
  /// the instrument reference so the sample survives project save/reopen.
  void addSampleInstrument(String name, String samplePath) {
    final Pointer<Utf8> nativeName = name.toNativeUtf8();
    final Pointer<Utf8> nativePath = samplePath.toNativeUtf8();
    try {
      _check(
        _bindings.ob_engine_instrument_add_sample(
          _engine,
          nativeName.cast<Char>(),
          nativePath.cast<Char>(),
        ),
      );
    } finally {
      calloc.free(nativeName);
      calloc.free(nativePath);
    }
  }

  /// Replaces a rack instrument with a WAV-backed sample instrument.
  void replaceSampleInstrument(
    String instrumentId,
    String name,
    String samplePath,
  ) {
    final Pointer<Utf8> nativeInstrument = instrumentId.toNativeUtf8();
    final Pointer<Utf8> nativeName = name.toNativeUtf8();
    final Pointer<Utf8> nativePath = samplePath.toNativeUtf8();
    try {
      _check(
        _bindings.ob_engine_instrument_replace_sample(
          _engine,
          nativeInstrument.cast<Char>(),
          nativeName.cast<Char>(),
          nativePath.cast<Char>(),
        ),
      );
    } finally {
      calloc.free(nativeInstrument);
      calloc.free(nativeName);
      calloc.free(nativePath);
    }
  }

  /// The same thing addressed by bundle path and plug-in id rather than by a
  /// scanned listing. The browser always has a listing; the integration driver
  /// does not — it points straight at the stock bundle in the build tree so it
  /// does not have to wait on a scan (OB-3-14 §2).
  void addPluginByPath(String bundlePath, String pluginId) {
    final Pointer<Utf8> path = bundlePath.toNativeUtf8();
    final Pointer<Utf8> id = pluginId.toNativeUtf8();
    try {
      _check(
        _bindings.ob_engine_instance_add(
          _engine,
          path.cast<Char>(),
          id.cast<Char>(),
        ),
      );
    } finally {
      calloc.free(path);
      calloc.free(id);
    }
  }

  List<ProjectInstrument> readInstruments() {
    final int count = _bindings.ob_engine_instrument_count(_engine);
    final List<ProjectInstrument> result = <ProjectInstrument>[];
    for (int index = 0; index < count; index++) {
      if (_bindings.ob_engine_instrument_at(_engine, index, _instrumentInfo) !=
          ob_status.OB_OK) {
        break;
      }
      final ob_instrument_info value = _instrumentInfo.ref;
      result.add(
        ProjectInstrument(
          id: _readFixedUtf8(value.id, 32),
          name: _readFixedUtf8(value.name, 128),
          color: _readFixedUtf8(value.color, 8),
          order: value.order,
          pluginId: _readFixedUtf8(value.plugin_id, 128),
          pluginName: _readFixedUtf8(value.plugin_name, 128),
          pluginVendor: _readFixedUtf8(value.plugin_vendor, 128),
          pluginPath: _readFixedUtf8(value.plugin_path, 512),
          muted: (value.flags & 1) != 0,
          selected: (value.flags & 2) != 0,
          affectedPatterns: value.affected_pattern_count,
          affectedClips: value.affected_clip_count,
          affectedNotes: value.affected_note_count,
          gain: value.gain,
          pan: value.pan,
        ),
      );
    }
    return result;
  }

  void selectInstrument(String id) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_select(_engine, native),
  );

  void renameInstrument(String id, String name) => _withTwoNativeStrings(
    id,
    name,
    (Pointer<Char> nativeId, Pointer<Char> nativeName) =>
        _bindings.ob_engine_instrument_rename(_engine, nativeId, nativeName),
  );

  void recolorInstrument(String id, String color) => _withTwoNativeStrings(
    id,
    color,
    (Pointer<Char> nativeId, Pointer<Char> nativeColor) =>
        _bindings.ob_engine_instrument_recolor(_engine, nativeId, nativeColor),
  );

  void setInstrumentMuted(String id, {required bool muted}) =>
      _withNativeString(
        id,
        (Pointer<Char> native) => _bindings.ob_engine_instrument_set_muted(
          _engine,
          native,
          muted ? 1 : 0,
        ),
      );

  void replaceInstrument(String id, PluginListing plugin) {
    final Pointer<Utf8> nativeId = id.toNativeUtf8();
    final Pointer<Utf8> nativePath = plugin.path.toNativeUtf8();
    final Pointer<Utf8> nativePluginId = plugin.id.toNativeUtf8();
    try {
      _check(
        _bindings.ob_engine_instrument_replace(
          _engine,
          nativeId.cast<Char>(),
          nativePath.cast<Char>(),
          nativePluginId.cast<Char>(),
        ),
      );
    } finally {
      calloc.free(nativeId);
      calloc.free(nativePath);
      calloc.free(nativePluginId);
    }
  }

  void reorderInstrument(String id, int order) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_reorder(_engine, native, order),
  );

  void duplicateInstrument(String id) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_duplicate(_engine, native),
  );

  void deleteInstrument(String id) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_remove(_engine, native),
  );

  /// Adds an empty channel (no plug-in) — a blank lane to drop an instrument
  /// into. [name] may be empty for a generated name.
  void addEmptyInstrument(String name) => _withNativeString(
    name,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_add_empty(_engine, native),
  );

  /// Per-channel gain (linear 0..2) applied to the active voice.
  void setInstrumentGain(String id, double gain) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_set_gain(_engine, native, gain),
  );

  /// Per-channel pan (-1..1) applied to the active voice.
  void setInstrumentPan(String id, double pan) => _withNativeString(
    id,
    (Pointer<Char> native) =>
        _bindings.ob_engine_instrument_set_pan(_engine, native, pan),
  );

  @override
  bool get canUndoProject => _bindings.ob_engine_project_can_undo(_engine) != 0;
  @override
  bool get canRedoProject => _bindings.ob_engine_project_can_redo(_engine) != 0;
  @override
  String get undoProjectName =>
      _bindings
          .ob_engine_project_undo_name(_engine)
          .cast<Utf8>()
          .toDartString();
  @override
  String get redoProjectName =>
      _bindings
          .ob_engine_project_redo_name(_engine)
          .cast<Utf8>()
          .toDartString();
  @override
  void undoProject() => _check(_bindings.ob_engine_project_undo(_engine));
  @override
  void redoProject() => _check(_bindings.ob_engine_project_redo(_engine));

  @override
  RackPattern readRackPattern() {
    _check(_bindings.ob_engine_rack_pattern(_engine, _rackPatternInfo));
    final ob_rack_pattern_info value = _rackPatternInfo.ref;
    return RackPattern(
      id: _readFixedUtf8(value.id, 32),
      name: _readFixedUtf8(value.name, 128),
      lengthTicks: value.length_ticks,
      baseGridTicks: value.base_grid_ticks,
      swing: value.swing,
    );
  }

  @override
  List<RackRow> readRackRows() {
    final int count = _bindings.ob_engine_rack_row_count(_engine);
    final List<RackRow> rows = <RackRow>[];
    for (int index = 0; index < count; index++) {
      _check(_bindings.ob_engine_rack_row_at(_engine, index, _rackRowInfo));
      final ob_rack_row_info value = _rackRowInfo.ref;
      rows.add(
        RackRow(
          instrumentId: _readFixedUtf8(value.instrument_id, 32),
          gridTicks: value.grid_ticks,
          hasSequence: (value.flags & 1) != 0,
          offGridCount: value.off_grid_count,
          noteCount: value.note_count,
          steps: List<RackStep>.generate(
            value.step_count,
            (int step) => RackStep(
              active: value.step_active[step] != 0,
              velocity: value.step_velocity[step],
            ),
            growable: false,
          ),
        ),
      );
    }
    return rows;
  }

  @override
  void setRackRowGrid(String instrumentId, int gridTicks) => _withNativeString(
    instrumentId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_rack_set_row_grid(_engine, native, gridTicks),
  );

  @override
  void setRackLength(int steps) =>
      _check(_bindings.ob_engine_rack_set_length(_engine, steps));

  @override
  void setRackSwing(double swing) =>
      _check(_bindings.ob_engine_rack_set_swing(_engine, swing));

  @override
  void toggleRackStep(String instrumentId, int step) => _withNativeString(
    instrumentId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_rack_toggle_step(_engine, native, step),
  );

  @override
  void setRackStepVelocity(String instrumentId, int step, int velocity) =>
      _withNativeString(
        instrumentId,
        (Pointer<Char> native) => _bindings.ob_engine_rack_set_step_velocity(
          _engine,
          native,
          step,
          velocity,
        ),
      );

  @override
  void removeRackSequence(String instrumentId) => _withNativeString(
    instrumentId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_rack_remove_sequence(_engine, native),
  );

  @override
  void beginRackGesture(String name) => _withNativeString(
    name,
    (Pointer<Char> native) =>
        _bindings.ob_engine_rack_gesture_begin(_engine, native),
  );

  @override
  void commitRackGesture() =>
      _check(_bindings.ob_engine_rack_gesture_commit(_engine));

  @override
  void abortRackGesture() =>
      _check(_bindings.ob_engine_rack_gesture_abort(_engine));

  // --- notes: the piano roll (OB-3-10) --------------------------------------

  @override
  List<SequenceNote> readNotes(String instrumentId) {
    final Pointer<Utf8> native = instrumentId.toNativeUtf8();
    try {
      final Pointer<Char> id = native.cast<Char>();
      final int count = _bindings.ob_engine_note_count(_engine, id);
      if (count <= 0) return const <SequenceNote>[];
      final Pointer<ob_note> buffer = _ensureNoteCapacity(count);
      _check(
        _bindings.ob_engine_notes_read(
          _engine,
          id,
          buffer,
          _noteCapacity,
          _noteCount,
        ),
      );
      final int written = _noteCount.value;
      return List<SequenceNote>.generate(written, (int index) {
        final ob_note note = buffer[index];
        return SequenceNote(
          startTicks: note.start,
          lengthTicks: note.length,
          key: note.key,
          velocity: note.velocity,
        );
      }, growable: false);
    } finally {
      calloc.free(native);
    }
  }

  /// Writes `notes` into the shared buffer and runs `call` against it. Every
  /// note mutation has the same shape — an instrument, an array, a count — so
  /// the marshalling lives here once.
  void _withNotes(
    String instrumentId,
    List<SequenceNote> notes,
    ob_status Function(Pointer<Char>, Pointer<ob_note>, int) call,
  ) {
    if (notes.isEmpty) return;
    final Pointer<ob_note> buffer = _ensureNoteCapacity(notes.length);
    for (int index = 0; index < notes.length; index++) {
      final SequenceNote note = notes[index];
      buffer[index].start = note.startTicks;
      buffer[index].length = note.lengthTicks;
      buffer[index].key = note.key;
      buffer[index].velocity = note.velocity;
    }
    _withNativeString(
      instrumentId,
      (Pointer<Char> native) => call(native, buffer, notes.length),
    );
  }

  @override
  void addNote(
    String instrumentId,
    int startTicks,
    int lengthTicks,
    int key, {
    int velocity = 0,
  }) => _withNativeString(
    instrumentId,
    (Pointer<Char> native) => _bindings.ob_engine_note_add(
      _engine,
      native,
      startTicks,
      lengthTicks,
      key,
      velocity,
    ),
  );

  @override
  void removeNotes(String instrumentId, List<SequenceNote> notes) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) =>
        _bindings.ob_engine_notes_remove(_engine, id, buffer, count),
  );

  @override
  void moveNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    int deltaTicks = 0,
    int semitones = 0,
    int snapTicks = 0,
  }) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) =>
        _bindings.ob_engine_notes_move(
          _engine,
          id,
          buffer,
          count,
          deltaTicks,
          semitones,
          snapTicks,
        ),
  );

  @override
  void resizeNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int lengthDelta,
    int snapTicks = 0,
  }) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) =>
        _bindings.ob_engine_notes_resize(
          _engine,
          id,
          buffer,
          count,
          lengthDelta,
          snapTicks,
        ),
  );

  @override
  void setNoteVelocity(
    String instrumentId,
    List<SequenceNote> notes,
    int velocity,
  ) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) => _bindings
        .ob_engine_notes_set_velocity(_engine, id, buffer, count, velocity),
  );

  @override
  void quantiseNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int gridTicks,
    required double strength,
  }) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) =>
        _bindings.ob_engine_notes_quantise(
          _engine,
          id,
          buffer,
          count,
          gridTicks,
          strength,
        ),
  );

  @override
  void duplicateNotes(
    String instrumentId,
    List<SequenceNote> notes, {
    required int deltaTicks,
  }) => _withNotes(
    instrumentId,
    notes,
    (Pointer<Char> id, Pointer<ob_note> buffer, int count) => _bindings
        .ob_engine_notes_duplicate(_engine, id, buffer, count, deltaTicks),
  );

  @override
  void auditionNoteOn(int key, double velocity) =>
      noteOn(key, velocity.clamp(0.0, 1.0));

  @override
  void auditionNoteOff(int key) => noteOff(key);

  /// Auditions the sample-preview slot rather than the selected rack channel.
  void previewNoteOn(int key, double velocity) =>
      _post(cmdPreviewNoteOn, i64: key, f64a: velocity.clamp(0.0, 1.0));

  void previewNoteOff(int key) => _post(cmdPreviewNoteOff, i64: key);

  // The rack's transaction calls under their general name: natively there is
  // one gesture mechanism and both editors use it.
  @override
  void beginGesture(String name) => beginRackGesture(name);

  @override
  void commitGesture() => commitRackGesture();

  @override
  void abortGesture() => abortRackGesture();

  // --- patterns (OB-3-11) ----------------------------------------------------

  @override
  List<PatternSummary> readPatterns() {
    final int count = _bindings.ob_engine_pattern_count(_engine);
    final List<PatternSummary> patterns = <PatternSummary>[];
    for (int index = 0; index < count; index++) {
      _check(_bindings.ob_engine_pattern_at(_engine, index, _patternInfo));
      final ob_pattern_info value = _patternInfo.ref;
      patterns.add(
        PatternSummary(
          id: _readFixedUtf8(value.id, 32),
          name: _readFixedUtf8(value.name, 128),
          color: _readFixedUtf8(value.color, 8),
          lengthTicks: value.length_ticks,
          swing: value.swing,
          usageCount: value.usage_count,
          noteCount: value.note_count,
          isCurrent: (value.flags & patternFlagCurrent) != 0,
        ),
      );
    }
    return patterns;
  }

  @override
  void selectPattern(String patternId) => _withNativeString(
    patternId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_pattern_select(_engine, native),
  );

  @override
  void createPattern(String name) => _withNativeString(
    name,
    (Pointer<Char> native) =>
        _bindings.ob_engine_pattern_create(_engine, native),
  );

  @override
  void renamePattern(String patternId, String name) => _withTwoNativeStrings(
    patternId,
    name,
    (Pointer<Char> id, Pointer<Char> value) =>
        _bindings.ob_engine_pattern_rename(_engine, id, value),
  );

  @override
  void recolorPattern(String patternId, String color) => _withTwoNativeStrings(
    patternId,
    color,
    (Pointer<Char> id, Pointer<Char> value) =>
        _bindings.ob_engine_pattern_recolor(_engine, id, value),
  );

  @override
  void duplicatePattern(String patternId) => _withNativeString(
    patternId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_pattern_duplicate(_engine, native),
  );

  @override
  void removePattern(String patternId) => _withNativeString(
    patternId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_pattern_remove(_engine, native),
  );

  @override
  void makeClipsUnique(List<String> clipIds) {
    if (clipIds.isEmpty) return;
    // NUL-separated, double-NUL-terminated: the shape the ABI takes so that a
    // multi-selection crosses the boundary as one string rather than an array
    // of pointers whose lifetimes Dart would have to own.
    // Dart source cannot carry a raw NUL, so the separator is escaped.
    const String nul = '\u0000';
    final String packed = '${clipIds.join(nul)}$nul$nul';
    _withNativeString(
      packed,
      (Pointer<Char> native) =>
          _bindings.ob_engine_clips_make_unique(_engine, native),
    );
  }

  // --- arrangement (OB-3-12, OB-3-13) ---------------------------------------

  @override
  List<ArrangementLane> readLanes() {
    final int count = _bindings.ob_engine_lane_count(_engine);
    final List<ArrangementLane> lanes = <ArrangementLane>[];
    for (int index = 0; index < count; index++) {
      _check(_bindings.ob_engine_lane_at(_engine, index, _laneInfo));
      final ob_lane_info value = _laneInfo.ref;
      lanes.add(
        ArrangementLane(
          id: _readFixedUtf8(value.id, 32),
          name: _readFixedUtf8(value.name, 128),
          color: _readFixedUtf8(value.color, 8),
          order: value.order,
          height: value.height,
          clipCount: value.clip_count,
          muted: (value.flags & laneFlagMuted) != 0,
          soloed: (value.flags & laneFlagSoloed) != 0,
          collapsed: (value.flags & laneFlagCollapsed) != 0,
        ),
      );
    }
    return lanes;
  }

  @override
  void createLane(String name) => _withNativeString(
    name,
    (Pointer<Char> native) => _bindings.ob_engine_lane_create(_engine, native),
  );

  @override
  void renameLane(String laneId, String name) => _withTwoNativeStrings(
    laneId,
    name,
    (Pointer<Char> id, Pointer<Char> value) =>
        _bindings.ob_engine_lane_rename(_engine, id, value),
  );

  @override
  void recolorLane(String laneId, String color) => _withTwoNativeStrings(
    laneId,
    color,
    (Pointer<Char> id, Pointer<Char> value) =>
        _bindings.ob_engine_lane_recolor(_engine, id, value),
  );

  @override
  void reorderLane(String laneId, int order) => _withNativeString(
    laneId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_lane_reorder(_engine, native, order),
  );

  @override
  void setLaneHeight(String laneId, int height) => _withNativeString(
    laneId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_lane_set_height(_engine, native, height),
  );

  @override
  void setLaneMuted(String laneId, {required bool muted}) => _withNativeString(
    laneId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_lane_set_muted(_engine, native, muted ? 1 : 0),
  );

  @override
  void setLaneSoloed(String laneId, {required bool soloed}) =>
      _withNativeString(
        laneId,
        (Pointer<Char> native) => _bindings.ob_engine_lane_set_soloed(
          _engine,
          native,
          soloed ? 1 : 0,
        ),
      );

  @override
  void setLaneCollapsed(String laneId, {required bool collapsed}) =>
      _withNativeString(
        laneId,
        (Pointer<Char> native) => _bindings.ob_engine_lane_set_collapsed(
          _engine,
          native,
          collapsed ? 1 : 0,
        ),
      );

  @override
  void removeLane(String laneId) => _withNativeString(
    laneId,
    (Pointer<Char> native) => _bindings.ob_engine_lane_remove(_engine, native),
  );

  @override
  List<ArrangementClip> readClips() {
    final int count = _bindings.ob_engine_clip_count(_engine);
    final List<ArrangementClip> clips = <ArrangementClip>[];
    for (int index = 0; index < count; index++) {
      _check(_bindings.ob_engine_clip_at(_engine, index, _clipInfo));
      final ob_clip_info value = _clipInfo.ref;
      clips.add(
        ArrangementClip(
          id: _readFixedUtf8(value.id, 32),
          laneId: _readFixedUtf8(value.lane_id, 32),
          patternId: _readFixedUtf8(value.pattern_id, 32),
          name: _readFixedUtf8(value.name, 128),
          color: _readFixedUtf8(value.color, 8),
          audioPath: _readFixedUtf8(value.audio_path, 512),
          startTicks: value.start_ticks,
          lengthTicks: value.length_ticks,
          windowStartTicks: value.window_start_ticks,
          patternLengthTicks: value.pattern_length_ticks,
          transpose: value.transpose,
          noteCount: value.note_count,
          usageCount: value.usage_count,
          muted: (value.flags & clipFlagMuted) != 0,
          loop: (value.flags & clipFlagLoop) != 0,
          isAudio: (value.flags & clipFlagAudio) != 0,
        ),
      );
    }
    return clips;
  }

  @override
  void addClip(
    String laneId, {
    String patternId = '',
    required int startTicks,
    required int lengthTicks,
  }) => _withTwoNativeStrings(
    laneId,
    patternId,
    (Pointer<Char> lane, Pointer<Char> pattern) => _bindings.ob_engine_clip_add(
      _engine,
      lane,
      pattern,
      startTicks,
      lengthTicks,
    ),
  );

  @override
  void moveClip(String clipId, {String laneId = '', required int startTicks}) =>
      _withTwoNativeStrings(
        clipId,
        laneId,
        (Pointer<Char> clip, Pointer<Char> lane) =>
            _bindings.ob_engine_clip_move(_engine, clip, lane, startTicks),
      );

  @override
  void resizeClip(String clipId, int lengthTicks) => _withNativeString(
    clipId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_clip_resize(_engine, native, lengthTicks),
  );

  @override
  void duplicateClip(
    String clipId, {
    String laneId = '',
    required int startTicks,
  }) => _withTwoNativeStrings(
    clipId,
    laneId,
    (Pointer<Char> clip, Pointer<Char> lane) =>
        _bindings.ob_engine_clip_duplicate(_engine, clip, lane, startTicks),
  );

  @override
  void removeClip(String clipId) => _withNativeString(
    clipId,
    (Pointer<Char> native) => _bindings.ob_engine_clip_remove(_engine, native),
  );

  @override
  void setClipMuted(String clipId, {required bool muted}) => _withNativeString(
    clipId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_clip_set_muted(_engine, native, muted ? 1 : 0),
  );

  @override
  void setClipLoop(String clipId, {required bool loop}) => _withNativeString(
    clipId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_clip_set_loop(_engine, native, loop ? 1 : 0),
  );

  @override
  void setClipWindowStart(String clipId, int windowStartTicks) =>
      _withNativeString(
        clipId,
        (Pointer<Char> native) => _bindings.ob_engine_clip_set_window_start(
          _engine,
          native,
          windowStartTicks,
        ),
      );

  @override
  void setClipTranspose(String clipId, int semitones) => _withNativeString(
    clipId,
    (Pointer<Char> native) =>
        _bindings.ob_engine_clip_set_transpose(_engine, native, semitones),
  );

  // --- project files (OB-3-05's writer, reachable from the UI) --------------

  /// Writes the project bundle. Distinct from [saveSession], which is the v0.2
  /// scratch file holding one hosted plug-in's opaque chunk.
  @override
  void saveProject(String path) => _withNativeString(
    path,
    (Pointer<Char> native) => _bindings.ob_engine_project_save(_engine, native),
  );

  /// Replaces the whole project. On failure the open project is untouched, so
  /// an unreadable file costs nothing but the attempt.
  @override
  void openProject(String path) => _withNativeString(
    path,
    (Pointer<Char> native) => _bindings.ob_engine_project_open(_engine, native),
  );

  @override
  String get projectPath =>
      _bindings.ob_engine_project_path(_engine).cast<Utf8>().toDartString();

  @override
  String get projectName =>
      _bindings.ob_engine_project_name(_engine).cast<Utf8>().toDartString();

  @override
  void setProjectName(String name) => _withNativeString(
    name,
    (Pointer<Char> native) =>
        _bindings.ob_engine_project_set_name(_engine, native),
  );

  @override
  bool get isProjectModified =>
      _bindings.ob_engine_project_is_modified(_engine) != 0;

  /// The canonical `project.json` bytes as the project stands. Byte-identical
  /// for a given model on any machine, which is what makes it usable as a
  /// save/reopen equality check (docs/project-format.md §6).
  String get projectJson =>
      _bindings.ob_engine_project_json(_engine).cast<Utf8>().toDartString();

  void _withNativeString(String value, ob_status Function(Pointer<Char>) call) {
    final Pointer<Utf8> native = value.toNativeUtf8();
    try {
      _check(call(native.cast<Char>()));
    } finally {
      calloc.free(native);
    }
  }

  void _withTwoNativeStrings(
    String first,
    String second,
    ob_status Function(Pointer<Char>, Pointer<Char>) call,
  ) {
    final Pointer<Utf8> nativeFirst = first.toNativeUtf8();
    final Pointer<Utf8> nativeSecond = second.toNativeUtf8();
    try {
      _check(call(nativeFirst.cast<Char>(), nativeSecond.cast<Char>()));
    } finally {
      calloc.free(nativeFirst);
      calloc.free(nativeSecond);
    }
  }

  void removePlugin(int instanceId) =>
      _check(_bindings.ob_engine_instance_remove(_engine, instanceId));

  void openPluginEditor(int instanceId) =>
      _check(_bindings.ob_engine_instance_editor_open(_engine, instanceId));

  void restartPlugin(int instanceId) =>
      _check(_bindings.ob_engine_instance_restart(_engine, instanceId));

  List<HostedParameter> readParameters(HostedInstance instance) {
    final List<HostedParameter> result = <HostedParameter>[];
    for (int index = 0; index < instance.paramCount; index++) {
      if (_bindings.ob_engine_param_at(
            _engine,
            instance.id,
            index,
            _paramInfo,
          ) !=
          ob_status.OB_OK) {
        break;
      }
      final ob_param_info value = _paramInfo.ref;
      result.add(
        HostedParameter(
          id: value.param_id,
          name: _readFixedUtf8(value.name, 128),
          module: _readFixedUtf8(value.module, 128),
          display: _readFixedUtf8(value.display, 128),
          value: value.value,
          minimum: value.min_value,
          maximum: value.max_value,
          defaultValue: value.default_value,
        ),
      );
    }
    return result;
  }

  void beginParameterGesture(int paramId) =>
      _post(cmdPluginParamBegin, i64: paramId);
  void setParameter(int paramId, double value) =>
      _post(cmdPluginParamValue, i64: paramId, f64a: value);
  void endParameterGesture(int paramId) =>
      _post(cmdPluginParamEnd, i64: paramId);

  void _check(ob_status status) {
    if (status != ob_status.OB_OK) {
      throw EngineException(
        _bindings.ob_last_error_message().cast<Utf8>().toDartString(),
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _bindings.ob_engine_stop(_engine);
    _bindings.ob_engine_destroy(_engine);
    calloc.free(_snapshot);
    calloc.free(_command);
    calloc.free(_event);
    calloc.free(_scanStatus);
    calloc.free(_pluginInfo);
    calloc.free(_instanceInfo);
    calloc.free(_instrumentInfo);
    calloc.free(_rackPatternInfo);
    calloc.free(_rackRowInfo);
    calloc.free(_patternInfo);
    calloc.free(_laneInfo);
    calloc.free(_clipInfo);
    calloc.free(_noteCount);
    calloc.free(_paramInfo);
    if (_noteBuffer != nullptr) calloc.free(_noteBuffer);
  }
}

/// Audio clips are deliberately an additive capability rather than part of the
/// pattern-placement API. Keeping this as an extension means test doubles that
/// implement [EngineClient] do not need native audio plumbing just to test the
/// pattern editor.
extension AudioClipEngineClient on EngineClient {
  void addAudioClip(String laneId, String samplePath, int startTicks) =>
      _withTwoNativeStrings(
        laneId,
        samplePath,
        (Pointer<Char> nativeLane, Pointer<Char> nativePath) =>
            _bindings.ob_engine_audio_clip_add(
              _engine,
              nativeLane,
              nativePath,
              startTicks,
            ),
      );
}

/// Mirrors `ob_scan_state`.
enum ScanState { idle, discovering, probing, complete, cancelled }

/// Mirrors `ob_plugin_format`.
enum PluginFormat { unknown, builtin, clap, vst3, audioUnit }

/// Mirrors `ob_scan_outcome`. Everything but [ok] is a plug-in the user cannot
/// use, and each one gets different copy (FR-UX-12) — which is why they are not
/// collapsed into a single "failed".
enum ScanOutcome { ok, notAPlugin, crashed, timedOut }

/// Mirrors `ob_scan_phase`.
enum ScanPhase { none, spawn, load, enumerate, instantiate, done }

const int obPluginFlagIntrospected = 0x1;

class PluginScanStatus {
  const PluginScanStatus({
    required this.state,
    required this.bundlesDiscovered,
    required this.bundlesReused,
    required this.bundlesProbed,
    required this.pluginsFound,
    required this.pluginCount,
    required this.listGeneration,
    required this.current,
  });

  const PluginScanStatus.idle()
    : state = ScanState.idle,
      bundlesDiscovered = 0,
      bundlesReused = 0,
      bundlesProbed = 0,
      pluginsFound = 0,
      pluginCount = 0,
      listGeneration = 0,
      current = '';

  final ScanState state;
  final int bundlesDiscovered;
  final int bundlesReused;
  final int bundlesProbed;
  final int pluginsFound;
  final int pluginCount;
  final int listGeneration;

  /// The bundle being opened right now, for the progress line. Empty unless the
  /// scan is in [ScanState.probing].
  final String current;

  bool get isScanning =>
      state == ScanState.discovering || state == ScanState.probing;
}

/// One row of the plug-in list, as the UI sees it.
class PluginListing {
  const PluginListing({
    required this.id,
    required this.name,
    required this.vendor,
    required this.version,
    required this.path,
    required this.format,
    required this.outcome,
    required this.failurePhase,
    required this.failureSignal,
    required this.retryCount,
    required this.introspected,
    required this.paramCount,
    required this.audioInputCount,
    required this.audioOutputCount,
    required this.noteInputCount,
    required this.noteOutputCount,
  });

  final String id;
  final String name;
  final String vendor;
  final String version;
  final String path;
  final PluginFormat format;
  final ScanOutcome outcome;
  final ScanPhase failurePhase;
  final int failureSignal;
  final int retryCount;

  /// False until something has actually opened the plug-in. While it is false,
  /// [vendor], [version], [paramCount] and the port counts are placeholders and
  /// must not be shown as facts (OB-2-07 sets it).
  final bool introspected;

  final int paramCount;
  final int audioInputCount;
  final int audioOutputCount;
  final int noteInputCount;
  final int noteOutputCount;

  bool get isUsable => outcome == ScanOutcome.ok;
  bool get isQuarantined =>
      outcome == ScanOutcome.crashed || outcome == ScanOutcome.timedOut;
}

class HostedInstance {
  const HostedInstance({
    required this.id,
    required this.pluginId,
    required this.name,
    required this.vendor,
    required this.path,
    required this.format,
    required this.missing,
    required this.hasEditor,
    required this.needsRestart,
    required this.paramCount,
  });
  final int id;
  final String pluginId;
  final String name;
  final String vendor;
  final String path;
  final PluginFormat format;
  final bool missing;
  final bool hasEditor;
  final bool needsRestart;
  final int paramCount;
}

class ProjectInstrument {
  const ProjectInstrument({
    required this.id,
    required this.name,
    required this.color,
    required this.order,
    required this.pluginId,
    required this.pluginName,
    required this.pluginVendor,
    required this.pluginPath,
    required this.muted,
    required this.selected,
    required this.affectedPatterns,
    required this.affectedClips,
    required this.affectedNotes,
    this.gain = 1.0,
    this.pan = 0.0,
  });

  final String id;
  final String name;
  final String color;
  final int order;
  final String pluginId;
  final String pluginName;
  final String pluginVendor;
  final String pluginPath;
  final bool muted;
  final bool selected;
  final int affectedPatterns;
  final int affectedClips;
  final int affectedNotes;

  /// Channel gain (linear 0..2) and pan (-1..1): the rack's VOL/PAN knobs.
  final double gain;
  final double pan;
}

class RackPattern {
  const RackPattern({
    required this.id,
    required this.name,
    required this.lengthTicks,
    required this.baseGridTicks,
    required this.swing,
  });

  final String id;
  final String name;
  final int lengthTicks;
  final int baseGridTicks;
  final double swing;

  int get baseStepCount => (lengthTicks / baseGridTicks).ceil();
}

class RackStep {
  const RackStep({required this.active, required this.velocity});
  final bool active;
  final int velocity;
}

class RackRow {
  const RackRow({
    required this.instrumentId,
    required this.gridTicks,
    required this.hasSequence,
    required this.offGridCount,
    required this.noteCount,
    required this.steps,
  });

  final String instrumentId;
  final int gridTicks;
  final bool hasSequence;
  final int offGridCount;
  final int noteCount;
  final List<RackStep> steps;
}

/// One note, in pattern-relative ticks. Value-equal notes are the same note as
/// far as every edit is concerned, which is why equality and hashing are
/// defined: the piano roll's selection is a `Set<SequenceNote>`.
@immutable
class SequenceNote {
  const SequenceNote({
    required this.startTicks,
    required this.lengthTicks,
    required this.key,
    required this.velocity,
  });

  final int startTicks;
  final int lengthTicks;
  final int key;
  final int velocity;

  int get endTicks => startTicks + lengthTicks;

  SequenceNote copyWith({
    int? startTicks,
    int? lengthTicks,
    int? key,
    int? velocity,
  }) => SequenceNote(
    startTicks: startTicks ?? this.startTicks,
    lengthTicks: lengthTicks ?? this.lengthTicks,
    key: key ?? this.key,
    velocity: velocity ?? this.velocity,
  );

  @override
  bool operator ==(Object other) =>
      other is SequenceNote &&
      other.startTicks == startTicks &&
      other.lengthTicks == lengthTicks &&
      other.key == key &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(startTicks, lengthTicks, key, velocity);
}

class PatternSummary {
  const PatternSummary({
    required this.id,
    required this.name,
    required this.color,
    required this.lengthTicks,
    required this.swing,
    required this.usageCount,
    required this.noteCount,
    required this.isCurrent,
  });

  final String id;
  final String name;
  final String color;
  final int lengthTicks;
  final double swing;

  /// Clips referencing this pattern. Editing it changes all of them, which is
  /// what the selector's badge and D-M6's notice are warning about.
  final int usageCount;
  final int noteCount;
  final bool isCurrent;

  bool get isShared => usageCount > 1;
}

class ArrangementLane {
  const ArrangementLane({
    required this.id,
    required this.name,
    required this.color,
    required this.order,
    required this.height,
    required this.clipCount,
    required this.muted,
    required this.soloed,
    required this.collapsed,
  });

  final String id;
  final String name;
  final String color;
  final int order;
  final int height;
  final int clipCount;

  /// An *event* gate (D-M4): clips on a muted lane are not scheduled at all.
  /// This is not the mixer's audio mute and the UI must not name it the same.
  final bool muted;
  final bool soloed;
  final bool collapsed;
}

class ArrangementClip {
  const ArrangementClip({
    required this.id,
    required this.laneId,
    required this.patternId,
    required this.name,
    required this.color,
    required this.startTicks,
    required this.lengthTicks,
    required this.windowStartTicks,
    required this.patternLengthTicks,
    required this.transpose,
    required this.noteCount,
    required this.usageCount,
    required this.muted,
    required this.loop,
    this.isAudio = false,
    this.audioPath = '',
  });

  final String id;
  final String laneId;

  /// Empty for audio and automation clips. Audio clips set [isAudio] and use
  /// [name] for the source file's display name.
  final String patternId;

  /// The pattern's name and colour, or the audio source's file name and colour.
  /// Pattern clips have no independent name, so renaming a pattern renames every
  /// placement at once.
  final String name;
  final String color;

  final int startTicks;
  final int lengthTicks;
  final int windowStartTicks;
  final int patternLengthTicks;
  final int transpose;
  final int noteCount;
  final int usageCount;
  final bool muted;
  final bool loop;
  final bool isAudio;
  final String audioPath;

  int get endTicks => startTicks + lengthTicks;
  bool get isPattern => !isAudio && patternId.isNotEmpty;
  bool get isShared => usageCount > 1;

  /// How many times the source pattern repeats inside the clip. Used to draw
  /// the loop boundaries on the clip face (OB-3-13 §1).
  int get repeatCount {
    if (!loop || patternLengthTicks <= 0) return 1;
    return (lengthTicks / patternLengthTicks).ceil();
  }
}

class HostedParameter {
  const HostedParameter({
    required this.id,
    required this.name,
    required this.module,
    required this.display,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.defaultValue,
  });
  final int id;
  final String name;
  final String module;
  final String display;
  final double value;
  final double minimum;
  final double maximum;
  final double defaultValue;
}

/// Command type constants, mirroring ob_command_type. ffigen renders the C enum
/// as a Dart enum; these ints keep the call sites readable and are pinned by the
/// ABI freeze test on the C side.
const int cmdTransportPlay = 1;
const int cmdTransportStop = 2;
const int cmdTransportSeekFrames = 3;
const int cmdTransportSeekBeats = 4;
const int cmdSetTempo = 5;
const int cmdSetLoop = 6;
const int cmdNoteOn = 7;
const int cmdNoteOff = 8;
const int cmdPreviewNoteOn = 16;
const int cmdPreviewNoteOff = 17;
const int cmdAllNotesOff = 9;
const int cmdSetMasterGain = 10;
const int cmdPluginParamBegin = 11;
const int cmdPluginParamValue = 12;
const int cmdPluginParamEnd = 13;

/// Flag bits from the ABI 1.9 structs. Mirrored rather than generated because
/// ffigen renders `#define`s inconsistently; the C side freezes them.
const int patternFlagCurrent = 0x1;
const int laneFlagMuted = 0x1;
const int laneFlagSoloed = 0x2;
const int laneFlagCollapsed = 0x4;
const int clipFlagMuted = 0x1;
const int clipFlagLoop = 0x2;
const int clipFlagAudio = 0x4;

const int evtDeviceChanged = 1;
const int evtDeviceLost = 2;
const int evtError = 3;
const int evtSampleLoaded = 4;
const int evtXrun = 5;
const int evtSchedulePublished = 6;

/// True when running somewhere that has no audio hardware (CI).
bool get isHeadlessEnvironment => Platform.environment['OB_HEADLESS'] == '1';
