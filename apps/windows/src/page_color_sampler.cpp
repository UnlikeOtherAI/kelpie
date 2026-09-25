#include "page_color_sampler.h"
#include <algorithm>
#include <objidl.h>
#include <gdiplus.h>
#include <wincrypt.h>
#include <vector>

namespace kelpie::windows {
namespace {
// Read only viewport metadata; the color comes from Chromium's rendered pixels.
constexpr char kViewport[] = R"JS(({url:location.href,x:scrollX,y:scrollY,width:innerWidth,height:innerHeight,time:performance.timeOrigin}))JS";

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
      nlohmann::json viewport, captured, after;
      const auto timeout = std::chrono::milliseconds(400);
      if (!engine.Evaluate(lease, kViewport, &viewport, timeout).ok || !viewport.is_object()) return sample;
      const double width = viewport.value("width", 0.0), height = viewport.value("height", 0.0);
      if (width<=0 || width>32768 || height<=0) return sample;
      // Alloy resizes its live native view when CDP's clip option is present.
      // Capture the existing view without emulation; average only its top band.
      const nlohmann::json params{{"format","png"},{"fromSurface",true},
                                  {"captureBeyondViewport",false}};
      if (!engine.DevTools(lease,"Page.captureScreenshot",params,&captured,timeout).ok ||
          !captured.is_object() || !captured.contains("data") || !captured["data"].is_string()) return sample;
      if (!engine.Evaluate(lease,kViewport,&after,timeout).ok ||
          after.value("url","") != viewport.value("url","") ||
          after.value("time",0.0) != viewport.value("time",0.0) ||
          after.value("x",0.0) != viewport.value("x",0.0) ||
          after.value("y",0.0) != viewport.value("y",0.0)) return sample;
      sample.url = viewport.value("url", "");
      sample.color = AverageEdge(captured["data"].get<std::string>());
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
