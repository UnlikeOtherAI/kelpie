add_library(kelpie_core_state STATIC
  src/bookmark_store.cpp
  src/history_store.cpp
  src/network_traffic_store.cpp
  src/console_store.cpp
  src/state_c_api.cpp
  src/peer_address.cpp
  src/peer_trust.cpp
  src/peer_trust_c_api.cpp
  src/peer_approval.cpp
)

if(WIN32)
  target_link_libraries(kelpie_core_state PUBLIC ws2_32 bcrypt)
endif()

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
