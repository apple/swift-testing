# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.19.6...3.29)

if(POLICY CMP0157)
  cmake_policy(SET CMP0157 NEW)
endif()

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
  # TODO: Update GIT_TAG to the 6.0 release tag once it is available.
  FetchContent_Declare(SwiftSyntax
    GIT_REPOSITORY https://github.com/swiftlang/swift-syntax
    GIT_TAG 27b74edd5de625d0e399869a5af08f1501af8837)
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
else()
  add_library(TestingMacros SHARED)

  # Install the macro plugin to the default location.
  #
  # This is not the plugin's actual, final install location -- it's only
  # relative to this external project's install dir. The final location is
  # determined by the "outer" project.
  install(TARGETS TestingMacros)
endif()

target_sources(TestingMacros PRIVATE
  ConditionMacro.swift
  SourceLocationMacro.swift
  SuiteDeclarationMacro.swift
  Support/Additions/DeclGroupSyntaxAdditions.swift
  Support/Additions/EditorPlaceholderExprSyntaxAdditions.swift
  Support/Additions/FunctionDeclSyntaxAdditions.swift
  Support/Additions/MacroExpansionContextAdditions.swift
  Support/Additions/TokenSyntaxAdditions.swift
  Support/Additions/TriviaPieceAdditions.swift
  Support/Additions/TypeSyntaxProtocolAdditions.swift
  Support/Additions/VersionTupleSyntaxAdditions.swift
  Support/Additions/WithAttributesSyntaxAdditions.swift
  Support/Argument.swift
  Support/AttributeDiscovery.swift
  Support/AvailabilityGuards.swift
  Support/CommentParsing.swift
  Support/ConditionArgumentParsing.swift
  Support/CRC32.swift
  Support/DiagnosticMessage.swift
  Support/DiagnosticMessage+Diagnosing.swift
  Support/SourceCodeCapturing.swift
  Support/SourceLocationGeneration.swift
  TagMacro.swift
  TestDeclarationMacro.swift
  TestingMacrosMain.swift)

target_link_libraries(TestingMacros PRIVATE
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::SwiftSyntaxMacroExpansion
  SwiftSyntax::SwiftSyntaxMacros)
if(SwiftTesting_BuildMacrosAsExecutables)
  # Link the 'SwiftCompilerPlugin' target, but only when built as an executable.
  target_link_libraries(TestingMacros PRIVATE
    SwiftSyntax::SwiftCompilerPlugin)
endif()
