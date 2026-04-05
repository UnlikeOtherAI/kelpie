#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace kelpie {

class RendererInterface {
 public:
  virtual ~RendererInterface() = default;

  // Returns the renderer's decoded textual evaluation result.
  virtual std::string EvaluateJs(const std::string& script) = 0;
  virtual std::vector<std::uint8_t> TakeSnapshot() = 0;
  virtual void LoadUrl(const std::string& url) = 0;
  virtual std::string CurrentUrl() const = 0;
  virtual std::string CurrentTitle() const = 0;
  virtual bool IsLoading() const = 0;
  virtual bool CanGoBack() const = 0;
  virtual bool CanGoForward() const = 0;
  virtual void GoBack() = 0;
  virtual void GoForward() = 0;
  virtual void Reload() = 0;
};

}  // namespace kelpie
