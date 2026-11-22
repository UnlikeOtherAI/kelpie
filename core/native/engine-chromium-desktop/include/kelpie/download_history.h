#pragma once

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace kelpie {

// Owned by the browser window/session. Both CEF callbacks and native controls use its UI thread.
class DownloadHistory {
 public:
  enum class State { downloading, complete, failed };
  struct Item {
    uint64_t id;
    std::filesystem::path path;
    std::string name;
    State state;
  };

  std::function<void(bool)> visibility_changed;
  const std::vector<Item>& items() const { return items_; }
  uint64_t revision() const { return revision_; }

  std::filesystem::path Begin(uint64_t id, std::string name, const std::filesystem::path& directory) {
    // Chromium normally supplies a basename. Enforce it at the filesystem boundary too.
    const auto slash = name.find_last_of("/\\");
    if (slash != std::string::npos) name.erase(0, slash + 1);
    for (auto& ch : name) {
      if (static_cast<unsigned char>(ch) < 32 || std::string("<>:\"|?*").find(ch) != std::string::npos) ch = '_';
    }
    const auto first = name.find_first_not_of(". ");
    name = first == std::string::npos ? "download" : name.substr(first);
    name.erase(name.find_last_not_of(". ") + 1);
    if (name.size() > 180) {
      size_t end = 180;
      while (end && (static_cast<unsigned char>(name[end]) & 0xc0) == 0x80) --end;
      name.resize(end);
    }
    auto device = name.substr(0, name.find('.'));
    for (auto& ch : device) if (ch >= 'a' && ch <= 'z') ch -= 'a' - 'A';
    if (device == "CON" || device == "PRN" || device == "AUX" || device == "NUL" ||
        (device.size() == 4 && (device.substr(0, 3) == "COM" || device.substr(0, 3) == "LPT") &&
         device.back() >= '0' && device.back() <= '9')) name.insert(0, "_");
    std::error_code error;
    std::filesystem::path path;
    if (!directory.empty() && directory.is_absolute()) {
      std::filesystem::create_directories(directory, error);
      const auto original = std::filesystem::u8path(name);
      for (unsigned n = 0; !error && n < 10000; ++n) {
        auto leaf = original;
        if (n) leaf = std::filesystem::u8path(Utf8(original.stem()) + " (" + std::to_string(n) + ")" +
                                               Utf8(original.extension()));
        auto candidate = directory / leaf;
        const auto existing = std::filesystem::symlink_status(candidate, error);
        if (error == std::errc::no_such_file_or_directory) error.clear();
        if (error) break;
        if (std::filesystem::exists(existing)) continue;
        // Use case-insensitive comparison even on case-sensitive volumes so concurrent transfers
        // cannot alias on a case-insensitive Downloads drive.
        auto key = [](const std::filesystem::path& p) {
          auto s = Utf8(p);
          for (auto& ch : s) if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
          return s;
        };
        if (std::any_of(items_.begin(), items_.end(), [&](const Item& item) {
              return item.state == State::downloading && key(item.path) == key(candidate);
            })) continue;
        path = std::move(candidate);
        break;
      }
    }
    const bool was_empty = items_.empty();
    items_.insert(items_.begin(), {id, path, path.empty() ? name : Utf8(path.filename()),
                                   path.empty() ? State::failed : State::downloading});
    Changed();
    if (was_empty && visibility_changed) visibility_changed(true);
    return path;
  }

  void Finish(uint64_t id, bool complete) {
    for (auto& item : items_) {
      if (item.id != id || item.state != State::downloading) continue;
      std::error_code error;
      item.state = complete && std::filesystem::is_regular_file(item.path, error) ? State::complete : State::failed;
      Changed();
      return;
    }
  }

  void ClearFinished() {
    const bool was_empty = items_.empty();
    items_.erase(std::remove_if(items_.begin(), items_.end(),
                                [](const Item& item) { return item.state != State::downloading; }), items_.end());
    ++revision_;
    if (!was_empty && items_.empty() && visibility_changed) visibility_changed(false);
  }

  static const char* Label(State state) {
    if (state == State::complete) return "Complete";
    if (state == State::failed) return "Failed";
    return "Downloading...";
  }

 private:
  static std::string Utf8(const std::filesystem::path& path) {
    const auto value = path.u8string();
    return {value.begin(), value.end()};
  }

  void Changed() {
    ++revision_;
    while (items_.size() > 200) {
      auto oldest = std::find_if(items_.rbegin(), items_.rend(), [](const Item& i) { return i.state != State::downloading; });
      if (oldest == items_.rend()) break;
      items_.erase(std::next(oldest).base());
    }
  }

  std::vector<Item> items_;
  uint64_t revision_ = 0;
};
}  // namespace kelpie
