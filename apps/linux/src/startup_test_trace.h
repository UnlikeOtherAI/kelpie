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
enum class StartupStage {
  GTK_INIT_ENTER, GTK_INIT_RETURN, SHOW_ENTER, SHOW_RETURN, CANVAS_REALIZE,
  ATTACH_ENTER, ATTACH_OK, ATTACH_FAIL, START_ENTER, START_OK, START_FAIL,
  ENGINE_ENTER, ENGINE_OK, ENGINE_FAIL, CEF_INIT_ENTER, CEF_INIT_OK, CEF_INIT_FAIL,
  FIRST_BROWSER_ENTER, FIRST_BROWSER_OK, FIRST_BROWSER_FAIL,
  HANDLERS_ENTER, HANDLERS_RETURN, LISTENER_ENTER, LISTENER_OK, LISTENER_FAIL,
  MDNS_ENTER, MDNS_RETURN, MDNS_SKIPPED, PUBLISH_ENTER, PUBLISH_RETURNED
};
inline const char* StartupStageName(StartupStage stage) {
  switch (stage) {
#define KELPIE_STARTUP_NAME(name) case StartupStage::name: return #name
    KELPIE_STARTUP_NAME(GTK_INIT_ENTER); KELPIE_STARTUP_NAME(GTK_INIT_RETURN);
    KELPIE_STARTUP_NAME(SHOW_ENTER); KELPIE_STARTUP_NAME(SHOW_RETURN);
    KELPIE_STARTUP_NAME(CANVAS_REALIZE); KELPIE_STARTUP_NAME(ATTACH_ENTER);
    KELPIE_STARTUP_NAME(ATTACH_OK); KELPIE_STARTUP_NAME(ATTACH_FAIL);
    KELPIE_STARTUP_NAME(START_ENTER); KELPIE_STARTUP_NAME(START_OK); KELPIE_STARTUP_NAME(START_FAIL);
    KELPIE_STARTUP_NAME(ENGINE_ENTER); KELPIE_STARTUP_NAME(ENGINE_OK); KELPIE_STARTUP_NAME(ENGINE_FAIL);
    KELPIE_STARTUP_NAME(CEF_INIT_ENTER); KELPIE_STARTUP_NAME(CEF_INIT_OK); KELPIE_STARTUP_NAME(CEF_INIT_FAIL);
    KELPIE_STARTUP_NAME(FIRST_BROWSER_ENTER); KELPIE_STARTUP_NAME(FIRST_BROWSER_OK); KELPIE_STARTUP_NAME(FIRST_BROWSER_FAIL);
    KELPIE_STARTUP_NAME(HANDLERS_ENTER); KELPIE_STARTUP_NAME(HANDLERS_RETURN);
    KELPIE_STARTUP_NAME(LISTENER_ENTER); KELPIE_STARTUP_NAME(LISTENER_OK); KELPIE_STARTUP_NAME(LISTENER_FAIL);
    KELPIE_STARTUP_NAME(MDNS_ENTER); KELPIE_STARTUP_NAME(MDNS_RETURN); KELPIE_STARTUP_NAME(MDNS_SKIPPED);
    KELPIE_STARTUP_NAME(PUBLISH_ENTER); KELPIE_STARTUP_NAME(PUBLISH_RETURNED);
#undef KELPIE_STARTUP_NAME
  }
  return nullptr;
}
inline void StartupTrace(StartupStage stage) {
  const char* enabled = std::getenv("KELPIE_GTK_STARTUP_TRACE");
  if (!enabled || std::strcmp(enabled, "1") != 0) return;
  const char* event = StartupStageName(stage);
  if (!event) return;
  static std::atomic<unsigned> count{0};
  if (count.fetch_add(1) >= 32) return;
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
  char line[128];
  const int n = std::snprintf(line, sizeof(line), "KELPIE_GTK_STARTUP %s %lld\n", event,
      static_cast<long long>(now.tv_sec) * 1000000000LL + now.tv_nsec);
  if (n > 0 && n < static_cast<int>(sizeof(line))) (void)write(STDERR_FILENO, line, n);
}
enum class StartupAux { CONTEXT_INITIALIZED, SCHEDULE_FIRST, GTK_PUMP_FIRST };
inline void StartupAuxTrace(StartupAux stage) {
  const char* enabled = std::getenv("KELPIE_GTK_STARTUP_TRACE");
  if (!enabled || std::strcmp(enabled, "1") != 0) return;
  const char* aux_enabled = std::getenv("KELPIE_GTK_AUX_TRACE");
  if (!aux_enabled || std::strcmp(aux_enabled, "1") != 0) return;
  const char* name = nullptr;
  unsigned bit = 0;
  switch (stage) {
    case StartupAux::CONTEXT_INITIALIZED: name = "CONTEXT_INITIALIZED"; bit = 1; break;
    case StartupAux::SCHEDULE_FIRST: name = "SCHEDULE_FIRST"; bit = 2; break;
    case StartupAux::GTK_PUMP_FIRST: name = "GTK_PUMP_FIRST"; bit = 4; break;
  }
  if (!name) return;
  static std::atomic<unsigned> seen{0};
  if (seen.fetch_or(bit) & bit) return;
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
  char line[128];
  const int n = std::snprintf(line, sizeof(line), "KELPIE_GTK_AUX %s %lld\n", name,
      static_cast<long long>(now.tv_sec) * 1000000000LL + now.tv_nsec);
  if (n > 0 && n < static_cast<int>(sizeof(line))) (void)write(STDERR_FILENO, line, n);
}
}
#define KELPIE_STARTUP_TRACE(event) ::kelpie::linuxapp::StartupTrace(::kelpie::linuxapp::StartupStage::event)
#define KELPIE_STARTUP_AUX(event) ::kelpie::linuxapp::StartupAuxTrace(::kelpie::linuxapp::StartupAux::event)
#else
#define KELPIE_STARTUP_TRACE(event) ((void)0)
#define KELPIE_STARTUP_AUX(event) ((void)0)
#endif
