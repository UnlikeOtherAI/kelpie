#pragma once
// Test builds only: numeric frame-admission evidence; no page or user content.
#include <fcntl.h>
#include <unistd.h>
#include <cmath>
#include <cstdlib>
#include <mutex>
#include <set>
#include <string>
#include <stdexcept>
#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {
inline bool AdmissionTraceEnabled() { return std::getenv("KELPIE_LINUX_TEST_ADMISSION_TRACE") != nullptr; }
inline void WriteAdmissionTrace(const nlohmann::json& row) {
  if (!AdmissionTraceEnabled()) return;
  if (!row.is_object() || row.size()>16) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  static const std::set<std::string> allowed={"phase","elapsedMs","markerStartMs","markerDurationMs",
    "markerAgeMs","hasMarker","previousMovieMs","due","committedBefore","committedAfter",
    "actionIndex","stepPng","admittedIndex","gifFrames","videoFrames","gifDropped","videoDropped"};
  for (const auto& item : row.items()) {
    if (!allowed.contains(item.key())) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
    if (!item.value().is_number() || !std::isfinite(item.value().get<double>()))
      throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  }
  static std::mutex mutex; static int fd=-1; static std::size_t rows=0;
  std::lock_guard lock(mutex);
  if (++rows>1200) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  if (fd<0) {
    const char* path=std::getenv("KELPIE_LINUX_TEST_ADMISSION_TRACE");
    if (!path || path[0]!='/') throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
    fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  }
  const std::string line=row.dump()+"\n"; std::size_t offset=0;
  while (offset<line.size()) {
    const auto count=write(fd,line.data()+offset,line.size()-offset);
    if (count<=0) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
    offset+=std::size_t(count);
  }
}
}
