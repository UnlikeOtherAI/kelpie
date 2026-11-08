# Stage runtime assets for a consumer of Kelpie::Browser. The SDK itself is a library.
function(kelpie_stage_browser_runtime target)
  if(NOT TARGET kelpie_engine_chromium_desktop)
    return()
  endif()
  get_target_property(output_dir ${target} RUNTIME_OUTPUT_DIRECTORY)
  if(NOT output_dir)
    get_target_property(output_dir ${target} BINARY_DIR)
  endif()
  # Consumers in one output directory share a single staging owner. Concurrent
  # DLL links must not overwrite the same locale files in parallel.
  string(SHA256 directory_hash "${output_dir}")
  string(SUBSTRING "${directory_hash}" 0 12 directory_hash)
  set(runtime_target "kelpie_browser_runtime_${directory_hash}")
  if(NOT TARGET ${runtime_target})
    file(GLOB runtime_files LIST_DIRECTORIES false
      "${CEF_ROOT}/Release/*.dll"
      "${CEF_ROOT}/Release/*.bin"
      "${CEF_ROOT}/Release/*.dat"
      "${CEF_ROOT}/Release/*.json"
      "${CEF_ROOT}/Resources/*.pak"
      "${CEF_ROOT}/Resources/*.dat"
    )
    set(copy_commands)
    foreach(runtime_file IN LISTS runtime_files)
      list(APPEND copy_commands COMMAND ${CMAKE_COMMAND} -E copy_if_different "${runtime_file}" "${output_dir}")
    endforeach()
    add_custom_target(${runtime_target}
      COMMAND ${CMAKE_COMMAND} -E make_directory "${output_dir}"
      ${copy_commands}
      COMMAND ${CMAKE_COMMAND} -E copy_directory "${CEF_ROOT}/Resources/locales" "${output_dir}/locales"
      COMMENT "Staging shared CEF runtime"
      VERBATIM
    )
  endif()
  add_dependencies(${target} ${runtime_target})
  get_target_property(consumer_type ${target} TYPE)
  if(consumer_type STREQUAL "SHARED_LIBRARY")
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CEF_ROOT}/Release/bootstrap.exe"
        "$<TARGET_FILE_DIR:${target}>/$<TARGET_FILE_BASE_NAME:${target}>.exe"
      COMMENT "Staging matching sandboxed CEF bootstrap for ${target}")
  endif()
endfunction()
