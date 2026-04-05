add_library(kelpie_core_mcp STATIC
  src/mcp_tool.cpp
  src/mcp_registry.cpp
  src/mcp_c_api.cpp
)

target_include_directories(kelpie_core_mcp
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kelpie_core_mcp
  PUBLIC
    kelpie_core_protocol
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
