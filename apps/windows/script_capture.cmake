# Native capture stays on the existing sandboxed Windows executable target.
set(KELPIE_SCRIPT_CODEC_SOURCES
  src/script_media_encoder.cpp
  src/script_media_gif.cpp
  src/script_media_video.cpp
  src/script_media_png.cpp
)
set(KELPIE_SCRIPT_SYSTEM_LIBRARIES
  ole32 windowscodecs mfplat mfreadwrite mfuuid wmcodecdspuuid propsys
)
target_sources(kelpie PRIVATE
  ${KELPIE_SCRIPT_CODEC_SOURCES}
  src/script_capture_service.cpp
  src/script_artifact_store.cpp
  src/script_artifact_lifecycle.cpp
  src/script_frame_compositor.cpp
  src/script_native_overlay.cpp
)
target_link_libraries(kelpie PRIVATE
  ${KELPIE_SCRIPT_SYSTEM_LIBRARIES} crypt32
)

if(BUILD_TESTING AND WIN32)
  add_executable(kelpie_windows_script_media_test
    tests/script_media_encoder_test.cpp
    ${KELPIE_SCRIPT_CODEC_SOURCES}
  )
  target_include_directories(kelpie_windows_script_media_test PRIVATE src)
  target_compile_definitions(kelpie_windows_script_media_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE
  )
  target_link_libraries(kelpie_windows_script_media_test PRIVATE
    ${KELPIE_SCRIPT_SYSTEM_LIBRARIES} psapi
  )
  kelpie_enable_test_assertions(kelpie_windows_script_media_test)
  if(MSVC)
    target_compile_options(kelpie_windows_script_media_test PRIVATE /W4 /WX)
  endif()
  add_test(NAME kelpie_windows_script_media_test
    COMMAND ${CMAKE_COMMAND}
      "-DTEST_EXECUTABLE=$<TARGET_FILE:kelpie_windows_script_media_test>"
      "-DARTIFACT_ROOT=${CMAKE_CURRENT_BINARY_DIR}/script-media-test-artifacts"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_script_media_test.cmake")
  add_executable(kelpie_windows_script_compositor_test
    tests/script_frame_compositor_test.cpp src/script_frame_compositor.cpp
  )
  target_include_directories(kelpie_windows_script_compositor_test PRIVATE src)
  target_compile_definitions(kelpie_windows_script_compositor_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE
  )
  target_link_libraries(kelpie_windows_script_compositor_test PRIVATE
    kelpie_core_automation nlohmann_json::nlohmann_json
    ole32 windowscodecs crypt32 gdiplus
  )
  kelpie_enable_test_assertions(kelpie_windows_script_compositor_test)
  add_test(NAME kelpie_windows_script_compositor_test COMMAND kelpie_windows_script_compositor_test)

  add_executable(kelpie_windows_script_media_prefix_test
    tests/script_media_prefix_test.cpp ${KELPIE_SCRIPT_CODEC_SOURCES})
  target_include_directories(kelpie_windows_script_media_prefix_test PRIVATE src)
  target_compile_definitions(kelpie_windows_script_media_prefix_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_link_libraries(kelpie_windows_script_media_prefix_test PRIVATE ${KELPIE_SCRIPT_SYSTEM_LIBRARIES})
  if(MSVC)
    target_compile_options(kelpie_windows_script_media_prefix_test PRIVATE /W4 /WX)
  endif()
  add_test(NAME kelpie_windows_script_media_prefix_test COMMAND ${CMAKE_COMMAND}
    "-DTEST_EXECUTABLE=$<TARGET_FILE:kelpie_windows_script_media_prefix_test>"
    "-DARTIFACT_ROOT=${CMAKE_CURRENT_BINARY_DIR}/script-media-prefix-artifacts"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_script_media_test.cmake")
endif()

if(BUILD_TESTING AND WIN32)
  add_executable(kelpie_windows_script_capture_file_identity_test
    tests/script_capture_file_identity_test.cpp src/script_artifact_store.cpp
    src/script_artifact_lifecycle.cpp src/script_native_overlay.cpp src/script_frame_compositor.cpp)
  target_include_directories(kelpie_windows_script_capture_file_identity_test PRIVATE src)
  target_compile_definitions(kelpie_windows_script_capture_file_identity_test PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_link_libraries(kelpie_windows_script_capture_file_identity_test PRIVATE
    kelpie_engine_chromium_desktop kelpie_core_automation nlohmann_json::nlohmann_json
    crypt32 advapi32 ole32 windowscodecs gdiplus)
  kelpie_enable_test_assertions(kelpie_windows_script_capture_file_identity_test)
  if(MSVC)
    target_compile_options(kelpie_windows_script_capture_file_identity_test PRIVATE /W4 /WX)
  endif()
  add_test(NAME kelpie_windows_script_capture_file_identity_test
    COMMAND kelpie_windows_script_capture_file_identity_test
      "${CMAKE_CURRENT_BINARY_DIR}/script-capture-file-identity-test")
endif()
