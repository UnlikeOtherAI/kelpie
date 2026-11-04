if(NOT TEST_EXECUTABLE OR NOT ARTIFACT_ROOT)
  message(FATAL_ERROR "Encoder test executable and artifact root are required")
endif()
# Preserve real decoded media for inspection; every invocation owns a fresh directory.
string(RANDOM LENGTH 24 ALPHABET 0123456789abcdef run_id)
execute_process(COMMAND "${TEST_EXECUTABLE}" "${ARTIFACT_ROOT}/${run_id}"
  RESULT_VARIABLE result)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Native media encode/decode test failed: ${result}")
endif()
