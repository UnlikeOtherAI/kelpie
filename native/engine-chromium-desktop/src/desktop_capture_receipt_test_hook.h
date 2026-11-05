#pragma once
// This hook is compiled only into explicitly requested test builds.
#include "kelpie/desktop_engine.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>

namespace kelpie {
inline std::optional<std::string> ReceiptTestNavigateOnce(DesktopEngine& engine,const TabLease& lease,
                                                          const BrowserNavigationState& before) {
  const char* configured=std::getenv("KELPIE_CAPTURE_RECEIPT_FIXTURE_URL");
  if(!configured) return std::nullopt;
  const std::string origin(configured),prefix="http://127.0.0.1:";
  if(origin.rfind(prefix,0)!=0 || origin.size()<=prefix.size() || origin.size()>prefix.size()+5 ||
     !std::all_of(origin.begin()+prefix.size(),origin.end(),[](char c){return c>='0'&&c<='9';}))
    throw std::runtime_error("CAPTURE_RECEIPT_TEST_CONFIG");
  const int port=std::stoi(origin.substr(prefix.size()));
  if(port<1 || port>65535) throw std::runtime_error("CAPTURE_RECEIPT_TEST_CONFIG");
  if(before.tab.url!=origin && before.tab.url!=origin+"/") return std::nullopt;
  static std::atomic<bool> fired=false;
  bool expected=false;
  if(!fired.compare_exchange_strong(expected,true)) return std::nullopt;
  TabSnapshot navigated;
  const auto result=engine.Navigate(lease,origin+"/next",&navigated,std::chrono::seconds(2));
  if(!result.ok) throw std::runtime_error("CAPTURE_RECEIPT_TEST_NAVIGATION");
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(3);
  while(std::chrono::steady_clock::now()<deadline) {
    if(lease.cancelled && lease.cancelled->load()) throw std::runtime_error("CAPTURE_RECEIPT_TEST_CANCELLED");
    BrowserNavigationState current;
    const auto observed=engine.GetNavigationState(lease,&current,std::chrono::seconds(1));
    if(observed.ok && current.tab.document_version!=before.tab.document_version &&
       !current.tab.is_loading && current.completed>=current.requested) {
      std::fputs("KELPIE_RECEIPT_TEST_NAVIGATED\n",stderr);std::fflush(stderr);
      return before.tab.document_version;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
  }
  throw std::runtime_error("CAPTURE_RECEIPT_TEST_NAVIGATION");
}
}
