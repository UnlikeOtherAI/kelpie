#include "desktop_engine_impl.h"

#include <chrono>

#include "desktop_screenshot_planner.h"
#if defined(_WIN32)
#include <windows.h>
#endif

// Viewport screenshots for the desktop engine. The capture is two DevTools
// calls: Page.getLayoutMetrics for the CSS viewport and device pixel ratio,
// then Page.captureScreenshot, which encodes the PNG or JPEG and, for
// `maxWidth`, scales a clip of the visible viewport.
namespace kelpie {
namespace {

// A minimised top-level window stops producing frames, and CDP then hands back
// the last frame or the iconic window's tiny surface (158x14 in practice) while
// the page still believes it is visible. So the window is asked, not the page.
// Runs on the UI thread. The check and the capture are not atomic: a minimise
// that lands between them can still yield one stale frame.
BrowserControlResult WindowCanProduceImage(const CefRefPtr<CefBrowser>& browser) {
#if defined(_WIN32)
  const HWND window = browser && browser->GetHost() ? browser->GetHost()->GetWindowHandle() : nullptr;
  if (window == nullptr) return BrowserControlResult::Success();  // Windowless rendering.
  const HWND root = GetAncestor(window, GA_ROOT);
  if (root != nullptr && IsIconic(root)) {
    return BrowserControlResult::Failure(
        "WINDOW_MINIMIZED",
        "The browser window is minimised, so it has no current image. Restore the window and retry.");
  }
  RECT client{};
  if (GetClientRect(window, &client) && (client.right <= client.left || client.bottom <= client.top)) {
    return BrowserControlResult::Failure(
        "WINDOW_MINIMIZED",
        "The browser window has no visible area, so it has no current image. Restore or enlarge the window and retry.");
  }
#else
  (void)browser;
#endif
  return BrowserControlResult::Success();
}

}  // namespace

BrowserControlResult DesktopEngine::Screenshot(TabLease lease, const BrowserScreenshotOptions& options,
                                               BrowserScreenshot* image, Timeout timeout) {
  const auto impl = impl_;
  if (image == nullptr) return BrowserControlResult::Failure("INTERNAL", "image is required");
  const auto started_at = std::chrono::steady_clock::now();

  Json metrics;
  BrowserControlResult result = DevTools(lease, "Page.getLayoutMetrics", Json::object(), &metrics, timeout);
  if (!result.ok) return result;
  const auto viewport = desktop_screenshot::ParseLayoutMetrics(metrics);
  if (!viewport) {
    return BrowserControlResult::Failure("CDP_MALFORMED_RESULT",
                                         "Page.getLayoutMetrics did not return a CSS visual viewport");
  }

  const BrowserControlResult window = impl->RunOnUi([impl, lease] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    const BrowserControlResult state = WindowCanProduceImage(tab->browser);
    return state.ok ? BrowserControlResult::Success(impl->Snapshot(*tab)) : state;
  }, RemainingTimeout(started_at, timeout));
  if (!window.ok) return window;

  Json captured;
  result = DevTools(lease, "Page.captureScreenshot", desktop_screenshot::CaptureParams(options, *viewport),
                    &captured, RemainingTimeout(started_at, timeout));
  if (!result.ok) return result;
  const auto data = captured.find("data");
  if (data == captured.end() || !data->is_string() || data->get_ref<const std::string&>().empty()) {
    return BrowserControlResult::Failure("CDP_MALFORMED_RESULT", "Page.captureScreenshot did not return image data");
  }
  const auto header = desktop_screenshot::ReadImageHeader(data->get_ref<const std::string&>());
  if (!header) {
    return BrowserControlResult::Failure("CDP_MALFORMED_RESULT",
                                         "Page.captureScreenshot returned an image Kelpie could not read");
  }
  image->mime_type = "image/" + header->format;
  image->base64_data = data->get<std::string>();
  image->width = header->width;
  image->height = header->height;
  image->viewport_width = viewport->css_width;
  image->viewport_height = viewport->css_height;
  image->device_pixel_ratio = viewport->device_pixel_ratio;
  image->image_scale = desktop_screenshot::ImageScale(options, *viewport);
  return BrowserControlResult::Success(window.tab);
}

}  // namespace kelpie
