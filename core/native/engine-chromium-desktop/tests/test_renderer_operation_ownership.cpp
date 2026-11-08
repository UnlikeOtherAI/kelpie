#include <cassert>
#include "renderer_operation_ownership.h"

int main() {
  auto pending = std::make_shared<std::atomic<std::size_t>>(0);
  kelpie::RendererOperationOwnership appearance(pending, false);
  appearance.MarkUncertain();
  appearance.MarkUncertain();
  assert(pending->load() == 0);  // Late pure sampling cannot fence admission.
  kelpie::RendererOperationOwnership action(pending);
  action.MarkUncertain();
  action.MarkUncertain();
  assert(pending->load() == 1);  // A timed-out public action still fences.
  appearance.Retire();
  appearance.Retire();
  assert(pending->load() == 1);  // Sampling cannot retire somebody else's fence.
  action.Retire();
  action.Retire();
  assert(pending->load() == 0);  // Late completion permits recovery.
  action.MarkUncertain();
  assert(pending->load() == 0);  // Retired callbacks cannot reopen ownership.
  kelpie::RendererOperationOwnership completed(pending);
  completed.Retire();
  completed.MarkUncertain();
  assert(pending->load() == 0);
}
