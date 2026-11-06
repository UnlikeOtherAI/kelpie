#pragma once

// Test-only fixed startup markers. No page, profile, token or error strings.
#if KELPIE_LINUX_STARTUP_TEST_TRACE
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <time.h>
#include <unistd.h>

namespace kelpie::linuxapp {
inline void StartupTrace(const char* event) {
  const char* enabled = std::getenv("KELPIE_GTK_STARTUP_TRACE");
  if (!enabled || std::strcmp(enabled, "1") != 0) return;
  static std::atomic<unsigned> count{0};
  if (count.fetch_add(1) >= 32) return;
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
  char line[128];
  const int n = std::snprintf(line, sizeof(line), "KELPIE_GTK_STARTUP %s %lld\n", event,
      static_cast<long long>(now.tv_sec) * 1000000000LL + now.tv_nsec);
  if (n > 0 && n < static_cast<int>(sizeof(line))) (void)write(STDERR_FILENO, line, n);
}
}
#define KELPIE_STARTUP_TRACE(event) ::kelpie::linuxapp::StartupTrace(event)
#else
#define KELPIE_STARTUP_TRACE(event) ((void)0)
#endif
