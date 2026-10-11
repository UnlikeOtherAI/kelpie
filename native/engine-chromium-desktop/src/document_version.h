#pragma once
#include <atomic>
#include <chrono>
#include <string>
namespace kelpie {
// Runtime epoch prevents a restored tab id from reusing its old document pin.
inline std::string NextDocumentVersion() {
  static const auto epoch=std::chrono::system_clock::now().time_since_epoch().count();
  static std::atomic<unsigned long long> next{0};
  return std::to_string(epoch)+"-"+std::to_string(++next);
}
}
