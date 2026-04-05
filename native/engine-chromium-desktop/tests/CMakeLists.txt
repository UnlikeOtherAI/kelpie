function(add_desktop_engine_test name)
  add_executable(${name} ${ARGN})
  target_link_libraries(${name} PRIVATE kelpie_engine_chromium_desktop)
  target_include_directories(${name} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
  )
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_desktop_engine_test(test_desktop_router test_desktop_router.cpp)
add_desktop_engine_test(test_desktop_mcp_server test_desktop_mcp_server.cpp)
add_desktop_engine_test(test_desktop_handlers test_desktop_handlers.cpp)
