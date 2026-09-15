function(add_automation_test name)
  add_executable(${name} ${ARGN})
  kelpie_enable_test_assertions(${name})
  target_link_libraries(${name} PRIVATE kelpie_core_automation)
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_automation_test(test_response_helpers test_response_helpers.cpp)
add_automation_test(test_handler_context test_handler_context.cpp)

