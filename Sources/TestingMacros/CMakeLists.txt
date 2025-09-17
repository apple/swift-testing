# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.19.6...3.29)

if(POLICY CMP0157)
  cmake_policy(SET CMP0157 NEW)
endif()

set(SWT_SOURCE_ROOT_DIR ${CMAKE_SOURCE_DIR}/../..)

project(TestingMacros
  LANGUAGES Swift)

list(APPEND CMAKE_MODULE_PATH
  ${CMAKE_SOURCE_DIR}/../../cmake/modules/shared)

if(WIN32)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

find_package(SwiftSyntax CONFIG GLOBAL)

if(SwiftTesting_BuildMacrosAsExecutables)
  # When building the macro plugin as an executable, clone and build
  # swift-syntax.
  include(FetchContent)
  set(FETCHCONTENT_BASE_DIR ${CMAKE_BINARY_DIR}/_d)
  FetchContent_Declare(SwiftSyntax
    GIT_REPOSITORY https://github.com/swiftlang/swift-syntax
    GIT_TAG 07bf225e198119c23b2b9a0a3432bdb534498873) # 603.0.0-prerelease-2025-08-11
  FetchContent_MakeAvailable(SwiftSyntax)
endif()

# Include these modules _after_ swift-syntax is declared above, but _before_ the
# macro plugin target is declared below, so that its settings are not applied to
# the former but are applied to the latter.
include(AvailabilityDefinitions)
include(CompilerSettings)

if(SwiftTesting_BuildMacrosAsExecutables)
  # When swift-syntax is built locally, the macro plugin must be built as an
  # executable.
  add_executable(TestingMacros)

  set_target_properties(TestingMacros PROPERTIES
    ENABLE_EXPORTS TRUE)

  # Parse the module as a library, even though it's an executable, because it
  # uses an `@main` type to define its entry point.
  target_compile_options(TestingMacros PRIVATE -parse-as-library)

  # Include the .swift file which contains its `@main` entry point type.
  target_compile_definitions(TestingMacros PRIVATE SWT_NO_LIBRARY_MACRO_PLUGINS)

  install(TARGETS TestingMacros
    RUNTIME DESTINATION bin)
else()
  add_library(TestingMacros SHARED)

  target_link_options(TestingMacros PRIVATE "-no-toolchain-stdlib-rpath")
  set_property(TARGET TestingMacros PROPERTY BUILD_WITH_INSTALL_RPATH YES)

  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(plugin_destination_dir "lib/swift/host/plugins/testing")
    set_property(TARGET TestingMacros PROPERTY INSTALL_RPATH)
  else()
    set(plugin_destination_dir "lib/swift/host/plugins")
    # RPATH 'lib/swift/{system}' and 'lib/swift/host'
    set_property(TARGET TestingMacros PROPERTY
      INSTALL_RPATH "$ORIGIN/../../$<LOWER_CASE:${CMAKE_SYSTEM_NAME}>;$ORIGIN/..")
  endif()

  install(TARGETS TestingMacros
    LIBRARY DESTINATION "${plugin_destination_dir}"
    RUNTIME DESTINATION bin)
endif()

target_sources(TestingMacros PRIVATE
  ConditionMacro.swift
  ExitTestCapturedValueMacro.swift
  PragmaMacro.swift
  SourceLocationMacro.swift
  SuiteDeclarationMacro.swift
  Support/Additions/DeclGroupSyntaxAdditions.swift
  Support/Additions/EditorPlaceholderExprSyntaxAdditions.swift
  Support/Additions/FunctionDeclSyntaxAdditions.swift
  Support/Additions/IntegerLiteralExprSyntaxAdditions.swift
  Support/Additions/MacroExpansionContextAdditions.swift
  Support/Additions/TokenSyntaxAdditions.swift
  Support/Additions/TriviaPieceAdditions.swift
  Support/Additions/TypeSyntaxProtocolAdditions.swift
  Support/Additions/VersionTupleSyntaxAdditions.swift
  Support/Additions/WithAttributesSyntaxAdditions.swift
  Support/Argument.swift
  Support/AttributeDiscovery.swift
  Support/AvailabilityGuards.swift
  Support/ClosureCaptureListParsing.swift
  Support/CommentParsing.swift
  Support/ConditionArgumentParsing.swift
  Support/DiagnosticMessage.swift
  Support/DiagnosticMessage+Diagnosing.swift
  Support/EffectfulExpressionHandling.swift
  Support/SHA256.swift
  Support/SourceCodeCapturing.swift
  Support/SourceLocationGeneration.swift
  Support/TestContentGeneration.swift
  TagMacro.swift
  TestDeclarationMacro.swift
  TestingMacrosMain.swift)

target_compile_options(TestingMacros PRIVATE
  "SHELL:-Xfrontend -disable-implicit-string-processing-module-import")

target_link_libraries(TestingMacros PRIVATE
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::SwiftSyntaxMacroExpansion
  SwiftSyntax::SwiftSyntaxMacros)
if(SwiftTesting_BuildMacrosAsExecutables)
  # Link the 'SwiftCompilerPlugin' target, but only when built as an executable.
  target_link_libraries(TestingMacros PRIVATE
    SwiftSyntax::SwiftCompilerPlugin)
endif()
