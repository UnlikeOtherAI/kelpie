#include "model_store.h"
#include "model_catalog.h"

#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>

#include <httplib.h>

namespace fs = std::filesystem;

namespace mollotov {

ModelStore::ModelStore(std::string models_dir)
    : models_dir_(std::move(models_dir)) {}

std::string ModelStore::model_dir(const std::string& model_id) const {
  return models_dir_ + "/" + model_id;
}

std::string ModelStore::model_path(const std::string& model_id) const {
  return model_dir(model_id) + "/model.gguf";
}

bool ModelStore::is_downloaded(const std::string& model_id) const {
  const std::string path = model_path(model_id);
  std::error_code ec;
  if (!fs::exists(path, ec)) return false;
  auto size = fs::file_size(path, ec);
  return !ec && size > 1'000'000;  // Must be > 1 MB (reject HTML error pages)
}

bool ModelStore::remove(const std::string& model_id) {
  const std::string dir = model_dir(model_id);
  std::error_code ec;
  if (!fs::exists(dir, ec)) return false;
  fs::remove_all(dir, ec);
  return !ec;
}

std::string ModelStore::download(const std::string& model_id,
                                 const std::string& hf_token,
                                 DownloadProgressCb progress_cb) {
  using json = nlohmann::json;

  const auto* model = ModelCatalog::find(model_id);
  if (!model) {
    return json{{"error", "not_found"},
                {"message", "Unknown model ID: " + model_id}}.dump();
  }

  // Parse download URL
  const std::string url = model->download_url();
  const std::string host = "huggingface.co";
  auto path_start = url.find(host);
  if (path_start == std::string::npos) {
    return json{{"error", "internal"}, {"message", "Bad download URL"}}.dump();
  }
  std::string path = url.substr(path_start + host.size());

  // Create model directory
  const std::string dir = model_dir(model_id);
  std::error_code ec;
  fs::create_directories(dir, ec);
  if (ec) {
    return json{{"error", "filesystem"},
                {"message", "Cannot create directory: " + dir}}.dump();
  }

  const std::string download_path = dir + "/model.gguf.download";
  const std::string final_path = dir + "/model.gguf";

  // Create HTTPS client
  httplib::SSLClient client(host);
  client.set_follow_location(true);
  client.set_connection_timeout(30);
  client.set_read_timeout(600);  // 10 min for large downloads

  httplib::Headers headers;
  if (!hf_token.empty()) {
    headers.emplace("Authorization", "Bearer " + hf_token);
  }

  // Stream download to file
  std::ofstream ofs(download_path, std::ios::binary);
  if (!ofs) {
    return json{{"error", "filesystem"},
                {"message", "Cannot create download file"}}.dump();
  }

  int64_t downloaded = 0;

  auto res = client.Get(
      path, headers,
      [&](const httplib::Response& response) -> bool {
        if (response.status == 401 || response.status == 403) {
          return false;
        }
        return true;
      },
      [&](const char* data, size_t len) -> bool {
        ofs.write(data, static_cast<std::streamsize>(len));
        downloaded += static_cast<int64_t>(len);
        if (progress_cb) {
          progress_cb(downloaded, 0);
        }
        return true;
      });

  ofs.close();

  if (!res) {
    fs::remove(download_path, ec);
    return json{{"error", "network"},
                {"message", "Download failed: connection error"}}.dump();
  }

  if (res->status == 401 || res->status == 403) {
    fs::remove(download_path, ec);
    std::string msg = hf_token.empty()
        ? "This model requires a Hugging Face token. Set one in the Models tab."
        : "Hugging Face rejected your token. Check it on the settings page.";
    return json{{"error", "auth_required"}, {"message", msg}}.dump();
  }

  if (res->status != 200) {
    fs::remove(download_path, ec);
    return json{{"error", "http"},
                {"message", "HTTP " + std::to_string(res->status)}}.dump();
  }

  // Validate file size — reject small HTML error pages
  auto file_size = fs::file_size(download_path, ec);
  if (ec || file_size < 1'000'000) {
    std::ifstream check(download_path);
    std::string snippet(200, '\0');
    check.read(snippet.data(), 200);
    snippet.resize(static_cast<size_t>(check.gcount()));
    fs::remove(download_path, ec);

    if (snippet.find("Invalid") != std::string::npos ||
        snippet.find("Access") != std::string::npos ||
        snippet.find("login") != std::string::npos ||
        snippet.find("<!DOCTYPE") != std::string::npos) {
      return json{{"error", "auth_required"},
                  {"message",
                   "Download failed — Hugging Face returned an auth error."}}
          .dump();
    }
    return json{{"error", "validation"},
                {"message", "Downloaded file is too small (" +
                                std::to_string(file_size) + " bytes)"}}
        .dump();
  }

  // Atomically move to final path
  fs::rename(download_path, final_path, ec);
  if (ec) {
    fs::remove(download_path, ec);
    return json{{"error", "filesystem"},
                {"message", "Failed to finalize download"}}.dump();
  }

  // Write metadata.json
  json metadata = model->to_json();
  metadata["downloaded_at"] = "now";
  std::ofstream meta_file(dir + "/metadata.json");
  meta_file << metadata.dump(2);

  return "";  // Success
}

}  // namespace mollotov
