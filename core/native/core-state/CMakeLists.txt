add_library(kelpie_core_state STATIC
  src/bookmark_store.cpp
  src/history_store.cpp
  src/network_traffic_store.cpp
  src/console_store.cpp
  src/state_c_api.cpp
)

target_include_directories(kelpie_core_state
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(kelpie_core_state
  PUBLIC
    kelpie_core_protocol
    nlohmann_json::nlohmann_json
)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
