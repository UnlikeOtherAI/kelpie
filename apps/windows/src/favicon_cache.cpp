#include "favicon_cache.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <utility>

#include <objidl.h>
// gdiplus.h needs std::min / std::max, which NOMINMAX removed from the macros.
#include <algorithm>
#include <gdiplus.h>

namespace kelpie::windows {
namespace {

// GDI+ is a process-wide token. The cache owns its lifetime so neither the shell
// nor the unit test has to call GdiplusStartup, and a test that constructs and
// destroys several caches still works.
std::size_t gdiplus_users = 0;
ULONG_PTR gdiplus_token = 0;

void AcquireGdiplus() {
  if (gdiplus_users++ == 0) {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&gdiplus_token, &input, nullptr);
  }
}

void ReleaseGdiplus() {
  if (gdiplus_users > 0 && --gdiplus_users == 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token);
    gdiplus_token = 0;
  }
}

// Favicons arrive capped at 32 DIP from the engine. The cap is re-applied here
// because the payload is attacker-controlled: a hostile site must not be able to
// make the shell allocate a large bitmap per tab.
constexpr int kMaxIconExtent = 64;

int DecodeBase64Char(char value) {
  if (value >= 'A' && value <= 'Z') return value - 'A';
  if (value >= 'a' && value <= 'z') return value - 'a' + 26;
  if (value >= '0' && value <= '9') return value - '0' + 52;
  if (value == '+') return 62;
  if (value == '/') return 63;
  return -1;
}

// Strict decoder: any character outside the alphabet, and any length that is not
// a whole number of quartets, rejects the whole payload rather than decoding a
// truncated image.
bool DecodeBase64(std::string_view input, std::vector<std::uint8_t>* output) {
  output->clear();
  if (input.empty() || input.size() % 4 != 0) {
    return false;
  }
  output->reserve(input.size() / 4 * 3);
  for (std::size_t index = 0; index < input.size(); index += 4) {
    std::uint32_t chunk = 0;
    std::size_t bytes = 3;
    bool padded = false;
    for (std::size_t offset = 0; offset < 4; ++offset) {
      const char value = input[index + offset];
      if (value == '=') {
        // Padding is legal only in the last two positions of the final quartet,
        // and everything after the first '=' must also be '='.
        if (index + 4 != input.size() || offset < 2) {
          return false;
        }
        if (!padded) {
          padded = true;
          bytes = offset - 1;
        }
        chunk <<= 6U;
        continue;
      }
      if (padded) {
        return false;
      }
      const int decoded = DecodeBase64Char(value);
      if (decoded < 0) {
        return false;
      }
      chunk = (chunk << 6U) | static_cast<std::uint32_t>(decoded);
    }
    for (std::size_t offset = 0; offset < bytes; ++offset) {
      output->push_back(static_cast<std::uint8_t>((chunk >> (16U - 8U * offset)) & 0xFFU));
    }
  }
  return true;
}

// Copies a GDI+ bitmap into a 32-bpp premultiplied top-down DIB section.
//
// `Gdiplus::Bitmap::GetHBITMAP` composites onto a background colour and throws
// the alpha channel away, which leaves a hard fringe around every transparent
// favicon. Reading the pixels and writing them premultiplied keeps the alpha
// that `AlphaBlend` needs at paint time.
HBITMAP CopyToPremultipliedDib(Gdiplus::Bitmap* source, int* out_width, int* out_height) {
  const int width = std::min(static_cast<int>(source->GetWidth()), kMaxIconExtent);
  const int height = std::min(static_cast<int>(source->GetHeight()), kMaxIconExtent);
  if (width <= 0 || height <= 0) {
    return nullptr;
  }

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;  // top-down
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (bitmap == nullptr || pixels == nullptr) {
    if (bitmap != nullptr) {
      DeleteObject(bitmap);
    }
    return nullptr;
  }

  Gdiplus::Rect region(0, 0, width, height);
  Gdiplus::BitmapData data{};
  if (source->LockBits(&region, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &data) !=
      Gdiplus::Ok) {
    DeleteObject(bitmap);
    return nullptr;
  }

  auto* destination = static_cast<std::uint8_t*>(pixels);
  for (int row = 0; row < height; ++row) {
    const auto* source_row =
        static_cast<const std::uint8_t*>(data.Scan0) + static_cast<std::ptrdiff_t>(row) * data.Stride;
    auto* destination_row = destination + static_cast<std::ptrdiff_t>(row) * width * 4;
    for (int column = 0; column < width; ++column) {
      const std::uint8_t blue = source_row[column * 4 + 0];
      const std::uint8_t green = source_row[column * 4 + 1];
      const std::uint8_t red = source_row[column * 4 + 2];
      const std::uint8_t alpha = source_row[column * 4 + 3];
      destination_row[column * 4 + 0] = static_cast<std::uint8_t>(blue * alpha / 255);
      destination_row[column * 4 + 1] = static_cast<std::uint8_t>(green * alpha / 255);
      destination_row[column * 4 + 2] = static_cast<std::uint8_t>(red * alpha / 255);
      destination_row[column * 4 + 3] = alpha;
    }
  }

  source->UnlockBits(&data);
  *out_width = width;
  *out_height = height;
  return bitmap;
}

HBITMAP DecodePng(const std::vector<std::uint8_t>& bytes, int* width, int* height) {
  if (bytes.empty()) {
    return nullptr;
  }
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (memory == nullptr) {
    return nullptr;
  }
  if (void* locked = GlobalLock(memory)) {
    std::copy(bytes.begin(), bytes.end(), static_cast<std::uint8_t*>(locked));
    GlobalUnlock(memory);
  } else {
    GlobalFree(memory);
    return nullptr;
  }

  IStream* stream = nullptr;
  // `fDeleteOnRelease` hands the HGLOBAL to the stream, so releasing it frees
  // the memory on every path below.
  if (FAILED(CreateStreamOnHGlobal(memory, TRUE, &stream))) {
    GlobalFree(memory);
    return nullptr;
  }

  HBITMAP bitmap = nullptr;
  {
    Gdiplus::Bitmap image(stream, FALSE);
    if (image.GetLastStatus() == Gdiplus::Ok) {
      bitmap = CopyToPremultipliedDib(&image, width, height);
    }
  }
  stream->Release();
  return bitmap;
}

}  // namespace

FaviconCache::FaviconCache(std::size_t capacity) : capacity_(capacity == 0 ? 1 : capacity) {
  AcquireGdiplus();
}

FaviconCache::~FaviconCache() {
  Clear();
  ReleaseGdiplus();
}

std::string FaviconCache::HostForUrl(std::string_view url) {
  const std::size_t scheme_end = url.find("://");
  if (scheme_end == std::string_view::npos) {
    return std::string();
  }
  std::string_view authority = url.substr(scheme_end + 3);
  const std::size_t authority_end = authority.find_first_of("/?#");
  if (authority_end != std::string_view::npos) {
    authority = authority.substr(0, authority_end);
  }
  const std::size_t at = authority.rfind('@');
  if (at != std::string_view::npos) {
    authority = authority.substr(at + 1);
  }
  if (authority.empty()) {
    return std::string();
  }
  if (authority.front() == '[') {
    const std::size_t close = authority.find(']');
    if (close == std::string_view::npos) {
      return std::string();
    }
    authority = authority.substr(0, close + 1);
  } else if (const std::size_t colon = authority.find(':'); colon != std::string_view::npos) {
    authority = authority.substr(0, colon);
  }

  std::string host(authority);
  std::transform(host.begin(), host.end(), host.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  return host;
}

void FaviconCache::EraseLocked(std::list<Entry>::iterator entry) {
  if (entry->bitmap != nullptr) {
    DeleteObject(entry->bitmap);
    entry->bitmap = nullptr;
  }
  index_.erase(entry->host);
  entries_.erase(entry);
}

bool FaviconCache::Update(const TabIcon& tab) {
  const std::string host = HostForUrl(tab.url);
  if (host.empty() || tab.favicon_png_base64.empty()) {
    return false;
  }

  const auto existing = index_.find(host);
  if (existing != index_.end()) {
    if (existing->second->source == tab.favicon_png_base64) {
      entries_.splice(entries_.begin(), entries_, existing->second);
      return existing->second->bitmap != nullptr;
    }
    // The site changed its icon: drop the old bitmap before decoding the new
    // one, so the handle count stays at one per host.
    EraseLocked(existing->second);
  }

  std::vector<std::uint8_t> bytes;
  if (!DecodeBase64(tab.favicon_png_base64, &bytes)) {
    return false;
  }
  int width = 0;
  int height = 0;
  HBITMAP bitmap = DecodePng(bytes, &width, &height);
  if (bitmap == nullptr) {
    return false;
  }

  entries_.push_front(Entry{host, tab.favicon_png_base64, bitmap, width, height});
  index_.emplace(host, entries_.begin());
  while (entries_.size() > capacity_) {
    EraseLocked(std::prev(entries_.end()));
  }
  return true;
}

HBITMAP FaviconCache::Lookup(std::string_view url) {
  const auto entry = index_.find(HostForUrl(url));
  if (entry == index_.end()) {
    return nullptr;
  }
  entries_.splice(entries_.begin(), entries_, entry->second);
  return entries_.front().bitmap;
}

HBITMAP FaviconCache::Peek(std::string_view url) const {
  const auto entry = index_.find(HostForUrl(url));
  return entry == index_.end() ? nullptr : entry->second->bitmap;
}

void FaviconCache::Clear() {
  for (Entry& entry : entries_) {
    if (entry.bitmap != nullptr) {
      DeleteObject(entry.bitmap);
    }
  }
  entries_.clear();
  index_.clear();
}

std::vector<std::string> FaviconCache::HostsMostRecentFirst() const {
  std::vector<std::string> hosts;
  hosts.reserve(entries_.size());
  for (const Entry& entry : entries_) {
    hosts.push_back(entry.host);
  }
  return hosts;
}

void DrawTabIcon(HDC device_context, const RECT& bounds, const TabIcon& tab, FaviconCache& cache) {
  // macOS checks `isStartPage` before the favicon, so the star always wins.
  if (tab.is_start_page) {
    DrawStartPageIcon(device_context, bounds);
    return;
  }

  cache.Update(tab);
  if (HBITMAP bitmap = cache.Lookup(tab.url)) {
    BITMAP info{};
    if (GetObject(bitmap, sizeof(info), &info) != 0) {
      HDC source = CreateCompatibleDC(device_context);
      HGDIOBJ previous = SelectObject(source, bitmap);
      BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
      AlphaBlend(device_context, bounds.left, bounds.top, bounds.right - bounds.left,
                 bounds.bottom - bounds.top, source, 0, 0, info.bmWidth, info.bmHeight, blend);
      SelectObject(source, previous);
      DeleteDC(source);
      return;
    }
  }

  DrawLetterAvatar(device_context, bounds, FaviconCache::HostForUrl(tab.url));
}

}  // namespace kelpie::windows
