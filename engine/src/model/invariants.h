// Referential integrity for the domain model (OB-3-02 §6).
//
// Every reference in the model is an ID, and an ID that resolves to nothing is
// the failure mode that quietly eats user work: a clip pointing at a deleted
// pattern, a sequence for an instrument that no longer exists, a routing entry
// naming a track that was removed. Each is cheap to detect and expensive to
// discover later, so the model checks itself after every mutation in debug and
// sanitizer builds.
//
// The checker is also usable on demand — the load path (OB-3-05) runs it on a
// freshly parsed project, where a hand-edited or third-party file can contain
// exactly these problems and must be reported rather than trusted.
#pragma once

#include <string>
#include <vector>

namespace onebeat::model {

class Project;

struct Violation {
  std::string message;
};

// Empty means the model is internally consistent. Order is deterministic
// (entity kind, then ID) so a failure message is stable across runs.
std::vector<Violation> checkReferentialIntegrity(const Project& project);

}  // namespace onebeat::model
