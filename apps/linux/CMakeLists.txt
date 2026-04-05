cmake_minimum_required(VERSION 3.16)

project(kelpie_linux LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
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

set(BUILD_TESTING OFF CACHE BOOL "Disable native library tests for app builds" FORCE)
if(KELPIE_LINUX_HAS_CEF)
  message(STATUS "Linux app: enabling CEF from ${KELPIE_LINUX_CEF_ROOT}")
  set(KELPIE_ENABLE_CHROMIUM_DESKTOP ON CACHE BOOL
      "Build the shared Chromium desktop engine with CEF for the Linux app" FORCE)
else()
  message(STATUS "Linux app: CEF SDK not found or incomplete at ${KELPIE_LINUX_CEF_ROOT}")
  set(KELPIE_ENABLE_CHROMIUM_DESKTOP OFF CACHE BOOL
      "Build the shared Chromium desktop engine with CEF for the Linux app" FORCE)
endif()
set(KELPIE_NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../native")
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

set(KELPIE_LINUX_HAS_AVAHI 0)
if(PkgConfig_FOUND)
  pkg_check_modules(AVAHI_CLIENT IMPORTED_TARGET avahi-client)
  if(AVAHI_CLIENT_FOUND)
    set(KELPIE_LINUX_HAS_AVAHI 1)
  endif()
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
  src/http_server.cpp
  src/linux_app.cpp
  src/linux_app_api.cpp
  src/headless_shell.cpp
  src/gui_shell.cpp
  src/gtk_browser_view.cpp
  src/url_bar.cpp
  src/ui_theme.cpp
  src/settings_view.cpp
  src/bookmarks_view.cpp
  src/history_view.cpp
  src/network_inspector.cpp
  src/toast_view.cpp
  src/device_info_linux.cpp
  src/mdns_avahi.cpp
  src/stub_renderer.cpp
)

target_include_directories(kelpie-linux
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_compile_definitions(kelpie-linux
  PRIVATE
    KELPIE_LINUX_HAS_GTK=${KELPIE_LINUX_HAS_GTK}
    KELPIE_LINUX_HAS_AVAHI=${KELPIE_LINUX_HAS_AVAHI}
    KELPIE_LINUX_HAS_FONTCONFIG=${KELPIE_LINUX_HAS_FONTCONFIG}
    KELPIE_LINUX_HAS_CEF=${KELPIE_LINUX_HAS_CEF}
    KELPIE_LINUX_VERSION="0.1.0-dev"
)

if(KELPIE_LINUX_HAS_CEF)
  target_include_directories(kelpie-linux PRIVATE "${KELPIE_LINUX_CEF_ROOT}")
endif()

if(KELPIE_LINUX_HAS_GTK)
  target_link_libraries(kelpie-linux PRIVATE PkgConfig::GTK3)
endif()

if(KELPIE_LINUX_HAS_AVAHI)
  target_link_libraries(kelpie-linux PRIVATE PkgConfig::AVAHI_CLIENT)
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
)

add_custom_command(TARGET kelpie-linux POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../macos/Kelpie/Resources/FontAwesome6Brands-Regular.otf"
    "$<TARGET_FILE_DIR:kelpie-linux>/FontAwesome6Brands-Regular.otf"
)

add_custom_command(TARGET kelpie-linux POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../macos/Kelpie/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    "$<TARGET_FILE_DIR:kelpie-linux>/icon-1024.png"
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
