# Stage runtime assets for a consumer of Kelpie::Browser. The SDK itself is a library.
function(kelpie_stage_browser_runtime target)
  if(NOT TARGET kelpie_engine_chromium_desktop)
    return()
  endif()
  file(GLOB runtime_files LIST_DIRECTORIES false
    "${CEF_ROOT}/Release/*.dll"
    "${CEF_ROOT}/Release/*.bin"
    "${CEF_ROOT}/Release/*.dat"
    "${CEF_ROOT}/Release/*.json"
    "${CEF_ROOT}/Resources/*.pak"
    "${CEF_ROOT}/Resources/*.dat"
  )
  foreach(runtime_file IN LISTS runtime_files)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${runtime_file}" "$<TARGET_FILE_DIR:${target}>")
  endforeach()
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CEF_ROOT}/Resources/locales" "$<TARGET_FILE_DIR:${target}>/locales")
  get_target_property(consumer_type ${target} TYPE)
  if(consumer_type STREQUAL "SHARED_LIBRARY")
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CEF_ROOT}/Release/bootstrap.exe"
        "$<TARGET_FILE_DIR:${target}>/$<TARGET_FILE_BASE_NAME:${target}>.exe"
      COMMENT "Staging matching sandboxed CEF bootstrap for ${target}")
  endif()
endfunction()
