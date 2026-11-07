cmake_minimum_required(VERSION 3.16)
project(kelpie_windows VERSION 0.1.15 LANGUAGES CXX RC)
include(CTest)

add_subdirectory(../../core/windows kelpie-browser)

if(HAS_CEF OR CEF_ROOT)
  add_library(kelpie SHARED src/main.cpp resources/kelpie.rc)
else()
  add_executable(kelpie WIN32 src/main.cpp resources/kelpie.rc)
  if(MSVC)
    target_link_options(kelpie PRIVATE "/MANIFEST:NO")
  endif()
endif()

target_link_libraries(kelpie PRIVATE Kelpie::Browser)
target_compile_features(kelpie PRIVATE cxx_std_20)
target_include_directories(kelpie PRIVATE ../../core/windows/resources)
set_target_properties(kelpie PROPERTIES
  OUTPUT_NAME "kelpie"
  PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)
