include(FetchContent)

set(KELPIE_LOCAL_LLM_DEFAULT OFF)
if(WIN32 OR CMAKE_SYSTEM_NAME STREQUAL "Android" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(KELPIE_LOCAL_LLM_DEFAULT ON)
endif()
option(KELPIE_LOCAL_LLM "Embed the portable CPU GGUF runtime" ${KELPIE_LOCAL_LLM_DEFAULT})
if(KELPIE_LOCAL_LLM)
  enable_language(C)
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
  set(GGML_NATIVE OFF CACHE BOOL "Portable release binaries" FORCE)
  set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
  set(GGML_METAL OFF CACHE BOOL "" FORCE)
  set(GGML_BLAS OFF CACHE BOOL "" FORCE)
  set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(kelpie_llama
    URL https://github.com/ggml-org/llama.cpp/archive/8345f333951c661d166b00e6f9362e553768f292.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(kelpie_llama)
endif()

set(KELPIE_AI_USE_HTTPLIB_DEFAULT ON)
if(APPLE OR CMAKE_SYSTEM_NAME STREQUAL "Android")
  set(KELPIE_AI_USE_HTTPLIB_DEFAULT OFF)
endif()

option(
  KELPIE_AI_USE_HTTPLIB
  "Enable cpp-httplib for HTTP clients (Ollama, HF download/cloud)"
  ${KELPIE_AI_USE_HTTPLIB_DEFAULT}
)
option(KELPIE_AI_ENABLE_HF_HTTPS "Enable optional HTTPS Hugging Face cloud inference" OFF)

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
if(KELPIE_LOCAL_LLM)
  target_sources(kelpie_core_ai PRIVATE src/local_inference.cpp)
  target_link_libraries(kelpie_core_ai PUBLIC llama)
endif()

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
  if(KELPIE_AI_ENABLE_HF_HTTPS)
    find_package(OpenSSL REQUIRED)
    target_link_libraries(kelpie_core_ai PRIVATE OpenSSL::SSL OpenSSL::Crypto)
    target_compile_definitions(kelpie_core_ai PRIVATE CPPHTTPLIB_OPENSSL_SUPPORT
      PUBLIC KELPIE_AI_HAS_HF_HTTPS=1)
  else()
    target_compile_definitions(kelpie_core_ai PUBLIC KELPIE_AI_HAS_HF_HTTPS=0)
  endif()
endif()

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
