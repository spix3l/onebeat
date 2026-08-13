#include "model/command.h"

#include <utility>

namespace onebeat::model {

bool CommandBus::execute(CommandPtr command) {
  if (command == nullptr) return false;
  if (!command->apply(project_)) return false;
  return record(std::move(command));
}

bool CommandBus::record(CommandPtr command) {
  if (!open_.empty()) {
    // Inside a gesture: the entry is the transaction, not this step.
    open_.back()->add(std::move(command));
    return true;
  }

  // A new edit invalidates the redo branch. Selective/branched undo is out of
  // scope (OB-3-03) and pretending otherwise would be a lie about what ⇧⌘Z does.
  redo_stack_.clear();

  if (coalescable_ && !undo_stack_.empty() && undo_stack_.back()->coalesceWith(*command)) {
    // Absorbed: the drag stays one history entry. The command's effect is
    // already applied; only its bookkeeping merged.
    return true;
  }

  undo_stack_.push_back(std::move(command));
  coalescable_ = true;
  return true;
}

bool CommandBus::undo() {
  if (!canUndo()) return false;
  CommandPtr command = std::move(undo_stack_.back());
  undo_stack_.pop_back();
  if (!command->revert(project_)) {
    // Put it back: the history and the model still agree, and the failure is
    // visible to the caller rather than swallowed.
    undo_stack_.push_back(std::move(command));
    return false;
  }
  redo_stack_.push_back(std::move(command));
  coalescable_ = false;
  return true;
}

bool CommandBus::redo() {
  if (!canRedo()) return false;
  CommandPtr command = std::move(redo_stack_.back());
  redo_stack_.pop_back();
  if (!command->apply(project_)) {
    redo_stack_.push_back(std::move(command));
    return false;
  }
  undo_stack_.push_back(std::move(command));
  coalescable_ = false;
  return true;
}

void CommandBus::beginTransaction(std::string name) {
  open_.push_back(std::make_unique<CompositeCommand>(std::move(name)));
}

void CommandBus::commitTransaction() {
  if (open_.empty()) return;
  std::unique_ptr<CompositeCommand> transaction = std::move(open_.back());
  open_.pop_back();

  // An empty gesture — a click that moved nothing — leaves no history entry.
  if (transaction->empty()) return;

  if (!open_.empty()) {
    open_.back()->add(std::move(transaction));
    return;
  }
  redo_stack_.clear();
  undo_stack_.push_back(std::move(transaction));
  coalescable_ = false;
}

void CommandBus::abortTransaction() {
  if (open_.empty()) return;
  std::unique_ptr<CompositeCommand> transaction = std::move(open_.back());
  open_.pop_back();
  transaction->revert(project_);
}

void CommandBus::clear() {
  undo_stack_.clear();
  redo_stack_.clear();
  open_.clear();
  coalescable_ = false;
}

}  // namespace onebeat::model
