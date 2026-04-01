add_library(mollotov_core_protocol STATIC
  src/error_codes.cpp
  src/platform.cpp
)

target_include_directories(mollotov_core_protocol
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
