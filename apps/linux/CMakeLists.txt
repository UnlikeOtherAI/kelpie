cmake_minimum_required(VERSION 3.16)

project(kelpie_linux LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(KELPIE_LINUX_HEADLESS_ONLY "Build Kelpie Linux without GTK UI support" OFF)

include(FetchContent)
find_package(PkgConfig QUIET)
find_package(Threads REQUIRED)
find_package(nlohmann_json CONFIG QUIET)

if(NOT TARGET nlohmann_json::nlohmann_json)
  find_path(KELPIE_LINUX_NLOHMANN_JSON_INCLUDE_DIR
    NAMES nlohmann/json.hpp
  )
  if(KELPIE_LINUX_NLOHMANN_JSON_INCLUDE_DIR)
    add_library(kelpie_linux_nlohmann_json INTERFACE)
    target_include_directories(kelpie_linux_nlohmann_json INTERFACE
      "${KELPIE_LINUX_NLOHMANN_JSON_INCLUDE_DIR}"
    )
    add_library(nlohmann_json::nlohmann_json ALIAS kelpie_linux_nlohmann_json)
  endif()
endif()

if(NOT TARGET nlohmann_json::nlohmann_json)
  FetchContent_Declare(
    nlohmann_json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(nlohmann_json)
endif()

set(KELPIE_LINUX_HAS_CEF 0)
set(KELPIE_LINUX_CEF_LIB "")
set(KELPIE_LINUX_CEF_WRAPPER "")
set(KELPIE_LINUX_CEF_ROOT "")
if(DEFINED CEF_ROOT AND NOT "${CEF_ROOT}" STREQUAL "")
  get_filename_component(KELPIE_LINUX_CEF_ROOT "${CEF_ROOT}" REALPATH)
endif()
if(KELPIE_LINUX_CEF_ROOT
   AND EXISTS "${KELPIE_LINUX_CEF_ROOT}/include/cef_app.h"
   AND EXISTS "${KELPIE_LINUX_CEF_ROOT}/Release/libcef.so")
  set(KELPIE_LINUX_CEF_LIB "${KELPIE_LINUX_CEF_ROOT}/Release/libcef.so")
  if(EXISTS "${KELPIE_LINUX_CEF_ROOT}/build/libcef_dll_wrapper/libcef_dll_wrapper.a")
    set(KELPIE_LINUX_CEF_WRAPPER "${KELPIE_LINUX_CEF_ROOT}/build/libcef_dll_wrapper/libcef_dll_wrapper.a")
  elseif(EXISTS "${KELPIE_LINUX_CEF_ROOT}/build/libcef_dll_wrapper/Release/libcef_dll_wrapper.a")
    set(KELPIE_LINUX_CEF_WRAPPER "${KELPIE_LINUX_CEF_ROOT}/build/libcef_dll_wrapper/Release/libcef_dll_wrapper.a")
  endif()
  set(KELPIE_LINUX_HAS_CEF 1)
endif()

include(CTest)
if(KELPIE_LINUX_HAS_CEF)
  message(STATUS "Linux app: enabling CEF from ${KELPIE_LINUX_CEF_ROOT}")
  set(KELPIE_ENABLE_CHROMIUM_DESKTOP ON CACHE BOOL
      "Build the shared Chromium desktop engine with CEF for the Linux app" FORCE)
else()
  message(STATUS "Linux app: CEF SDK not found or incomplete at ${KELPIE_LINUX_CEF_ROOT}")
  set(KELPIE_ENABLE_CHROMIUM_DESKTOP OFF CACHE BOOL
      "Build the shared Chromium desktop engine with CEF for the Linux app" FORCE)
endif()
set(KELPIE_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../core/native")
add_subdirectory("${KELPIE_NATIVE_ROOT}" "${CMAKE_BINARY_DIR}/kelpie-native")

set(KELPIE_LINUX_HAS_GTK 0)
if(NOT KELPIE_LINUX_HEADLESS_ONLY)
  if(PkgConfig_FOUND)
    pkg_check_modules(GTK3 IMPORTED_TARGET gtk+-3.0)
    if(GTK3_FOUND)
      set(KELPIE_LINUX_HAS_GTK 1)
    endif()
  endif()
endif()

# Cookie-sync discovery loads libavahi-client at runtime (dlopen), so only the
# headers are needed here and the app still starts on systems without Avahi.
set(KELPIE_LINUX_HAS_AVAHI_HEADERS 0)
if(PkgConfig_FOUND)
  pkg_check_modules(AVAHI_CLIENT avahi-client)
endif()
if(AVAHI_CLIENT_FOUND)
  set(KELPIE_LINUX_HAS_AVAHI_HEADERS 1)
elseif(KELPIE_LINUX_HAS_CEF)
  message(FATAL_ERROR "The Chromium Linux build needs the Avahi client headers for cookie-sync discovery: install libavahi-client-dev (Debian/Ubuntu) or avahi-devel (Fedora)")
endif()

set(KELPIE_LINUX_HAS_FONTCONFIG 0)
if(PkgConfig_FOUND)
  pkg_check_modules(FONTCONFIG IMPORTED_TARGET fontconfig)
  if(FONTCONFIG_FOUND)
    set(KELPIE_LINUX_HAS_FONTCONFIG 1)
  endif()
endif()

add_executable(kelpie-linux
  src/main.cpp

  src/headless_shell.cpp
  src/gui_shell.cpp
  src/gtk_browser_view.cpp
  src/gtk_browser_input.cpp
  src/browser_chrome.cpp
  src/chrome_icons.cpp
  src/window_geometry.cpp
  src/url_bar.cpp
  src/ui_theme.cpp
  src/settings_view.cpp
  src/bookmarks_view.cpp
  src/history_view.cpp
  src/network_inspector.cpp
  src/toast_view.cpp
  src/device_info_linux.cpp
  src/release_updates.cpp
)

target_include_directories(kelpie-linux
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_compile_definitions(kelpie-linux
  PRIVATE
    KELPIE_LINUX_HAS_GTK=${KELPIE_LINUX_HAS_GTK}
    KELPIE_LINUX_HAS_FONTCONFIG=${KELPIE_LINUX_HAS_FONTCONFIG}
    KELPIE_LINUX_HAS_CEF=${KELPIE_LINUX_HAS_CEF}
    KELPIE_LINUX_VERSION="0.2.5"
)

if(KELPIE_LINUX_HAS_CEF)
  target_include_directories(kelpie-linux PRIVATE "${KELPIE_LINUX_CEF_ROOT}")
endif()

if(KELPIE_LINUX_HAS_GTK)
  find_package(CURL REQUIRED)
  target_link_libraries(kelpie-linux PRIVATE PkgConfig::GTK3 CURL::libcurl)
endif()

if(KELPIE_LINUX_HAS_FONTCONFIG)
  target_link_libraries(kelpie-linux PRIVATE PkgConfig::FONTCONFIG)
endif()

target_link_libraries(kelpie-linux
  PRIVATE
    kelpie_core_protocol
    kelpie_core_state
    kelpie_core_automation
    kelpie_core_mcp
    nlohmann_json::nlohmann_json
    Threads::Threads
)

if(TARGET kelpie_engine_chromium_desktop)
  target_link_libraries(kelpie-linux PRIVATE kelpie_engine_chromium_desktop)
endif()

set_target_properties(kelpie-linux PROPERTIES
  OUTPUT_NAME "kelpie-linux"
  BUILD_RPATH "\$ORIGIN"
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "\$ORIGIN"
  INSTALL_RPATH_USE_LINK_PATH FALSE
)

add_custom_command(TARGET kelpie-linux POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${CMAKE_CURRENT_SOURCE_DIR}/../updates/install-linux.sh" "$<TARGET_FILE_DIR:kelpie-linux>/install-update.sh")

add_custom_command(TARGET kelpie-linux POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../core/native/resources/FontAwesome6Brands-Regular.otf"
    "$<TARGET_FILE_DIR:kelpie-linux>/FontAwesome6Brands-Regular.otf"
)

add_custom_command(TARGET kelpie-linux POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/kelpie-icon-1024.png"
    "$<TARGET_FILE_DIR:kelpie-linux>/icon-1024.png"
)

add_custom_command(TARGET kelpie-linux POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    "$<TARGET_FILE_DIR:kelpie-linux>/diagnostics"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/diagnostics/coordinate-calibration.html"
    "$<TARGET_FILE_DIR:kelpie-linux>/diagnostics/coordinate-calibration.html"
)

if(KELPIE_LINUX_HAS_CEF)
  file(GLOB KELPIE_LINUX_CEF_RELEASE_FILES
    "${KELPIE_LINUX_CEF_ROOT}/Release/*"
  )
  file(GLOB KELPIE_LINUX_CEF_RESOURCE_FILES
    "${KELPIE_LINUX_CEF_ROOT}/Resources/*"
  )

  foreach(runtime_file IN LISTS KELPIE_LINUX_CEF_RELEASE_FILES)
    add_custom_command(TARGET kelpie-linux POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${runtime_file}"
        "$<TARGET_FILE_DIR:kelpie-linux>"
    )
  endforeach()

  foreach(resource_file IN LISTS KELPIE_LINUX_CEF_RESOURCE_FILES)
    if(IS_DIRECTORY "${resource_file}")
      get_filename_component(resource_name "${resource_file}" NAME)
      add_custom_command(TARGET kelpie-linux POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${resource_file}"
          "$<TARGET_FILE_DIR:kelpie-linux>/${resource_name}"
      )
    else()
      add_custom_command(TARGET kelpie-linux POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${resource_file}"
          "$<TARGET_FILE_DIR:kelpie-linux>"
      )
    endif()
  endforeach()
endif()

# Both variants share the local-control contract: a profile lock and a
# per-launch bearer token published in readiness.json.
add_subdirectory("${KELPIE_NATIVE_ROOT}/desktop-account" "${CMAKE_BINARY_DIR}/desktop-account")
add_subdirectory("${KELPIE_NATIVE_ROOT}/desktop-connect" "${CMAKE_BINARY_DIR}/desktop-connect")
add_subdirectory("${KELPIE_NATIVE_ROOT}/desktop-sync" "${CMAKE_BINARY_DIR}/desktop-sync")
target_link_libraries(kelpie-linux PRIVATE kelpie_desktop_account kelpie_desktop_connect kelpie_desktop_sync)
target_sources(kelpie-linux PRIVATE src/profile_session.cpp)
if(BUILD_TESTING)
  add_executable(linux_standalone_instance_test tests/standalone_instance_test.cpp)
  target_include_directories(linux_standalone_instance_test PRIVATE src)
  target_compile_options(linux_standalone_instance_test PRIVATE -UNDEBUG)
  add_test(NAME linux_standalone_instance_test COMMAND linux_standalone_instance_test)
  add_executable(linux_profile_session_test tests/profile_session_test.cpp src/profile_session.cpp)
  target_include_directories(linux_profile_session_test PRIVATE src)
  target_compile_options(linux_profile_session_test PRIVATE -UNDEBUG)
  target_link_libraries(linux_profile_session_test PRIVATE kelpie_desktop_account)
  add_test(NAME linux_profile_session_test COMMAND linux_profile_session_test)
endif()

# Discovery is portable C++ over a dlopen'ed Avahi; its tests run in both
# configurations. Only the Chromium build syncs.
add_library(kelpie_linux_sync_discovery STATIC src/avahi_sync_discovery.cpp src/sync_peer_events.cpp)
target_include_directories(kelpie_linux_sync_discovery PUBLIC src)
target_compile_definitions(kelpie_linux_sync_discovery PRIVATE
  KELPIE_LINUX_HAS_AVAHI_HEADERS=${KELPIE_LINUX_HAS_AVAHI_HEADERS})
if(KELPIE_LINUX_HAS_AVAHI_HEADERS)
  target_include_directories(kelpie_linux_sync_discovery PRIVATE ${AVAHI_CLIENT_INCLUDE_DIRS})
endif()
target_link_libraries(kelpie_linux_sync_discovery PUBLIC kelpie_desktop_sync Threads::Threads ${CMAKE_DL_LIBS})
if(BUILD_TESTING)
  add_executable(linux_sync_discovery_test tests/sync_discovery_test.cpp)
  target_compile_options(linux_sync_discovery_test PRIVATE -UNDEBUG)
  target_link_libraries(linux_sync_discovery_test PRIVATE kelpie_linux_sync_discovery)
  add_test(NAME linux_sync_discovery_test COMMAND linux_sync_discovery_test)
  # A real Avahi round trip; it runs only with KELPIE_SYNC_MDNS_LIVE=1.
  add_executable(linux_avahi_sync_discovery_live_test tests/avahi_sync_discovery_live_test.cpp)
  target_compile_options(linux_avahi_sync_discovery_live_test PRIVATE -UNDEBUG)
  target_link_libraries(linux_avahi_sync_discovery_live_test PRIVATE kelpie_linux_sync_discovery)
  add_test(NAME linux_avahi_sync_discovery_live_test COMMAND linux_avahi_sync_discovery_live_test)
endif()

if(KELPIE_LINUX_HAS_CEF)
  target_sources(kelpie-linux PRIVATE src/linux_desktop_app.cpp src/linux_desktop_actions.cpp)
  target_link_libraries(kelpie-linux PRIVATE kelpie_linux_sync_discovery)
else()
  target_sources(kelpie-linux PRIVATE src/http_server.cpp src/linux_app.cpp src/linux_app_api.cpp src/linux_browser_gateway.cpp src/linux_stub_chrome.cpp src/tap_runtime_utils.cpp src/web_runtime_utils.cpp src/stub_renderer.cpp)
  if(BUILD_TESTING)
    add_executable(linux_http_server_test tests/http_server_test.cpp src/http_server.cpp)
    target_include_directories(linux_http_server_test PRIVATE src)
    target_compile_options(linux_http_server_test PRIVATE -UNDEBUG)
    target_link_libraries(linux_http_server_test PRIVATE nlohmann_json::nlohmann_json Threads::Threads)
    add_test(NAME linux_http_server_test COMMAND linux_http_server_test)
  endif()
endif()
