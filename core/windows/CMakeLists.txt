cmake_minimum_required(VERSION 3.16)

project(kelpie_windows_browser LANGUAGES CXX RC)

include(CTest)

# C++20 for both configurations: the shell uses std::wstring::starts_with, so
# raising the standard only under HAS_CEF left the documented no-CEF fallback
# unable to compile.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CEF_ROOT "" CACHE PATH "Path to an extracted CEF SDK root")
set(CEF_WRAPPER "" CACHE FILEPATH "Path to a built Windows libcef_dll_wrapper library")
option(HAS_CEF "Build Windows app with Chromium Embedded Framework" OFF)
if(CEF_ROOT)
  set(HAS_CEF ON)
endif()
if(HAS_CEF AND CMAKE_BUILD_TYPE AND NOT CMAKE_BUILD_TYPE STREQUAL "Release")
  message(FATAL_ERROR "The pinned Windows CEF minimal SDK is packaged with a Release wrapper; configure -DCMAKE_BUILD_TYPE=Release")
endif()
if(CMAKE_BUILD_TYPE STREQUAL "Release" AND NOT HAS_CEF)
  message(FATAL_ERROR "Shipping the Windows Release target requires the pinned sandboxed CEF SDK")
endif()
if(HAS_CEF AND NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "The Windows CEF 152 artifact is x64 only")
endif()

if(MSVC)
  # CEF's Windows wrapper uses the static CRT. Every native target must use
  # the same CRT or the linker rejects mixed debug/runtime allocations.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
  # Chrome glyph literals are UTF-8 source, independently of the active system code page.
  add_compile_options(/utf-8)
endif()

include(CTest)
include(FetchContent)

set(KELPIE_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../native")
if(NOT EXISTS "${KELPIE_NATIVE_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "Expected native core at ${KELPIE_NATIVE_ROOT}")
endif()

set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_ZLIB_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)

if(HAS_CEF AND NOT CEF_WRAPPER)
  # Resolve the wrapper before the native subproject is configured. On Windows
  # that subproject accepts only an explicit CEF_WRAPPER and fails hard without
  # one, and add_subdirectory() below runs long before this file's own fallback
  # search — so a clean configure that passes CEF_ROOT alone would stop there
  # rather than find the library sitting in the SDK.
  find_library(CEF_WRAPPER NAMES libcef_dll_wrapper PATHS
    "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug"
    "${CEF_ROOT}/build/libcef_dll_wrapper"
    "${CEF_ROOT}/build/libcef_dll_wrapper/Release"
    NO_DEFAULT_PATH)
endif()

if(NOT TARGET kelpie_core_protocol)
  if(HAS_CEF)
    set(KELPIE_ENABLE_CHROMIUM_DESKTOP ON CACHE BOOL "" FORCE)
  endif()
  add_subdirectory("${KELPIE_NATIVE_ROOT}" "${CMAKE_BINARY_DIR}/kelpie_native")
endif()

FetchContent_Declare(
  cpp_httplib
  URL https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.18.5.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(cpp_httplib)

# The shared visual system: palette, DPI metrics, fonts, drawing primitives.
set(WINDOWS_THEME_SOURCES
  src/theme/palette.cpp
  src/theme/metrics.cpp
  src/theme/paint.cpp
  src/theme/panels.cpp
)

set(WINDOWS_THEME_HEADERS
  src/theme/theme.h
  src/theme/palette.h
  src/theme/metrics.h
  src/theme/paint.h
  src/theme/panels.h
  src/theme/icons.h
)

add_subdirectory("${KELPIE_NATIVE_ROOT}/desktop-account" "${CMAKE_BINARY_DIR}/desktop-account")
add_subdirectory("${KELPIE_NATIVE_ROOT}/desktop-connect" "${CMAKE_BINARY_DIR}/desktop-connect")

include(inference.cmake)

set(WINDOWS_APP_SOURCES
  ${WINDOWS_THEME_SOURCES}
  src/standalone_entry.cpp
  src/native_window_control.cpp
  src/owner_task_queue.cpp
  src/cef_pump_schedule.cpp
  src/close_lifecycle.h
  src/windows_app.cpp
  src/windows_app_persistence.cpp
  src/shell_actions.cpp
  src/account_menu.cpp
  src/windows_runtime.cpp
  src/page_color_sampler.cpp
  src/win32_shell.cpp
  src/window_placement.cpp
  src/shell_tabs.cpp
  src/shell_chrome.cpp
  src/favorites_bar.cpp
  src/drag_effects.cpp
  src/window_chrome.cpp
  src/maximized_frame.cpp
  src/win32_browser_view.cpp
  src/url_bar.cpp
  src/account_avatar.cpp
  src/favicon_cache.cpp
  src/letter_avatar.cpp
  src/settings_view.cpp
  ${WINDOWS_INFERENCE_SOURCES}
  src/panel_window.cpp
  src/link_list_panel.cpp
  src/display_format.cpp
  src/network_rows.cpp
  src/network_inspector.cpp
  src/profile_session.cpp
  src/session_snapshot.cpp
  src/tab_tooltips.cpp
  src/toast_view.cpp
  src/device_info_windows.cpp
  src/mdns_windows.cpp
)

set(WINDOWS_APP_HEADERS
  ${WINDOWS_THEME_HEADERS}
  src/windows_app.h
  src/native_window_control.h
  src/owner_task_queue.h
  src/cef_pump_schedule.h
  src/win32_shell.h
  src/window_placement.h
  src/window_chrome.h
  src/maximized_frame.h
  src/win32_browser_view.h
  src/url_bar.h
  src/favicon_cache.h
  src/letter_avatar.h
  src/settings_view.h
  src/panel_window.h
  src/link_list_panel.h
  src/display_format.h
  src/network_rows.h
  src/network_inspector.h
  src/profile_session.h
  src/session_snapshot.h
  src/startup_diagnostics.h
  src/tab_tooltips.h
  src/toast_view.h
  src/drag_effects.h
  src/device_info_windows.h
  src/mdns_windows.h
)

add_library(kelpie_windows_browser STATIC ${WINDOWS_APP_SOURCES} ${WINDOWS_APP_HEADERS})
add_library(Kelpie::Browser ALIAS kelpie_windows_browser)

target_compile_definitions(kelpie_windows_browser
  PUBLIC
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _WIN32_WINNT=0x0A00
    UNICODE
    _UNICODE
)

target_include_directories(kelpie_windows_browser
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)

target_link_libraries(kelpie_windows_browser PUBLIC kelpie_desktop_account kelpie_desktop_connect shlwapi)

target_link_libraries(kelpie_windows_browser
  PUBLIC
    httplib::httplib
    kelpie_core_protocol
    kelpie_core_state
    kelpie_core_automation
    kelpie_core_mcp
    kelpie_core_ai
    winhttp
    nlohmann_json::nlohmann_json
    user32
    gdi32
    gdiplus
    uxtheme
    msimg32
    dwmapi
    shell32
    ws2_32
    iphlpapi
    dnsapi
    advapi32
    bcrypt
    crypt32
    comctl32
    ole32
    Rpcrt4
)

set_target_properties(kelpie_windows_browser PROPERTIES
  OUTPUT_NAME "kelpie_windows_browser"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  PREFIX ""
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

if(TARGET kelpie_engine_chromium_desktop)
  target_link_libraries(kelpie_windows_browser PUBLIC kelpie_engine_chromium_desktop)
endif()

if(HAS_CEF)
  if(NOT CEF_ROOT)
    message(FATAL_ERROR "HAS_CEF requires CEF_ROOT to point at a CEF binary distribution")
  endif()

  target_compile_definitions(kelpie_windows_browser PUBLIC HAS_CEF=1 CEF_USE_BOOTSTRAP=1)
  target_include_directories(kelpie_windows_browser PUBLIC "${CEF_ROOT}" "${CEF_ROOT}/include")

  find_library(CEF_LIBCEF NAMES libcef PATHS "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug" NO_DEFAULT_PATH)
  if(NOT CEF_WRAPPER)
    find_library(CEF_WRAPPER NAMES libcef_dll_wrapper PATHS
      "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug"
      "${CEF_ROOT}/build/libcef_dll_wrapper"
      "${CEF_ROOT}/build/libcef_dll_wrapper/Release"
      NO_DEFAULT_PATH)
  endif()

  if(CEF_LIBCEF)
    target_link_libraries(kelpie_windows_browser PUBLIC "${CEF_LIBCEF}")
  endif()
  if(CEF_WRAPPER AND EXISTS "${CEF_WRAPPER}")
    target_link_libraries(kelpie_windows_browser PUBLIC "${CEF_WRAPPER}")
  else()
    message(FATAL_ERROR "Windows CEF requires a built libcef_dll_wrapper; set CEF_WRAPPER")
  endif()


endif()

include(runtime.cmake)

if(BUILD_TESTING)
  add_windows_inference_tests()
  add_executable(page_color_sampler_test tests/page_color_sampler_test.cpp src/page_color_sampler.cpp ${WINDOWS_THEME_SOURCES})
  target_include_directories(page_color_sampler_test PRIVATE src "${KELPIE_NATIVE_ROOT}/engine-chromium-desktop/include")
  target_link_libraries(page_color_sampler_test PRIVATE nlohmann_json::nlohmann_json user32 gdi32 gdiplus uxtheme dwmapi crypt32 ole32)
  target_compile_options(page_color_sampler_test PRIVATE /UNDEBUG)
  add_test(NAME page_color_sampler_test COMMAND page_color_sampler_test)

  add_executable(kelpie_windows_utf_test tests/windows_utf_test.cpp)
  target_include_directories(kelpie_windows_utf_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_utf_test PRIVATE user32)
  if(MSVC)
    target_compile_options(kelpie_windows_utf_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_utf_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_utf_test COMMAND kelpie_windows_utf_test)
  add_executable(kelpie_windows_session_snapshot_test tests/session_snapshot_test.cpp src/session_snapshot.cpp)
  # `session_snapshot.cpp` shares the internal-scheme predicate with the engine
  # so the restorable-URL rule cannot drift from what the browser will navigate,
  # and the partition validator so a snapshot cannot restore an invalid one.
  target_include_directories(kelpie_windows_session_snapshot_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${KELPIE_NATIVE_ROOT}/core-state/include")
  target_link_libraries(kelpie_windows_session_snapshot_test PRIVATE nlohmann_json::nlohmann_json
    kelpie_core_protocol)
  if(MSVC)
    target_compile_options(kelpie_windows_session_snapshot_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_session_snapshot_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_session_snapshot_test COMMAND kelpie_windows_session_snapshot_test)
  add_executable(kelpie_windows_cef_pump_schedule_test tests/cef_pump_schedule_test.cpp src/cef_pump_schedule.cpp)
  target_include_directories(kelpie_windows_cef_pump_schedule_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_compile_options(kelpie_windows_cef_pump_schedule_test PRIVATE /UNDEBUG)
  add_test(NAME kelpie_windows_cef_pump_schedule_test COMMAND kelpie_windows_cef_pump_schedule_test)
  add_executable(kelpie_windows_owner_task_queue_test tests/owner_task_queue_test.cpp src/owner_task_queue.cpp)
  target_include_directories(kelpie_windows_owner_task_queue_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_compile_options(kelpie_windows_owner_task_queue_test PRIVATE /UNDEBUG)
  add_test(NAME kelpie_windows_owner_task_queue_test COMMAND kelpie_windows_owner_task_queue_test)
  add_executable(kelpie_windows_window_placement_test tests/window_placement_test.cpp src/window_placement.cpp)
  target_include_directories(kelpie_windows_window_placement_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_window_placement_test PRIVATE nlohmann_json::nlohmann_json user32)
  target_compile_options(kelpie_windows_window_placement_test PRIVATE /UNDEBUG)
  add_test(NAME kelpie_windows_window_placement_test COMMAND kelpie_windows_window_placement_test)
  add_executable(kelpie_windows_profile_session_test tests/profile_session_test.cpp src/profile_session.cpp)
  target_include_directories(kelpie_windows_profile_session_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_profile_session_test PRIVATE nlohmann_json::nlohmann_json advapi32 bcrypt)
  if(MSVC)
    target_compile_options(kelpie_windows_profile_session_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_profile_session_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_profile_session_test COMMAND kelpie_windows_profile_session_test)
  add_executable(kelpie_windows_device_info_test tests/device_info_windows_test.cpp src/device_info_windows.cpp)
  target_include_directories(kelpie_windows_device_info_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_device_info_test PRIVATE kelpie_engine_chromium_desktop nlohmann_json::nlohmann_json ws2_32 iphlpapi Rpcrt4)
  if(MSVC)
    target_compile_options(kelpie_windows_device_info_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_device_info_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_device_info_test COMMAND kelpie_windows_device_info_test)
  add_executable(kelpie_windows_browser_view_test tests/win32_browser_view_test.cpp src/win32_browser_view.cpp)
  target_include_directories(kelpie_windows_browser_view_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_browser_view_test PRIVATE user32)
  if(MSVC)
    target_compile_options(kelpie_windows_browser_view_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_browser_view_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_browser_view_test COMMAND kelpie_windows_browser_view_test)
  add_executable(kelpie_windows_startup_diagnostics_test tests/startup_diagnostics_test.cpp)
  target_include_directories(kelpie_windows_startup_diagnostics_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  if(MSVC)
    target_compile_options(kelpie_windows_startup_diagnostics_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_startup_diagnostics_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_startup_diagnostics_test COMMAND kelpie_windows_startup_diagnostics_test)
  # The favicon cache and the letter avatar are Win32/GDI+ only — no CEF — so
  # both configurations build and run these.
  add_executable(kelpie_windows_letter_avatar_test
    tests/letter_avatar_test.cpp
    src/letter_avatar.cpp
    ${WINDOWS_THEME_SOURCES})
  target_include_directories(kelpie_windows_letter_avatar_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_letter_avatar_test PRIVATE user32 gdi32 gdiplus uxtheme dwmapi)
  if(MSVC)
    target_compile_options(kelpie_windows_letter_avatar_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_letter_avatar_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_letter_avatar_test COMMAND kelpie_windows_letter_avatar_test)

  add_executable(kelpie_windows_favicon_cache_test
    tests/favicon_cache_test.cpp
    src/favicon_cache.cpp
    src/letter_avatar.cpp
    ${WINDOWS_THEME_SOURCES})
  target_include_directories(kelpie_windows_favicon_cache_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_favicon_cache_test PRIVATE user32 gdi32 gdiplus uxtheme dwmapi msimg32 ole32)
  if(MSVC)
    target_compile_options(kelpie_windows_favicon_cache_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_favicon_cache_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_favicon_cache_test COMMAND kelpie_windows_favicon_cache_test)

  add_executable(kelpie_windows_close_lifecycle_test tests/close_lifecycle_test.cpp)
  target_include_directories(kelpie_windows_close_lifecycle_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  if(MSVC)
    target_compile_options(kelpie_windows_close_lifecycle_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_close_lifecycle_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_close_lifecycle_test COMMAND kelpie_windows_close_lifecycle_test)
endif()

if(MINGW)
  target_link_options(kelpie_windows_browser PRIVATE -municode -static -static-libgcc -static-libstdc++)
endif()

if(BUILD_TESTING)
  add_executable(window_chrome_test
    tests/window_chrome_test.cpp
    src/window_chrome.cpp
    src/maximized_frame.cpp
    ${WINDOWS_THEME_SOURCES}
  )
  target_compile_definitions(window_chrome_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_include_directories(window_chrome_test PRIVATE src resources)
  target_link_libraries(window_chrome_test PRIVATE user32 gdi32 gdiplus uxtheme dwmapi comctl32 shell32)
  add_test(NAME window_chrome_test COMMAND window_chrome_test)

  # The maximized client-rect arithmetic, without a window or a monitor.
  add_executable(kelpie_windows_maximized_frame_test
    tests/maximized_frame_test.cpp
    src/maximized_frame.cpp
    src/theme/metrics.cpp
  )
  target_compile_definitions(kelpie_windows_maximized_frame_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_include_directories(kelpie_windows_maximized_frame_test PRIVATE src)
  target_link_libraries(kelpie_windows_maximized_frame_test PRIVATE user32 gdi32 shell32)
  if(MSVC)
    target_compile_options(kelpie_windows_maximized_frame_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_maximized_frame_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_maximized_frame_test COMMAND kelpie_windows_maximized_frame_test)

  add_executable(windows_shell_preview_test
    tests/windows_shell_preview_test.cpp
    tests/test_manifest.rc
    ${WINDOWS_THEME_SOURCES}
    src/win32_shell.cpp
    src/shell_tabs.cpp
    src/shell_chrome.cpp
    src/favorites_bar.cpp
    src/drag_effects.cpp
    src/window_chrome.cpp
    src/maximized_frame.cpp
    src/url_bar.cpp
    src/account_avatar.cpp
    src/win32_browser_view.cpp
    src/favicon_cache.cpp
    src/letter_avatar.cpp
    src/tab_tooltips.cpp
    src/toast_view.cpp
    src/panel_window.cpp
    src/link_list_panel.cpp
    src/display_format.cpp
    src/network_rows.cpp
    src/network_inspector.cpp
  )
  target_compile_definitions(windows_shell_preview_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_include_directories(windows_shell_preview_test PRIVATE src resources)
  # win32_browser_view.h includes kelpie/renderer_interface.h, which the
  # automation core owns; without it this target cannot compile.
  target_link_libraries(windows_shell_preview_test PRIVATE nlohmann_json::nlohmann_json
    kelpie_core_automation user32 gdi32 gdiplus uxtheme dwmapi comctl32 shell32 ole32 msimg32)
  if(MSVC)
    # tests/test_manifest.rc supplies the manifest; the linker would otherwise
    # add its own and the two collide as a duplicate resource.
    target_link_options(windows_shell_preview_test PRIVATE "/MANIFEST:NO")
  endif()

  add_test(NAME windows_shell_preview_test COMMAND windows_shell_preview_test)

  add_executable(kelpie_windows_theme_test
    tests/theme_test.cpp
    tests/test_manifest.rc
    ${WINDOWS_THEME_SOURCES}
  )
  target_compile_definitions(kelpie_windows_theme_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_include_directories(kelpie_windows_theme_test PRIVATE src resources)
  target_link_libraries(kelpie_windows_theme_test PRIVATE user32 gdi32 gdiplus uxtheme dwmapi comctl32)
  if(MSVC)
    target_link_options(kelpie_windows_theme_test PRIVATE "/MANIFEST:NO")
  endif()
  add_test(NAME kelpie_windows_theme_test COMMAND kelpie_windows_theme_test)

  add_executable(kelpie_windows_network_rows_test
    tests/network_rows_test.cpp src/network_rows.cpp src/display_format.cpp)
  target_include_directories(kelpie_windows_network_rows_test PRIVATE src)
  target_link_libraries(kelpie_windows_network_rows_test PRIVATE nlohmann_json::nlohmann_json user32 kernel32)
  target_compile_options(kelpie_windows_network_rows_test PRIVATE /UNDEBUG)
  add_test(NAME kelpie_windows_network_rows_test COMMAND kelpie_windows_network_rows_test)

  include(tests/close_tab.cmake)
  include(tests/native_window_control.cmake)
endif()
