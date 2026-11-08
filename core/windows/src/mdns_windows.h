#pragma once

#include <cstdint>
#include <string>

#include "kelpie/types.h"

namespace kelpie::windows {

struct MdnsRegistration {
  std::string instance_name;
  std::uint16_t port = 0;
  StringMap txt_records;
};

class MdnsWindows {
 public:
  MdnsWindows();
  ~MdnsWindows();

  bool Start(const MdnsRegistration& registration);
  void Stop();
  bool IsRunning() const { return running_; }
  const std::string& LastError() const { return last_error_; }

 private:
  bool StartNative(const MdnsRegistration& registration);
  bool StartBonjour(const MdnsRegistration& registration);
  void SetError(std::string message);

  bool running_ = false;
  std::string last_error_;

#if defined(_WIN32) && __has_include(<windns.h>)
  void* native_instance_ = nullptr;
  bool native_registered_ = false;
#endif

#if defined(_WIN32) && __has_include(<dns_sd.h>)
  void* bonjour_service_ = nullptr;
#endif
};

}  // namespace kelpie::windows
