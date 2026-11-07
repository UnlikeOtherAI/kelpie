add_library(kelpie_core_automation STATIC
  src/automation_c_api.cpp
  src/handler_context.cpp
  src/response_helpers.cpp
)

target_include_directories(kelpie_core_automation
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kelpie_core_automation
  PUBLIC
    kelpie_core_protocol
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
