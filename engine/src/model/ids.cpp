#include "model/ids.h"

#include <chrono>
#include <random>

namespace onebeat::model {
namespace {

// Crockford base32: no I, L, O or U, so an ID read aloud or retyped from a bug
// report cannot become a different valid ID.
constexpr std::string_view Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
constexpr int UlidChars = 26;

uint8_t fiveBitsAt(RawId id, int shift) {
  uint64_t value = 0;
  if (shift >= 64) {
    value = id.high >> (shift - 64);
  } else if (shift == 0) {
    value = id.low;
  } else {
    value = (id.low >> shift) | (id.high << (64 - shift));
  }
  return static_cast<uint8_t>(value & 0x1FU);
}

int decodeChar(char c) {
  for (size_t i = 0; i < Alphabet.size(); ++i) {
    if (Alphabet[i] == c) return static_cast<int>(i);
  }
  // Crockford's documented aliases. Accepted on read, never produced on write,
  // so a hand-typed ID still resolves to the entity the user meant.
  switch (c) {
    case 'i':
    case 'I':
    case 'l':
    case 'L':
      return 1;
    case 'o':
    case 'O':
      return 0;
    default:
      break;
  }
  if (c >= 'a' && c <= 'z') {
    const char upper = static_cast<char>(c - ('a' - 'A'));
    for (size_t i = 0; i < Alphabet.size(); ++i) {
      if (Alphabet[i] == upper) return static_cast<int>(i);
    }
  }
  return -1;
}

}  // namespace

std::string encodeUlid(RawId id) {
  std::string out(static_cast<size_t>(UlidChars), '0');
  for (int i = 0; i < UlidChars; ++i) {
    const int shift = 125 - (5 * i);
    out[static_cast<size_t>(i)] = Alphabet[fiveBitsAt(id, shift)];
  }
  return out;
}

std::optional<RawId> decodeUlid(std::string_view text) {
  if (text.size() != static_cast<size_t>(UlidChars)) return std::nullopt;
  RawId id{};
  for (const char c : text) {
    const int value = decodeChar(c);
    if (value < 0) return std::nullopt;
    // Shift the whole 128-bit value left by five and drop the digit in.
    id.high = (id.high << 5) | (id.low >> 59);
    id.low = (id.low << 5) | static_cast<uint64_t>(value);
  }
  return id;
}

IdGenerator::IdGenerator() : IdGenerator(std::random_device{}(), 0, false) {}

IdGenerator IdGenerator::deterministic(uint64_t seed, uint64_t start_unix_ms) {
  return IdGenerator(seed, start_unix_ms, true);
}

IdGenerator::IdGenerator(uint64_t seed, uint64_t start_unix_ms, bool deterministic)
    : rng_state_(seed | 1ULL), fixed_now_ms_(start_unix_ms), deterministic_(deterministic) {}

uint64_t IdGenerator::nowMilliseconds() {
  if (deterministic_) return fixed_now_ms_;
  using namespace std::chrono;
  const auto now = system_clock::now().time_since_epoch();
  return static_cast<uint64_t>(duration_cast<milliseconds>(now).count()) & 0xFFFFFFFFFFFFULL;
}

uint64_t IdGenerator::nextRandom() {
  // splitmix64: small, fast, and reproducible from a seed, which is what the
  // byte-stable-fixture promise in ADR-004 needs.
  rng_state_ += 0x9E3779B97F4A7C15ULL;
  uint64_t z = rng_state_;
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
  return z ^ (z >> 31);
}

RawId IdGenerator::nextRaw() {
  const uint64_t ms = nowMilliseconds();

  if (has_last_ && ms == last_ms_) {
    // Same millisecond: increment the 80-bit random field so the new ID still
    // sorts after the previous one. Overflow of all 80 bits is not reachable in
    // one millisecond, and if it somehow were, the next millisecond redraws.
    if (++last_random_low_ == 0) last_random_high_ = (last_random_high_ + 1) & 0xFFFFULL;
  } else {
    last_ms_ = ms;
    last_random_high_ = nextRandom() & 0xFFFFULL;
    last_random_low_ = nextRandom();
    has_last_ = true;
  }

  RawId id{};
  id.high = ((ms & 0xFFFFFFFFFFFFULL) << 16) | last_random_high_;
  id.low = last_random_low_;
  return id;
}

}  // namespace onebeat::model
