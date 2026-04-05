cmake_minimum_required(VERSION 3.22.1)

project(kelpie_android_jni LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

set(BUILD_TESTING OFF CACHE BOOL "Disable native tests for Android JNI builds" FORCE)

set(KELPIE_NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../native)

# Disable httplib in core-ai on Android — HTTPS is handled by OkHttp in Kotlin.
set(KELPIE_AI_USE_HTTPLIB OFF CACHE BOOL "" FORCE)

# Skip desktop browser engines (CEF/Chromium) — not applicable on Android.
set(KELPIE_BUILD_DESKTOP_ENGINES OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

add_subdirectory(${KELPIE_NATIVE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/kelpie-native)

add_library(kelpie_jni SHARED
  kelpie_jni.cpp
)

target_link_libraries(kelpie_jni
  PRIVATE
    kelpie_core_state
    kelpie_core_protocol
    kelpie_core_ai
)
