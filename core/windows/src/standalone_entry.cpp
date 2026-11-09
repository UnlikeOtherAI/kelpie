#include "kelpie/bootstrap.h"
#if defined(HAS_CEF)
#include "include/cef_app.h"
#include "kelpie/cef_app_factory.h"
#include <cstring>
int kelpie::windows::BootstrapBrowserHost(HINSTANCE instance,
                            LPWSTR command_line,
                            int show_command,
                            void* sandbox_info,
                            cef_version_info_t* version_info, BrowserHostMain host_main) {
  if (host_main == nullptr) return ERROR_INVALID_PARAMETER;
  if (version_info == nullptr || version_info->size < CEF_VERSION_INFO_SIZE_WITH_SANDBOX_HASH) {
    return ERROR_REVISION_MISMATCH;
  }
  cef_version_info_t expected{};
  CEF_POPULATE_VERSION_INFO(&expected);
  if (version_info->cef_version_major != expected.cef_version_major ||
      version_info->cef_version_minor != expected.cef_version_minor ||
      version_info->cef_version_patch != expected.cef_version_patch ||
      std::strncmp(version_info->sandbox_compat_hash, expected.sandbox_compat_hash,
                   sizeof(expected.sandbox_compat_hash)) != 0) {
    return ERROR_REVISION_MISMATCH;
  }
  CefMainArgs main_args(instance);
  CefRefPtr<CefApp> app = kelpie::CreateDesktopCefApp();
  const int subprocess_exit = CefExecuteProcess(main_args, app, sandbox_info);
  if (subprocess_exit >= 0) return subprocess_exit;
  HMODULE client_module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&BootstrapBrowserHost), &client_module)) {
    return GetLastError();
  }
  return host_main(client_module, instance, command_line, show_command, sandbox_info);
}

#endif
