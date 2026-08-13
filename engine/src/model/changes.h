// Fine-grained change notification (OB-3-02 §7).
//
// Two consumers, both of which need to know *what* changed rather than *that*
// something changed: the flattener (OB-3-04), which re-flattens only the
// affected span, and the UI stores, which repaint only the affected widget.
// "The model changed" would make both of them re-do everything at 120 Hz.
//
// Events are emitted synchronously on the thread that made the edit — always an
// off-audio thread. The audio thread never sees the model, let alone these
// events; it only ever reads the published schedule.
#pragma once

#include <cstdint>
#include <functional>
#include <vector>

#include "model/ids.h"

namespace onebeat::model {

enum class ChangeType : uint8_t { Added, Removed, Modified };

// The field granularity the consumers actually branch on. `All` is for creation
// and deletion, where every field is new or gone.
enum class ChangeField : uint8_t {
  All,
  Name,
  Color,
  Muted,
  Soloed,
  Order,
  Height,
  Collapsed,
  Group,
  Routing,
  Plugin,
  NoteDefaults,
  Notes,
  Length,
  Start,
  Lane,
  Source,
  Transforms,
  Gain,
  Pan,
  Output,
  Transport,
  Meta,
};

struct ChangeEvent {
  ChangeType type = ChangeType::Modified;
  EntityKind kind = EntityKind::Instrument;
  RawId id;
  ChangeField field = ChangeField::All;
  // The other end of the change when there is one: the instrument whose
  // sequence changed inside a pattern, the lane a clip moved to, the pattern a
  // deleted clip referenced.
  RawId related;
};

using ChangeListener = std::function<void(const ChangeEvent&)>;

class ChangeBus {
 public:
  using Token = uint64_t;

  Token subscribe(ChangeListener listener) {
    const Token token = ++next_token_;
    listeners_.push_back({token, std::move(listener)});
    return token;
  }

  void unsubscribe(Token token) {
    for (size_t i = 0; i < listeners_.size(); ++i) {
      if (listeners_[i].token == token) {
        listeners_.erase(listeners_.begin() + static_cast<ptrdiff_t>(i));
        return;
      }
    }
  }

  void emit(const ChangeEvent& event) const {
    // Iterated by index over a copy-free vector: a listener that edits the
    // model in response would otherwise invalidate the iterator. Subscribing or
    // unsubscribing from inside a listener is not supported and is not needed.
    for (const Entry& entry : listeners_) entry.listener(event);
  }

  size_t listenerCount() const { return listeners_.size(); }

 private:
  struct Entry {
    Token token;
    ChangeListener listener;
  };

  std::vector<Entry> listeners_;
  Token next_token_ = 0;
};

}  // namespace onebeat::model
