#include "profile_session.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <sys/stat.h>
#include <unistd.h>
#include <nlohmann/json.hpp>

int main() {
  char path[]="/tmp/kelpie-profile-test-XXXXXX";
  const auto* created=mkdtemp(path); assert(created);
  const std::filesystem::path root(created);
  {
    kelpie::linuxapp::ProfileSession session;
    session.Open(root,{});
    bool rejected=false;
    try { kelpie::linuxapp::ProfileSession other; other.Open(root,{}); }
    catch (const std::exception&) { rejected=true; }
    assert(rejected);
    session.Publish("test-device",8420,false);
    struct stat info{}; assert(stat((root/"readiness.json").c_str(),&info)==0);
    assert((info.st_mode&0777)==0600);
    std::ifstream input(root/"readiness.json"); nlohmann::json readiness; input>>readiness;
    assert(readiness["token"]==session.token());
    assert(readiness["port"]==8420);
    session.Clear(); assert(!std::filesystem::exists(root/"readiness.json"));
    kelpie::linuxapp::AtomicWrite(root/"readiness.json","{\"launchId\":\"newer-launch\"}");
    session.Clear(); assert(std::filesystem::exists(root/"readiness.json"));
  }
  {
    kelpie::linuxapp::ProfileSession next; next.Open(root,{});
    assert(!std::filesystem::exists(root/"readiness.json"));
    next.Publish("test-device",8421,false);
  }
  assert(!std::filesystem::exists(root/"readiness.json"));
  std::filesystem::remove_all(root);
}
