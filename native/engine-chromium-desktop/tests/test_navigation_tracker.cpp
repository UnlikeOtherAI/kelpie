#include "kelpie/navigation_tracker.h"

#include <cassert>
#include <cstdlib>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

namespace {

using kelpie::NavigationTracker;
using Progress = NavigationTracker::Progress;

// A wait reads the baseline once, when it starts, then polls Since(baseline).
std::uint64_t WaitStarts(const NavigationTracker& tracker) { return tracker.baseline; }

void ApiNavigation() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  const auto wait = WaitStarts(tab);
  assert(tab.Since(wait) == Progress::kLoading);
  tab.LoadStarted();  // The API's own load commits; it is not counted twice.
  assert(tab.started == 1);
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFinished);
}

void PageNavigationAfterClick() {
  NavigationTracker tab;
  tab.LoadStarted();  // The first page of a fresh tab.
  tab.LoadStopped();
  tab.MarkAction();  // The click is dispatched after this.
  const auto wait = WaitStarts(tab);
  assert(tab.Since(wait) == Progress::kNotStarted);
  tab.LoadStarted();  // The link the click followed commits.
  assert(tab.Since(wait) == Progress::kLoading);
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFinished);
}

void FinishedBeforeTheWaitStarted() {
  NavigationTracker tab;
  tab.MarkAction();
  tab.LoadStarted();
  tab.LoadStopped();
  assert(tab.Since(WaitStarts(tab)) == Progress::kFinished);
}

void NoNavigationAtAll() {
  NavigationTracker tab;
  tab.LoadStarted();
  tab.LoadStopped();
  // A button that does not navigate, or one that only calls history.pushState:
  // neither fires OnLoadStart, so nothing reaches the tracker.
  tab.MarkAction();
  assert(tab.Since(WaitStarts(tab)) == Progress::kNotStarted);
}

void EarlierApiSuccessIsNotReturnedAfterAClick() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  tab.LoadStarted();
  tab.LoadStopped();
  tab.MarkAction();  // A click that does not navigate.
  assert(tab.Since(WaitStarts(tab)) == Progress::kNotStarted);
}

void LoadError() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  const auto wait = WaitStarts(tab);
  tab.LoadFailed("net::ERR_NAME_NOT_RESOLVED");
  assert(tab.Since(wait) == Progress::kFailed);
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFailed);
  assert(tab.error == "net::ERR_NAME_NOT_RESOLVED");
  // The next navigation starts clean.
  tab.ApiNavigationRequested();
  assert(tab.error.empty());
  assert(tab.Since(tab.baseline) == Progress::kLoading);
}

void PageNavigationThatFailsBeforeCommit() {
  NavigationTracker tab;
  tab.LoadStarted();
  tab.LoadStopped();
  tab.MarkAction();
  const auto wait = WaitStarts(tab);
  // CEF never calls OnLoadStart for a navigation that fails before it commits.
  tab.LoadFailed("net::ERR_CONNECTION_REFUSED");
  assert(tab.Since(wait) == Progress::kFailed);
}

void SecondPageLoadWhileTheFirstIsLoading() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  const auto wait = WaitStarts(tab);
  tab.LoadStarted();
  tab.LoadStarted();  // A redirect or script navigation before loading stopped.
  assert(tab.started == 1);
  assert(tab.Since(wait) == Progress::kLoading);
  tab.LoadStopped();  // CEF reports this only once everything has stopped.
  assert(tab.Since(wait) == Progress::kFinished);
}

void AbortedThenCompleted() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  const auto wait = WaitStarts(tab);
  // A later navigation supersedes the first. CEF reports ERR_ABORTED for the
  // first, which the client drops before it reaches the tracker, then the
  // second commits and finishes.
  tab.LoadStarted();
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFinished);
  assert(tab.error.empty());
}

void FailureSupersededByALaterCommit() {
  NavigationTracker tab;
  tab.MarkAction();
  const auto wait = WaitStarts(tab);
  tab.LoadStarted();                  // A commits,
  tab.LoadFailed("net::ERR_FAILED");  // fails after committing,
  tab.LoadStarted();                  // and B commits before loading stops.
  tab.LoadStopped();
  // B is the navigation that landed, and it did not fail.
  assert(tab.Since(wait) == Progress::kFinished);
}

void LoadInFlightAtTheActionStillCounts() {
  NavigationTracker tab;
  tab.ApiNavigationRequested();
  tab.LoadStarted();
  tab.MarkAction();  // An evaluate while the page is still loading.
  const auto wait = WaitStarts(tab);
  assert(tab.Since(wait) == Progress::kLoading);
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFinished);
}

void FreshTabFirstLoadCounts() {
  NavigationTracker tab;
  const auto wait = WaitStarts(tab);
  assert(wait == 0);
  tab.LoadStarted();
  tab.LoadStopped();
  assert(tab.Since(wait) == Progress::kFinished);
}

}  // namespace

int main() {
  ApiNavigation();
  PageNavigationAfterClick();
  FinishedBeforeTheWaitStarted();
  NoNavigationAtAll();
  EarlierApiSuccessIsNotReturnedAfterAClick();
  LoadError();
  PageNavigationThatFailsBeforeCommit();
  SecondPageLoadWhileTheFirstIsLoading();
  AbortedThenCompleted();
  FailureSupersededByALaterCommit();
  LoadInFlightAtTheActionStillCounts();
  FreshTabFirstLoadCounts();
  return 0;
}
