include(FetchContent)

set(KELPIE_AI_USE_HTTPLIB_DEFAULT ON)
if(APPLE OR CMAKE_SYSTEM_NAME STREQUAL "Android")
  set(KELPIE_AI_USE_HTTPLIB_DEFAULT OFF)
endif()

option(
  KELPIE_AI_USE_HTTPLIB
  "Enable cpp-httplib for HTTP clients (Ollama, HF download/cloud)"
  ${KELPIE_AI_USE_HTTPLIB_DEFAULT}
)

set(CORE_AI_SOURCES
  src/ai_c_api.cpp
  src/model_catalog.cpp
)

if(KELPIE_AI_USE_HTTPLIB)
  FetchContent_Declare(
    cpp_httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG v0.18.3
    GIT_SHALLOW TRUE
  )
  FetchContent_MakeAvailable(cpp_httplib)

  list(APPEND CORE_AI_SOURCES
    src/hf_cloud_client.cpp
    src/model_store.cpp
    src/ollama_client.cpp
  )
endif()

add_library(kelpie_core_ai STATIC ${CORE_AI_SOURCES})

target_include_directories(kelpie_core_ai
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kelpie_core_ai
  PUBLIC
    kelpie_core_protocol
    nlohmann_json::nlohmann_json
)

if(KELPIE_AI_USE_HTTPLIB)
  target_link_libraries(kelpie_core_ai PRIVATE httplib::httplib)
  target_compile_definitions(kelpie_core_ai PUBLIC KELPIE_AI_HAS_HTTPLIB=1)
endif()

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
