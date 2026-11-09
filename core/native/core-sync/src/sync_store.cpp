#include "sync_store.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>

#ifdef _WIN32
#include <io.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace kelpie::sync {
namespace {

constexpr int kFileVersion = 1;

std::filesystem::path PathFrom(const std::string& utf8) {
  return std::filesystem::u8path(utf8);
}

void WriteAtomically(const std::string& utf8_path, const std::string& contents) {
  const auto path = PathFrom(utf8_path);
  std::error_code ignored;
  std::filesystem::create_directories(path.parent_path(), ignored);
  const auto temp = path.parent_path() / (path.filename().u8string() + ".tmp");
#ifdef _WIN32
  FILE* file = _wfopen(temp.wstring().c_str(), L"wb");
  if (file == nullptr) throw SyncError{"IO", "cannot open sync store for writing"};
  const bool written = std::fwrite(contents.data(), 1, contents.size(), file) == contents.size() &&
                       std::fflush(file) == 0 && _commit(_fileno(file)) == 0;
  std::fclose(file);
#else
  ::chmod(path.parent_path().c_str(), 0700);
  const int fd = ::open(temp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) throw SyncError{"IO", "cannot open sync store for writing"};
  std::size_t offset = 0;
  bool written = true;
  while (offset < contents.size()) {
    const auto count = ::write(fd, contents.data() + offset, contents.size() - offset);
    if (count <= 0) {
      written = false;
      break;
    }
    offset += static_cast<std::size_t>(count);
  }
  written = written && ::fsync(fd) == 0;
  ::close(fd);
#endif
  if (!written) {
    std::filesystem::remove(temp, ignored);
    throw SyncError{"IO", "cannot write sync store"};
  }
  std::error_code renamed;
  std::filesystem::rename(temp, path, renamed);
  if (renamed) {
    std::filesystem::remove(temp, ignored);
    throw SyncError{"IO", "cannot replace sync store"};
  }
}

std::optional<nlohmann::json> ReadJsonFile(const std::string& utf8_path) {
  std::ifstream input(PathFrom(utf8_path), std::ios::binary);
  if (!input) return std::nullopt;
  std::ostringstream buffer;
  buffer << input.rdbuf();
  auto parsed = nlohmann::json::parse(buffer.str(), nullptr, false);
  if (parsed.is_discarded()) return nlohmann::json(nullptr);
  return parsed;
}

}  // namespace

std::unique_ptr<SyncStore> SyncStore::Open(const std::string& path, const Options& options) {
  if (options.subject.empty() || options.replica.empty() || options.replica.size() > 64) {
    throw SyncError{"INVALID_OPTIONS", "subject and replica are required"};
  }
  std::unique_ptr<SyncStore> store(new SyncStore());
  store->path_ = path;
  store->subject_ = options.subject;
  store->replica_ = options.replica;
  store->Load(options);
  store->Persist();
  return store;
}

void SyncStore::Load(const Options& options) {
  const auto file = ReadJsonFile(path_);
  if (!file) {
    adoption_ = Adoption::kZeroVersion;  // first sign-in on this device
  } else if (!file->is_object() || file->value("v", 0) != kFileVersion) {
    adoption_ = Adoption::kZeroVersion;  // unreadable: let every peer version win
  } else if (file->value("subject", std::string()) != options.subject) {
    adoption_ = Adoption::kForeign;  // another account's cookies stay local
  } else {
    adoption_ = Adoption::kNormal;
    if (const auto it = file->find("lastHlc"); it != file->end() && it->is_array() && it->size() == 2 &&
                                               (*it)[0].is_number_integer() && (*it)[1].is_number_integer()) {
      last_hlc_.wall = (*it)[0].get<std::int64_t>();
      last_hlc_.counter = (*it)[1].get<std::int64_t>();
    }
    if (const auto it = file->find("entries"); it != file->end() && it->is_array()) {
      for (const auto& stored : *it) {
        auto entry = EntryFromStoredJson(stored);
        if (entry) entries_[entry->Key()] = std::move(*entry);
      }
    }
  }
  last_hlc_.replica = replica_;

  if (options.launch) {
    // The restart lost every session cookie; forgetting them lets peers that
    // still hold them send them back in the first full snapshot.
    for (auto it = entries_.begin(); it != entries_.end();) {
      if (!it->second.deleted && !it->second.expires) {
        it = entries_.erase(it);
      } else {
        ++it;
      }
    }
  }
  warming_ = options.launch;
  first_scan_after_launch_ = options.launch;
  Renumber();
}

void SyncStore::Renumber() {
  std::vector<Entry*> ordered;
  ordered.reserve(entries_.size());
  for (auto& [key, entry] : entries_) ordered.push_back(&entry);
  std::sort(ordered.begin(), ordered.end(), [](const Entry* a, const Entry* b) {
    return a->hlc < b->hlc || (a->hlc == b->hlc && a->Key() < b->Key());
  });
  by_seq_.clear();
  head_ = 0;
  for (Entry* entry : ordered) {
    entry->seq = ++head_;
    by_seq_[entry->seq] = entry->Key();
  }
}

void SyncStore::Persist() const {
  nlohmann::json entries = nlohmann::json::array();
  for (const auto& [key, entry] : entries_) entries.push_back(EntryToStoredJson(entry));
  const nlohmann::json file = {
      {"v", kFileVersion},
      {"subject", subject_},
      {"lastHlc", nlohmann::json::array({last_hlc_.wall, last_hlc_.counter})},
      {"entries", std::move(entries)},
  };
  WriteAtomically(path_, file.dump());
}

void SyncStore::Touch(Entry* entry) {
  if (entry->seq != 0) by_seq_.erase(entry->seq);
  entry->seq = ++head_;
  by_seq_[entry->seq] = entry->Key();
}

void SyncStore::Erase(const std::string& key) {
  const auto it = entries_.find(key);
  if (it == entries_.end()) return;
  by_seq_.erase(it->second.seq);
  entries_.erase(it);
}

Hlc SyncStore::Stamp(std::int64_t now) {
  if (now > last_hlc_.wall) {
    last_hlc_.wall = now;
    last_hlc_.counter = 0;
  } else {
    ++last_hlc_.counter;
  }
  return Hlc{last_hlc_.wall, last_hlc_.counter, replica_};
}

void SyncStore::Observe(const Hlc& remote) {
  if (remote.wall > last_hlc_.wall || (remote.wall == last_hlc_.wall && remote.counter > last_hlc_.counter)) {
    last_hlc_.wall = remote.wall;
    last_hlc_.counter = remote.counter;
  }
}

void SyncStore::RequireIdle() const {
  if (merge_) throw SyncError{"BUSY", "a merge transaction is open"};
}

nlohmann::json SyncStore::Status() const {
  std::size_t tombstones = 0, local_only = 0, unapplied = 0, live = 0;
  for (const auto& [key, entry] : entries_) {
    if (entry.deleted) ++tombstones;
    if (entry.local_only) ++local_only;
    if (entry.unapplied) ++unapplied;
    if (entry.Live()) ++live;
  }
  return {
      {"replica", replica_},       {"head", head_},           {"entries", live},
      {"tombstones", tombstones},  {"localOnly", local_only}, {"unapplied", unapplied},
      {"skipped", skipped_},       {"warming", warming_},     {"merging", merge_.has_value()},
      {"lastPurgeAt", last_purge_at_ == 0 ? nlohmann::json(nullptr) : nlohmann::json(last_purge_at_)},
  };
}

nlohmann::json SyncStore::Watermark(const std::string& replica) const {
  const auto it = watermarks_.find(replica);
  return {{"replica", replica}, {"seq", it == watermarks_.end() ? 0 : it->second}};
}

}  // namespace kelpie::sync
