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
enum class StartupAux { CONTEXT_INITIALIZED, SCHEDULE_FIRST, GTK_PUMP_FIRST,
  AFTER_CREATED_ENTER_UI, AFTER_CREATED_ENTER_OTHER, AFTER_CREATED_RETURN_UI, AFTER_CREATED_RETURN_OTHER };
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
    case StartupAux::AFTER_CREATED_ENTER_UI: name = "AFTER_CREATED_ENTER_UI"; bit = 8; break;
    case StartupAux::AFTER_CREATED_ENTER_OTHER: name = "AFTER_CREATED_ENTER_OTHER"; bit = 16; break;
    case StartupAux::AFTER_CREATED_RETURN_UI: name = "AFTER_CREATED_RETURN_UI"; bit = 32; break;
    case StartupAux::AFTER_CREATED_RETURN_OTHER: name = "AFTER_CREATED_RETURN_OTHER"; bit = 64; break;
  }
  if (!name) return;
  static std::atomic<unsigned> seen{0};
  if (seen.fetch_or(bit) & bit) return;
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
  char line[128];
  const int n = std::snprintf(line, sizeof(line), "KELPIE_GTK_AUX %s %ld %lld\n", name, static_cast<long>(getpid()),
      static_cast<long long>(now.tv_sec) * 1000000000LL + now.tv_nsec);
  if (n > 0 && n < static_cast<int>(sizeof(line))) (void)write(STDERR_FILENO, line, n);
}
inline bool StartupAfterCreatedEnter(bool on_ui) {
  const char* enabled = std::getenv("KELPIE_GTK_STARTUP_TRACE");
  const char* aux_enabled = std::getenv("KELPIE_GTK_AUX_TRACE");
  if (!enabled || std::strcmp(enabled, "1") != 0 ||
      !aux_enabled || std::strcmp(aux_enabled, "1") != 0) return false;
  static std::atomic_flag first = ATOMIC_FLAG_INIT;
  if (first.test_and_set()) return false;
  StartupAuxTrace(on_ui ? StartupAux::AFTER_CREATED_ENTER_UI : StartupAux::AFTER_CREATED_ENTER_OTHER);
  return true;
}
inline void StartupAfterCreatedReturn(bool on_ui) {
  StartupAuxTrace(on_ui ? StartupAux::AFTER_CREATED_RETURN_UI : StartupAux::AFTER_CREATED_RETURN_OTHER);
}
}
#define KELPIE_STARTUP_TRACE(event) ::kelpie::linuxapp::StartupTrace(::kelpie::linuxapp::StartupStage::event)
#define KELPIE_STARTUP_AUX(event) ::kelpie::linuxapp::StartupAuxTrace(::kelpie::linuxapp::StartupAux::event)
#define KELPIE_STARTUP_AFTER_ENTER(ui) ::kelpie::linuxapp::StartupAfterCreatedEnter(ui)
#define KELPIE_STARTUP_AFTER_RETURN(ui) ::kelpie::linuxapp::StartupAfterCreatedReturn(ui)
#else
#define KELPIE_STARTUP_TRACE(event) ((void)0)
#define KELPIE_STARTUP_AUX(event) ((void)0)
#define KELPIE_STARTUP_AFTER_ENTER(ui) false
#define KELPIE_STARTUP_AFTER_RETURN(ui) ((void)0)
#endif
