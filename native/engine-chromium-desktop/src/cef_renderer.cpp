#include "kelpie/cef_renderer.h"

#include <stdexcept>

namespace kelpie {

CefRenderer::CefRenderer() = default;

CefRenderer::CefRenderer(Callbacks callbacks) : callbacks_(std::move(callbacks)) {}

void CefRenderer::SetCallbacks(Callbacks callbacks) {
  std::lock_guard<std::mutex> lock(mutex_);
  callbacks_ = std::move(callbacks);
}

std::string CefRenderer::EvaluateJs(const std::string& script) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!callbacks_.evaluate_js) {
    throw std::runtime_error("EvaluateJs callback is not configured");
  }
  return callbacks_.evaluate_js(script);
}

std::vector<std::uint8_t> CefRenderer::TakeSnapshot() {
  std::lock_guard<std::mutex> lock(mutex_);
  return callbacks_.take_snapshot ? callbacks_.take_snapshot() : std::vector<std::uint8_t>{};
}

void CefRenderer::LoadUrl(const std::string& url) {
  std::lock_guard<std::mutex> lock(mutex_);
  InvokeVoid([&]() { callbacks_.load_url(url); });
}

std::string CefRenderer::CurrentUrl() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return InvokeString(callbacks_.current_url);
}

std::string CefRenderer::CurrentTitle() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return InvokeString(callbacks_.current_title);
}

bool CefRenderer::IsLoading() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return InvokeBool(callbacks_.is_loading);
}

bool CefRenderer::CanGoBack() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return InvokeBool(callbacks_.can_go_back);
}

bool CefRenderer::CanGoForward() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return InvokeBool(callbacks_.can_go_forward);
}

void CefRenderer::GoBack() {
  std::lock_guard<std::mutex> lock(mutex_);
  InvokeVoid(callbacks_.go_back);
}

void CefRenderer::GoForward() {
  std::lock_guard<std::mutex> lock(mutex_);
  InvokeVoid(callbacks_.go_forward);
}

void CefRenderer::Reload() {
  std::lock_guard<std::mutex> lock(mutex_);
  InvokeVoid(callbacks_.reload);
}

std::string CefRenderer::InvokeString(const StringCallback& callback) {
  return callback ? callback() : std::string();
}

bool CefRenderer::InvokeBool(const BoolCallback& callback) {
  return callback ? callback() : false;
}

void CefRenderer::InvokeVoid(const VoidCallback& callback) {
  if (callback) {
    callback();
  }
}

}  // namespace kelpie
