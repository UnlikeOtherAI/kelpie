# The TS package is the authoritative source. Bootstrap explicitly; never consume stale ignored dist.
get_filename_component(KELPIE_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
find_program(KELPIE_NODE_EXECUTABLE NAMES node REQUIRED)
find_program(KELPIE_PNPM_EXECUTABLE NAMES pnpm.cmd pnpm REQUIRED)
set(KELPIE_BROWSER_HEADER "${CMAKE_CURRENT_BINARY_DIR}/generated/browser_contract.h")
file(LOCK "${KELPIE_REPO_ROOT}/.build-browser-contract.lock" TIMEOUT 300)
execute_process(COMMAND "${KELPIE_PNPM_EXECUTABLE}" install --frozen-lockfile
  WORKING_DIRECTORY "${KELPIE_REPO_ROOT}" RESULT_VARIABLE install_status)
if(NOT install_status EQUAL 0)
  message(FATAL_ERROR "Browser contract dependencies failed to install (Node 20+ and pnpm required).")
endif()
function(kelpie_generate_browser_contract)
  execute_process(COMMAND "${KELPIE_PNPM_EXECUTABLE}" --filter @unlikeotherai/kelpie-shared build
    WORKING_DIRECTORY "${KELPIE_REPO_ROOT}" RESULT_VARIABLE build_status)
  if(NOT build_status EQUAL 0)
    message(FATAL_ERROR "Authoritative browser contract TypeScript build failed.")
  endif()
  execute_process(COMMAND "${KELPIE_NODE_EXECUTABLE}" "${KELPIE_REPO_ROOT}/scripts/native/generate-browser-contract.mjs" "${KELPIE_BROWSER_HEADER}"
    RESULT_VARIABLE generator_status)
  if(NOT generator_status EQUAL 0)
    message(FATAL_ERROR "Browser contract generation failed.")
  endif()
endfunction()
kelpie_generate_browser_contract()
file(LOCK "${KELPIE_REPO_ROOT}/.build-browser-contract.lock" RELEASE)
file(GLOB browser_sources CONFIGURE_DEPENDS "${KELPIE_REPO_ROOT}/packages/shared/src/browser-control/*.ts"
  "${KELPIE_REPO_ROOT}/packages/shared/src/extension*-tools.ts")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${browser_sources}
  "${KELPIE_REPO_ROOT}/packages/shared/package.json" "${KELPIE_REPO_ROOT}/packages/shared/scripts/build.mjs"
  "${KELPIE_REPO_ROOT}/pnpm-lock.yaml" "${KELPIE_REPO_ROOT}/scripts/native/generate-browser-contract.mjs")
