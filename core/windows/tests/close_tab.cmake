  if(HAS_CEF)
    # Only the packaged executable can prove the invariant this guards: closing
    # a tab must not retire the loopback control surface. close-tab reports
    # success either way, so the assertion has to be a later request that the
    # running app actually answers.
    add_executable(close_tab_control_surface_test tests/close_tab_control_surface_test.cpp)
    target_compile_definitions(close_tab_control_surface_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
    target_link_libraries(close_tab_control_surface_test PRIVATE
      httplib::httplib nlohmann_json::nlohmann_json ws2_32 user32)
    add_test(NAME close_tab_control_surface_test
      COMMAND close_tab_control_surface_test "$<TARGET_FILE_DIR:kelpie>")
    set_tests_properties(close_tab_control_surface_test PROPERTIES TIMEOUT 300)
  endif()
