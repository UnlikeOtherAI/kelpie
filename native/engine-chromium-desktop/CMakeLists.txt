include(FetchContent)
find_package(Threads REQUIRED)

find_path(CPP_HTTPLIB_INCLUDE_DIR
  NAMES httplib.h
)

if(CPP_HTTPLIB_INCLUDE_DIR)
  add_library(httplib INTERFACE)
  target_include_directories(httplib INTERFACE "${CPP_HTTPLIB_INCLUDE_DIR}")
  add_library(httplib::httplib ALIAS httplib)
else()
  FetchContent_Declare(
    cpp_httplib
    URL https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.18.5.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(cpp_httplib)
endif()

set(MOLOTOV_DESKTOP_ENGINE_SOURCES
  src/desktop_app.cpp
  src/desktop_bridge.cpp
  src/desktop_http_server.cpp
  src/desktop_mcp_server.cpp
  src/desktop_router.cpp
  src/cef_renderer.cpp
  src/handlers/navigation_handler.cpp
  src/handlers/interaction_handler.cpp
  src/handlers/dom_handler.cpp
  src/handlers/evaluate_handler.cpp
  src/handlers/screenshot_handler.cpp
  src/handlers/scroll_handler.cpp
  src/handlers/console_handler.cpp
  src/handlers/network_handler.cpp
  src/handlers/device_handler.cpp
  src/handlers/bookmark_handler.cpp
  src/handlers/history_handler.cpp
  src/handlers/browser_mgmt_handler.cpp
  src/handlers/renderer_handler.cpp
  src/handlers/viewport_handler.cpp
  src/handlers/cookie_handler.cpp
)

option(KELPIE_ENABLE_CHROMIUM_DESKTOP "Build the Chromium desktop engine with CEF" OFF)
set(CEF_ROOT "" CACHE PATH "Path to an extracted CEF SDK root")
set(KELPIE_CHROMIUM_DESKTOP_CEF_LIB "")
set(KELPIE_CHROMIUM_DESKTOP_CEF_WRAPPER "")

if(KELPIE_ENABLE_CHROMIUM_DESKTOP)
  list(APPEND MOLOTOV_DESKTOP_ENGINE_SOURCES src/cef_app_factory.cpp)
  if(NOT CEF_ROOT)
    message(FATAL_ERROR "KELPIE_ENABLE_CHROMIUM_DESKTOP requires CEF_ROOT to point at a CEF SDK")
  endif()
  if(EXISTS "${CEF_ROOT}/build/libcef_dll_wrapper/libcef_dll_wrapper.a")
    set(KELPIE_CHROMIUM_DESKTOP_CEF_WRAPPER
        "${CEF_ROOT}/build/libcef_dll_wrapper/libcef_dll_wrapper.a")
  elseif(EXISTS "${CEF_ROOT}/build/libcef_dll_wrapper/Release/libcef_dll_wrapper.a")
    set(KELPIE_CHROMIUM_DESKTOP_CEF_WRAPPER
        "${CEF_ROOT}/build/libcef_dll_wrapper/Release/libcef_dll_wrapper.a")
  endif()
  if(EXISTS "${CEF_ROOT}/Release/libcef.so")
    set(KELPIE_CHROMIUM_DESKTOP_CEF_LIB "${CEF_ROOT}/Release/libcef.so")
  endif()
  list(APPEND MOLOTOV_DESKTOP_ENGINE_SOURCES src/desktop_engine.cpp)
else()
  list(APPEND MOLOTOV_DESKTOP_ENGINE_SOURCES src/desktop_engine_stub.cpp)
endif()

add_library(kelpie_engine_chromium_desktop STATIC
  ${MOLOTOV_DESKTOP_ENGINE_SOURCES}
)

target_include_directories(kelpie_engine_chromium_desktop
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if(KELPIE_ENABLE_CHROMIUM_DESKTOP)
  target_include_directories(kelpie_engine_chromium_desktop PRIVATE ${CEF_ROOT})
  if(KELPIE_CHROMIUM_DESKTOP_CEF_WRAPPER)
    target_link_libraries(kelpie_engine_chromium_desktop
      PUBLIC
        "${KELPIE_CHROMIUM_DESKTOP_CEF_WRAPPER}"
    )
  endif()
  if(KELPIE_CHROMIUM_DESKTOP_CEF_LIB)
    target_link_libraries(kelpie_engine_chromium_desktop
      PUBLIC
        "${KELPIE_CHROMIUM_DESKTOP_CEF_LIB}"
    )
  endif()
endif()

target_link_libraries(kelpie_engine_chromium_desktop
  PUBLIC
    kelpie_core_protocol
    kelpie_core_state
    kelpie_core_automation
    kelpie_core_mcp
    nlohmann_json::nlohmann_json
    httplib::httplib
    Threads::Threads
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
