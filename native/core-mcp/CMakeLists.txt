include(browser_contract.cmake)

add_library(kelpie_core_mcp STATIC
  src/mcp_tool.cpp
  src/mcp_registry.cpp
  src/mcp_c_api.cpp
  src/browser_schema.cpp
  src/browser_gateway.cpp
  src/browser_gateway_c_api.cpp
  src/browser_mcp.cpp
  src/native_extension_schema.cpp
)

target_include_directories(kelpie_core_mcp
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_include_directories(kelpie_core_mcp PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")

target_link_libraries(kelpie_core_mcp
  PUBLIC
    kelpie_core_protocol
    kelpie_core_automation
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()

if(MSVC)
  target_compile_options(kelpie_core_mcp PRIVATE /utf-8)
endif()
