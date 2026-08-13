// The wire format between the scanner and the helper process (OB-2-03 §1).
//
// Both sides are built from this repository at the same commit, so this is not
// a compatibility surface and needs no versioning: `PluginDescriptor` crosses
// as raw bytes, exactly as `descriptor.h` intends. If the helper ever ships
// separately from the engine, that stops being true and this file grows a
// version field — but a helper that can disagree with its host about a struct
// layout is a bug waiting to happen, so the intent is that it never does.
//
// **The stream does not run over stdout.** The helper `dlopen`s third-party
// code, and third-party code prints: a licence warning on stdout during a
// static initialiser would sit in the middle of a descriptor and desynchronise
// the reader. The records go over a dedicated inherited descriptor
// (`ScanPipeFd`) instead, which leaves stdout and stderr free to be whatever
// the plugin makes of them.
#pragma once

#include <cstdint>
#include <type_traits>

#include "plugin/scan/descriptor.h"

namespace onebeat::plugin::scan {

// The fd the helper writes records to. 0/1/2 belong to the plugin; 3 is the
// first free one, and the parent dup2()s the pipe onto it.
inline constexpr int ScanPipeFd = 3;

enum class ScanRecordTag : uint32_t {
  // The helper is about to enter `phase`. Sent *before* the risky call, which
  // is the whole point: the parent learns where a crash happened by reading
  // the last phase that arrived before the pipe closed.
  Phase = 1,
  // One `PluginDescriptor`, verbatim.
  Descriptor = 2,
  // Probing finished. Its absence is what distinguishes a crash from a bundle
  // that legitimately contains nothing.
  Done = 3,
};

// Fixed 16 bytes, no padding, so the reader can consume a header without
// knowing what follows it.
struct ScanRecordHeader {
  uint32_t magic;
  uint32_t tag;   // ScanRecordTag
  uint32_t size;  // payload bytes following this header
  uint32_t reserved;
};

static_assert(sizeof(ScanRecordHeader) == 16, "the reader consumes exactly 16 bytes");
static_assert(std::has_unique_object_representations_v<ScanRecordHeader>,
              "written as raw bytes; padding would be uninitialised on the wire");

inline constexpr uint32_t ScanRecordMagic = 0x4E534250U;  // 'PBSN'

// The payload of a `Descriptor` record, and the reason this header includes
// `descriptor.h`: both sides size their buffers from this, and a reader that
// sees any other size for a descriptor record treats the stream as garbage.
inline constexpr uint32_t ScanDescriptorSize = sizeof(PluginDescriptor);

// A helper that gets this far without crashing still has to say so. Anything
// else — a signal, a non-zero exit, a closed pipe with no Done record — is a
// failure the parent classifies (see `SubprocessProbe`).
inline constexpr uint8_t ScanHelperExitOk = 0;

}  // namespace onebeat::plugin::scan
