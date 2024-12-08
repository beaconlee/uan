include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(uan_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(uan_setup_options)
  option(uan_ENABLE_HARDENING "Enable hardening" ON)
  option(uan_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    uan_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    uan_ENABLE_HARDENING
    OFF)

  uan_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR uan_PACKAGING_MAINTAINER_MODE)
    option(uan_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(uan_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(uan_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(uan_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(uan_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(uan_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(uan_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(uan_ENABLE_PCH "Enable precompiled headers" OFF)
    option(uan_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(uan_ENABLE_IPO "Enable IPO/LTO" ON)
    option(uan_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(uan_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(uan_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(uan_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(uan_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(uan_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(uan_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(uan_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(uan_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(uan_ENABLE_PCH "Enable precompiled headers" OFF)
    option(uan_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      uan_ENABLE_IPO
      uan_WARNINGS_AS_ERRORS
      uan_ENABLE_USER_LINKER
      uan_ENABLE_SANITIZER_ADDRESS
      uan_ENABLE_SANITIZER_LEAK
      uan_ENABLE_SANITIZER_UNDEFINED
      uan_ENABLE_SANITIZER_THREAD
      uan_ENABLE_SANITIZER_MEMORY
      uan_ENABLE_UNITY_BUILD
      uan_ENABLE_CLANG_TIDY
      uan_ENABLE_CPPCHECK
      uan_ENABLE_COVERAGE
      uan_ENABLE_PCH
      uan_ENABLE_CACHE)
  endif()

  uan_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (uan_ENABLE_SANITIZER_ADDRESS OR uan_ENABLE_SANITIZER_THREAD OR uan_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(uan_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(uan_global_options)
  if(uan_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    uan_enable_ipo()
  endif()

  uan_supports_sanitizers()

  if(uan_ENABLE_HARDENING AND uan_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR uan_ENABLE_SANITIZER_UNDEFINED
       OR uan_ENABLE_SANITIZER_ADDRESS
       OR uan_ENABLE_SANITIZER_THREAD
       OR uan_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${uan_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${uan_ENABLE_SANITIZER_UNDEFINED}")
    uan_enable_hardening(uan_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(uan_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(uan_warnings INTERFACE)
  add_library(uan_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  uan_set_project_warnings(
    uan_warnings
    ${uan_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(uan_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    uan_configure_linker(uan_options)
  endif()

  include(cmake/Sanitizers.cmake)
  uan_enable_sanitizers(
    uan_options
    ${uan_ENABLE_SANITIZER_ADDRESS}
    ${uan_ENABLE_SANITIZER_LEAK}
    ${uan_ENABLE_SANITIZER_UNDEFINED}
    ${uan_ENABLE_SANITIZER_THREAD}
    ${uan_ENABLE_SANITIZER_MEMORY})

  set_target_properties(uan_options PROPERTIES UNITY_BUILD ${uan_ENABLE_UNITY_BUILD})

  if(uan_ENABLE_PCH)
    target_precompile_headers(
      uan_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(uan_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    uan_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(uan_ENABLE_CLANG_TIDY)
    uan_enable_clang_tidy(uan_options ${uan_WARNINGS_AS_ERRORS})
  endif()

  if(uan_ENABLE_CPPCHECK)
    uan_enable_cppcheck(${uan_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(uan_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    uan_enable_coverage(uan_options)
  endif()

  if(uan_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(uan_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(uan_ENABLE_HARDENING AND NOT uan_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR uan_ENABLE_SANITIZER_UNDEFINED
       OR uan_ENABLE_SANITIZER_ADDRESS
       OR uan_ENABLE_SANITIZER_THREAD
       OR uan_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    uan_enable_hardening(uan_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
