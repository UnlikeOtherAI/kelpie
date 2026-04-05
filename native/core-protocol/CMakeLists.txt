add_library(kelpie_core_protocol STATIC
  src/error_codes.cpp
  src/platform.cpp
  src/viewport_presets_c_api.cpp
)

target_include_directories(kelpie_core_protocol
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
