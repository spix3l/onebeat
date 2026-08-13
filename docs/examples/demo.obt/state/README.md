# `state/` — plugin state sidecars

In a real bundle this directory holds one opaque binary chunk per instrument,
each written by the plugin itself and referenced from `project.json` by
`state_ref`, with its SHA-256 in `state_sha256`.

OneBeat names them after the instrument's ID —
`ins_01K2QF8Z00KEYS000000000000.bin` — rather than after the instrument, because
two instruments called "Bass" are ordinary and a filename collision would have
one silently loading the other's settings. `state_ref` is a path, though, so a
file written by hand under any name loads and keeps that name until the plugin
next saves. This example still says `state/piano.bin` for exactly that reason:
it is a legal bundle that OneBeat did not write.

They are omitted here on purpose: the chunks are large, binary, third-party, and
would say nothing that [`../../../project-format.md`](../../../project-format.md)
§5.1 does not. The example exists to show the **text** the format produces.

A bundle whose sidecars are missing still loads — the instruments come up at
their defaults and the loss is reported. That is the same path a project takes
when a sidecar is lost to a bad sync.
