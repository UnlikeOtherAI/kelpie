function(add_store_test name)
  add_executable(${name} ${ARGN})
  kelpie_enable_test_assertions(${name})
  target_link_libraries(${name} PRIVATE kelpie_core_state)
  target_include_directories(${name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_store_test(test_bookmark_store test_bookmark_store.cpp)
add_store_test(test_history_store test_history_store.cpp)
add_store_test(test_history_store_extended test_history_store_extended.cpp)
add_store_test(test_network_traffic_store test_network_traffic_store.cpp)
add_store_test(test_console_store test_console_store.cpp)

