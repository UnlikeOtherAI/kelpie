#include "profile_session.h"
#include "account_protocol.h"
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fstream>
#include <stdexcept>
#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {
void AtomicWrite(const std::filesystem::path& path,const std::string& contents) {
  std::filesystem::create_directories(path.parent_path());
  const auto temp=path.string()+"."+account::RandomAccountValue()+".tmp";
  const int fd=open(temp.c_str(),O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);
  if(fd<0) throw std::runtime_error("Cannot write profile data");
  std::size_t offset=0;
  while(offset<contents.size()) {
    auto written=write(fd,contents.data()+offset,contents.size()-offset);
    if(written<=0) { close(fd); unlink(temp.c_str()); throw std::runtime_error("Cannot save profile data"); }
    offset+=written;
  }
  const bool flushed=fsync(fd)==0; close(fd);
  if(!flushed || rename(temp.c_str(),path.c_str())!=0) {
    unlink(temp.c_str()); throw std::runtime_error("Cannot publish profile data");
  }
}
void ProfileSession::Open(const std::filesystem::path& directory,const std::string& readiness) {
  std::filesystem::create_directories(directory);
  struct stat info{};
  if(lstat(directory.c_str(),&info)!=0 || !S_ISDIR(info.st_mode) || info.st_uid!=getuid())
    throw std::runtime_error("Profile must be a directory owned by the current user");
  if(chmod(directory.c_str(),0700)!=0) throw std::runtime_error("Cannot protect profile directory");
  lock_=open((directory/"profile.lock").c_str(),O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
  if(lock_<0 || flock(lock_,LOCK_EX|LOCK_NB)!=0) throw std::runtime_error("This profile is already in use");
  token_=account::RandomAccountValue(); launch_=account::RandomAccountValue();
  readiness_=readiness.empty()?directory/"readiness.json":std::filesystem::path(readiness);
  std::error_code error; std::filesystem::remove(readiness_,error);
  if(error) throw std::runtime_error("Cannot clear stale readiness");
}
void ProfileSession::Publish(const std::string& id,int port,bool stdio) {
  AtomicWrite(readiness_,nlohmann::json{{"version",1},{"launchId",launch_},{"deviceId",id},
      {"port",port},{"token",token_},{"controlMode","loopback"},
      {"mcp",{{"http",true},{"stdio",stdio},{"endpoint","/mcp"}}}}.dump());
}
void ProfileSession::Clear() {
  if(readiness_.empty()) return;
  std::ifstream input(readiness_); nlohmann::json data=nlohmann::json::parse(input,nullptr,false);
  if(data.is_object() && data.value("launchId","")==launch_) {
    std::error_code error; std::filesystem::remove(readiness_,error);
  }
}
ProfileSession::~ProfileSession() { Clear(); if(lock_>=0) close(lock_); }
}  // namespace kelpie::linuxapp
