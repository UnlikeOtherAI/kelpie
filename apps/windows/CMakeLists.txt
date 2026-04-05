cmake_minimum_required(VERSION 3.16)

project(kelpie_windows LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

set(KELPIE_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../native")
if(NOT EXISTS "${KELPIE_NATIVE_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "Expected native core at ${KELPIE_NATIVE_ROOT}")
endif()

set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_ZLIB_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)

if(NOT TARGET kelpie_core_protocol)
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
  src/windows_app.cpp
  src/windows_app_server.cpp
  src/win32_shell.cpp
  src/win32_browser_view.cpp
  src/url_bar.cpp
  src/settings_view.cpp
  src/bookmarks_view.cpp
  src/history_view.cpp
  src/network_inspector.cpp
  src/toast_view.cpp
  src/device_info_windows.cpp
  src/mdns_windows.cpp
)

set(WINDOWS_APP_HEADERS
  src/windows_app.h
  src/win32_shell.h
  src/win32_browser_view.h
  src/url_bar.h
  src/settings_view.h
  src/bookmarks_view.h
  src/history_view.h
  src/network_inspector.h
  src/toast_view.h
  src/device_info_windows.h
  src/mdns_windows.h
)

set(WINDOWS_APP_RESOURCES
  resources/kelpie.rc
  resources/resource.h
)

add_executable(kelpie WIN32
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
    comctl32
    ole32
    Rpcrt4
)

set_target_properties(kelpie PROPERTIES
  OUTPUT_NAME "kelpie"
)

if(TARGET kelpie_engine_chromium_desktop)
  target_link_libraries(kelpie PRIVATE kelpie_engine_chromium_desktop)
endif()

option(HAS_CEF "Build Windows app with Chromium Embedded Framework" OFF)
if(CEF_ROOT)
  set(HAS_CEF ON)
endif()

if(HAS_CEF)
  if(NOT CEF_ROOT)
    message(FATAL_ERROR "HAS_CEF requires CEF_ROOT to point at a CEF binary distribution")
  endif()

  target_compile_definitions(kelpie PRIVATE HAS_CEF=1)
  target_include_directories(kelpie PRIVATE "${CEF_ROOT}" "${CEF_ROOT}/include")

  find_library(CEF_LIBCEF NAMES libcef PATHS "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug" NO_DEFAULT_PATH)
  find_library(CEF_WRAPPER NAMES libcef_dll_wrapper PATHS "${CEF_ROOT}/Release" "${CEF_ROOT}/Debug" NO_DEFAULT_PATH)

  if(CEF_LIBCEF)
    target_link_libraries(kelpie PRIVATE "${CEF_LIBCEF}")
  endif()
  if(CEF_WRAPPER)
    target_link_libraries(kelpie PRIVATE "${CEF_WRAPPER}")
  endif()

  file(GLOB CEF_RUNTIME_FILES
    "${CEF_ROOT}/Release/*.dll"
    "${CEF_ROOT}/Release/*.bin"
    "${CEF_ROOT}/Release/*.dat"
    "${CEF_ROOT}/Resources/*"
  )
  foreach(runtime_file IN LISTS CEF_RUNTIME_FILES)
    add_custom_command(TARGET kelpie POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${runtime_file}"
        "$<TARGET_FILE_DIR:kelpie>"
    )
  endforeach()
endif()

if(MINGW)
  target_link_options(kelpie PRIVATE -municode -static -static-libgcc -static-libstdc++)
endif()
