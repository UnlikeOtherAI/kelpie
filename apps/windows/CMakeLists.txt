cmake_minimum_required(VERSION 3.16)
project(kelpie_windows VERSION 0.2.4 LANGUAGES CXX RC)
include(CTest)

add_subdirectory(../../core/windows kelpie-browser)

if(HAS_CEF OR CEF_ROOT)
  add_library(kelpie SHARED src/main.cpp src/standalone_entry.cpp src/release_updates.cpp resources/kelpie.rc)
else()
  add_executable(kelpie WIN32 src/main.cpp src/standalone_entry.cpp src/release_updates.cpp resources/kelpie.rc)
  if(MSVC)
    target_link_options(kelpie PRIVATE "/MANIFEST:NO")
  endif()
endif()

target_link_libraries(kelpie PRIVATE Kelpie::Browser)
target_link_libraries(kelpie PRIVATE winhttp comctl32)
target_compile_definitions(kelpie PRIVATE KELPIE_APP_VERSION="${PROJECT_VERSION}")

add_custom_command(TARGET kelpie POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${CMAKE_CURRENT_SOURCE_DIR}/../updates/install-windows.ps1" "$<TARGET_FILE_DIR:kelpie>/install-update.ps1")
target_compile_features(kelpie PRIVATE cxx_std_20)
target_include_directories(kelpie PRIVATE ../../core/windows/resources)
set_target_properties(kelpie PROPERTIES
  OUTPUT_NAME "kelpie"
  PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

if(HAS_CEF OR CEF_ROOT)
  kelpie_stage_browser_runtime(kelpie)
endif()

# Opt-in native embedding fixture; it is excluded from standalone releases.
option(KELPIE_BUILD_EMBEDDING_HOST "Build the native parent-window SDK fixture" OFF)
if(KELPIE_BUILD_EMBEDDING_HOST AND CEF_ROOT)
  add_library(kelpie_embed_host SHARED test/embedding_host.cpp resources/kelpie.rc)
  target_link_libraries(kelpie_embed_host PRIVATE Kelpie::Browser)
  target_compile_features(kelpie_embed_host PRIVATE cxx_std_20)
  target_include_directories(kelpie_embed_host PRIVATE ../../core/windows/resources)
  set_target_properties(kelpie_embed_host PROPERTIES
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
  )
  kelpie_stage_browser_runtime(kelpie_embed_host)
endif()

# Keep multi-config generators beside the shared runtime staging directory,
# matching the single-config release build and package manifest.
foreach(host IN ITEMS kelpie kelpie_embed_host)
  if(TARGET ${host})
    foreach(configuration IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
      set_property(TARGET ${host} PROPERTY RUNTIME_OUTPUT_DIRECTORY_${configuration} "${CMAKE_BINARY_DIR}")
    endforeach()
  endif()
endforeach()
