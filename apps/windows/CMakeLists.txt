cmake_minimum_required(VERSION 3.16)

project(kelpie_windows VERSION 0.1.1 LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
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
if(HAS_CEF)
  set(CMAKE_CXX_STANDARD 20)
endif()

if(MSVC)
  # CEF's Windows wrapper uses the static CRT. Every native target must use
  # the same CRT or the linker rejects mixed debug/runtime allocations.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
endif()

include(CTest)
include(FetchContent)

set(KELPIE_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../native")
if(NOT EXISTS "${KELPIE_NATIVE_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "Expected native core at ${KELPIE_NATIVE_ROOT}")
endif()

set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_ZLIB_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)

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

set(WINDOWS_APP_SOURCES
  src/main.cpp
  src/cef_pump_deadline.cpp
  src/windows_app.cpp
  src/win32_shell.cpp
  src/win32_browser_view.cpp
  src/url_bar.cpp
  src/settings_view.cpp
  src/bookmarks_view.cpp
  src/history_view.cpp
  src/network_inspector.cpp
  src/profile_session.cpp
  src/session_snapshot.cpp
  src/toast_view.cpp
  src/device_info_windows.cpp
  src/mdns_windows.cpp
)

set(WINDOWS_APP_HEADERS
  src/windows_app.h
  src/cef_pump_deadline.h
  src/win32_shell.h
  src/win32_browser_view.h
  src/url_bar.h
  src/settings_view.h
  src/bookmarks_view.h
  src/history_view.h
  src/network_inspector.h
  src/profile_session.h
  src/session_snapshot.h
  src/toast_view.h
  src/device_info_windows.h
  src/mdns_windows.h
)

set(WINDOWS_APP_RESOURCES
  resources/kelpie.rc
  resources/resource.h
)

add_library(kelpie SHARED
  ${WINDOWS_APP_SOURCES}
  ${WINDOWS_APP_HEADERS}
  ${WINDOWS_APP_RESOURCES}
)

target_compile_definitions(kelpie
  PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _WIN32_WINNT=0x0600
    UNICODE
    _UNICODE
)

target_include_directories(kelpie
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/resources"
)

target_link_libraries(kelpie
  PRIVATE
    httplib::httplib
    kelpie_core_protocol
    kelpie_core_state
    kelpie_core_automation
    kelpie_core_mcp
    nlohmann_json::nlohmann_json
    user32
    gdi32
    shell32
    ws2_32
    iphlpapi
    dnsapi
    advapi32
    bcrypt
    comctl32
    ole32
    Rpcrt4
)

set_target_properties(kelpie PROPERTIES
  OUTPUT_NAME "kelpie"
  PREFIX ""
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

if(TARGET kelpie_engine_chromium_desktop)
  target_link_libraries(kelpie PRIVATE kelpie_engine_chromium_desktop)
endif()

if(HAS_CEF)
  if(NOT CEF_ROOT)
    message(FATAL_ERROR "HAS_CEF requires CEF_ROOT to point at a CEF binary distribution")
  endif()

  target_compile_definitions(kelpie PRIVATE HAS_CEF=1 CEF_USE_BOOTSTRAP=1)
  target_include_directories(kelpie PRIVATE "${CEF_ROOT}" "${CEF_ROOT}/include")

  find_library(CEF_LIBCEF NAMES libcef PATHS "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug" NO_DEFAULT_PATH)
  if(NOT CEF_WRAPPER)
    find_library(CEF_WRAPPER NAMES libcef_dll_wrapper PATHS
      "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug"
      "${CEF_ROOT}/build/libcef_dll_wrapper"
      "${CEF_ROOT}/build/libcef_dll_wrapper/Release"
      NO_DEFAULT_PATH)
  endif()

  if(CEF_LIBCEF)
    target_link_libraries(kelpie PRIVATE "${CEF_LIBCEF}")
  endif()
  if(CEF_WRAPPER AND EXISTS "${CEF_WRAPPER}")
    target_link_libraries(kelpie PRIVATE "${CEF_WRAPPER}")
  else()
    message(FATAL_ERROR "Windows CEF requires a built libcef_dll_wrapper; set CEF_WRAPPER")
  endif()

  file(GLOB CEF_RUNTIME_FILES LIST_DIRECTORIES false
    "${CEF_ROOT}/Release/*.dll"
    "${CEF_ROOT}/Release/*.bin"
    "${CEF_ROOT}/Release/*.dat"
    "${CEF_ROOT}/Release/*.json"
    "${CEF_ROOT}/Resources/*.pak"
    "${CEF_ROOT}/Resources/*.dat"
  )
  foreach(runtime_file IN LISTS CEF_RUNTIME_FILES)
    add_custom_command(TARGET kelpie POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${runtime_file}" "$<TARGET_FILE_DIR:kelpie>")
  endforeach()
  add_custom_command(TARGET kelpie POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CEF_ROOT}/Resources/locales" "$<TARGET_FILE_DIR:kelpie>/locales"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CEF_ROOT}/Release/bootstrap.exe" "$<TARGET_FILE_DIR:kelpie>/kelpie.exe"
    COMMENT "Bundling sandboxed CEF bootstrap and locale resources")
endif()

if(BUILD_TESTING)
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
  target_include_directories(kelpie_windows_session_snapshot_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(kelpie_windows_session_snapshot_test PRIVATE nlohmann_json::nlohmann_json)
  if(MSVC)
    target_compile_options(kelpie_windows_session_snapshot_test PRIVATE /UNDEBUG)
  else()
    target_compile_options(kelpie_windows_session_snapshot_test PRIVATE -UNDEBUG)
  endif()
  add_test(NAME kelpie_windows_session_snapshot_test COMMAND kelpie_windows_session_snapshot_test)
  add_executable(kelpie_windows_cef_pump_deadline_test tests/cef_pump_deadline_test.cpp src/cef_pump_deadline.cpp)
  target_include_directories(kelpie_windows_cef_pump_deadline_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_compile_options(kelpie_windows_cef_pump_deadline_test PRIVATE /UNDEBUG)
  add_test(NAME kelpie_windows_cef_pump_deadline_test COMMAND kelpie_windows_cef_pump_deadline_test)
endif()

if(MINGW)
  target_link_options(kelpie PRIVATE -municode -static -static-libgcc -static-libstdc++)
endif()
