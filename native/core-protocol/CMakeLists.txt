add_library(kelpie_core_protocol STATIC
  src/error_codes.cpp
  src/partition.cpp
  src/platform.cpp
  src/viewport_presets_c_api.cpp
)

target_include_directories(kelpie_core_protocol
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
