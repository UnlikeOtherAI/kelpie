#include "account_login_surface.h"
#include <cassert>
#include <string>
#include <vector>

using namespace kelpie::account;
namespace {
constexpr char kUrl[]="https://authentication.unlikeotherai.com/login";

struct Opener {
  bool result;
  std::vector<std::string>* calls;
  const char* name;
  bool operator()(const std::string& url) const {
    assert(url==kUrl);
    calls->push_back(name);
    return result;
  }
};

std::vector<std::string> Run(bool allowed, bool window_opens, bool browser_opens, LoginSurface expected) {
  std::vector<std::string> calls;
  const auto surface=OpenLoginSurface(kUrl,allowed,Opener{window_opens,&calls,"window"},
                                      Opener{browser_opens,&calls,"browser"});
  assert(surface==expected);
  return calls;
}
}

int main() {
  // The shared-profile window wins and the system browser is never touched.
  assert((Run(true,true,true,LoginSurface::kAppWindow)==std::vector<std::string>{"window"}));
  // A window that cannot open falls back to the system browser.
  assert((Run(true,false,true,LoginSurface::kSystemBrowser)==std::vector<std::string>{"window","browser"}));
  // Headless/disallowed skips the window entirely.
  assert((Run(false,true,true,LoginSurface::kSystemBrowser)==std::vector<std::string>{"browser"}));
  // Nothing could open: the caller reports failure.
  assert((Run(true,false,false,LoginSurface::kNone)==std::vector<std::string>{"window","browser"}));
  // A missing opener counts as unavailable.
  assert(OpenLoginSurface(kUrl,true,{},{})==LoginSurface::kNone);
  return 0;
}
