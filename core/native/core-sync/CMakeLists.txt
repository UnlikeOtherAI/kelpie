add_library(kelpie_core_sync STATIC
  src/base64url.cpp
  src/cookie.cpp
  src/protocol.cpp
  src/sha256.cpp
  src/sync_c_api.cpp
  src/sync_entry.cpp
  src/sync_feed.cpp
  src/sync_merge.cpp
  src/sync_rebase.cpp
  src/sync_scan.cpp
  src/sync_store.cpp
)

target_include_directories(kelpie_core_sync
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(kelpie_core_sync
  PUBLIC
    nlohmann_json::nlohmann_json
)

set_target_properties(kelpie_core_sync PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
