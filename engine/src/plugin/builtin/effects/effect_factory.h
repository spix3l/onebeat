// The built-in effect registry.
//
// One list, in one place, answering two questions the rest of the app keeps
// asking: what effects can the user insert (the browser needs names), and how
// do I build the one this project asked for (the mixer needs instances).
//
// Identifiers are frozen strings, not indices. A project stores the identifier,
// so reordering this list or dropping an effect must never silently load a
// different one — an identifier this build does not know produces a null
// instance and a visible "missing effect", exactly as an absent CLAP bundle
// does (FR-PLG-10).
#pragma once

#include <cstddef>
#include <memory>

#include "plugin/builtin/effects/effect_plugin.h"

namespace onebeat::plugin::builtin {

struct EffectDescriptor {
  const char* id = "";
  const char* name = "";
  // What it does, in one line, for the browser.
  const char* summary = "";
};

// The catalogue, in the order the browser should show it.
const EffectDescriptor* builtinEffects() noexcept;
size_t builtinEffectCount() noexcept;
const EffectDescriptor* findBuiltinEffect(const char* id) noexcept;

// Null when `id` names nothing this build ships. The caller reports a missing
// effect rather than substituting one.
std::unique_ptr<EffectPlugin> createBuiltinEffect(const char* id, PluginHost* host);

}  // namespace onebeat::plugin::builtin
