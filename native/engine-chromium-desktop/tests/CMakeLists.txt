function(add_desktop_engine_test name)
  add_executable(${name} ${ARGN})
  kelpie_enable_test_assertions(${name})
  target_compile_features(${name} PRIVATE cxx_std_20)
  target_link_libraries(${name} PRIVATE kelpie_engine_chromium_desktop)
  target_include_directories(${name} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
  )
  if(KELPIE_ENABLE_CHROMIUM_DESKTOP)
    target_include_directories(${name} PRIVATE ${CEF_ROOT})
    target_compile_definitions(${name} PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  endif()
  add_test(NAME ${name} COMMAND ${name})
  if(KELPIE_ENABLE_CHROMIUM_DESKTOP AND WIN32)
    set_tests_properties(${name} PROPERTIES
      ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${CEF_ROOT}/Release")
  endif()
endfunction()

add_desktop_engine_test(test_desktop_router test_desktop_router.cpp)
add_desktop_engine_test(test_desktop_mcp_server test_desktop_mcp_server.cpp)
add_desktop_engine_test(test_desktop_http_server test_desktop_http_server.cpp)
add_desktop_engine_test(test_desktop_handlers test_desktop_handlers.cpp)
add_desktop_engine_test(test_desktop_input_cookie test_desktop_input_cookie.cpp)
add_desktop_engine_test(test_favicon_registry test_favicon_registry.cpp)
add_desktop_engine_test(test_start_page test_start_page.cpp)
if(KELPIE_ENABLE_CHROMIUM_DESKTOP)
  add_desktop_engine_test(test_desktop_network_events test_desktop_network_events.cpp)
endif()

