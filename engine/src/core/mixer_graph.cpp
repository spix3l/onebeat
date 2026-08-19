#include "core/mixer_graph.h"

#include <cstddef>

namespace onebeat::core {

int32_t MixerGraph::indexOf(const std::string& track_id) const {
  for (size_t i = 0; i < nodes_.size(); ++i) {
    if (nodes_[i].track_id == track_id) return static_cast<int32_t>(i);
  }
  return -1;
}

bool MixerGraph::finalise() {
  const auto count = static_cast<int32_t>(nodes_.size());
  order_.clear();
  order_.reserve(nodes_.size());
  master_ = -1;
  effect_count_ = 0;

  for (int32_t i = 0; i < count; ++i) {
    const GraphNode& node = nodes_[static_cast<size_t>(i)];
    if (node.output < 0) master_ = i;
    effect_count_ += static_cast<int32_t>(node.effects.size());
  }

  // Depth-first post-order: a node is emitted only after the node it feeds has
  // been visited, then the whole list is reversed. The result is inputs first,
  // master last, which is the order the render loop needs.
  //
  // 0 = unvisited, 1 = on the stack (a second visit is a cycle), 2 = done.
  std::vector<uint8_t> state(nodes_.size(), 0);
  std::vector<int32_t> stack;
  std::vector<int32_t> reverse;
  reverse.reserve(nodes_.size());

  for (int32_t start = 0; start < count; ++start) {
    if (state[static_cast<size_t>(start)] != 0) continue;
    stack.push_back(start);
    while (!stack.empty()) {
      const int32_t current = stack.back();
      uint8_t& mark = state[static_cast<size_t>(current)];
      if (mark == 2) {
        stack.pop_back();
        continue;
      }
      if (mark == 1) {
        // Every descendant is done, so this node is too.
        mark = 2;
        reverse.push_back(current);
        stack.pop_back();
        continue;
      }
      mark = 1;
      const int32_t output = nodes_[static_cast<size_t>(current)].output;
      if (output < 0 || output >= count) continue;
      if (state[static_cast<size_t>(output)] == 1) {
        // Back edge: this routing feeds itself. Refuse the whole graph rather
        // than render part of it — a half-connected mixer is harder to
        // diagnose than one that plainly did not load.
        return false;
      }
      if (state[static_cast<size_t>(output)] == 0) stack.push_back(output);
    }
  }

  for (size_t i = reverse.size(); i > 0; --i) order_.push_back(reverse[i - 1]);
  return master_ >= 0;
}

}  // namespace onebeat::core
