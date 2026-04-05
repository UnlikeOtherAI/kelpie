cmake_minimum_required(VERSION 3.16)

project(kelpie_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)
include(FetchContent)

find_package(nlohmann_json CONFIG QUIET)
if(NOT TARGET nlohmann_json::nlohmann_json)
  find_path(NLOHMANN_JSON_INCLUDE_DIR
    NAMES nlohmann/json.hpp
  )
  if(NLOHMANN_JSON_INCLUDE_DIR)
    add_library(nlohmann_json INTERFACE)
    target_include_directories(nlohmann_json INTERFACE "${NLOHMANN_JSON_INCLUDE_DIR}")
    add_library(nlohmann_json::nlohmann_json ALIAS nlohmann_json)
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

add_subdirectory(core-protocol)
add_subdirectory(core-state)
add_subdirectory(core-automation)
add_subdirectory(core-mcp)
add_subdirectory(core-ai)

option(KELPIE_BUILD_DESKTOP_ENGINES "Build desktop browser engines (CEF/Chromium)" ON)
if(KELPIE_BUILD_DESKTOP_ENGINES)
  add_subdirectory(engine-chromium-desktop)
endif()
