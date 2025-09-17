##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for Swift project authors
##

# Settings intended to be applied to every Swift target in this project.
# Analogous to project-level build settings in an Xcode project.
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-package-name org.swift.testing>")
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -require-explicit-sendable>")
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-experimental-feature -Xfrontend AccessLevelOnImport>")
add_compile_options(
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend ExistentialAny>"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend InternalImportsByDefault>"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend MemberImportVisibility>"
  "SHELL:$<$<COMPILE_LANGUAGE:Swift>:-Xfrontend -enable-upcoming-feature -Xfrontend InferIsolatedConformances>")

# Platform-specific definitions.
if(APPLE)
  add_compile_definitions("SWT_TARGET_OS_APPLE")
endif()
set(SWT_NO_EXIT_TESTS_LIST "iOS" "watchOS" "tvOS" "visionOS" "WASI" "Android")
if(CMAKE_SYSTEM_NAME IN_LIST SWT_NO_EXIT_TESTS_LIST)
  add_compile_definitions("SWT_NO_EXIT_TESTS")
endif()
set(SWT_NO_PROCESS_SPAWNING_LIST "iOS" "watchOS" "tvOS" "visionOS" "WASI" "Android")
if(CMAKE_SYSTEM_NAME IN_LIST SWT_NO_PROCESS_SPAWNING_LIST)
  add_compile_definitions("SWT_NO_PROCESS_SPAWNING")
endif()
if(NOT APPLE)
  add_compile_definitions("SWT_NO_SNAPSHOT_TYPES")
  add_compile_definitions("SWT_NO_FOUNDATION_FILE_COORDINATION")
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "WASI")
  add_compile_definitions("SWT_NO_DYNAMIC_LINKING")
  add_compile_definitions("SWT_NO_PIPES")
endif()

file(STRINGS "${SWT_SOURCE_ROOT_DIR}/VERSION.txt" SWT_TESTING_LIBRARY_VERSION LIMIT_COUNT 1)
if(SWT_TESTING_LIBRARY_VERSION)
  message(STATUS "Swift Testing version: ${SWT_TESTING_LIBRARY_VERSION}")
  add_compile_definitions("$<$<COMPILE_LANGUAGE:CXX>:SWT_TESTING_LIBRARY_VERSION=\"${SWT_TESTING_LIBRARY_VERSION}\">")
endif()
