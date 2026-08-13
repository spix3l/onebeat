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

class EngineClient {
  EngineClient._(this._bindings, this._engine)
    : _snapshot = calloc<ob_snapshot>(),
      _command = calloc<ob_command>(),
      _event = calloc<ob_event>(),
      _scanStatus = calloc<ob_plugin_scan_status>(),
      _pluginInfo = calloc<ob_plugin_info>(),
      _instanceInfo = calloc<ob_instance_info>(),
      _instrumentInfo = calloc<ob_instrument_info>(),
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
  final Pointer<ob_param_info> _paramInfo;

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

  void addPlugin(PluginListing plugin) {
    final Pointer<Utf8> path = plugin.path.toNativeUtf8();
    final Pointer<Utf8> id = plugin.id.toNativeUtf8();
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

  bool get canUndoProject => _bindings.ob_engine_project_can_undo(_engine) != 0;
  bool get canRedoProject => _bindings.ob_engine_project_can_redo(_engine) != 0;
  void undoProject() => _check(_bindings.ob_engine_project_undo(_engine));
  void redoProject() => _check(_bindings.ob_engine_project_redo(_engine));

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
    calloc.free(_paramInfo);
  }
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
const int cmdAllNotesOff = 9;
const int cmdSetMasterGain = 10;
const int cmdPluginParamBegin = 11;
const int cmdPluginParamValue = 12;
const int cmdPluginParamEnd = 13;

const int evtDeviceChanged = 1;
const int evtDeviceLost = 2;
const int evtError = 3;
const int evtSampleLoaded = 4;
const int evtXrun = 5;
const int evtSchedulePublished = 6;

/// True when running somewhere that has no audio hardware (CI).
bool get isHeadlessEnvironment => Platform.environment['OB_HEADLESS'] == '1';
