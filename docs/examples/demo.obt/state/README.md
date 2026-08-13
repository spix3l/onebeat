# `state/` — plugin state sidecars

In a real bundle this directory holds one opaque binary chunk per instrument
(`piano.bin`, `bass.bin`, `lead.bin`, `pad.bin` for this example), each written
by the plugin itself and referenced from `project.json` by `state_ref`, with its
SHA-256 in `state_sha256`.

They are omitted here on purpose: the chunks are large, binary, third-party, and
would say nothing that [`../../../project-format.md`](../../../project-format.md)
§5.1 does not. The example exists to show the **text** the format produces.

A bundle whose sidecars are missing still loads — the instruments come up at
their defaults and the loss is reported. That is the same path a project takes
when a sidecar is lost to a bad sync.
