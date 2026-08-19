// Entity identity for the domain model (OB-3-02 §1, FR-PRJ-02, ADR-004).
//
// Two rules, and everything here exists to make them structural rather than
// remembered:
//
//  1. **IDs are never reused.** ADR-004 chose ULIDs precisely so that this is a
//     property of the identifier and not a bookkeeping obligation: there is no
//     counter to persist and no tombstone list to maintain, and two projects
//     that meet (copy-paste, a preset browser) cannot collide.
//  2. **An ID of one kind is not an ID of another.** `TypedId` is a distinct
//     type per entity kind with no conversions between them, so
//     `ArrangementLane` cannot acquire a `MixerTrackId` field by accident —
//     ARCHITECTURE.md §4's "none. Deliberate. Do not add." is enforced by the
//     compiler, not by review.
//
// IDs order by their 128-bit value, which is ULID order, which is creation
// order. `std::map` keyed by one of these therefore iterates in creation order
// and serialises in the order docs/project-format.md §6 requires, with no sort
// step at save time.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>

namespace onebeat::model {

enum class EntityKind : uint8_t {
  Instrument,
  Pattern,
  ArrangementLane,
  Clip,
  MixerTrack,
  // A slot in a mixer track's effect chain. It needs an identity of its own
  // because automation targets it: an automation clip written against slot 2
  // must keep pointing at the same reverb after the user drags it to slot 1,
  // and a chain position cannot promise that.
  Effect,
  // Not an entity and never an ID in the file: `Project` addresses
  // project-level state (transport, meta) in change events, which otherwise
  // would have to pretend to be some entity they are not.
  Project,
};

// The prefixes of docs/project-format.md §4. A mis-typed reference is visible
// in the file and rejected by the loader instead of failing confusingly later.
constexpr std::string_view entityPrefix(EntityKind kind) {
  switch (kind) {
    case EntityKind::Instrument:
      return "ins";
    case EntityKind::Pattern:
      return "pat";
    case EntityKind::ArrangementLane:
      return "lan";
    case EntityKind::Clip:
      return "clp";
    case EntityKind::MixerTrack:
      return "mix";
    case EntityKind::Effect:
      return "efx";
    case EntityKind::Project:
      return "prj";
  }
  return "???";
}

constexpr std::string_view entityNoun(EntityKind kind) {
  switch (kind) {
    case EntityKind::Instrument:
      return "instrument";
    case EntityKind::Pattern:
      return "pattern";
    case EntityKind::ArrangementLane:
      return "lane";
    case EntityKind::Clip:
      return "clip";
    case EntityKind::MixerTrack:
      return "mixer track";
    case EntityKind::Effect:
      return "effect";
    case EntityKind::Project:
      return "project";
  }
  return "entity";
}

// A 128-bit ULID with no type attached. Only used where code must be generic
// over kinds — logging, the invariant checker, change events.
struct RawId {
  uint64_t high = 0;
  uint64_t low = 0;

  constexpr bool valid() const { return high != 0 || low != 0; }
  friend constexpr bool operator==(const RawId&, const RawId&) = default;
  friend constexpr auto operator<=>(const RawId& a, const RawId& b) {
    if (a.high != b.high) return a.high <=> b.high;
    return a.low <=> b.low;
  }
};

// 26 Crockford base32 characters, most significant first.
std::string encodeUlid(RawId id);
std::optional<RawId> decodeUlid(std::string_view text);

template <EntityKind K>
class TypedId {
 public:
  static constexpr EntityKind Kind = K;

  constexpr TypedId() = default;
  constexpr explicit TypedId(RawId raw) : raw_(raw) {}

  constexpr bool valid() const { return raw_.valid(); }
  constexpr RawId raw() const { return raw_; }

  // "ins_01K2QF8Z01BASS00000000002" — the exact text that goes in the file.
  std::string str() const { return std::string(entityPrefix(K)) + "_" + encodeUlid(raw_); }

  // Rejects a well-formed ULID carrying the wrong prefix: that is a reference
  // pointing at the wrong kind of thing, which is a load error, not a warning.
  static std::optional<TypedId> parse(std::string_view text) {
    const std::string_view prefix = entityPrefix(K);
    if (text.size() != prefix.size() + 1 + 26) return std::nullopt;
    if (text.substr(0, prefix.size()) != prefix) return std::nullopt;
    if (text[prefix.size()] != '_') return std::nullopt;
    const std::optional<RawId> raw = decodeUlid(text.substr(prefix.size() + 1));
    if (!raw) return std::nullopt;
    return TypedId(*raw);
  }

  friend constexpr bool operator==(const TypedId&, const TypedId&) = default;
  friend constexpr auto operator<=>(const TypedId&, const TypedId&) = default;

 private:
  RawId raw_{};
};

using InstrumentId = TypedId<EntityKind::Instrument>;
using PatternId = TypedId<EntityKind::Pattern>;
using ArrangementLaneId = TypedId<EntityKind::ArrangementLane>;
using ClipId = TypedId<EntityKind::Clip>;
using MixerTrackId = TypedId<EntityKind::MixerTrack>;
using EffectId = TypedId<EntityKind::Effect>;

// The compiler is the enforcement mechanism for ARCHITECTURE.md §4. If any of
// these ever compiles as convertible, a lane has become able to hold a routing
// destination and the two axes have been welded together.
static_assert(!std::is_convertible_v<MixerTrackId, ArrangementLaneId>);
static_assert(!std::is_convertible_v<ArrangementLaneId, MixerTrackId>);
static_assert(!std::is_convertible_v<PatternId, ClipId>);
static_assert(!std::is_convertible_v<InstrumentId, MixerTrackId>);
// An effect lives *in* a track and is not one: a chain slot must never be
// usable as a routing destination.
static_assert(!std::is_convertible_v<EffectId, MixerTrackId>);
static_assert(!std::is_convertible_v<MixerTrackId, EffectId>);

// Generates ULIDs: 48 bits of Unix milliseconds, 80 bits of randomness,
// monotonic within a millisecond (the random field is incremented rather than
// redrawn, so IDs minted in the same tick still sort by creation order).
//
// The clock and the random source are injectable because ADR-004 promises
// byte-stable fixtures: `deterministic()` gives a generator whose output is a
// pure function of its seed.
class IdGenerator {
 public:
  IdGenerator();
  static IdGenerator deterministic(uint64_t seed, uint64_t start_unix_ms = 1'700'000'000'000ULL);

  template <EntityKind K>
  TypedId<K> next() {
    return TypedId<K>(nextRaw());
  }

  RawId nextRaw();

 private:
  IdGenerator(uint64_t seed, uint64_t start_unix_ms, bool deterministic);

  uint64_t nowMilliseconds();
  uint64_t nextRandom();

  uint64_t rng_state_ = 0;
  uint64_t fixed_now_ms_ = 0;
  bool deterministic_ = false;
  uint64_t last_ms_ = 0;
  uint64_t last_random_high_ = 0;  // 16 bits
  uint64_t last_random_low_ = 0;   // 64 bits
  bool has_last_ = false;
};

}  // namespace onebeat::model
