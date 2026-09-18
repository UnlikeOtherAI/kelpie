#include "close_lifecycle.h"

#include <cassert>

int main() {
  kelpie::windows::CloseLifecycle lifecycle;
  int persisted = 0;
  lifecycle.Request();

  // The first close attempt must wait for handlers admitted before listener
  // shutdown. It cannot persist a state that an in-flight mutation can alter.
  assert(!lifecycle.Advance(false, [&] { ++persisted; }, [] { return true; }));
  assert(persisted == 0);

  // A bounded CEF close can be incomplete after persistence. Retrying must not
  // write a second snapshot, and the next successful close completes it.
  assert(!lifecycle.Advance(true, [&] { ++persisted; }, [] { return false; }));
  assert(persisted == 1);
  assert(lifecycle.persisted());
  assert(!lifecycle.completed());
  assert(lifecycle.Advance(true, [&] { ++persisted; }, [] { return true; }));
  assert(persisted == 1);
  assert(lifecycle.completed());
  return 0;
}