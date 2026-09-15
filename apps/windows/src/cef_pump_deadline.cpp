#include "cef_pump_deadline.h"
#include <algorithm>
namespace kelpie::windows {
void CeftPumpDeadline::Schedule(std::int64_t now_ms, std::int64_t delay_ms) { const auto due=now_ms+std::max<std::int64_t>(0,delay_ms); if(!due_ms_||due<*due_ms_) due_ms_=due; }
bool CeftPumpDeadline::ConsumeIfDue(std::int64_t now_ms) { if(!due_ms_||now_ms<*due_ms_) return false; due_ms_.reset(); return true; }
}
