#include "page_color_sampler.h"

#include <atomic>
#include <cassert>
#include <thread>

using namespace kelpie;
using kelpie::windows::PageColorSampler;

namespace {
const char* kBluePng =
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUA"
    "AAAJcEhZcwAADsMAAA7DAcdvqGQAAAAfSURBVDhPY2BgYGDQqLjzn1xMkeZRA0YNGDVgMBkAAKZqeKQj0PGx"
    "AAAAAElFTkSuQmCC";

class SamplerBrowser : public DesktopBrowserControl {
 public:
  std::atomic<bool> release{true};
  std::atomic<int> calls{0};
  bool fail = false, navigate_during_capture = false;
  Json capture_params;
  BrowserControlResult Evaluate(TabLease, std::string, Json* out, Timeout) override {
    const int call = ++calls;
    while (!release) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    if (fail) return BrowserControlResult::Failure("TIMEOUT", "Fixture timeout");
    *out = {{"url","https://test.invalid/"},{"width",1200},{"height",800},
            {"x",0},{"y",0},{"time",navigate_during_capture ? call : 1}};
    return BrowserControlResult::Success();
  }
  BrowserControlResult DevTools(TabLease, std::string method, const Json& params, Json* out, Timeout) override {
    assert(method == "Page.captureScreenshot");
    capture_params = params;
    *out = {{"data",kBluePng}};
    return BrowserControlResult::Success();
  }
  // Unused browser operations deliberately fail, so the fixture also constrains
  // the sampler to a read-only metadata/capture path.
  BrowserControlResult No() { assert(false); return BrowserControlResult::Failure("UNUSED", "Unexpected operation"); }
  BrowserControlResult GetTabs(std::vector<TabSnapshot>*,Timeout) override { return No(); }
  BrowserControlResult ResolveTab(const std::optional<std::string>&,const std::optional<std::uint64_t>&,TabLease*,Timeout) override { return No(); }
  BrowserControlResult CreateTab(const NewTabRequest&,TabSnapshot*,Timeout) override { return No(); }
  BrowserControlResult ActivateTab(TabLease,Timeout) override { return No(); }
  BrowserControlResult CloseTab(TabLease,Timeout) override { return No(); }
  BrowserControlResult Navigate(std::optional<TabLease>,std::string,TabSnapshot*,Timeout) override { return No(); }
  BrowserControlResult Back(TabLease,TabSnapshot*,Timeout) override { return No(); }
  BrowserControlResult Forward(TabLease,TabSnapshot*,Timeout) override { return No(); }
  BrowserControlResult Reload(TabLease,TabSnapshot*,Timeout) override { return No(); }
  BrowserControlResult Screenshot(TabLease,BrowserScreenshot*,Timeout) override { return No(); }
  BrowserControlResult GetCookies(TabLease,const Json&,Json*,Timeout) override { return No(); }
  BrowserControlResult SetCookies(TabLease,const Json&,Json*,Timeout) override { return No(); }
  BrowserControlResult DeleteCookies(TabLease,const Json&,Json*,Timeout) override { return No(); }
  BrowserControlResult DispatchTrustedInput(TabLease,const Json&,Json*,Timeout) override { return No(); }
  BrowserControlResult GetDialog(TabLease,Json*,Timeout) override { return No(); }
  BrowserControlResult HandleDialog(TabLease,const Json&,Json*,Timeout) override { return No(); }
};

void Drain(PageColorSampler& sampler) {
  for (int i=0; i<2000; ++i) {
    if (sampler.Drain()) return;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(false && "sampler did not drain");
}
}

int main() {
  if (kelpie::windows::ui::HighContrast()) return 0;
  const TabSnapshot tab{"first",1,"https://test.invalid/","Fixture",true};
  {
    SamplerBrowser browser;
    PageColorSampler sampler;
    sampler.Poll(browser,tab,0);
    std::optional<COLORREF> color;
    for (int i=0; i<2000 && !color; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
      color = sampler.Poll(browser,tab,1);
    }
    assert(color && GetBValue(*color)>GetRValue(*color));
    assert(!browser.capture_params.contains("clip"));
    assert(browser.capture_params["fromSurface"]==true);
    assert(browser.calls==2);
    assert(sampler.Drain());
  }
  {
    SamplerBrowser browser;
    browser.release=false;
    PageColorSampler sampler;
    sampler.Poll(browser,tab,0);
    assert(!sampler.Drain()); // Engine must remain owned while capture is pending.
    auto reloading = tab;
    reloading.is_loading=true;
    assert(!sampler.Poll(browser,reloading,1));
    browser.release=true;
    for (int i=0;i<100;++i) {
      assert(!sampler.Poll(browser,reloading,2)); // Same-URL reload rejects old sample.
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    Drain(sampler);
    assert(browser.calls==2); // No second request admitted while loading.
  }
  for (bool navigation : {false,true}) {
    SamplerBrowser browser;
    browser.fail=!navigation;
    browser.navigate_during_capture=navigation;
    PageColorSampler sampler;
    sampler.Poll(browser,tab,0);
    for (int i=0;i<100;++i) {
      assert(!sampler.Poll(browser,tab,1));
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    Drain(sampler);
  }
}
