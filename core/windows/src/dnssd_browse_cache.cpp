#include "dnssd_browse_cache.h"

#include <algorithm>
#include <cctype>

namespace kelpie::windows {
namespace {

std::string Lower(std::string value) {
  for (char& c : value) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return value;
}

// DNS names compare without a trailing root dot.
std::string Normalize(const std::string& name) {
  std::string lower = Lower(name);
  while (!lower.empty() && lower.back() == '.') lower.pop_back();
  return lower;
}

bool EndsWith(const std::string& value, const std::string& suffix) {
  return value.size() > suffix.size() &&
         value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

DnsSdBrowseCache::Clock::time_point Until(DnsSdBrowseCache::Clock::time_point now, std::uint32_t ttl) {
  return now + std::chrono::seconds(ttl);
}

}  // namespace

DnsSdBrowseCache::DnsSdBrowseCache(std::string service) : service_(Normalize(service)) {}

void DnsSdBrowseCache::SetOwnInstance(const std::string& full_name) { own_ = Normalize(full_name); }

std::optional<std::string> DnsSdBrowseCache::InstanceKey(const std::string& full_name) const {
  std::string key = Normalize(full_name);
  if (!EndsWith(key, "." + service_) || key == own_) return std::nullopt;
  return key;
}

std::string DnsSdBrowseCache::Label(const std::string& full_name) const {
  std::string name = full_name;
  while (!name.empty() && name.back() == '.') name.pop_back();
  return name.substr(0, name.size() - service_.size() - 1);
}

DnsSdBrowseCache::Result DnsSdBrowseCache::Apply(const std::vector<DnsSdRecord>& records,
                                                 Clock::time_point now) {
  Result result;
  std::set<std::string> touched;
  std::set<std::string> removed;
  std::set<std::string> touched_hosts;
  // PTRs first: SRV and TXT are accepted only for an instance the browse knows.
  for (const auto& record : records) {
    if (record.type != DnsSdRecord::Type::kPtr || Normalize(record.name) != service_) continue;
    const auto key = InstanceKey(record.target);
    if (!key) continue;
    if (record.ttl == 0) {
      removed.insert(*key);
      continue;
    }
    removed.erase(*key);
    auto& instance = instances_[*key];
    if (instance.label.empty()) instance.label = Label(record.target);
    instance.expires = Until(now, record.ttl);
    touched.insert(*key);
  }
  for (const auto& record : records) {
    if (record.type == DnsSdRecord::Type::kAddress) {
      const std::string host = Normalize(record.name);
      if (record.address.empty() || host.empty()) continue;
      auto& addresses = hosts_[host];
      if (record.ttl == 0) {
        addresses.erase(record.address);
      } else {
        addresses[record.address] = std::max(Until(now, record.ttl), now + kMinAddressLifetime);
      }
      touched_hosts.insert(host);
      continue;
    }
    if (record.type != DnsSdRecord::Type::kSrv && record.type != DnsSdRecord::Type::kTxt) continue;
    const auto key = InstanceKey(record.name);
    if (!key) continue;
    const auto instance = instances_.find(*key);
    if (instance == instances_.end()) continue;
    if (record.type == DnsSdRecord::Type::kSrv) {
      instance->second.host = record.ttl == 0 ? std::string() : Normalize(record.target);
      instance->second.port = record.ttl == 0 ? 0 : record.port;
    } else if (record.ttl == 0) {
      instance->second.txt.reset();
    } else {
      instance->second.txt = DecodeSyncTxt(record.txt);
    }
    touched.insert(*key);
  }
  for (const auto& key : removed) {
    touched.erase(key);
    Erase(key, &result);
  }
  for (const auto& [key, instance] : instances_) {
    if (touched_hosts.count(instance.host) != 0) touched.insert(key);
  }
  Collect(touched, now, &result);
  return result;
}

DnsSdBrowseCache::Result DnsSdBrowseCache::Resolved(const std::string& full_name, const std::string& host,
                                                    int port, const std::vector<std::string>& txt,
                                                    const std::vector<std::string>& addresses,
                                                    Clock::time_point now) {
  Result result;
  const auto key = InstanceKey(full_name);
  if (!key) return result;
  const auto found = instances_.find(*key);
  // A goodbye can arrive while the resolve runs; never resurrect the instance.
  if (found == instances_.end()) return result;
  auto& instance = found->second;
  if (instance.host.empty()) instance.host = Normalize(host);
  if (instance.port == 0) instance.port = port;
  if (!instance.txt) instance.txt = DecodeSyncTxt(txt);
  for (const auto& address : addresses) {
    if (!address.empty()) instance.resolved_addresses[address] = std::max(instance.expires, now + kMinAddressLifetime);
  }
  Collect({*key}, now, &result);
  return result;
}

DnsSdBrowseCache::Result DnsSdBrowseCache::Expire(Clock::time_point now) {
  Result result;
  std::set<std::string> touched;
  std::set<std::string> touched_hosts;
  for (auto& [host, addresses] : hosts_) {
    for (auto address = addresses.begin(); address != addresses.end();) {
      if (address->second <= now) {
        address = addresses.erase(address);
        touched_hosts.insert(host);
      } else {
        ++address;
      }
    }
  }
  for (auto host = hosts_.begin(); host != hosts_.end();) {
    host = host->second.empty() ? hosts_.erase(host) : std::next(host);
  }
  std::vector<std::string> expired;
  for (auto& [key, instance] : instances_) {
    if (instance.expires <= now) {
      expired.push_back(key);
      continue;
    }
    for (auto address = instance.resolved_addresses.begin(); address != instance.resolved_addresses.end();) {
      if (address->second <= now) {
        address = instance.resolved_addresses.erase(address);
        touched.insert(key);
      } else {
        ++address;
      }
    }
    if (touched_hosts.count(instance.host) != 0) touched.insert(key);
  }
  for (const auto& key : expired) Erase(key, &result);
  Collect(touched, now, &result);
  return result;
}

void DnsSdBrowseCache::Clear() {
  instances_.clear();
  hosts_.clear();
}

SyncPeerView DnsSdBrowseCache::View(const Instance& instance, Clock::time_point now) const {
  SyncPeerView view;
  view.port = instance.port;
  if (instance.txt) view.txt = *instance.txt;
  const auto host = hosts_.find(instance.host);
  if (host != hosts_.end()) {
    for (const auto& [address, expires] : host->second) {
      if (expires > now) view.addresses.push_back(address);
    }
  }
  for (const auto& [address, expires] : instance.resolved_addresses) {
    if (expires > now) view.addresses.push_back(address);
  }
  return view;
}

void DnsSdBrowseCache::Collect(const std::set<std::string>& touched, Clock::time_point now,
                               Result* result) const {
  for (const auto& key : touched) {
    const auto found = instances_.find(key);
    if (found == instances_.end()) continue;
    const auto& instance = found->second;
    SyncPeerView view = View(instance, now);
    if (instance.port == 0 || !instance.txt || view.addresses.empty()) result->resolve.push_back(key);
    result->changes.push_back({instance.label, std::move(view)});
  }
}

void DnsSdBrowseCache::Erase(const std::string& key, Result* result) {
  const auto found = instances_.find(key);
  if (found == instances_.end()) return;
  result->changes.push_back({found->second.label, std::nullopt});
  instances_.erase(found);
}

}  // namespace kelpie::windows
