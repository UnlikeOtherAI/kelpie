#pragma once

#include <cstdint>
#include <string>
#include <utility>

namespace kelpie {

// Per-tab main-frame navigation bookkeeping behind `wait-for-navigation`.
//
// It counts navigations the page starts itself (a link a click followed, a
// form submit, a script assigning `location`) as well as the ones requested
// through the API. Counting only the API's own requests is what made a wait
// after a click fail with "No navigation has been requested", or return an
// earlier navigation's stale success at once.
//
// Pure data with no CEF dependency, so it is unit-tested directly. Every read
// and write happens on the CEF UI thread: the load events arrive there, and the
// engine reaches the tracker through RunOnUi.
struct NavigationTracker {
  enum class Progress { kNotStarted, kLoading, kFinished, kFailed };

  // Main-frame navigations started, by the API or by the page.
  std::uint64_t started = 0;
  // Navigations that have stopped loading. `finished == started` means idle.
  std::uint64_t finished = 0;
  // Navigations a wait must not count: those that had already finished when
  // the tab's most recent navigation-capable action ran.
  std::uint64_t baseline = 0;
  // The load error of the latest navigation, if it failed.
  std::string error;

  // A navigation-capable action (click, fill, evaluate, ...) is about to run.
  // A load already in flight is not finished, so it stays after the baseline:
  // a wait that follows still waits for it.
  void MarkAction() { baseline = finished; }

  // `navigate`, `back`, `forward` or `reload`. The CEF load this starts is not
  // counted again when it commits, because `started` is already ahead.
  void ApiNavigationRequested() {
    MarkAction();
    ++started;
    error.clear();
  }

  // CEF's OnLoadStart for the main frame, which fires when a cross-document
  // navigation commits. Same-document navigations (pushState, a hash change)
  // do not fire it and are not counted. A start while another navigation is
  // still in flight belongs to that navigation (a redirect, or a later click
  // that superseded it) and merges into it: `finished` only advances once CEF
  // reports that everything has stopped loading.
  void LoadStarted() {
    if (started != finished) return;
    ++started;
    error.clear();
  }

  // CEF's OnLoadError for the main frame, except ERR_ABORTED, which only means
  // a newer navigation or a download replaced the load. A navigation that fails
  // before it commits never reaches OnLoadStart, so a failure while idle is a
  // page-started navigation in its own right.
  void LoadFailed(std::string message) {
    if (started == finished) ++started;
    error = std::move(message);
  }

  // CEF's OnLoadingStateChange with is_loading false.
  void LoadStopped() { finished = started; }

  // Where the first navigation after `since` stands.
  Progress Since(std::uint64_t since) const {
    if (started <= since) return Progress::kNotStarted;
    if (!error.empty()) return Progress::kFailed;
    return finished < started ? Progress::kLoading : Progress::kFinished;
  }
};

}  // namespace kelpie
