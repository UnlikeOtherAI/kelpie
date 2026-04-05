#pragma once

#include <cstdint>
#include <functional>
#include <string>

namespace kelpie {

using DownloadProgressCb = std::function<void(int64_t downloaded, int64_t total)>;

class ModelStore {
 public:
  explicit ModelStore(std::string models_dir);

  bool is_downloaded(const std::string& model_id) const;
  std::string model_path(const std::string& model_id) const;
  bool remove(const std::string& model_id);

  // Downloads model with auth. Returns empty string on success, error JSON on failure.
  // This is blocking — platforms wrap in async.
  std::string download(const std::string& model_id,
                       const std::string& hf_token,
                       DownloadProgressCb progress_cb);

 private:
  std::string models_dir_;
  std::string model_dir(const std::string& model_id) const;
};

}  // namespace kelpie
