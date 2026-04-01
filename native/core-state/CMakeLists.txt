add_library(mollotov_core_state STATIC
  src/bookmark_store.cpp
  src/history_store.cpp
  src/network_traffic_store.cpp
  src/console_store.cpp
  src/state_c_api.cpp
)

target_include_directories(mollotov_core_state
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(mollotov_core_state
  PUBLIC
    mollotov_core_protocol
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
