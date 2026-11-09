# Host (desktop JVM) build of the cookie-sync JNI bridge, so JVM unit tests run
# the real core-sync instead of a fake. The app uses src/main/cpp instead.
cmake_minimum_required(VERSION 3.22)

project(kelpie_sync_host_jni LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_TESTING OFF CACHE BOOL "No core-sync CTest in the host JNI build" FORCE)

if(NOT KELPIE_JNI_INCLUDE)
  message(FATAL_ERROR "Pass -DKELPIE_JNI_INCLUDE=<JDK>/include and -DKELPIE_JNI_PLATFORM_INCLUDE")
endif()

include(FetchContent)
FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

set(KELPIE_NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native)
add_subdirectory(${KELPIE_NATIVE_DIR}/core-sync ${CMAKE_CURRENT_BINARY_DIR}/core-sync)

add_library(kelpie_sync_host_jni SHARED ${CMAKE_CURRENT_SOURCE_DIR}/../../main/cpp/cookie_sync_jni.cpp)
target_include_directories(kelpie_sync_host_jni PRIVATE ${KELPIE_JNI_INCLUDE} ${KELPIE_JNI_PLATFORM_INCLUDE})
target_compile_definitions(kelpie_sync_host_jni PRIVATE _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING)
target_link_libraries(kelpie_sync_host_jni PRIVATE kelpie_core_sync)

foreach(config "" _DEBUG _RELEASE _RELWITHDEBINFO _MINSIZEREL)
  set_target_properties(kelpie_sync_host_jni PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY${config} ${KELPIE_JNI_OUTPUT}
    RUNTIME_OUTPUT_DIRECTORY${config} ${KELPIE_JNI_OUTPUT})
endforeach()
