# Packaging consumes exactly the files staged from this SDK. CEF can add or
# retire runtime libraries between releases; Kelpie must not keep a second list.
function(kelpie_stage_cef_runtime target cef_root)
  file(GLOB runtime_sources CONFIGURE_DEPENDS
    "${cef_root}/Release/*"
    "${cef_root}/Resources/*"
  )
  if(NOT EXISTS "${cef_root}/Release/libcef.so" OR
     NOT EXISTS "${cef_root}/Release/chrome-sandbox" OR NOT runtime_sources)
    message(FATAL_ERROR "A complete Linux CEF runtime is required")
  endif()

  set(runtime_names "")
  set(runtime_manifest "")
  foreach(source IN LISTS runtime_sources)
    get_filename_component(name "${source}" NAME)
    if(NOT name MATCHES "^[A-Za-z0-9_][A-Za-z0-9_.-]*$" OR name IN_LIST runtime_names)
      message(FATAL_ERROR "Invalid or duplicate CEF runtime name: ${name}")
    endif()
    list(APPEND runtime_names "${name}")
    string(APPEND runtime_manifest "${name}\n")
    if(IS_DIRECTORY "${source}")
      set(copy_command copy_directory)
    else()
      set(copy_command copy_if_different)
    endif()
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E ${copy_command}
        "${source}" "$<TARGET_FILE_DIR:${target}>/${name}"
      VERBATIM
    )
  endforeach()
  file(GENERATE OUTPUT "$<TARGET_FILE_DIR:${target}>/cef-runtime-files.txt"
    CONTENT "${runtime_manifest}")
endfunction()
