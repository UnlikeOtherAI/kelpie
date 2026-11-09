#pragma once

// TEMPORARY: verbatim copy of the desktop-sync discovery interface until
// core/native/desktop-sync lands on this branch. Deleted before the final
// commit; nothing else may be added here.

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace kelpie {

struct SyncPeerAdvert {
  std::string instance;
  std::vector<std::string> addresses;
  int port = 0;
  std::map<std::string, std::string> txt;
};

class SyncDiscovery {
 public:
  virtual ~SyncDiscovery() = default;
  virtual bool Advertise(int port, const std::map<std::string, std::string>& txt) = 0;
  virtual void UpdateTxt(const std::map<std::string, std::string>& txt) = 0;
  virtual void StopAdvertising() = 0;
  virtual bool Browse(std::function<void(const SyncPeerAdvert&)> found,
                      std::function<void(const std::string& instance)> lost) = 0;
  virtual void StopBrowsing() = 0;
};

}  // namespace kelpie
