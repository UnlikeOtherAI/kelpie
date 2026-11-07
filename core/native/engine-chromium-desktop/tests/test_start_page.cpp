#include <cassert>
#include <iostream>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/bookmark_store.h"
#include "kelpie/history_store.h"
#include "kelpie/internal_scheme.h"
#include "kelpie/start_page.h"

namespace {

using nlohmann::json;
using kelpie::start_page::BuildDataJson;

void TestSchemePredicates() {
  // A full header value handed to CefResponse::SetMimeType leaves Chromium
  // unable to match the type, and it renders the document as plain text.
  {
    using kelpie::start_page::SplitMediaType;
    const auto html = SplitMediaType("text/html; charset=utf-8");
    assert(html.type == "text/html");
    assert(html.charset == "utf-8");
    const auto png = SplitMediaType("image/png");
    assert(png.type == "image/png");
    assert(png.charset.empty());
    const auto odd = SplitMediaType("text/css;charset=utf-8");
    assert(odd.type == "text/css" && odd.charset == "utf-8");
    // No resource may declare a type CEF would reject.
    for (const auto& resource : kelpie::start_page::StaticResources()) {
      assert(SplitMediaType(resource.mime_type).type.find(';') == std::string_view::npos);
    }
  }

  assert(kelpie::IsInternalSchemeUrl("kelpie://start"));
  assert(kelpie::IsInternalSchemeUrl("KELPIE://START"));
  assert(!kelpie::IsInternalSchemeUrl("https://kelpie.example/start"));
  assert(!kelpie::IsInternalSchemeUrl("kelpie:start"));
  assert(!kelpie::IsInternalSchemeUrl(""));

  assert(kelpie::IsStartPageUrl("kelpie://start"));
  assert(kelpie::IsStartPageUrl("kelpie://start/"));
  assert(kelpie::IsStartPageUrl("kelpie://start/start.css"));
  assert(kelpie::IsStartPageUrl("kelpie://start?x=1"));
  assert(!kelpie::IsStartPageUrl("kelpie://settings"));
  // A host that merely begins with "start" is a different page.
  assert(!kelpie::IsStartPageUrl("kelpie://started"));
}

void TestResourceResolution() {
  const auto* document = kelpie::start_page::FindStaticResource(std::string(kelpie::kStartPageUrl));
  assert(document != nullptr);
  assert(document->mime_type == "text/html; charset=utf-8");
  // The embedded assets must actually have been generated into the binary.
  assert(document->body.find("<!DOCTYPE html>") == 0);
  assert(document->body.find("start.css") != std::string_view::npos);

  const auto* trailing_slash = kelpie::start_page::FindStaticResource("kelpie://start/");
  assert(trailing_slash != nullptr && trailing_slash->body == document->body);

  const auto* css = kelpie::start_page::FindStaticResource("kelpie://start/start.css");
  assert(css != nullptr && css->mime_type == "text/css; charset=utf-8");
  assert(css->body.find("max-width: 720px") != std::string_view::npos);

  const auto* script = kelpie::start_page::FindStaticResource("kelpie://start/start.js");
  assert(script != nullptr && script->mime_type == "text/javascript; charset=utf-8");

  const auto* icon = kelpie::start_page::FindStaticResource("kelpie://start/app-icon.png");
  assert(icon != nullptr && icon->mime_type == "image/png");
  // PNG magic, proving the binary asset survived embedding byte for byte.
  assert(icon->body.size() > 1000);
  assert(static_cast<unsigned char>(icon->body[0]) == 0x89 && icon->body.substr(1, 3) == "PNG");

  // The dynamic payload is not a static asset, and unknown paths resolve to
  // neither, so the handler can answer 404 instead of serving the document.
  assert(kelpie::start_page::FindStaticResource("kelpie://start/data.json") == nullptr);
  assert(kelpie::start_page::IsDataRequest("kelpie://start/data.json"));
  assert(!kelpie::start_page::IsDataRequest(std::string(kelpie::kStartPageUrl)));
  assert(!kelpie::start_page::IsDataRequest("https://example.com/data.json"));
  assert(kelpie::start_page::FindStaticResource("kelpie://start/../secret") == nullptr);
  assert(kelpie::start_page::FindStaticResource("https://example.com/start.css") == nullptr);
}

void TestDataPayload() {
  kelpie::BookmarkStore bookmarks;
  bookmarks.Add("Example", "https://example.com/");
  bookmarks.Add("Other", "https://other.test/");

  kelpie::HistoryStore history;
  for (int index = 0; index < 25; ++index) {
    history.Record("https://site" + std::to_string(index) + ".test/", "Site " + std::to_string(index));
  }

  const json payload = json::parse(BuildDataJson(bookmarks.ToJson(), history.ToJson()));
  assert(payload["bookmarks"].size() == 2);
  assert(payload["bookmarks"][0]["title"] == "Example");
  assert(payload["bookmarks"][0]["url"] == "https://example.com/");
  // Nothing beyond url/title/favicon reaches the page.
  assert(payload["bookmarks"][0].size() == 2);

  // `HistoryStore::ToJson` is newest-first and the payload keeps the last 20.
  assert(payload["recent"].size() == 20);
  assert(payload["recent"][0]["url"] == "https://site24.test/");
  assert(payload["recent"][19]["url"] == "https://site5.test/");

  // A favicon lookup produces a data URI only for hosts it knows.
  const json with_icons = json::parse(BuildDataJson(
      bookmarks.ToJson(), history.ToJson(), 20, [](const std::string& host) {
        return host == "example.com" ? std::string("QUJD") : std::string();
      }));
  assert(with_icons["bookmarks"][0]["favicon"] == "data:image/png;base64,QUJD");
  assert(!with_icons["bookmarks"][1].contains("favicon"));

  // Malformed store output degrades to an empty page rather than throwing.
  const json empty = json::parse(BuildDataJson("not json", "{}"));
  assert(empty["bookmarks"].empty() && empty["recent"].empty());
}

void TestRejectsNonWebUrls() {
  // The page turns every entry into a link inside its own origin, so a
  // `javascript:` bookmark must never reach it.
  const std::string hostile = R"JSON([
    {"url": "javascript:alert(1)", "title": "x"},
    {"url": "JavaScript:alert(1)", "title": "x"},
    {"url": "data:text/html,<script>alert(1)</script>", "title": "x"},
    {"url": "file:///C:/Windows/win.ini", "title": "x"},
    {"url": "kelpie://start", "title": "x"},
    {"url": "", "title": "x"},
    {"url": "http://", "title": "x"},
    {"url": "https://example.com/", "title": "ok"}
  ])JSON";
  const json payload = json::parse(BuildDataJson(hostile, hostile));
  assert(payload["bookmarks"].size() == 1);
  assert(payload["bookmarks"][0]["url"] == "https://example.com/");
  assert(payload["recent"].size() == 1);

  // A non-string or missing url is dropped rather than crashing the payload.
  const json malformed = json::parse(BuildDataJson(R"JSON([{"title":"x"},{"url":42}])JSON", "[]"));
  assert(malformed["bookmarks"].empty());
}

void TestStoresIgnoreInternalScheme() {
  kelpie::HistoryStore history;
  history.Record(std::string(kelpie::kStartPageUrl), "Kelpie");
  history.Record("kelpie://start/data.json", "Kelpie");
  history.Record("KELPIE://START", "Kelpie");
  assert(history.Count() == 0);

  // Real pages still record, and the start page never appears among them.
  history.Record("https://example.com/", "Example");
  assert(history.Count() == 1);
  const json entries = json::parse(history.ToJson());
  assert(entries.size() == 1 && entries[0]["url"] == "https://example.com/");

  kelpie::BookmarkStore bookmarks;
  bookmarks.Add("Kelpie", std::string(kelpie::kStartPageUrl));
  assert(bookmarks.Count() == 0);
  bookmarks.Add("Example", "https://example.com/");
  assert(bookmarks.Count() == 1);

  // The start page therefore never renders itself inside its own lists.
  const json payload = json::parse(BuildDataJson(bookmarks.ToJson(), history.ToJson()));
  assert(payload["bookmarks"].size() == 1);
  assert(payload["recent"].size() == 1);
  for (const json& entry : payload["recent"]) {
    assert(!kelpie::IsInternalSchemeUrl(entry["url"].get<std::string>()));
  }
}

}  // namespace

int main() {
  TestSchemePredicates();
  TestResourceResolution();
  TestDataPayload();
  TestRejectsNonWebUrls();
  TestStoresIgnoreInternalScheme();
  std::cout << "start page tests passed" << std::endl;
  return 0;
}
