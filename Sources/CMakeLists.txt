# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

set(SwiftTesting_MACRO "<auto>" CACHE STRING
    "Path to SwiftTesting macro plugin, or '<auto>' for automatically building it")

if(SwiftTesting_MACRO STREQUAL "<auto>")
  # Macros must be built for the build machine, not the host.
  include(ExternalProject)
  if(NOT SwiftTesting_MACRO_MAKE_PROGRAM)
    set(SwiftTesting_MACRO_MAKE_PROGRAM ${CMAKE_MAKE_PROGRAM})
  endif()
  if(NOT SwiftTesting_MACRO_Swift_COMPILER)
    set(SwiftTesting_MACRO_Swift_COMPILER ${CMAKE_Swift_COMPILER})
  endif()
  if(NOT SwiftTesting_MACRO_Swift_FLAGS)
    set(SwiftTesting_MACRO_Swift_FLAGS ${CMAKE_Swift_FLAGS})
    set(SwiftTesting_MACRO_SWIFT_FLAGS_RELEASE ${CMAKE_Swift_FLAGS_RELEASE})
    set(SwiftTesting_MACRO_SWIFT_FLAGS_RELWITHDEBINFO ${CMAKE_Swift_FLAGS_RELWITHDEBINFO})
  endif()
  if(NOT SwiftTesting_MACRO_AR)
    set(SwiftTesting_MACRO_AR ${CMAKE_AR})
  endif()
  if(NOT SwiftTesting_MACRO_RANLIB)
    set(SwiftTesting_MACRO_RANLIB ${CMAKE_RANLIB})
  endif()
  if(NOT SwiftTesting_MACRO_BUILD_TYPE)
    set(SwiftTesting_MACRO_BUILD_TYPE ${CMAKE_BUILD_TYPE})
  endif()

  find_package(SwiftSyntax CONFIG GLOBAL)
  if(SwiftSyntax_FOUND)
    set(SwiftTesting_BuildMacrosAsExecutables NO)
  else()
    set(SwiftTesting_BuildMacrosAsExecutables YES)
  endif()

  # Build and install the plugin into the current build directry.
  set(SwiftTesting_MACRO_INSTALL_PREFIX "${CMAKE_BINARY_DIR}")

  ExternalProject_Add(TestingMacros
    PREFIX "tm"
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/TestingMacros"
    BUILD_ALWAYS ON
    CMAKE_ARGS
      -DCMAKE_MAKE_PROGRAM=${SwiftTesting_MACRO_MAKE_PROGRAM}
      -DCMAKE_Swift_COMPILER=${SwiftTesting_MACRO_Swift_COMPILER}
      -DCMAKE_Swift_FLAGS=${SwiftTesting_MACRO_Swift_FLAGS}
      -DCMAKE_Swift_FLAGS_RELEASE=${SwiftTesting_MACRO_Swift_FLAGS_RELEASE}
      -DCMAKE_Swift_FLAGS_RELWITHDEBINFO=${SwiftTesting_MACRO_Swift_FLAGS_RELWITHDEBINFO}
      -DCMAKE_AR=${SwiftTesting_MACRO_AR}
      -DCMAKE_RANLIB=${SwiftTesting_MACRO_RANLIB}
      -DCMAKE_BUILD_TYPE=${CSwiftTesting_MACRO_BUILD_TYPE}
      -DSwiftTesting_BuildMacrosAsExecutables=${SwiftTesting_BuildMacrosAsExecutables}
      -DSwiftSyntax_DIR=${SwiftSyntax_DIR}
      -DCMAKE_INSTALL_PREFIX=${SwiftTesting_MACRO_INSTALL_PREFIX})

  # Hardcode the known file names based on system name as a workaround since
  # TestingMacros uses `ExternalProject` and we cannot directly query the
  # properties of its targets here.
  if(NOT SwiftTesting_BuildMacrosAsExecutables)
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
      set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO_INSTALL_PREFIX}/lib/swift/host/plugins/testing/libTestingMacros.dylib")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
      set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO_INSTALL_PREFIX}/lib/swift/host/plugins/libTestingMacros.so")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
      set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO_INSTALL_PREFIX}/bin/TestingMacros.dll")
    else()
      message(FATAL_ERROR "Unable to determine the library name for TestingMacros based on system name: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()
  else()
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
      set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO_INSTALL_PREFIX}/bin/TestingMacros.exe")
    else()
      set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO_INSTALL_PREFIX}/bin/TestingMacros")
    endif()
  endif()
elseif(SwiftTesting_MACRO)
  # Use the passed-in plugin path.
  set(SwiftTesting_MACRO_PATH "${SwiftTesting_MACRO}")
  add_custom_target(TestingMacros DEPENDS "${SwiftTesting_MACRO_PATH}")
else()
  # If it's explicitly "NO", do not compile the library with macros.
  add_custom_target(TestingMacros)
endif()

if(NOT SwiftTesting_MACRO_PATH)
  message(STATUS "TestingMacros: (none)")
elseif(SwiftTesting_MACRO_PATH)
  if(SwiftTesting_MACRO_PATH MATCHES [[\.(dylib|so|dll)$]])
    message(STATUS "TestingMacros: ${SwiftTesting_MACRO_PATH} (shared library)")
    add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-load-plugin-library ${SwiftTesting_MACRO_PATH}>")
  else()
    message(STATUS "TestingMacros: ${SwiftTesting_MACRO_PATH} (executable)")
    add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:SHELL:-load-plugin-exectuable ${SwiftTesting_MACRO_PATH}#TestingMacros>")
  endif()
endif()

include(AvailabilityDefinitions)
include(CompilerSettings)
add_subdirectory(_TestingInternals)
add_subdirectory(Testing)
