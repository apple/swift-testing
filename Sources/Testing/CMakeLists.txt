# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Testing
  ABI/EntryPoints/ABIEntryPoint.swift
  ABI/EntryPoints/EntryPoint.swift
  ABI/EntryPoints/SwiftPMEntryPoint.swift
  ABI/ABI.Record.swift
  ABI/ABI.Record+Streaming.swift
  ABI/ABI.swift
  ABI/Encoded/ABI.EncodedAttachment.swift
  ABI/Encoded/ABI.EncodedBacktrace.swift
  ABI/Encoded/ABI.EncodedError.swift
  ABI/Encoded/ABI.EncodedEvent.swift
  ABI/Encoded/ABI.EncodedInstant.swift
  ABI/Encoded/ABI.EncodedIssue.swift
  ABI/Encoded/ABI.EncodedMessage.swift
  ABI/Encoded/ABI.EncodedTest.swift
  Attachments/Images/_AttachableImageWrapper.swift
  Attachments/Images/AttachableImageFormat.swift
  Attachments/Images/ImageAttachmentError.swift
  Attachments/Attachable.swift
  Attachments/AttachableWrapper.swift
  Attachments/Attachment.swift
  Events/Clock.swift
  Events/Event.swift
  Events/Recorder/Event.AdvancedConsoleOutputRecorder.swift
  Events/Recorder/Event.ConsoleOutputRecorder.swift
  Events/Recorder/Event.HumanReadableOutputRecorder.swift
  Events/Recorder/Event.JUnitXMLRecorder.swift
  Events/Recorder/Event.Symbol.swift
  Events/TimeValue.swift
  ExitTests/ExitTest.swift
  ExitTests/ExitTest.CapturedValue.swift
  ExitTests/ExitTest.Condition.swift
  ExitTests/ExitTest.Result.swift
  ExitTests/SpawnProcess.swift
  ExitTests/ExitStatus.swift
  ExitTests/WaitFor.swift
  Expectations/Expectation.swift
  Expectations/Expectation+Macro.swift
  Expectations/ExpectationChecking+Macro.swift
  Issues/Confirmation.swift
  Issues/ErrorSnapshot.swift
  Issues/Issue.swift
  Issues/Issue+Recording.swift
  Issues/KnownIssue.swift
  Parameterization/CustomTestArgumentEncodable.swift
  Parameterization/Test.Case.Generator.swift
  Parameterization/Test.Case.ID.swift
  Parameterization/Test.Case.swift
  Parameterization/TypeInfo.swift
  Running/Configuration.swift
  Running/Configuration.TestFilter.swift
  Running/Configuration+EventHandling.swift
  Running/Runner.Plan.swift
  Running/Runner.Plan+Dumping.swift
  Running/Runner.RuntimeState.swift
  Running/Runner.swift
  Running/SkipInfo.swift
  SourceAttribution/Backtrace.swift
  SourceAttribution/Backtrace+Symbolication.swift
  SourceAttribution/CustomTestStringConvertible.swift
  SourceAttribution/Expression.swift
  SourceAttribution/Expression+Macro.swift
  SourceAttribution/SourceContext.swift
  SourceAttribution/SourceLocation.swift
  SourceAttribution/SourceLocation+Macro.swift
  Support/Additions/ArrayAdditions.swift
  Support/Additions/CollectionDifferenceAdditions.swift
  Support/Additions/CommandLineAdditions.swift
  Support/Additions/NumericAdditions.swift
  Support/Additions/ResultAdditions.swift
  Support/Additions/WinSDKAdditions.swift
  Support/CartesianProduct.swift
  Support/CError.swift
  Support/CustomIssueRepresentable.swift
  Support/Environment.swift
  Support/FileHandle.swift
  Support/GetSymbol.swift
  Support/Graph.swift
  Support/JSON.swift
  Support/Locked.swift
  Support/Locked+Platform.swift
  Support/VersionNumber.swift
  Support/Versions.swift
  Discovery+Macro.swift
  Test.ID.Selection.swift
  Test.ID.swift
  Test.swift
  Test+Discovery.swift
  Test+Discovery+Legacy.swift
  Test+Macro.swift
  Traits/Bug.swift
  Traits/Comment.swift
  Traits/Comment+Macro.swift
  Traits/ConditionTrait.swift
  Traits/ConditionTrait+Macro.swift
  Traits/HiddenTrait.swift
  Traits/IssueHandlingTrait.swift
  Traits/ParallelizationTrait.swift
  Traits/Tags/Tag.Color.swift
  Traits/Tags/Tag.Color+Loading.swift
  Traits/Tags/Tag.List.swift
  Traits/Tags/Tag.swift
  Traits/Tags/Tag+Macro.swift
  Traits/Tags/Tag+Predefined.swift
  Traits/TimeLimitTrait.swift
  Traits/Trait.swift)
target_link_libraries(Testing PRIVATE
  _TestDiscovery
  _TestingInternals)
if(NOT APPLE)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL WASI)
    target_link_libraries(Testing PUBLIC
      dispatch)
  endif()
  target_link_libraries(Testing PUBLIC
    Foundation)
  if (CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
    target_link_libraries(Testing PUBLIC execinfo)
  endif()
endif()
if(NOT BUILD_SHARED_LIBS)
  # When building a static library, tell clients to autolink the internal
  # libraries.
  target_compile_options(Testing PRIVATE
    "SHELL:-Xfrontend -public-autolink-library -Xfrontend _TestDiscovery"
    "SHELL:-Xfrontend -public-autolink-library -Xfrontend _TestingInternals")
endif()
add_dependencies(Testing
  TestingMacros)
target_compile_options(Testing PRIVATE
  -enable-library-evolution
  -emit-module-interface -emit-module-interface-path $<TARGET_PROPERTY:Testing,Swift_MODULE_DIRECTORY>/Testing.swiftinterface)

_swift_testing_install_target(Testing)

# Install the Swift cross-import overlay directory.
_swift_testing_install_swiftcrossimport(Testing
  Testing.swiftcrossimport)
