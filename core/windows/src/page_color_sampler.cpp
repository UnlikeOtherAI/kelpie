#include "page_color_sampler.h"
#include <algorithm>
#include <objidl.h>
#include <gdiplus.h>
#include <wincrypt.h>
#include <vector>

namespace kelpie::windows {
namespace {
std::optional<COLORREF> AverageEdge(const std::string& encoded) {
  if (encoded.empty() || encoded.size() > 16*1024*1024) return std::nullopt;
  DWORD size = 0;
  if (!CryptStringToBinaryA(encoded.data(), static_cast<DWORD>(encoded.size()), CRYPT_STRING_BASE64,
                           nullptr, &size, nullptr, nullptr)) return std::nullopt;
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!memory) return std::nullopt;
  auto* bytes = static_cast<BYTE*>(GlobalLock(memory));
  const bool decoded = bytes && CryptStringToBinaryA(encoded.data(), static_cast<DWORD>(encoded.size()),
      CRYPT_STRING_BASE64, bytes, &size, nullptr, nullptr);
  GlobalUnlock(memory);
  if (!decoded) { GlobalFree(memory); return std::nullopt; }
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(memory, TRUE, &stream))) { GlobalFree(memory); return std::nullopt; }
  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) { stream->Release(); return std::nullopt; }
  std::optional<COLORREF> result;
  {
    Gdiplus::Bitmap bitmap(stream);
    const UINT width = bitmap.GetWidth(), height = bitmap.GetHeight();
    if (bitmap.GetLastStatus()==Gdiplus::Ok && width>0 && height>0 &&
        width<=16384 && height<=16384 && static_cast<std::uint64_t>(width)*height<=32000000) {
      unsigned long red=0, green=0, blue=0, count=0;
      for (UINT y=0; y<std::min(height,24U); y+=2) for (UINT x=0; x<width; x+=std::max(1U,width/256)) {
        Gdiplus::Color c;
        if (bitmap.GetPixel(x,y,&c)==Gdiplus::Ok) { red+=c.GetR(); green+=c.GetG(); blue+=c.GetB(); ++count; }
      }
      if (count) result=RGB(red/count,green/count,blue/count);
    }
  }
  Gdiplus::GdiplusShutdown(token);
  stream->Release();
  return result;
}
}

std::optional<COLORREF> PageColorSampler::Poll(DesktopBrowserControl& engine,
                                               const TabSnapshot& tab, std::uint64_t now) {
  std::optional<COLORREF> result;
  const bool changed = tab.id != tab_id_ || tab.generation != generation_ ||
      tab.url != url_ || (tab.is_loading && !loading_);
  if (changed) {
    ++epoch_;
    tab_id_ = tab.id;
    generation_ = tab.generation;
    url_ = tab.url;
    next_sample_ = now;
  }
  loading_ = tab.is_loading;
  if (pending_.valid() && pending_.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
    const auto sample = pending_.get();
    if (sample.epoch == epoch_ && sample.url == url_ && sample.color) result = sample.color;
  }
  if (pending_.valid() || tab.is_loading || now < next_sample_ || ui::HighContrast()) return result;
  next_sample_ = now + 500;
  const auto epoch = epoch_;
  const TabLease lease{tab.id, tab.generation};
  pending_ = std::async(std::launch::async, [&engine, lease, epoch] {
    Result sample{epoch, {}, std::nullopt};
    try {
      nlohmann::json appearance;
      if (!engine.ReadAppearance(lease, &appearance, std::chrono::milliseconds(400)).ok) return sample;
      sample.url = appearance.at("url").get<std::string>();
      sample.color = AverageEdge(appearance.at("data").get<std::string>());
    } catch (...) {
      // A closed renderer or malformed page result cannot break chrome.
    }
    return sample;
  });
  return result;
}

bool PageColorSampler::Drain() {
  if (!pending_.valid()) return true;
  if (pending_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return false;
  pending_.get();
  return true;
}

}  // namespace kelpie::windows
