# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

find_package(Git QUIET)
if(Git_FOUND)
  # Get the commit hash corresponding to the current build.
  execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse --verify HEAD
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    OUTPUT_VARIABLE SWT_TESTING_LIBRARY_COMMIT_HASH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)

  # Check if there are local changes.
  execute_process(
    COMMAND ${GIT_EXECUTABLE} status -s
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    OUTPUT_VARIABLE SWT_TESTING_LIBRARY_COMMIT_MODIFIED
    OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

if(SWT_TESTING_LIBRARY_COMMIT_HASH)
  message(STATUS "Swift Testing commit hash: ${SWT_TESTING_LIBRARY_COMMIT_HASH}")
  add_compile_definitions(
    "$<$<COMPILE_LANGUAGE:CXX>:SWT_TESTING_LIBRARY_COMMIT_HASH=\"${SWT_TESTING_LIBRARY_COMMIT_HASH}\">")
  if(SWT_TESTING_LIBRARY_COMMIT_MODIFIED)
    add_compile_definitions(
      "$<$<COMPILE_LANGUAGE:CXX>:SWT_TESTING_LIBRARY_COMMIT_MODIFIED=1>")
  endif()
endif()
