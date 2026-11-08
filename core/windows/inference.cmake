set(WINDOWS_INFERENCE_SOURCES
  src/inference_transport.cpp
  src/inference_store.cpp
  src/inference_service.cpp
  src/inference_chat.cpp
  src/inference_view.cpp
)

function(add_windows_inference_tests)
  add_executable(inference_service_test tests/inference_service_test.cpp src/inference_service.cpp
    src/inference_chat.cpp src/inference_transport.cpp src/inference_store.cpp)
  target_include_directories(inference_service_test PRIVATE src)
  target_link_libraries(inference_service_test PRIVATE kelpie_core_ai kelpie_engine_chromium_desktop winhttp crypt32 ole32)
  kelpie_enable_test_assertions(inference_service_test)
  add_test(NAME inference_service_test COMMAND inference_service_test)
endfunction()
