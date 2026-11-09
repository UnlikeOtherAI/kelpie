# Shared verification avoids different computer identities on different platforms.
enable_language(C)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
FetchContent_Declare(kelpie_ed25519
  URL https://codeload.github.com/orlp/ed25519/tar.gz/b1f19fab4aebe607805620d25a5e42566ce46a0e
  URL_HASH SHA256=aedb26c46d3dc3b721ab37c5248d5c923142e4d56009a9605c470383f32ce77a
)
FetchContent_MakeAvailable(kelpie_ed25519)
add_library(kelpie_core_state STATIC
  src/computer_signature.cpp
  src/bookmark_store.cpp
  src/history_store.cpp
  src/network_traffic_store.cpp
  src/console_store.cpp
  src/state_c_api.cpp
  src/peer_address.cpp
  src/peer_trust.cpp
  src/peer_trust_c_api.cpp
  src/peer_approval.cpp
  ${kelpie_ed25519_SOURCE_DIR}/src/fe.c
  ${kelpie_ed25519_SOURCE_DIR}/src/ge.c
  ${kelpie_ed25519_SOURCE_DIR}/src/sc.c
  ${kelpie_ed25519_SOURCE_DIR}/src/sha512.c
  ${kelpie_ed25519_SOURCE_DIR}/src/verify.c
  ${kelpie_ed25519_SOURCE_DIR}/src/sign.c
  ${kelpie_ed25519_SOURCE_DIR}/src/keypair.c
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

target_include_directories(kelpie_core_state PRIVATE ${kelpie_ed25519_SOURCE_DIR}/src)
