#include "kelpie/tab_chat_session.h"
#include <cassert>
#include <future>

int main() {
  kelpie::TabChatSession first, second;
  for (int index = 0; index < 15; ++index) {
    const auto turn = first.Begin("Remember turn " + std::to_string(index));
    assert(turn && turn->messages.size() == static_cast<size_t>(index * 2 + 1));
    assert(!first.Begin("duplicate"));
    assert(first.Complete(turn->token, "answer " + std::to_string(index)));
    assert(!first.Complete(turn->token, "duplicate completion"));
  }
  assert(first.Messages().size() == 30);
  assert(first.Messages().front()["content"] == "Remember turn 0");
  assert(second.Messages().empty());
  const auto in_flight = first.Begin("reply after a tab switch");
  const auto other_turn = second.Begin("another tab");
  assert(in_flight && other_turn);
  assert(first.Complete(in_flight->token, "still belongs to first"));
  assert(second.Messages().size() == 1);
  const auto closing = first.Begin("late reply");
  assert(closing);
  first.Close();
  assert(first.Messages().empty());
  assert(!first.Complete(closing->token, "discarded"));
  assert(!first.Complete(closing->token, std::nullopt));
  assert(!first.Begin("closed tab"));
  kelpie::TabChatSession reopened;
  assert(reopened.Messages().empty());
  const auto retry = reopened.Begin("request fails");
  assert(retry && reopened.Complete(retry->token, std::nullopt));
  assert(reopened.Messages().size() == 1); // An error is never an assistant turn.
  assert(reopened.Begin("retry"));

  kelpie::TabChatSession concurrent;
  std::promise<void> release;
  const auto ready = release.get_future().share();
  const auto ask = [&] { ready.wait(); return concurrent.Begin("simultaneous request"); };
  auto one = std::async(std::launch::async, ask);
  auto two = std::async(std::launch::async, ask);
  release.set_value();
  const auto a = one.get(), b = two.get();
  assert(a.has_value() != b.has_value());
  assert(concurrent.Messages().size() == 1);
}
