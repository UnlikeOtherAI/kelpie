#include <cassert>
#include <cstdio>
#include <string>

#include "display_format.h"
#include "network_rows.h"

namespace {

using kelpie::windows::FilterNetworkRows;
using kelpie::windows::ParseNetworkRows;
using kelpie::windows::RequestType;
namespace format = kelpie::windows::format;

void TestRequestNames() {
  assert(format::RequestName("https://example.com/") == L"example.com");
  assert(format::RequestName("https://example.com") == L"example.com");
  assert(format::RequestName("https://example.com/assets/app.js") == L"app.js");
  assert(format::RequestName("https://example.com/api/items/?page=2#top") == L"items?page=2");
  assert(format::RequestName("https://example.com/?q=kelpie") == L"example.com?q=kelpie");
  assert(format::RequestName("about:blank") == L"about:blank");
}

void TestSizesAndTimes() {
  assert(format::Bytes(0) == L"0 B");
  assert(format::Bytes(999) == L"999 B");
  assert(format::Bytes(1640) == L"1.6 kB");
  assert(format::Bytes(45200) == L"45 kB");
  assert(format::Bytes(2400000) == L"2.4 MB");
  assert(format::Bytes(-5) == L"0 B");
  assert(format::Duration(57) == L"57 ms");
  assert(format::Duration(1240) == L"1.24 s");
  assert(format::Duration(-1) == L"0 ms");
}

void TestLocalTime() {
  // The zone and the person's date format vary, so only the shape is fixed:
  // a stamp that parses is reformatted, anything else is shown as it came.
  const std::wstring formatted = format::LocalTime("2026-11-09T10:05:30.123Z");
  assert(!formatted.empty() && formatted != L"2026-11-09T10:05:30.123Z");
  assert(format::LocalTime("yesterday") == L"yesterday");
  assert(format::LocalTime("2026-13-40T99:99:99Z") == L"2026-13-40T99:99:99Z");
}

void TestParsingAndBuckets() {
  const auto rows = ParseNetworkRows(R"([
    {"id":"1","method":"GET","url":"https://example.com/","status_code":200,"category":"HTML","initiator":"browser","size":1200,"duration":40},
    {"id":"2","method":"GET","url":"https://example.com/app.js","status_code":200,"category":"JS","initiator":"browser","size":2400,"duration":12},
    {"id":"3","method":"POST","url":"https://api.example.com/items","status_code":201,"category":"JSON","initiator":"js","size":300,"duration":90},
    {"id":"4","method":"GET","url":"https://example.com/missing.png","status_code":404,"category":"Image","initiator":"browser","size":0,"duration":5},
    {"id":"5","method":"GET","url":"https://cdn.example.com/font.woff2","status_code":0,"category":"Font","initiator":"browser","size":0,"duration":3},
    {"id":"6","method":"GET","url":"https://example.com/feed.xml","status_code":200,"category":"XML","initiator":"browser","size":10,"duration":1},
    "not an object"
  ])");
  assert(rows.size() == 6);
  assert(rows[0].type == L"document" && rows[0].bucket == RequestType::kDoc && rows[0].name == L"example.com");
  assert(rows[2].type == L"fetch" && rows[2].bucket == RequestType::kFetch && rows[2].initiator == L"script");
  assert(rows[3].failed && rows[3].status == L"404");
  assert(rows[4].failed && rows[4].status == L"(failed)");
  assert(!rows[1].failed && rows[1].size == L"2.4 kB" && rows[1].time == L"12 ms");
  assert(rows[5].bucket == RequestType::kOther);

  assert(FilterNetworkRows(rows, RequestType::kAll, L"").size() == 6);
  assert(FilterNetworkRows(rows, RequestType::kFetch, L"") == std::vector<std::size_t>{2});
  assert(FilterNetworkRows(rows, RequestType::kImg, L"") == std::vector<std::size_t>{3});
  assert(FilterNetworkRows(rows, RequestType::kFont, L"") == std::vector<std::size_t>{4});
  assert(FilterNetworkRows(rows, RequestType::kCss, L"").empty());
  // The text filter matches the address or the method, ignoring case.
  assert(FilterNetworkRows(rows, RequestType::kAll, L"post") == std::vector<std::size_t>{2});
  assert(FilterNetworkRows(rows, RequestType::kAll, L"EXAMPLE.COM/APP").size() == 1);
  assert(FilterNetworkRows(rows, RequestType::kJs, L"missing").empty());
  assert(ParseNetworkRows("not json").empty());
  assert(ParseNetworkRows("{}").empty());
}

}  // namespace

int main() {
  TestRequestNames();
  TestSizesAndTimes();
  TestLocalTime();
  TestParsingAndBuckets();
  std::puts("network rows: ok");
  return 0;
}
