add_executable(test_mcp_registry test_mcp_registry.cpp)
target_link_libraries(test_mcp_registry PRIVATE kelpie_core_mcp)
add_test(NAME test_mcp_registry COMMAND test_mcp_registry)

kelpie_enable_test_assertions(test_mcp_registry)

add_executable(test_browser_gateway test_browser_gateway.cpp)
target_include_directories(test_browser_gateway PRIVATE ../src "${CMAKE_CURRENT_BINARY_DIR}/../generated")
target_link_libraries(test_browser_gateway PRIVATE kelpie_core_mcp)
kelpie_enable_test_assertions(test_browser_gateway)
add_test(NAME test_browser_gateway COMMAND test_browser_gateway)

add_executable(test_native_extensions test_native_extensions.cpp)
target_include_directories(test_native_extensions PRIVATE ../src "${CMAKE_CURRENT_BINARY_DIR}/../generated")
target_link_libraries(test_native_extensions PRIVATE kelpie_core_mcp)
kelpie_enable_test_assertions(test_native_extensions)
add_test(NAME test_native_extensions COMMAND test_native_extensions)
