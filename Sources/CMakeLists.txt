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
    -DCMAKE_MAKE_PROGRAM=${SwiftTesting_MACRO_MAKE_PROGRAM}
    -DSwiftTesting_BuildMacrosAsExecutables=${SwiftTesting_BuildMacrosAsExecutables}
    -DSwiftSyntax_DIR=${SwiftSyntax_DIR}
  INSTALL_COMMAND "")
ExternalProject_Get_Property(TestingMacros BINARY_DIR)

if(SwiftTesting_BuildMacrosAsExecutables)
  set(_TestingMacros_ExecutableSuffix "")
  if(CMAKE_HOST_WIN32)
    set(_TestingMacros_ExecutableSuffix ".exe")
  endif()

  set(SwiftTesting_MacroPluginFlags -load-plugin-executable "${BINARY_DIR}/TestingMacros${_TestingMacros_ExecutableSuffix}#TestingMacros")
else()
  set(SwiftTesting_MacroPluginFlags -plugin-path "${BINARY_DIR}")
endif()

include(AvailabilityDefinitions)
include(CompilerSettings)
add_subdirectory(_TestingInternals)
add_subdirectory(Testing)
