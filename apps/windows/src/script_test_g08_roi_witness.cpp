#include "script_test_g08_roi_witness.h"
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <utility>

namespace kelpie::windows {
namespace {
std::string HashRoi(const ScriptMediaFrame& frame) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  DWORD object_size = 0, returned = 0;
  std::vector<unsigned char> object, digest(32);
  bool ok = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0;
  if (ok) ok = BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
      reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size), &returned, 0) >= 0 &&
      returned == sizeof(object_size) && object_size > 0 && object_size <= 65536;
  if (ok) { object.resize(object_size); ok = BCryptCreateHash(algorithm, &hash, object.data(), object_size, nullptr, 0, 0) >= 0; }
  std::array<unsigned char, 85 * 85 * 4> roi{};
  for (int y = 161; ok && y <= 245; ++y) {
    const auto offset = static_cast<std::size_t>(y) * frame.stride + 438 * 4;
    std::memcpy(roi.data() + static_cast<std::size_t>(y - 161) * 85 * 4, frame.bgra.data() + offset, 85 * 4);
  }
  if (ok) ok = BCryptHashData(hash, roi.data(), static_cast<ULONG>(roi.size()), 0) >= 0;
  SecureZeroMemory(roi.data(), roi.size());
  if (ok) ok = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0;
  if (hash) BCryptDestroyHash(hash);
  if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
  if (!ok) return {};
  constexpr char hex[] = "0123456789abcdef";
  std::string result; result.reserve(64);
  for (const auto value : digest) { result.push_back(hex[value >> 4]); result.push_back(hex[value & 15]); }
  return result;
}
}  // namespace

bool TestG08RoiWitness::RecordAdmittedFrame(const ScriptMediaFrame& frame) {
  if (!valid_ || finalized_ || rows_.size() >= 800 || frame.width != 640 || frame.height != 406 ||
      frame.stride != 2560 || frame.bgra.size() != static_cast<std::size_t>(frame.stride) * frame.height ||
      !std::isfinite(frame.elapsed_ms) || frame.elapsed_ms < 0) { Invalidate(); return false; }
  if (rows_.empty()) origin_ms_ = frame.elapsed_ms;
  const double normalized = (frame.elapsed_ms - origin_ms_) * 10000.0;
  if (!std::isfinite(normalized) || normalized < 0 || normalized > 33000.0 * 10000.0 ||
      normalized > static_cast<double>(std::numeric_limits<std::int64_t>::max())) { Invalidate(); return false; }
  const auto pts = static_cast<std::int64_t>(std::llround(normalized));
  if (!rows_.empty() && pts <= rows_.back().pts100ns) { Invalidate(); return false; }
  auto digest = HashRoi(frame);
  if (digest.size() != 64) { Invalidate(); return false; }
  rows_.push_back({rows_.size(), pts, std::move(digest)});
  return true;
}
bool TestG08RoiWitness::Finalize(bool partial, const ScriptMediaOutput& output) {
  if (!valid_ || finalized_ || partial || rows_.empty() || output.mime_type != "video/mp4" ||
      output.width != 640 || output.height != 406 || output.dropped_frames != 0 ||
      output.frame_count != rows_.size()) { Invalidate(); return false; }
  finalized_ = true; return true;
}
}  // namespace kelpie::windows
#endif
