// Undo/redo (OB-3-03, FR-PRJ-08, FR-UX-21).
//
// **Every model mutation from Stage 3 onwards goes through a command.** Not
// because commands are elegant, but because retrofitting undo is miserable and
// FR-UX-21 asks for exploration to be safe: an action a user cannot take back
// is an action they hesitate over. `tools/seam_check.sh` enforces the rule
// mechanically — outside `model/commands.cpp` and the tests, nothing calls
// `Project`'s mutating API.
//
// Two design choices worth naming:
//
//  1. **Commands capture inverses, not snapshots.** Undoing "delete the kick"
//     restores the instrument, the sequences it had in every pattern, and the
//     automation clips that died with it — captured at apply time, ~kilobytes.
//     A whole-project snapshot per edit would be megabytes per keystroke.
//  2. **IDs are minted before apply.** A create command holds the entity it
//     will insert, ID and all, so apply → revert → re-apply lands the *same*
//     ID every time and every other command's references stay valid. This is
//     the concrete reason ADR-004's never-reused IDs matter.
#pragma once

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

#include "model/project.h"

namespace onebeat::model {

class Command {
 public:
  virtual ~Command() = default;

  // Both directions return false when the model is not in a state where the
  // step makes sense. That is a bug in the history, not a user error, so the
  // bus stops rather than limping on with a half-applied edit.
  virtual bool apply(Project& project) = 0;
  virtual bool revert(Project& project) = 0;

  // Shown in the UI: "Undo Delete 3 notes" (FR-UX-21).
  virtual std::string name() const = 0;

  // Continuous gestures. A knob twiddle or a note drag arrives as a stream of
  // small commands; absorbing the next one into this one keeps the history at
  // one entry per gesture without the UI having to bracket every interaction.
  // The absorbing command keeps its own "before" and takes the other's "after".
  virtual bool coalesceWith(const Command& /*next*/) { return false; }
};

using CommandPtr = std::unique_ptr<Command>;

// Several commands that undo as one. Produced by transactions, and by anything
// that is one user action and several model edits ("Make unique" clones a
// pattern *and* re-points a clip).
class CompositeCommand : public Command {
 public:
  explicit CompositeCommand(std::string name) : name_(std::move(name)) {}

  void add(CommandPtr command) { commands_.push_back(std::move(command)); }
  bool empty() const { return commands_.empty(); }
  size_t size() const { return commands_.size(); }

  bool apply(Project& project) override {
    for (size_t i = 0; i < commands_.size(); ++i) {
      if (commands_[i]->apply(project)) continue;
      // Roll back what did apply, so a failed composite leaves the model where
      // it started rather than halfway.
      for (size_t undo = i; undo > 0; --undo) commands_[undo - 1]->revert(project);
      return false;
    }
    return true;
  }

  bool revert(Project& project) override {
    for (size_t i = commands_.size(); i > 0; --i) {
      if (!commands_[i - 1]->revert(project)) return false;
    }
    return true;
  }

  std::string name() const override { return name_; }

 private:
  std::string name_;
  std::vector<CommandPtr> commands_;
};

// The single mutation path. Unbounded history (FR-PRJ-08): bounded in practice
// by command granularity, not by snapshot size.
class CommandBus {
 public:
  explicit CommandBus(Project& project) : project_(project) {}

  // Applies and records. A command that fails to apply is not recorded and the
  // redo stack is left alone — nothing happened, so nothing changed.
  bool execute(CommandPtr command);

  bool canUndo() const { return !undo_stack_.empty(); }
  bool canRedo() const { return !redo_stack_.empty(); }
  bool undo();
  bool redo();

  // What the menu item should say. Empty when there is nothing to do.
  std::string undoName() const { return canUndo() ? undo_stack_.back()->name() : std::string(); }
  std::string redoName() const { return canRedo() ? redo_stack_.back()->name() : std::string(); }

  size_t undoDepth() const { return undo_stack_.size(); }
  size_t redoDepth() const { return redo_stack_.size(); }

  // ----- gestures ----------------------------------------------------------
  // The UI brackets a drag: begin on mouse-down, commit on mouse-up. Everything
  // executed in between becomes one history entry with the transaction's name.
  // Transactions nest; only the outermost one produces an entry.
  void beginTransaction(std::string name);
  void commitTransaction();
  // Reverts everything in the open transaction — the drag was cancelled.
  void abortTransaction();
  bool inTransaction() const { return !open_.empty(); }

  // Ends the coalescing window without ending anything else: the next command
  // starts a new history entry even if it would otherwise merge. Called on
  // selection change, focus change, and gesture end.
  void seal() { coalescable_ = false; }

  void clear();

 private:
  bool record(CommandPtr command);

  Project& project_;
  std::vector<CommandPtr> undo_stack_;
  std::vector<CommandPtr> redo_stack_;
  std::vector<std::unique_ptr<CompositeCommand>> open_;
  bool coalescable_ = false;
};

}  // namespace onebeat::model
