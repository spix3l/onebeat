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
#define OB_ABI_VERSION_MINOR 3
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
  OB_CMD_PLUGIN_PARAM_END = 13      /* i64_a = ParamId */
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
/* Main/UI thread. May block on filesystem and opaque plug-in state I/O. */
OB_API ob_status ob_engine_session_save(ob_engine* engine, const char* utf8_path);
OB_API ob_status ob_engine_session_load(ob_engine* engine, const char* utf8_path);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ONEBEAT_ABI_H */
