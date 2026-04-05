#include "stub_renderer.h"

#include <utility>

#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {

StubRenderer::StubRenderer(std::string initial_url) {
  NavigateInternal(initial_url.empty() ? "about:blank" : std::move(initial_url), true);
}

std::string StubRenderer::EvaluateJs(const std::string& script) {
  using json = nlohmann::json;
  std::lock_guard<std::mutex> lock(mutex_);
  const std::string trimmed = script;
  if (trimmed.find("document.title") != std::string::npos) {
    return trimmed.rfind("JSON.stringify((", 0) == 0 ? json(title_).dump() : title_;
  }
  if (trimmed.find("location.href") != std::string::npos) {
    return trimmed.rfind("JSON.stringify((", 0) == 0 ? json(current_url_).dump() : current_url_;
  }
  if (trimmed.rfind("JSON.stringify((", 0) == 0) {
    return json("CEF unavailable; expression was not executed").dump();
  }
  return "CEF unavailable; expression was not executed";
}

std::vector<std::uint8_t> StubRenderer::TakeSnapshot() {
  return {};
}

void StubRenderer::LoadUrl(const std::string& url) {
  std::lock_guard<std::mutex> lock(mutex_);
  NavigateInternal(url, false);
}

std::string StubRenderer::CurrentUrl() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return current_url_;
}

std::string StubRenderer::CurrentTitle() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return title_;
}

bool StubRenderer::IsLoading() const {
  return false;
}

bool StubRenderer::CanGoBack() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return index_ > 0;
}

bool StubRenderer::CanGoForward() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return index_ + 1 < history_.size();
}

void StubRenderer::GoBack() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (index_ > 0) {
    --index_;
    ApplyHistoryEntry();
  }
}

void StubRenderer::GoForward() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (index_ + 1 < history_.size()) {
    ++index_;
    ApplyHistoryEntry();
  }
}

void StubRenderer::Reload() {}

bool StubRenderer::SupportsScreenshots() const {
  return false;
}

std::string StubRenderer::TitleForUrl(const std::string& url) {
  if (url.find("example.com") != std::string::npos) {
    return "Example Domain";
  }
  if (url == "about:blank") {
    return "Blank";
  }
  const std::size_t scheme = url.find("://");
  const std::size_t start = scheme == std::string::npos ? 0 : scheme + 3;
  const std::size_t end = url.find('/', start);
  return end == std::string::npos ? url.substr(start) : url.substr(start, end - start);
}

void StubRenderer::NavigateInternal(const std::string& url, bool replace) {
  current_url_ = url;
  title_ = TitleForUrl(url);
  if (replace) {
    history_ = {url};
    index_ = 0;
    return;
  }
  history_.erase(history_.begin() + static_cast<long>(index_ + 1), history_.end());
  history_.push_back(url);
  index_ = history_.size() - 1;
}

void StubRenderer::ApplyHistoryEntry() {
  current_url_ = history_[index_];
  title_ = TitleForUrl(current_url_);
}

}  // namespace kelpie::linuxapp
