#include "standalone_instance.h"

#include <cassert>
#include <string>

using kelpie::windows::StandaloneInstance;

int wmain(int argc, wchar_t** argv) {
  if (argc == 3) {
    StandaloneInstance instance(argv[1]);
    if (instance.error() != ERROR_SUCCESS) return static_cast<int>(instance.error());
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[2]);
    if (!ready) return 2;
    SetEvent(ready);
    CloseHandle(ready);
    Sleep(INFINITE);
    return 3;
  }

  const std::wstring name = L"Global\\Kelpie.Standalone.Test." + std::to_wstring(GetCurrentProcessId());
  {
    StandaloneInstance first(name.c_str());
    assert(first.error() == ERROR_SUCCESS);
    StandaloneInstance other_copy(name.c_str());
    assert(other_copy.error() == ERROR_ALREADY_EXISTS);
  }
  {
    StandaloneInstance next(name.c_str());
    assert(next.error() == ERROR_SUCCESS);
  }

  const std::wstring event_name = name + L".Ready";
  HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, event_name.c_str());
  assert(ready);
  wchar_t executable[32768]{};
  assert(GetModuleFileNameW(nullptr, executable, 32768));
  std::wstring command = L"\"" + std::wstring(executable) + L"\" \"" + name + L"\" \"" + event_name + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  assert(CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &child));
  assert(WaitForSingleObject(ready, 10000) == WAIT_OBJECT_0);
  {
    StandaloneInstance contender(name.c_str());
    assert(contender.error() == ERROR_ALREADY_EXISTS);
  }
  assert(TerminateProcess(child.hProcess, 99));
  assert(WaitForSingleObject(child.hProcess, 10000) == WAIT_OBJECT_0);
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  CloseHandle(ready);
  StandaloneInstance recovered(name.c_str());
  assert(recovered.error() == ERROR_SUCCESS);
}
