/*
 * onebeat_abi.h — the OneBeat engine's public C ABI.
 *
 * This header is the single source of truth for the Dart <-> C++ boundary and is
 * the *only* supported way to talk to the engine. Dart bindings are generated
 * from this file by ffigen; hand-written bindings are forbidden (ADR-002 §1).
 *
 * Shape of the contract (NFR-10): commands in, snapshots out.
 *   - The UI never blocks on, allocates on, or polls the audio thread.
 *   - UI -> engine traffic goes through a lock-free SPSC command queue
 *     (ob_engine_post_command), fire-and-forget.
 *   - engine -> UI *frame-rate* state is a fixed-layout snapshot struct read
 *     through a seqlock (ob_engine_read_snapshot) into caller-owned memory.
 *   - engine -> UI *occasional* notifications (device changes, errors) go
 *     through a lock-free queue drained with ob_engine_poll_event.
 *
 * Every function below documents which thread it may be called from and whether
 * it may block. Debug builds assert the threading contract.
 *
 * Rationale, alternatives and the ABI change checklist: docs/adr/ADR-002-ffi-contract.md
 * This header must compile as C: `clang -x c -std=c11 -fsyntax-only`.
 */
#ifndef ONEBEAT_ABI_H
#define ONEBEAT_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define OB_API __declspec(dllexport)
#else
#define OB_API __attribute__((visibility("default")))
#endif

/* ------------------------------------------------------------------------- */
/* Versioning (ADR-002 §1)                                                    */
/* ------------------------------------------------------------------------- */

#define OB_ABI_VERSION_MAJOR 1
#define OB_ABI_VERSION_MINOR 18
#define OB_ABI_VERSION_PATCH 0

/* Packed as (major << 16) | (minor << 8) | patch. */
#define OB_ABI_VERSION_PACKED \
  ((OB_ABI_VERSION_MAJOR << 16) | (OB_ABI_VERSION_MINOR << 8) | OB_ABI_VERSION_PATCH)

/* Any thread. Never blocks. Callable before ob_engine_create.
 * The client MUST refuse to run against a different major version. */
OB_API uint32_t ob_abi_version(void);

/* Any thread. Never blocks. Static storage, caller must not free. */
OB_API const char* ob_abi_version_string(void);

/* ------------------------------------------------------------------------- */
/* Status codes and errors (ADR-002 §2, error taxonomy: docs/errors.md)        */
/* ------------------------------------------------------------------------- */

typedef enum ob_status {
  OB_OK = 0,
  OB_ERR_INVALID_ARGUMENT = 1,
  OB_ERR_OUT_OF_MEMORY = 2,
  OB_ERR_DEVICE_UNAVAILABLE = 3,
  OB_ERR_DEVICE_FORMAT_UNSUPPORTED = 4,
  OB_ERR_ALREADY_RUNNING = 5,
  OB_ERR_NOT_RUNNING = 6,
  OB_ERR_QUEUE_FULL = 7,
  OB_ERR_FILE_NOT_FOUND = 8,
  OB_ERR_FILE_UNSUPPORTED = 9,
  OB_ERR_INTERNAL = 10
} ob_status;

/* Any thread. Never blocks. Returns the message for the last failing call *on
 * the calling thread* (thread-local). Valid until the next failing call on that
 * thread. Caller must not free. Never NULL. Exceptions never cross this
 * boundary — every entry point is noexcept internally. */
OB_API const char* ob_last_error_message(void);

/* Any thread. Never blocks. Stable English identifier for a status code, for
 * logs and for the UI's error-copy lookup table. */
OB_API const char* ob_status_name(ob_status status);

/* ------------------------------------------------------------------------- */
/* Engine lifecycle (ADR-002 §2)                                              */
/* ------------------------------------------------------------------------- */

typedef struct ob_engine ob_engine;

typedef struct ob_engine_config {
  uint32_t struct_size;      /* = sizeof(ob_engine_config); additive evolution */
  double sample_rate;        /* 0 => device default, else 44100..96000 */
  int32_t block_frames;      /* 0 => 512; else 64..2048, device may grant other */
  int32_t use_null_device;   /* 1 => headless null backend (tests, CI) */
  const char* log_directory; /* UTF-8, may be NULL => platform app-support dir.
                              * Also where the plug-in scan cache is written, so
                              * that pointing this at a scratch directory keeps
                              * everything the engine writes together. */
} ob_engine_config;

/* Main/UI thread only. May block (opens the audio device). Writes *out_engine
 * on OB_OK, leaves it untouched otherwise. */
OB_API ob_status ob_engine_create(const ob_engine_config* config, ob_engine** out_engine);

/* Main/UI thread only. May block (stops and closes the device, joins workers).
 * Safe with NULL. After this call the handle is dangling. */
OB_API void ob_engine_destroy(ob_engine* engine);

/* Main/UI thread only. May block. Starts the audio device callback. */
OB_API ob_status ob_engine_start(ob_engine* engine);

/* Main/UI thread only. May block. Stops the audio device callback. */
OB_API ob_status ob_engine_stop(ob_engine* engine);

/* ------------------------------------------------------------------------- */
/* Command channel: UI -> engine (ADR-002 §3)                                 */
/* ------------------------------------------------------------------------- */

typedef enum ob_command_type {
  OB_CMD_NONE = 0,
  OB_CMD_TRANSPORT_PLAY = 1,        /* -- */
  OB_CMD_TRANSPORT_STOP = 2,        /* -- */
  OB_CMD_TRANSPORT_SEEK_FRAMES = 3, /* i64_a = frames */
  OB_CMD_TRANSPORT_SEEK_BEATS = 4,  /* f64_a = beats */
  OB_CMD_SET_TEMPO = 5,             /* f64_a = bpm, 20..999 */
  OB_CMD_SET_LOOP = 6,              /* f64_a = start beats, f64_b = end beats,
                                       i64_a = 0 off / 1 on */
  OB_CMD_NOTE_ON = 7,               /* i64_a = midi note, f64_a = velocity 0..1 */
  OB_CMD_NOTE_OFF = 8,              /* i64_a = midi note */
  OB_CMD_ALL_NOTES_OFF = 9,         /* -- */
  OB_CMD_SET_MASTER_GAIN = 10,      /* f64_a = linear gain, 0..2 */
  OB_CMD_PLUGIN_PARAM_BEGIN = 11,   /* i64_a = ParamId */
  OB_CMD_PLUGIN_PARAM_VALUE = 12,   /* i64_a = ParamId, f64_a = value */
  OB_CMD_PLUGIN_PARAM_END = 13,     /* i64_a = ParamId */
  OB_CMD_SET_INSTRUMENT_GAIN = 14,  /* f64_a = linear gain, 0..2 */
  OB_CMD_SET_INSTRUMENT_PAN = 15,   /* f64_a = pan -1..1 */
  OB_CMD_PREVIEW_NOTE_ON = 16,      /* i64_a = midi note, f64_a = velocity */
  OB_CMD_PREVIEW_NOTE_OFF = 17,     /* i64_a = midi note */
  OB_CMD_SET_METRONOME = 18         /* i64_a = 0 disabled / 1 enabled */
} ob_command_type;

/* Fixed layout, POD, 32 bytes. Frozen by the ABI layout test (OB-1-13).
 * Fields are deliberately generic: adding a command type must not change the
 * struct (additive-only evolution, ADR-002 §8). */
typedef struct ob_command {
  uint32_t type;       /* ob_command_type */
  uint32_t generation; /* client-assigned, echoed in the snapshot for coalescing */
  int64_t i64_a;
  double f64_a;
  double f64_b;
} ob_command;

/* UI thread only (single producer). Never blocks, never allocates.
 * Fire-and-forget: returns OB_ERR_QUEUE_FULL if the engine is not draining;
 * the caller may retry next frame. Commands take effect at the next audio
 * block boundary. */
OB_API ob_status ob_engine_post_command(ob_engine* engine, const ob_command* command);

/* ------------------------------------------------------------------------- */
/* Snapshot channel: engine -> UI, once per UI frame (ADR-002 §4)             */
/* ------------------------------------------------------------------------- */

/* Bumped whenever the layout changes; the reader checks it once at startup. */
#define OB_SNAPSHOT_VERSION 1

/* Fixed layout, POD. Written by the audio thread into a seqlock-protected slot
 * and copied out by ob_engine_read_snapshot. Field order is chosen for natural
 * alignment with no implicit padding; the layout test freezes every offset. */
typedef struct ob_snapshot {
  uint32_t struct_version; /* = OB_SNAPSHOT_VERSION */
  uint32_t struct_size;    /* = sizeof(ob_snapshot) */

  uint32_t playing;      /* 0/1 */
  uint32_t loop_enabled; /* 0/1 */

  int64_t position_frames; /* canonical transport position */
  uint64_t host_time_ns;   /* monotonic clock at publish; meter ballistics use
                              this, never a frame counter (OB-1-11 §3) */
  uint64_t callback_count; /* audio callbacks since engine start */
  uint64_t xrun_count;     /* render-overrun count (OB-1-12 §3) */
  uint64_t dropped_log_records;
  uint64_t last_command_generation; /* highest generation applied */

  double position_beats;
  double position_seconds;
  double tempo_bpm;
  double loop_start_beats;
  double loop_end_beats;
  double sample_rate;

  int32_t bar;  /* 1-based musical position, 4/4 in v0.1 */
  int32_t beat; /* 1-based */
  int32_t tick; /* 0..959, 960 PPQN */
  int32_t block_frames;

  int32_t active_voices;
  int32_t latency_frames_output;
  int32_t latency_frames_roundtrip;
  int32_t schedule_event_count;

  float peak_left;
  float peak_right;
  float rms_left;
  float rms_right;

  float cpu_load;    /* render time / block budget, 0..1+ */
  float master_gain; /* linear */
} ob_snapshot;

/* Any thread, typically the UI frame callback. Never blocks (bounded seqlock
 * retry), never allocates. Copies the most recent consistent snapshot into
 * caller-owned memory — allocate one ob_snapshot at startup and reuse it. */
OB_API ob_status ob_engine_read_snapshot(ob_engine* engine, ob_snapshot* out_snapshot);

/* ------------------------------------------------------------------------- */
/* Event channel: engine -> UI, occasional (ADR-002 §5)                       */
/* ------------------------------------------------------------------------- */

typedef enum ob_event_type {
  OB_EVT_NONE = 0,
  OB_EVT_DEVICE_CHANGED = 1,    /* text = new device name */
  OB_EVT_DEVICE_LOST = 2,       /* text = lost device name; engine fell back */
  OB_EVT_ERROR = 3,             /* code = ob_status, text = message */
  OB_EVT_SAMPLE_LOADED = 4,     /* text = file name, i64_a = frames */
  OB_EVT_XRUN = 5,              /* i64_a = total xruns */
  OB_EVT_SCHEDULE_PUBLISHED = 6 /* i64_a = schedule generation */
} ob_event_type;

typedef struct ob_event {
  uint32_t type; /* ob_event_type */
  int32_t code;  /* ob_status where applicable, else 0 */
  int64_t i64_a;
  double f64_a;
  char text[96]; /* UTF-8, NUL-terminated, engine-owned copy */
} ob_event;

/* UI thread only (single consumer). Never blocks, never allocates.
 * Returns 1 and fills *out_event when an event was dequeued, 0 when empty.
 * Drain in a loop once per UI frame. */
OB_API int32_t ob_engine_poll_event(ob_engine* engine, ob_event* out_event);

/* ------------------------------------------------------------------------- */
/* Content (v0.1 subset — the real model arrives in Stage 3)                  */
/* ------------------------------------------------------------------------- */

/* Main/UI thread. Returns immediately; decoding happens on a worker thread and
 * completes with an OB_EVT_SAMPLE_LOADED or OB_EVT_ERROR event. Passing NULL
 * loads the bundled default one-shot. Path is UTF-8 and is copied. */
OB_API ob_status ob_engine_load_sample(ob_engine* engine, const char* utf8_path);

/* Main/UI thread. May block briefly (flattens and publishes a schedule on the
 * calling thread, then hands the retired one to the reclaim thread).
 * `steps` is one byte per step: 0 = rest, 1..127 = velocity.
 * v0.1 stand-in for the Stage 3 flattener; the publish machinery it drives is
 * final (OB-1-07). */
OB_API ob_status ob_engine_set_step_pattern(ob_engine* engine, const uint8_t* steps,
                                            int32_t step_count, int32_t midi_note,
                                            double step_beats);

/* Main/UI thread. Never blocks. Human-readable name of the active output
 * device; static per-engine storage, valid until the next device change. */
OB_API const char* ob_engine_output_device_name(ob_engine* engine);

/* ------------------------------------------------------------------------- */
/* Plugin library: scan progress and the plugin list (OB-2-02, FR-PLG-05)     */
/* ------------------------------------------------------------------------- */

/* None of this touches the audio thread. The plugin list is main-thread-owned
 * state read from a persistent cache and a background scanner, so the
 * "no synchronous ask-and-wait" rule of ADR-002 §8 — which is about state the
 * audio thread owns — does not apply and no snapshot field is involved. The
 * list is not frame-rate data: read it when the scan generation changes, not
 * every frame. */

typedef enum ob_scan_state {
  OB_SCAN_IDLE = 0,
  OB_SCAN_DISCOVERING = 1, /* walking the plug-in folders */
  OB_SCAN_PROBING = 2,     /* opening the bundles that changed */
  OB_SCAN_COMPLETE = 3,
  OB_SCAN_CANCELLED = 4
} ob_scan_state;

typedef enum ob_plugin_format {
  OB_PLUGIN_FORMAT_UNKNOWN = 0,
  OB_PLUGIN_FORMAT_BUILTIN = 1,
  OB_PLUGIN_FORMAT_CLAP = 2,
  OB_PLUGIN_FORMAT_VST3 = 3, /* Stage 5 */
  OB_PLUGIN_FORMAT_AU = 4    /* Stage 5 */
} ob_plugin_format;

/* Why a plugin is not available. OB-2-03 fills in the crash and hang cases; the
 * values exist here from the start so the UI's copy table is written once. */
typedef enum ob_scan_outcome {
  OB_SCAN_OK = 0,
  OB_SCAN_NOT_A_PLUGIN = 1,
  OB_SCAN_CRASHED = 2,
  OB_SCAN_TIMED_OUT = 3
} ob_scan_outcome;

/* The last phase announced by the scan helper before a quarantine failure. */
typedef enum ob_scan_phase {
  OB_SCAN_PHASE_NONE = 0,
  OB_SCAN_PHASE_SPAWN = 1,
  OB_SCAN_PHASE_LOAD = 2,
  OB_SCAN_PHASE_ENUMERATE = 3,
  OB_SCAN_PHASE_INSTANTIATE = 4,
  OB_SCAN_PHASE_DONE = 5
} ob_scan_phase;

/* Bit flags describing how much of an ob_plugin_info is actually known. */
#define OB_PLUGIN_FLAG_INTROSPECTED                 \
  0x1u /* the plugin was opened and asked; without  \
        * this, id/vendor/version and the port and  \
        * parameter counts are placeholders and the \
        * UI must say "not yet inspected" rather    \
        * than show them as facts */

typedef struct ob_plugin_scan_status {
  uint32_t struct_size; /* = sizeof(ob_plugin_scan_status) */
  uint32_t state;       /* ob_scan_state */

  uint32_t bundles_discovered;
  uint32_t bundles_reused; /* unchanged since the last scan, so never opened */
  uint32_t bundles_probed;
  uint32_t plugins_found;

  uint32_t plugin_count; /* rows currently retrievable via ob_engine_plugin_at */
  /* Increments whenever the list changes. The UI re-reads the list when this
   * moves and otherwise does nothing, which is what keeps the per-frame path
   * allocation-free. */
  uint32_t list_generation;

  char current[256]; /* bundle being opened right now; "" when not probing */
} ob_plugin_scan_status;

/* One row of the plugin list. ~1 KB, POD, caller-owned: allocate one and reuse
 * it across the loop that reads the list. Copied out rather than pointed at
 * because the list is rebuilt underneath as the scan streams in. */
typedef struct ob_plugin_info {
  uint32_t struct_size; /* = sizeof(ob_plugin_info) */
  uint32_t format;      /* ob_plugin_format */
  uint32_t outcome;     /* ob_scan_outcome */
  uint32_t flags;       /* OB_PLUGIN_FLAG_* */

  uint32_t features;        /* reserved for the browser's filters (FR-PLG-13) */
  uint32_t param_count;     /* 0 unless OB_PLUGIN_FLAG_INTROSPECTED */
  uint32_t index_in_bundle; /* one bundle can contain many plugins */
  uint32_t audio_input_count;
  uint32_t audio_output_count;
  uint32_t note_input_count;
  uint32_t note_output_count;
  uint32_t padding_;

  int64_t scanned_at_nanos; /* Unix nanoseconds */

  char id[128];
  char name[128];
  char vendor[128];
  char version[32];
  char path[512];

  /* Added in ABI 1.2. Appended so every ABI 1.1 field keeps its offset. */
  uint32_t failure_phase;  /* ob_scan_phase; meaningful when quarantined */
  uint32_t failure_signal; /* signal that killed the helper, or 0 */
  uint32_t retry_count;    /* manual retries since this quarantine began */
} ob_plugin_info;

/* Main/UI thread. May block briefly: reads the scan cache from disk. Call once
 * at startup, before the first frame — that is the whole point of the cache.
 * Safe to call again; it discards and reloads. */
OB_API ob_status ob_engine_plugin_cache_load(ob_engine* engine);

/* Main/UI thread. Never blocks: launches the background scan and returns.
 * Returns OB_ERR_ALREADY_RUNNING if a scan is in flight. Passing NULL or an
 * empty `utf8_directories` scans the standard plug-in folders; otherwise it is
 * a NUL-separated, double-NUL-terminated list of directories (so the UI can add
 * user folders without an array-of-pointers marshalling dance). */
OB_API ob_status ob_engine_plugin_scan_start(ob_engine* engine, const char* utf8_directories);

/* Main/UI thread. Never blocks. Asks the scan to stop at the next bundle; a
 * cancelled scan does not update the cache. */
OB_API ob_status ob_engine_plugin_scan_cancel(ob_engine* engine);

/* Main/UI thread. Never blocks: launches a background re-scan of exactly one
 * quarantined bundle. `utf8_path` is copied. Returns OB_ERR_ALREADY_RUNNING if
 * another scan is in flight. */
OB_API ob_status ob_engine_plugin_retry(ob_engine* engine, const char* utf8_path);

/* Main/UI thread. Never blocks. Also the point at which streamed results are
 * folded into the list, so call it once per frame while a scan is running. */
OB_API ob_status ob_engine_plugin_scan_status(ob_engine* engine, ob_plugin_scan_status* out_status);

/* Main/UI thread. Never blocks. Copies row `index` (0-based, ordered by display
 * name) into caller-owned memory. Returns OB_ERR_INVALID_ARGUMENT for an index
 * past the end — which is how a stale index is detected after the list changed
 * under the caller. */
OB_API ob_status ob_engine_plugin_at(ob_engine* engine, int32_t index, ob_plugin_info* out_info);

/* ------------------------------------------------------------------------- */
/* Hosted instance + parameters (added in ABI 1.3, OB-2-09/10)               */
/* ------------------------------------------------------------------------- */

#define OB_INSTANCE_FLAG_MISSING 0x1u
#define OB_INSTANCE_FLAG_BYPASSED 0x2u
#define OB_INSTANCE_FLAG_HAS_EDITOR 0x4u
#define OB_INSTANCE_FLAG_NEEDS_RESTART 0x8u

typedef struct ob_instance_info {
  uint32_t struct_size;
  uint32_t instance_id;
  uint32_t format; /* ob_plugin_format */
  uint32_t flags;  /* OB_INSTANCE_FLAG_* */
  uint32_t param_count;
  uint32_t reserved;
  char plugin_id[128];
  char name[128];
  char vendor[128];
  char path[512];
} ob_instance_info;

typedef struct ob_param_info {
  uint32_t struct_size;
  uint32_t instance_id;
  uint32_t param_id;
  uint32_t flags;
  double min_value;
  double max_value;
  double default_value;
  double value;
  char name[128];
  char module[128];
  char display[128];
} ob_param_info;

/* Main/UI thread. May block while the helper launches and the plug-in loads.
 * Strings are copied before return. v0.2 has one flat instrument slot. */
OB_API ob_status ob_engine_instance_add(ob_engine* engine, const char* utf8_bundle_path,
                                        const char* utf8_plugin_id);
/* Main/UI thread. May block while the helper exits. Restores the built-in. */
OB_API ob_status ob_engine_instance_remove(ob_engine* engine, uint32_t instance_id);
/* Main/UI thread. Never blocks. The v0.2 flat list contains zero or one row. */
OB_API int32_t ob_engine_instance_count(ob_engine* engine);
OB_API ob_status ob_engine_instance_at(ob_engine* engine, int32_t index,
                                       ob_instance_info* out_info);
/* Main/UI thread. May block briefly on the helper control channel. */
OB_API ob_status ob_engine_param_at(ob_engine* engine, uint32_t instance_id, int32_t index,
                                    ob_param_info* out_info);
/* Main/UI thread. May block briefly on helper window creation. */
OB_API ob_status ob_engine_instance_editor_open(ob_engine* engine, uint32_t instance_id);
OB_API ob_status ob_engine_instance_editor_close(ob_engine* engine, uint32_t instance_id);
/* Main/UI thread. Replaces a failed helper and restores its last state. */
OB_API ob_status ob_engine_instance_restart(ob_engine* engine, uint32_t instance_id);
/* Main/UI thread. May block on filesystem and opaque plug-in state I/O. */
OB_API ob_status ob_engine_session_save(ob_engine* engine, const char* utf8_path);
OB_API ob_status ob_engine_session_load(ob_engine* engine, const char* utf8_path);

/* ------------------------------------------------------------------------- */
/* Project instruments (added in ABI 1.5, OB-3-07)                           */
/* ------------------------------------------------------------------------- */

typedef struct ob_instrument_info {
  uint32_t struct_size;
  int32_t order;
  uint32_t flags; /* bit 0: muted; bit 1: selected; bit 2: soloed */
  uint32_t affected_pattern_count;
  uint32_t affected_clip_count;
  uint32_t affected_note_count;
  char id[32];
  char name[128];
  char color[8];
  char plugin_id[128];
  char plugin_name[128];
  char plugin_vendor[128];
  char plugin_path[512];
  float gain;           /* linear 0..2, the channel rack VOL knob */
  float pan;            /* -1..1, the channel rack PAN knob */
  char route_id[32];    /* stable mixer-track ID for output port 0 */
  char route_name[128]; /* display name for output port 0 */
} ob_instrument_info;

/* Main/UI thread. The rows are project-global and ordered by `order`. */
OB_API int32_t ob_engine_instrument_count(ob_engine* engine);
OB_API ob_status ob_engine_instrument_at(ob_engine* engine, int32_t index,
                                         ob_instrument_info* out_info);
OB_API ob_status ob_engine_instrument_select(ob_engine* engine, const char* utf8_instrument_id);
OB_API ob_status ob_engine_instrument_rename(ob_engine* engine, const char* utf8_instrument_id,
                                             const char* utf8_name);
OB_API ob_status ob_engine_instrument_recolor(ob_engine* engine, const char* utf8_instrument_id,
                                              const char* utf8_color);
OB_API ob_status ob_engine_instrument_set_muted(ob_engine* engine, const char* utf8_instrument_id,
                                                int32_t muted);
OB_API ob_status ob_engine_instrument_set_soloed(ob_engine* engine, const char* utf8_instrument_id,
                                                 int32_t soloed);
OB_API ob_status ob_engine_instrument_reorder(ob_engine* engine, const char* utf8_instrument_id,
                                              int32_t order);
OB_API ob_status ob_engine_instrument_replace(ob_engine* engine, const char* utf8_instrument_id,
                                              const char* utf8_bundle_path,
                                              const char* utf8_plugin_id);
OB_API ob_status ob_engine_instrument_duplicate(ob_engine* engine, const char* utf8_instrument_id);
OB_API ob_status ob_engine_instrument_remove(ob_engine* engine, const char* utf8_instrument_id);
/* Adds a channel with no plug-in — an empty lane to drop an instrument into.
 * Main/UI thread. `utf8_name` may be empty for a generated name. */
OB_API ob_status ob_engine_instrument_add_empty(ob_engine* engine, const char* utf8_name);
/* Adds a project instrument backed by one decoded WAV sample. The path is
 * persisted in the instrument's plugin reference and loaded by the built-in
 * sampler when the row is selected. */
OB_API ob_status ob_engine_instrument_add_sample(ob_engine* engine, const char* utf8_name,
                                                 const char* utf8_sample_path);
/* Replaces an existing instrument with a sample-backed instrument. */
OB_API ob_status ob_engine_instrument_replace_sample(ob_engine* engine,
                                                     const char* utf8_instrument_id,
                                                     const char* utf8_name,
                                                     const char* utf8_sample_path);
/* Per-channel gain (linear 0..2) and pan (-1..1), applied to the active voice.
 * v0.3 hosts one instrument, so these act on the hosted voice; the per-track
 * mixer (v0.4) replaces this. */
OB_API ob_status ob_engine_instrument_set_gain(ob_engine* engine, const char* utf8_instrument_id,
                                               float gain);
OB_API ob_status ob_engine_instrument_set_pan(ob_engine* engine, const char* utf8_instrument_id,
                                              float pan);
/* Routes output port 0 to an existing mixer track by stable ID. */
OB_API ob_status ob_engine_instrument_set_route(ob_engine* engine, const char* utf8_instrument_id,
                                                const char* utf8_mixer_track_id);

/* Advanced Channel Settings. This is a new struct/API rather than an extension
 * of ob_instrument_info, whose layout is frozen for ABI compatibility. */
typedef struct ob_instrument_settings {
  uint32_t struct_size;
  int32_t gate_percent;
  int64_t shift_ticks;
  int32_t cut_group;
  int32_t cut_by_group;
  int32_t max_polyphony;
  int32_t mono;
  int32_t portamento;
  int32_t root_key;
  int32_t key_low;
  int32_t key_high;
  int32_t fine_tune_cents;
  float velocity_tracking;
  int32_t mod_x;
  int32_t mod_y;
  int32_t arpeggiator;
  int32_t arpeggiator_time_ticks;
  int32_t arpeggiator_gate_percent;
  int32_t echo_time_ticks;
  int32_t echo_feedback_percent;
} ob_instrument_settings;
OB_API ob_status ob_engine_instrument_settings(ob_engine* engine, const char* utf8_instrument_id,
                                               ob_instrument_settings* out_settings);
OB_API ob_status ob_engine_instrument_set_settings(ob_engine* engine, const char* utf8_instrument_id,
                                                   const ob_instrument_settings* settings);
OB_API int32_t ob_engine_project_can_undo(ob_engine* engine);
OB_API int32_t ob_engine_project_can_redo(ob_engine* engine);
/* Main/UI thread. Never blocks. Engine-owned UTF-8, valid until the next call
 * to the same getter; caller must not free. */
OB_API const char* ob_engine_project_undo_name(ob_engine* engine);
OB_API const char* ob_engine_project_redo_name(ob_engine* engine);
OB_API ob_status ob_engine_project_undo(ob_engine* engine);
OB_API ob_status ob_engine_project_redo(ob_engine* engine);

/* ------------------------------------------------------------------------- */
/* Channel rack (added in ABI 1.6, OB-3-09)                                  */
/* ------------------------------------------------------------------------- */

#define OB_RACK_MAX_STEPS 512

typedef struct ob_rack_pattern_info {
  uint32_t struct_size;
  int64_t length_ticks;
  int64_t base_grid_ticks;
  double swing;
  char id[32];
  char name[128];
} ob_rack_pattern_info;

typedef struct ob_rack_row_info {
  uint32_t struct_size;
  uint32_t flags; /* bit 0: sequence has notes; bit 1: off-grid notes present */
  int64_t grid_ticks;
  int32_t step_count;
  uint32_t note_count;
  uint32_t off_grid_count;
  char instrument_id[32];
  uint8_t step_active[OB_RACK_MAX_STEPS];
  uint16_t step_velocity[OB_RACK_MAX_STEPS];
} ob_rack_row_info;

/* Main/UI thread. Never blocks. Rack rows follow project instrument order and
 * are copied into caller-owned fixed-layout output structs. */
OB_API ob_status ob_engine_rack_pattern(ob_engine* engine, ob_rack_pattern_info* out_info);
OB_API int32_t ob_engine_rack_row_count(ob_engine* engine);
OB_API ob_status ob_engine_rack_row_at(ob_engine* engine, int32_t index,
                                       ob_rack_row_info* out_info);
/* Main/UI thread. Never blocks. Presentation state only; does not flatten. */
OB_API ob_status ob_engine_rack_set_row_grid(ob_engine* engine, const char* utf8_instrument_id,
                                             int64_t grid_ticks);
/* Main/UI thread. May block briefly while the model is flattened and its
 * immutable schedule is published. Input strings are copied before return. */
OB_API ob_status ob_engine_rack_set_length(ob_engine* engine, int32_t base_step_count);
OB_API ob_status ob_engine_rack_set_swing(ob_engine* engine, double swing);
OB_API ob_status ob_engine_rack_toggle_step(ob_engine* engine, const char* utf8_instrument_id,
                                            int32_t step_index);
OB_API ob_status ob_engine_rack_set_step_velocity(ob_engine* engine, const char* utf8_instrument_id,
                                                  int32_t step_index, uint16_t velocity);
OB_API ob_status ob_engine_rack_remove_sequence(ob_engine* engine, const char* utf8_instrument_id);
/* Main/UI thread. Begin never blocks; commit/abort may briefly flatten and
 * publish. A paint drag is one undo entry even when it changes many cells. */
/* Main/UI thread. Begin never blocks; commit/abort may briefly flatten and
 * publish. A paint drag is one undo entry even when it changes many cells.
 *
 * Despite the `rack_` prefix these are the general editor-gesture transaction,
 * used unchanged by the piano roll and the arrangement (ABI 1.7). The name is
 * kept because renaming an exported symbol is a breaking change and the
 * behaviour is identical; `utf8_name` is what the undo entry ends up called. */
OB_API ob_status ob_engine_rack_gesture_begin(ob_engine* engine, const char* utf8_name);
OB_API ob_status ob_engine_rack_gesture_commit(ob_engine* engine);
OB_API ob_status ob_engine_rack_gesture_abort(ob_engine* engine);

/* ------------------------------------------------------------------------- */
/* Notes: the piano roll (added in ABI 1.7, OB-3-10)                          */
/* ------------------------------------------------------------------------- */

/* One note of one sequence, in the current pattern, for one instrument.
 *
 * A note has no ID. In the model it is a *value* inside a sorted sequence
 * (model/note_sequence.h), and the editing vocabulary in model/note_edit.h
 * addresses notes by passing them back by value. The ABI keeps that shape: the
 * UI reads notes out, holds them as its selection, and hands the same values
 * back to say which ones an edit applies to. That is why every mutation below
 * takes an array rather than an index — an index would go stale the instant
 * another edit re-sorted the sequence. */
typedef struct ob_note {
  int64_t start;    /* ticks, pattern-relative, 960 PPQN */
  int64_t length;   /* ticks, > 0 */
  int32_t key;      /* MIDI key, 0..127 */
  int32_t velocity; /* 1..16383 */
} ob_note;

/* Main/UI thread. Never blocks. Notes for `utf8_instrument_id` in the current
 * pattern; 0 when the pattern holds no sequence for it. */
OB_API int32_t ob_engine_note_count(ob_engine* engine, const char* utf8_instrument_id);

/* Main/UI thread. Never blocks, never allocates. Copies up to `capacity` notes
 * into caller-owned memory in (start, key) order and writes how many were
 * written to *out_count. Allocate once against ob_engine_note_count and reuse:
 * this is read every time the sequence changes, not every frame. */
OB_API ob_status ob_engine_notes_read(ob_engine* engine, const char* utf8_instrument_id,
                                      ob_note* out_notes, int32_t capacity, int32_t* out_count);

/* Every mutation below goes through an OB-3-03 command, so all of them undo,
 * and all of them coalesce into the enclosing ob_engine_rack_gesture_* when one
 * is open. Each may briefly flatten and publish. `snap_ticks` of 0 means "do
 * not snap"; otherwise the result is snapped to that grid. */
OB_API ob_status ob_engine_note_add(ob_engine* engine, const char* utf8_instrument_id,
                                    int64_t start, int64_t length, int32_t key, int32_t velocity);
OB_API ob_status ob_engine_notes_remove(ob_engine* engine, const char* utf8_instrument_id,
                                        const ob_note* notes, int32_t count);
OB_API ob_status ob_engine_notes_move(ob_engine* engine, const char* utf8_instrument_id,
                                      const ob_note* notes, int32_t count, int64_t delta_ticks,
                                      int32_t semitones, int64_t snap_ticks);
OB_API ob_status ob_engine_notes_resize(ob_engine* engine, const char* utf8_instrument_id,
                                        const ob_note* notes, int32_t count, int64_t length_delta,
                                        int64_t snap_ticks);
OB_API ob_status ob_engine_notes_set_velocity(ob_engine* engine, const char* utf8_instrument_id,
                                              const ob_note* notes, int32_t count,
                                              int32_t velocity);
/* `strength` is 0..1: 0 leaves the note where it is, 1 lands it on the grid. */
OB_API ob_status ob_engine_notes_quantise(ob_engine* engine, const char* utf8_instrument_id,
                                          const ob_note* notes, int32_t count, int64_t grid_ticks,
                                          double strength);
OB_API ob_status ob_engine_notes_duplicate(ob_engine* engine, const char* utf8_instrument_id,
                                           const ob_note* notes, int32_t count,
                                           int64_t delta_ticks);

/* ------------------------------------------------------------------------- */
/* Patterns (added in ABI 1.7, OB-3-11)                                       */
/* ------------------------------------------------------------------------- */

#define OB_PATTERN_FLAG_CURRENT 0x1u

typedef struct ob_pattern_info {
  uint32_t struct_size;
  uint32_t flags; /* OB_PATTERN_FLAG_* */
  int64_t length_ticks;
  double swing;
  /* Derived on read, never stored: a cached count is a second source of truth
   * that goes stale, and D-M6 needs this to be right rather than fast. */
  uint32_t usage_count;
  uint32_t note_count;
  char id[32];
  char name[128];
  char color[8];
  int32_t order;
  int32_t time_signature_numerator;
  int32_t time_signature_denominator;
  char group[64];
} ob_pattern_info;

/* Main/UI thread. Never blocks. Patterns in creation (ULID) order. */
OB_API int32_t ob_engine_pattern_count(ob_engine* engine);
OB_API ob_status ob_engine_pattern_at(ob_engine* engine, int32_t index, ob_pattern_info* out_info);
/* Which pattern the rack and the piano roll edit. Presentation state: not
 * undoable, because selecting is not an edit. */
OB_API ob_status ob_engine_pattern_select(ob_engine* engine, const char* utf8_pattern_id);

/* Editor preview: schedules only the selected pattern once at tick zero and
 * loops it at the pattern's own length. Playlist transport remains separate. */
OB_API ob_status ob_engine_pattern_preview_start(ob_engine* engine, const char* utf8_pattern_id);
OB_API ob_status ob_engine_pattern_preview_channel_start(ob_engine* engine,
                                                         const char* utf8_pattern_id,
                                                         const char* utf8_instrument_id);
OB_API ob_status ob_engine_pattern_preview_stop(ob_engine* engine);
/* May block briefly (flattens). Creates and selects; the new ID is readable by
 * re-reading the list and looking for OB_PATTERN_FLAG_CURRENT. */
OB_API ob_status ob_engine_pattern_create(ob_engine* engine, const char* utf8_name);
OB_API ob_status ob_engine_pattern_rename(ob_engine* engine, const char* utf8_pattern_id,
                                          const char* utf8_name);
OB_API ob_status ob_engine_pattern_recolor(ob_engine* engine, const char* utf8_pattern_id,
                                           const char* utf8_color);
/* An *unreferenced* clone: copies the sequences, repoints no clip. Distinct
 * from ob_engine_clips_make_unique, which repoints exactly the clips given
 * (FR-SEQ-04 vs FR-UX-11's action vocabulary — both exist, differently named,
 * because they are different intentions). */
OB_API ob_status ob_engine_pattern_duplicate(ob_engine* engine, const char* utf8_pattern_id);
/* Deletes the pattern and every clip referencing it, as one undo entry. The
 * caller is expected to have shown the clip count first (D-M6). */
OB_API ob_status ob_engine_pattern_remove(ob_engine* engine, const char* utf8_pattern_id);
/* Pattern metadata edits are undoable and persist with the project. */
OB_API ob_status ob_engine_pattern_set_time_signature(ob_engine* engine,
                                                      const char* utf8_pattern_id,
                                                      int32_t numerator, int32_t denominator);
OB_API ob_status ob_engine_pattern_reorder(ob_engine* engine, const char* utf8_pattern_id,
                                           int32_t order);
OB_API ob_status ob_engine_pattern_set_group(ob_engine* engine, const char* utf8_pattern_id,
                                             const char* utf8_group);

/* ------------------------------------------------------------------------- */
/* Arrangement: lanes and clips (added in ABI 1.7, OB-3-12/13)                */
/* ------------------------------------------------------------------------- */

#define OB_LANE_FLAG_MUTED 0x1u /* an *event* gate, never an audio fade (D-M4) */
#define OB_LANE_FLAG_SOLOED 0x2u
#define OB_LANE_FLAG_COLLAPSED 0x4u

/* Deliberately absent, and this is the point of the whole entity: there is no
 * instrument, no mixer track, no gain, no pan, no meter and no plugin here. A
 * lane is organisational. Adding any of those fields is the anti-pattern
 * ARCHITECTURE.md §6 #2 names, and the review checklist for this struct is
 * "does it still hold nothing that implies routing?". */
typedef struct ob_lane_info {
  uint32_t struct_size;
  uint32_t flags; /* OB_LANE_FLAG_* */
  int32_t order;  /* the display order field, never the array position */
  int32_t height;
  uint32_t clip_count;
  uint32_t reserved_;
  char id[32];
  char name[128];
  char color[8];
} ob_lane_info;

OB_API int32_t ob_engine_lane_count(ob_engine* engine);
/* Rows are returned ordered by `order`, which is what the view draws. */
OB_API ob_status ob_engine_lane_at(ob_engine* engine, int32_t index, ob_lane_info* out_info);
OB_API ob_status ob_engine_lane_create(ob_engine* engine, const char* utf8_name);
OB_API ob_status ob_engine_lane_rename(ob_engine* engine, const char* utf8_lane_id,
                                       const char* utf8_name);
OB_API ob_status ob_engine_lane_recolor(ob_engine* engine, const char* utf8_lane_id,
                                        const char* utf8_color);
OB_API ob_status ob_engine_lane_reorder(ob_engine* engine, const char* utf8_lane_id, int32_t order);
OB_API ob_status ob_engine_lane_set_height(ob_engine* engine, const char* utf8_lane_id,
                                           int32_t height);
OB_API ob_status ob_engine_lane_set_muted(ob_engine* engine, const char* utf8_lane_id,
                                          int32_t muted);
OB_API ob_status ob_engine_lane_set_soloed(ob_engine* engine, const char* utf8_lane_id,
                                           int32_t soloed);
OB_API ob_status ob_engine_lane_set_collapsed(ob_engine* engine, const char* utf8_lane_id,
                                              int32_t collapsed);
/* Deletes the lane and its clips as one undo entry; the caller shows the count. */
OB_API ob_status ob_engine_lane_remove(ob_engine* engine, const char* utf8_lane_id);

#define OB_CLIP_FLAG_MUTED 0x1u
#define OB_CLIP_FLAG_LOOP 0x2u  /* clear => hold-off: the tail is silence */
#define OB_CLIP_FLAG_AUDIO 0x4u /* source is an audio file, not a pattern */

typedef struct ob_clip_info {
  uint32_t struct_size;
  uint32_t flags; /* OB_CLIP_FLAG_* */
  int64_t start_ticks;
  int64_t length_ticks;
  int64_t window_start_ticks; /* offset into the pattern (DM-Q2) */
  /* The source pattern's length, so the view can draw loop boundaries and the
   * tiled repeat without a second lookup per clip while painting. */
  int64_t pattern_length_ticks;
  int32_t transpose;    /* semitones, -48..48 (DM-Q3) */
  uint32_t note_count;  /* in the source pattern, for the density preview */
  uint32_t usage_count; /* clips sharing this clip's pattern, including it */
  uint32_t reserved_;
  char id[32];
  char lane_id[32];
  char pattern_id[32];
  char name[128]; /* the pattern's name — a clip has no name of its own */
  char color[8];  /* the pattern's colour, likewise */
  /* Absolute/source path for audio clips; empty for pattern and automation
   * clips. Appended in ABI 1.10 so the existing fields keep their offsets. */
  char audio_path[512];
} ob_clip_info;

OB_API int32_t ob_engine_clip_count(ob_engine* engine);
OB_API ob_status ob_engine_clip_at(ob_engine* engine, int32_t index, ob_clip_info* out_info);
/* Places the *current* pattern when `utf8_pattern_id` is NULL or empty, which
 * is the drag-from-the-selector path. */
OB_API ob_status ob_engine_clip_add(ob_engine* engine, const char* utf8_lane_id,
                                    const char* utf8_pattern_id, int64_t start_ticks,
                                    int64_t length_ticks);
/* Adds an audio clip from a WAV file. The clip length is derived from the
 * source duration at the current project tempo, so the UI can place the full
 * file without decoding it a second time. Main/UI thread; may block while the
 * WAV header and samples are read. */
OB_API ob_status ob_engine_audio_clip_add(ob_engine* engine, const char* utf8_lane_id,
                                          const char* utf8_sample_path, int64_t start_ticks);
/* Moving between lanes is deliberately the same call as moving in time, and
 * changes nothing audible: a lane carries no signal (ARCHITECTURE.md §4). */
OB_API ob_status ob_engine_clip_move(ob_engine* engine, const char* utf8_clip_id,
                                     const char* utf8_lane_id, int64_t start_ticks);
OB_API ob_status ob_engine_clip_resize(ob_engine* engine, const char* utf8_clip_id,
                                       int64_t length_ticks);
OB_API ob_status ob_engine_clip_duplicate(ob_engine* engine, const char* utf8_clip_id,
                                          const char* utf8_lane_id, int64_t start_ticks);
OB_API ob_status ob_engine_clip_remove(ob_engine* engine, const char* utf8_clip_id);
OB_API ob_status ob_engine_clip_set_muted(ob_engine* engine, const char* utf8_clip_id,
                                          int32_t muted);
OB_API ob_status ob_engine_clip_set_loop(ob_engine* engine, const char* utf8_clip_id, int32_t loop);
OB_API ob_status ob_engine_clip_set_window_start(ob_engine* engine, const char* utf8_clip_id,
                                                 int64_t window_start_ticks);
OB_API ob_status ob_engine_clip_set_transpose(ob_engine* engine, const char* utf8_clip_id,
                                              int32_t semitones);

/* Audio clip editing (added in ABI 1.18)                                     */

#define OB_STRETCH_OFF 0      /* the clip is a window; resizing trims */
#define OB_STRETCH_RESAMPLE 1 /* speed moves the pitch */
#define OB_STRETCH_STRETCH 2  /* pitch-preserving, via the WSOLA stretcher */

typedef struct ob_audio_clip_info {
  uint32_t struct_size;
  int32_t stretch_mode;        /* OB_STRETCH_* */
  int64_t source_offset_ticks; /* trim-in, in *source* time */
  /* Trim-out as a duration from the offset. 0 means "to the end of the file",
   * which is the state a freshly dropped sample is in. */
  int64_t source_length_ticks;
  /* The whole file's duration at the current tempo, so the editor can draw how
   * much room a trim has left without decoding the file again. 0 when unknown. */
  int64_t source_duration_ticks;
  double source_bpm; /* 0 when unknown; only "fit to tempo" reads it */
  double gain;
  int32_t reversed;
  int32_t reserved_;
} ob_audio_clip_info;

/* Fails with OB_STATUS_INVALID_ARGUMENT when the clip is not an audio clip. */
OB_API ob_status ob_engine_audio_clip_info(ob_engine* engine, const char* utf8_clip_id,
                                           ob_audio_clip_info* out_info);
/* Trim. Both values are in source time; `source_length_ticks` of 0 keeps its
 * "to the end of the file" meaning. */
OB_API ob_status ob_engine_audio_clip_set_window(ob_engine* engine, const char* utf8_clip_id,
                                                 int64_t source_offset_ticks,
                                                 int64_t source_length_ticks);
OB_API ob_status ob_engine_audio_clip_set_stretch_mode(ob_engine* engine, const char* utf8_clip_id,
                                                       int32_t stretch_mode);
OB_API ob_status ob_engine_audio_clip_set_source_bpm(ob_engine* engine, const char* utf8_clip_id,
                                                     double bpm);
OB_API ob_status ob_engine_audio_clip_set_reversed(ob_engine* engine, const char* utf8_clip_id,
                                                   int32_t reversed);
OB_API ob_status ob_engine_audio_clip_set_gain(ob_engine* engine, const char* utf8_clip_id,
                                               double gain);
/* Resize with the clip's own stretch rule applied: a clip that is not stretched
 * re-trims, and one that is stretches. The single entry point for dragging a
 * clip's right edge, so the two behaviours cannot drift apart. */
OB_API ob_status ob_engine_audio_clip_resize(ob_engine* engine, const char* utf8_clip_id,
                                             int64_t length_ticks);
/* Cuts at an absolute tick. The left half keeps this clip's ID; the right half
 * is a new clip that resumes where the left one stopped rather than restarting
 * the file. One undo entry. OB_STATUS_INVALID_ARGUMENT when the tick is not
 * strictly inside the clip — cutting on an edge is not an edit. Works on
 * pattern and automation clips too. */
OB_API ob_status ob_engine_clip_split(ob_engine* engine, const char* utf8_clip_id,
                                      int64_t at_ticks);
/* Resizes the clip so its material plays at the project tempo, and switches it
 * to pitch-preserving stretch. OB_STATUS_INVALID_ARGUMENT when the clip has no
 * source tempo to fit — set one with ob_engine_audio_clip_set_source_bpm first,
 * because guessing silently is how a project ends up subtly out of time. */
OB_API ob_status ob_engine_audio_clip_fit_to_tempo(ob_engine* engine, const char* utf8_clip_id);

/* A counter that changes whenever the project model changes (ABI 1.18).
 *
 * The UI repaints every frame — meters and the playhead have to — but the model
 * behind it changes only when the user edits something. Reading the whole rack,
 * the whole mixer and every insert on every frame is O(project) work sixty
 * times a second, which is felt as the app getting heavier the bigger the song
 * gets. A view can compare this instead and rebuild only when it moved.
 *
 * Opaque and monotonic: compare it for equality, never interpret it. */
OB_API uint64_t ob_engine_model_revision(ob_engine* engine);

/* Mixer tracks (added in ABI 1.18, EPIC-4)                                   */

#define OB_MIXER_FLAG_MUTED 0x1u
#define OB_MIXER_FLAG_SOLOED 0x2u
/* This is the master: it feeds the device and has no output of its own. */
#define OB_MIXER_FLAG_MASTER 0x4u

typedef struct ob_mixer_track_info {
  uint32_t struct_size;
  uint32_t flags; /* OB_MIXER_FLAG_* */
  double gain;    /* linear, 0..2 */
  double pan;     /* -1..1 */
  uint32_t effect_count;
  uint32_t reserved_;
  char id[32];
  char output_id[32]; /* empty for the master */
  char name[128];
} ob_mixer_track_info;

/* Enumerated in creation order, which is the order the engine's mixer graph is
 * built in — so an index here is the index the meters and the graph agree on. */
OB_API int32_t ob_engine_mixer_track_count(ob_engine* engine);
OB_API ob_status ob_engine_mixer_track_at(ob_engine* engine, int32_t index,
                                          ob_mixer_track_info* out_info);
OB_API ob_status ob_engine_mixer_track_set_gain(ob_engine* engine, const char* utf8_track_id,
                                                double gain);
OB_API ob_status ob_engine_mixer_track_set_pan(ob_engine* engine, const char* utf8_track_id,
                                               double pan);
OB_API ob_status ob_engine_mixer_track_set_muted(ob_engine* engine, const char* utf8_track_id,
                                                 int32_t muted);
OB_API ob_status ob_engine_mixer_track_set_soloed(ob_engine* engine, const char* utf8_track_id,
                                                  int32_t soloed);

/* Mixer inserts (added in ABI 1.18, EPIC-4)                                  */

typedef struct ob_effect_descriptor {
  uint32_t struct_size;
  uint32_t reserved_;
  char id[128];
  char name[128];
  char summary[256];
} ob_effect_descriptor;

/* The effects this build ships, for the insert picker. */
OB_API int32_t ob_engine_builtin_effect_count(ob_engine* engine);
OB_API ob_status ob_engine_builtin_effect_at(ob_engine* engine, int32_t index,
                                             ob_effect_descriptor* out_info);

typedef struct ob_effect_info {
  uint32_t struct_size;
  uint32_t flags; /* OB_EFFECT_FLAG_* */
  int32_t index;  /* position in the chain */
  uint32_t param_count;
  char id[32];         /* the slot's own EffectId — what automation targets */
  char plugin_id[128]; /* which effect is in the slot */
  char name[128];
} ob_effect_info;

#define OB_EFFECT_FLAG_BYPASSED 0x1u
/* The slot names a plug-in this build does not have. It stays in the chain and
 * in the file, and it is silent (FR-PLG-10). */
#define OB_EFFECT_FLAG_MISSING 0x2u

OB_API int32_t ob_engine_mixer_effect_count(ob_engine* engine, const char* utf8_track_id);
OB_API ob_status ob_engine_mixer_effect_at(ob_engine* engine, const char* utf8_track_id,
                                           int32_t index, ob_effect_info* out_info);
/* Appends when `index` is negative. */
OB_API ob_status ob_engine_mixer_effect_add(ob_engine* engine, const char* utf8_track_id,
                                            const char* utf8_plugin_id, int32_t index);
/* Removes the insert *and* every automation clip driving it, as one undo entry.
 * Ask ob_engine_mixer_effect_impact first if the count should be shown. */
OB_API ob_status ob_engine_mixer_effect_remove(ob_engine* engine, const char* utf8_track_id,
                                               const char* utf8_effect_id);
/* How many automation clips would die with this insert. */
OB_API int32_t ob_engine_mixer_effect_impact(ob_engine* engine, const char* utf8_track_id,
                                             const char* utf8_effect_id);
OB_API ob_status ob_engine_mixer_effect_move(ob_engine* engine, const char* utf8_track_id,
                                             const char* utf8_effect_id, int32_t index);
OB_API ob_status ob_engine_mixer_effect_set_bypassed(ob_engine* engine, const char* utf8_track_id,
                                                     const char* utf8_effect_id, int32_t bypassed);

/* Insert parameters. The same `ob_param_info` the hosted-plug-in editor uses,
 * so the generic editor renders an effect with no new drawing code. */
OB_API ob_status ob_engine_mixer_effect_param_at(ob_engine* engine, const char* utf8_track_id,
                                                 const char* utf8_effect_id, uint32_t index,
                                                 ob_param_info* out_info);
OB_API ob_status ob_engine_mixer_effect_param_value(ob_engine* engine, const char* utf8_track_id,
                                                    const char* utf8_effect_id, uint32_t param_id,
                                                    double* out_value);
/* Coalesces per (track, insert, parameter) while the bus's window is open, so
 * one knob drag is one undo entry and two knobs are two. */
OB_API ob_status ob_engine_mixer_effect_set_param(ob_engine* engine, const char* utf8_track_id,
                                                  const char* utf8_effect_id, uint32_t param_id,
                                                  double value);

/* FR-SEQ-04. Clones the pattern once, repoints exactly the given clips at the
 * clone, and leaves every other reference alone — all as one undo entry, so
 * undo restores the shared reference. `utf8_clip_ids` is NUL-separated and
 * double-NUL-terminated (the same shape as ob_engine_plugin_scan_start's
 * directory list), which is how the multi-selection case is expressed without
 * marshalling an array of pointers. */
OB_API ob_status ob_engine_clips_make_unique(ob_engine* engine, const char* utf8_clip_ids);

/* Split by channel (added in ABI 1.16). Takes one pattern clip and replaces it
 * with one clip per channel the pattern uses: each new pattern holds a single
 * channel's notes and keeps the source's length, time signature and swing, and
 * each new clip keeps the source clip's position, length and transforms.
 *
 * The first channel stays on the clip's own lane; the rest go onto lanes
 * *inserted* directly below it, named after their channel — inserted rather
 * than reused, because reusing the lanes below would drop the split clips on
 * top of whatever already lives there.
 *
 * The source pattern is left in the project. It may still be placed elsewhere,
 * and a split is not a request to delete arrangement the user did not select.
 *
 * One undo entry. A clip whose pattern uses fewer than two channels has
 * nothing to split: that succeeds and changes nothing, so a menu item wired
 * straight to this call cannot raise an error dialog by being clicked. */
OB_API ob_status ob_engine_clip_split_by_channel(ob_engine* engine, const char* utf8_clip_id);

/* ------------------------------------------------------------------------- */
/* Project files (added in ABI 1.7, OB-3-05's writer reaching the UI)         */
/* ------------------------------------------------------------------------- */

/* Main/UI thread. May block: replaces the session with a fresh project
 * containing Pattern 1 and its arrangement lane. The new project has no file
 * path and is considered saved until the user edits it. */
OB_API ob_status ob_engine_project_new(ob_engine* engine);

/* Main/UI thread. May block: writes the project bundle at `utf8_path`.
 *
 * Distinct from ob_engine_session_save, which is the v0.2 scratch file holding
 * one hosted plug-in's opaque chunk. This is the real project format (ADR-004):
 * instruments, patterns, sequences, lanes, clips and transport.
 *
 * Saving is not an edit — it does not touch the undo history, and the model is
 * not mutated on the way out. */
OB_API ob_status ob_engine_project_save(ob_engine* engine, const char* utf8_path);

/* Main/UI thread. May block: replaces the whole project from the bundle at
 * `utf8_path`, clears the undo history (the history belongs to the session that
 * made it, not to the file), and republishes the schedule.
 *
 * On failure the currently open project is left exactly as it was: an
 * unreadable file must not cost the user the session they already have. */
OB_API ob_status ob_engine_project_open(ob_engine* engine, const char* utf8_path);

/* Main/UI thread. Never blocks. The canonical `project.json` bytes for the
 * project as it stands — byte-identical for a given model on any machine
 * (docs/project-format.md §6), which is what makes it usable as a
 * save/reopen equality check. Engine-owned, valid until the next call. */
OB_API const char* ob_engine_project_json(ob_engine* engine);

/* Main/UI thread. Never blocks. The bundle the project was last saved to or
 * opened from, empty for a project that has never been written. This is what
 * lets ⌘S save in place and Save As default to the right folder, without the UI
 * keeping a second copy of a fact the engine already owns. Engine-owned, valid
 * until the next save or open. */
OB_API const char* ob_engine_project_path(ob_engine* engine);

/* Main/UI thread. Never blocks. `meta.name` — the user-facing project name,
 * which is *not* derived from the file name: an unsaved project has a name and
 * no path. Engine-owned, valid until the next call that changes the name. */
OB_API const char* ob_engine_project_name(ob_engine* engine);

/* Main/UI thread. May block briefly. Renames the project. This is an edit like
 * any other — it goes through the command bus, so it undoes, and it marks the
 * project modified. Renaming the *bundle on disk* is the caller's business:
 * the engine owns the model, not the file system. */
OB_API ob_status ob_engine_project_set_name(ob_engine* engine, const char* utf8_name);

/* Main/UI thread. 1 when the project differs from what was last saved or
 * opened, 0 when it matches.
 *
 * Compared by canonical bytes rather than counted by edits, because an edit
 * count cannot answer the question the user is actually asking: undoing back to
 * the last save leaves nothing to save, and an edit counter would still claim
 * there is. The comparison is memoised against the model revision, so calling
 * this every frame costs a load and a compare. */
OB_API int32_t ob_engine_project_is_modified(ob_engine* engine);

/* ------------------------------------------------------------------------- */
/* Audio export (added in ABI 1.17, EPIC-4)                                   */
/* ------------------------------------------------------------------------- */

/* Both are uncompressed 24-bit PCM. Bit depth is not offered: 24-bit is the
 * only answer that is right for a master, and a choice the user cannot judge
 * from the dialog is a choice not worth asking for. */
typedef enum ob_export_format {
  OB_EXPORT_FORMAT_WAV = 0,
  OB_EXPORT_FORMAT_AIFF = 1
} ob_export_format;

typedef enum ob_export_state {
  OB_EXPORT_IDLE = 0,
  OB_EXPORT_RUNNING = 1,
  OB_EXPORT_DONE = 2,
  OB_EXPORT_FAILED = 3,
  OB_EXPORT_CANCELLED = 4
} ob_export_state;

typedef struct ob_export_status {
  uint32_t struct_size; /* = sizeof(ob_export_status) */
  uint32_t state;       /* ob_export_state */
  float progress;       /* 0..1 */
  uint32_t reserved_;
  char path[512];  /* the file being written, or the one written */
  char error[256]; /* empty unless state == OB_EXPORT_FAILED */
} ob_export_status;

/* Main/UI thread. Never blocks: starts a background render and returns.
 *
 * The render goes through the same Engine::process the device calls, faster
 * than real time, from the start of the arrangement to its end plus a tail so
 * that releases and reverbs are not cut off. The audio device is stopped for
 * the duration and restarted afterwards — the transport is left where it was,
 * stopped — so nothing is audible while an export runs.
 *
 * `utf8_directory` is the folder to write into; the file is named after the
 * project with the format's extension, and an existing file of that name is
 * given a ` 2`, ` 3` suffix rather than being overwritten. `sample_rate` is the
 * rate of the file, which need not be the rate the engine is running at.
 *
 * Returns OB_ERR_ALREADY_RUNNING if an export is already in flight. Commands
 * posted with ob_engine_post_command are rejected while one is: the exporter
 * owns the transport until it is finished. */
OB_API ob_status ob_engine_export_start(ob_engine* engine, const char* utf8_directory,
                                        uint32_t format, int32_t sample_rate);

/* Main/UI thread. Never blocks. Poll once per frame while an export runs; the
 * terminal states (done, failed, cancelled) survive until the next start. */
OB_API ob_status ob_engine_export_status(ob_engine* engine, ob_export_status* out_status);

/* Main/UI thread. Never blocks. Asks the render to stop at the next block; the
 * partial file is deleted, and the state becomes OB_EXPORT_CANCELLED. */
OB_API ob_status ob_engine_export_cancel(ob_engine* engine);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ONEBEAT_ABI_H */
