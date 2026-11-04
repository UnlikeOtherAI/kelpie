function(add_automation_test name)
  add_executable(${name} ${ARGN})
  kelpie_enable_test_assertions(${name})
  target_link_libraries(${name} PRIVATE kelpie_core_automation)
  add_test(NAME ${name} COMMAND ${name})
endfunction()

add_automation_test(test_response_helpers test_response_helpers.cpp)
add_automation_test(test_handler_context test_handler_context.cpp)


# Parity vectors are test-only. Reuse the existing shared build; never install/bootstrap here.
find_program(KELPIE_PRESENTATION_NODE NAMES node)
if(NOT KELPIE_PRESENTATION_NODE)
  message(FATAL_ERROR "Node.js is required for presentation parity test vectors")
endif()
set(KELPIE_PRESENTATION_VECTOR_FILE "${CMAKE_CURRENT_BINARY_DIR}/script-presentation-vectors.json")
set(KELPIE_PRESENTATION_VECTOR_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../../../scripts/native/generate-script-presentation.mjs")
add_executable(test_script_presentation test_script_presentation.cpp)
kelpie_enable_test_assertions(test_script_presentation)
target_link_libraries(test_script_presentation PRIVATE kelpie_core_automation)
add_test(NAME script_presentation_vectors
  COMMAND "${KELPIE_PRESENTATION_NODE}" "${KELPIE_PRESENTATION_VECTOR_SCRIPT}" "${KELPIE_PRESENTATION_VECTOR_FILE}")
set_tests_properties(script_presentation_vectors PROPERTIES FIXTURES_SETUP script_presentation_vectors)
add_test(NAME test_script_presentation COMMAND test_script_presentation "${KELPIE_PRESENTATION_VECTOR_FILE}")
set_tests_properties(test_script_presentation PROPERTIES FIXTURES_REQUIRED script_presentation_vectors)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${KELPIE_PRESENTATION_VECTOR_SCRIPT}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../packages/shared/src/script-presentation.ts")
