# OB-2-04 — two-process audio IPC prototype

The measuring prototype behind [ADR-003](../../docs/adr/ADR-003-sandbox-ipc.md).
It answers one question with numbers instead of intuition: **can a sandboxed
plugin be called synchronously inside the audio callback, or must OneBeat
pipeline it and pay a block of latency?**

## Build

```
cmake -S spikes/ipc_roundtrip -B spikes/ipc_roundtrip/build -DCMAKE_BUILD_TYPE=Release
cmake --build spikes/ipc_roundtrip/build
```

Standalone — it links nothing from the engine, so what it measures is the IPC
mechanism and not OneBeat's DSP.

## Run

```
cd spikes/ipc_roundtrip/build
./ob204_host --backend mach_sem --seconds 600 --load 8 --csv /tmp/run.csv
```

| Option | Meaning |
|---|---|
| `--backend` | `spin`, `wait_on_address`, `posix_sem`, `mach_sem` |
| `--frames N` | block size (default 128, the ADR's budget case) |
| `--seconds N` | run length |
| `--load N` | spawn N competing CPU burners |
| `--kill-after N` | `SIGKILL` the helper N seconds in — the failure test |
| `--deadline-frac F` | fraction of the block period the host will wait (default 0.6) |
| `--csv PATH` | per-block round trip and callback cost |

`OB204_NO_RT=1` leaves the *helper* at default priority instead of giving it a
time-constraint policy. It exists to test one hypothesis; see FINDINGS.md.

## What it does

`ob204_host` paces itself with `mach_wait_until` at the block period CoreAudio
would use, on a thread with CoreAudio's time-constraint policy. Each block it
writes into a shared segment, signals `ob204_helper`, and waits under a
deadline. `ob204_helper` — the stand-in for the OB-2-05 sandboxed plugin host —
applies a trivial gain and signals back. The DSP is deliberately negligible so
the number reported is transport cost.

The exit status is non-zero if any callback overran its period.

## Reading the output

```
round-trip us: min=2.92 p50=3.92 p99=8.54 p99.9=10.75 max=13.12  (n=11250)
callback  us: p50=4.00 p99.9=10.83 max=13.29
misses=0 silent_blocks=0 overruns=0 helper_dead=no
```

- **round-trip** — signal sent → answer visible, per block.
- **callback** — the whole simulated callback, which is round trip plus the
  block copies. It is the number that must fit inside the period.
- **misses** — blocks where the helper did not answer before the deadline.
  Those blocks output silence.
- **overruns** — callbacks that exceeded the period. This is the xrun count and
  the number that must be zero.

## Results

[FINDINGS.md](FINDINGS.md).
