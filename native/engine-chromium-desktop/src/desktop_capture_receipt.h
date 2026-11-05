#pragma once
#include <chrono>
#include <string>

namespace kelpie {
template<typename Callback>
bool CaptureCompletionApproved(Callback&& callback) {
  try { return callback(); } catch(...) { return false; }
}
inline bool CaptureReceiptEligible(std::chrono::steady_clock::time_point now,
    std::chrono::steady_clock::time_point deadline,bool cancelled,bool liveLease,bool matchingBrowser) {
  return now<deadline && !cancelled && liveLease && matchingBrowser;
}
enum class CaptureViewportFailure { DocumentUnavailable, TornFrame, ViewportChanged };
inline CaptureViewportFailure ClassifyCaptureViewportFailure(bool navigationAvailable,
    const std::string& receiptDocument,const std::string& currentDocument) {
  if(!navigationAvailable) return CaptureViewportFailure::DocumentUnavailable;
  if(receiptDocument!=currentDocument) return CaptureViewportFailure::TornFrame;
  return CaptureViewportFailure::ViewportChanged;
}
}
