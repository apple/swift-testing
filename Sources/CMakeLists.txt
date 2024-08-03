# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

# Macros must be built for the build machine, not the host.
include(ExternalProject)
if(NOT SwiftTesting_MACRO_MAKE_PROGRAM)
  set(SwiftTesting_MACRO_MAKE_PROGRAM ${CMAKE_MAKE_PROGRAM})
endif()
if(NOT SwiftTesting_MACRO_Swift_COMPILER)
  set(SwiftTesting_MACRO_Swift_COMPILER ${CMAKE_Swift_COMPILER})
endif()
if(NOT SwiftTesting_MACRO_AR)
  set(SwiftTesting_MACRO_AR ${CMAKE_AR})
endif()
if(NOT SwiftTesting_MACRO_RANLIB)
  set(SwiftTesting_MACRO_RANLIB ${CMAKE_RANLIB})
endif()

find_package(SwiftSyntax CONFIG GLOBAL)
if(SwiftSyntax_FOUND)
  set(SwiftTesting_BuildMacrosAsExecutables NO)
else()
  set(SwiftTesting_BuildMacrosAsExecutables YES)
endif()

ExternalProject_Add(TestingMacros
  PREFIX "tm"
  SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/TestingMacros"
  CMAKE_ARGS
    -DCMAKE_Swift_COMPILER=${SwiftTesting_MACRO_Swift_COMPILER}
    -DCMAKE_AR=${SwiftTesting_MACRO_AR}
    -DCMAKE_RANLIB=${SwiftTesting_MACRO_RANLIB}
    -DCMAKE_MAKE_PROGRAM=${SwiftTesting_MACRO_MAKE_PROGRAM}
    -DSwiftTesting_BuildMacrosAsExecutables=${SwiftTesting_BuildMacrosAsExecutables}
    -DSwiftSyntax_DIR=${SwiftSyntax_DIR}
    -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>)
ExternalProject_Get_Property(TestingMacros BINARY_DIR)
ExternalProject_Get_Property(TestingMacros INSTALL_DIR)

include(AvailabilityDefinitions)
include(CompilerSettings)
add_subdirectory(_TestingInternals)
add_subdirectory(Testing)

if(NOT SwiftTesting_BuildMacrosAsExecutables)
  # Hardcode the known library names based on system name as a workaround since
  # TestingMacros uses `ExternalProject` and we cannot directly query the
  # properties of its targets here.
  if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
    set(SwiftTesting_TestingMacrosLibraryName "libTestingMacros.dylib")
  elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux")
    set(SwiftTesting_TestingMacrosLibraryName "libTestingMacros.so")
  else()
    message(FATAL_ERROR "Unable to determine the library name for TestingMacros based on system name: ${CMAKE_SYSTEM_NAME}")
  endif()

  install(PROGRAMS "${INSTALL_DIR}/lib/${SwiftTesting_TestingMacrosLibraryName}"
    # TODO: Finalize the install path
    DESTINATION lib/swift/host/plugins)
endif()
