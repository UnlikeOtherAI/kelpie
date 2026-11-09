#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <unordered_set>

#include "kelpie/desktop_engine.h"
#include "kelpie/history_store.h"
#include "kelpie/site_preview_capture.h"
#include "kelpie/site_preview_store.h"
#include "kelpie/start_page.h"

namespace kelpie {

// Everything `kelpie://start` needs from the running app: the payload built
// from the shared bookmark and history stores, the persistent site screenshot
// store, and the worker that keeps those screenshots current.
//
// DesktopApp owns one. The capture worker reads the engine, so the app stops
// it, and waits for it, before it shuts the engine down.
class DesktopStartPage {
 public:
  DesktopStartPage(DesktopEngine& engine, HistoryStore& history,
                   std::function<std::string()> bookmarks_json);
  ~DesktopStartPage();

  // Opens the screenshot store at `previews_path` (empty keeps it in memory)
  // and points the engine's `kelpie://start` suppliers at this object. Must run
  // before the engine initializes.
  void Configure(const std::filesystem::path& previews_path, DesktopEngine::Config& engine_config);

  void StartCapture();
  // Called from the engine's navigation sink on every navigation event.
  void NotifyNavigation();
  void BeginStop();
  bool IsStopped() const;
  // Joins the capture worker. Call once IsStopped() is true.
  void Stop();

 private:
  std::unordered_set<std::string> FavouriteHosts() const;
  start_page::SiteImages SiteImagesFor(const std::string& host);

  DesktopEngine& engine_;
  HistoryStore& history_;
  std::function<std::string()> bookmarks_json_;
  std::unique_ptr<SitePreviewStore> previews_;
  std::unique_ptr<SitePreviewCapture> capture_;
};

}  // namespace kelpie
