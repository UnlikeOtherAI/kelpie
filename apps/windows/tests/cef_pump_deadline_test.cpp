#include "cef_pump_deadline.h"
using kelpie::windows::CefPumpDeadline;
int main() {
  CefPumpDeadline deadline;
  if (!deadline.Schedule(10, 50) || deadline.Schedule(10, 80)) return 1;
  if (!deadline.due_ms() || *deadline.due_ms() != 60) return 2;
  if (deadline.ConsumeIfDue(59) || !deadline.due_ms()) return 3;
  if (!deadline.ConsumeIfDue(60) || deadline.due_ms()) return 4;
  if (!deadline.Schedule(100, -1) || !deadline.ConsumeIfDue(100)) return 5;
  deadline.Schedule(200, 10); deadline.Cancel();
  return deadline.due_ms() ? 6 : 0;
}
