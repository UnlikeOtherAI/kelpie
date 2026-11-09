add_library(kelpie_desktop_sync STATIC
  src/sync_channel.cpp
  src/sync_client.cpp
  src/sync_connection_guard.cpp
  src/sync_crypto_hkdf.cpp
  src/sync_listener.cpp
  src/sync_net.cpp
  src/sync_peer_events.cpp
  src/sync_protocol.cpp
  src/sync_service.cpp
  src/sync_service_initiator.cpp
  src/sync_service_peers.cpp
  src/sync_service_responder.cpp
  src/sync_store_host.cpp)
target_compile_features(kelpie_desktop_sync PUBLIC cxx_std_20)
target_include_directories(kelpie_desktop_sync
  PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src" "${CMAKE_CURRENT_SOURCE_DIR}/../core-sync/src")
target_link_libraries(kelpie_desktop_sync
  PUBLIC kelpie_desktop_account nlohmann_json::nlohmann_json
  PRIVATE kelpie_core_sync httplib::httplib)
if(WIN32)
  target_sources(kelpie_desktop_sync PRIVATE src/sync_crypto_cng.cpp src/sync_net_windows.cpp)
  target_compile_definitions(kelpie_desktop_sync PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
  target_link_libraries(kelpie_desktop_sync PRIVATE bcrypt iphlpapi ws2_32)
else()
  find_package(OpenSSL 3.0 REQUIRED)
  target_sources(kelpie_desktop_sync PRIVATE src/sync_crypto_openssl.cpp src/sync_net_posix.cpp)
  target_link_libraries(kelpie_desktop_sync PRIVATE OpenSSL::Crypto)
endif()

if(BUILD_TESTING)
  foreach(test sync_crypto_test sync_net_test sync_protocol_test sync_listener_test sync_service_test)
    add_executable(${test} tests/${test}.cpp)
    target_include_directories(${test} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
      "${CMAKE_CURRENT_SOURCE_DIR}/../core-sync/src")
    target_link_libraries(${test} PRIVATE kelpie_desktop_sync kelpie_core_sync httplib::httplib)
    if(MSVC)
      target_compile_options(${test} PRIVATE /UNDEBUG)
      target_compile_definitions(${test} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    else()
      target_compile_options(${test} PRIVATE -UNDEBUG)
    endif()
    add_test(NAME ${test} COMMAND ${test})
    set_tests_properties(${test} PROPERTIES TIMEOUT 120)
  endforeach()
  target_compile_definitions(sync_crypto_test PRIVATE
    KELPIE_SYNC_VECTORS="${CMAKE_CURRENT_SOURCE_DIR}/../core-sync/tests/vectors/handshake-v1.json")
endif()
