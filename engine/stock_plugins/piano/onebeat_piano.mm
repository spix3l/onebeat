// OneBeat Piano — a compact, sample-free stock instrument shipped as CLAP.
// The DSP and editor deliberately use only the public CLAP surface: the stock
// instrument is exercised through exactly the same host path as third-party
// plug-ins.
#include <clap/clap.h>

#import <AppKit/AppKit.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

namespace {

constexpr double Pi = 3.14159265358979323846;
constexpr double TwoPi = Pi * 2.0;
constexpr uint32_t VoiceCount = 32;
constexpr uint32_t DelaySize = 32768;

enum ParamId : clap_id {
  Tone = 100,
  Body = 101,
  Decay = 102,
  Release = 103,
  Room = 104,
  Width = 105,
  Output = 106,
};

struct ParamSpec {
  clap_id id;
  const char* name;
  const char* module;
  double default_value;
};

constexpr std::array<ParamSpec, 7> Specs{{
    {Tone, "Tone", "Piano", 0.56},       {Body, "Body", "Piano", 0.62},
    {Decay, "Decay", "Envelope", 0.58}, {Release, "Release", "Envelope", 0.42},
    {Room, "Room", "Space", 0.24},      {Width, "Width", "Space", 0.68},
    {Output, "Output", "Master", 0.72},
}};

size_t paramIndex(clap_id id) {
  for (size_t index = 0; index < Specs.size(); ++index) {
    if (Specs[index].id == id) return index;
  }
  return Specs.size();
}

double clamp01(double value) {
  return std::clamp(value, 0.0, 1.0);
}

struct Voice {
  bool active = false;
  bool released = false;
  int16_t note_id = -1;
  int16_t channel = 0;
  int16_t key = 60;
  double frequency = 261.625565;
  double phase = 0.0;
  double envelope = 0.0;
  double age = 0.0;
  double velocity = 0.0;
  uint32_t noise = 1;
};

struct UiNote {
  int16_t key = 60;
  bool on = false;
};

struct Piano {
  clap_plugin_t plugin{};
  const clap_host_t* host = nullptr;
  double sample_rate = 48000.0;
  std::array<std::atomic<double>, Specs.size()> params{};
  std::array<Voice, VoiceCount> voices{};
  std::array<float, DelaySize> delay_left{};
  std::array<float, DelaySize> delay_right{};
  uint32_t delay_cursor = 0;
  std::array<UiNote, 64> ui_notes{};
  std::atomic<uint32_t> ui_write{0};
  std::atomic<uint32_t> ui_read{0};
  NSView* editor = nil;
  bool gui_created = false;

  explicit Piano(const clap_host_t* clap_host) : host(clap_host) {
    for (size_t index = 0; index < Specs.size(); ++index) {
      params[index].store(Specs[index].default_value, std::memory_order_relaxed);
    }
  }

  double value(clap_id id) const {
    const size_t index = paramIndex(id);
    return index < Specs.size() ? params[index].load(std::memory_order_relaxed) : 0.0;
  }

  void setValue(clap_id id, double value) {
    const size_t index = paramIndex(id);
    if (index < Specs.size()) params[index].store(clamp01(value), std::memory_order_relaxed);
  }

  void queueUiNote(int key, bool on) {
    const uint32_t write = ui_write.load(std::memory_order_relaxed);
    const uint32_t next = (write + 1U) % static_cast<uint32_t>(ui_notes.size());
    if (next == ui_read.load(std::memory_order_acquire)) return;
    ui_notes[write] = UiNote{static_cast<int16_t>(key), on};
    ui_write.store(next, std::memory_order_release);
    if (host != nullptr && host->request_process != nullptr) host->request_process(host);
  }
};

Piano& self(const clap_plugin_t* plugin) {
  return *static_cast<Piano*>(plugin->plugin_data);
}

double midiFrequency(int key) {
  return 440.0 * std::pow(2.0, (static_cast<double>(key) - 69.0) / 12.0);
}

void noteOn(Piano& piano, int note_id, int channel, int key, double velocity) {
  Voice* selected = nullptr;
  for (Voice& voice : piano.voices) {
    if (!voice.active) {
      selected = &voice;
      break;
    }
    if (selected == nullptr || voice.envelope < selected->envelope) selected = &voice;
  }
  if (selected == nullptr) return;
  selected->active = true;
  selected->released = false;
  selected->note_id = static_cast<int16_t>(note_id);
  selected->channel = static_cast<int16_t>(channel);
  selected->key = static_cast<int16_t>(key);
  selected->frequency = midiFrequency(key);
  selected->phase = 0.0;
  selected->envelope = 0.0001;
  selected->age = 0.0;
  selected->velocity = std::clamp(velocity, 0.0, 1.0);
  selected->noise = static_cast<uint32_t>(key) * 2654435761U ^ 0x9e3779b9U;
}

bool voiceMatches(const Voice& voice, int note_id, int channel, int key) {
  if (!voice.active) return false;
  if (note_id >= 0 && voice.note_id != note_id) return false;
  if (channel >= 0 && voice.channel != channel) return false;
  return key < 0 || voice.key == key;
}

void noteOff(Piano& piano, int note_id, int channel, int key, bool choke) {
  for (Voice& voice : piano.voices) {
    if (!voiceMatches(voice, note_id, channel, key)) continue;
    if (choke) {
      voice.active = false;
      voice.envelope = 0.0;
    } else {
      voice.released = true;
    }
  }
}

void handleEvent(Piano& piano, const clap_event_header_t* header) {
  if (header == nullptr || header->space_id != CLAP_CORE_EVENT_SPACE_ID) return;
  if (header->type == CLAP_EVENT_NOTE_ON) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    noteOn(piano, note->note_id, note->channel, note->key, note->velocity);
  } else if (header->type == CLAP_EVENT_NOTE_OFF || header->type == CLAP_EVENT_NOTE_CHOKE) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    noteOff(piano, note->note_id, note->channel, note->key,
            header->type == CLAP_EVENT_NOTE_CHOKE);
  } else if (header->type == CLAP_EVENT_PARAM_VALUE) {
    const auto* event = reinterpret_cast<const clap_event_param_value_t*>(header);
    piano.setValue(event->param_id, event->value);
  } else if (header->type == CLAP_EVENT_MIDI) {
    const auto* midi = reinterpret_cast<const clap_event_midi_t*>(header);
    const uint8_t status = midi->data[0] & 0xf0U;
    const int channel = midi->data[0] & 0x0fU;
    const int key = midi->data[1] & 0x7fU;
    const int velocity = midi->data[2] & 0x7fU;
    if (status == 0x90U && velocity > 0) {
      noteOn(piano, -1, channel, key, static_cast<double>(velocity) / 127.0);
    } else if (status == 0x80U || (status == 0x90U && velocity == 0)) {
      noteOff(piano, -1, channel, key, false);
    }
  }
}

void drainUiNotes(Piano& piano) {
  uint32_t read = piano.ui_read.load(std::memory_order_relaxed);
  const uint32_t write = piano.ui_write.load(std::memory_order_acquire);
  while (read != write) {
    const UiNote event = piano.ui_notes[read];
    if (event.on) {
      noteOn(piano, -1, 0, event.key, 0.78);
    } else {
      noteOff(piano, -1, 0, event.key, false);
    }
    read = (read + 1U) % static_cast<uint32_t>(piano.ui_notes.size());
  }
  piano.ui_read.store(read, std::memory_order_release);
}

bool pluginInit(const clap_plugin_t*) { return true; }
void pluginDestroy(const clap_plugin_t* plugin) { delete &self(plugin); }
bool pluginActivate(const clap_plugin_t* plugin, double sample_rate, uint32_t, uint32_t) {
  self(plugin).sample_rate = std::clamp(sample_rate, 8000.0, 192000.0);
  return true;
}
void pluginDeactivate(const clap_plugin_t*) {}
bool pluginStart(const clap_plugin_t*) { return true; }
void pluginStop(const clap_plugin_t*) {}
void pluginReset(const clap_plugin_t* plugin) {
  Piano& piano = self(plugin);
  for (Voice& voice : piano.voices) voice = Voice{};
  piano.delay_left.fill(0.0F);
  piano.delay_right.fill(0.0F);
  piano.delay_cursor = 0;
}

clap_process_status pluginProcess(const clap_plugin_t* plugin, const clap_process_t* process) {
  Piano& piano = self(plugin);
  if (process->audio_outputs_count == 0 || process->audio_outputs[0].data32 == nullptr) {
    return CLAP_PROCESS_CONTINUE;
  }
  clap_audio_buffer_t& output = process->audio_outputs[0];
  if (output.channel_count == 0 || output.data32[0] == nullptr) return CLAP_PROCESS_CONTINUE;

  drainUiNotes(piano);
  uint32_t event_index = 0;
  const uint32_t event_count = process->in_events != nullptr
                                   ? process->in_events->size(process->in_events)
                                   : 0U;
  const double tone = piano.value(Tone);
  const double body = piano.value(Body);
  const double decay_seconds = 0.7 + piano.value(Decay) * 7.3;
  const double release_seconds = 0.05 + piano.value(Release) * 2.2;
  const double room = piano.value(Room);
  const double width = piano.value(Width);
  const double output_gain = piano.value(Output) * 0.72;
  const double natural_decay = std::exp(-1.0 / (piano.sample_rate * decay_seconds));
  const double release_decay = std::exp(-1.0 / (piano.sample_rate * release_seconds));
  const uint32_t room_offset = static_cast<uint32_t>(piano.sample_rate * 0.071) % DelaySize;

  for (uint32_t frame = 0; frame < process->frames_count; ++frame) {
    while (event_index < event_count) {
      const clap_event_header_t* event = process->in_events->get(process->in_events, event_index);
      if (event == nullptr || event->time > frame) break;
      handleEvent(piano, event);
      ++event_index;
    }

    double left = 0.0;
    double right = 0.0;
    for (Voice& voice : piano.voices) {
      if (!voice.active) continue;
      voice.age += 1.0 / piano.sample_rate;
      if (voice.age < 0.006) {
        voice.envelope = std::min(1.0, voice.envelope + 1.0 / (piano.sample_rate * 0.006));
      } else {
        voice.envelope *= voice.released ? release_decay : natural_decay;
      }
      if (voice.envelope < 0.00004 || voice.age > 24.0) {
        voice.active = false;
        continue;
      }

      const double brightness = 0.14 + tone * 0.62 + voice.velocity * 0.18;
      const double fundamental = std::sin(voice.phase);
      const double second = std::sin(voice.phase * 2.006) * (0.18 + body * 0.20);
      const double third = std::sin(voice.phase * 3.018) * brightness * 0.16;
      const double fourth = std::sin(voice.phase * 4.041) * brightness * brightness * 0.08;
      voice.noise = voice.noise * 1664525U + 1013904223U;
      const double noise = (static_cast<double>((voice.noise >> 9U) & 0x7fffffU) / 4194304.0 - 1.0) *
                           std::exp(-voice.age * (18.0 - tone * 8.0)) * (0.02 + tone * 0.035);
      const double sample = (fundamental + second + third + fourth + noise) * voice.envelope *
                            (0.08 + voice.velocity * voice.velocity * 0.22);
      const double pan = std::clamp((static_cast<double>(voice.key) - 60.0) / 38.0, -1.0, 1.0) *
                         width * 0.72;
      left += sample * std::sqrt((1.0 - pan) * 0.5);
      right += sample * std::sqrt((1.0 + pan) * 0.5);
      voice.phase += TwoPi * voice.frequency / piano.sample_rate;
      if (voice.phase >= TwoPi) voice.phase -= TwoPi;
    }

    const uint32_t tap = (piano.delay_cursor + DelaySize - room_offset) % DelaySize;
    const double wet_left = static_cast<double>(piano.delay_left[tap]);
    const double wet_right = static_cast<double>(piano.delay_right[tap]);
    piano.delay_left[piano.delay_cursor] = static_cast<float>(left + wet_right * 0.36);
    piano.delay_right[piano.delay_cursor] = static_cast<float>(right + wet_left * 0.36);
    piano.delay_cursor = (piano.delay_cursor + 1U) % DelaySize;
    left = (left + wet_left * room * 0.55) * output_gain;
    right = (right + wet_right * room * 0.55) * output_gain;
    output.data32[0][frame] = static_cast<float>(std::tanh(left));
    if (output.channel_count > 1 && output.data32[1] != nullptr) {
      output.data32[1][frame] = static_cast<float>(std::tanh(right));
    }
    for (uint32_t channel = 2; channel < output.channel_count; ++channel) {
      if (output.data32[channel] != nullptr) output.data32[channel][frame] = 0.0F;
    }
  }
  return CLAP_PROCESS_CONTINUE;
}

uint32_t paramsCount(const clap_plugin_t*) { return static_cast<uint32_t>(Specs.size()); }
bool paramsGetInfo(const clap_plugin_t*, uint32_t index, clap_param_info_t* info) {
  if (index >= Specs.size() || info == nullptr) return false;
  *info = {};
  info->id = Specs[index].id;
  info->flags = CLAP_PARAM_IS_AUTOMATABLE | CLAP_PARAM_IS_MODULATABLE;
  std::strncpy(info->name, Specs[index].name, sizeof(info->name) - 1);
  std::strncpy(info->module, Specs[index].module, sizeof(info->module) - 1);
  info->min_value = 0.0;
  info->max_value = 1.0;
  info->default_value = Specs[index].default_value;
  return true;
}
bool paramsGetValue(const clap_plugin_t* plugin, clap_id id, double* value) {
  if (paramIndex(id) >= Specs.size() || value == nullptr) return false;
  *value = self(plugin).value(id);
  return true;
}
bool paramsValueToText(const clap_plugin_t*, clap_id id, double value, char* display,
                       uint32_t size) {
  if (paramIndex(id) >= Specs.size() || display == nullptr || size == 0) return false;
  std::snprintf(display, size, "%d %%", static_cast<int>(std::lround(clamp01(value) * 100.0)));
  return true;
}
bool paramsTextToValue(const clap_plugin_t*, clap_id id, const char* display, double* value) {
  if (paramIndex(id) >= Specs.size() || display == nullptr || value == nullptr) return false;
  *value = clamp01(std::strtod(display, nullptr) / 100.0);
  return true;
}
void paramsFlush(const clap_plugin_t* plugin, const clap_input_events_t* input,
                 const clap_output_events_t*) {
  if (input == nullptr) return;
  for (uint32_t index = 0; index < input->size(input); ++index) handleEvent(self(plugin), input->get(input, index));
}
const clap_plugin_params_t Params{paramsCount, paramsGetInfo, paramsGetValue, paramsValueToText,
                                  paramsTextToValue, paramsFlush};

uint32_t audioCount(const clap_plugin_t*, bool input) { return input ? 0U : 1U; }
bool audioGet(const clap_plugin_t*, uint32_t index, bool input, clap_audio_port_info_t* info) {
  if (input || index != 0 || info == nullptr) return false;
  *info = {};
  info->id = 0;
  std::strncpy(info->name, "Main Output", sizeof(info->name) - 1);
  info->flags = CLAP_AUDIO_PORT_IS_MAIN;
  info->channel_count = 2;
  info->port_type = CLAP_PORT_STEREO;
  info->in_place_pair = CLAP_INVALID_ID;
  return true;
}
const clap_plugin_audio_ports_t AudioPorts{audioCount, audioGet};

uint32_t noteCount(const clap_plugin_t*, bool input) { return input ? 1U : 0U; }
bool noteGet(const clap_plugin_t*, uint32_t index, bool input, clap_note_port_info_t* info) {
  if (!input || index != 0 || info == nullptr) return false;
  *info = {};
  info->id = 0;
  info->supported_dialects = CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI;
  info->preferred_dialect = CLAP_NOTE_DIALECT_CLAP;
  std::strncpy(info->name, "Piano", sizeof(info->name) - 1);
  return true;
}
const clap_plugin_note_ports_t NotePorts{noteCount, noteGet};

struct SavedState {
  uint32_t magic = 0x4f42504eU;
  uint32_t version = 1;
  std::array<double, Specs.size()> values{};
};

bool writeAll(const clap_ostream_t* stream, const void* data, uint64_t size) {
  const auto* bytes = static_cast<const uint8_t*>(data);
  uint64_t offset = 0;
  while (offset < size) {
    const int64_t written = stream->write(stream, bytes + offset, size - offset);
    if (written <= 0) return false;
    offset += static_cast<uint64_t>(written);
  }
  return true;
}
bool readAll(const clap_istream_t* stream, void* data, uint64_t size) {
  auto* bytes = static_cast<uint8_t*>(data);
  uint64_t offset = 0;
  while (offset < size) {
    const int64_t read = stream->read(stream, bytes + offset, size - offset);
    if (read <= 0) return false;
    offset += static_cast<uint64_t>(read);
  }
  return true;
}
bool stateSave(const clap_plugin_t* plugin, const clap_ostream_t* stream) {
  SavedState state;
  for (size_t index = 0; index < Specs.size(); ++index) state.values[index] = self(plugin).value(Specs[index].id);
  return writeAll(stream, &state, sizeof(state));
}
bool stateLoad(const clap_plugin_t* plugin, const clap_istream_t* stream) {
  SavedState state;
  if (!readAll(stream, &state, sizeof(state)) || state.magic != 0x4f42504eU || state.version != 1) return false;
  for (size_t index = 0; index < Specs.size(); ++index) self(plugin).setValue(Specs[index].id, state.values[index]);
  return true;
}
const clap_plugin_state_t State{stateSave, stateLoad};

uint32_t latencyGet(const clap_plugin_t*) { return 0; }
const clap_plugin_latency_t Latency{latencyGet};

uint32_t tailGet(const clap_plugin_t* plugin) {
  return static_cast<uint32_t>(self(plugin).sample_rate * 3.0);
}
const clap_plugin_tail_t Tail{tailGet};

NSColor* color(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
  return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

}  // namespace

@interface OneBeatPianoView : NSView {
 @private
  Piano* _piano;
  NSInteger _draggedKnob;
  CGFloat _dragOriginY;
  double _dragOriginValue;
  NSInteger _heldKey;
}
- (instancetype)initWithPiano:(Piano*)piano;
- (NSDictionary<NSAttributedStringKey, id>*)textStyle:(CGFloat)size
                                                color:(NSColor*)textColor
                                               weight:(NSFontWeight)weight;
- (NSRect)knobRect:(NSInteger)index;
- (void)drawKnob:(NSInteger)index spec:(const ParamSpec&)spec;
- (NSInteger)keyAtPoint:(NSPoint)point;
@end

@implementation OneBeatPianoView

- (instancetype)initWithPiano:(Piano*)piano {
  self = [super initWithFrame:NSMakeRect(0, 0, 760, 500)];
  if (self != nil) {
    _piano = piano;
    _draggedKnob = -1;
    _heldKey = -1;
    [self setWantsLayer:YES];
  }
  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSDictionary<NSAttributedStringKey, id>*)textStyle:(CGFloat)size
                                                color:(NSColor*)textColor
                                               weight:(NSFontWeight)weight {
  NSFont* font = [NSFont fontWithName:@"Archivo" size:size];
  if (font == nil) font = [NSFont systemFontOfSize:size weight:weight];
  return @{NSFontAttributeName : font, NSForegroundColorAttributeName : textColor};
}

- (NSRect)knobRect:(NSInteger)index {
  const CGFloat x = 70.0 + static_cast<CGFloat>(index) * 104.0;
  return NSMakeRect(x, 178, 64, 64);
}

- (void)drawKnob:(NSInteger)index spec:(const ParamSpec&)spec {
  const NSRect rect = [self knobRect:index];
  const double value = _piano->value(spec.id);
  [color(0.165, 0.173, 0.157) setFill];
  [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
  [color(0.23, 0.24, 0.216) setStroke];
  NSBezierPath* rim = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 0.5, 0.5)];
  [rim setLineWidth:1.0];
  [rim stroke];

  const CGFloat angle = static_cast<CGFloat>((-135.0 + value * 270.0) * Pi / 180.0);
  const NSPoint centre = NSMakePoint(NSMidX(rect), NSMidY(rect));
  NSBezierPath* marker = [NSBezierPath bezierPath];
  [marker moveToPoint:NSMakePoint(centre.x + std::cos(angle) * 16.0,
                                  centre.y + std::sin(angle) * 16.0)];
  [marker lineToPoint:NSMakePoint(centre.x + std::cos(angle) * 27.0,
                                  centre.y + std::sin(angle) * 27.0)];
  [color(0.486, 0.424, 0.941) setStroke];
  [marker setLineWidth:3.0];
  [marker setLineCapStyle:NSLineCapStyleRound];
  [marker stroke];

  NSString* label = [NSString stringWithUTF8String:spec.name];
  NSDictionary* labelStyle = [self textStyle:11 color:color(0.60, 0.616, 0.58) weight:NSFontWeightMedium];
  const NSSize labelSize = [label sizeWithAttributes:labelStyle];
  [label drawAtPoint:NSMakePoint(NSMidX(rect) - labelSize.width / 2.0, NSMaxY(rect) + 12.0)
       withAttributes:labelStyle];
  NSString* amount = [NSString stringWithFormat:@"%02d", static_cast<int>(std::lround(value * 100.0))];
  NSDictionary* amountStyle = [self textStyle:10 color:color(0.91, 0.914, 0.894) weight:NSFontWeightMedium];
  const NSSize amountSize = [amount sizeWithAttributes:amountStyle];
  [amount drawAtPoint:NSMakePoint(NSMidX(rect) - amountSize.width / 2.0, NSMidY(rect) - amountSize.height / 2.0)
        withAttributes:amountStyle];
}

- (NSInteger)keyAtPoint:(NSPoint)point {
  const NSRect keyboard = NSMakeRect(28, 332, 704, 136);
  if (!NSPointInRect(point, keyboard)) return -1;
  constexpr int WhiteKeys = 14;
  const CGFloat whiteWidth = keyboard.size.width / WhiteKeys;
  const int white = std::clamp(static_cast<int>((point.x - keyboard.origin.x) / whiteWidth), 0, WhiteKeys - 1);
  constexpr int whiteOffsets[7] = {0, 2, 4, 5, 7, 9, 11};
  int key = 48 + (white / 7) * 12 + whiteOffsets[white % 7];
  if (point.y < keyboard.origin.y + 82) {
    for (int candidate = 0; candidate < WhiteKeys - 1; ++candidate) {
      const int step = candidate % 7;
      if (step == 2 || step == 6) continue;
      const CGFloat centre = keyboard.origin.x + (candidate + 1) * whiteWidth;
      if (std::abs(point.x - centre) < whiteWidth * 0.29) {
        key = 49 + (candidate / 7) * 12 + whiteOffsets[candidate % 7];
        break;
      }
    }
  }
  return key;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [color(0.075, 0.078, 0.071) setFill];
  NSRectFill(self.bounds);

  [color(0.114, 0.122, 0.11) setFill];
  NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 58));
  [color(0.227, 0.239, 0.216) setFill];
  NSRectFill(NSMakeRect(0, 57, self.bounds.size.width, 1));
  [@"ONEBEAT" drawAtPoint:NSMakePoint(28, 20)
             withAttributes:[self textStyle:12 color:color(0.91, 0.914, 0.894) weight:NSFontWeightSemibold]];
  [@"STOCK INSTRUMENT / 01" drawAtPoint:NSMakePoint(110, 21)
                          withAttributes:[self textStyle:10 color:color(0.60, 0.616, 0.58) weight:NSFontWeightMedium]];
  NSString* voiceText = [NSString stringWithFormat:@"%u VOICES", VoiceCount];
  NSDictionary* metaStyle = [self textStyle:10 color:color(0.60, 0.616, 0.58) weight:NSFontWeightMedium];
  [voiceText drawAtPoint:NSMakePoint(self.bounds.size.width - 82, 21) withAttributes:metaStyle];

  [@"PIANO" drawAtPoint:NSMakePoint(28, 79)
           withAttributes:[self textStyle:34 color:color(0.91, 0.914, 0.894) weight:NSFontWeightSemibold]];
  [@"A compact, responsive piano for sketching the first idea." drawAtPoint:NSMakePoint(31, 122)
      withAttributes:[self textStyle:12 color:color(0.60, 0.616, 0.58) weight:NSFontWeightRegular]];
  [color(0.486, 0.424, 0.941) setFill];
  NSRectFill(NSMakeRect(31, 151, 102, 2));
  [color(0.227, 0.239, 0.216) setFill];
  NSRectFill(NSMakeRect(145, 151, self.bounds.size.width - 176, 1));

  for (NSInteger index = 0; index < static_cast<NSInteger>(Specs.size()); ++index) {
    [self drawKnob:index spec:Specs[static_cast<size_t>(index)]];
  }

  [@"PLAYABLE RANGE  C3 — B4" drawAtPoint:NSMakePoint(28, 304) withAttributes:metaStyle];
  [@"CLICK KEYS TO AUDITION" drawAtPoint:NSMakePoint(592, 304) withAttributes:metaStyle];

  const NSRect keyboard = NSMakeRect(28, 332, 704, 136);
  constexpr int WhiteKeys = 14;
  const CGFloat whiteWidth = keyboard.size.width / WhiteKeys;
  constexpr int whiteOffsets[7] = {0, 2, 4, 5, 7, 9, 11};
  for (int index = 0; index < WhiteKeys; ++index) {
    const int key = 48 + (index / 7) * 12 + whiteOffsets[index % 7];
    NSRect rect = NSMakeRect(keyboard.origin.x + index * whiteWidth, keyboard.origin.y,
                             whiteWidth - 1, keyboard.size.height);
    [(key == _heldKey ? color(0.78, 0.75, 0.93) : color(0.88, 0.89, 0.85)) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2] fill];
  }
  for (int index = 0; index < WhiteKeys - 1; ++index) {
    const int step = index % 7;
    if (step == 2 || step == 6) continue;
    const int key = 49 + (index / 7) * 12 + whiteOffsets[index % 7];
    NSRect rect = NSMakeRect(keyboard.origin.x + (index + 1) * whiteWidth - whiteWidth * 0.29,
                             keyboard.origin.y, whiteWidth * 0.58, 82);
    [(key == _heldKey ? color(0.486, 0.424, 0.941) : color(0.075, 0.078, 0.071)) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2] fill];
  }
}

- (void)mouseDown:(NSEvent*)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  for (NSInteger index = 0; index < static_cast<NSInteger>(Specs.size()); ++index) {
    if (NSPointInRect(point, NSInsetRect([self knobRect:index], -10, -10))) {
      _draggedKnob = index;
      _dragOriginY = point.y;
      _dragOriginValue = _piano->value(Specs[static_cast<size_t>(index)].id);
      return;
    }
  }
  const NSInteger key = [self keyAtPoint:point];
  if (key >= 0) {
    _heldKey = key;
    _piano->queueUiNote(static_cast<int>(key), true);
    [self setNeedsDisplay:YES];
  }
}

- (void)mouseDragged:(NSEvent*)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (_draggedKnob >= 0) {
    const ParamSpec& spec = Specs[static_cast<size_t>(_draggedKnob)];
    _piano->setValue(spec.id, _dragOriginValue + static_cast<double>(_dragOriginY - point.y) / 160.0);
    [self setNeedsDisplay:YES];
    return;
  }
  if (_heldKey >= 0) {
    const NSInteger key = [self keyAtPoint:point];
    if (key >= 0 && key != _heldKey) {
      _piano->queueUiNote(static_cast<int>(_heldKey), false);
      _heldKey = key;
      _piano->queueUiNote(static_cast<int>(_heldKey), true);
      [self setNeedsDisplay:YES];
    }
  }
}

- (void)mouseUp:(NSEvent*)event {
  (void)event;
  _draggedKnob = -1;
  if (_heldKey >= 0) {
    _piano->queueUiNote(static_cast<int>(_heldKey), false);
    _heldKey = -1;
    [self setNeedsDisplay:YES];
  }
}
@end

namespace {

bool guiIsApiSupported(const clap_plugin_t*, const char* api, bool floating) {
  return !floating && api != nullptr && std::strcmp(api, CLAP_WINDOW_API_COCOA) == 0;
}
bool guiGetPreferredApi(const clap_plugin_t*, const char** api, bool* floating) {
  if (api == nullptr || floating == nullptr) return false;
  *api = CLAP_WINDOW_API_COCOA;
  *floating = false;
  return true;
}
bool guiCreate(const clap_plugin_t* plugin, const char* api, bool floating) {
  if (!guiIsApiSupported(plugin, api, floating)) return false;
  Piano& piano = self(plugin);
  if (piano.gui_created) return false;
  piano.editor = [[OneBeatPianoView alloc] initWithPiano:&piano];
  piano.gui_created = piano.editor != nil;
  return piano.gui_created;
}
void guiDestroy(const clap_plugin_t* plugin) {
  Piano& piano = self(plugin);
  [piano.editor removeFromSuperview];
  [piano.editor release];
  piano.editor = nil;
  piano.gui_created = false;
}
bool guiSetScale(const clap_plugin_t*, double) { return false; }
bool guiGetSize(const clap_plugin_t*, uint32_t* width, uint32_t* height) {
  if (width == nullptr || height == nullptr) return false;
  *width = 760;
  *height = 500;
  return true;
}
bool guiCanResize(const clap_plugin_t*) { return false; }
bool guiGetResizeHints(const clap_plugin_t*, clap_gui_resize_hints_t*) { return false; }
bool guiAdjustSize(const clap_plugin_t*, uint32_t* width, uint32_t* height) {
  if (width == nullptr || height == nullptr) return false;
  *width = 760;
  *height = 500;
  return true;
}
bool guiSetSize(const clap_plugin_t*, uint32_t width, uint32_t height) {
  return width == 760 && height == 500;
}
bool guiSetParent(const clap_plugin_t* plugin, const clap_window_t* window) {
  Piano& piano = self(plugin);
  if (window == nullptr || window->cocoa == nullptr || piano.editor == nil) return false;
  NSView* parent = static_cast<NSView*>(window->cocoa);
  [piano.editor setFrame:NSMakeRect(0, 0, 760, 500)];
  [piano.editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [parent addSubview:piano.editor];
  return true;
}
bool guiSetTransient(const clap_plugin_t*, const clap_window_t*) { return false; }
void guiSuggestTitle(const clap_plugin_t*, const char*) {}
bool guiShow(const clap_plugin_t* plugin) {
  [self(plugin).editor setHidden:NO];
  return self(plugin).editor != nil;
}
bool guiHide(const clap_plugin_t* plugin) {
  [self(plugin).editor setHidden:YES];
  return self(plugin).editor != nil;
}
[[maybe_unused]] const clap_plugin_gui_t Gui{guiIsApiSupported, guiGetPreferredApi, guiCreate, guiDestroy,
                            guiSetScale, guiGetSize, guiCanResize, guiGetResizeHints,
                            guiAdjustSize, guiSetSize, guiSetParent, guiSetTransient,
                            guiSuggestTitle, guiShow, guiHide};

const void* pluginExtension(const clap_plugin_t*, const char* id) {
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) return &Params;
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) return &AudioPorts;
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) return &NotePorts;
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) return &State;
  if (std::strcmp(id, CLAP_EXT_LATENCY) == 0) return &Latency;
  if (std::strcmp(id, CLAP_EXT_TAIL) == 0) return &Tail;
  return nullptr;
}
void pluginMainThread(const clap_plugin_t* plugin) {
  if (self(plugin).editor != nil) [self(plugin).editor setNeedsDisplay:YES];
}

const char* Features[]{CLAP_PLUGIN_FEATURE_INSTRUMENT, CLAP_PLUGIN_FEATURE_SYNTHESIZER,
                       "piano", CLAP_PLUGIN_FEATURE_STEREO, nullptr};
const clap_plugin_descriptor_t Descriptor{
    CLAP_VERSION,
    "dev.onebeat.stock.piano",
    "OneBeat Piano",
    "OneBeat",
    "https://github.com/spix3l/onebeat",
    "",
    "",
    "0.2.0",
    "A responsive, sample-free stock piano for sketching ideas.",
    Features,
};

uint32_t factoryCount(const clap_plugin_factory_t*) { return 1; }
const clap_plugin_descriptor_t* factoryDescriptor(const clap_plugin_factory_t*, uint32_t index) {
  return index == 0 ? &Descriptor : nullptr;
}
const clap_plugin_t* factoryCreate(const clap_plugin_factory_t*, const clap_host_t* host,
                                   const char* id) {
  if (id == nullptr || std::strcmp(id, Descriptor.id) != 0) return nullptr;
  auto* piano = new (std::nothrow) Piano(host);
  if (piano == nullptr) return nullptr;
  piano->plugin.desc = &Descriptor;
  piano->plugin.plugin_data = piano;
  piano->plugin.init = pluginInit;
  piano->plugin.destroy = pluginDestroy;
  piano->plugin.activate = pluginActivate;
  piano->plugin.deactivate = pluginDeactivate;
  piano->plugin.start_processing = pluginStart;
  piano->plugin.stop_processing = pluginStop;
  piano->plugin.reset = pluginReset;
  piano->plugin.process = pluginProcess;
  piano->plugin.get_extension = pluginExtension;
  piano->plugin.on_main_thread = pluginMainThread;
  return &piano->plugin;
}
const clap_plugin_factory_t Factory{factoryCount, factoryDescriptor, factoryCreate};

bool entryInit(const char*) { return true; }
void entryDeinit() {}
const void* entryFactory(const char* id) {
  return id != nullptr && std::strcmp(id, CLAP_PLUGIN_FACTORY_ID) == 0 ? &Factory : nullptr;
}

}  // namespace

extern "C" {
extern __attribute__((visibility("default"))) const clap_plugin_entry_t clap_entry;
const clap_plugin_entry_t clap_entry{CLAP_VERSION, entryInit, entryDeinit, entryFactory};
}
