# Error taxonomy

One table, two consumers: the engine returns the status code, the UI shows the
copy. FR-UX-12 asks that every error state what happened and what to do about
it — that is only achievable if the two live in the same place and change
together.

Status codes are defined in `engine/src/abi/onebeat_abi.h` (`ob_status`).

| Status | What happened | What the user is told | What they can do |
|---|---|---|---|
| `OB_OK` | — | — | — |
| `OB_ERR_INVALID_ARGUMENT` | A caller passed something the ABI rejects. | *(never shown — this is a bug in OneBeat)* | Report it; the session log has the detail. |
| `OB_ERR_OUT_OF_MEMORY` | Allocation failed while starting the engine. | "OneBeat ran out of memory while starting its audio engine." | Close other applications and try again. |
| `OB_ERR_DEVICE_UNAVAILABLE` | No output device, or the device refused to open. | "No output device is available. Connect an output device and try again." | Connect or select a device. |
| `OB_ERR_DEVICE_FORMAT_UNSUPPORTED` | The device rejected the requested rate or format. | "This device does not support 32-bit float output at the requested rate." | Choose a different sample rate. |
| `OB_ERR_ALREADY_RUNNING` | Start called on a running engine. | *(never shown)* | — |
| `OB_ERR_NOT_RUNNING` | An operation needed a running engine. | *(never shown)* | — |
| `OB_ERR_QUEUE_FULL` | The command queue is full — the engine is not draining. | *(never shown; the UI retries next frame)* | — |
| `OB_ERR_FILE_NOT_FOUND` | A sample file was missing. | "Could not open '<name>'. It may be missing or not a WAV file." | Check the file, or choose another. |
| `OB_ERR_FILE_UNSUPPORTED` | The file is not a format we can decode. | "'<name>' contains no audio." | Convert it to WAV (more formats arrive in v0.7). |
| `OB_ERR_INTERNAL` | Anything unexpected, including a caught exception. | "Something went wrong inside OneBeat's audio engine." | The session log path is shown; attach it to a report. |

## Rules

1. **Never show a status code to a user.** The code is for the log; the copy is
   for the person.
2. **Name the thing.** "Could not open 'kick.wav'" beats "Could not open file".
3. **Say what to do next**, even when the answer is "report this".
4. **Never blame the user** and never use an exclamation mark.
5. A failure the user cannot act on and did not cause does not get a dialog — it
   goes to the status bar and the session log.

## Where errors surface

- **Status bar** — device changes, recoverable problems, the last message from
  the engine event queue. Non-modal, does not steal focus.
- **Full-window failure state** — only when the app cannot function at all, e.g.
  the engine dylib is missing (`_EngineUnavailable` in `app/lib/main.dart`).
- **Session log** — everything, always:
  `~/Library/Application Support/OneBeat/logs/onebeat-<timestamp>.log`
  (inside the app sandbox container when running the bundled app).

## Session logs

- One file per session, the ten most recent kept.
- The audio thread never writes to it directly: it pushes POD records onto
  `rt::RtLog` and the housekeeping thread formats and writes them.
- A `session.running` marker file is written at startup and removed on a clean
  shutdown. Finding it at launch means the previous session died unexpectedly —
  Stage 3's auto-save recovery reads it (OB-3-06).
- Fatal signals flush the log before the process dies.
