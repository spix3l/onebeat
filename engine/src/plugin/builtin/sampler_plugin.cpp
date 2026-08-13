#include "plugin/builtin/sampler_plugin.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace onebeat::plugin::builtin {
namespace {

// Frozen so a v0.2 project still loads in v0.9. A reader that meets an unknown
// version keeps the bytes and reports a load failure rather than guessing —
// FR-PLG-10's rule applies to our own plugins too.
constexpr uint32_t StateMagic = 0x4F425350U;  // 'OBSP'
constexpr uint32_t StateVersion = 1;

struct SamplerState {
  uint32_t magic;
  uint32_t version;
  double gain;
  double transpose;
};

ParamInfo makeGainInfo() noexcept {
  ParamInfo value;
  value.id = SamplerPlugin::ParamGain;
  value.name.assign("Gain");
  value.module.assign("/");
  value.min_value = 0.0;
  value.max_value = 2.0;
  value.default_value = 1.0;
  value.flags = ParamFlagIsAutomatable | ParamFlagIsModulatable;
  return value;
}

ParamInfo makeTransposeInfo() noexcept {
  ParamInfo value;
  value.id = SamplerPlugin::ParamTranspose;
  value.name.assign("Transpose");
  value.module.assign("/");
  value.min_value = -24.0;
  value.max_value = 24.0;
  value.default_value = 0.0;
  // Stepped: semitones only. Per-note modulation is deliberately *not*
  // advertised — the voice allocator has no per-voice pitch offset yet, and
  // claiming a capability we do not have is worse than lacking it.
  value.flags = ParamFlagIsAutomatable | ParamFlagIsModulatable | ParamFlagIsStepped;
  return value;
}

// Namespace scope, not function-local statics: a function-local static's
// thread-safe initialisation guard is a lock, and these are read from
// applyEvent() on the audio thread. Same reasoning as rt.cpp's GlobalTimebase —
// they are built when the library loads, long before an audio thread exists.
//
// The makers are `noexcept` because a static initialiser that throws terminates
// the process before main() with nowhere to catch it. ParamInfo is a POD with
// fixed-capacity text, so there is nothing here that could throw; saying so lets
// the compiler and clang-tidy hold us to it.
const ParamInfo GainParam = makeGainInfo();
const ParamInfo TransposeParam = makeTransposeInfo();

}  // namespace

SamplerPlugin::SamplerPlugin(PluginHost* host, rt::RtLog* log)
    : PluginInstance(host), sampler_(log) {}

// --------------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------------

bool SamplerPlugin::onConfigure(const ProcessSetup& setup) {
  if (setup.sample_rate <= 0.0 || setup.max_block_frames == 0) {
    return false;
  }
  // Every allocation the instance will ever perform happens here.
  sampler_.prepare(setup.sample_rate, static_cast<int>(setup.max_block_frames));
  tail_frames_ = static_cast<uint32_t>(core::Sampler::ReleaseSeconds * setup.sample_rate) + 1U;
  return true;
}

bool SamplerPlugin::onActivate() {
  return true;
}

void SamplerPlugin::onDeactivate() {
  sampler_.release();
}

void SamplerPlugin::reset() noexcept OB_NONBLOCKING {
  OB_ASSERT_AUDIO_THREAD();
  sampler_.reset();
  gain_.modulation = 0.0;
  transpose_.modulation = 0.0;
}

// --------------------------------------------------------------------------
// Processing
// --------------------------------------------------------------------------

void SamplerPlugin::applyEvent(const PluginEvent& event) noexcept OB_NONBLOCKING {
  switch (event.kind()) {
    case EventType::NoteOn: {
      const double semitones = transpose_.effective(TransposeParam);
      const auto key = static_cast<int16_t>(event.key + static_cast<int16_t>(semitones));
      const auto velocity = static_cast<float>(event.value() * gain_.effective(GainParam));
      sampler_.noteOn(key, velocity);
      break;
    }
    case EventType::NoteOff: {
      // A wildcarded key means every voice — the model's "all notes off".
      if (event.key == AnyKey) {
        sampler_.allNotesOff();
      } else {
        const double semitones = transpose_.effective(TransposeParam);
        sampler_.noteOff(static_cast<int16_t>(event.key + static_cast<int16_t>(semitones)));
      }
      break;
    }
    case EventType::NoteChoke:
      // No per-voice choke in the v0.1 allocator: a choke degrades to the
      // fastest release the sampler has. Documented in docs/clap-coverage.md
      // rather than silently equated with note-off.
      sampler_.allNotesOff();
      break;
    case EventType::ParamValue:
      if (event.id == ParamGain) {
        gain_.base = GainParam.clamp(event.value());
      } else if (event.id == ParamTranspose) {
        transpose_.base = TransposeParam.clamp(event.value());
      }
      break;
    case EventType::ParamModulation:
      // Never touches `base`: this is the whole point of the distinction.
      if (event.id == ParamGain) {
        gain_.modulation = event.value();
      } else if (event.id == ParamTranspose) {
        transpose_.modulation = event.value();
      }
      break;
    case EventType::None:
    case EventType::NoteEnd:
    case EventType::NoteExpression:
    case EventType::ParamGestureBegin:
    case EventType::ParamGestureEnd:
    case EventType::TransportDiscontinuity:
    case EventType::Midi1:
    case EventType::Midi2:
    case EventType::MidiSysex:
      break;
  }
}

ProcessStatus SamplerPlugin::process(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  OB_ASSERT_AUDIO_THREAD();
  if (block.audio_output_count == 0) {
    return ProcessStatus::Error;
  }

  const core::AudioBufferView& output = block.output(MainOutputPort);
  const EventListView& events = block.in_events;
  const uint32_t count = events.size();

  // Split the block at every event frame and render the gaps. This is exactly
  // the loop Engine::runSchedule used to run; moving it inside the instance is
  // what makes sample-accurate event timing a property of the *model* rather
  // than of one call site.
  uint32_t consumed = 0;
  uint32_t index = 0;
  while (consumed < block.frames) {
    uint32_t next = block.frames;
    if (index < count && events[index].time < block.frames) {
      next = events[index].time > consumed ? events[index].time : consumed;
    }
    if (next > consumed) {
      sampler_.render(output, static_cast<int>(consumed), static_cast<int>(next - consumed));
      consumed = next;
    }
    while (index < count && events[index].time <= consumed && events[index].time < block.frames) {
      applyEvent(events[index]);
      ++index;
    }
  }

  return sampler_.activeVoices() > 0 ? ProcessStatus::Continue : ProcessStatus::Sleep;
}

// --------------------------------------------------------------------------
// Parameters
// --------------------------------------------------------------------------

bool SamplerPlugin::paramInfo(uint32_t index, ParamInfo& out) const {
  OB_ASSERT_MAIN_THREAD();
  switch (index) {
    case 0:
      out = GainParam;
      return true;
    case 1:
      out = TransposeParam;
      return true;
    default:
      return false;
  }
}

bool SamplerPlugin::paramValue(ParamId param, double& out) const {
  OB_ASSERT_MAIN_THREAD();
  if (param == ParamGain) {
    out = gain_.base;  // the *base*: what the user set, never the modulated value
    return true;
  }
  if (param == ParamTranspose) {
    out = transpose_.base;
    return true;
  }
  return false;
}

bool SamplerPlugin::paramValueToText(ParamId param, double value, char* out,
                                     size_t out_size) const {
  OB_ASSERT_MAIN_THREAD();
  if (out == nullptr || out_size == 0) {
    return false;
  }
  if (param == ParamGain) {
    // dB rather than a linear coefficient: "0.71" means nothing to a musician
    // and "-3.0 dB" means something to everyone.
    if (value <= 0.0) {
      std::snprintf(out, out_size, "-inf dB");
    } else {
      std::snprintf(out, out_size, "%.1f dB", 20.0 * std::log10(value));
    }
    return true;
  }
  if (param == ParamTranspose) {
    std::snprintf(out, out_size, "%+d st", static_cast<int>(value));
    return true;
  }
  return false;
}

bool SamplerPlugin::paramTextToValue(ParamId param, const char* text, double& out) const {
  OB_ASSERT_MAIN_THREAD();
  if (text == nullptr) {
    return false;
  }
  char* end = nullptr;
  const double parsed = std::strtod(text, &end);
  if (end == text) {
    return false;
  }
  if (param == ParamGain) {
    out = GainParam.clamp(std::pow(10.0, parsed / 20.0));
    return true;
  }
  if (param == ParamTranspose) {
    out = TransposeParam.clamp(std::trunc(parsed));
    return true;
  }
  return false;
}

void SamplerPlugin::paramsFlush(const EventListView& in, EventList* /*out*/) {
  OB_ASSERT_MAIN_THREAD();
  // Legal only while process() is not running — that is the contract that makes
  // touching these fields here safe without a lock.
  for (const PluginEvent& event : in) {
    if (event.kind() == EventType::ParamValue || event.kind() == EventType::ParamModulation) {
      applyEvent(event);
    }
  }
}

// --------------------------------------------------------------------------
// Ports
// --------------------------------------------------------------------------

uint32_t SamplerPlugin::audioPortCount(PortDirection direction) const {
  // One stereo output, no audio input. The plural interface is not decoration:
  // FR-PLG-12 multi-out drum kits report several here, and nothing above needs
  // to change to accommodate them.
  return direction == PortDirection::Output ? 1U : 0U;
}

bool SamplerPlugin::audioPortInfo(PortDirection direction, uint32_t index,
                                  AudioPortInfo& out) const {
  if (direction != PortDirection::Output || index != 0) {
    return false;
  }
  out = AudioPortInfo{};
  out.id = MainOutputPort;
  out.name.assign("Main");
  out.channel_count = 2;
  out.layout = ChannelLayout::Stereo;
  out.is_main = true;
  return true;
}

uint32_t SamplerPlugin::notePortCount(PortDirection direction) const {
  return direction == PortDirection::Input ? 1U : 0U;
}

bool SamplerPlugin::notePortInfo(PortDirection direction, uint32_t index, NotePortInfo& out) const {
  if (direction != PortDirection::Input || index != 0) {
    return false;
  }
  out = NotePortInfo{};
  out.id = NoteInputPort;
  out.name.assign("Notes");
  out.supported_dialects = NoteDialectClap | NoteDialectMidi;
  out.preferred_dialect = NoteDialectClap;
  return true;
}

// --------------------------------------------------------------------------
// State
// --------------------------------------------------------------------------

bool SamplerPlugin::saveState(StateWriter& writer) const {
  OB_ASSERT_MAIN_THREAD();
  // Base values only. Modulation is transient by definition — persisting it
  // would make a project reopen with an offset nobody applied.
  const SamplerState state{StateMagic, StateVersion, gain_.base, transpose_.base};
  return writer.write(&state, sizeof(state));
}

bool SamplerPlugin::loadState(StateReader& reader) {
  OB_ASSERT_MAIN_THREAD();
  SamplerState state{};
  if (reader.read(&state, sizeof(state)) != sizeof(state)) {
    return false;
  }
  if (state.magic != StateMagic || state.version > StateVersion) {
    return false;
  }
  gain_.base = GainParam.clamp(state.gain);
  transpose_.base = TransposeParam.clamp(state.transpose);
  gain_.modulation = 0.0;
  transpose_.modulation = 0.0;
  return true;
}

}  // namespace onebeat::plugin::builtin
