#pragma once
// Only compiled into the explicitly enabled test binary.
#include <openssl/evp.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdlib>
#include <mutex>
#include <stdexcept>
#include <vector>

namespace kelpie::linuxapp {
inline nlohmann::json ObserveG08Backing(const ScriptFrame& frame, const ScriptFrameSourceSize& source,
    const nlohmann::json& shown, const std::string& run, std::size_t sequence) {
  if (!std::getenv("KELPIE_G08_TEST_BACKING_PATH")) return nullptr;
  constexpr int left=445, top=190, width=71, height=71;
  if (sequence>=600 || frame.width<left+width || frame.height<top+height || run.size()>128)
    throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  std::vector<unsigned char> roi; roi.reserve(width*height*4);
  for (int y=top; y<top+height; ++y) {
    const auto begin=frame.bgra.begin()+std::size_t(y)*frame.stride+left*4;
    roi.insert(roi.end(),begin,begin+width*4);
  }
  unsigned char digest[EVP_MAX_MD_SIZE]; unsigned length=0;
  if (EVP_Digest(roi.data(),roi.size(),digest,&length,EVP_sha256(),nullptr)!=1 || length!=32)
    throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  const char hex[]="0123456789abcdef"; std::string hash; hash.reserve(64);
  for (unsigned i=0;i<length;++i) { hash+=hex[digest[i]>>4]; hash+=hex[digest[i]&15]; }
  std::string bytes((roi.size()+2)/3*4,'\0');
  if (EVP_EncodeBlock(reinterpret_cast<unsigned char*>(bytes.data()),roi.data(),int(roi.size())) != int(bytes.size()))
    throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  return {{"pid",getpid()},{"run",run},{"sequence",sequence},{"elapsedMs",frame.elapsed_ms},
    {"frameWidth",frame.width},{"frameHeight",frame.height},{"stride",frame.stride},
    {"sourceWidth",source.width},{"sourceHeight",source.height},
    {"viewportWidth",shown.at("viewportWidth")},{"viewportHeight",shown.at("viewportHeight")},
    {"visualViewport",shown.at("visualViewport")},{"documentId",shown.at("documentVersion")},
    {"roi",{left,top,width,height}},{"bgraSHA256",hash},{"bgraBase64",bytes}};
}
inline void WriteG08Backing(const nlohmann::json& record) {
  if (record.is_null()) return;
  static std::mutex mutex; static int fd=-1;
  std::lock_guard lock(mutex);
  if (fd<0) {
    const char* path=std::getenv("KELPIE_G08_TEST_BACKING_PATH");
    if (!path || path[0]!='/') throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
    fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  }
  const std::string line=record.dump()+"\n"; std::size_t offset=0;
  while (offset<line.size()) {
    const auto count=write(fd,line.data()+offset,line.size()-offset);
    if (count<=0) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
    offset+=std::size_t(count);
  }
}
}
