function(add_protocol_test name)
  add_executable(${name} ${ARGN})
  kelpie_enable_test_assertions(${name})
  target_link_libraries(${name} PRIVATE kelpie_core_protocol)
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_protocol_test(test_partition test_partition.cpp)
