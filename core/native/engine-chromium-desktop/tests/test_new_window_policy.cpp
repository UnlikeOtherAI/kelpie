#include "new_window_policy.h"

#include <cassert>

int main() {
  using kelpie::IsAppLink;
  using kelpie::OpensAsTab;
  using kelpie::OriginOf;

  assert(IsAppLink("slack://open?team=T1"));
  assert(IsAppLink("zoommtg://zoom.us/join"));
  assert(IsAppLink("mailto:a@example.com"));
  assert(IsAppLink("MS-Teams:/l/chat"));
  assert(!IsAppLink("https://slack.com"));
  assert(!IsAppLink("HTTP://localhost:8420/"));
  assert(!IsAppLink("about:blank"));
  assert(!IsAppLink("data:text/plain,hi"));
  assert(!IsAppLink("blob:https://a.test/1"));
  assert(!IsAppLink("kelpie://start"));
  assert(!IsAppLink("chrome-error://chromewebdata/"));
  assert(!IsAppLink(""));
  assert(!IsAppLink("no scheme here"));

  assert(kelpie::IsDeniedAppLink("shell:startup"));
  assert(kelpie::IsDeniedAppLink("VBScript:msgbox(1)"));
  assert(kelpie::IsDeniedAppLink("ms-msdt:/id"));
  assert(!kelpie::IsDeniedAppLink("slack://open"));

  assert(OriginOf("https://KiloMayo.slack.com/ssb/redirect?x=1") == "https://kilomayo.slack.com");
  assert(OriginOf("http://user:pw@127.0.0.1:8765/launch.html") == "http://127.0.0.1:8765");
  assert(OriginOf("https://a.test") == "https://a.test");
  assert(OriginOf("slack://open").empty());
  assert(OriginOf("about:blank").empty());

  // Ordinary new-window links become tabs; pop-ups and blank windows stay native.
  assert(OpensAsTab(false, "https://app.slack.com/t/kilomayo/login"));
  assert(!OpensAsTab(true, "https://accounts.google.com/o/oauth2"));
  assert(!OpensAsTab(false, ""));
  assert(!OpensAsTab(false, "about:blank"));
  assert(!OpensAsTab(false, "blob:https://a.test/1"));
  return 0;
}
