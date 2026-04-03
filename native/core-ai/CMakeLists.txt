include(FetchContent)

FetchContent_Declare(
  cpp_httplib
  GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
  GIT_TAG v0.18.3
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(cpp_httplib)

add_library(mollotov_core_ai STATIC
  src/ai_c_api.cpp
  src/model_catalog.cpp
  src/model_store.cpp
)

target_include_directories(mollotov_core_ai
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(mollotov_core_ai
  PUBLIC
    mollotov_core_protocol
    nlohmann_json::nlohmann_json
  PRIVATE
    httplib::httplib
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
